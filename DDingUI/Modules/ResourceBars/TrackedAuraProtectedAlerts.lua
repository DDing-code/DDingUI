local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local ResourceBars = DDingUI.ResourceBars
local Engine = DDingUI.TrackedAuraContainer
if not ResourceBars or not Engine or not Engine.IsBound then return end

-- AuraContainer intentionally owns protected aura state in 12.1. The addon may
-- bind that state to approved visual sinks, but it must not infer the same state
-- again through legacy CDM/aura reads just to drive arbitrary alert actions.
--
-- For a container-owned tracker we therefore remove aura-dependent triggers
-- from the alert evaluation view. Explicit actions bound to non-aura triggers
-- (currently combat, plus any future non-aura trigger types) are preserved and
-- their trigger indexes are remapped. Combined `any` actions are suppressed when
-- protected triggers are present because their truth value is no longer fully
-- observable without risking false positives.

local AURA_DEPENDENT_TRIGGER = {
    active = true,
    duration = true,
    duration_percent = true,
    stacks = true,
}

local diagnostics = {
    filteredEvaluations = 0,
    protectedTriggersSuppressed = 0,
    protectedActionsSuppressed = 0,
    safeActionsRetained = 0,
}
local reportedSignatures = setmetatable({}, { __mode = "k" })

local function ShallowCopy(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

local function BuildSafeAlerts(tracker, alerts)
    if type(alerts) ~= "table" or alerts.enabled ~= true then return alerts end

    local originalTriggers = alerts.triggers or {}
    local safeTriggers = {}
    local triggerIndexMap = {}
    local protectedIndexes = {}

    for index, trigger in ipairs(originalTriggers) do
        if type(trigger) == "table" and AURA_DEPENDENT_TRIGGER[trigger.type] then
            protectedIndexes[#protectedIndexes + 1] = index
        else
            safeTriggers[#safeTriggers + 1] = trigger
            triggerIndexMap[index] = #safeTriggers
        end
    end

    if #protectedIndexes == 0 then return alerts end

    local safeActions = {}
    local suppressedActions = 0
    for _, action in ipairs(alerts.actions or {}) do
        local condition = action and action.condition
        local originalIndex = type(condition) == "string" and tonumber(condition:match("^trigger(%d+)$")) or nil
        local mappedIndex = originalIndex and triggerIndexMap[originalIndex] or nil

        if mappedIndex then
            local safeAction = ShallowCopy(action)
            safeAction.condition = "trigger" .. mappedIndex
            safeActions[#safeActions + 1] = safeAction
        else
            -- `any` depends on the combined result. Once one of its inputs is
            -- protected we cannot prove the combined state for all trigger
            -- logics, so suppress it rather than guessing.
            suppressedActions = suppressedActions + 1
        end
    end

    diagnostics.filteredEvaluations = diagnostics.filteredEvaluations + 1

    local signature = table.concat(protectedIndexes, ",") .. ":" .. suppressedActions .. ":" .. #safeActions
    if reportedSignatures[tracker] ~= signature then
        reportedSignatures[tracker] = signature
        diagnostics.protectedTriggersSuppressed = diagnostics.protectedTriggersSuppressed + #protectedIndexes
        diagnostics.protectedActionsSuppressed = diagnostics.protectedActionsSuppressed + suppressedActions
        diagnostics.safeActionsRetained = diagnostics.safeActionsRetained + #safeActions
    end

    local safeAlerts = ShallowCopy(alerts)
    safeAlerts.triggers = safeTriggers
    safeAlerts.actions = safeActions
    return safeAlerts
end

local function CallWithProtectedAlertsFiltered(original, self, barIndex, tracker, globalCfg)
    if not tracker or not Engine:IsBound(tracker) then
        return original(self, barIndex, tracker, globalCfg)
    end

    local settings = tracker.settings
    local alerts = settings and settings.alerts
    local safeAlerts = BuildSafeAlerts(tracker, alerts)
    if not settings or safeAlerts == alerts then
        return original(self, barIndex, tracker, globalCfg)
    end

    -- The runtime update methods are synchronous. Expose only the safe alert
    -- view during this call, then restore the SavedVariables-backed table.
    settings.alerts = safeAlerts
    local result = original(self, barIndex, tracker, globalCfg)
    settings.alerts = alerts
    return result
end

local function Wrap(methodName)
    local original = ResourceBars[methodName]
    if type(original) ~= "function" then return end

    ResourceBars[methodName] = function(self, barIndex, tracker, globalCfg)
        return CallWithProtectedAlertsFiltered(original, self, barIndex, tracker, globalCfg)
    end
end

Wrap("UpdateSingleTrackedBuffBar")
Wrap("UpdateSingleTrackedBuffRing")
Wrap("UpdateSingleTrackedBuffIcon")
Wrap("UpdateSingleTrackedBuffText")

function Engine:GetProtectedAlertDiagnostics()
    local result = {}
    for key, value in pairs(diagnostics) do
        result[key] = value
    end
    return result
end

local originalGetDiagnostics = Engine.GetDiagnostics
if originalGetDiagnostics then
    function Engine:GetDiagnostics()
        local result = originalGetDiagnostics(self) or {}
        local protected = self:GetProtectedAlertDiagnostics()
        result.protectedAlertFilteredEvaluations = protected.filteredEvaluations
        result.protectedAlertTriggersSuppressed = protected.protectedTriggersSuppressed
        result.protectedAlertActionsSuppressed = protected.protectedActionsSuppressed
        result.protectedAlertSafeActionsRetained = protected.safeActionsRetained
        return result
    end
end

local originalResetDiagnostics = Engine.ResetDiagnostics
if originalResetDiagnostics then
    function Engine:ResetDiagnostics()
        originalResetDiagnostics(self)
        diagnostics.filteredEvaluations = 0
        diagnostics.protectedTriggersSuppressed = 0
        diagnostics.protectedActionsSuppressed = 0
        diagnostics.safeActionsRetained = 0
        wipe(reportedSignatures)
    end
end
