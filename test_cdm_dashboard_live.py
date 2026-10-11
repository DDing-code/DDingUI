"""The options dashboard draws only real frames: a live layout session puts elements on screen.

Lua 5.1 checks against the real DDingUI_CDM_Option/DashboardPreview.lua (LiveSession),
DDingUI_CDM/Utils/Toolkit.lua (SetLayoutPreviewForced), GroupSystem/BuffGroupPlaceholders.lua and
the sound entry points:
  * opening a preview turns on the runtime preview paths; closing / the last owner leaving,
    and entering combat, restore them at once; combat end resumes while a preview is still open,
  * modes that were already on before the dashboard opened stay on,
  * the forced layout shows every configured inactive buff through the real placeholder path,
  * custom aura / icon / condition sounds are silent while preview values or the forced layout
    are on, and a test cast never cancels a real cast.
"""
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).parent

STUBS = r'''
combat = false
function InCombatLockdown() return combat end
clock = 100
function GetTime() return clock end
function wipe(t) for k in pairs(t) do t[k] = nil end end
function issecretvalue() return false end
events = {}
tickers = {}
C_Timer = {
    After = function(_, fn) fn() end,
    NewTimer = function(_, fn) return { Cancel = function() end } end,
    NewTicker = function(interval, fn) local t = { fn = fn, interval = interval, Cancel = function(self) self.cancelled = true end }; tickers[#tickers + 1] = t; return t end,
}
function CreateFrame()
    local f = { scripts = {}, events = {} }
    function f:RegisterEvent(e) self.events[e] = true; events[e] = events[e] or {}; table.insert(events[e], self) end
    function f:SetScript(k, v) self.scripts[k] = v end
    function f:Hide() end
    function f:Show() end
    return f
end
function Fire(event)
    for _, f in ipairs(events[event] or {}) do f.scripts.OnEvent(f, event) end
end
log = {}
local function note(name) log[#log + 1] = name end
castBar = { shown = false }
function castBar:IsShown() return self.shown end
addon = {
    GUI = {},
    db = { profile = { castBar = { enabled = true } } },
    castBar = castBar,
}
trackerPreview = false
function addon:IsBuffTrackerPreviewEnabled() return trackerPreview end
function addon:EnableBuffTrackerPreview() trackerPreview = true; note("tracker:on") end
function addon:DisableBuffTrackerPreview() trackerPreview = false; note("tracker:off") end
function addon:SetLayoutPreviewForced(on) self._layoutPreviewForced = on or nil; note(on and "forced:on" or "forced:off") end
function addon:IsTestCastActive() return castBar.shown and castBar.test == true end
function addon:ShowTestCastBar(loop) castBar.shown, castBar.test, castBar.loop, castBar.endTime = true, true, loop, clock + 15; note("cast:test") end
function addon:StopTestCastBar()
    if not addon:IsTestCastActive() then return false end
    castBar.shown, castBar.test = false, nil; note("cast:stop"); return true
end
function Log() return table.concat(log, ",") end
function Reset() for k in pairs(log) do log[k] = nil end end
'''


def session_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    ns = lua.table(Addon=lua.globals().addon)
    lua.execute((ROOT / "DDingUI_CDM_Option/DashboardPreview.lua").read_text(encoding="utf-8"),
                "DDingUI_CDM_Option", ns)
    return lua


def test_session_lifecycle():
    lua = session_runtime()
    lua.execute(r'''
        local S = addon.GUI.DashboardPreview.LiveSession
        local dash, section = {}, {}
        assert(S:Begin(dash) and S:IsActive())
        assert(Log() == "tracker:on,forced:on,cast:test", "open: " .. Log())
        Reset()
        S:Begin(section)                 -- a second preview shares the session
        assert(Log() == "", "second owner restarted modes: " .. Log())
        S:End(dash)
        assert(S:IsActive() and Log() == "", "closing one preview must keep the other alive")
        -- the runtime loops the test cast in place; the session never restarts a running one
        assert(castBar.loop == true, "dashboard test cast must loop in place")
        clock = clock + 14.95
        tickers[#tickers].fn()
        assert(Log() == "", "running test cast was restarted (visible jump / relayout): " .. Log())
        -- after a real cast ended (bar hidden), the next check brings the test cast back
        castBar.shown, castBar.test = false, nil
        tickers[#tickers].fn()
        assert(Log() == "cast:test", "test cast did not come back: " .. Log())
        Reset()
        S:End(section)
        assert(not S:IsActive())
        assert(Log() == "cast:stop,tracker:off,forced:off", "close did not restore: " .. Log())
        assert(tickers[#tickers].cancelled, "renew ticker kept running")
    ''')


def test_existing_modes_and_real_cast_are_kept():
    lua = session_runtime()
    lua.execute(r'''
        local S = addon.GUI.DashboardPreview.LiveSession
        trackerPreview = true             -- user had the custom aura screen preview on
        addon._layoutPreviewForced = true -- and the layout already forced
        castBar.shown, castBar.test = true, nil -- a real cast is running
        local owner = {}
        S:Begin(owner)
        assert(Log() == "", "pre-existing modes or the real cast were touched: " .. Log())
        S:End(owner)
        assert(Log() == "" and trackerPreview and addon._layoutPreviewForced and castBar.shown,
            "closing turned off what was on before: " .. Log())
    ''')


def test_combat_restores_and_resumes():
    lua = session_runtime()
    lua.execute(r'''
        local S = addon.GUI.DashboardPreview.LiveSession
        local owner = {}
        S:Begin(owner); Reset()
        combat = true
        Fire("PLAYER_REGEN_DISABLED")
        assert(not S:IsActive() and S.combatBlocked, "combat did not stop the live layout")
        assert(Log() == "cast:stop,tracker:off,forced:off", "combat restore: " .. Log())
        Reset()
        assert(S:Begin({}) == false and Log() == "", "live layout started in combat")
        combat = false
        Fire("PLAYER_REGEN_ENABLED")
        assert(S:IsActive() and not S.combatBlocked, "did not resume after combat while open")
        S:End(nil)
        assert(not S:IsActive())
    ''')


def test_sync_live_follows_bars_every_frame():
    lua = session_runtime()
    lua.execute(r'''
        UIParent = { GetEffectiveScale = function() return 1 end }
        local Preview = addon.GUI.DashboardPreview
        -- runtime cast bar: StatusBar with a spark texture and a time text on it
        local value = 2
        local status = { IsForbidden = function() return false end }
        function status:GetObjectType() return "StatusBar" end
        function status:GetMinMaxValues() return 0, 15 end
        function status:GetInterpolatedValue() return value end
        local spark = {}
        function spark:GetParent() return status end
        function spark:GetRect() return 10 + value, 5, 4, 12 end
        function spark:GetEffectiveScale() return 1 end
        local timeText = { text = "2.0 / 15.0" }
        function timeText:GetText() return self.text end
        -- painted copy cells (as DashboardPreview.Paint leaves them)
        local function Cell(source, shown)
            local c = { _liveSource = source, shown = shown, visual = {} }
            function c:IsShown() return self.shown end
            function c:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
            function c:SetValue(v) self.value = v end
            function c:ClearAllPoints() end
            function c:SetPoint(_, _, _, x, y) self.x, self.y = x, y end
            function c:SetSize(w, h) self.w, self.h = w, h end
            function c.visual:SetText(t) self.text = t end
            return c
        end
        local bar, hiddenBar = Cell(status, true), Cell(status, false)
        local sparkCell = Cell(spark, true); sparkCell._trackRect = true
        local textCell = Cell(timeText, true)
        local host = { _previewPool = { StatusBar = { bar, hiddenBar }, Texture = { sparkCell },
            FontString = { textCell } }, _liveBounds = { left = 0, bottom = 0 }, _liveScale = 2 }

        for frame = 1, 3 do             -- every OnUpdate frame follows the runtime value
            value = value + 0.016
            timeText.text = string.format("%.2f / 15.0", value)
            assert(Preview.SyncLive(host) == 3)
            assert(bar.max == 15 and bar.value == value, "bar value lagged behind the runtime bar")
            assert(textCell.visual.text == timeText.text, "time text lagged behind")
            assert(sparkCell.x == (10 + value) * 2 and sparkCell.w == 8, "spark did not follow the fill")
        end
        assert(hiddenBar.value == nil, "hidden copy cells must not be updated")
        assert(Preview.SyncLive({}) == 0, "an unpainted host has nothing to follow")
    ''')
    section = (ROOT / "DDingUI_CDM_Option/SectionWorkspace.lua").read_text(encoding="utf-8")
    tracker = (ROOT / "DDingUI_CDM_Option/BuffTrackerGUI.lua").read_text(encoding="utf-8")
    # between the full copies (4x a second) the dashboard, section and aura-card previews follow
    # bar values every frame; their OnUpdate is removed when the preview hides
    assert section.count("DashboardPreview.SyncLive(node.visual)") == 2
    assert "if live and self.previewVisual.SyncLive then self.previewVisual:SyncLive() end" in section
    assert "if reader and reader.SyncLive and self.host then reader.SyncLive(self.host) end" in tracker
    assert section.count('self:SetScript("OnUpdate", nil)') >= 2
    assert section.count('SetScript("OnHide", function(self) self:Release() end)') >= 2


def toolkit_runtime():
    from test_cdm_auto_width import STUBS as AUTO_STUBS
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(AUTO_STUBS)
    ns = lua.table(Addon=lua.globals().addon)
    lua.execute((ROOT / "DDingUI_CDM/Utils/Toolkit.lua").read_text(encoding="utf-8"), "DDingUI_CDM", ns)
    return lua, ns


def test_forced_layout_flag_and_placeholders():
    lua, ns = toolkit_runtime()
    lua.execute(r'''
        local refreshed = 0
        addon.GroupSystem = { RequestFullUpdate = function() refreshed = refreshed + 1 end }
        assert(addon:SetLayoutPreviewForced(true) and addon:IsLayoutPreviewForced() and refreshed == 1)
        combat = true
        assert(not addon:IsLayoutPreviewForced(), "forced layout visible in combat")
        for _, f in ipairs(frames) do if f.events.PLAYER_REGEN_DISABLED then f.scripts.OnEvent(f) end end
        combat = false
        assert(not addon:IsLayoutPreviewForced() and refreshed == 2, "combat start did not clear the forced layout")
        combat = true
        assert(addon:SetLayoutPreviewForced(true) == false, "forced layout turned on in combat")
        combat = false

        C_Spell = { GetSpellTexture = function() return 555 end, GetSpellInfo = function() return { spellID = 1 } end }
        addon.IconCustomization = { GetSpellSettings = function() return nil end }
        addon.db.profile = { groupSystem = {}, iconCustomization = { spells = {} } }
        Frame.SetDesaturation = function() end
    ''')
    lua.execute((ROOT / "DDingUI_CDM/Modules/GroupSystem/BuffGroupPlaceholders.lua").read_text(encoding="utf-8"),
                "DDingUI_CDM", ns)
    lua.execute(r'''
        local P = addon.BuffGroupPlaceholders
        local settings = { iconOrder = { "cdm:one", "cdm:two" } }
        assert(P:BuildPlacements("Buffs", settings, {}) == nil, "inactive buffs shown without always-show")
        addon:SetLayoutPreviewForced(true)
        local placements = P:BuildPlacements("Buffs", settings, { ["cdm:two"] = true })
        assert(placements and #placements == 1 and placements[1]._ddOrderToken == "cdm:one",
            "forced layout must place every inactive buff (active ones are real frames)")
        -- dashboard forced layout: the buff looks as it does while active (no gray, active alpha/crop)
        assert(placements[1].inactiveGray == false and placements[1].inactiveAlpha == nil
            and placements[1].activeLook == true, "forced placeholder still uses the gray inactive look")
        addon:SetLayoutPreviewForced(false)
        assert(P:BuildPlacements("Buffs", settings, {}) == nil, "placeholders stayed after the dashboard closed")

        -- without the dashboard, "always show" keeps the configured in-game inactive look
        addon.db.profile.iconCustomization.spells = { ["1_Buff"] = { alwaysShow = "on" } }
        addon.IconCustomization.GetSpellSettings = function() return { alwaysShow = "on", inactiveAlpha = 0.4 } end
        local shown = P:BuildPlacements("Buffs", settings, { ["cdm:two"] = true })
        assert(shown and #shown == 1 and shown[1].inactiveGray == true and shown[1].inactiveAlpha == 0.4
            and shown[1].activeLook == nil, "always-show lost the in-game inactive style")
    ''')


def test_forced_placeholder_renders_active_look():
    renderer = (ROOT / "DDingUI_CDM/Modules/GroupSystem/GroupRenderer.lua").read_text(encoding="utf-8")
    body = extract("DDingUI_CDM/Modules/GroupSystem/GroupRenderer.lua",
                   "local function SetDynamicIconInactiveGray", "\nend\n") + "\nend\n"
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        local function SetAlphaIfNeeded(obj, alpha) obj:SetAlpha(alpha) end
        function GetIconCountText() return nil end
        local tex = { desat = 0, alpha = 1 }
        function tex:Show() end
        function tex:SetDesaturated(v) self.desat = v and 1 or 0 end
        function tex:SetDesaturation(v) self.desat = v end
        function tex:SetAlpha(a) self.alpha = a end
        icon = { icon = tex }
    ''' + body.replace("local function SetDynamicIconInactiveGray", "function SetDynamicIconInactiveGray").replace(
        "local function SetDynamicIconInactiveGray", "") + r'''
        SetDynamicIconInactiveGray(icon, true, 0.5)          -- in-game inactive placeholder
        assert(icon.icon.desat == 1 and icon.icon.alpha == 0.5)
        SetDynamicIconInactiveGray(icon, false, nil)         -- dashboard forced placement
        assert(icon.icon.desat == 0 and icon.icon.alpha == 1, "forced placeholder stayed gray / dim")
    ''')
    # the forced placement uses the active CDM crop, the in-game placeholder keeps the bridge crop
    assert "if entry.activeLook and skinCrop and icon.icon then" in renderer
    assert "icon.icon:SetTexCoord(skinCrop(groupSettings))" in renderer


def extract(path, start, end):
    source = (ROOT / path).read_text(encoding="utf-8").replace("\r\n", "\n")
    body = source.split(start, 1)[1].split(end, 1)[0]
    return start + body


def test_sounds_are_silent_during_previews():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        played = 0
        function PlaySoundFile() played = played + 1 end
        LSM = { Fetch = function() return "sound.ogg" end }
        forced = false
        DDingUI = { IsLayoutPreviewForced = function() return forced end }
    ''')
    tracker = extract("DDingUI_CDM/Modules/ResourceBars/BuffTrackerBar.lua",
                      "local function IsValidSoundPath", "-- Reset all sound trackers")
    icon = extract("DDingUI_CDM/Modules/IconCustomization/IconCustomization.lua",
                   "local function PlayConfiguredSound", "\nend\n") + "\nend\n"
    play = lua.execute("isInPreviewMode = false\n" + tracker.replace("local function PlayTrackerSound",
                       "function PlayTrackerSound") + "\n" + icon.replace("local function PlayConfiguredSound",
                       "function PlayConfiguredSound") + "\nreturn true")
    assert play
    lua.execute(r'''
        PlayTrackerSound("Alarm", "Master"); PlayConfiguredSound("Alarm")
        assert(played == 2, "baseline sounds did not play")
        isInPreviewMode = true
        PlayTrackerSound("Alarm", "Master")
        assert(played == 2, "custom aura preview values played a sound")
        isInPreviewMode = false; forced = true
        PlayTrackerSound("Alarm", "Master"); PlayTrackerSound(nil, "Master", "x.ogg"); PlayConfiguredSound("Alarm")
        assert(played == 2, "forced dashboard layout played a sound")
    ''')
    conditional = (ROOT / "DDingUI_CDM/Core/ConditionalActions.lua").read_text(encoding="utf-8")
    assert 'if shouldFire and not (DDingUI.IsLayoutPreviewForced and DDingUI:IsLayoutPreviewForced()) then' in conditional


def test_stop_test_cast_leaves_real_casts():
    body = extract("DDingUI_CDM/Modules/CastBars/CastBars.lua",
                   "function CastBars:IsTestCastActive()", "DDingUI.StopTestCastBar =")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        function GetTime() return 10 end
        ended = 0
        local function CastBar_OnUpdate(frame) if GetTime() >= frame.endTime then ended = ended + 1; frame.shown = false end end
        DDingUI = {}
        CastBars = {}
        bar = { shown = true, castGUID = "Cast-real", endTime = 20 }
        function bar:IsShown() return self.shown end
        DDingUI.castBar = bar
    ''' + "local CastBar_OnUpdate = function(frame) if GetTime() >= frame.endTime then ended = ended + 1; frame.shown = false end end\n" + body + r'''
        assert(CastBars:StopTestCastBar() == false and bar.shown and ended == 0, "a real cast was cancelled")
        bar.castGUID = "test_5"
        assert(CastBars:StopTestCastBar() == true and not bar.shown and ended == 1, "test cast not stopped")
    ''')


def test_estimation_paths_are_gone():
    section = (ROOT / "DDingUI_CDM_Option/SectionWorkspace.lua").read_text(encoding="utf-8")
    options = (ROOT / "DDingUI_CDM_Option/GroupSystemOptions.lua").read_text(encoding="utf-8")
    for stale in ("DashboardIdleRect", "DashboardBarRect", "PaintDashboardIdle", "idleVisual",
                  "GetDashboardBuffPreview", "CreatePreviewBar", "MarkAutoWidthMismatches"):
        assert stale not in section, "estimated drawing path came back: " + stale
    assert "GetDashboardBuffPreview" not in options
    assert "DashboardPreview.LiveSession:Begin(workspace)" in section
    assert "DashboardPreview.LiveSession:End(self)" in section


if __name__ == "__main__":
    test_session_lifecycle()
    test_existing_modes_and_real_cast_are_kept()
    test_combat_restores_and_resumes()
    test_sync_live_follows_bars_every_frame()
    test_forced_layout_flag_and_placeholders()
    test_forced_placeholder_renders_active_look()
    test_sounds_are_silent_during_previews()
    test_stop_test_cast_leaves_real_casts()
    test_estimation_paths_are_gone()
    print("CDM dashboard live layout: session, restore, combat, placeholders, silent sounds OK")
