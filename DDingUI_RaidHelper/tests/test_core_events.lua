local addonName = "DDingUI_RaidHelper"
local ns = {}
local eventFrame

CreateFrame = function(frameType)
    assert(frameType == "Frame")
    local frame = {
        events = {},
    }

    function frame:RegisterEvent(event)
        assert(event ~= "COMBAT_LOG_EVENT_UNFILTERED", "Midnight-protected combat log event must not be registered")
        self.events[event] = true
    end

    function frame:SetScript(scriptType, callback)
        assert(scriptType == "OnEvent")
        self.onEvent = callback
    end

    eventFrame = frame
    return frame
end

local initialized = {}
for _, key in ipairs({
    "Engine",
    "HealerProfileUI",
    "TimelineUI",
    "MinimapButton",
    "BigWigsSync",
    "Options",
    "Commands",
}) do
    local moduleKey = key
    initialized[key] = 0
    ns[key] = {
        Initialize = function()
            initialized[moduleKey] = initialized[moduleKey] + 1
        end,
    }
end

assert(loadfile("Core.lua"))(addonName, ns)
assert(eventFrame.events.ADDON_LOADED)
assert(eventFrame.events.PLAYER_LOGIN)
assert(not eventFrame.events.COMBAT_LOG_EVENT_UNFILTERED)

eventFrame.onEvent(eventFrame, "ADDON_LOADED", addonName)

assert(ns.initialized)
assert(DDingUI_RaidHelperDB.timelineScale == 1.0)
assert(DDingUI_RaidHelperDB.timelineWidth == 680)
assert(DDingUI_RaidHelperDB.timelineHeight == 210)
assert(DDingUI_RaidHelperDB.backgroundAlpha == 1.0)
assert(DDingUI_RaidHelperDB.showUpcomingCooldowns == true)
assert(type(DDingUI_RaidHelperDB.cooldownVisibility) == "table")
assert(eventFrame.events.ENCOUNTER_START)
assert(eventFrame.events.ENCOUNTER_END)
assert(eventFrame.events.PLAYER_SPECIALIZATION_CHANGED)
assert(eventFrame.events.PLAYER_REGEN_ENABLED)
assert(not eventFrame.events.COMBAT_LOG_EVENT_UNFILTERED)

for key, count in pairs(initialized) do
    assert(count == 1, key .. " should initialize exactly once")
end

-- Exercise the real event -> registry -> engine path with the installed pack.
assert(loadfile("Data/Registry.lua"))(addonName, ns)
assert(loadfile("Data/Generated.lua"))(addonName, ns)
assert(loadfile("Runtime/Engine.lua"))(addonName, ns)
GetTime = function() return 100 end
GetSpecialization = function() return 1 end
GetSpecializationInfo = function() return 257, "Holy", "", 0, "HEALER" end
GetDifficultyInfo = function(id) return "Difficulty " .. id end
local timelineStarted = false
ns.TimelineUI.OnEngineEvent = function(_, event)
    if event == "START" then timelineStarted = true end
    if event == "STOP" then timelineStarted = false end
end
ns.Engine:Initialize()

for _, difficultyID in ipairs({ 15, 16, 233 }) do
    eventFrame.onEvent(eventFrame, "ENCOUNTER_START", 3379, "Nymrissa Wavecaller", difficultyID, 20)
    assert(ns.Engine:IsRunning() and timelineStarted, "Nymrissa must start at difficulty " .. difficultyID)
    assert(ns.Engine:GetModel() == ns.Registry:GetEncounter(3379, difficultyID == 233 and 16 or difficultyID))
    assert(ns.Engine.difficultyID == difficultyID, "preserve the actual encounter difficulty")
    assert(ns.Engine.difficultyName == "Difficulty " .. difficultyID)
    assert(#ns.Engine:GetCooldowns() > 0)
    eventFrame.onEvent(eventFrame, "ENCOUNTER_END", 3379, "Nymrissa Wavecaller", difficultyID, 20, 1)
    assert(not ns.Engine:IsRunning() and not timelineStarted)
end

for _, difficultyID in ipairs({ 8, 14, 17, 23 }) do
    eventFrame.onEvent(eventFrame, "ENCOUNTER_START", 3379, "Nymrissa Wavecaller", difficultyID, 20)
    assert(not ns.Engine:IsRunning() and not timelineStarted, "unrelated difficulties must not reuse mythic data")
end
assert(ns.Registry:GetEncounter(0, 233) == nil, "unknown bosses must stay hidden")
local flexModel = { encounterID = 3379, difficultyID = 233, duration = 100 }
assert(ns.Registry:Register(nil, flexModel))
assert(ns.Registry:GetEncounter(3379, 233) == flexModel, "exact flex data must take priority when available")
assert(ns.Registry:GetEncounter(3379, 16) ~= flexModel, "do not overwrite the fixed mythic model")

ns.Engine.model = {
    dpsProfilesBySpec = { [251] = { specID = 251 } },
    cooldownsBySpec = { [251] = { { spellID = 51271, t = 20 } } },
}
ns.Engine.playerSpecID = 251
assert(ns.Engine:GetHealerProfile().specID == 251)
assert(#ns.Engine:GetCooldowns() == 1)
ns.Engine.playerSpecID = 252
assert(#ns.Engine:GetCooldowns() == 0, "do not show another DPS spec's cooldowns")

print("RaidHelper Midnight-safe core events test OK")
