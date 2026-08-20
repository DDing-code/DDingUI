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

local function IsProtectedVisualPath(tracker)
    if not tracker then return false end
    local displayType = tracker.displayType or "bar"
    if displayType ~= "bar" and displayType ~= "ring"
        and displayType ~= "icon" and displayType ~= "text"
    then
        return false
    end
    if Engine.IsProtectedDisplayPath then
        return Engine:IsProtectedDisplayPath(tracker)
    end
    return Engine.IsBound and Engine:IsBound(tracker) or false
end

local function CallWithProtectedSelfGlow(original, self, barIndex, tracker, globalCfg)
    if not IsProtectedVisualPath(tracker) then
        return original(self, barIndex, tracker, globalCfg)
    end

    diagnostics.eligibleEvaluations = diagnostics.eligibleEvaluations + 1

    local action = ResolveProtectedSelfGlow(tracker)
    if not action then
        return original(self, barIndex, tracker, globalCfg)
    end

    Engine:SetActiveGlowOverride(tracker, action)
    local ok, result1, result2, result3 = pcall(original, self, barIndex, tracker, globalCfg)
    Engine:ClearActiveGlowOverride(tracker)

    if not ok then
        error(result1, 0)
    end

    diagnostics.appliedOverrides = diagnostics.appliedOverrides + 1
    return result1, result2, result3
end

local function Wrap(methodName)
    local original = ResourceBars[methodName]
    if type(original) == "function" then
        ResourceBars[methodName] = function(self, barIndex, tracker, globalCfg)
            return CallWithProtectedSelfGlow(original, self, barIndex, tracker, globalCfg)
        end
    end
end

Wrap("UpdateSingleTrackedBuffBar")
Wrap("UpdateSingleTrackedBuffRing")
Wrap("UpdateSingleTrackedBuffIcon")
Wrap("UpdateSingleTrackedBuffText")

function Engine:GetProtectedGlowDiagnostics()
    return {
        eligibleEvaluations = diagnostics.eligibleEvaluations,
        appliedOverrides = diagnostics.appliedOverrides,
    }
end
