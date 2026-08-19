local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local ResourceBars = DDingUI.ResourceBars
local Engine = DDingUI.TrackedAuraContainer
if not ResourceBars or not Engine then return end

-- Protected automatic auras cannot expose their active/stacks/duration state to
-- ordinary addon Lua. A narrow visual case is still representable without
-- observing that state: if an alert means exactly "this aura is present" and
-- its action is a self glow, the glow can be styled onto the AuraContainer
-- AuraButton itself. The button's secure visibility then owns the condition.
--
-- This bridge runs outside TrackedAuraProtectedAlerts so it can inspect the
-- SavedVariables-backed alert definition before that module temporarily removes
-- protected triggers/actions from legacy Lua evaluation.

local diagnostics = {
    eligibleEvaluations = 0,
    appliedOverrides = 0,
}

local OVERRIDE_FIELDS = {
    "iconAnimation",
    "glowColor",
    "glowLines",
    "glowFrequency",
    "glowThickness",
    "glowXOffset",
    "glowYOffset",
    "glowWhenInactive",
}

local function ActiveTriggerMeansAuraPresent(trigger)
    if type(trigger) ~= "table" or trigger.type ~= "active" then
        return false
    end

    local op = trigger.op or "=="
    if op == "==" then
        return trigger.value == true
    elseif op == "!=" then
        return trigger.value == false
    end
    return false
end

local function AllTriggersMeanAuraPresent(alerts)
    local triggers = alerts and alerts.triggers or {}
    if #triggers == 0 then return false end

    for _, trigger in ipairs(triggers) do
        if not ActiveTriggerMeansAuraPresent(trigger) then
            return false
        end
    end
    return true
end

local function ConditionMeansAuraPresent(alerts, condition)
    if condition == "any" then
        -- With only aura-present predicates, both AND and OR collapse to the
        -- same condition: the tracked aura is present. The default single
        -- active trigger + `any` action therefore remains supported.
        return AllTriggersMeanAuraPresent(alerts)
    end

    local triggerIndex = type(condition) == "string"
        and tonumber(condition:match("^trigger(%d+)$")) or nil
    if not triggerIndex then return false end

    local trigger = alerts and alerts.triggers and alerts.triggers[triggerIndex]
    return ActiveTriggerMeansAuraPresent(trigger)
end

local function ResolveProtectedSelfGlow(tracker)
    local settings = tracker and tracker.settings
    local alerts = settings and settings.alerts
    if type(alerts) ~= "table" or alerts.enabled ~= true then return nil end

    local selected
    for _, action in ipairs(alerts.actions or {}) do
        if type(action) == "table"
            and action.type == "glow"
            and (action.visualTarget == nil or action.visualTarget == "self")
            and ConditionMeansAuraPresent(alerts, action.condition)
        then
            -- Match ApplyAlertActions' last-matching-action behavior.
            selected = action
        end
    end
    return selected
end

local function IsProtectedIconPath(tracker)
    if not tracker or (tracker.displayType or "bar") ~= "icon" then return false end
    if Engine.IsProtectedDisplayPath then
        return Engine:IsProtectedDisplayPath(tracker)
    end
    return Engine.IsBound and Engine:IsBound(tracker) or false
end

local function CallWithProtectedSelfGlow(original, self, barIndex, tracker, globalCfg)
    if not IsProtectedIconPath(tracker) then
        return original(self, barIndex, tracker, globalCfg)
    end

    diagnostics.eligibleEvaluations = diagnostics.eligibleEvaluations + 1

    local action = ResolveProtectedSelfGlow(tracker)
    if not action then
        return original(self, barIndex, tracker, globalCfg)
    end

    local settings = tracker.settings
    local saved = {}
    local present = {}
    for _, field in ipairs(OVERRIDE_FIELDS) do
        present[field] = settings[field] ~= nil
        saved[field] = settings[field]
    end

    -- TrackedAuraContainer copies these presentation settings into the secure
    -- AuraButton initializer. No protected aura value is read here.
    settings.iconAnimation = action.glowType or "pixel"
    settings.glowColor = action.glowColor or { 1, 0.82, 0.1, 1 }
    settings.glowLines = action.glowLines or 8
    settings.glowFrequency = action.glowFrequency or 0.25
    settings.glowThickness = action.glowThickness or 2
    settings.glowXOffset = action.glowXOffset or 0
    settings.glowYOffset = action.glowYOffset or 0
    settings.glowWhenInactive = false

    local ok, result1, result2, result3 = pcall(original, self, barIndex, tracker, globalCfg)

    for _, field in ipairs(OVERRIDE_FIELDS) do
        if present[field] then
            settings[field] = saved[field]
        else
            settings[field] = nil
        end
    end

    if not ok then
        error(result1, 0)
    end

    diagnostics.appliedOverrides = diagnostics.appliedOverrides + 1
    return result1, result2, result3
end

local originalUpdateIcon = ResourceBars.UpdateSingleTrackedBuffIcon
if type(originalUpdateIcon) == "function" then
    ResourceBars.UpdateSingleTrackedBuffIcon = function(self, barIndex, tracker, globalCfg)
        return CallWithProtectedSelfGlow(originalUpdateIcon, self, barIndex, tracker, globalCfg)
    end
end

function Engine:GetProtectedGlowDiagnostics()
    return {
        eligibleEvaluations = diagnostics.eligibleEvaluations,
        appliedOverrides = diagnostics.appliedOverrides,
    }
end
