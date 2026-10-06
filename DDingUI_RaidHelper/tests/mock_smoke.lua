local addonName = "DDingUI_RaidHelper"
local ns = {
    IsSecret = function() return false end,
    Print = function() end,
    TimelineUI = {
        events = {},
        OnEngineEvent = function(self, event)
            self.events[#self.events + 1] = event
        end,
    },
}

local clock = 100
GetTime = function() return clock end
GetSpecialization = function() return 1 end
GetSpecializationInfo = function()
    return 105, "Restoration", "", 0, "HEALER"
end
GetDifficultyInfo = function(difficultyID)
    return difficultyID == 16 and "Mythic" or "Other"
end
issecretvalue = function() return false end

assert(loadfile("Data/Registry.lua"))(addonName, ns)
assert(loadfile("Data/Demo.lua"))(addonName, ns)
assert(loadfile("Runtime/Engine.lua"))(addonName, ns)

assert(ns.Registry:Register("test:16", {
    encounterID = 999,
    difficultyID = 16,
    name = "Automatic Selection Boss",
    dataStatus = "wcl",
    generatedAt = "2026-08-24T10:15:06+00:00",
    duration = 120,
    phases = {
        { index = 1, stage = 1, t = 0, label = "P1" },
        { index = 2, stage = 2, t = 40, label = "P2" },
        { index = 3, stage = 1, t = 80, label = "P1 반복" },
    },
    damage = { interval = 0.5, values = { 1, 2, 3 }, max = 3 },
    mechanics = {},
    cooldowns = {},
    cooldownsBySpec = {
        [105] = {
            { id = "spec-cooldown", t = 20, spellID = 740, label = "Tranquility" },
        },
    },
    healerProfilesBySpec = {
        [105] = {
            specID = 105,
            sampleCount = 10,
            secondaryStats = { criticalStrike = 1000, haste = 800, mastery = 1200, versatility = 200 },
            talentBuilds = {},
        },
    },
}))

ns.Engine:Initialize()
assert(ns.Engine:StartEncounter(999, "Automatic Selection Boss", 16, 20))
assert(ns.Engine:GetModel().name == "Automatic Selection Boss")
assert(ns.Engine.difficultyID == 16)
assert(ns.Engine.difficultyName == "Mythic")
assert(ns.Engine.encounterName == "Automatic Selection Boss")
assert(ns.Engine.playerSpecID == 105)
assert(#ns.Engine:GetCooldowns() == 1)
assert(ns.Engine:GetCooldowns()[1].id == "spec-cooldown")
assert(ns.Engine:GetHealerProfile().sampleCount == 10)

local dataSummary = ns.Registry:GetDataSummary()
assert(dataSummary.modelCount == 1)
assert(dataSummary.heroicCount == 0)
assert(dataSummary.mythicCount == 1)
assert(dataSummary.latestGeneratedAt == "2026-08-24T10:15:06+00:00")

clock = 110
assert(math.abs(ns.Engine:GetTimelineTime() - 10) < 0.001)
assert(ns.Engine:ObservePhase(2, "test"))
ns.Engine:Tick(1)
assert(math.abs(ns.Engine:GetTimelineTime() - 40) < 0.001)

clock = 148
assert(math.abs(ns.Engine:GetTimelineTime() - 78) < 0.001)
assert(ns.Engine:ObservePhase(1, "repeated-stage-test"))
ns.Engine:Tick(1)
assert(math.abs(ns.Engine:GetTimelineTime() - 80) < 0.001)

ns.Engine:StopEncounter(true)
assert(not ns.Engine:IsRunning())

local eventCount = #ns.TimelineUI.events
local started, reason = ns.Engine:StartEncounter(1001, "Dungeon Boss", 8, 5)
assert(started == false and reason == "model_not_found")
assert(not ns.Engine:IsRunning())
assert(#ns.TimelineUI.events == eventCount)

local demo = ns.Registry:GetByKey("demo")
assert(demo and demo.sampleCount == 10)
assert(#demo.damage.values > 200)
assert(#demo.mechanics == 8)
assert(#demo.cooldowns == 8)

print("RaidHelper mock smoke OK")
