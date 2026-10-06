local _, ns = ...

local Registry = {}
ns.Registry = Registry

local models = {}

local function IsSecret(value)
    return ns.IsSecret and ns:IsSecret(value) or false
end

local function MakeEncounterKey(encounterID, difficultyID)
    return tostring(encounterID or 0) .. ":" .. tostring(difficultyID or 0)
end

local function SortByTime(left, right)
    return (left.t or 0) < (right.t or 0)
end

local function AddIndexValue(index, key, mechanic)
    if key == nil then return end
    key = tostring(key)
    index[key] = index[key] or {}
    if index[key][#index[key]] ~= mechanic then
        index[key][#index[key] + 1] = mechanic
    end
end

local function IndexModel(model)
    model.phases = model.phases or {}
    model.mechanics = model.mechanics or {}
    model.syncAnchors = model.syncAnchors or {}
    model.cooldowns = model.cooldowns or {}
    model.cooldownsBySpec = model.cooldownsBySpec or {}
    model.damage = model.damage or { interval = 0.5, values = {} }
    model.damage.values = model.damage.values or {}

    table.sort(model.phases, SortByTime)
    table.sort(model.mechanics, SortByTime)
    table.sort(model.syncAnchors, SortByTime)
    table.sort(model.cooldowns, SortByTime)
    for _, cooldowns in pairs(model.cooldownsBySpec) do
        table.sort(cooldowns, SortByTime)
    end

    local index = {}
    for _, mechanic in ipairs(model.mechanics) do
        AddIndexValue(index, mechanic.id, mechanic)
        AddIndexValue(index, mechanic.anchorKey, mechanic)
        AddIndexValue(index, mechanic.bigWigsKey, mechanic)
        AddIndexValue(index, mechanic.spellID, mechanic)
    end
    for _, anchor in ipairs(model.syncAnchors) do
        AddIndexValue(index, anchor.id, anchor)
        AddIndexValue(index, anchor.bigWigsKey, anchor)
        AddIndexValue(index, anchor.spellID, anchor)
    end
    model._mechanicIndex = index
end

function Registry:Validate(model)
    if type(model) ~= "table" then
        return false, "model must be a table"
    end
    if type(model.duration) ~= "number" or model.duration <= 0 then
        return false, "model.duration must be greater than zero"
    end
    if model.damage and model.damage.interval ~= nil then
        if type(model.damage.interval) ~= "number" or model.damage.interval <= 0 then
            return false, "model.damage.interval must be greater than zero"
        end
    end
    return true
end

function Registry:Register(key, model)
    local valid, reason = self:Validate(model)
    if not valid then
        if ns.Print then ns:Print("데이터 등록 실패:", tostring(key), reason) end
        return false, reason
    end

    model.key = key or model.key or MakeEncounterKey(model.encounterID, model.difficultyID)
    IndexModel(model)
    models[model.key] = model

    if model.encounterID then
        models[MakeEncounterKey(model.encounterID, model.difficultyID)] = model
    end
    return true
end

function Registry:GetByKey(key)
    return models[key]
end

function Registry:GetEncounter(encounterID, difficultyID)
    return models[MakeEncounterKey(encounterID, difficultyID)]
        -- [FIX] Mythic Flex uses 233 in-game; WCL mythic packs use 16.
        or (difficultyID == 233 and models[MakeEncounterKey(encounterID, 16)])
        or models[MakeEncounterKey(encounterID, 0)]
end

function Registry:CreateEmptyEncounter(encounterID, encounterName, difficultyID, groupSize)
    local model = {
        key = "live:" .. MakeEncounterKey(encounterID, difficultyID),
        encounterID = encounterID,
        difficultyID = difficultyID,
        groupSize = groupSize,
        name = encounterName or "Unknown Encounter",
        duration = 900,
        dataStatus = "missing",
        phases = {
            { index = 1, stage = 1, t = 0, label = "P1" },
        },
        mechanics = {},
        cooldowns = {},
        damage = { interval = 0.5, values = {}, max = 1 },
    }
    IndexModel(model)
    return model
end

function Registry:FindMechanic(model, keys, nearTime)
    if not model or not model._mechanicIndex then return nil end
    if type(keys) ~= "table" then keys = { keys } end

    local best
    local bestDistance
    for _, key in ipairs(keys) do
        local candidates
        if not IsSecret(key) and key ~= nil then
            local identity = tostring(key)
            if not IsSecret(identity) then
                candidates = model._mechanicIndex[identity]
            end
        end
        if candidates then
            for _, mechanic in ipairs(candidates) do
                -- BigWigs bars expire on the hostile cast/event anchor, while
                -- mechanic.t is the resulting raid-damage hit. Compare the
                -- bar against syncT so cast time and damage time do not become
                -- two competing clocks.
                local syncTime = mechanic.syncT or mechanic.t or 0
                local distance = math.abs(syncTime - (nearTime or 0))
                if not best or distance < bestDistance then
                    best = mechanic
                    bestDistance = distance
                end
            end
        end
    end
    return best, bestDistance
end

function Registry:GetModels()
    return models
end

function Registry:GetDataSummary()
    local seen = {}
    local summary = {
        modelCount = 0,
        heroicCount = 0,
        mythicCount = 0,
        dpsModelCount = 0,
        limitedDpsModelCount = 0,
        latestGeneratedAt = nil,
    }

    for _, model in pairs(models) do
        if type(model) == "table" and not seen[model] and model.dataStatus == "wcl" then
            seen[model] = true
            summary.modelCount = summary.modelCount + 1
            if model.difficultyID == 15 then
                summary.heroicCount = summary.heroicCount + 1
            elseif model.difficultyID == 16 then
                summary.mythicCount = summary.mythicCount + 1
            end
            if type(model.generatedAt) == "string"
                and (not summary.latestGeneratedAt or model.generatedAt > summary.latestGeneratedAt) then
                summary.latestGeneratedAt = model.generatedAt
            end
            if model.dpsProfilesBySpec and next(model.dpsProfilesBySpec) then
                summary.dpsModelCount = summary.dpsModelCount + 1
                if model.validation and model.validation.dpsCoverageStatus == "limited" then
                    summary.limitedDpsModelCount = summary.limitedDpsModelCount + 1
                end
            end
        end
    end
    return summary
end
