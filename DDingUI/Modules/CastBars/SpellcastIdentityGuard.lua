local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
if not DDingUI then return end

local CastBars = DDingUI.CastBars
if not CastBars then return end

-- Midnight/12.1 spellcast events identify each cast with the castID/castGUID
-- carried by UNIT_SPELLCAST_* events. A failed queued spell can fire while an
-- earlier cast is still in progress, so terminal events must only affect the
-- cast bar when their ID matches the cast currently owned by the bar.
--
-- Blizzard's CastingBarMixin applies the same rule for FAILED/INTERRUPTED/STOP:
-- compare the incoming castID against the castID cached from UnitCastingInfo.

local diagnostics = {
    remembered = 0,
    ignoredTerminalEvents = 0,
    ignoredUpdateEvents = 0,
    recoveredFromUnitCastingInfo = 0,
}

local function GetCurrentRegularCastIdentity()
    if not UnitCastingInfo then return nil, nil end
    local _, _, _, _, _, _, castID, _, spellID = UnitCastingInfo("player")
    return castID, spellID
end

local function RememberIdentity(bar, eventCastID, spellID, preferUnitCastingInfo)
    if not bar then return end

    local activeCastID = eventCastID
    local activeSpellID = spellID

    if preferUnitCastingInfo then
        local unitCastID, unitSpellID = GetCurrentRegularCastIdentity()
        activeCastID = unitCastID or activeCastID
        activeSpellID = unitSpellID or activeSpellID
    end

    if activeCastID ~= nil then
        bar._ddingActiveCastID = activeCastID
        -- Keep the old compatibility field useful instead of clearing it on
        -- every start. Existing code may inspect it, while the dedicated guard
        -- below remains the source of truth.
        bar.castGUID = activeCastID
        diagnostics.remembered = diagnostics.remembered + 1
    end

    if activeSpellID ~= nil then
        bar._ddingActiveCastSpellID = activeSpellID
    end
end

local function ClearIdentity(bar)
    if not bar then return end
    bar._ddingActiveCastID = nil
    bar._ddingActiveCastSpellID = nil
end

local function RecoverRegularIdentity(bar)
    if not bar or bar.isChannel or bar.isEmpowered then return nil end

    local castID, spellID = GetCurrentRegularCastIdentity()
    if castID ~= nil then
        bar._ddingActiveCastID = castID
        bar._ddingActiveCastSpellID = spellID
        bar.castGUID = castID
        diagnostics.recoveredFromUnitCastingInfo = diagnostics.recoveredFromUnitCastingInfo + 1
    end
    return castID
end

local function GetActiveCastID(bar)
    if not bar then return nil end
    return bar._ddingActiveCastID or bar.castGUID or RecoverRegularIdentity(bar)
end

local function EventBelongsToActiveCast(bar, eventCastID, isUpdate)
    if not bar or eventCastID == nil then
        return true
    end

    local activeCastID = GetActiveCastID(bar)
    if activeCastID == nil then
        -- If identity is genuinely unavailable, preserve the old behavior
        -- rather than guessing from spellID or timing.
        return true
    end

    if eventCastID ~= activeCastID then
        if isUpdate then
            diagnostics.ignoredUpdateEvents = diagnostics.ignoredUpdateEvents + 1
        else
            diagnostics.ignoredTerminalEvents = diagnostics.ignoredTerminalEvents + 1
        end
        return false
    end

    return true
end

local function IsBarFinished(bar)
    if not bar then return true end
    if bar._ddingFading then return true end
    if bar.IsShown and not bar:IsShown() then return true end
    return false
end

local originalStart = CastBars.OnPlayerSpellcastStart
if type(originalStart) == "function" then
    function CastBars:OnPlayerSpellcastStart(unit, castID, spellID, eventCastBarID)
        local result = originalStart(self, unit, castID, spellID, eventCastBarID)
        local bar = DDingUI.castBar
        if bar and bar.startTime and bar.endTime then
            -- UnitCastingInfo's castID is authoritative for normal casts.
            RememberIdentity(bar, castID, spellID, true)
        end
        return result
    end
end

local originalChannelStart = CastBars.OnPlayerSpellcastChannelStart
if type(originalChannelStart) == "function" then
    function CastBars:OnPlayerSpellcastChannelStart(unit, castID, spellID, eventCastBarID)
        local result = originalChannelStart(self, unit, castID, spellID, eventCastBarID)
        local bar = DDingUI.castBar
        if bar and bar.isChannel then
            RememberIdentity(bar, castID, spellID, false)
        end
        return result
    end
end

local originalEmpowerStart = CastBars.OnPlayerSpellcastEmpowerStart
if type(originalEmpowerStart) == "function" then
    function CastBars:OnPlayerSpellcastEmpowerStart(unit, castID, spellID, eventCastBarID)
        local result = originalEmpowerStart(self, unit, castID, spellID, eventCastBarID)
        local bar = DDingUI.castBar
        if bar and bar.isEmpowered then
            RememberIdentity(bar, castID, spellID, false)
        end
        return result
    end
end

local originalStop = CastBars.OnPlayerSpellcastStop
if type(originalStop) == "function" then
    function CastBars:OnPlayerSpellcastStop(unit, castID, spellID, wasInterrupted, eventCastBarID)
        local bar = DDingUI.castBar
        if bar and not EventBelongsToActiveCast(bar, castID, false) then
            return
        end

        local result = originalStop(self, unit, castID, spellID, wasInterrupted, eventCastBarID)
        bar = DDingUI.castBar

        if bar then
            if IsBarFinished(bar) then
                ClearIdentity(bar)
            elseif not bar.isChannel and not bar.isEmpowered then
                -- Some stop paths transition directly into a new regular cast.
                -- Refresh ownership from UnitCastingInfo so a late event from the
                -- previous cast cannot terminate the new bar.
                local currentCastID, currentSpellID = GetCurrentRegularCastIdentity()
                if currentCastID ~= nil and currentCastID ~= bar._ddingActiveCastID then
                    RememberIdentity(bar, currentCastID, currentSpellID, false)
                end
            end
        end

        return result
    end
end

local originalChannelUpdate = CastBars.OnPlayerSpellcastChannelUpdate
if type(originalChannelUpdate) == "function" then
    function CastBars:OnPlayerSpellcastChannelUpdate(unit, castID, spellID, eventCastBarID)
        local bar = DDingUI.castBar
        if bar and not EventBelongsToActiveCast(bar, castID, true) then
            return
        end
        return originalChannelUpdate(self, unit, castID, spellID, eventCastBarID)
    end
end

local originalEmpowerUpdate = CastBars.OnPlayerSpellcastEmpowerUpdate
if type(originalEmpowerUpdate) == "function" then
    function CastBars:OnPlayerSpellcastEmpowerUpdate(unit, castID, spellID, eventCastBarID)
        local bar = DDingUI.castBar
        if bar and not EventBelongsToActiveCast(bar, castID, true) then
            return
        end
        return originalEmpowerUpdate(self, unit, castID, spellID, eventCastBarID)
    end
end

local originalEmpowerStop = CastBars.OnPlayerSpellcastEmpowerStop
if type(originalEmpowerStop) == "function" then
    function CastBars:OnPlayerSpellcastEmpowerStop(unit, castID, spellID, eventCastBarID)
        local bar = DDingUI.castBar
        if bar and not EventBelongsToActiveCast(bar, castID, false) then
            return
        end

        local result = originalEmpowerStop(self, unit, castID, spellID, eventCastBarID)
        bar = DDingUI.castBar
        if bar then
            if IsBarFinished(bar) then
                ClearIdentity(bar)
            else
                local currentCastID, currentSpellID = GetCurrentRegularCastIdentity()
                if currentCastID ~= nil then
                    RememberIdentity(bar, currentCastID, currentSpellID, false)
                end
            end
        end
        return result
    end
end

function CastBars:GetSpellcastIdentityDiagnostics()
    local result = {}
    for key, value in pairs(diagnostics) do
        result[key] = value
    end
    local bar = DDingUI.castBar
    result.activeCastID = bar and bar._ddingActiveCastID or nil
    result.activeSpellID = bar and bar._ddingActiveCastSpellID or nil
    return result
end
