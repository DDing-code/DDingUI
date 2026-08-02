local _, ns = ...
local DDingUI = ns and (ns.Addon or ns.DDingUI)
if not DDingUI then return end

local ExternalBuffDetection = {}
DDingUI.ExternalBuffDetection = ExternalBuffDetection

local INNERVATE_ID = 29166
local SPATIAL_PARADOX_ID = 406732
local POLL_INTERVAL = 0.1
local FALSE_CONFIRM_COUNT = 2

local SPATIAL_BY_SPEC = {
    [256] = { 47540, 80 },
    [257] = { 2050, 80 },
    [65] = { 20473, 80 },
    [270] = { 115151, 80 },
    [105] = { 774, 80 },
    [264] = { 61295, 80 },
    [1468] = { 364343, 60 },
    [1473] = { 409311, 60 },
    [1467] = { 361469, 50 },
}

local INNERVATE_BY_SPEC = {
    [256] = { 47540 },
    [257] = { 2050, 33076 },
    [65] = { 20473 },
    [270] = { 115151 },
    [105] = { 774 },
    [264] = { 61295 },
    [1468] = { 364343, 361469 },
}

local trackers = {
    [INNERVATE_ID] = {
        duration = 7.8,
        grace = 9,
        configured = false,
        active = false,
        falsePolls = 0,
        zeroPolls = 0,
        lastTriggerAt = 0,
    },
    [SPATIAL_PARADOX_ID] = {
        duration = 10,
        grace = 15,
        configured = false,
        active = false,
        falsePolls = 0,
        lastTriggerAt = 0,
    },
}

local currentSpecID
local spatialSpellID
local spatialRangeThreshold
local innervateSpellIDs
local pollTicker
local refreshQueued = false
local forceResetQueued = false

local function IsAccessibleValue(value)
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return true
end

local function SafeNumber(value)
    if not IsAccessibleValue(value) then return nil end
    local valueType = type(value)
    if valueType == "number" then return value end
    if valueType == "string" then return tonumber(value) end
    return nil
end

local function GetCurrentSpecID()
    if not (GetSpecialization and GetSpecializationInfo) then return nil end
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    return SafeNumber(GetSpecializationInfo(specIndex))
end

local function ResolveSpellTexture(spellID)
    if not C_Spell then return nil end
    if C_Spell.GetSpellTexture then
        local texture = C_Spell.GetSpellTexture(spellID)
        if IsAccessibleValue(texture) and texture and texture ~= 0 then
            return texture
        end
    end
    if C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        local texture = info and info.iconID
        if IsAccessibleValue(texture) and texture and texture ~= 0 then
            return texture
        end
    end
    return nil
end

local function StopTracker(stateID)
    local tracker = trackers[stateID]
    if not tracker then return end
    if tracker.active then
        local customIcons = DDingUI.CustomIcons
        if customIcons and customIcons.DeactivateExternalTimedAura then
            customIcons:DeactivateExternalTimedAura(stateID)
        end
    end
    tracker.active = false
    tracker.falsePolls = 0
    tracker.zeroPolls = 0
end

local function StartTracker(stateID, now)
    local tracker = trackers[stateID]
    local customIcons = DDingUI.CustomIcons
    if not tracker or not customIcons or not customIcons.ActivateExternalTimedAura then return end

    customIcons:ActivateExternalTimedAura(
        stateID,
        tracker.duration,
        ResolveSpellTexture(stateID),
        nil,
        now
    )
    tracker.active = true
    tracker.falsePolls = 0
    tracker.zeroPolls = 0
    tracker.lastTriggerAt = now
end

local function IsSpatialActive()
    if not spatialSpellID or not C_Spell or not C_Spell.GetSpellInfo then return false end
    local info = C_Spell.GetSpellInfo(spatialSpellID)
    local maxRange = info and SafeNumber(info.maxRange)
    return maxRange ~= nil and maxRange >= spatialRangeThreshold
end

local function IsInnervateActive()
    if not innervateSpellIDs or not C_Spell or not C_Spell.GetSpellPowerCost then return false end
    for index = 1, #innervateSpellIDs do
        local costs = C_Spell.GetSpellPowerCost(innervateSpellIDs[index])
        local first = costs and costs[1]
        local cost = first and SafeNumber(first.cost)
        if cost == nil or cost ~= 0 then
            return false
        end
    end
    return true
end

local function PollActiveTracker(stateID, isActive)
    local tracker = trackers[stateID]
    if isActive then
        tracker.falsePolls = 0
        return
    end
    tracker.falsePolls = tracker.falsePolls + 1
    if tracker.falsePolls >= FALSE_CONFIRM_COUNT then
        StopTracker(stateID)
    end
end

local function PollInnervate(now)
    local tracker = trackers[INNERVATE_ID]
    local active = IsInnervateActive()
    if tracker.active then
        PollActiveTracker(INNERVATE_ID, active)
        return
    end
    if now - tracker.lastTriggerAt < tracker.grace then return end
    if active then
        tracker.zeroPolls = tracker.zeroPolls + 1
        if tracker.zeroPolls >= FALSE_CONFIRM_COUNT then
            StartTracker(INNERVATE_ID, now)
        end
    else
        tracker.zeroPolls = 0
    end
end

local function PollSpatialParadox(now)
    local tracker = trackers[SPATIAL_PARADOX_ID]
    local active = IsSpatialActive()
    if tracker.active then
        PollActiveTracker(SPATIAL_PARADOX_ID, active)
        return
    end
    if now - tracker.lastTriggerAt < tracker.grace then return end
    if active then
        StartTracker(SPATIAL_PARADOX_ID, now)
    end
end

local function PollAll()
    local now = GetTime()
    if trackers[INNERVATE_ID].configured and innervateSpellIDs then
        PollInnervate(now)
    end
    if trackers[SPATIAL_PARADOX_ID].configured and spatialSpellID then
        PollSpatialParadox(now)
    end
end

local function StopPolling()
    if pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
    end
end

local function RefreshPolling()
    local shouldPoll = (trackers[INNERVATE_ID].configured and innervateSpellIDs ~= nil)
        or (trackers[SPATIAL_PARADOX_ID].configured and spatialSpellID ~= nil)
    if shouldPoll and not pollTicker then
        pollTicker = C_Timer.NewTicker(POLL_INTERVAL, PollAll)
    elseif not shouldPoll then
        StopPolling()
    end
end

local function RefreshConfiguredIcons()
    local foundInnervate = false
    local foundSpatial = false
    local profile = DDingUI.db and DDingUI.db.profile
    local dynamicIcons = profile and profile.dynamicIcons
    local iconDataByKey = dynamicIcons and dynamicIcons.iconData

    for _, iconData in pairs(type(iconDataByKey) == "table" and iconDataByKey or {}) do
        if type(iconData) == "table" and iconData.type == "aura" then
            local settings = type(iconData.settings) == "table" and iconData.settings or nil
            local stateID = SafeNumber(settings and settings.customAuraStateID) or SafeNumber(iconData.id)
            if stateID == INNERVATE_ID then
                foundInnervate = true
            elseif stateID == SPATIAL_PARADOX_ID then
                foundSpatial = true
            end
        end
    end

    local innervate = trackers[INNERVATE_ID]
    local spatial = trackers[SPATIAL_PARADOX_ID]
    if innervate.configured and not foundInnervate then StopTracker(INNERVATE_ID) end
    if spatial.configured and not foundSpatial then StopTracker(SPATIAL_PARADOX_ID) end
    innervate.configured = foundInnervate
    spatial.configured = foundSpatial
end

local function ResolveSpecState(specID)
    currentSpecID = specID
    local spatial = specID and SPATIAL_BY_SPEC[specID]
    spatialSpellID = spatial and spatial[1] or nil
    spatialRangeThreshold = spatial and spatial[2] or nil
    innervateSpellIDs = specID and INNERVATE_BY_SPEC[specID] or nil
end

function ExternalBuffDetection:Refresh(forceReset)
    local specID = GetCurrentSpecID()
    if forceReset or specID ~= currentSpecID then
        StopPolling()
        StopTracker(INNERVATE_ID)
        StopTracker(SPATIAL_PARADOX_ID)
        ResolveSpecState(specID)
    end
    RefreshConfiguredIcons()
    RefreshPolling()
end

local function QueueRefresh(forceReset)
    forceResetQueued = forceResetQueued or forceReset == true
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        local reset = forceResetQueued
        forceResetQueued = false
        ExternalBuffDetection:Refresh(reset)
    end)
end

local function QueueConfiguredRefresh()
    QueueRefresh(false)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED" and unit and unit ~= "player" then return end
    QueueRefresh(true)
end)

if DDingUI.CustomIcons and hooksecurefunc then
    hooksecurefunc(DDingUI.CustomIcons, "AddDynamicIcon", QueueConfiguredRefresh)
    hooksecurefunc(DDingUI.CustomIcons, "RemoveDynamicIcon", QueueConfiguredRefresh)
    hooksecurefunc(DDingUI.CustomIcons, "LoadDynamicIcons", QueueConfiguredRefresh)
end

if IsLoggedIn and IsLoggedIn() then
    QueueRefresh(true)
end
