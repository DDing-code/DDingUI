from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).parents[1]

HARNESS = r'''
now = 100
combat = false
unitCombat = {}
groupKind = nil      -- nil / "party" / "raid"
groupSize = 0
secretUnits = {}

function issecretvalue(v) return type(v) == "table" and rawget(v, "secret") == true end
local SECRET = setmetatable({ secret = true }, { __eq = function() error("compared a secret") end })

function GetTime() return now end
function InCombatLockdown() return combat end
function UnitAffectingCombat(unit)
    if secretUnits[unit] then return SECRET end
    if unit == "player" then return combat end
    return unitCombat[unit] == true
end
function UnitIsUnit(a, b) return a == b end
function IsInRaid() return groupKind == "raid" end
function IsInGroup() return groupKind ~= nil end
function GetNumGroupMembers() return groupKind == "raid" and groupSize or 0 end
function GetNumSubgroupMembers() return groupKind == "party" and groupSize or 0 end
function IsInInstance() return true, "party" end
function GetInstanceInfo() return "x", "party", 8 end
function print() end
function geterrorhandler() return error end
SOUNDKIT = {}
function PlaySound() end

-- universal UI stub: any method call returns nil, numbers where arithmetic is expected
local Stub = {}
local stubMethods = {
    GetStringWidth = function() return 60 end,
    GetStringHeight = function() return 20 end,
    GetText = function() return nil end,
    GetWidth = function() return 100 end,
    GetHeight = function() return 40 end,
    GetScale = function() return 1 end,
}
local function newStub()
    local s = { scripts = {}, events = {} }
    return setmetatable(s, Stub)
end
Stub.__index = function(self, key)
    if stubMethods[key] then return stubMethods[key] end
    if key == "CreateTexture" or key == "CreateFontString" or key == "CreateAnimationGroup"
        or key == "CreateAnimation" then
        return function() return newStub() end
    end
    if key == "SetScript" then return function(s, name, fn) s.scripts[name] = fn end end
    if key == "RegisterEvent" then return function(s, e) s.events[e] = true end end
    if key == "UnregisterAllEvents" then return function(s) s.events = {} end end
    return function() end
end
frames = {}
function CreateFrame()
    local f = newStub()
    frames[#frames + 1] = f
    return f
end
UIParent = newStub()

function fire(event, ...)
    for _, f in ipairs(frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

-- deterministic timers
local timers = {}
C_Timer = {}
function C_Timer.After(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end
function C_Timer.NewTicker(interval, fn)
    local t = { interval = interval, at = now + interval, fn = fn, repeating = true }
    function t:Cancel() self.cancelled = true end
    timers[#timers + 1] = t
    return t
end
function advance(seconds)
    local target = now + seconds
    while true do
        local nextT, nextI
        for i, t in ipairs(timers) do
            if not t.cancelled and t.at <= target and (not nextT or t.at < nextT.at) then nextT, nextI = t, i end
        end
        if not nextT then break end
        now = nextT.at
        if nextT.repeating then nextT.at = nextT.at + nextT.interval else table.remove(timers, nextI) end
        nextT.fn()
    end
    now = target
end

ns = { db = { profile = {
    CombatTimer = { hideDelay = 0, printToChat = false, position = {}, textColor = { 1, 1, 1, 1 },
        textAlign = "CENTER", showMilliseconds = true },
    CombatStateAlert = { showStart = true, showEnd = true, instanceOnly = false, excludeDelves = false },
} } }
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.CHAT_PREFIX = ""
modules = {}
ns.DDingToolKit = { RegisterModule = function(_, name, m) modules[name] = m end }
'''


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(HARNESS)
    for rel in ("Core/CombatSession.lua", "Modules/CombatTimer/CombatTimer.lua",
                "Modules/CombatStateAlert/CombatStateAlert.lua"):
        lua.execute((ROOT / rel).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    lua.execute(r'''
        log = {}
        local timer = modules.CombatTimer
        local startTimer, stopTimer = timer.StartTimer, timer.StopTimer
        function timer:StartTimer(...) log[#log + 1] = "timer:start"; return startTimer(self, ...) end
        function timer:StopTimer(endedAt, ...)
            log[#log + 1] = "timer:stop@" .. tostring(endedAt)
            return stopTimer(self, endedAt, ...)
        end
        timer:OnInitialize()
        timer:OnEnable()

        local alert = modules.CombatStateAlert
        function alert:CreateFrame() end
        function alert:ApplySettings() end
        function alert:ShowAlert(kind) log[#log + 1] = "alert:" .. kind end
        alert:OnInitialize()
        alert:OnEnable()

        function enter() combat = true; fire("PLAYER_REGEN_DISABLED") end
        function leave() combat = false; fire("PLAYER_REGEN_ENABLED") end
        function events() local out = {}; for i, v in ipairs(log) do out[i] = v end; log = {}; return out end
    ''')
    return lua


def events(lua):
    return list(lua.globals().events().values())


def test_short_drop_and_reentry_is_one_combat():
    lua = runtime()
    g = lua.globals()
    g.enter()
    g.advance(5)
    g.leave()
    g.advance(1.0)  # back in before END_GRACE (2s)
    g.enter()
    g.advance(10)
    assert events(lua) == ["timer:start", "alert:START"]
    assert g.ns.CombatSession.IsActive(g.ns.CombatSession)

    g.leave()
    g.advance(1.9)
    assert events(lua) == []
    g.advance(0.5)
    assert events(lua) == ["timer:stop@116", "alert:END"]  # endedAt = the moment combat really ended


def test_real_start_and_end_alert_once_each():
    lua = runtime()
    g = lua.globals()
    g.enter()
    g.advance(30)
    g.leave()
    g.advance(10)
    assert events(lua) == ["timer:start", "alert:START", "timer:stop@130", "alert:END"]
    g.enter()
    assert events(lua) == ["timer:start", "alert:START"]


def test_rapid_regen_flapping_collapses_to_one_pair():
    lua = runtime()
    g = lua.globals()
    for _ in range(6):
        g.enter()
        g.advance(0.05)
        g.leave()
        g.advance(0.05)
    g.advance(5)
    assert events(lua) == ["timer:start", "alert:START", "timer:stop@100.55", "alert:END"]


def test_group_member_still_fighting_keeps_timer_and_alert_quiet():
    lua = runtime()
    g = lua.globals()
    g.groupKind, g.groupSize = "party", 4
    g.enter()
    g.advance(3)
    g.unitCombat["party2"] = True
    g.leave()  # e.g. feign death / vanish / dead while the party fights on
    g.advance(20)
    assert events(lua) == ["timer:start", "alert:START"]
    g.enter()  # back into the same fight
    g.advance(4)
    g.unitCombat["party2"] = False
    g.leave()
    g.advance(3)
    assert events(lua) == ["timer:stop@127", "alert:END"]


def test_secret_group_combat_values_are_not_compared():
    lua = runtime()
    g = lua.globals()
    g.groupKind, g.groupSize = "raid", 3
    g.secretUnits["raid2"] = True
    g.enter()
    g.advance(2)
    g.leave()
    g.advance(3)
    assert events(lua) == ["timer:start", "alert:START", "timer:stop@102", "alert:END"]


def test_end_across_loading_screen_is_silent_but_stops_timer():
    lua = runtime()
    g = lua.globals()
    g.enter()
    g.advance(4)
    g.leave()
    g.fire("PLAYER_ENTERING_WORLD")
    g.advance(3)
    assert events(lua) == ["timer:start", "alert:START", "timer:stop@104"]


def test_reload_in_combat_resumes_timer_without_start_alert():
    lua = runtime()
    g = lua.globals()
    g.combat = True
    g.fire("PLAYER_ENTERING_WORLD")
    assert events(lua) == ["timer:start"]


def test_alert_and_timer_no_longer_listen_to_regen_directly():
    alert = (ROOT / "Modules/CombatStateAlert/CombatStateAlert.lua").read_text(encoding="utf-8")
    timer = (ROOT / "Modules/CombatTimer/CombatTimer.lua").read_text(encoding="utf-8")
    toc = (ROOT / "DDingUI_Toolkit.toc").read_text(encoding="utf-8")
    assert 'RegisterEvent("PLAYER_REGEN' not in alert
    assert 'RegisterEvent("PLAYER_REGEN' not in timer
    assert "COMBAT_LOG_EVENT" not in (ROOT / "Core/CombatSession.lua").read_text(encoding="utf-8")
    assert toc.index("Core\\CombatSession.lua") < toc.index("Modules\\CombatTimer\\CombatTimer.lua")
    assert toc.index("Core\\CombatSession.lua") < toc.index("Modules\\CombatStateAlert\\CombatStateAlert.lua")
