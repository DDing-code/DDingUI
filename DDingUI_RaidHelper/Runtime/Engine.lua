local _, ns = ...

local Engine = {}
ns.Engine = Engine

local function IsSecret(value)
    return ns.IsSecret and ns:IsSecret(value) or false
end

local function SafeIdentity(value)
    if IsSecret(value) or value == nil then return nil end
    local valueType = type(value)
    if valueType ~= "string" and valueType ~= "number" then return nil end

    local identity = tostring(value)
    if IsSecret(identity) then return nil end
    return identity
end

local function SafeValue(value, fallback)
    if IsSecret(value) or value == nil then return fallback end
    return value
end

local function Notify(event, ...)
    if ns.TimelineUI and ns.TimelineUI.OnEngineEvent then
        ns.TimelineUI:OnEngineEvent(event, ...)
    end
end

function Engine:Initialize()
    if self.initialized then return end
    self.running = false
    self.liveMechanics = {}
    self.correction = 0
    self.targetCorrection = 0
    self.initialized = true
end

function Engine:IsRunning()
    return self.running == true
end

function Engine:GetModel()
    return self.model
end

function Engine:RefreshPlayerSpecialization()
    local specializationIndex = GetSpecialization and GetSpecialization() or nil
    if ns:IsSecret(specializationIndex) or type(specializationIndex) ~= "number" then
        self.playerSpecID = nil
        self.playerSpecName = nil
        self.playerRole = nil
        return nil
    end

    local specID, specName, _, _, role = GetSpecializationInfo(specializationIndex)
    if ns:IsSecret(specID) or ns:IsSecret(specName) or ns:IsSecret(role) then return nil end

    self.playerSpecID = specID
    self.playerSpecName = specName
    self.playerRole = role
    Notify("SPECIALIZATION", specID, specName, role)
    return specID
end

function Engine:GetCooldowns()
    local model = self.model
    if not model then return {} end

    local bySpec = model.cooldownsBySpec or {}
    local cooldowns
    if self.playerSpecID then
        cooldowns = bySpec[self.playerSpecID] or bySpec[tostring(self.playerSpecID)]
        if not cooldowns and (model.healerProfilesBySpec or model.dpsProfilesBySpec) then return {} end
        cooldowns = cooldowns or model.cooldowns or {}
    else
        cooldowns = model.cooldowns or {}
    end

    if not self.playerSpecID or not ns.CooldownCatalog then
        return cooldowns
    end

    local filtered = {}
    for _, cooldown in ipairs(cooldowns) do
        if ns.CooldownCatalog:IsShown(
            self.playerSpecID,
            cooldown.spellID,
            ns.db and ns.db.cooldownVisibility
        ) then
            filtered[#filtered + 1] = cooldown
        end
    end
    return filtered
end

function Engine:GetHealerProfile()
    local model = self.model
    if not model or not self.playerSpecID then return nil end

    local bySpec = model.healerProfilesBySpec or {}
    local profile = bySpec[self.playerSpecID] or bySpec[tostring(self.playerSpecID)]
    if profile then return profile end
    bySpec = model.dpsProfilesBySpec or {}
    return bySpec[self.playerSpecID] or bySpec[tostring(self.playerSpecID)]
end

function Engine:StartModel(model, options)
    if not model then return false end

    self.model = model
    self.options = options or {}
    if not self.options.encounter then
        self.encounterID = nil
        self.encounterName = nil
        self.difficultyID = nil
        self.difficultyName = nil
    end
    self:RefreshPlayerSpecialization()
    self.running = true
    self.startClock = GetTime()
    self.correction = 0
    self.targetCorrection = 0
    self.liveMechanics = {}
    self.lastSync = nil
    Notify("START", model)
    return true
end

function Engine:StartEncounter(encounterID, encounterName, difficultyID, groupSize)
    local model = ns.Registry:GetEncounter(encounterID, difficultyID)
    if not model then
        if self.running then
            self:StopEncounter(false)
        end
        return false, "model_not_found"
    end
    self.encounterID = encounterID
    self.encounterName = encounterName
    self.difficultyID = difficultyID
    if GetDifficultyInfo then
        local difficultyName = GetDifficultyInfo(difficultyID)
        if not ns:IsSecret(difficultyName) then
            self.difficultyName = difficultyName
        end
    end
    return self:StartModel(model, {
        encounter = true,
        encounterID = encounterID,
        difficultyID = difficultyID,
        groupSize = groupSize,
    })
end

function Engine:StopEncounter(success)
    if not self.running then return end
    self.running = false
    Notify("STOP", success == true, self.model)
end

function Engine:GetTimelineTimeAt(clock)
    if not self.running or not self.startClock then return 0 end
    return math.max(0, (clock - self.startClock) + (self.correction or 0))
end

function Engine:GetTimelineTime()
    return self:GetTimelineTimeAt(GetTime())
end

function Engine:GetPhaseAt(t)
    local phases = self.model and self.model.phases or nil
    local current = phases and phases[1] or nil
    for _, phase in ipairs(phases or {}) do
        if (phase.t or 0) <= t then
            current = phase
        else
            break
        end
    end
    return current
end

function Engine:Tick(elapsed)
    if not self.running then return end

    local difference = (self.targetCorrection or 0) - (self.correction or 0)
    if math.abs(difference) < 0.01 then
        self.correction = self.targetCorrection or 0
    else
        local blend = math.min(1, math.max(0, elapsed or 0) * 6)
        self.correction = (self.correction or 0) + difference * blend
    end

    if self.options and self.options.loop then
        local duration = self.model and self.model.duration or 0
        if duration > 0 and self:GetTimelineTime() > duration then
            self.startClock = GetTime()
            self.correction = 0
            self.targetCorrection = 0
            self.liveMechanics = {}
            Notify("LOOP", self.model)
        end
    end

    local cutoff = self:GetTimelineTime() - 20
    for key, mechanic in pairs(self.liveMechanics) do
        if mechanic.endClock and not mechanic.matched and not mechanic.paused then
            mechanic.t = self:GetTimelineTimeAt(mechanic.endClock)
        end
        if not mechanic.paused and (mechanic.t or 0) < cutoff then
            self.liveMechanics[key] = nil
        end
    end
end

function Engine:Synchronize(expectedTime, observedClock, source)
    if not self.running or type(expectedTime) ~= "number" then return false end
    observedClock = observedClock or GetTime()
    local rawElapsed = observedClock - self.startClock
    local desiredCorrection = expectedTime - rawElapsed

    if math.abs(desiredCorrection - (self.targetCorrection or 0)) < 0.15 then
        return false
    end

    self.targetCorrection = desiredCorrection
    self.lastSync = {
        source = source or "event",
        expectedTime = expectedTime,
        observedClock = observedClock,
    }
    Notify("SYNC", self.lastSync)
    return true
end

function Engine:ObservePhase(stage, source)
    if not self.running or IsSecret(stage) or stage == nil then return false end
    local currentTime = self:GetTimelineTime()
    local bestPhase
    local bestDistance
    local bestIsCurrentOrFuture = false
    for _, phase in ipairs(self.model.phases or {}) do
        if tostring(phase.stage or phase.index) == tostring(stage) then
            local phaseTime = phase.t or 0
            local distance = math.abs(phaseTime - currentTime)
            local isCurrentOrFuture = phaseTime >= currentTime - 8
            if not bestPhase
                or (isCurrentOrFuture and not bestIsCurrentOrFuture)
                or (isCurrentOrFuture == bestIsCurrentOrFuture and distance < bestDistance) then
                bestPhase = phase
                bestDistance = distance
                bestIsCurrentOrFuture = isCurrentOrFuture
            end
        end
    end
    if bestPhase then
        return self:Synchronize(bestPhase.t or 0, GetTime(), source or "phase")
    end
    return false
end

function Engine:ObserveFutureMechanic(keys, secondsUntil, info)
    if not self.running or IsSecret(secondsUntil) or type(secondsUntil) ~= "number" then return nil end
    info = info or {}

    local now = GetTime()
    local predictedTime = self:GetTimelineTimeAt(now) + math.max(0, secondsUntil)
    local mechanic, distance = ns.Registry:FindMechanic(self.model, keys, predictedTime)
    local source = SafeValue(info.source, "mechanic")

    if mechanic and distance and distance <= 8 then
        self:Synchronize(mechanic.syncT or mechanic.t, now + secondsUntil, source)
        predictedTime = mechanic.t
    else
        mechanic = nil
    end

    local identity = SafeIdentity(info.eventID)
        or SafeIdentity(info.id)
        or SafeIdentity(info.key)
        or SafeIdentity(info.text)
        or tostring(predictedTime)
    local label = SafeValue(info.text)
        or SafeValue(mechanic and mechanic.label)
        or "Boss mechanic"
    local icon = SafeValue(info.icon, SafeValue(mechanic and mechanic.icon))
    local spellID = SafeValue(info.spellID, SafeValue(mechanic and mechanic.spellID))
    self.liveMechanics[identity] = {
        id = identity,
        t = predictedTime,
        endClock = now + math.max(0, secondsUntil),
        label = label,
        icon = icon,
        spellID = spellID,
        approximate = SafeValue(info.approximate),
        source = source,
        matched = mechanic,
    }
    return self.liveMechanics[identity]
end

function Engine:RemoveLiveMechanic(value)
    local identity = SafeIdentity(value)
    if not identity then return false end

    if self.liveMechanics[identity] then
        self.liveMechanics[identity] = nil
        return true
    end

    for key, mechanic in pairs(self.liveMechanics) do
        local labelIdentity = SafeIdentity(mechanic.label)
        if labelIdentity and labelIdentity == identity then
            self.liveMechanics[key] = nil
            return true
        end
    end
    return false
end

function Engine:SetLiveMechanicPaused(value, paused)
    local identity = SafeIdentity(value)
    if not identity then return false end

    local mechanic = self.liveMechanics[identity]
    if mechanic then
        mechanic.paused = paused == true
        mechanic.pauseClock = mechanic.paused and GetTime() or nil
        return true
    end
    return false
end

function Engine:ResumeLiveMechanic(value, secondsUntil)
    local identity = SafeIdentity(value)
    if not identity then return false end

    local mechanic = self.liveMechanics[identity]
    if not mechanic then return false end

    mechanic.paused = false
    mechanic.pauseClock = nil
    if IsSecret(secondsUntil) or type(secondsUntil) ~= "number" then return false end

    local now = GetTime()
    mechanic.endClock = now + math.max(0, secondsUntil)
    if mechanic.matched then
        local syncTime = mechanic.matched.syncT or mechanic.matched.t
        self:Synchronize(syncTime, now + math.max(0, secondsUntil), mechanic.source or "BigWigs resume")
        mechanic.t = mechanic.matched.t or syncTime
    else
        mechanic.t = self:GetTimelineTimeAt(now) + math.max(0, secondsUntil)
    end
    return true
end

function Engine:ClearLiveMechanics()
    self.liveMechanics = {}
end

function Engine:GetLiveMechanics()
    return self.liveMechanics
end
