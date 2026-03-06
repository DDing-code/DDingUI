local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

-- ============================================================
-- SPEC PROFILES - Per-specialization full-profile snapshot
--
-- ONE AceDB profile; each spec's settings stored in db.char.specData[specID].
-- On spec change: save entire db.profile → load new spec's snapshot.
-- No per-module toggles; everything switches together.
-- ============================================================

DDingUI.SpecProfiles = {}
local SP = DDingUI.SpecProfiles

-- ============================================================
-- HELPERS
-- ============================================================

local function GetCurrentSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    return GetSpecializationInfo(specIndex)
end

local function DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = type(v) == "table" and DeepCopy(v) or v
    end
    return copy
end

-- FullSnapshot: captures ALL values including AceDB metatable defaults
-- (pairs() only returns explicitly stored keys; defaults come via __index)
local function FullSnapshot(settings, defaults)
    local snapshot = {}
    for k, v in pairs(settings) do
        if type(v) == "table" then
            local subDef = defaults and type(defaults[k]) == "table" and defaults[k] or nil
            snapshot[k] = FullSnapshot(v, subDef)
        else
            snapshot[k] = v
        end
    end
    if defaults then
        for k, v in pairs(defaults) do
            if snapshot[k] == nil then
                snapshot[k] = type(v) == "table" and DeepCopy(v) or v
            end
        end
    end
    return snapshot
end

-- ApplySnapshot: overwrites dest in-place (preserves AceDB table/metatable)
local function ApplySnapshot(dest, source)
    for k in pairs(dest) do
        if source[k] == nil then dest[k] = nil end
    end
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(dest[k]) == "table" then
                ApplySnapshot(dest[k], v)
            else
                dest[k] = DeepCopy(v)
            end
        else
            dest[k] = v
        end
    end
end

-- ============================================================
-- SAVE / LOAD entire profile per spec
-- ============================================================

SP.lastSpecID = nil

function SP:SaveCurrentSpec()
    local specID = self.lastSpecID or GetCurrentSpecID()
    if not specID then return end
    if not DDingUI.db then return end

    if not DDingUI.db.char.specData then
        DDingUI.db.char.specData = {}
    end

    local defaults = DDingUI.defaults and DDingUI.defaults.profile
    DDingUI.db.char.specData[specID] = FullSnapshot(DDingUI.db.profile, defaults)
end

function SP:LoadSpec(specID)
    if not specID then return false end
    if not DDingUI.db then return false end
    if not DDingUI.db.char.specData then return false end

    local snapshot = DDingUI.db.char.specData[specID]
    if not snapshot then return false end

    -- Enrich with current defaults (forward compatibility for new keys)
    local defaults = DDingUI.defaults and DDingUI.defaults.profile
    if defaults then
        snapshot = FullSnapshot(snapshot, defaults)
    end

    ApplySnapshot(DDingUI.db.profile, snapshot)
    return true
end

-- ============================================================
-- SPEC CHANGE HANDLING
-- ============================================================

function SP:OnSpecChanged(newSpecID)
    if not DDingUI.db then return end

    -- Cancel any pending MarkDirty timer to prevent it from
    -- firing AFTER lastSpecID changes (would overwrite new spec's snapshot)
    if self._saveTimer then
        self._saveTimer:Cancel()
        self._saveTimer = nil
    end

    -- Save old spec BEFORE loading new
    if self.lastSpecID and self.lastSpecID ~= newSpecID then
        self:SaveCurrentSpec()
    end

    -- Load new spec (or save initial snapshot if first visit)
    local loaded = self:LoadSpec(newSpecID)
    self.lastSpecID = newSpecID

    if not loaded then
        -- First visit to this spec: save current profile as initial snapshot
        self:SaveCurrentSpec()
    end

    C_Timer.After(0.1, function()
        if DDingUI.RefreshAll then
            DDingUI:RefreshAll()
        end
    end)
end

-- ============================================================
-- DEBOUNCED SAVE (called by config option changes)
-- ============================================================

SP._saveTimer = nil

function SP:MarkDirty()
    if self._saveTimer then
        self._saveTimer:Cancel()
    end
    self._saveTimer = C_Timer.NewTimer(2, function()
        SP:SaveCurrentSpec()
        SP._saveTimer = nil
    end)
end

-- ============================================================
-- MIGRATION
-- ============================================================

local SPEC_DATA_VERSION = 2  -- v2 = full-profile snapshots

local function MigrateSpecData()
    if not DDingUI.db or not DDingUI.db.char then return end

    local charDB = DDingUI.db.char
    local ver = charDB.specDataVersion or 0

    if ver < SPEC_DATA_VERSION then
        -- Wipe old per-module format specData (incompatible with full-profile snapshots)
        charDB.specData = {}
        charDB.specDataVersion = SPEC_DATA_VERSION
    end
end

-- ============================================================
-- INITIALIZE
-- ============================================================

function SP:Initialize()
    -- LibDualSpec handles full-profile switching via separate AceDB profiles.
    -- Per-spec snapshots within one profile are unnecessary in that case.
    if DDingUI.db and DDingUI.db.IsDualSpecEnabled and DDingUI.db:IsDualSpecEnabled() then
        return
    end

    -- Check if per-spec snapshots are enabled (default: true)
    if DDingUI.db and DDingUI.db.char and DDingUI.db.char.specProfilesEnabled == false then
        return
    end

    -- Migrate old per-module specData → wipe and start fresh
    MigrateSpecData()

    self.lastSpecID = GetCurrentSpecID()

    if not self.eventFrame then
        self.eventFrame = CreateFrame("Frame")
        self.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        self.eventFrame:RegisterEvent("PLAYER_LOGOUT")
        self.eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
        self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        self.eventFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
            if event == "PLAYER_SPECIALIZATION_CHANGED" then
                local newSpecID = GetCurrentSpecID()
                if newSpecID then
                    SP:OnSpecChanged(newSpecID)
                end
            elseif event == "PLAYER_ENTERING_WORLD" then
                -- arg1=isInitialLogin, arg2=isReloadingUI
                -- 존 이동(인스턴스 등)마다 스냅샷을 덮어씌우면 설정이 날아감
                -- 최초 로그인 또는 UI 리로드 시에만 로드
                if arg1 or arg2 then
                    local specID = GetCurrentSpecID()
                    if specID then
                        SP.lastSpecID = specID
                        if SP:LoadSpec(specID) then
                            C_Timer.After(0.2, function()
                                if DDingUI.RefreshAll then
                                    DDingUI:RefreshAll()
                                end
                            end)
                        end
                    end
                end
            elseif event == "PLAYER_LOGOUT" or event == "PLAYER_LEAVING_WORLD" then
                -- 저장 대기 중인 타이머 즉시 실행
                if SP._saveTimer then
                    SP._saveTimer:Cancel()
                    SP._saveTimer = nil
                end
                SP:SaveCurrentSpec()
            end
        end)
    end

    -- Save initial snapshot for current spec if none exists yet
    local specID = GetCurrentSpecID()
    if specID and DDingUI.db and DDingUI.db.char then
        if not DDingUI.db.char.specData then
            DDingUI.db.char.specData = {}
        end
        if not DDingUI.db.char.specData[specID] then
            self:SaveCurrentSpec()
        end
    end
end

-- ============================================================
-- MODULE-LEVEL IMPORT from another spec snapshot
-- ============================================================

-- 모듈 키 → 표시 이름
SP.MODULE_KEYS = {
    { key = "buffTrackerBar",  name = "강화효과 바" },
    { key = "castBar",         name = "시전바 (플레이어)" },
    { key = "targetCastBar",   name = "시전바 (대상)" },
    { key = "dynamicIcons",    name = "동적 아이콘" },
    { key = "viewers",         name = "쿨다운 뷰어 설정" },
    { key = "primaryPowerBar", name = "주 자원바" },
    { key = "secondaryPowerBar", name = "보조 자원바" },
    { key = "buffBarViewer",   name = "강화효과 바 뷰어" },
    { key = "missingAlerts",   name = "미적용 알림" },
    { key = "buffDebuffFrames", name = "버프/디버프 프레임" },
    { key = "iconCustomization", name = "아이콘 커스터마이징" },
}

function SP:GetAvailableSpecs()
    local result = {}
    if not DDingUI.db or not DDingUI.db.char or not DDingUI.db.char.specData then
        return result
    end
    for specID, _ in pairs(DDingUI.db.char.specData) do
        result[specID] = specID
    end
    return result
end

function SP:GetSpecName(specID)
    if not specID then return "?" end
    -- 현재 클래스 전문화 먼저 시도
    local numSpecs = GetNumSpecializations()
    for i = 1, numSpecs do
        local id, name = GetSpecializationInfo(i)
        if id == specID then
            return name
        end
    end
    -- 다른 클래스 전문화: GetSpecializationInfoByID 사용
    if GetSpecializationInfoByID then
        local _, sName, _, _, _, _, className = GetSpecializationInfoByID(specID)
        if sName then
            return (className and (className .. " - ") or "") .. sName
        end
    end
    return "전문화 " .. specID
end

-- 전체 캐릭터의 저장된 전문화 목록 (크로스캐릭터 지원)
function SP:GetAllSavedSpecs()
    local result = {}
    if not DDingUI.db or not DDingUI.db.sv or not DDingUI.db.sv.char then
        return result
    end

    -- 현재 캐릭터 키
    local playerName = UnitName("player")
    local realmName = GetRealmName()
    local currentCharKey = playerName and realmName and (playerName .. " - " .. realmName) or nil
    local currentSpecID = self.lastSpecID

    for charKey, charData in pairs(DDingUI.db.sv.char) do
        if type(charData) == "table" and charData.specData and type(charData.specData) == "table" then
            for specID, _ in pairs(charData.specData) do
                -- 현재 캐릭터의 현재 전문화는 제외
                if not (charKey == currentCharKey and specID == currentSpecID) then
                    local compositeKey = charKey .. "::" .. specID

                    -- 직업-전문화 형식
                    local specLabel = "전문화 " .. specID
                    if GetSpecializationInfoByID then
                        local _, sName, _, _, _, _, className = GetSpecializationInfoByID(specID)
                        if sName and className then
                            specLabel = className .. "-" .. sName
                        elseif sName then
                            specLabel = sName
                        end
                    end

                    result[compositeKey] = specLabel
                end
            end
        end
    end

    return result
end

-- 크로스캐릭터 모듈 복사
function SP:CopyModulesFromCharSpec(charKey, specID, moduleKeys)
    if not charKey or not specID or not moduleKeys or #moduleKeys == 0 then return false end
    if not DDingUI.db or not DDingUI.db.sv or not DDingUI.db.sv.char then return false end

    local charData = DDingUI.db.sv.char[charKey]
    if not charData or not charData.specData then return false end

    local snapshot = charData.specData[specID]
    if not snapshot then return false end

    for _, moduleKey in ipairs(moduleKeys) do
        if snapshot[moduleKey] then
            local copied = DeepCopy(snapshot[moduleKey])
            if type(DDingUI.db.profile[moduleKey]) == "table" then
                ApplySnapshot(DDingUI.db.profile[moduleKey], copied)
            else
                DDingUI.db.profile[moduleKey] = copied
            end
        end
    end

    self:SaveCurrentSpec()
    return true
end

function SP:CopyModulesFromSpec(sourceSpecID, moduleKeys)
    if not sourceSpecID or not moduleKeys or #moduleKeys == 0 then return false end
    if not DDingUI.db or not DDingUI.db.char or not DDingUI.db.char.specData then return false end

    local snapshot = DDingUI.db.char.specData[sourceSpecID]
    if not snapshot then return false end

    for _, moduleKey in ipairs(moduleKeys) do
        if snapshot[moduleKey] then
            local copied = DeepCopy(snapshot[moduleKey])
            if type(DDingUI.db.profile[moduleKey]) == "table" then
                ApplySnapshot(DDingUI.db.profile[moduleKey], copied)
            else
                DDingUI.db.profile[moduleKey] = copied
            end
        end
    end

    -- Update current spec snapshot
    self:SaveCurrentSpec()

    return true
end

-- Also allow copying from a different AceDB profile (not just spec)
function SP:CopyModulesFromProfile(sourceProfileKey, moduleKeys)
    if not sourceProfileKey or not moduleKeys or #moduleKeys == 0 then return false end
    if not DDingUI.db or not DDingUI.db.profiles then return false end

    local sourceProfile = DDingUI.db.profiles[sourceProfileKey]
    if not sourceProfile then return false end

    for _, moduleKey in ipairs(moduleKeys) do
        if sourceProfile[moduleKey] then
            local copied = DeepCopy(sourceProfile[moduleKey])
            if type(DDingUI.db.profile[moduleKey]) == "table" then
                ApplySnapshot(DDingUI.db.profile[moduleKey], copied)
            else
                DDingUI.db.profile[moduleKey] = copied
            end
        end
    end

    self:SaveCurrentSpec()
    return true
end

-- ============================================================
-- STUBS for external callers (per-module UI is no longer needed)
-- ============================================================

function SP:AddSpecProfileOptions() end
function SP:IsEnabled() return true end
function SP:IsAnyModuleEnabled() return true end
function SP:GetCurrentSpecInfo()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID, specName, _, specIcon = GetSpecializationInfo(specIndex)
    return specIndex, specID, specName, specIcon
end
function SP:GetAllSpecInfo()
    local specs = {}
    local numSpecs = GetNumSpecializations()
    for i = 1, numSpecs do
        local specID, specName, _, specIcon = GetSpecializationInfo(i)
        if specID then
            specs[i] = { index = i, id = specID, name = specName, icon = specIcon }
        end
    end
    return specs, numSpecs
end
