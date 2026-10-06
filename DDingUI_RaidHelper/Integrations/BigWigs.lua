local _, ns = ...

local BigWigsSync = {}
ns.BigWigsSync = BigWigsSync

local function SafeValue(value)
    if (ns.IsSecret and ns:IsSecret(value)) or value == nil then return nil end
    return value
end

local function IsCurrentEncounter(module)
    local engine = ns.Engine
    if not engine:IsRunning() or not (engine.options and engine.options.encounter) then
        return false
    end
    -- Ignore plugin test bars and other encounter modules, including their
    -- stage/stop messages. They must not move or clear the raid clock.
    if not module then return true end
    if type(module.IsEncounterID) ~= "function" then return false end
    return SafeValue(module:IsEncounterID(engine.encounterID)) == true
end

local MESSAGES = {
    "BigWigs_StartBar",
    "BigWigs_StopBar",
    "BigWigs_StopBars",
    "BigWigs_PauseBar",
    "BigWigs_ResumeBar",
    "BigWigs_SetStage",
}

function BigWigsSync:Initialize()
    if self.registered then return true end

    local loader = _G.BigWigsLoader
    if not loader or type(loader.RegisterMessage) ~= "function" then return false end

    local registered = true
    for _, message in ipairs(MESSAGES) do
        if not pcall(loader.RegisterMessage, self, message) then
            registered = false
        end
    end

    if not registered and type(loader.UnregisterMessage) == "function" then
        for _, message in ipairs(MESSAGES) do
            pcall(loader.UnregisterMessage, self, message)
        end
    end

    self.registered = registered
    return registered
end

function BigWigsSync:BigWigs_StartBar(_, module, key, text, seconds, icon, isApproximate, _, eventID, spellIndicators)
    if not IsCurrentEncounter(module)
        or (ns.IsSecret and ns:IsSecret(seconds))
        or type(seconds) ~= "number" then
        return
    end

    local safeKey = SafeValue(key)
    local spellID = type(safeKey) == "number" and safeKey or nil
    local resolvedEventID = SafeValue(eventID) or SafeValue(spellIndicators)
    ns.Engine:ObserveFutureMechanic({ safeKey }, seconds, {
        id = resolvedEventID,
        eventID = resolvedEventID,
        key = safeKey,
        text = text,
        icon = icon,
        spellID = spellID,
        approximate = isApproximate,
        source = "BigWigs",
    })
end

function BigWigsSync:BigWigs_StopBar(_, module, text, eventID)
    if not IsCurrentEncounter(module) then return end
    ns.Engine:RemoveLiveMechanic(SafeValue(eventID) or SafeValue(text))
end

function BigWigsSync:BigWigs_StopBars(_, module)
    if not IsCurrentEncounter(module) then return end
    ns.Engine:ClearLiveMechanics()
end

function BigWigsSync:BigWigs_PauseBar(_, module, text, eventID)
    if not IsCurrentEncounter(module) then return end
    ns.Engine:SetLiveMechanicPaused(SafeValue(eventID) or SafeValue(text), true)
end

function BigWigsSync:BigWigs_ResumeBar(_, module, text, eventID)
    if not IsCurrentEncounter(module) then return end
    local identity = SafeValue(eventID) or SafeValue(text)
    local remaining
    if type(identity) == "number"
        and C_EncounterTimeline
        and type(C_EncounterTimeline.GetEventTimeRemaining) == "function" then
        local ok, value = pcall(C_EncounterTimeline.GetEventTimeRemaining, identity)
        if ok and not ns:IsSecret(value) and type(value) == "number" then
            remaining = value
        end
    end
    ns.Engine:ResumeLiveMechanic(identity, remaining)
end

function BigWigsSync:BigWigs_SetStage(_, module, stage)
    if not IsCurrentEncounter(module) then return end
    ns.Engine:ObservePhase(stage, "BigWigs phase")
end
