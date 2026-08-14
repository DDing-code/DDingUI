--[[
    DDingToolKit - DeathAlert Module
    공격대/파티원의 사망을 감지하여 알림 (DeathTracer 호환 로직 적용)
]]

local addonName, ns = ...
local L = ns.L
local SL = _G.DDingUI_StyleLib
local LSM = LibStub and LibStub("LibSharedMedia-3.0")

local DeathAlert = {}
ns.DeathAlert = DeathAlert

------------------------------------------------------
-- State & Frame
------------------------------------------------------
local frame
local msgFrame
local isActive = false
local roleCache = {}
local inspectRequests = {}
local deadState = {}
local scanElapsed = 0
local SCAN_INTERVAL = 0.25

local function IsSecretValue(value)
    return type(hasanysecretvalues) == "function" and hasanysecretvalues(value)
end

local wipeTracker = {
    resetTime = 0,
    count = 0,
    maxSounds = 3,
    window = 10,
}

local function GetRoleIcon(role)
    if role == "TANK" then
        return "|A:groupfinder-icon-role-large-tank:15:15|a"
    elseif role == "HEALER" then
        return "|A:groupfinder-icon-role-large-heal:15:15|a"
    elseif role == "DAMAGER" then
        return "|A:groupfinder-icon-role-large-dps:15:15|a"
    end
    return ""
end

-- Sound helpers
local function ResolveSoundFile(key)
    if type(key) ~= "string" or key == "" or key == "None" then
        return nil
    end

    if key:find("[\\/]") then
        return key
    end

    if LSM then
        local ok, snd = pcall(LSM.Fetch, LSM, "sound", key, true)
        if ok and snd and snd ~= "" then
            return snd
        end
    end

    return nil
end

local function HasSoundSelection(key)
    return type(key) == "string" and key ~= "" and key ~= "None"
end

local function PlayDeathSound(key, channel)
    local soundFile = ResolveSoundFile(key)
    if not soundFile then return false end

    local played, willPlay = pcall(PlaySoundFile, soundFile, channel or "Master")
    return played and willPlay ~= false
end

-- GUID로부터 UnitID를 안전하게 가져오는 함수 (비밀값 우회용)
local function GetUnitIDFromGUIDFallback(guid)
    if not guid then return nil end
    if IsSecretValue(guid) then return nil end

    local token = type(UnitTokenFromGUID) == "function" and UnitTokenFromGUID(guid)
    if token then return token end

    if UnitGUID("player") == guid then return "player" end

    if IsInRaid() then
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitGUID(u) == guid then return u end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local u = "party" .. i
            if UnitGUID(u) == guid then return u end
        end
    end
    return nil
end

local function NormalizeRole(role)
    if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
        return role
    end
    return nil
end

local function GetSpecRole(unit)
    if not unit or IsSecretValue(unit) or not UnitExists(unit) then return nil end

    if unit == "player" and GetSpecialization and GetSpecializationRole then
        local specIndex = GetSpecialization()
        if specIndex then
            return NormalizeRole(GetSpecializationRole(specIndex))
        end
    end

    if GetInspectSpecialization and GetSpecializationRoleByID then
        local specID = GetInspectSpecialization(unit)
        if specID and specID > 0 then
            return NormalizeRole(GetSpecializationRoleByID(specID))
        end
    end

    return nil
end

local function RequestInspectRole(unit, guid)
    if unit == "player" or not guid or not NotifyInspect or not CanInspect then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if not CanInspect(unit) then return end

    local now = GetTime and GetTime() or 0
    if inspectRequests[guid] and now - inspectRequests[guid] < 30 then
        return
    end

    inspectRequests[guid] = now
    pcall(NotifyInspect, unit)
end

local function CacheUnitRole(unit)
    if not unit or IsSecretValue(unit) or not UnitExists(unit) then return nil end

    local guid = UnitGUID(unit)
    if not guid or IsSecretValue(guid) then return nil end

    local role = NormalizeRole(UnitGroupRolesAssigned(unit)) or GetSpecRole(unit)
    if role then
        roleCache[guid] = role
    else
        RequestInspectRole(unit, guid)
    end

    return role
end

local function RefreshRoleCache()
    CacheUnitRole("player")

    if IsInRaid() then
        for i = 1, 40 do
            CacheUnitRole("raid" .. i)
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            CacheUnitRole("party" .. i)
        end
    end
end

local function ResolveUnitRole(unit)
    local role = CacheUnitRole(unit)
    if role then return role end

    local guid = UnitGUID(unit)
    if guid and not IsSecretValue(guid) then
        return roleCache[guid]
    end

    return nil
end

local function IsTrackedGroupUnit(unit)
    if unit == "player" then return true end

    local inParty = UnitInParty(unit)
    if IsSecretValue(inParty) then inParty = false end

    local inRaid = UnitInRaid(unit)
    if IsSecretValue(inRaid) then inRaid = false end

    return inParty or inRaid
end

------------------------------------------------------
-- Visuals
------------------------------------------------------
local function CreateMessageFrame()
    if msgFrame then return end

    msgFrame = CreateFrame("Frame", "DDingToolKit_DeathAlertFrame", UIParent)
    msgFrame:SetSize(400, 50)
    msgFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    msgFrame:EnableMouse(false)
    if ns.EnableRightClickMouselook then
        ns:EnableRightClickMouselook(msgFrame)
        msgFrame:EnableMouse(false)
    end

    msgFrame.text = msgFrame:CreateFontString(nil, "OVERLAY")
    msgFrame.text:SetPoint("CENTER")

    -- Fade Out Animation
    msgFrame.anim = msgFrame:CreateAnimationGroup()
    local alpha = msgFrame.anim:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0)
    alpha:SetDuration(1.0)
    msgFrame.alphaAnim = alpha  -- ShowMessage에서 직접 참조하기 위해 저장
    msgFrame.anim:SetScript("OnFinished", function() msgFrame:Hide() end)

    msgFrame:Hide()
end

function DeathAlert:UpdateVisuals()
    if not msgFrame then CreateMessageFrame() end
    local db = ns.db.profile.DeathAlert
    if not db then return end

    local font = LSM and LSM:Fetch("font", db.font or "2002") or (SL and SL.Font.path) or "Fonts\\2002.TTF"
    msgFrame.text:SetFont(font, db.fontSize or 24, "OUTLINE")

    local pos = db.position
    if pos then
        msgFrame:ClearAllPoints()
        msgFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        msgFrame:ClearAllPoints()
        msgFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end

    if db.locked == false then
        msgFrame:EnableMouse(true)
        if not msgFrame.bg then
            msgFrame.bg = msgFrame:CreateTexture(nil, "BACKGROUND")
            msgFrame.bg:SetAllPoints()
            msgFrame.bg:SetColorTexture(0, 1, 0, 0.3)
        end
        msgFrame.bg:Show()
        msgFrame.text:SetText(L["DEATHALERT_TITLE"] .. " " .. L["POSITION_LOCKED"] .. " 해제됨")
        msgFrame:SetAlpha(1)
        msgFrame:Show()
    else
        msgFrame:EnableMouse(false)
        if msgFrame.bg then msgFrame.bg:Hide() end
        msgFrame:Hide()
    end
end

------------------------------------------------------
-- Trigger Logic
------------------------------------------------------
function DeathAlert:ShowMessage(text, role, name)
    if not msgFrame then CreateMessageFrame() end
    local db = ns.db.profile.DeathAlert
    if not db then return end

    msgFrame.text:SetText(text)
    msgFrame:SetAlpha(1)
    msgFrame:Show()

    -- Apply display duration
    local duration = db.messageDuration or 4
    if msgFrame.anim then
        msgFrame.anim:Stop()
        if msgFrame.alphaAnim then
            msgFrame.alphaAnim:SetStartDelay(duration)
        end
        msgFrame.anim:Play()
    end

    -- 사운드 재생 로직
    if not db.enableSound then return end

    local allowSound = false
    local now = GetTime()

    -- 전멸 체크 (Wipe detection)
    if now > wipeTracker.resetTime then
        wipeTracker.count = 0
        wipeTracker.resetTime = now + wipeTracker.window
    end
    wipeTracker.count = wipeTracker.count + 1

    if wipeTracker.count <= wipeTracker.maxSounds then
        allowSound = true
    elseif (role == "TANK" or role == "HEALER") and wipeTracker.count <= (wipeTracker.maxSounds + 2) then
        allowSound = true -- 탱/힐은 조금 더 허용
    end

    if not db.enableWipeDetection then
        allowSound = true
    end

    if allowSound then
        local playedRoleSound = false

        -- 본인 사망
        if db.enablePlayerSound and name == UnitName("player") and HasSoundSelection(db.playerSound) then
            PlayDeathSound(db.playerSound, db.soundChannel)
            playedRoleSound = true
        end

        -- 직업별 사운드
        if not playedRoleSound then
            if role == "TANK" and HasSoundSelection(db.tankSound) then
                PlayDeathSound(db.tankSound, db.soundChannel)
                playedRoleSound = true
            elseif role == "HEALER" and HasSoundSelection(db.healerSound) then
                PlayDeathSound(db.healerSound, db.soundChannel)
                playedRoleSound = true
            end
        end

        -- 일반 사운드
        if not playedRoleSound and HasSoundSelection(db.soundFile) then
            PlayDeathSound(db.soundFile, db.soundChannel)
        end
    end
end

function DeathAlert:HandleDeath(deadGUID, fallbackName)
    local db = ns.db.profile.DeathAlert
    if not db or not deadGUID or IsSecretValue(deadGUID) then return end

    if db.onlyInstance then
        local inInstance, instanceType = IsInInstance()
        if not inInstance or (instanceType ~= "party" and instanceType ~= "raid") then
            return
        end
    end

    local unitID = GetUnitIDFromGUIDFallback(deadGUID)
    if not unitID or IsSecretValue(unitID) or not IsTrackedGroupUnit(unitID) then
        return
    end

    local name = UnitName(unitID)
    if IsSecretValue(name) or not name or name == "" then
        name = fallbackName or UNKNOWN or "Unknown"
    end

    local role = ResolveUnitRole(unitID)
    local _, classFilename = UnitClass(unitID)
    local color = classFilename and C_ClassColor.GetClassColor(classFilename)
    local hexColor = color and color:GenerateHexColor() or "ff808080"
    local coloredName = "|c" .. hexColor .. name .. "|r"

    local iconStr = ""
    if db.enableRoleIcon and role then
        iconStr = GetRoleIcon(role) .. " "
    end

    DeathAlert:ShowMessage(iconStr .. coloredName .. " 사망!", role, name)

    if db.enableChatAlert then
        print((ns.prefix or "") .. "|cffff0000[사망]|r " .. iconStr .. coloredName)
    end
end

local function ScanUnitDeath(unit)
    if not unit or IsSecretValue(unit) or not UnitExists(unit) or not IsTrackedGroupUnit(unit) then
        return
    end

    local guid = UnitGUID(unit)
    if not guid or IsSecretValue(guid) then return end

    CacheUnitRole(unit)

    local isDead = UnitIsDeadOrGhost(unit) or UnitIsDead(unit)
    if IsSecretValue(isDead) then return end

    if isDead then
        if not deadState[guid] then
            deadState[guid] = true
            DeathAlert:HandleDeath(guid, UnitName(unit))
        end
    else
        deadState[guid] = nil
    end
end

local function ScanGroupDeaths()
    ScanUnitDeath("player")

    if IsInRaid() then
        for i = 1, 40 do
            ScanUnitDeath("raid" .. i)
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            ScanUnitDeath("party" .. i)
        end
    end
end

local function PrimeUnitDeathState(unit)
    if not unit or IsSecretValue(unit) or not UnitExists(unit) or not IsTrackedGroupUnit(unit) then
        return
    end

    local guid = UnitGUID(unit)
    if not guid or IsSecretValue(guid) then return end

    local isDead = UnitIsDeadOrGhost(unit) or UnitIsDead(unit)
    if IsSecretValue(isDead) then return end

    deadState[guid] = isDead and true or nil
end

local function PrimeDeadState()
    wipe(deadState)
    PrimeUnitDeathState("player")

    if IsInRaid() then
        for i = 1, 40 do
            PrimeUnitDeathState("raid" .. i)
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            PrimeUnitDeathState("party" .. i)
        end
    end
end

local function OnUpdate(self, elapsed)
    if not isActive then return end

    scanElapsed = scanElapsed + (elapsed or 0)
    if scanElapsed < SCAN_INTERVAL then return end
    scanElapsed = 0

    ScanGroupDeaths()
end

local function EnsureEventFrame()
    if not frame then
        frame = CreateFrame("Frame")
        frame:SetScript("OnUpdate", OnUpdate)
    end
end

------------------------------------------------------
-- Core Methods
------------------------------------------------------
local function CopyDefaultValue(value)
    if type(value) ~= "table" then return value end
    return CopyTable and CopyTable(value) or value
end

local function EnsureDeathAlertDefaults()
    local profile = ns.db and ns.db.profile
    if not profile then return end

    profile.DeathAlert = profile.DeathAlert or {}
    local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile.DeathAlert or {}
    for key, value in pairs(defaults) do
        if profile.DeathAlert[key] == nil then
            profile.DeathAlert[key] = CopyDefaultValue(value)
        end
    end

    for _, key in ipairs({ "soundFile", "tankSound", "healerSound", "playerSound" }) do
        if profile.DeathAlert[key] == "None" then
            profile.DeathAlert[key] = ""
        end
    end
end

function DeathAlert:OnInitialize()
    EnsureDeathAlertDefaults()
    EnsureEventFrame()
    CreateMessageFrame()
    self:UpdateVisuals()
    RefreshRoleCache()
end

function DeathAlert:Init()
    self:OnInitialize()
end

function DeathAlert:OnEnable()
    EnsureDeathAlertDefaults()
    local enabled = ns.db.profile.modules and (ns.db.profile.modules.DeathAlert == true)
    if not enabled then
        self:OnDisable()
        return
    end

    PrimeDeadState()
    scanElapsed = SCAN_INTERVAL
    isActive = true
    RefreshRoleCache()
    self:UpdateVisuals()
end

function DeathAlert:OnDisable()
    isActive = false
    wipe(deadState)
    if msgFrame and msgFrame.bg then msgFrame.bg:Hide(); msgFrame:Hide() end
end

function DeathAlert:EnterEditPreview()
    self:UpdateVisuals()
end

function DeathAlert:ExitEditPreview()
    self:UpdateVisuals()
end

function DeathAlert:TestMode()
    local roles = {"TANK", "HEALER", "DAMAGER"}
    local classes = {"WARRIOR", "PRIEST", "MAGE"}
    local names = {"테스트탱커", "테스트힐러", "테스트딜러"}

    local idx = math.random(1, 3)
    local role, class, name = roles[idx], classes[idx], names[idx]

    local color = C_ClassColor.GetClassColor(class)
    local hexColor = color and color:GenerateHexColor() or "ff808080"
    local coloredName = "|c" .. hexColor .. name .. "|r"

    local db = ns.db.profile.DeathAlert
    local iconStr = (db and db.enableRoleIcon) and (GetRoleIcon(role) .. " ") or ""

    self:ShowMessage(iconStr .. coloredName .. " 사망! (테스트)", role, name)
end

EnsureEventFrame()

-- 모듈 등록
local DDingToolKit = ns.DDingToolKit
DDingToolKit:RegisterModule("DeathAlert", DeathAlert)
