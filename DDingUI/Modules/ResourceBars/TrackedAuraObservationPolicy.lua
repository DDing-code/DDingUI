local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local Engine = DDingUI.TrackedAuraContainer
if not Engine then return end

-- Runtime policy for the 12.1 AuraContainer migration.
--
-- Supported automatic visual trackers start on the protected display path and
-- never read CDM/aura runtime values just because alert rules exist. Legacy
-- observation is re-enabled only after an AuraContainer attach/build failure,
-- which keeps BuffTrackerBar's old C_UnitAuras/CDM branches as compatibility
-- fallback instead of part of the normal automatic-aura path.

local AURA_DEPENDENT_TRIGGER = {
    active = true,
    duration = true,
    duration_percent = true,
    stacks = true,
}

local boundTrackers = setmetatable({}, { __mode = "k" })
local boundHosts = setmetatable({}, { __mode = "k" })
local fallbackTrackers = setmetatable({}, { __mode = "k" })
local visibilityQueued = setmetatable({}, { __mode = "k" })
local policySuspended = false
local diagnostics = {
    successfulBindings = 0,
    releasedBindings = 0,
    legacyReadsSuppressed = 0,
    prebindLegacyReadsSuppressed = 0,
    fallbackActivations = 0,
    fallbackReadsAllowed = 0,
    legacyDurationHandlersStopped = 0,
    hostVisibilityRestores = 0,
}

local originalAttach = Engine.Attach
local originalDetach = Engine.Detach
local originalSync = Engine.Sync
local originalSuspend = Engine.Suspend
local originalShouldReadLegacy = Engine.ShouldReadLegacy
local originalGetDiagnostics = Engine.GetDiagnostics
local originalResetDiagnostics = Engine.ResetDiagnostics

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function HasUsableID(value)
    if IsSecret(value) then return false end
    value = tonumber(value)
    return value ~= nil and value > 0
end

local function IsContainerCandidate(tracker)
    if type(tracker) ~= "table" or tracker.isGroup or tracker.enabled == false then return false end

    local displayType = tracker.displayType or "bar"
    if displayType ~= "bar" and displayType ~= "ring"
        and displayType ~= "icon" and displayType ~= "text"
    then
        return false
    end
    if displayType == "bar" and ((tracker.settings or {}).barStyle or "bar") ~= "bar" then
        return false
    end
    if displayType == "icon" and (tracker.settings or {}).showOnlyWhenInactive then
        return false
    end
    if tracker.trackingMode == "manual" or tracker.trackingMode == "spell" then return false end
    if tracker.trigger and tracker.trigger.type == "spell" then return false end
    if tracker.isAura == false then return false end

    return HasUsableID(tracker.cooldownID or (tracker.trigger and tracker.trigger.cooldownID))
        or HasUsableID(tracker.spellID or (tracker.trigger and tracker.trigger.spellID))
end

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

local function IsContainerBar(tracker)
    if type(tracker) ~= "table" then return false end
    if (tracker.displayType or "bar") ~= "bar" then return false end
    return ((tracker.settings or {}).barStyle or "bar") == "bar"
end

local function StopLegacyDurationDrivers(host)
    if not host then return end

    local driver = DDingUI.BuffTrackerDurationDriver
    local unregister = driver and driver.UnregisterOwner
    local removed = 0
    if unregister then
        removed = removed + (unregister(host) or 0)
        if host.StatusBar then
            removed = removed + (unregister(host.StatusBar) or 0)
        end
        if host.TextFrame then
            removed = removed + (unregister(host.TextFrame) or 0)
        end
    end

    host._durationData = nil
    host._auraActivatedTime = nil
    if host._hasDurationUpdate then host._hasDurationUpdate = nil end
    if host._hasRingTextUpdate then host._hasRingTextUpdate = false end

    if host.TextFrame then
        host.TextFrame._dtData = nil
        if host.TextFrame._hasDurationUpdate then
            host.TextFrame._hasDurationUpdate = nil
        end
    end

    diagnostics.legacyDurationHandlersStopped = diagnostics.legacyDurationHandlersStopped + removed
end

local function QueueHostVisibilityRestore(tracker, host)
    if not IsContainerBar(tracker) or not host then return end
    if visibilityQueued[tracker] == host then return end
    if not (C_Timer and C_Timer.After) then return end

    visibilityQueued[tracker] = host
    C_Timer.After(0, function()
        if visibilityQueued[tracker] == host then
            visibilityQueued[tracker] = nil
        end
        if not boundTrackers[tracker] or boundHosts[tracker] ~= host then return end
        if not host._auraContainerOwnsDisplay then return end
        if type(host.IsShown) ~= "function" or type(host.Show) ~= "function" then return end

        local ok, shown = pcall(host.IsShown, host)
        if ok and not shown then
            host:Show()
            diagnostics.hostVisibilityRestores = diagnostics.hostVisibilityRestores + 1
        end
    end)
end

local function ClearBinding(tracker)
    if tracker and boundTrackers[tracker] then
        boundTrackers[tracker] = nil
        boundHosts[tracker] = nil
        visibilityQueued[tracker] = nil
        diagnostics.releasedBindings = diagnostics.releasedBindings + 1
    end
end

local function MarkFallback(tracker)
    if not tracker then return end
    if not fallbackTrackers[tracker] then
        diagnostics.fallbackActivations = diagnostics.fallbackActivations + 1
    end
    fallbackTrackers[tracker] = true
end

function Engine:Attach(tracker, bar, style)
    local candidate = IsContainerCandidate(tracker) and type(style) == "table"
    local attached = originalAttach(self, tracker, bar, style)
    if tracker then
        if attached == true then
            if not boundTrackers[tracker] then
                diagnostics.successfulBindings = diagnostics.successfulBindings + 1
            end
            fallbackTrackers[tracker] = nil
            boundTrackers[tracker] = true
            boundHosts[tracker] = bar
            StopLegacyDurationDrivers(bar)
            QueueHostVisibilityRestore(tracker, bar)
        else
            ClearBinding(tracker)
            if candidate then
                MarkFallback(tracker)
            end
        end
    end
    return attached
end

function Engine:Detach(tracker, bar)
    ClearBinding(tracker)
    if tracker then fallbackTrackers[tracker] = nil end
    return originalDetach(self, tracker, bar)
end

function Engine:Sync(trackers)
    policySuspended = false
    local retained = {}
    for _, tracker in ipairs(trackers or {}) do
        retained[tracker] = true
        if not IsContainerCandidate(tracker) then
            fallbackTrackers[tracker] = nil
        end
    end

    for tracker in pairs(boundTrackers) do
        if not retained[tracker] then
            ClearBinding(tracker)
        end
    end
    for tracker in pairs(fallbackTrackers) do
        if not retained[tracker] then
            fallbackTrackers[tracker] = nil
        end
    end

    return originalSync(self, trackers)
end

function Engine:Suspend()
    policySuspended = true
    for tracker in pairs(boundTrackers) do
        ClearBinding(tracker)
    end
    for tracker in pairs(fallbackTrackers) do
        fallbackTrackers[tracker] = nil
    end
    return originalSuspend(self)
end

function Engine:ShouldReadLegacy(tracker)
    if tracker and boundTrackers[tracker] then
        diagnostics.legacyReadsSuppressed = diagnostics.legacyReadsSuppressed + 1
        return false
    end

    if not policySuspended and IsContainerCandidate(tracker) and not fallbackTrackers[tracker] then
        diagnostics.legacyReadsSuppressed = diagnostics.legacyReadsSuppressed + 1
        diagnostics.prebindLegacyReadsSuppressed = diagnostics.prebindLegacyReadsSuppressed + 1
        return false
    end

    local shouldRead = originalShouldReadLegacy(self, tracker)
    if tracker and fallbackTrackers[tracker] and shouldRead then
        diagnostics.fallbackReadsAllowed = diagnostics.fallbackReadsAllowed + 1
    end
    return shouldRead
end

function Engine:IsBound(tracker)
    return tracker ~= nil and boundTrackers[tracker] == true
end

function Engine:IsLegacyFallbackActive(tracker)
    return tracker ~= nil and fallbackTrackers[tracker] == true
end

function Engine:RequiresAuraObservation(tracker)
    return RequiresAuraObservation(tracker)
end

function Engine:GetObservationPolicyDiagnostics()
    local activeBindings = 0
    local activeFallbacks = 0
    for _ in pairs(boundTrackers) do activeBindings = activeBindings + 1 end
    for _ in pairs(fallbackTrackers) do activeFallbacks = activeFallbacks + 1 end

    return {
        activeBindings = activeBindings,
        activeFallbacks = activeFallbacks,
        successfulBindings = diagnostics.successfulBindings,
        releasedBindings = diagnostics.releasedBindings,
        legacyReadsSuppressed = diagnostics.legacyReadsSuppressed,
        prebindLegacyReadsSuppressed = diagnostics.prebindLegacyReadsSuppressed,
        fallbackActivations = diagnostics.fallbackActivations,
        fallbackReadsAllowed = diagnostics.fallbackReadsAllowed,
        legacyDurationHandlersStopped = diagnostics.legacyDurationHandlersStopped,
        hostVisibilityRestores = diagnostics.hostVisibilityRestores,
    }
end

if originalGetDiagnostics then
    function Engine:GetDiagnostics()
        local result = originalGetDiagnostics(self) or {}
        local policy = self:GetObservationPolicyDiagnostics()
        result.policyActiveBindings = policy.activeBindings
        result.policyActiveFallbacks = policy.activeFallbacks
        result.policySuccessfulBindings = policy.successfulBindings
        result.policyReleasedBindings = policy.releasedBindings
        result.policyLegacyReadsSuppressed = policy.legacyReadsSuppressed
        result.policyPrebindLegacyReadsSuppressed = policy.prebindLegacyReadsSuppressed
        result.policyFallbackActivations = policy.fallbackActivations
        result.policyFallbackReadsAllowed = policy.fallbackReadsAllowed
        result.policyLegacyDurationHandlersStopped = policy.legacyDurationHandlersStopped
        result.policyHostVisibilityRestores = policy.hostVisibilityRestores
        return result
    end
end

if originalResetDiagnostics then
    function Engine:ResetDiagnostics()
        originalResetDiagnostics(self)
        for key in pairs(diagnostics) do
            diagnostics[key] = 0
        end
    end
end
