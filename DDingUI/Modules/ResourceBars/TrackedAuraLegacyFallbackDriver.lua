local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

-- Legacy aura data access used only by manual/compatibility paths.
--
-- 12.1 automatic visual trackers are rendered through TrackedAuraContainer and
-- must not call this driver during the protected display path. Keeping every
-- direct CDM/C_UnitAuras presentation read behind one module gives the legacy
-- path an explicit retirement boundary and keeps BuffTrackerBar focused on
-- layout/style orchestration.

local Driver = {}
DDingUI.TrackedAuraLegacyFallbackDriver = Driver

local C_UnitAuras = C_UnitAuras
local CDMCompat = DDingUI.CDMCompat
local pcall = pcall
local type = type
local tonumber = tonumber
local tostring = tostring

function Driver.IsSecretValue(value)
    if issecretvalue then
        return issecretvalue(value)
    end
    return false
end

function Driver.IsAccessibleNumber(value)
    if type(value) ~= "number" then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    return not Driver.IsSecretValue(value)
end

function Driver.HasTrackedAuraData(trackedStacks, auraInstanceID)
    if Driver.IsSecretValue(auraInstanceID) then return true end
    if type(auraInstanceID) == "number" and auraInstanceID ~= 0 then return true end
    if Driver.IsSecretValue(trackedStacks) then return true end
    if type(trackedStacks) ~= "number" then return false end
    if Driver.IsAccessibleNumber(trackedStacks) then
        return trackedStacks > 0
    end
    return false
end

function Driver.IsProtectedAuraObservation(trackedStacks, auraInstanceID)
    if Driver.IsSecretValue(trackedStacks) or Driver.IsSecretValue(auraInstanceID) then
        return true
    end
    if type(trackedStacks) == "number" and not Driver.IsAccessibleNumber(trackedStacks) then
        return true
    end
    if type(auraInstanceID) == "number" and not Driver.IsAccessibleNumber(auraInstanceID) then
        return true
    end
    return false
end

function Driver.HasAuraInstanceID(value)
    if Driver.IsSecretValue(value) then return true end
    return type(value) == "number" and value ~= 0
end

function Driver.HasAuraResult(value)
    if Driver.IsSecretValue(value) then return true end
    return value ~= nil
end

function Driver.GetAuraInstanceCacheKey(value)
    if Driver.IsSecretValue(value) then return "secret" end
    if type(value) == "number" and value ~= 0 then return value end
    return nil
end

local function IsTrackedAuraFrameActive(frame)
    if not frame then return false end

    if type(frame.IsActive) == "function" then
        local ok, result = pcall(frame.IsActive, frame)
        if ok and not Driver.IsSecretValue(result) and type(result) == "boolean" then
            return result
        end
    end

    local active = frame.isActive
    if not Driver.IsSecretValue(active) and active == true then
        return true
    end

    local wasSetFromAura = frame.wasSetFromAura
    if not Driver.IsSecretValue(wasSetFromAura) and wasSetFromAura == true then
        return true
    end

    return Driver.HasAuraInstanceID(frame.auraInstanceID)
end

local function AcceptTrackedFrame(frame, cooldownID)
    if not frame then return nil end
    if not CDMCompat or not CDMCompat.GetFrameCooldownID then return frame end

    local frameCooldownID = CDMCompat:GetFrameCooldownID(frame)
    if Driver.IsAccessibleNumber(frameCooldownID) and frameCooldownID == cooldownID then
        return frame
    end
    return nil
end

function Driver.ResolveFrame(cooldownID, trackedBuff)
    cooldownID = tonumber(cooldownID) or 0

    local resolver = DDingUI.TrackedAuraFrameResolver
    if trackedBuff and resolver and resolver.GetFrame then
        local frame = resolver:GetFrame(trackedBuff)
        if frame then return frame end
    end

    if CDMCompat and CDMCompat.FindFrameByCooldownID then
        local frame = AcceptTrackedFrame(CDMCompat:FindFrameByCooldownID(cooldownID, true), cooldownID)
        if frame then return frame end
    end

    local controller = DDingUI.FrameController
    if controller and controller.GetIconFrame then
        local frame = AcceptTrackedFrame(controller:GetIconFrame(cooldownID), cooldownID)
        if frame then return frame end
    end

    local scanner = DDingUI.CDMScanner
    if scanner and scanner.FindFrameByCooldownID then
        return AcceptTrackedFrame(scanner.FindFrameByCooldownID(cooldownID), cooldownID)
    end
    return nil
end

local function GetBuffStacks(frame, unit)
    if not frame then return 0, nil end
    if not IsTrackedAuraFrameActive(frame) then return 0, nil end

    local rawAuraID = frame.auraInstanceID
    unit = unit or "player"
    local stacks = 1

    local scanner = DDingUI.CDMScanner
    if scanner and scanner.GetStacksFromFrame then
        local ok, frameStacks = pcall(scanner.GetStacksFromFrame, frame)
        if ok and Driver.IsAccessibleNumber(frameStacks) and frameStacks > 0 then
            stacks = frameStacks
        end
    end

    if Driver.HasAuraInstanceID(rawAuraID)
        and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
    then
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, rawAuraID)
        if ok and Driver.HasAuraResult(auraData) and not Driver.IsSecretValue(auraData) then
            local applications = auraData.applications
            if Driver.IsAccessibleNumber(applications) and applications > 0 then
                stacks = applications
            end
        end
        return stacks, rawAuraID
    end

    return stacks, nil
end

local function FindAuraGloballyByName(name)
    if not C_UnitAuras or not name or name == "" then return nil, nil end

    for i = 1, 255 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        if aura.name == name then return aura, "player" end
    end
    for i = 1, 255 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HARMFUL")
        if not aura then break end
        if aura.name == name then return aura, "player" end
    end
    for i = 1, 255 do
        local aura = C_UnitAuras.GetAuraDataByIndex("target", i, "PLAYER|HARMFUL")
        if not aura then break end
        if aura.name == name then return aura, "target" end
    end
    for i = 1, 255 do
        local aura = C_UnitAuras.GetAuraDataByIndex("target", i, "PLAYER|HELPFUL")
        if not aura then break end
        if aura.name == name then return aura, "target" end
    end
    return nil, nil
end

local function TryTrackedPlayerAura(spellID)
    if not C_UnitAuras or not Driver.IsAccessibleNumber(spellID) or spellID <= 0 then
        return nil, nil
    end
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
    return aura, Driver.HasAuraResult(aura) and spellID or nil
end

local function FindTrackedPlayerAura(cooldownID, savedSpellID)
    local aura, matchedSpellID = TryTrackedPlayerAura(savedSpellID)
    if Driver.HasAuraResult(aura) then return aura, matchedSpellID end

    local scanner = DDingUI.CDMScanner
    local entry = scanner and scanner.GetEntry and scanner.GetEntry(cooldownID)
    if entry then
        aura, matchedSpellID = TryTrackedPlayerAura(entry.overrideTooltipSpellID)
        if Driver.HasAuraResult(aura) then return aura, matchedSpellID end
        aura, matchedSpellID = TryTrackedPlayerAura(entry.overrideSpellID)
        if Driver.HasAuraResult(aura) then return aura, matchedSpellID end
        aura, matchedSpellID = TryTrackedPlayerAura(entry.displaySpellID)
        if Driver.HasAuraResult(aura) then return aura, matchedSpellID end

        local linkedSpellIDs = entry.linkedSpellIDs
        if type(linkedSpellIDs) == "table" and not Driver.IsSecretValue(linkedSpellIDs) then
            for index = 1, #linkedSpellIDs do
                aura, matchedSpellID = TryTrackedPlayerAura(linkedSpellIDs[index])
                if Driver.HasAuraResult(aura) then return aura, matchedSpellID end
            end
        end

        aura, matchedSpellID = TryTrackedPlayerAura(entry.spellID)
        if Driver.HasAuraResult(aura) then return aura, matchedSpellID end
    elseif cooldownID > 0 and CDMCompat then
        local info = CDMCompat:GetCooldownInfo(cooldownID)
        if info and not Driver.IsSecretValue(info) then
            aura, matchedSpellID = TryTrackedPlayerAura(info.overrideTooltipSpellID)
            if Driver.HasAuraResult(aura) then return aura, matchedSpellID end
            aura, matchedSpellID = TryTrackedPlayerAura(info.overrideSpellID)
            if Driver.HasAuraResult(aura) then return aura, matchedSpellID end

            local linkedSpellIDs = info.linkedSpellIDs
            if type(linkedSpellIDs) == "table" and not Driver.IsSecretValue(linkedSpellIDs) then
                for index = 1, #linkedSpellIDs do
                    aura, matchedSpellID = TryTrackedPlayerAura(linkedSpellIDs[index])
                    if Driver.HasAuraResult(aura) then return aura, matchedSpellID end
                end
            end

            aura, matchedSpellID = TryTrackedPlayerAura(info.spellID)
            if Driver.HasAuraResult(aura) then return aura, matchedSpellID end
        end
    end

    return TryTrackedPlayerAura(cooldownID)
end

local function ReadAuraPresentation(aura)
    if Driver.IsSecretValue(aura) then
        return 1, nil
    end

    local stacks = 1
    local applications = aura.applications
    if Driver.IsSecretValue(applications)
        or (Driver.IsAccessibleNumber(applications) and applications > 0)
    then
        stacks = applications
    end

    local auraInstanceID = aura.auraInstanceID
    if not Driver.HasAuraInstanceID(auraInstanceID) then
        auraInstanceID = nil
    end
    return stacks, auraInstanceID
end

function Driver.ResolveStacks(cooldownID, frame, isManualMode, manualStackCount, spellID, spellName, debugEnabled)
    cooldownID = tonumber(cooldownID) or 0
    spellID = tonumber(spellID) or 0
    if isManualMode then
        return manualStackCount or 0, nil, "player"
    end

    local unit = frame and frame.auraDataUnit or "player"
    local trackedStacks, auraInstanceID = GetBuffStacks(frame, unit)

    local resolvedSpellID
    if not Driver.HasTrackedAuraData(trackedStacks, auraInstanceID) then
        local directAura
        directAura, resolvedSpellID = FindTrackedPlayerAura(cooldownID, spellID)
        if Driver.HasAuraResult(directAura) then
            trackedStacks, auraInstanceID = ReadAuraPresentation(directAura)
            unit = "player"
        end
    end

    if not Driver.HasTrackedAuraData(trackedStacks, auraInstanceID)
        and spellName and spellName ~= ""
    then
        pcall(function()
            local aura, foundUnit = FindAuraGloballyByName(spellName)
            if Driver.HasAuraResult(aura) then
                trackedStacks, auraInstanceID = ReadAuraPresentation(aura)
                unit = foundUnit or "player"
            end
        end)
    end

    if debugEnabled and (cooldownID > 0 or (resolvedSpellID and resolvedSpellID > 0)) then
        pcall(function()
            print(string.format(
                "|cffff8800[BT]|r cdID=%s res=%s stacks=%s auraID=%s unit=%s",
                tostring(cooldownID), tostring(resolvedSpellID), tostring(trackedStacks),
                tostring(auraInstanceID), tostring(unit)
            ))
        end)
    end

    return trackedStacks, auraInstanceID, unit
end
