"""Edit mode splits the combat timeline and the "곧 사용" alert into two modules (2026-10-10).

Runs the shipped Core.lua, UI/Timeline.lua and the embedded StyleLib 1.4 edit parts on the
shared frame-geometry mock. Real dragging, mouse focus and taint remain in-game checks.
"""
import re

from lupa.lua51 import LuaRuntime

from test_raidhelper_edit_mode import ADDON_ROOT, EXTRA, MOCK, STYLE_FILES

SCENARIO = r'''
local ns = ...
local function Noop() end

ns.Engine = {
    running = false, options = {},
    Initialize = Noop,
    IsRunning = function(self) return self.running end,
    StartModel = function(self, _, options) self.running = true; self.options = options; return true end,
    StopEncounter = function(self) self.running = false; self.options = {} end,
    StartEncounter = Noop,
    GetModel = function() return nil end,
    Tick = Noop,
    GetCooldowns = function() return {} end,
    GetLiveMechanics = function() return {} end,
}
ns.Registry = { GetByKey = function() return { name = "Demo" } end }
ns.Options = {
    Initialize = Noop, ApplyPendingSettings = Noop, RefreshPreviewButton = Noop,
    Open = function(self) self.frame:Show(); return true end,
    Close = function(self) self.frame:Hide(); return true end,
}
for _, key in ipairs({ "HealerProfileUI", "MinimapButton", "BigWigsSync", "Commands" }) do
    ns[key] = { Initialize = Noop }
end
ns.eventFrame:Fire("OnEvent", "ADDON_LOADED", "DDingUI_RaidHelper")
ns.Options.frame = CreateFrame("Frame", nil, UIParent)

local UI, db = ns.TimelineUI, ns.db
local frame, alert = UI.frame, UI.upcomingPanel
local function Rect(f) local x, y, w, h = f:Rect(); return x, y, w, h end

-- Before any editing the alert still rides right under the timeline (pre-split layout).
assert(db.alertPosition == nil)
assert(alert.points.TOPLEFT[1] == frame and alert.points.TOPLEFT[2] == "BOTTOMLEFT")
local fx, fy = Rect(frame)
local ax, ay, aw, ah = Rect(alert)
assert(ax == fx and ay + ah == fy - 6, "attached 6 px under the timeline")
assert(not alert.mouse, "outside edit mode the alert never catches the mouse")

-- Entering edit mode detaches it in place: own UIParent anchor, same spot on screen.
assert(UI:SetEditMode(true))
local saved = db.alertPosition
assert(saved and saved.point == "TOPLEFT" and saved.relativePoint == "CENTER")
assert(alert.points.TOPLEFT[1] == UIParent)
local ax2, ay2 = Rect(alert)
assert(ax2 == ax and ay2 == ay, "detaching does not move it")
assert(alert:IsShown() and alert.mover:IsShown() and alert.mouse, "alert is an editable module")
local remote = UI.editRemote
assert(remote.frameDropdown, "frame selector lists the two modules")
assert(UI.editTarget == "timeline" and remote.nameText:GetText() == "공격대 타임라인")
assert(frame.editHUD:IsShown() and not alert.editHUD:IsShown())

-- Clicking the alert selects it: mover selected, its own HUD, remote shows its name.
alert:Fire("OnMouseDown", "LeftButton")
assert(UI.editTarget == "alert" and alert.moverStyle.selected)
assert(remote.nameText:GetText() == "리마인더")
assert(alert.editHUD:IsShown() and not frame.editHUD:IsShown())
assert(frame.border[4] < 1, "timeline outline dims while the alert is selected")

-- Nudging moves only the alert.
local timelineY = db.position.y
remote:GetScript("OnKeyDown")(remote, "UP")
assert(db.alertPosition.y == saved.y + 1 and db.position.y == timelineY)

-- The dropdown selects the timeline; moving it leaves the alert where it is.
UI:SelectEditModule("timeline")
assert(remote.nameText:GetText() == "공격대 타임라인" and not alert.moverStyle.selected)
local before = { Rect(alert) }
remote:GetScript("OnKeyDown")(remote, "LEFT")
assert(db.position.x == -1)
local after = { Rect(alert) }
assert(after[1] == before[1] and after[2] == before[2], "timeline moves alone")

-- Dragging the alert: drop 5 px off the timeline's left edge snaps flush ("프레임" snap).
alert:Fire("OnDragStart", "LeftButton")
assert(UI.editTarget == "alert" and alert._editDragging)
local tx, ty = Rect(frame)
alert:ClearAllPoints(); alert:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", tx + 5, ty - 200)
alert:Fire("OnUpdate", 0.01)
assert(alert.editHUD:IsShown())
alert:Fire("OnDragStop")
local dx = Rect(alert)
assert(dx == tx, "alert left edge snapped to the timeline left edge")
assert(db.alertPosition.point == "TOPLEFT" and db.alertPosition.relativePoint == "CENTER")

-- Undo walks back per module and reselects it.
UI:SelectEditModule("timeline")
assert(UI:UndoPosition())
assert(UI.editTarget == "alert" and db.alertPosition.y == saved.y + 1)
assert(UI:UndoPosition()) -- the timeline nudge
assert(UI.editTarget == "timeline" and db.position.x == 0)
assert(UI:RedoPosition() and db.position.x == -1)

-- Remote reset on the alert puts it back under the timeline; the timeline stays.
UI:SelectEditModule("alert")
remote.buttons["초기화"]:Fire("OnClick", "LeftButton")
local rx, ry, _, rh = Rect(alert)
local nx, ny = Rect(frame)
assert(rx == nx and ry + rh == ny - 6 and db.position.x == -1)
assert(db.alertPosition and db.alertPosition.point == "TOPLEFT", "still its own module")

-- Leaving edit mode: no mouse, no mover, hidden while there is nothing to show.
assert(UI:SetEditMode(false))
assert(not alert.mouse and not alert.mover:IsShown() and not alert:IsShown())
assert(not alert.editHUD:IsShown())

-- The saved alert anchor survives a reload-style re-apply.
db.alertPosition = { point = "TOPLEFT", relativePoint = "CENTER", x = 120, y = -300 }
UI:ApplyPosition()
assert(alert.points.TOPLEFT[1] == UIParent and alert.points.TOPLEFT[3] == 120 and alert.points.TOPLEFT[4] == -300)

-- Settings "위치 초기화" outside edit mode resets both and re-attaches the alert.
UI:ResetPosition()
assert(db.alertPosition == nil and db.position.x == 0 and db.position.y == -180)
assert(alert.points.TOPLEFT[1] == frame)
'''


def run(extra=""):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().Measure = lambda text, size: len(re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)) * size * 0.65
    lua.execute(MOCK.read_text(encoding="utf-8"))
    lua.execute(EXTRA)
    for relative in STYLE_FILES:
        source = (ADDON_ROOT / relative.replace("\\", "/")).read_text(encoding="utf-8-sig")
        lua.execute("local source = ...; assert(loadstring(source))('DDingUI_RaidHelper')", source)
    ns = lua.table()
    for relative in ("UI/Timeline.lua", "Core.lua"):
        source = (ADDON_ROOT / relative).read_text(encoding="utf-8-sig")
        lua.execute("local source, ns = ...; assert(loadstring(source))('DDingUI_RaidHelper', ns)", source, ns)
    lua.execute(SCENARIO, ns)
    if extra:
        lua.execute(extra, ns)


def test_timeline_and_alert_are_separate_edit_modules():
    run()


def test_edit_labels_do_not_cover_the_other_module_or_alert_rows():
    run(r'''
local ns = ...
local UI = ns.TimelineUI
assert(UI:SetEditMode(true))
local function Overlaps(a, b)
    local ax, ay, aw, ah = a:Rect()
    local bx, by, bw, bh = b:Rect()
    return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end
for _, width in ipairs({200, 300, 400, 680, 1200}) do
    ns.db.timelineWidth = width
    UI:ApplyDisplaySettings()
    UI:ResetPosition("alert")
    UI:SelectEditModule("timeline")
    assert(not Overlaps(UI.frame.editHUD.box, UI.upcomingPanel),
        "timeline coordinates must not cover the alert module")
    UI:SelectEditModule("alert")
    assert(not Overlaps(UI.upcomingPanel.editHUD.box, UI.frame),
        "alert coordinates must not cover the timeline")
end
ns.Engine.GetCooldowns = function() return {
    {spellID = 31821, label = "오라 숙련", t = 42},
    {spellID = 740, label = "평온", t = 44},
    {spellID = 62618, label = "신의 권능: 방벽", t = 46},
} end
UI:UpdateUpcomingCooldowns(40)
assert(not UI.upcomingPanel.moverStyle.label:IsShown(),
    "module name must not cover the live alert rows")
UI:UpdateUpcomingCooldowns(100)
assert(UI.upcomingPanel.moverStyle.label:IsShown(), "empty module keeps its name")

-- Exercise the real dropdown row callback, not just SelectEditModule directly.
UI:SelectEditModule("timeline")
UI.editRemote.frameDropdown.button:Fire("OnClick", "LeftButton")
local chosen = false
for _, object in ipairs(objects) do
    if object.kind == "FontString" and object.text == "리마인더"
        and object.parent.kind == "Button" and object.parent:IsVisible() then
        object.parent:Fire("OnClick", "LeftButton")
        chosen = true
        break
    end
end
assert(chosen and UI.editTarget == "alert" and UI.editRemote.frameDropdown:GetValue() == "alert")
''')


if __name__ == "__main__":
    run()
    print("PASS: RaidHelper edit modules (timeline / alert)")
