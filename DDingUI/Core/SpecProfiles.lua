local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

-- ============================================================
-- SPEC PROFILES - Per-specialization full-profile snapshot
--
-- ONE AceDB profile; each spec's settings stored in db.profile.specData[specID].
-- specData is in db.profile (not db.char) so same-class characters share settings.
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

-- [PERF] 모듈 스코프 상수: 재귀마다 테이블 재생성 방지
local EXCLUDE_KEYS = {
    specData = true,
    specDataVersion = true,
    profileVersion = true,
    pendingMoverMigration = true,
}

-- FullSnapshot: captures ALL values including AceDB metatable defaults
-- (pairs() only returns explicitly stored keys; defaults come via __index)
-- isTopLevel: excludeKeys는 최상위 호출에서만 적용 (하위 테이블에는 해당 키가 없음)
local function FullSnapshot(settings, defaults, isTopLevel)
    local snapshot = {}
    for k, v in pairs(settings) do
        if not (isTopLevel and EXCLUDE_KEYS[k]) then
            if type(v) == "table" then
                local subDef = defaults and type(defaults[k]) == "table" and defaults[k] or nil
                snapshot[k] = FullSnapshot(v, subDef, false)
            else
                snapshot[k] = v
            end
        end
    end
    if defaults then
        for k, v in pairs(defaults) do
            if not (isTopLevel and EXCLUDE_KEYS[k]) and snapshot[k] == nil then
                snapshot[k] = type(v) == "table" and DeepCopy(v) or v
            end
        end
    end
    return snapshot
end

-- ApplySnapshot: overwrites dest in-place (preserves AceDB table/metatable)
local function ApplySnapshot(dest, source, isTopLevel)
    -- [FIX] 2-pass 삭제: pairs() 순회 중 nil 할당 시 키 누락 방지
    -- Lua 5.1에서 pairs()/next()는 테이블 수정 시 동작이 미정의
    local toRemove
    for k in pairs(dest) do
        if not (isTopLevel and EXCLUDE_KEYS[k]) and source[k] == nil then
            if not toRemove then toRemove = {} end
            toRemove[#toRemove + 1] = k
        end
    end
    if toRemove then
        for _, k in ipairs(toRemove) do
            dest[k] = nil
        end
    end
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(dest[k]) == "table" then
                ApplySnapshot(dest[k], v, false)
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

    if not DDingUI.db.profile.specData then
        DDingUI.db.profile.specData = {}
    end

    local defaults = DDingUI.defaults and DDingUI.defaults.profile
    DDingUI.db.profile.specData[specID] = FullSnapshot(DDingUI.db.profile, defaults, true)
end

function SP:LoadSpec(specID)
    if not specID then return false end
    if not DDingUI.db then return false end
    if not DDingUI.db.profile.specData then return false end

    local snapshot = DDingUI.db.profile.specData[specID]
    if not snapshot then return false end

    -- Enrich with current defaults (forward compatibility for new keys)
    local defaults = DDingUI.defaults and DDingUI.defaults.profile
    if defaults then
        snapshot = FullSnapshot(snapshot, defaults, true)
    end

    ApplySnapshot(DDingUI.db.profile, snapshot, true)
    return true
end

-- ============================================================
-- SPEC CHANGE HANDLING
-- ============================================================

function SP:OnSpecChanged(newSpecID)
    if not DDingUI.db then return end

    print("|cff00ccff[SP]|r OnSpecChanged: " .. tostring(self.lastSpecID) .. " -> " .. tostring(newSpecID))

    -- Cancel any pending MarkDirty timer to prevent it from
    -- firing AFTER lastSpecID changes (would overwrite new spec's snapshot)
    if self._saveTimer then
        self._saveTimer:Cancel()
        self._saveTimer = nil
    end

    -- Save old spec BEFORE loading new
    if self.lastSpecID and self.lastSpecID ~= newSpecID then
        self:SaveCurrentSpec()
        print("|cff00ccff[SP]|r Saved old spec " .. tostring(self.lastSpecID))
    end

    -- Load new spec (or save initial snapshot if first visit)
    local loaded = self:LoadSpec(newSpecID)
    self.lastSpecID = newSpecID

    if not loaded then
        -- [FIX] 첫 방문 전문화: 자원바 markers를 기본값(빈 배열)으로 리셋
        -- 이전 전문화의 markers가 새 전문화에 상속되는 것을 방지
        local p = DDingUI.db.profile
        if p.powerBar then
            p.powerBar.markers = {}
            p.powerBar.markerBarColors = {}
            p.powerBar.markerColorChange = false
        end
        if p.secondaryPowerBar then
            p.secondaryPowerBar.markers = {}
            p.secondaryPowerBar.markerBarColors = {}
            p.secondaryPowerBar.markerColorChange = false
        end
        self:SaveCurrentSpec()
        print("|cff00ccff[SP]|r First visit to spec " .. tostring(newSpecID) .. " - saved current state (markers reset)")
    else
        print("|cff00ccff[SP]|r Loaded snapshot for spec " .. tostring(newSpecID))
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

local SPEC_DATA_VERSION = 4  -- v4: specData를 db.char → db.profile로 이동

local function MigrateSpecData()
    if not DDingUI.db then return end

    -- db.char 정리 (이전 버전 잔여 데이터 삭제, 복사하지 않음 — 오염 가능성)
    if DDingUI.db.char then
        DDingUI.db.char.specData = nil
        DDingUI.db.char.specDataVersion = nil
        DDingUI.db.char.specDataProfileKey = nil
    end

    -- 버전 체크 (db.profile 기준)
    local ver = DDingUI.db.profile.specDataVersion or 0
    if ver < SPEC_DATA_VERSION then
        -- 오래된 포맷이면 초기화
        if ver > 0 and ver < 4 then
            DDingUI.db.profile.specData = {}
        end
        DDingUI.db.profile.specDataVersion = SPEC_DATA_VERSION
    end
end

-- ============================================================
-- INITIALIZE
-- ============================================================

function SP:Initialize()
    -- Check if per-spec snapshots are enabled (default: true)
    if DDingUI.db and DDingUI.db.char and DDingUI.db.char.specProfilesEnabled == false then
        return
    end

    -- Migrate specData: db.char → db.profile
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
                -- [FIX] 3분기: 인스턴스 전환(arg1=false, arg2=false) 시 LoadSpec 방지
                -- 인스턴스 입장 시 LoadSpec하면 저장하지 않은 설정 변경이 롤백됨
                local specID = GetCurrentSpecID()
                if specID then
                    SP.lastSpecID = specID
                    if arg2 then
                        -- 리로드: AceDB가 SavedVariables에서 직접 복원하므로 저장만
                        SP:SaveCurrentSpec()
                    elseif arg1 then
                        -- 초기 로그인: 전문화별 스냅샷 복원
                        if DDingUI.db.profile.specData and DDingUI.db.profile.specData[specID] then
                            SP:LoadSpec(specID)
                            C_Timer.After(0.1, function()
                                if DDingUI.RefreshAll then DDingUI:RefreshAll() end
                            end)
                        else
                            -- 첫 방문: 현재 상태를 스냅샷으로 저장
                            SP:SaveCurrentSpec()
                        end
                    else
                        -- 인스턴스 전환/포탈: 현재 상태 저장만 (롤백 방지)
                        SP:SaveCurrentSpec()
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

    -- [FIX] 프로필 전환 시 specData 초기화
    if DDingUI.db and DDingUI.db.RegisterCallback then
        DDingUI.db.RegisterCallback(SP, "OnProfileChanged", "OnProfileSwitched")
        DDingUI.db.RegisterCallback(SP, "OnProfileCopied",  "OnProfileSwitched")
        DDingUI.db.RegisterCallback(SP, "OnProfileReset",   "OnProfileSwitched")
    end

    -- Save initial snapshot for current spec if none exists yet
    local specID = GetCurrentSpecID()
    if specID and DDingUI.db then
        if not DDingUI.db.profile.specData then
            DDingUI.db.profile.specData = {}
        end
        if not DDingUI.db.profile.specData[specID] then
            self:SaveCurrentSpec()
        end
    end
end

-- [FIX] 프로필 전환 콜백: specData 초기화 + 새 프로필 스냅샷 저장
function SP:OnProfileSwitched()
    -- 대기 중인 저장 타이머 취소 (이전 프로필 데이터 저장 방지)
    if self._saveTimer then
        self._saveTimer:Cancel()
        self._saveTimer = nil
    end

    -- 새 프로필의 현재 spec 스냅샷 저장
    local specID = GetCurrentSpecID()
    if specID then
        self.lastSpecID = specID
        -- 새 프로필에 specData가 있으면 로드, 없으면 저장
        if DDingUI.db.profile.specData and DDingUI.db.profile.specData[specID] then
            self:LoadSpec(specID)
            -- [FIX] LoadSpec 후 화면 갱신 (이전에 누락)
            C_Timer.After(0.1, function()
                if DDingUI.RefreshAll then DDingUI:RefreshAll() end
            end)
        else
            self:SaveCurrentSpec()
        end
    end
end

-- ============================================================
-- MODULE-LEVEL IMPORT from another spec snapshot
-- ============================================================

-- 모듈 카테고리 → 표시 이름 + 실제 프로필 키 매핑
SP.MODULE_KEYS = {
    { key = "general",           name = "일반",              profileKeys = {"general"} },
    { key = "iconGroups",        name = "아이콘 그룹",       profileKeys = {"viewers", "groupSystem", "dynamicIcons", "customIcons"} },
    { key = "resourceBars",      name = "자원바",            profileKeys = {"powerBar", "secondaryPowerBar"} },
    { key = "iconCustomization", name = "아이콘 커스터마이징", profileKeys = {"iconCustomization"} },
    { key = "castBar",           name = "시전바",            profileKeys = {"castBar"} },
    { key = "buffTrackerBar",    name = "추적중인 막대",     profileKeys = {"buffTrackerBar"} },
    { key = "buffBarViewer",     name = "버프추적기",        profileKeys = {"buffBarViewer"} },
}

function SP:GetAvailableSpecs()
    local result = {}
    if not DDingUI.db or not DDingUI.db.profile or not DDingUI.db.profile.specData then
        return result
    end
    for specID, _ in pairs(DDingUI.db.profile.specData) do
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
    -- db.profile.specData에서 직접 읽음 (프로필 공유이므로 모든 캐릭터 데이터가 여기 있음)
    if not DDingUI.db or not DDingUI.db.profile or not DDingUI.db.profile.specData then
        return result
    end

    local currentSpecID = self.lastSpecID

    for specID, _ in pairs(DDingUI.db.profile.specData) do
        if specID ~= currentSpecID then
            local specLabel = "전문화 " .. specID
            if GetSpecializationInfoByID then
                local _, sName, _, _, _, _, className = GetSpecializationInfoByID(specID)
                if sName and className then
                    specLabel = className .. "-" .. sName
                elseif sName then
                    specLabel = sName
                end
            end
            result[specID] = specLabel
        end
    end

    return result
end

-- 크로스캐릭터 모듈 복사 (이제 불필요하지만 호환성 유지)
function SP:CopyModulesFromCharSpec(charKey, specID, moduleKeys)
    return self:CopyModulesFromSpec(specID, moduleKeys)
end

function SP:CopyModulesFromSpec(sourceSpecID, moduleKeys)
    if not sourceSpecID or not moduleKeys or #moduleKeys == 0 then return false end
    if not DDingUI.db or not DDingUI.db.profile or not DDingUI.db.profile.specData then return false end

    local snapshot = DDingUI.db.profile.specData[sourceSpecID]
    if not snapshot then return false end

    for _, moduleKey in ipairs(moduleKeys) do
        if snapshot[moduleKey] then
            local copied = DeepCopy(snapshot[moduleKey])
            if type(DDingUI.db.profile[moduleKey]) == "table" then
                ApplySnapshot(DDingUI.db.profile[moduleKey], copied, false)
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
            local defaults = DDingUI.db and DDingUI.db.defaults
                and DDingUI.db.defaults.profile and DDingUI.db.defaults.profile[moduleKey]
            local copied = FullSnapshot(sourceProfile[moduleKey], defaults, false)
            if type(DDingUI.db.profile[moduleKey]) == "table" then
                ApplySnapshot(DDingUI.db.profile[moduleKey], copied, false)
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
