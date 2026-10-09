local addonName = "DDingUI_RaidHelper"
local secretLabel = setmetatable({}, {
    __tostring = function() error("secret label must not be converted to a string") end,
})
local secretIcon = setmetatable({}, {
    __tostring = function() error("secret icon must not be converted to a string") end,
})
local ns = {
    IsSecret = function(_, value)
        return rawequal(value, secretLabel) or rawequal(value, secretIcon)
    end,
    TimelineUI = { OnEngineEvent = function() end },
}

local clock = 100
GetTime = function() return clock end
GetSpecialization = function() return nil end

assert(loadfile("Data/Registry.lua"))(addonName, ns)
assert(loadfile("Runtime/Engine.lua"))(addonName, ns)

local model = {
    duration = 120,
    phases = { { index = 1, stage = 1, t = 0 } },
    damage = { interval = 0.5, values = {} },
    mechanics = {},
    syncAnchors = {
        {
            id = "boss-cast",
            t = 70,
            syncT = 45,
            spellID = 888001,
            bigWigsKey = 888001,
            syncOnly = true,
        },
    },
}

assert(ns.Registry:Register("sync-test", model))
ns.Engine:Initialize()
assert(ns.Engine:StartModel(model, { encounter = true }))

clock = 110
local live = ns.Engine:ObserveFutureMechanic({ 888001 }, 30, {
    eventID = 77,
    text = "Live boss bar",
    source = "BigWigs",
})
assert(live and live.matched and live.matched.syncOnly)
assert(live.t == 70)
assert(math.abs(ns.Engine.targetCorrection - 5) < 0.001)

ns.Engine:Tick(1)
assert(math.abs(ns.Engine:GetTimelineTime() - 15) < 0.001)

ns.Engine:SetLiveMechanicPaused(77, true)
assert(live.paused)
clock = 120
assert(ns.Engine:ResumeLiveMechanic(77, 20))
assert(not live.paused)
assert(math.abs(ns.Engine.targetCorrection - 5) < 0.001)

local matched = ns.Registry:FindMechanic(model, { secretLabel, 888001 }, 45)
assert(matched and matched.id == "boss-cast")

local far = ns.Engine:ObserveFutureMechanic({ 888001 }, 90, { eventID = 991 })
assert(far and not far.matched, "rejected occurrences must not become sync anchors")
assert(ns.Engine:ResumeLiveMechanic(991, 90))
assert(math.abs(ns.Engine.targetCorrection - 5) < 0.001)
ns.Engine:Synchronize(50, clock, "phase")
ns.Engine:Tick(1)
assert(math.abs(far.t - ns.Engine:GetTimelineTime() - 90) < 0.001,
    "unmatched bars must retain their real remaining time after a clock correction")

local secretLive = ns.Engine:ObserveFutureMechanic({ secretLabel }, 5, {
    eventID = 889,
    text = secretLabel,
    icon = secretIcon,
    source = "BigWigs",
})
assert(secretLive and secretLive.id == "889")
assert(secretLive.label == "Boss mechanic")
assert(secretLive.icon == nil)

ns.Engine.liveMechanics["897"] = {
    id = "897",
    t = 90,
    label = secretLabel,
}
assert(ns.Engine:RemoveLiveMechanic(889))
assert(ns.Engine.liveMechanics["889"] == nil)
assert(ns.Engine.liveMechanics["897"] ~= nil)
assert(ns.Engine:RemoveLiveMechanic(secretLabel) == false)

assert(loadfile("Integrations/BigWigs.lua"))(addonName, ns)
ns.BigWigsSync:BigWigs_StartBar(
    "BigWigs_StartBar",
    nil,
    nil,
    secretLabel,
    5,
    secretIcon,
    nil,
    nil,
    990,
    990
)
assert(ns.Engine.liveMechanics["990"] ~= nil)
assert(ns.Engine.liveMechanics["990"].label == "Boss mechanic")
ns.BigWigsSync:BigWigs_StopBar("BigWigs_StopBar", nil, nil, 990)
assert(ns.Engine.liveMechanics["990"] == nil)
ns.BigWigsSync:BigWigs_StopBar("BigWigs_StopBar", nil, secretLabel, nil)

local wrongBoss = { IsEncounterID = function() return false end }
ns.BigWigsSync:BigWigs_StartBar("BigWigs_StartBar", wrongBoss, 888001, "Other boss", 5, nil, nil, nil, 992)
assert(ns.Engine.liveMechanics["992"] == nil)
ns.BigWigsSync:BigWigs_StopBars("BigWigs_StopBars", wrongBoss)
assert(ns.Engine.liveMechanics["991"] == far)
local correction = ns.Engine.targetCorrection
ns.BigWigsSync:BigWigs_SetStage("BigWigs_SetStage", wrongBoss, 1)
assert(ns.Engine.targetCorrection == correction)

model.phases = { { index = 1, stage = 1, t = 0 }, { index = 2, stage = 3, t = 70 } }
assert(not ns.Engine:ObservePhase(2), "phase indexes are not boss stage identifiers")

-- A late cast must not be mistaken for its later damage tick.
local delayedModel = {
    duration = 120,
    phases = { { index = 1, stage = 1, t = 0 } },
    mechanics = { { id = "hit", t = 47, syncT = 45, bigWigsKey = 888001 } },
    syncAnchors = {
        { id = "cast", t = 45, syncT = 45, bigWigsKey = 888001, syncOnly = true },
        { id = "hit_damage_sync", t = 47, syncT = 47, bigWigsKey = 888001, syncOnly = true },
    },
    damage = { interval = 0.5, values = {} },
}
assert(ns.Registry:Register("delayed-hit", delayedModel))
clock = 200
assert(ns.Engine:StartModel(delayedModel, { encounter = true }))
clock = 210
local delayed = ns.Engine:ObserveFutureMechanic({ 888001 }, 37, { eventID = 1001 })
assert(delayed.matched.syncT == 45, "cast anchors must take priority over damage fallback anchors")
ns.Engine:Tick(1)
assert(ns.Engine:GetTimelineTimeAt(247) == 45, "the graph must follow the actual delayed cast")
assert(ns.Engine:GetTimelineTimeAt(249) == 47, "the damage delay must survive clock correction")
local fallback = ns.Registry:FindMechanic(delayedModel, { 888001 }, 54)
assert(fallback.id == "hit_damage_sync", "a cast outside the 8-second window must not override a valid fallback")
assert(ns.Engine:ObserveFutureMechanic({ 888001 }, 60, { eventID = 1002 }).matched == nil)

-- BigWigs event IDs may be strings; they are not spell IDs or bar labels.
clock = 300
assert(ns.Engine:StartModel(model, { encounter = true }))
clock = 310
ns.BigWigsSync:BigWigs_StartBar("BigWigs_StartBar", nil, 888001, secretLabel, 30, secretIcon, nil, nil, "timeline-77")
local stringBar = ns.Engine.liveMechanics["timeline-77"]
assert(stringBar and stringBar.matched)
ns.BigWigsSync:BigWigs_PauseBar("BigWigs_PauseBar", nil, nil, "timeline-77")
assert(stringBar.paused)
clock = 320
local remainingQueries = 0
C_EncounterTimeline = {
    GetEventTimeRemaining = function(eventID)
        assert(eventID == "timeline-77")
        remainingQueries = remainingQueries + 1
        return 30
    end,
}
ns.BigWigsSync:BigWigs_ResumeBar("BigWigs_ResumeBar", nil, nil, "timeline-77")
assert(remainingQueries == 1, "string event IDs must query the live remaining time")
assert(not stringBar.paused and stringBar.endClock == 350)
assert(ns.Engine.targetCorrection == -5, "the graph clock must include the pause")

-- Label-based legacy messages must resolve the same bar as start/stop.
C_EncounterTimeline = nil
clock = 400
assert(ns.Engine:StartModel(model, { encounter = true }))
clock = 410
ns.BigWigsSync:BigWigs_StartBar("BigWigs_StartBar", nil, 888001, "Legacy boss bar", 30)
local legacy = ns.Engine:ObserveFutureMechanic({ 888001 }, 30, {
    eventID = 2001, text = "Legacy boss bar with ID",
})
ns.BigWigsSync:BigWigs_PauseBar("BigWigs_PauseBar", nil, "Legacy boss bar with ID")
assert(legacy.paused, "pause messages must resolve safe labels even when start used an ID")
clock = 420
assert(not ns.Engine:ResumeLiveMechanic(2001, secretLabel))
assert(legacy.paused and legacy.pauseClock == 410, "rejected remaining time must preserve the paused clock")
ns.BigWigsSync:BigWigs_ResumeBar("BigWigs_ResumeBar", nil, "Legacy boss bar with ID")
assert(not legacy.paused and legacy.endClock == 450)
assert(ns.Engine.targetCorrection == -5)
ns.BigWigsSync:BigWigs_StopBar("BigWigs_StopBar", nil, "Legacy boss bar with ID")
assert(ns.Engine.liveMechanics["2001"] == nil)

C_EncounterTimeline = {
    GetEventTimeRemaining = function() error("legacy labels are not timeline event IDs") end,
}
ns.BigWigsSync:BigWigs_PauseBar("BigWigs_PauseBar", nil, "Legacy boss bar")
local labelBar = ns.Engine.liveMechanics["888001"]
assert(labelBar and labelBar.paused)
clock = 430
ns.BigWigsSync:BigWigs_ResumeBar("BigWigs_ResumeBar", nil, "Legacy boss bar")
assert(not labelBar.paused and labelBar.endClock == 450)
assert(ns.Engine.targetCorrection == -5)

print("RaidHelper live timeline synchronization test OK")
