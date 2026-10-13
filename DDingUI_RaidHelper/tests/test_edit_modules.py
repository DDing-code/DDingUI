"""Edit mode splits the combat timeline and the "곧 사용" alert into two modules (2026-10-10).

Runs the shipped Core.lua, UI/Timeline.lua and the embedded StyleLib 1.4 edit parts on the
shared frame-geometry mock. Real dragging, mouse focus and taint remain in-game checks.
"""
import re

from lupa.lua51 import LuaRuntime

from test_raidhelper_edit_mode import ADDON_ROOT, EXTRA, MOCK, STYLE_FILES

# WoW coordinates use the region's effective scale; clamping constrains its whole rect.
GEOMETRY_EXTRA = r'''
function methods:GetEffectiveScale()
    return self:GetScale() * (self.parent and self.parent:GetEffectiveScale() or 1)
end
function methods:SetClampedToScreen(value) self.clamped = value end
local factors = {TOPLEFT={0,1},TOP={.5,1},TOPRIGHT={1,1},LEFT={0,.5},CENTER={.5,.5},
    RIGHT={1,.5},BOTTOMLEFT={0,0},BOTTOM={.5,0},BOTTOMRIGHT={1,0}}
function methods:Rect()
    if self == UIParent then return 0, 0, self.width or 1280, self.height or 900 end
    local scale = self:GetEffectiveScale()
    local width = self.width or (self.text and Measure(self.text, self.fontSize or 12)) or 0
    local height = self.height or (self.text and (self.fontSize or 12)*1.2) or 0
    local ax, ay = {}, {}
    for point, a in pairs(self.points) do
        local rx, ry, rw, rh = a[1]:Rect()
        local ratio, f, own = a[1]:GetEffectiveScale()/scale, factors[a[2]], factors[point]
        ax[#ax+1] = {own[1], (rx+rw*f[1])*ratio+a[3]}
        ay[#ay+1] = {own[2], (ry+rh*f[2])*ratio+a[4]}
    end
    local function Solve(points, size)
        for i=1,#points do for j=i+1,#points do if points[i][1] ~= points[j][1] then
            size = (points[i][2]-points[j][2])/(points[i][1]-points[j][1])
            return points[i][2]-points[i][1]*size, size
        end end end
        return #points > 0 and points[1][2]-points[1][1]*size or 0, size
    end
    local x, y; x, width = Solve(ax, width); y, height = Solve(ay, height)
    if self.clamped then
        local ratio = UIParent:GetEffectiveScale()/scale
        x = math.max(0, math.min(x, UIParent:GetWidth()*ratio-width))
        y = math.max(0, math.min(y, UIParent:GetHeight()*ratio-height))
    end
    return x, y, width, height
end
'''

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


def run(extra="", scenario=SCENARIO, setup=""):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().Measure = lambda text, size: len(re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)) * size * 0.65
    lua.execute(MOCK.read_text(encoding="utf-8"))
    lua.execute(EXTRA)
    if setup:
        lua.execute(setup)
    for relative in STYLE_FILES:
        source = (ADDON_ROOT / relative.replace("\\", "/")).read_text(encoding="utf-8-sig")
        lua.execute("local source = ...; assert(loadstring(source))('DDingUI_RaidHelper')", source)
    ns = lua.table()
    for relative in ("UI/Timeline.lua", "Core.lua"):
        source = (ADDON_ROOT / relative).read_text(encoding="utf-8-sig")
        lua.execute("local source, ns = ...; assert(loadstring(source))('DDingUI_RaidHelper', ns)", source, ns)
    lua.execute(scenario, ns)
    if extra:
        lua.execute(extra, ns)


def test_timeline_and_alert_are_separate_edit_modules():
    run()


def test_first_edit_keeps_reminder_position_at_screen_edges():
    for scale in (0.6, 1, 1.35, 1.6):
        run("local scale = " + str(scale) + r'''
local ns = ...
local UI = ns.TimelineUI
UIParent:SetScale(0.7)
ns.db.timelineScale = scale
UI:ApplyDisplaySettings()
-- No mover has been created yet on a fresh login.
assert(not UI.upcomingPanel.mover)
ns.db.alertPosition = {point="TOPLEFT", relativePoint="BOTTOMLEFT", x=90, y=45}
UI:ApplyPosition()
local bx, by = UI:GetFrameRect("alert")
assert(UI:SetEditMode(true))
local ax, ay = UI:GetFrameRect("alert")
assert(math.abs(ax-bx) < 0.01 and math.abs(ay-by) < 0.01,
    string.format("edit entry moved reminder at scale %.2f: (%.1f, %.1f) -> (%.1f, %.1f)",
        scale, bx, by, ax, ay))
assert(ns.db.alertPosition.x == 90 and ns.db.alertPosition.y == 45, "saved anchor is preserved")
assert(UI:SetEditMode(false))
UI:ApplyPosition()
ax, ay = UI:GetFrameRect("alert")
assert(math.abs(ax-bx) < 0.01 and math.abs(ay-by) < 0.01, "reload anchor stays in place")
''', scenario=SCENARIO.split("local UI, db =")[0], setup=GEOMETRY_EXTRA)


def test_scaled_attached_reminder_detaches_in_place():
    for scale in (0.6, 1, 1.35, 1.6):
        run("local scale = " + str(scale) + r'''
local ns = ...
local UI = ns.TimelineUI
UIParent:SetScale(0.7)
ns.db.timelineScale = scale
ns.db.position = {point="BOTTOMLEFT", relativePoint="BOTTOMLEFT", x=90, y=45}
UI:ApplyDisplaySettings()
UI:ApplyPosition()
local tx, ty = UI:GetFrameRect("timeline")
local bx, by = UI:GetFrameRect("alert")
assert(UI:SetEditMode(true))
local ax, ay = UI:GetFrameRect("alert")
local tolerance = scale*0.5 + 0.01 -- integer saved offsets round by at most half a unit
assert(math.abs(ax-bx) <= tolerance and math.abs(ay-by) <= tolerance,
    "scaled attached reminder stays in place when detached")
local tx2, ty2 = UI:GetFrameRect("timeline")
assert(tx == tx2 and ty == ty2, "entering edit does not move the timeline")
assert(UI:SetEditMode(false))
UI:ApplyPosition()
local rx, ry = UI:GetFrameRect("alert")
assert(math.abs(rx-ax) < 0.01 and math.abs(ry-ay) < 0.01, "saved independent anchor is stable")
''', scenario=SCENARIO.split("local UI, db =")[0], setup=GEOMETRY_EXTRA)


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
