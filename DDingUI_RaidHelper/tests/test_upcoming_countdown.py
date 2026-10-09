"""'곧 사용' alert (2026-10-10): NSRT-style icon + spell name + countdown, voice 셋 · 둘 · 하나.

Runs the shipped Core.lua, Data/Demo.lua and UI/Timeline.lua on the frame mock and walks the
demo encounter clock past 오라 숙련 (44.5 s) and 재활 (60.5 s). The mock records every
PlaySoundFile call. Real audio playback and the in-game look remain in-game checks.
"""
import re

from lupa.lua51 import LuaRuntime

from test_raidhelper_edit_mode import ADDON_ROOT, EXTRA, MOCK, STYLE_FILES
from test_timeline_bar import BAR_EXTRA

COUNT_EXTRA = r'''
function methods:SetTextScale(value) self.textScale = value end
'''

SCENARIO = r'''
local ns = ...
local function Noop() end
local clock = 37.0
DDingUI_RaidHelperDB = {}

ns.Engine = {
    running = false, options = {}, Initialize = Noop,
    IsRunning = function(self) return self.running end,
    StartModel = function(self, model, options)
        self.model, self.options, self.running = model, options, true
        ns.TimelineUI:OnEngineEvent("START", model)
        return true
    end,
    StopEncounter = function(self) self.running = false; self.options = {} end,
    StartEncounter = Noop,
    GetModel = function(self) return self.model end,
    GetTimelineTime = function() return clock end,
    GetPhaseAt = function(self, t)
        local current = self.model.phases[1]
        for _, phase in ipairs(self.model.phases) do
            if phase.t <= t then current = phase else break end
        end
        return current
    end,
    Tick = Noop,
    GetCooldowns = function(self) return self.model and self.model.cooldowns or {} end,
    GetLiveMechanics = function() return {} end,
}
ns.Options = {
    Initialize = Noop, ApplyPendingSettings = Noop, RefreshPreviewButton = Noop,
    ShouldShowTooltips = function() return false end, Open = Noop, Close = Noop,
}
for _, key in ipairs({ "HealerProfileUI", "MinimapButton", "BigWigsSync", "Commands" }) do
    ns[key] = { Initialize = Noop }
end
ns.eventFrame:Fire("OnEvent", "ADDON_LOADED", "DDingUI_RaidHelper")
assert(ns.db.countdownVoice == true, "voice countdown is on by default")

local UI = ns.TimelineUI
local model = ns.Registry:GetByKey("demo")
ns.Engine.model, ns.Engine.running = model, true
UI:OnEngineEvent("START", model)

local function At(seconds)
    clock = seconds
    UI:UpdateView()
    return UI.upcomingRows[1]
end
local function Spoken()
    local list = {}
    for _, sound in ipairs(sounds) do
        list[#list + 1] = sound[1]:match("Countdown_(%d)%.ogg$") or sound[1]
        assert(sound[2] == "Master", "count plays on the Master channel")
    end
    return table.concat(list, ",")
end

-- 7.5 s ahead: icon + name + whole seconds in the accent colour, no box, no sound.
local row = At(37.0)
assert(UI.upcomingPanel.shown and row.shown)
assert(row.label.text == "오라 숙련" and row.countdown.text == "8")
assert(row.countdown.fontSize == 20 and row.label.fontSize == 14)
assert(row.countdown.textColor[1] == UI.accentLight[1])
assert(not row.border and not row.backdrop, "no boxed bar any more")
assert(row.shade.gradient[1] == "HORIZONTAL")
assert(math.abs(row.shade.gradient[2][4] - 0.8) < 1e-6 and math.abs(row.shade.gradient[3][4] - 0.4) < 1e-6
    and math.abs(row.shade2.gradient[2][4] - 0.4) < 1e-6 and row.shade2.gradient[3][4] == 0, "shade fades out to the right")
assert(Spoken() == "")

-- Last three seconds: warning colour, the number pops, and 셋 · 둘 · 하나 each play once.
row = At(41.6) -- 2.9 s
assert(row.countdown.text == "3" and row.countdown.textColor[1] == UI.colors.status.warning[1])
assert(row.textScale == nil and row.countdown.textScale > 1.3, "number pops when it ticks")
assert(Spoken() == "3")
At(41.7)
assert(Spoken() == "3", "a number is spoken once")
now = now + 0.4
At(41.8)
assert(row.countdown.textScale == 1, "pop settles")
At(42.6); assert(Spoken() == "3,2")
At(43.6); assert(Spoken() == "3,2,1")
row = At(44.6)
assert(row.countdown.text == "지금" and Spoken() == "3,2,1", "no voice at 0")

-- A resync jump lands at 1.6 s before 재활: speak 둘 now, never a late 셋.
At(58.9); assert(Spoken() == "3,2,1,2")
At(59.6); assert(Spoken() == "3,2,1,2,1")

-- Two cooldowns close together: only the nearest one counts.
local extra = { id = "test_close", t = 61.2, spellID = 740, label = "평온" }
table.insert(model.cooldowns, 5, extra)
At(60.4) -- 재활 at 0.1 s is still nearest and already said 하나; 평온 (0.8 s) waits
assert(Spoken() == "3,2,1,2,1")
At(60.6) -- 재활 has passed; 평온 is 0.6 s away and says 하나
assert(Spoken() == "3,2,1,2,1,1")
table.remove(model.cooldowns, 5)

-- Turned off: nothing plays. Preview never talks either.
ns.db.countdownVoice = false
At(73.6); assert(Spoken() == "3,2,1,2,1,1")
ns.db.countdownVoice = true
UI.previewMode = true
At(74.6); assert(Spoken() == "3,2,1,2,1,1", "preview/edit stays silent")
UI.previewMode = false

-- A demo loop resets the spoken marks so the next lap counts again.
clock = 30.0 -- the loop restarts the demo near the start, where nothing is due
UI:OnEngineEvent("LOOP", model)
At(41.6); assert(Spoken() == "3,2,1,2,1,1,3")

-- Settings "미리 듣기" plays the full count.
for index = #sounds, 1, -1 do sounds[index] = nil end
UI:PreviewCountdownVoice()
assert(Spoken() == "3,2,1")

-- 0% background: the shade disappears, the text stays.
ns.db.backgroundAlpha = 0
UI:ApplyDisplaySettings()
assert(UI.upcomingRows[1].shade.gradient[2][4] == 0)
'''


def run(extra=""):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().Measure = lambda text, size: len(re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)) * size * 0.65
    lua.execute(MOCK.read_text(encoding="utf-8"))
    lua.execute(EXTRA)
    lua.execute(BAR_EXTRA)
    lua.execute(COUNT_EXTRA)
    for relative in STYLE_FILES + (r"Libs\DDingUI_StyleLib\Animation.lua",):
        source = (ADDON_ROOT / relative.replace("\\", "/")).read_text(encoding="utf-8-sig")
        lua.execute("local source = ...; assert(loadstring(source))('DDingUI_RaidHelper')", source)
    ns = lua.table()
    for relative in ("Data/Registry.lua", "Data/Demo.lua", "UI/Timeline.lua", "Core.lua"):
        source = (ADDON_ROOT / relative).read_text(encoding="utf-8-sig")
        lua.execute("local source, ns = ...; assert(loadstring(source))('DDingUI_RaidHelper', ns)", source, ns)
    lua.execute(SCENARIO, ns)
    if extra:
        lua.execute(extra, ns)


def test_upcoming_alert_counts_down_with_voice():
    run()


def test_long_alert_keeps_the_pulsing_count_inside_the_row():
    run(r'''
local ns = ...
local UI = ns.TimelineUI
ns.db.timelineWidth = 200
UI:ApplyDisplaySettings()
for _, cooldown in ipairs(ns.Engine.model.cooldowns) do
    if cooldown.t == 44.5 then cooldown.label = "Incarnation: Tree of Life" end
end
UI.upcomingRows[1].data = nil
UI:UpdateUpcomingCooldowns(44.4)
UI:UpdateUpcomingCooldowns(44.6)
local row = UI.upcomingRows[1]
assert(row.countdown.text == "지금" and row.countdown.textScale > 1.3)
assert(row.countdown:GetLeft() >= row.label:GetLeft() + row.label:GetWidth() + 8)
assert(row.countdown:GetLeft() + row.countdown:GetStringWidth() * row.countdown.textScale
    <= row:GetLeft() + row:GetWidth() - 2, "expanded 지금 must stay inside the narrow row")
''')


def test_voice_resync_and_repeated_preview_do_not_overlap():
    run(r'''
local ns = ...
local UI = ns.TimelineUI
local active, calls, callbacks = {}, {}, {}
local serial = 0
PlaySoundFile = function(path)
    assert(next(active) == nil, "a resync must stop the previous count before playing another")
    serial = serial + 1
    active[serial] = true
    calls[#calls + 1] = path:match("Countdown_(%d)%.ogg$")
    return true, serial
end
StopSound = function(handle) active[handle] = nil end
C_Timer.After = function(delay, callback) callbacks[#callbacks + 1] = callback end
UI:ResetCountdownVoice()
UI:UpdateCountdownVoice({{data = {}, remaining = 2.9}})
UI:UpdateCountdownVoice({{data = {}, remaining = 1.9}})
UI:PreviewCountdownVoice()
UI:PreviewCountdownVoice()
for _, callback in ipairs(callbacks) do callback() end
assert(table.concat(calls, ",") == "3,2,3,3,2,1", "old preview callbacks must be cancelled")
''')


def test_countdown_voice_files_ship_with_the_addon():
    for number in (1, 2, 3):
        path = ADDON_ROOT / "Media" / "Sounds" / f"Countdown_{number}.ogg"
        data = path.read_bytes()
        assert data[:4] == b"OggS" and b"vorbis" in data[:200], path
        assert 4000 < len(data) < 60000, path


if __name__ == "__main__":
    run()
    test_countdown_voice_files_ship_with_the_addon()
    print("PASS: RaidHelper upcoming countdown")
