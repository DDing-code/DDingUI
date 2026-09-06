--[[
    DDingToolKit - CastingAlert Module
    TargetedSpells-inspired nameplate cast tracker.
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib
local SOLID = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local DEFAULT_ICON = 136243
local INTERRUPT_ICON = "Interface\\TARGETINGFRAME\\UI-RaidTargetingIcon_7"
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("TargetSpell", "TargetSpell") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6TargetSpell|r: "
local DISPLAY_MODE_ICON = "ICON"
local DISPLAY_MODE_BAR = "BAR"
local DISPLAY_MODE_DUAL = "ICON_TEXT_ICON"

local CastingAlert = {}
CastingAlert.name = "CastingAlert"
ns.CastingAlert = CastingAlert

local MAX_NAMEPLATES = 40
local START_DELAY = 0.2

local DEFAULTS = {
    enabled = false,
    disableForTank = false,
    showTarget = true,
    onlyTargetingMe = true,
    hideUntargeted = false,
    onlyImportant = false,
    combatOnly = true,
    ignoreMinor = true,
    showDuration = true,
    showSwipe = true,
    showImportantGlow = true,
    indicateInterrupts = true,

    displayMode = DISPLAY_MODE_ICON,
    maxShow = 10,
    iconSize = 35,
    fontSize = 18,
    font = (SL and SL.Font and SL.Font.path) or STANDARD_TEXT_FONT,
    iconFontSize = 18,
    durationTextColor = { 0.35, 1.00, 0.35, 1 },
    dimAlpha = 0.4,
    spacing = 4,
    stackDirection = "UP",
    scale = 1.0,
    updateRate = 0.05,
    scanDelay = START_DELAY,

    barWidth = 300,
    barHeight = 30,
    barTexture = SOLID,
    barFontSize = 14,
    barColor = { 0.16, 0.58, 0.42, 1 },
    barBackgroundColor = { 0.04, 0.05, 0.06, 0.92 },
    barBorderColor = { 0.24, 0.29, 0.33, 1 },
    barTextColor = { 1, 1, 1, 1 },
    barTargetTextColor = { 0.25, 0.82, 1, 1 },

    dualIconSize = 32,
    dualFontSize = 20,
    dualGap = 4,

    soundEnabled = true,
    soundThreshold = 2,
    soundCooldown = 2,
    soundFile = "",
    soundCustomPath = "",
    soundChannel = "Master",

    iconPosition = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -30 },
}

local START_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_EMPOWER_START = true,
}

local STOP_EVENTS = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
    NAME_PLATE_UNIT_REMOVED = true,
}

local ENVIRONMENT_EVENTS = {
    PLAYER_ENTERING_WORLD = true,
    LOADING_SCREEN_DISABLED = true,
    ZONE_CHANGED_NEW_AREA = true,
    UPDATE_INSTANCE_INFO = true,
    PLAYER_SPECIALIZATION_CHANGED = true,
}

local mainFrame
local iconAnchorFrame
local eventFrame
local updateTicker
local previewTicker
local iconFrames = {}
local barFrames = {}
local dualFrames = {}
local activeCasts = {}
local previewInfos = {}
local isEnabled = false
local isPreview = false
local lastSoundTime = 0
local previousTargetingCount = 0
local activeEncounterID

local function T(key, fallback)
    return (L and L[key]) or fallback
end

local function WipeTable(tbl)
    if wipe then
        wipe(tbl)
        return
    end

    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function CopyValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = CopyValue(child)
    end
    return copy
end

local function MergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = CopyValue(value)
        elseif type(value) == "table" and type(target[key]) == "table" then
            MergeDefaults(target[key], value)
        end
    end
end

local function Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function NumberValue(value, fallback, minimum, maximum)
    local result = tonumber(value)
    if result == nil then
        result = fallback
    end
    if minimum ~= nil and maximum ~= nil then
        result = Clamp(result, minimum, maximum)
    end
    return result
end

local function NormalizeDisplayMode(value)
    if value == DISPLAY_MODE_BAR or value == DISPLAY_MODE_DUAL then
        return value
    end
    return DISPLAY_MODE_ICON
end

local function GetDisplayDimensions(db)
    local mode = NormalizeDisplayMode(db and db.displayMode)
    if mode == DISPLAY_MODE_BAR then
        return NumberValue(db.barWidth, DEFAULTS.barWidth, 120, 800),
            NumberValue(db.barHeight, DEFAULTS.barHeight, 16, 80)
    end

    if mode == DISPLAY_MODE_DUAL then
        local iconSize = NumberValue(db.dualIconSize, DEFAULTS.dualIconSize, 16, 120)
        local fontSize = NumberValue(db.dualFontSize, DEFAULTS.dualFontSize, 8, 64)
        local gap = NumberValue(db.dualGap, DEFAULTS.dualGap, 0, 60)
        return (iconSize * 2) + (gap * 2) + (fontSize * 2.6), math.max(iconSize, fontSize + 4)
    end

    local iconSize = NumberValue(db and db.iconSize, DEFAULTS.iconSize, 16, 120)
    return iconSize, iconSize
end

local function IsSecretValue(value)
    return (ns.IsSecretValue and ns.IsSecretValue(value))
        or (issecretvalue and issecretvalue(value))
        or false
end

local function HasValue(value)
    if IsSecretValue(value) then
        return true
    end
    return value ~= nil
end

local function DisplayTexture(value)
    if IsSecretValue(value) then
        return value
    end
    return value == nil and DEFAULT_ICON or value
end

local function BoolAlpha(value, trueAlpha, falseAlpha)
    if trueAlpha == nil then
        trueAlpha = 1
    end
    if falseAlpha == nil then
        falseAlpha = 0
    end

    if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
        return C_CurveUtil.EvaluateColorValueFromBoolean(value, trueAlpha, falseAlpha)
    end

    if value == true then
        return trueAlpha
    end

    return falseAlpha
end

local function SecretBoolean(value)
    if value == nil then
        return secretwrap and secretwrap(false) or false
    end
    return value
end

local function ApplyAlphaFromBoolean(region, value, trueAlpha, falseAlpha)
    value = SecretBoolean(value)
    if trueAlpha == nil then
        trueAlpha = 1
    end
    if falseAlpha == nil then
        falseAlpha = 0
    end

    if region.SetAlphaFromBoolean then
        region:SetAlphaFromBoolean(value, trueAlpha, falseAlpha)
    else
        region:SetAlpha(BoolAlpha(value, trueAlpha, falseAlpha))
    end
end

local function SetPoint(frame, ...)
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(frame, ...)
    else
        frame:SetPoint(...)
    end
end

local function SetSize(frame, width, height)
    if PixelUtil and PixelUtil.SetSize then
        PixelUtil.SetSize(frame, width, height)
    else
        frame:SetSize(width, height)
    end
end

local function ReadColor(value, fallback)
    value = type(value) == "table" and value or fallback
    fallback = fallback or { 1, 1, 1, 1 }

    local r = value.r or value[1] or fallback[1] or 1
    local g = value.g or value[2] or fallback[2] or 1
    local b = value.b or value[3] or fallback[3] or 1
    local a = value.a or value[4] or fallback[4] or 1

    return r, g, b, a
end

local function IsNameplateUnit(unit)
    return type(unit) == "string" and unit:match("^nameplate%d+$") ~= nil
end

local function IsPlayerTank()
    local specIndex = GetSpecialization and GetSpecialization()
    if not specIndex then return false end

    local role = GetSpecializationRole and GetSpecializationRole(specIndex)
    return role == "TANK"
end

local function GetSpellTexture(spellID, fallbackTexture)
    if spellID ~= nil and C_Spell and C_Spell.GetSpellTexture then
        local texture = C_Spell.GetSpellTexture(spellID)
        if texture ~= nil then
            return texture
        end
    end

    if fallbackTexture ~= nil then
        return fallbackTexture
    end

    return DEFAULT_ICON
end

local function GetSpellName(spellID, fallbackName)
    if spellID ~= nil and C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(spellID)
        if name ~= nil then
            return name
        end
    end

    if fallbackName ~= nil then
        return fallbackName
    end

    return UNKNOWN
end

local function IsSpellImportant(spellID)
    if spellID == nil or not C_Spell or not C_Spell.IsSpellImportant then
        return false
    end

    local ok, important = pcall(C_Spell.IsSpellImportant, spellID)
    if not ok then
        return SecretBoolean(false)
    end

    return SecretBoolean(important)
end

local function GetTargetName(unit)
    if UnitSpellTargetName then
        return UnitSpellTargetName(unit)
    end

    return nil
end

local function GetTargetsPlayer(unit)
    if PlayerIsSpellTarget then
        return SecretBoolean(PlayerIsSpellTarget(unit, "player"))
    end

    return SecretBoolean(false)
end

local function GetTargetClassColor(unit)
    local class

    if UnitSpellTargetClass then
        class = UnitSpellTargetClass(unit)
    end

    if IsSecretValue(class) then
        return nil
    end

    if class and C_ClassColor and C_ClassColor.GetClassColor then
        return C_ClassColor.GetClassColor(class)
    end

    return nil
end

local function GetUnitLevelScore(unit)
    local level = UnitLevel(unit)
    if IsSecretValue(level) or type(level) ~= "number" then
        return 0
    end

    if level < 0 then
        return 1000
    end

    local classification = UnitClassification(unit)
    if IsSecretValue(classification) then classification = nil end
    local isBoss = UnitIsBossMob(unit)
    if IsSecretValue(isBoss) then isBoss = false end
    if classification == "worldboss" or classification == "elite" or isBoss == true then
        return level + 500
    end

    return level
end

local function CreateBorderLines(parent, layer, thickness)
    thickness = thickness or 1

    local lines = {}
    lines.top = parent:CreateTexture(nil, layer or "OVERLAY")
    lines.top:SetTexture(SOLID)
    lines.top:SetPoint("TOPLEFT")
    lines.top:SetPoint("TOPRIGHT")
    lines.top:SetHeight(thickness)

    lines.bottom = parent:CreateTexture(nil, layer or "OVERLAY")
    lines.bottom:SetTexture(SOLID)
    lines.bottom:SetPoint("BOTTOMLEFT")
    lines.bottom:SetPoint("BOTTOMRIGHT")
    lines.bottom:SetHeight(thickness)

    lines.left = parent:CreateTexture(nil, layer or "OVERLAY")
    lines.left:SetTexture(SOLID)
    lines.left:SetPoint("TOPLEFT")
    lines.left:SetPoint("BOTTOMLEFT")
    lines.left:SetWidth(thickness)

    lines.right = parent:CreateTexture(nil, layer or "OVERLAY")
    lines.right:SetTexture(SOLID)
    lines.right:SetPoint("TOPRIGHT")
    lines.right:SetPoint("BOTTOMRIGHT")
    lines.right:SetWidth(thickness)

    return lines
end

local function SetBorderLinesColor(lines, r, g, b, a)
    if not lines then return end
    for _, texture in pairs(lines) do
        texture:SetVertexColor(r, g, b, a)
    end
end

local function SetFontStringColor(fontString, color, fallback)
    if not fontString then return end
    local r, g, b, a = ReadColor(color, fallback)
    fontString:SetTextColor(r, g, b, a)
end

local function ApplyFont(fontString, font, size, color, fallbackColor)
    if not fontString then return end
    fontString:SetFont(font or STANDARD_TEXT_FONT, size, "OUTLINE")
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, 0.9)
    SetFontStringColor(fontString, color, fallbackColor)
end

local function ApplyCooldownFont(cooldown, font, size, color)
    if not cooldown then return end

    if cooldown.GetCountdownFontString then
        local fontString = cooldown:GetCountdownFontString()
        if fontString then
            ApplyFont(fontString, font, size, color, DEFAULTS.durationTextColor)
            fontString:ClearAllPoints()
            fontString:SetPoint("CENTER", cooldown, "CENTER", 0, 0)
            fontString:SetJustifyH("CENTER")
            fontString:SetJustifyV("MIDDLE")
            fontString:SetDrawLayer("OVERLAY")
            return
        end
    end

    for _, region in next, { cooldown:GetRegions() } do
        if region.GetObjectType and region:GetObjectType() == "FontString" then
            ApplyFont(region, font, size, color, DEFAULTS.durationTextColor)
            region:ClearAllPoints()
            region:SetPoint("CENTER", cooldown, "CENTER", 0, 0)
            region:SetJustifyH("CENTER")
            region:SetJustifyV("MIDDLE")
            region:SetDrawLayer("OVERLAY")
            return
        end
    end
end

local function SetCooldownDuration(cooldown, info)
    if not cooldown or not info then return end

    cooldown:Clear()
    if info.durationObject and cooldown.SetCooldownFromDurationObject then
        cooldown:SetCooldownFromDurationObject(info.durationObject)
    elseif info.isPreview then
        cooldown:SetCooldown(info.startTime or GetTime(), info.duration or 1)
    end
end

local function ApplyDisplayAlpha(frame, info, db)
    local shownAlpha = info.interrupted and 0.85 or 1
    if db.onlyTargetingMe then
        local trueAlpha = shownAlpha
        if db.onlyImportant then
            trueAlpha = BoolAlpha(info.importantSecret, shownAlpha, 0)
        end
        ApplyAlphaFromBoolean(frame, info.targetsPlayerSecret, trueAlpha, 0)
    elseif db.onlyImportant then
        ApplyAlphaFromBoolean(frame, info.importantSecret, shownAlpha, 0)
    else
        ApplyAlphaFromBoolean(frame, info.targetsPlayerSecret, shownAlpha, db.dimAlpha or DEFAULTS.dimAlpha)
    end
end

local function GetImportantAlpha(db, info)
    if not db.showImportantGlow then
        return 0
    end
    return BoolAlpha(info.importantSecret, 0.95, 0)
end

local function GetCastPlainKey(info)
    return tostring(info and info.unit) .. ":" .. tostring(info and info.createdAt)
end

local function GetCastDurationObject(unit, isChannel)
    if isChannel then
        return UnitChannelDuration and UnitChannelDuration(unit) or nil
    end

    return UnitCastingDuration and UnitCastingDuration(unit) or nil
end

local function CreateDurationObject(startTime, duration)
    if C_DurationUtil and C_DurationUtil.CreateDuration then
        local durationObject = C_DurationUtil.CreateDuration()
        if durationObject and durationObject.SetTimeFromStart then
            durationObject:SetTimeFromStart(startTime or GetTime(), duration or 1)
            return durationObject
        end
    end

    return nil
end

local function GetCurrentCastIdentity(unit)
    local _, _, _, _, _, _, _, _, spellID, castID = UnitCastingInfo(unit)
    local isChannel = false

    if spellID == nil then
        _, _, _, _, _, _, _, spellID, _, _, castID = UnitChannelInfo(unit)
        isChannel = spellID ~= nil
    end

    return isChannel, spellID, castID
end

local function GetCurrentCastInfo(unit)
    local isChannel, spellID, castID = GetCurrentCastIdentity(unit)
    if spellID == nil then
        return nil
    end

    local now = GetTime()
    local durationObject = GetCastDurationObject(unit, isChannel)
    if durationObject == nil then
        return nil
    end

    local targetName = GetTargetName(unit)
    local important = IsSpellImportant(spellID)
    local notInterruptible
    if isChannel then
        notInterruptible = select(7, UnitChannelInfo(unit))
    else
        notInterruptible = select(8, UnitCastingInfo(unit))
    end

    return {
        unit = unit,
        id = castID,
        spellID = spellID,
        spellName = GetSpellName(spellID),
        texture = GetSpellTexture(spellID),
        startTime = now,
        durationObject = durationObject,
        isChannel = isChannel,
        notInterruptibleSecret = SecretBoolean(notInterruptible),
        targetName = targetName,
        hasTargetNamePlain = HasValue(targetName),
        targetClassColor = GetTargetClassColor(unit),
        targetsPlayerNamePlain = false,
        targetsPlayerSecret = GetTargetsPlayer(unit),
        importantSecret = important,
        levelScore = GetUnitLevelScore(unit),
        raidTargetIndex = GetRaidTargetIndex(unit),
        createdAt = now,
        isCurrentTarget = false,
    }
end

local function CompareCastInfo(a, b)
    local scoreA = a.levelScore or 0
    local scoreB = b.levelScore or 0

    if scoreA ~= scoreB then
        return scoreA > scoreB
    end

    if a.createdAt ~= b.createdAt then
        return a.createdAt < b.createdAt
    end

    return tostring(a.unit) < tostring(b.unit)
end

local function CastIsStillActive(info)
    if not info or info.isPreview then
        return true
    end

    if info.interrupted then
        return GetTime() < (info.interruptedUntil or 0)
    end

    if not UnitExists(info.unit) then
        return false
    end

    local _, spellID, castID = GetCurrentCastIdentity(info.unit)
    if spellID == nil then
        return false
    end

    if info.id ~= nil and castID ~= nil then
        return castID == info.id
    end

    return true
end

function CastingAlert:ApplyDefaults()
    self.db = self.db or (ns.db and ns.db.profile and ns.db.profile.CastingAlert) or {}
    local hadIconPosition = rawget(self.db, "iconPosition") ~= nil
    local legacyPosition = rawget(self.db, "position")

    MergeDefaults(self.db, DEFAULTS)
    self.db.displayMode = NormalizeDisplayMode(self.db.displayMode)

    if not hadIconPosition then
        self.db.iconPosition = CopyValue(legacyPosition or DEFAULTS.iconPosition)
    end

    local legacyFontSize = tonumber(rawget(self.db, "fontSize")) or DEFAULTS.fontSize
    if rawget(self.db, "iconFontSize") == nil then
        self.db.iconFontSize = legacyFontSize
    end
end

function CastingAlert:OnInitialize()
    ns.db.profile.CastingAlert = ns.db.profile.CastingAlert or {}
    self.db = ns.db.profile.CastingAlert
    self:ApplyDefaults()
end

function CastingAlert:OnEnable()
    self:ApplyDefaults()
    self:RegisterSpecFrame()
    self:RefreshEnabledState()
end

function CastingAlert:OnDisable()
    if ns.CancelManagedSoundsBySource then ns:CancelManagedSoundsBySource("CastingAlert") end
    self:Stop()
    if self._specFrame then
        self._specFrame:UnregisterAllEvents()
    end
end

function CastingAlert:RegisterSpecFrame()
    if not self._specFrame then
        self._specFrame = CreateFrame("Frame")
        self._specFrame:SetScript("OnEvent", function(_, _, unit)
            if not unit or unit == "player" then
                CastingAlert:RefreshEnabledState()
            end
        end)
    end

    self._specFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

function CastingAlert:ShouldRun()
    if not self.db or not self.db.enabled then
        return false
    end

    if self.db.disableForTank and IsPlayerTank() then
        return false
    end

    return true
end

function CastingAlert:RefreshEnabledState()
    self:ApplyDefaults()

    if self:ShouldRun() then
        self:Start()
    else
        self:Stop()
    end
end

function CastingAlert:Start()
    if isEnabled then
        self:RestartUpdate()
        return
    end

    isEnabled = true
    self:CreateMainFrame()
    self:RegisterEvents()
    self:ScanVisibleNameplates()
    self:StartTicker()

    if mainFrame then
        mainFrame:Show()
    end
    if iconAnchorFrame then
        iconAnchorFrame:Show()
    end
end

function CastingAlert:Stop()
    isEnabled = false

    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end

    if eventFrame then
        eventFrame:UnregisterAllEvents()
    end

    WipeTable(activeCasts)
    previousTargetingCount = 0

    self:HideDisplayFrames()

    if iconAnchorFrame and not isPreview then
        iconAnchorFrame:Hide()
    end

    if mainFrame and not isPreview then
        mainFrame:Hide()
    end
end

function CastingAlert:RegisterEvents()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", function(_, event, ...)
            CastingAlert:OnEvent(event, ...)
        end)
    end

    eventFrame:UnregisterAllEvents()

    for event in pairs(START_EVENTS) do
        eventFrame:RegisterEvent(event)
    end

    for event in pairs(STOP_EVENTS) do
        eventFrame:RegisterEvent(event)
    end

    for event in pairs(ENVIRONMENT_EVENTS) do
        eventFrame:RegisterEvent(event)
    end

    eventFrame:RegisterEvent("UNIT_TARGET")
    eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTIBLE")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
    eventFrame:RegisterEvent("RAID_TARGET_UPDATE")
    eventFrame:RegisterEvent("ENCOUNTER_START")
    eventFrame:RegisterEvent("ENCOUNTER_END")
end

function CastingAlert:StartTicker()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end

    local rate = NumberValue(self.db.updateRate, DEFAULTS.updateRate, 0.03, 0.5)
    updateTicker = C_Timer.NewTicker(rate, function()
        if isEnabled and not isPreview then
            CastingAlert:Render()
        end
    end)
end

function CastingAlert:RestartUpdate()
    if not isEnabled then return end
    self:RegisterEvents()
    self:StartTicker()
    self:ScanVisibleNameplates()
    self:Render()
end

function CastingAlert:IsTrackableUnit(unit, skipTargetCheck)
    if not IsNameplateUnit(unit) then return false end
    if not UnitExists(unit) then return false end
    if UnitInParty(unit) or UnitIsFriend(unit, "player") then return false end
    if not UnitCanAttack("player", unit) then return false end
    if self.db.combatOnly and not UnitAffectingCombat(unit) then return false end
    if self.db.ignoreMinor and UnitClassification(unit) == "minus" then return false end

    return true
end

function CastingAlert:ScanVisibleNameplates()
    if not isEnabled then return end

    for i = 1, MAX_NAMEPLATES do
        local unit = "nameplate" .. i
        if self:IsTrackableUnit(unit) then
            self:ProcessUnitCast(unit, nil, true)
        end
    end
end

function CastingAlert:OnEvent(event, ...)
    if START_EVENTS[event] then
        self:OnCastStartEvent(event, ...)
    elseif STOP_EVENTS[event] then
        self:OnCastStopEvent(event, ...)
    elseif ENVIRONMENT_EVENTS[event] then
        self:OnEnvironmentEvent(event, ...)
    elseif event == "UNIT_TARGET" then
        self:OnUnitTarget(...)
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        local unit = ...
        if self:IsTrackableUnit(unit) then
            C_Timer.After(0.05, function()
                CastingAlert:ProcessUnitCast(unit, nil, true)
            end)
        end
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" or event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        self:UpdateInterruptibility(event, ...)
    elseif event == "RAID_TARGET_UPDATE" then
        self:RefreshRaidMarkers()
    elseif event == "ENCOUNTER_START" then
        activeEncounterID = ...
    elseif event == "ENCOUNTER_END" then
        activeEncounterID = nil
    end
end

function CastingAlert:OnCastStartEvent(event, unit, ...)
    if not self:IsTrackableUnit(unit) then
        return
    end

    local delay = NumberValue(self.db.scanDelay, START_DELAY, 0, 1)
    C_Timer.After(delay, function()
        CastingAlert:ProcessUnitCast(unit, event == "UNIT_SPELLCAST_CHANNEL_START", false)
    end)
end

function CastingAlert:OnUnitTarget(unit)
    if not self:IsTrackableUnit(unit) then
        return
    end

    self:ProcessUnitCast(unit, nil, true)
end

function CastingAlert:OnCastStopEvent(event, unit, ...)
    if not IsNameplateUnit(unit) then
        return
    end

    if event == "NAME_PLATE_UNIT_REMOVED" then
        self:ClearUnit(unit)
        return
    end

    local interruptedBy, castID
    if event == "UNIT_SPELLCAST_CHANNEL_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        interruptedBy, castID = select(4, ...)
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" then
        interruptedBy, castID = select(5, ...)
    else
        castID = select(4, ...)
    end

    if event == "UNIT_SPELLCAST_INTERRUPTED" and self.db.indicateInterrupts then
        self:MarkInterrupted(unit, castID, interruptedBy)
        return
    end

    self:ClearUnit(unit, castID)
end

function CastingAlert:OnEnvironmentEvent(event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        self:RefreshEnabledState()
        return
    end

    self:CleanupDanglingCasts()
    C_Timer.After(0.2, function()
        if isEnabled then
            CastingAlert:ScanVisibleNameplates()
        end
    end)
end

function CastingAlert:UpdateInterruptibility(event, unit)
    local info = activeCasts[unit]
    if not info then return end

    info.notInterruptibleSecret = SecretBoolean(event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE")
    self:Render()
end

function CastingAlert:RefreshRaidMarkers()
    for unit, info in pairs(activeCasts) do
        if UnitExists(unit) then
            info.raidTargetIndex = GetRaidTargetIndex(unit)
        end
    end
    self:Render()
end

function CastingAlert:ProcessUnitCast(unit, seedIsChannel, isRetarget)
    if not isEnabled or isPreview then return end
    if not self:IsTrackableUnit(unit) then
        self:ClearUnit(unit)
        return
    end

    local info = GetCurrentCastInfo(unit)
    if not info then
        if not isRetarget then
            self:ClearUnit(unit)
        end
        return
    end

    if seedIsChannel ~= nil then
        info.isChannel = seedIsChannel and true or info.isChannel
    end

    local previous = activeCasts[unit]
    if isRetarget and previous then
        info.startTime = previous.startTime or info.startTime
        info.createdAt = previous.createdAt or info.createdAt
    end

    info.isRetarget = isRetarget and true or false
    activeCasts[unit] = info
    self:Render()
end

function CastingAlert:ClearUnit(unit, castID)
    local info = activeCasts[unit]
    if not info then return end

    if castID == nil or info.id == nil or castID == info.id then
        activeCasts[unit] = nil
        self:Render()
    end
end

function CastingAlert:MarkInterrupted(unit, castID, interruptedBy)
    local info = activeCasts[unit]
    if not info then return end
    if castID ~= nil and info.id ~= nil and castID ~= info.id then return end
    if not UnitExists(unit) then
        self:ClearUnit(unit, castID)
        return
    end

    local interruptName
    local interruptColor

    if interruptedBy then
        interruptName = UnitNameFromGUID(interruptedBy)
        local class = select(2, UnitClassFromGUID(interruptedBy))
        if class and C_ClassColor and C_ClassColor.GetClassColor then
            interruptColor = C_ClassColor.GetClassColor(class)
        end
    end

    info.interrupted = true
    info.interruptedBy = interruptName
    info.interruptColor = interruptColor
    info.interruptedUntil = GetTime() + 0.95

    self:Render()

    C_Timer.After(1, function()
        local current = activeCasts[unit]
        if current == info then
            CastingAlert:ClearUnit(unit, castID)
        end
    end)
end

function CastingAlert:CleanupDanglingCasts()
    local changed = false

    for unit, info in pairs(activeCasts) do
        if not CastIsStillActive(info) then
            activeCasts[unit] = nil
            changed = true
        end
    end

    if changed then
        self:Render()
    end
end

function CastingAlert:InfoPassesFilters(info)
    if self.db.hideUntargeted and info.hasTargetNamePlain == false then
        return false
    end

    return true
end

function CastingAlert:CollectVisibleCasts()
    self:CleanupExpiredWithoutRender()

    local list = {}
    for _, info in pairs(activeCasts) do
        if self:InfoPassesFilters(info) then
            list[#list + 1] = info
        end
    end

    table.sort(list, CompareCastInfo)

    local maxShow = math.max(1, math.floor(NumberValue(self.db.maxShow, DEFAULTS.maxShow, 1, 20)))
    while #list > maxShow do
        table.remove(list)
    end

    return list
end

function CastingAlert:CleanupExpiredWithoutRender()
    for unit, info in pairs(activeCasts) do
        if not CastIsStillActive(info) then
            activeCasts[unit] = nil
        end
    end
end

function CastingAlert:ApplyAnchorPosition(frame, position)
    if not frame then return end

    position = position or DEFAULTS.iconPosition
    frame:ClearAllPoints()
    frame:SetPoint(position.point or "CENTER", UIParent, position.relativePoint or position.point or "CENTER", position.x or 0, position.y or 0)
end

function CastingAlert:SaveAnchorPosition(frame, key)
    if not frame or not key then return end

    self.db[key] = self.db[key] or {}

    local centerX, centerY = frame:GetCenter()
    local parentX, parentY = UIParent:GetCenter()
    if centerX and centerY and parentX and parentY then
        local frameScale = frame:GetEffectiveScale() or 1
        local parentScale = UIParent:GetEffectiveScale() or 1
        self.db[key].point = "CENTER"
        self.db[key].relativePoint = "CENTER"
        self.db[key].x = ((centerX * frameScale) - (parentX * parentScale)) / parentScale
        self.db[key].y = ((centerY * frameScale) - (parentY * parentScale)) / parentScale
        self:ApplyAnchorPosition(frame, self.db[key])
        return
    end

    local point, _, relativePoint, x, y = frame:GetPoint()
    self.db[key].point = point or "CENTER"
    self.db[key].relativePoint = relativePoint or point or "CENTER"
    self.db[key].x = x or 0
    self.db[key].y = y or 0
end

function CastingAlert:CreateAnchorFrame(name, positionKey, fallbackPosition)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(1, 1)
    frame:SetFrameStrata("LOW")
    frame:SetScale(NumberValue(self.db.scale, 1, 0.3, 3))
    frame:EnableMouse(false)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    self:ApplyAnchorPosition(frame, self.db[positionKey] or fallbackPosition)

    frame:SetScript("OnDragStart", function(anchor)
        if isPreview then
            anchor:StartMoving()
        end
    end)

    frame:SetScript("OnDragStop", function(anchor)
        anchor:StopMovingOrSizing()
        CastingAlert:SaveAnchorPosition(anchor, positionKey)
    end)

    return frame
end

function CastingAlert:UpdateAnchorSizes()
    if iconAnchorFrame then
        local width, height = GetDisplayDimensions(self.db)
        iconAnchorFrame:SetSize(width, height)
    end
end

function CastingAlert:CreateMainFrame()
    self:ApplyDefaults()

    if not mainFrame then
        mainFrame = CreateFrame("Frame", "DDingToolKit_CastingAlertFrame", UIParent)
        mainFrame:SetSize(1, 1)
        mainFrame:SetFrameStrata("LOW")
        mainFrame:Hide()
    end

    if not iconAnchorFrame then
        iconAnchorFrame = self:CreateAnchorFrame("DDingToolKit_CastingAlertIconFrame", "iconPosition", DEFAULTS.iconPosition)
    end

    ns.CastingAlertIconFrame = iconAnchorFrame

    self:UpdatePosition()
    self:UpdateAnchorSizes()
end

function CastingAlert:CreateIconFrame(index)
    local frame = iconFrames[index]
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", nil, iconAnchorFrame or UIParent)
    frame:SetFrameLevel(1000 - index)
    frame:EnableMouse(false)

    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetTexture(SOLID)
    frame.background:SetAllPoints()
    frame.background:SetVertexColor(0, 0, 0, 0.9)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 2, -2)
    frame.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.icon:SetTexCoord(0.08, 0.92, 0.16, 0.84)

    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints(frame.icon)
    frame.cooldown:SetDrawEdge(true)
    frame.cooldown:SetDrawSwipe(true)
    frame.cooldown:SetDrawBling(false)

    frame.interruptIcon = frame:CreateTexture(nil, "OVERLAY")
    frame.interruptIcon:SetTexture(INTERRUPT_ICON)
    frame.interruptIcon:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 4, -4)
    frame.interruptIcon:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", -4, 4)
    frame.interruptIcon:Hide()

    frame.border = CreateBorderLines(frame, "OVERLAY", 1)
    SetBorderLinesColor(frame.border, 0, 0, 0, 1)

    frame.importantBorder = CreateBorderLines(frame, "OVERLAY", 2)
    SetBorderLinesColor(frame.importantBorder, 1, 0.86, 0.2, 0)

    iconFrames[index] = frame
    return frame
end

function CastingAlert:PositionDisplayFrame(frame, index, width, height)
    local spacing = NumberValue(self.db.spacing, DEFAULTS.spacing, -50, 80)
    local direction = self.db.stackDirection or "UP"
    local x, y = 0, 0

    if direction == "DOWN" then
        y = -(index - 1) * (height + spacing)
    elseif direction == "LEFT" then
        x = -(index - 1) * (width + spacing)
    elseif direction == "RIGHT" then
        x = (index - 1) * (width + spacing)
    elseif direction == "OVERLAP" then
        x, y = 0, 0
    else
        y = (index - 1) * (height + spacing)
    end

    local parent = iconAnchorFrame or UIParent
    if frame:GetParent() ~= parent then
        frame:SetParent(parent)
        frame._layoutKey = nil
    end

    local layoutKey = tostring(index) .. ":" .. tostring(width) .. ":" .. tostring(height) .. ":" .. tostring(spacing) .. ":" .. tostring(direction) .. ":" .. tostring(x) .. ":" .. tostring(y)
    if frame._layoutKey == layoutKey then
        return
    end

    frame._layoutKey = layoutKey
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", parent, "CENTER", x, y)
end

function CastingAlert:UpdateIconFrame(frame, info, index)
    local size = NumberValue(self.db.iconSize, DEFAULTS.iconSize, 16, 120)
    if frame._iconSize ~= size then
        SetSize(frame, size, size)
        frame._iconSize = size
        frame._layoutKey = nil
    end
    self:PositionDisplayFrame(frame, index, size, size)

    frame.icon:SetTexture(DisplayTexture(info.texture))
    frame.icon:SetDesaturated(info.interrupted and true or false)
    frame.interruptIcon:SetShown(info.interrupted and self.db.indicateInterrupts)

    if frame.cooldown.SetHideCountdownNumbers then
        frame.cooldown:SetHideCountdownNumbers(not self.db.showDuration)
    end
    frame.cooldown:SetDrawSwipe(self.db.showSwipe and not info.interrupted)
    frame.cooldown:SetReverse(info.isChannel and true or false)
    ApplyCooldownFont(
        frame.cooldown,
        self.db.font or DEFAULTS.font,
        NumberValue(self.db.iconFontSize, DEFAULTS.iconFontSize, 8, 48),
        self.db.durationTextColor
    )

    local key = GetCastPlainKey(info)
    if frame._castKeyPlain ~= key then
        frame._castKeyPlain = key
        SetCooldownDuration(frame.cooldown, info)
    end

    if info.interrupted then
        frame.cooldown:Clear()
    end

    SetBorderLinesColor(frame.importantBorder, 1, 0.86, 0.2, GetImportantAlpha(self.db, info))
    ApplyDisplayAlpha(frame, info, self.db)

    frame:Show()
end

function CastingAlert:CreateBarFrame(index)
    local frame = barFrames[index]
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", nil, iconAnchorFrame or UIParent)
    frame:SetFrameLevel(1000 - index)
    frame:EnableMouse(false)

    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetTexture(SOLID)
    frame.background:SetAllPoints()

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexCoord(0.08, 0.92, 0.16, 0.84)

    frame.progress = CreateFrame("StatusBar", nil, frame)
    frame.progress:SetMinMaxValues(0, 1)
    frame.progress:SetValue(1)

    frame.progressBackground = frame.progress:CreateTexture(nil, "BACKGROUND")
    frame.progressBackground:SetTexture(SOLID)
    frame.progressBackground:SetAllPoints()

    frame.spellName = frame.progress:CreateFontString(nil, "OVERLAY")
    frame.spellName:SetJustifyH("LEFT")
    frame.spellName:SetJustifyV("MIDDLE")
    frame.spellName:SetWordWrap(false)

    frame.targetName = frame.progress:CreateFontString(nil, "OVERLAY")
    frame.targetName:SetJustifyH("RIGHT")
    frame.targetName:SetJustifyV("MIDDLE")
    frame.targetName:SetWordWrap(false)

    frame.durationCooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.durationCooldown:SetDrawEdge(false)
    frame.durationCooldown:SetDrawSwipe(false)
    frame.durationCooldown:SetDrawBling(false)

    frame.interruptIcon = frame:CreateTexture(nil, "OVERLAY")
    frame.interruptIcon:SetTexture(INTERRUPT_ICON)
    frame.interruptIcon:Hide()

    frame.border = CreateBorderLines(frame, "OVERLAY", 1)
    frame.importantBorder = CreateBorderLines(frame, "OVERLAY", 2)
    SetBorderLinesColor(frame.importantBorder, 1, 0.86, 0.2, 0)

    barFrames[index] = frame
    return frame
end

function CastingAlert:UpdateBarFrame(frame, info, index)
    local width = NumberValue(self.db.barWidth, DEFAULTS.barWidth, 120, 800)
    local height = NumberValue(self.db.barHeight, DEFAULTS.barHeight, 16, 80)
    local fontSize = NumberValue(self.db.barFontSize, DEFAULTS.barFontSize, 8, 36)
    local durationWidth = math.max(34, fontSize * 2.8)
    local targetWidth = math.max(52, math.min(96, width * 0.24))

    if frame._displayWidth ~= width or frame._displayHeight ~= height or frame._fontSize ~= fontSize or frame._showTarget ~= self.db.showTarget then
        SetSize(frame, width, height)
        frame._displayWidth = width
        frame._displayHeight = height
        frame._fontSize = fontSize
        frame._showTarget = self.db.showTarget
        frame._layoutKey = nil

        frame.icon:ClearAllPoints()
        frame.icon:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        frame.icon:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
        frame.icon:SetWidth(math.max(1, height - 2))

        frame.progress:ClearAllPoints()
        frame.progress:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 1, 0)
        frame.progress:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)

        frame.durationCooldown:ClearAllPoints()
        frame.durationCooldown:SetPoint("TOPRIGHT", frame.progress, "TOPRIGHT", 0, 0)
        frame.durationCooldown:SetPoint("BOTTOMRIGHT", frame.progress, "BOTTOMRIGHT", 0, 0)
        frame.durationCooldown:SetWidth(durationWidth)

        frame.targetName:ClearAllPoints()
        frame.targetName:SetPoint("RIGHT", frame.durationCooldown, "LEFT", -4, 0)
        frame.targetName:SetWidth(targetWidth)

        frame.spellName:ClearAllPoints()
        frame.spellName:SetPoint("LEFT", frame.progress, "LEFT", 6, 0)
        if self.db.showTarget then
            frame.spellName:SetPoint("RIGHT", frame.targetName, "LEFT", -6, 0)
        else
            frame.spellName:SetPoint("RIGHT", frame.durationCooldown, "LEFT", -6, 0)
        end

        frame.interruptIcon:ClearAllPoints()
        frame.interruptIcon:SetPoint("TOPLEFT", frame.icon, "TOPLEFT", 4, -4)
        frame.interruptIcon:SetPoint("BOTTOMRIGHT", frame.icon, "BOTTOMRIGHT", -4, 4)
    end

    self:PositionDisplayFrame(frame, index, width, height)

    frame.icon:SetTexture(DisplayTexture(info.texture))
    frame.icon:SetDesaturated(info.interrupted and true or false)
    frame.interruptIcon:SetShown(info.interrupted and self.db.indicateInterrupts)

    frame.progress:SetStatusBarTexture(self.db.barTexture or DEFAULTS.barTexture)
    local statusTexture = frame.progress:GetStatusBarTexture()
    if statusTexture and statusTexture.SetHorizTile then
        statusTexture:SetHorizTile(false)
    end

    local r, g, b, a = ReadColor(self.db.barColor, DEFAULTS.barColor)
    frame.progress:SetStatusBarColor(r, g, b, a)
    r, g, b, a = ReadColor(self.db.barBackgroundColor, DEFAULTS.barBackgroundColor)
    frame.background:SetVertexColor(r, g, b, a)
    frame.progressBackground:SetVertexColor(r, g, b, a)
    r, g, b, a = ReadColor(self.db.barBorderColor, DEFAULTS.barBorderColor)
    SetBorderLinesColor(frame.border, r, g, b, a)

    ApplyFont(frame.spellName, self.db.font or DEFAULTS.font, fontSize, self.db.barTextColor, DEFAULTS.barTextColor)
    ApplyFont(frame.targetName, self.db.font or DEFAULTS.font, fontSize, self.db.barTargetTextColor, DEFAULTS.barTargetTextColor)
    frame.spellName:SetText(info.spellName)
    if self.db.showTarget then
        frame.targetName:SetText(info.targetName)
        frame.targetName:Show()
    else
        frame.targetName:Hide()
    end

    frame.durationCooldown:SetHideCountdownNumbers(not self.db.showDuration)
    ApplyCooldownFont(frame.durationCooldown, self.db.font or DEFAULTS.font, fontSize, self.db.durationTextColor)

    local key = GetCastPlainKey(info)
    if frame._castKeyPlain ~= key then
        frame._castKeyPlain = key
        SetCooldownDuration(frame.durationCooldown, info)
        if info.durationObject and frame.progress.SetTimerDuration then
            local interpolation = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.None
            if interpolation ~= nil then
                frame.progress:SetTimerDuration(info.durationObject, interpolation, info.isChannel and 1 or 0)
            else
                frame.progress:SetTimerDuration(info.durationObject)
            end
        end
    end

    if info.interrupted then
        frame.durationCooldown:Clear()
    end

    SetBorderLinesColor(frame.importantBorder, 1, 0.86, 0.2, GetImportantAlpha(self.db, info))
    ApplyDisplayAlpha(frame, info, self.db)
    frame:Show()
end

local function CreateDualIconCell(parent)
    local cell = CreateFrame("Frame", nil, parent)

    cell.background = cell:CreateTexture(nil, "BACKGROUND")
    cell.background:SetTexture(SOLID)
    cell.background:SetAllPoints()
    cell.background:SetVertexColor(0, 0, 0, 0.9)

    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetPoint("TOPLEFT", 2, -2)
    cell.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    cell.icon:SetTexCoord(0.08, 0.92, 0.16, 0.84)

    cell.cooldown = CreateFrame("Cooldown", nil, cell, "CooldownFrameTemplate")
    cell.cooldown:SetAllPoints(cell.icon)
    cell.cooldown:SetDrawEdge(false)
    cell.cooldown:SetDrawBling(false)
    cell.cooldown:SetHideCountdownNumbers(true)

    cell.interruptIcon = cell:CreateTexture(nil, "OVERLAY")
    cell.interruptIcon:SetTexture(INTERRUPT_ICON)
    cell.interruptIcon:SetPoint("TOPLEFT", cell.icon, "TOPLEFT", 4, -4)
    cell.interruptIcon:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", -4, 4)
    cell.interruptIcon:Hide()

    cell.border = CreateBorderLines(cell, "OVERLAY", 1)
    SetBorderLinesColor(cell.border, 0, 0, 0, 1)
    cell.importantBorder = CreateBorderLines(cell, "OVERLAY", 2)
    SetBorderLinesColor(cell.importantBorder, 1, 0.86, 0.2, 0)

    return cell
end

function CastingAlert:CreateDualFrame(index)
    local frame = dualFrames[index]
    if frame then
        return frame
    end

    frame = CreateFrame("Frame", nil, iconAnchorFrame or UIParent)
    frame:SetFrameLevel(1000 - index)
    frame:EnableMouse(false)

    frame.leftCell = CreateDualIconCell(frame)
    frame.rightCell = CreateDualIconCell(frame)
    frame.cells = { frame.leftCell, frame.rightCell }

    frame.durationCooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.durationCooldown:SetDrawEdge(false)
    frame.durationCooldown:SetDrawSwipe(false)
    frame.durationCooldown:SetDrawBling(false)

    dualFrames[index] = frame
    return frame
end

function CastingAlert:UpdateDualFrame(frame, info, index)
    local iconSize = NumberValue(self.db.dualIconSize, DEFAULTS.dualIconSize, 16, 120)
    local fontSize = NumberValue(self.db.dualFontSize, DEFAULTS.dualFontSize, 8, 64)
    local gap = NumberValue(self.db.dualGap, DEFAULTS.dualGap, 0, 60)
    local textWidth = fontSize * 2.6
    local width = (iconSize * 2) + (gap * 2) + textWidth
    local height = math.max(iconSize, fontSize + 4)

    if frame._displayWidth ~= width or frame._displayHeight ~= height then
        SetSize(frame, width, height)
        frame._displayWidth = width
        frame._displayHeight = height
        frame._layoutKey = nil

        SetSize(frame.leftCell, iconSize, iconSize)
        frame.leftCell:ClearAllPoints()
        frame.leftCell:SetPoint("LEFT", frame, "LEFT", 0, 0)

        SetSize(frame.rightCell, iconSize, iconSize)
        frame.rightCell:ClearAllPoints()
        frame.rightCell:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

        frame.durationCooldown:ClearAllPoints()
        frame.durationCooldown:SetPoint("CENTER", frame, "CENTER", 0, 0)
        SetSize(frame.durationCooldown, textWidth, height)
    end

    self:PositionDisplayFrame(frame, index, width, height)

    local texture = DisplayTexture(info.texture)
    local importantAlpha = GetImportantAlpha(self.db, info)
    for _, cell in ipairs(frame.cells) do
        cell.icon:SetTexture(texture)
        cell.icon:SetDesaturated(info.interrupted and true or false)
        cell.interruptIcon:SetShown(info.interrupted and self.db.indicateInterrupts)
        cell.cooldown:SetDrawSwipe(self.db.showSwipe and not info.interrupted)
        cell.cooldown:SetReverse(info.isChannel and true or false)
        SetBorderLinesColor(cell.importantBorder, 1, 0.86, 0.2, importantAlpha)
    end

    frame.durationCooldown:SetHideCountdownNumbers(not self.db.showDuration)
    ApplyCooldownFont(
        frame.durationCooldown,
        self.db.font or DEFAULTS.font,
        fontSize,
        self.db.durationTextColor
    )

    local key = GetCastPlainKey(info)
    if frame._castKeyPlain ~= key then
        frame._castKeyPlain = key
        SetCooldownDuration(frame.leftCell.cooldown, info)
        SetCooldownDuration(frame.rightCell.cooldown, info)
        SetCooldownDuration(frame.durationCooldown, info)
    end

    if info.interrupted then
        frame.leftCell.cooldown:Clear()
        frame.rightCell.cooldown:Clear()
        frame.durationCooldown:Clear()
    end

    ApplyDisplayAlpha(frame, info, self.db)
    frame:Show()
end

local function HideFrames(frames, firstIndex)
    for i = firstIndex or 1, #frames do
        frames[i]._castKeyPlain = nil
        frames[i]:Hide()
    end
end

function CastingAlert:HideDisplayFrames()
    HideFrames(iconFrames)
    HideFrames(barFrames)
    HideFrames(dualFrames)
end

function CastingAlert:RenderList(list)
    if not iconAnchorFrame then return end

    local mode = NormalizeDisplayMode(self.db.displayMode)
    if mode == DISPLAY_MODE_BAR then
        HideFrames(iconFrames)
        HideFrames(dualFrames)
        for index, info in ipairs(list) do
            self:UpdateBarFrame(self:CreateBarFrame(index), info, index)
        end
        HideFrames(barFrames, #list + 1)
    elseif mode == DISPLAY_MODE_DUAL then
        HideFrames(iconFrames)
        HideFrames(barFrames)
        for index, info in ipairs(list) do
            self:UpdateDualFrame(self:CreateDualFrame(index), info, index)
        end
        HideFrames(dualFrames, #list + 1)
    else
        HideFrames(barFrames)
        HideFrames(dualFrames)
        for index, info in ipairs(list) do
            self:UpdateIconFrame(self:CreateIconFrame(index), info, index)
        end
        HideFrames(iconFrames, #list + 1)
    end
end

function CastingAlert:Render()
    if not iconAnchorFrame then return end
    if isPreview then
        self:RenderPreview()
        return
    end

    local list = self:CollectVisibleCasts()
    self:RenderList(list)
    self:MaybePlaySound(list)
end

function CastingAlert:MaybePlaySound(list)
    if not self.db.soundEnabled then
        previousTargetingCount = 0
        return
    end

    local targetingCount = 0
    for _, info in ipairs(list) do
        if info.targetsPlayerNamePlain then
            targetingCount = targetingCount + 1
        end
    end

    local threshold = math.max(1, math.floor(NumberValue(self.db.soundThreshold, DEFAULTS.soundThreshold, 1, 10)))
    local cooldown = NumberValue(self.db.soundCooldown, DEFAULTS.soundCooldown, 0, 30)
    local now = GetTime()

    if targetingCount >= threshold and previousTargetingCount < threshold and (now - lastSoundTime) >= cooldown then
        local channel = self.db.soundChannel or "Master"
        local soundKit = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959
        if ns.RequestSound then
            ns:RequestSound({
                source = "CastingAlert",
                key = "multiple-targeting",
                soundFile = self.db.soundFile,
                customPath = self.db.soundCustomPath,
                soundKit = soundKit,
                channel = channel,
                priority = 100,
            })
        elseif (self.db.soundCustomPath and self.db.soundCustomPath ~= "") or (self.db.soundFile and self.db.soundFile ~= "") then
            ns:PlaySound(self.db.soundFile, channel, self.db.soundCustomPath)
        else
            PlaySound(soundKit, channel)
        end
        lastSoundTime = now
    end

    previousTargetingCount = targetingCount
end

function CastingAlert:BuildPreviewInfos()
    WipeTable(previewInfos)

    local now = GetTime()
    local playerName = UnitName("player") or PLAYER
    local samples = {
        { spellID = 116, targetName = playerName, targetsPlayer = true, important = true, notInterruptible = false },
        { spellID = 44614, targetName = "Party", targetsPlayer = false, important = false, notInterruptible = false },
        { spellID = 118, targetName = nil, targetsPlayer = false, important = false, notInterruptible = true },
    }

    local maxShow = math.min(math.max(1, math.floor(NumberValue(self.db.maxShow, DEFAULTS.maxShow, 1, 20))), #samples)
    for i = 1, maxShow do
        local sample = samples[i]
        local spellName = GetSpellName(sample.spellID, "Spell")
        local startTime = now - (i * 0.35)
        local duration = 3 + i + (i * 0.35)
        previewInfos[i] = {
            unit = "preview" .. i,
            id = "preview" .. i,
            spellID = sample.spellID,
            spellName = spellName,
            texture = GetSpellTexture(sample.spellID, DEFAULT_ICON),
            startTime = startTime,
            duration = duration,
            durationObject = CreateDurationObject(startTime, duration),
            isChannel = i == 3,
            isPreview = true,
            notInterruptibleSecret = SecretBoolean(sample.notInterruptible),
            targetName = sample.targetName,
            hasTargetNamePlain = sample.targetName ~= nil,
            targetClassColor = i == 1 and C_ClassColor and C_ClassColor.GetClassColor(select(2, UnitClass("player"))) or nil,
            targetsPlayerNamePlain = sample.targetsPlayer,
            targetsPlayerSecret = sample.targetsPlayer,
            importantSecret = SecretBoolean(sample.important),
            levelScore = 1000 - i,
            raidTargetIndex = i == 2 and 8 or nil,
            createdAt = now,
            isCurrentTarget = false,
        }
    end
end

function CastingAlert:RenderPreview()
    if not isPreview then return end
    self:BuildPreviewInfos()
    self:RenderList(previewInfos)
end

function CastingAlert:EnterPreview()
    self:ApplyDefaults()
    self:CreateMainFrame()
    isPreview = true

    if mainFrame then
        mainFrame:Show()
    end

    if iconAnchorFrame then
        iconAnchorFrame:SetScale(NumberValue(self.db.scale, 1, 0.3, 3))
        iconAnchorFrame:EnableMouse(true)
        if ns.EnableRightClickMouselook then
            ns:EnableRightClickMouselook(iconAnchorFrame)
        end
        iconAnchorFrame:Show()
    end

    self:RenderPreview()

    if previewTicker then
        previewTicker:Cancel()
    end

    previewTicker = C_Timer.NewTicker(0.5, function()
        if isPreview then
            CastingAlert:RenderPreview()
        end
    end)
end

function CastingAlert:ExitPreview()
    if not isPreview then return end
    isPreview = false

    if previewTicker then
        previewTicker:Cancel()
        previewTicker = nil
    end

    if iconAnchorFrame then
        iconAnchorFrame:EnableMouse(false)
    end

    WipeTable(previewInfos)
    self:HideDisplayFrames()

    if isEnabled then
        self:Render()
    elseif mainFrame then
        if iconAnchorFrame then iconAnchorFrame:Hide() end
        mainFrame:Hide()
    end
end

function CastingAlert:TestMode()
    if isPreview then
        self:ExitPreview()
        print(CHAT_PREFIX .. "CastingAlert " .. T("TEST_MODE", "Test Mode") .. " OFF")
    else
        self:EnterPreview()
        print(CHAT_PREFIX .. "CastingAlert " .. T("TEST_MODE", "Test Mode") .. " ON")
    end
end

function CastingAlert:IsTestMode()
    return isPreview
end

function CastingAlert:UpdateStyle()
    self:ApplyDefaults()

    local scale = NumberValue(self.db.scale, 1, 0.3, 3)
    if iconAnchorFrame then
        iconAnchorFrame:SetScale(scale)
    end
    self:UpdateAnchorSizes()

    if isPreview then
        self:RenderPreview()
    elseif isEnabled then
        self:Render()
    end
end

function CastingAlert:UpdatePosition()
    self:UpdateIconPosition()
end

function CastingAlert:UpdateIconPosition()
    if not iconAnchorFrame then return end
    self:ApplyAnchorPosition(iconAnchorFrame, self.db.iconPosition or DEFAULTS.iconPosition)
end

function CastingAlert:ResetPosition()
    self.db.iconPosition = CopyValue(DEFAULTS.iconPosition)
    self:CreateMainFrame()
    self:UpdatePosition()
end

function CastingAlert:EnterEditPreview()
    self:EnterPreview()
end

function CastingAlert:ExitEditPreview()
    self:ExitPreview()
end

function CastingAlert:ApplySettings()
    self:ApplyDefaults()
    self:RefreshEnabledState()
    self:UpdateStyle()
end

DDingToolKit:RegisterModule("CastingAlert", CastingAlert)
