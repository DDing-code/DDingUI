local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

-- Legacy duration/cooldown access for BuffTracker compatibility paths.
--
-- Automatic 12.1 aura displays are owned by TrackedAuraContainer. This module
-- centralizes the remaining direct C_UnitAuras/CDM duration reads that are only
-- allowed after the protected path falls back (or for manual/legacy displays).
-- Keeping these reads here prevents BuffTrackerBar presentation code from
-- owning protected aura timing implementation details.

local AuraDriver = DDingUI.TrackedAuraLegacyFallbackDriver
if not AuraDriver then
    error("DDingUI: TrackedAuraLegacyFallbackDriver must load before TrackedAuraLegacyDurationDriver.lua")
end

local Driver = {}
DDingUI.TrackedAuraLegacyDurationDriver = Driver

local C_UnitAuras = C_UnitAuras
local GetTime = GetTime
local pcall = pcall
local pairs = pairs
local type = type

local ringTargets = setmetatable({}, { __mode = "k" })
local targetSources = setmetatable({}, { __mode = "k" })

local function IsPositivePlainNumber(value)
    return AuraDriver.IsAccessibleNumber(value) and value > 0
end

local function IsProtectedNumber(value)
    if AuraDriver.IsSecretValue(value) then return true end
    return type(value) == "number" and not AuraDriver.IsAccessibleNumber(value)
end

function Driver.ReadTiming(unit, auraInstanceID)
    if not AuraDriver.HasAuraInstanceID(auraInstanceID)
        or not C_UnitAuras or not C_UnitAuras.GetAuraDataByAuraInstanceID
    then
        return nil, nil, nil, false
    end

    local duration, expirationTime, remaining
    local protected = false
    local ok = pcall(function()
        local auraData = AuraDriver.GetAuraDataByInstance(unit or "player", auraInstanceID)
        if not AuraDriver.HasAuraResult(auraData) then return end
        if AuraDriver.IsSecretValue(auraData) then
            protected = true
            return
        end

        local rawDuration = auraData.duration
        local rawExpirationTime = auraData.expirationTime
        if IsProtectedNumber(rawDuration) or IsProtectedNumber(rawExpirationTime) then
            protected = true
            return
        end

        if IsPositivePlainNumber(rawDuration) then
            duration = rawDuration
        end
        if IsPositivePlainNumber(rawExpirationTime) then
            expirationTime = rawExpirationTime
        end
        if expirationTime then
            remaining = expirationTime - GetTime()
            if remaining < 0 then remaining = 0 end
        end
    end)
    if not ok then
        return nil, nil, nil, true
    end
    return duration, expirationTime, remaining, protected
end

-- GetAuraDuration may return a protected number. Do not inspect it here; callers
-- may pass it only to Blizzard-approved display sinks or keep comparisons inside
-- their existing guarded compatibility code.
function Driver.GetRemainingDuration(unit, auraInstanceID)
    if not AuraDriver.HasAuraInstanceID(auraInstanceID)
        or not C_UnitAuras or not C_UnitAuras.GetAuraDuration
    then
        return nil
    end

    local remaining
    local ok = pcall(function()
        local durationObject = C_UnitAuras.GetAuraDuration(unit or "player", auraInstanceID)
        if durationObject and durationObject.GetRemainingDuration then
            remaining = durationObject:GetRemainingDuration()
        end
    end)
    if not ok then return nil end
    return remaining
end

function Driver.HasRemainingDurationValue(value)
    if AuraDriver.IsSecretValue(value) then return true end
    return value ~= nil
end

function Driver.GetTimeLeft(unit, auraInstanceID, now)
    local _, expirationTime = Driver.ReadTiming(unit, auraInstanceID)
    if not expirationTime then return nil end
    local remaining = expirationTime - (now or GetTime())
    if remaining < 0 then remaining = 0 end
    return remaining
end

function Driver.ResolveDynamicDuration(frame, unit, auraInstanceID, settings, fallbackDuration, hasData, isManualMode, skipWhenSourceBar)
    local cached = settings and settings._detectedDuration
    if not hasData or isManualMode then
        return cached or fallbackDuration
    end

    if skipWhenSourceBar and frame and frame.Bar
        and frame.Bar.GetMinMaxValues and frame.Bar.GetValue
    then
        return cached or fallbackDuration
    end

    local detectedDuration
    if frame then
        pcall(function()
            if frame.Bar and frame.Bar.GetMinMaxValues then
                local _, maxValue = frame.Bar:GetMinMaxValues()
                if IsPositivePlainNumber(maxValue) then
                    detectedDuration = maxValue
                end
            end
            if not detectedDuration and frame.GetMinMaxValues then
                local _, maxValue = frame:GetMinMaxValues()
                if IsPositivePlainNumber(maxValue) then
                    detectedDuration = maxValue
                end
            end
        end)
    end

    if not detectedDuration then
        local duration = Driver.ReadTiming(unit, auraInstanceID)
        if duration then detectedDuration = duration end
    end

    if detectedDuration then
        if settings then settings._detectedDuration = detectedDuration end
        return detectedDuration
    end
    return cached or fallbackDuration
end

function Driver.SyncAuraCooldown(cooldown, owner, cacheField, unit, auraInstanceID)
    if not cooldown then return false end

    if not AuraDriver.HasAuraInstanceID(auraInstanceID) then
        if cooldown.Clear then cooldown:Clear() end
        if owner and cacheField then owner[cacheField] = nil end
        return false
    end

    local cacheKey = AuraDriver.GetAuraInstanceCacheKey(auraInstanceID)
    if owner and cacheField then
        if owner[cacheField] ~= cacheKey and cooldown.Clear then
            cooldown:Clear()
        end
        owner[cacheField] = cacheKey
    end

    local duration, expirationTime = Driver.ReadTiming(unit, auraInstanceID)
    if duration and expirationTime and cooldown.SetCooldown then
        local ok = pcall(cooldown.SetCooldown, cooldown, expirationTime - duration, duration)
        if ok then return true end
    end

    if cooldown.Clear then cooldown:Clear() end
    return false
end

function Driver.MirrorProgress(sourceFrame, targetStatusBar, targetText, showText)
    local resolver = DDingUI.TrackedAuraFrameResolver
    if not sourceFrame or not resolver or not resolver.MirrorProgress then
        return false, false
    end
    return resolver:MirrorProgress(sourceFrame, targetStatusBar, targetText, showText)
end

local function RemoveRingTarget(targetCooldown)
    local sourceCooldown = targetSources[targetCooldown]
    if not sourceCooldown then return end
    local targets = ringTargets[sourceCooldown]
    if targets then targets[targetCooldown] = nil end
    targetSources[targetCooldown] = nil
end

local function EnsureRingSourceHook(sourceCooldown)
    local targets = ringTargets[sourceCooldown]
    if targets then return targets end

    targets = setmetatable({}, { __mode = "k" })
    ringTargets[sourceCooldown] = targets

    if hooksecurefunc and sourceCooldown and type(sourceCooldown.SetCooldown) == "function" then
        hooksecurefunc(sourceCooldown, "SetCooldown", function(_, startTime, duration)
            local currentTargets = ringTargets[sourceCooldown]
            if not currentTargets then return end
            for targetCooldown in pairs(currentTargets) do
                pcall(function()
                    if targetCooldown and targetCooldown.IsShown and targetCooldown:IsShown() then
                        if IsPositivePlainNumber(duration) then
                            targetCooldown:SetCooldown(startTime, duration)
                        elseif targetCooldown.Clear then
                            targetCooldown:Clear()
                        end
                    end
                end)
            end
        end)
    end
    return targets
end

function Driver.SyncRingCooldown(sourceFrame, targetCooldown, unit, auraInstanceID)
    if not targetCooldown then return false end

    RemoveRingTarget(targetCooldown)

    local sourceCooldown = sourceFrame and sourceFrame.Cooldown
    if sourceCooldown then
        local targets = EnsureRingSourceHook(sourceCooldown)
        targets[targetCooldown] = true
        targetSources[targetCooldown] = sourceCooldown

        local copied = false
        pcall(function()
            if sourceCooldown.GetCooldownTimes then
                local startMS, durationMS = sourceCooldown:GetCooldownTimes()
                if IsPositivePlainNumber(startMS) and IsPositivePlainNumber(durationMS) then
                    targetCooldown:SetCooldown(startMS / 1000, durationMS / 1000)
                    copied = true
                end
            end
        end)
        if copied then return true end
    end

    return Driver.SyncAuraCooldown(targetCooldown, nil, nil, unit, auraInstanceID)
end

function Driver.DetachRingCooldown(targetCooldown)
    RemoveRingTarget(targetCooldown)
end
