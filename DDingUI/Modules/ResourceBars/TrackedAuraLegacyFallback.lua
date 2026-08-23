local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local Engine = DDingUI.TrackedAuraContainer
if not Engine then return end

-- Compatibility boundary for BuffTracker's pre-AuraContainer runtime.
--
-- Supported automatic visual trackers stay on the protected AuraContainer path
-- from the first update pass. The old CDM/C_UnitAuras observation path is
-- enabled only after an actual AuraContainer attach/build failure. Keeping that
-- state in this module makes legacy fallback explicit and removable after client
-- validation instead of mixing it into the normal binding policy.

local fallbackTrackers = setmetatable({}, { __mode = "k" })
local policySuspended = false
local diagnostics = {
    legacyReadsSuppressed = 0,
    prebindLegacyReadsSuppressed = 0,
    fallbackActivations = 0,
    fallbackReadsAllowed = 0,
    legacyDurationHandlersStopped = 0,
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
    if Engine.IsSupportedAuraTracker then
        return Engine:IsSupportedAuraTracker(tracker)
    end
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

    local trigger = tracker.trigger
    return HasUsableID(tracker.cooldownID)
        or HasUsableID(trigger and trigger.cooldownID)
        or HasUsableID(tracker.spellID)
        or HasUsableID(trigger and trigger.spellID)
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

    -- Older fallback passes can leave permanent secure hooks on the legacy
    -- Cooldown widget. Hiding the widget makes those hooks inert while the
    -- AuraContainer-owned proxy remains authoritative.
    if host.Cooldown and type(host.Cooldown.Hide) == "function" then
        host.Cooldown:Hide()
    end

    if host.TextFrame then
        host.TextFrame._dtData = nil
        if host.TextFrame._hasDurationUpdate then
            host.TextFrame._hasDurationUpdate = nil
        end
    end

    diagnostics.legacyDurationHandlersStopped = diagnostics.legacyDurationHandlersStopped + removed
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
            fallbackTrackers[tracker] = nil
            StopLegacyDurationDrivers(bar)
        elseif candidate and not (self.IsBuildDeferred and self:IsBuildDeferred(tracker)) then
            MarkFallback(tracker)
        end
    end
    return attached
end

function Engine:Detach(tracker, bar)
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

    for tracker in pairs(fallbackTrackers) do
        if not retained[tracker] then
            fallbackTrackers[tracker] = nil
        end
    end

    return originalSync(self, trackers)
end

function Engine:Suspend()
    policySuspended = true
    for tracker in pairs(fallbackTrackers) do
        fallbackTrackers[tracker] = nil
    end
    return originalSuspend(self)
end

function Engine:ShouldReadLegacy(tracker)
    if not policySuspended and IsContainerCandidate(tracker) and not fallbackTrackers[tracker] then
        diagnostics.legacyReadsSuppressed = diagnostics.legacyReadsSuppressed + 1
        diagnostics.prebindLegacyReadsSuppressed = diagnostics.prebindLegacyReadsSuppressed + 1
        return false
    end

    local shouldRead = originalShouldReadLegacy(self, tracker)
    if tracker and fallbackTrackers[tracker] and shouldRead then
        diagnostics.fallbackReadsAllowed = diagnostics.fallbackReadsAllowed + 1
    elseif tracker and self.IsBound and self:IsBound(tracker) and not shouldRead then
        diagnostics.legacyReadsSuppressed = diagnostics.legacyReadsSuppressed + 1
    end
    return shouldRead
end

function Engine:IsContainerCandidate(tracker)
    return IsContainerCandidate(tracker)
end

function Engine:IsLegacyFallbackActive(tracker)
    return tracker ~= nil and fallbackTrackers[tracker] == true
end

-- True while a supported automatic visual tracker is expected to be rendered
-- exclusively through AuraContainer. This includes the initial pre-bind pass.
function Engine:IsProtectedDisplayPath(tracker)
    return tracker ~= nil
        and not policySuspended
        and IsContainerCandidate(tracker)
        and fallbackTrackers[tracker] ~= true
end

function Engine:GetLegacyFallbackDiagnostics()
    local activeFallbacks = 0
    for _ in pairs(fallbackTrackers) do activeFallbacks = activeFallbacks + 1 end

    return {
        activeFallbacks = activeFallbacks,
        legacyReadsSuppressed = diagnostics.legacyReadsSuppressed,
        prebindLegacyReadsSuppressed = diagnostics.prebindLegacyReadsSuppressed,
        fallbackActivations = diagnostics.fallbackActivations,
        fallbackReadsAllowed = diagnostics.fallbackReadsAllowed,
        legacyDurationHandlersStopped = diagnostics.legacyDurationHandlersStopped,
        suspended = policySuspended,
    }
end

if originalGetDiagnostics then
    function Engine:GetDiagnostics()
        local result = originalGetDiagnostics(self) or {}
        local fallback = self:GetLegacyFallbackDiagnostics()
        result.policyActiveFallbacks = fallback.activeFallbacks
        result.policyLegacyReadsSuppressed = fallback.legacyReadsSuppressed
        result.policyPrebindLegacyReadsSuppressed = fallback.prebindLegacyReadsSuppressed
        result.policyFallbackActivations = fallback.fallbackActivations
        result.policyFallbackReadsAllowed = fallback.fallbackReadsAllowed
        result.policyLegacyDurationHandlersStopped = fallback.legacyDurationHandlersStopped
        result.policyFallbackSuspended = fallback.suspended
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
