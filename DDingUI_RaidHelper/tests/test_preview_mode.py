"""Watch the real demo UI without edit tools; keep the separate editor and live pull safe."""
import re

from lupa.lua51 import LuaRuntime

from test_raidhelper_edit_mode import ADDON_ROOT, EXTRA, MOCK, STYLE_FILES
from test_timeline_bar import BAR_EXTRA
from test_upcoming_countdown import COUNT_EXTRA


def run(checks):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().Measure = lambda text, size: len(re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)) * size * 0.65
    lua.execute(MOCK.read_text(encoding="utf-8"))
    lua.execute(EXTRA + BAR_EXTRA + COUNT_EXTRA)
    for relative in STYLE_FILES + (r"Libs\DDingUI_StyleLib\Animation.lua",):
        source = (ADDON_ROOT / relative.replace("\\", "/")).read_text(encoding="utf-8-sig")
        lua.execute("local source = ...; assert(loadstring(source))('DDingUI_RaidHelper')", source)
    ns = lua.table()
    for relative in ("Data/Registry.lua", "Data/Demo.lua", "Runtime/Engine.lua", "UI/Timeline.lua", "Core.lua"):
        source = (ADDON_ROOT / relative).read_text(encoding="utf-8-sig")
        lua.execute("local source, ns = ...; assert(loadstring(source))('DDingUI_RaidHelper', ns)", source, ns)
    lua.execute(r'''
local ns = ...
local function Noop() end
ns.Options = {
    Initialize = Noop, ApplyPendingSettings = Noop, RefreshPreviewButton = Noop,
    ShouldShowTooltips = function() return false end,
    Open = function(self) self.frame:Show() end,
    Close = function(self) self.frame:Hide() end,
}
for _, key in ipairs({ "HealerProfileUI", "MinimapButton", "BigWigsSync", "Commands" }) do
    ns[key] = { Initialize = Noop }
end
ns.eventFrame:Fire("OnEvent", "ADDON_LOADED", "DDingUI_RaidHelper")
ns.Options.frame = CreateFrame("Frame", nil, UIParent)
ns.Options.frame:Show()
''', ns)
    lua.execute("local source, ns = ...; assert(loadstring(source))('DDingUI_RaidHelper', ns)",
                (ADDON_ROOT / "Commands.lua").read_text(encoding="utf-8"), ns)
    lua.execute(checks, ns)


def test_watch_plays_real_motion_without_editing_or_saving_positions():
    run(r'''
local ns = ...
local UI = ns.TimelineUI
local x, y = ns.db.position.x, ns.db.position.y
assert(ns.db.alertPosition == nil)
ns.Commands:Handle("preview")
assert(UI:IsPreviewMode() and not UI:IsEditSessionActive() and not UI.editMode)
assert(ns.Engine.options.previewMode and not ns.Engine.options.editMode)
assert(ns.Options.frame:IsShown() and UI.frame:IsShown())
assert(UI.editRemote == nil and UI.editGrid == nil and not UI.frame.editHUD:IsShown())
assert(UI.frame.border[4] == 0 and not UI.frame.mouse and UI.frame.strata == "FULLSCREEN_DIALOG")
Advance(7.2)
local row = UI.upcomingRows[1]
assert(row.countdown.text == "3" and row.tint.alpha == 0.45 and row.drain.shown)
assert(UI.frame.syncText.text == "미리보기 · 견본 전투 재생 중")
Advance(2.8)
assert(row.countdown.text == "지금" and row.flash.alpha == 1, "the actual reminder runs its now motion")
assert(#sounds == 0, "the watch preview remains silent")
ns.db.locked = false
UI.frame:Fire("OnDragStart", "LeftButton")
UI.frame:Fire("OnDragStop", "LeftButton")
assert(not UI.frame._editDragging and ns.db.position.x == x and ns.db.position.y == y)
assert(ns.db.alertPosition == nil, "watching never detaches the reminder")
Advance(126)
assert(UI:IsPreviewMode() and not UI:IsEditSessionActive() and ns.Engine:GetTimelineTime() == 0, "demo loops without opening tools")
ns.Commands:Handle("stop")
assert(not ns.Engine:IsRunning() and not UI:IsPreviewMode() and not UI.frame:IsShown())
assert(ns.Options.frame:IsShown() and UI.frame.strata == "MEDIUM" and UI.frame.mouse)
''')


def test_switching_watch_and_editor_restores_settings_and_tools():
    run(r'''
local ns = ...
local UI = ns.TimelineUI
assert(UI:SetPreviewMode(true))
ns.Commands:Handle("edit")
assert(UI:IsEditSessionActive() and UI.editMode and not ns.Options.frame:IsShown())
local remote = UI.editRemote
assert(remote and remote:IsShown() and remote.keyboard and UI.frame.editHUD:IsShown())
assert(UI.frame.mouse and UI.frame.strata == "MEDIUM")
ns.Commands:Handle("preview")
assert(not UI:IsPreviewMode() and not UI:IsEditSessionActive(), "preview toggle stops an existing demo")
assert(ns.Options.frame:IsShown() and not remote.keyboard)
ns.Commands:Handle("test")
assert(UI:IsPreviewMode() and not UI:IsEditSessionActive() and ns.Options.frame:IsShown())
Advance(0.5)
assert(not remote:IsShown() and not UI.editGrid:IsShown() and not UI.frame.editHUD:IsShown())
ns.Commands:Handle("move")
assert(UI:IsEditSessionActive() and UI.editRemote == remote, "the same editor can be reopened")
assert(UI:SetPreviewMode(true))
assert(UI:IsPreviewMode() and not UI:IsEditSessionActive() and ns.Options.frame:IsShown())
assert(not remote.keyboard and not UI.upcomingPanel.mouse)
''')


def test_watch_stops_for_combat_and_cannot_replace_a_live_timeline():
    run(r'''
local ns = ...
local UI = ns.TimelineUI
assert(UI:SetPreviewMode(true))
combat = true
ns.eventFrame:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
assert(not UI:IsPreviewMode() and not UI.frame:IsShown() and not ns.Engine:IsRunning())
assert(not UI:SetPreviewMode(true) and not UI:SetEditMode(true))
combat = false
local model = ns.Registry:GetByKey("demo")
ns.Engine:StartModel(model, { encounter = true })
assert(not UI:SetPreviewMode(true) and not UI:SetEditMode(true))
assert(ns.Engine:IsRunning() and ns.Engine.options.encounter and UI.frame:IsShown())
''')
