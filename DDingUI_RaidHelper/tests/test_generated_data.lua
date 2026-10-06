local addonName = "DDingUI_RaidHelper"
local ns = {
    Print = function() end,
}

assert(loadfile("Data/Registry.lua"))(addonName, ns)
assert(loadfile("Data/Generated.lua"))(addonName, ns)

local healerSpecs = {
    [65] = true,
    [105] = true,
    [256] = true,
    [257] = true,
    [264] = true,
    [270] = true,
    [1468] = true,
}
local privateKeys = {
    characterName = true,
    playerName = true,
    report = true,
    reportCode = true,
    server = true,
}

local function AssertPrivateDataRemoved(value, visited)
    if type(value) ~= "table" or visited[value] then return end
    visited[value] = true
    for key, child in pairs(value) do
        assert(not privateKeys[key], "private source field found: " .. tostring(key))
        AssertPrivateDataRemoved(child, visited)
    end
end

local seen = {}
local modelCount = 0
local heroicCount = 0
local mythicCount = 0
for _, model in pairs(ns.Registry:GetModels()) do
    if type(model) == "table" and model.dataStatus == "wcl" and not seen[model] then
        seen[model] = true
        modelCount = modelCount + 1
        heroicCount = heroicCount + (model.difficultyID == 15 and 1 or 0)
        mythicCount = mythicCount + (model.difficultyID == 16 and 1 or 0)

        assert(type(model.sampleCount) == "number" and model.sampleCount > 0 and model.sampleCount <= 10)
        assert(model.schemaVersion == 2)
        assert(type(model.damage) == "table" and #(model.damage.values or {}) > 0)
        assert(type(model.healerProfilesBySpec) == "table")
        assert(model.healerRankingMetric == "hps")
        assert(model.cooldownTimingAlignment == "phase-cast-anchored-v2"
            or model.cooldownTimingAlignment == "phase-mechanic-warped")
        assert(type(model.cooldownsBySpec) == "table")
        assert(type(model.syncAnchors) == "table" and #model.syncAnchors > 0)
        assert(type(model.validation) == "table", "source-log validation metadata is required")
        assert(
            model.validation.status == "passed" or model.validation.status == "limited",
            "failed or missing source-log validation status"
        )
        assert(type(model.validation.phaseCoverage) == "number" and model.validation.phaseCoverage >= 0.8)
        assert(
            type(model.validation.healerAnchoredSampleCoverage) == "number"
                and model.validation.healerAnchoredSampleCoverage >= 0.2
        )
        if model.difficultyID == 15 then
            assert(model.validation.status == "passed", "heroic data must pass independent validation")
            assert(model.validation.holdoutSampleCount >= 1, "heroic data requires a holdout log")
        end
        for _, anchor in ipairs(model.syncAnchors) do
            assert(anchor.bigWigsKey ~= 145629, "friendly/environment spell leaked into boss sync anchors")
            assert(anchor.syncOnly == true)
        end

        local profileCount = 0
        for specID, profile in pairs(model.healerProfilesBySpec) do
            assert(healerSpecs[specID], "unexpected healer specialization")
            assert(profile.specID == specID)
            assert(profile.rankingMetric == "hps")
            assert(profile.secondaryStatsUnit == "rating")
            assert(type(profile.sampleCount) == "number" and profile.sampleCount > 0 and profile.sampleCount <= 10)
            assert(type(profile.statSampleCount) == "number" and profile.statSampleCount > 0)
            assert(type(profile.secondaryStats) == "table")
            for _, statKey in ipairs({ "criticalStrike", "haste", "mastery", "versatility" }) do
                assert(type(profile.secondaryStats[statKey]) == "number")
            end
            assert(type(profile.averageItemLevel) == "number" and profile.averageItemLevel > 0)
            assert(type(profile.talentBuilds) == "table" and #profile.talentBuilds > 0)
            assert(type(profile.talentBuilds[1].talents) == "table" and #profile.talentBuilds[1].talents > 0)
            for _, talent in ipairs(profile.talentBuilds[1].talents or {}) do
                assert(type(talent.nodeID) == "number" and talent.nodeID > 0)
            end
            profileCount = profileCount + 1
        end
        if model.validation.status == "passed" then
            assert(profileCount == 7, "passed models require all seven healer specializations")
        else
            assert(model.difficultyID == 16, "limited healer coverage is only valid for mythic")
            assert(profileCount > 0 and profileCount <= 7, "limited models require real healer samples")
        end
        AssertPrivateDataRemoved(model, {})
    end
end

assert(modelCount >= 9, "expected a complete heroic raid data pack")
assert(heroicCount >= 9, "expected at least the original nine heroic encounters")
for _, encounterID in ipairs({ 3470, 3445, 3455, 3497, 3420, 3421, 3429, 3492, 3379 }) do
    assert(ns.Registry:GetEncounter(encounterID, 15), "missing heroic encounter " .. encounterID)
end
assert(mythicCount >= 1, "expected currently available mythic data")

print(string.format(
    "RaidHelper generated data test OK (%d models: %d heroic, %d mythic)",
    modelCount,
    heroicCount,
    mythicCount
))
