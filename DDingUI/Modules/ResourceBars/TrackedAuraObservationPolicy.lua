local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local Engine = DDingUI.TrackedAuraContainer
if not Engine then return end

-- Transitional policy layer for the 12.1 AuraContainer migration.
--
-- Once an automatic tracker is successfully owned by AuraContainer, legacy
-- CDM/aura observation must stop. Protected aura values are display-only in
-- 12.1; alert logic that depends on those values is handled separately by
-- TrackedAuraProtectedAlerts.lua and must not keep the legacy resolver alive.

local AURA_DEPENDENT_TRIGGER = {
    active = true,
    duration = true,
    duration_percent = true,
    stacks = true,
}

local boundTrackers = setmetatable({}, { __mode = "k" })
local diagnostics = {
    successfulBindings = 0,
    releasedBindings = 0,
    legacyReadsSuppressed = 0,
}

local originalAttach = Engine.Attach
local originalDetach = Engine.Detach
local originalSync = Engine.Sync
local originalSuspend = Engine.Suspend
local originalShouldReadLegacy = Engine.ShouldReadLegacy
local originalGetDiagnostics = Engine.GetDiagnostics
local originalResetDiagnostics = Engine.ResetDiagnostics

local function RequiresAuraObservation(tracker)
    local alerts = tracker and tracker.settings and tracker.settings.alerts
    if not alerts or alerts.enabled ~= true then return false end

    for _, trigger in ipairs(alerts.triggers or {}) do
        if type(trigger) == "table" and AURA_DEPENDENT_TRIGGER[trigger.type] then
            return true
        end
    end
    return false
end

local function ClearBinding(tracker)
    if tracker and boundTrackers[tracker] then
        boundTrackers[tracker] = nil
        diagnostics.releasedBindings = diagnostics.releasedBindings + 1
    end
end

function Engine:Attach(tracker, bar, style)
    local attached = originalAttach(self, tracker, bar, style)
    if tracker then
        if attached == true then
            if not boundTrackers[tracker] then
                diagnostics.successfulBindings = diagnostics.successfulBindings + 1
            end
            boundTrackers[tracker] = true
        else
            ClearBinding(tracker)
        end
    end
    return attached
end

function Engine:Detach(tracker, bar)
    ClearBinding(tracker)
    return originalDetach(self, tracker, bar)
end

function Engine:Sync(trackers)
    local retained = {}
    for _, tracker in ipairs(trackers or {}) do
        retained[tracker] = true
    end

    for tracker in pairs(boundTrackers) do
        if not retained[tracker] then
            ClearBinding(tracker)
        end
    end

    return originalSync(self, trackers)
end

function Engine:Suspend()
    for tracker in pairs(boundTrackers) do
        ClearBinding(tracker)
    end
    return originalSuspend(self)
end

function Engine:ShouldReadLegacy(tracker)
    if tracker and boundTrackers[tracker] then
        diagnostics.legacyReadsSuppressed = diagnostics.legacyReadsSuppressed + 1
        return false
    end
    return originalShouldReadLegacy(self, tracker)
end

function Engine:IsBound(tracker)
    return tracker ~= nil and boundTrackers[tracker] == true
end

function Engine:RequiresAuraObservation(tracker)
    return RequiresAuraObservation(tracker)
end

function Engine:GetObservationPolicyDiagnostics()
    local activeBindings = 0
    for _ in pairs(boundTrackers) do
        activeBindings = activeBindings + 1
    end

    return {
        activeBindings = activeBindings,
        successfulBindings = diagnostics.successfulBindings,
        releasedBindings = diagnostics.releasedBindings,
        legacyReadsSuppressed = diagnostics.legacyReadsSuppressed,
    }
end

if originalGetDiagnostics then
    function Engine:GetDiagnostics()
        local result = originalGetDiagnostics(self) or {}
        local policy = self:GetObservationPolicyDiagnostics()
        result.policyActiveBindings = policy.activeBindings
        result.policySuccessfulBindings = policy.successfulBindings
        result.policyReleasedBindings = policy.releasedBindings
        result.policyLegacyReadsSuppressed = policy.legacyReadsSuppressed
        return result
    end
end

if originalResetDiagnostics then
    function Engine:ResetDiagnostics()
        originalResetDiagnostics(self)
        diagnostics.successfulBindings = 0
        diagnostics.releasedBindings = 0
        diagnostics.legacyReadsSuppressed = 0
    end
end
