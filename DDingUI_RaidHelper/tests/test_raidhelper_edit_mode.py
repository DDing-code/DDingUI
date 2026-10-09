"""RaidHelper preview/edit mode follows the series edit-mode spec (C5, C12).

Runs the shipped Core.lua, UI/Timeline.lua and the embedded StyleLib 1.4 parts in
Lua 5.1 with the shared frame-geometry mock. WoW rendering, keyboard focus and
taint remain in-game checks.
"""
from pathlib import Path
import re

from lupa.lua51 import LuaRuntime

ADDON_ROOT = Path(__file__).resolve().parents[1]
SUPER_ROOT = ADDON_ROOT.parent
MOCK = SUPER_ROOT / "DDingUI_FX" / "tests" / "wow_mock.lua"
STYLE_FILES = (
    r"Libs\LibStub\LibStub.lua",
    r"Libs\DDingUI_StyleLib\Core.lua",
    r"Libs\DDingUI_StyleLib\Colors.lua",
    r"Libs\DDingUI_StyleLib\Gradient.lua",
    r"Libs\DDingUI_StyleLib\Motion.lua",
    r"Libs\DDingUI_StyleLib\Widgets.lua",
    r"Libs\DDingUI_StyleLib\EditMode.lua",
)

EXTRA = r'''
print = function() end
function methods:GetPoint(index)
    local point, anchor = next(self.points)
    if not point then return nil end
    return point, anchor[1], anchor[2], anchor[3], anchor[4]
end
function methods:GetLeft() local x = self:Rect(); return x end
function methods:GetBottom() local _, y = self:Rect(); return y end
function methods:GetTop() local _, y, _, h = self:Rect(); return y + h end
function methods:GetSize() return self:GetWidth(), self:GetHeight() end
function methods:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function methods:HasFocus() return self.focus end
function methods:SetFocus() self.focus = true end
function methods:ClearFocus() self.focus = false end
function methods:SetScale(v) self.scale = v end
function methods:GetScale() return self.scale or 1 end
function methods:CreateAnimationGroup() return CreateFrame("AnimationGroup", nil, self) end
function methods:CreateAnimation() return CreateFrame("Animation", nil, self) end
function methods:CreateLine() return CreateFrame("Line", nil, self) end
function methods:GetVertexColor() return 1, 1, 1, 1 end
function methods:GetFont() return self.fontPath, self.fontSize, self.fontFlags end
function methods:GetStringWidth() return Measure(self.text or "", self.fontSize or 12) end
function methods:SetMinMaxValues(a, b) self.min, self.max = a, b end
function methods:SetValue(v) self.value = v end
function methods:GetValue() return self.value end
function methods:EnableKeyboard(v) self.keyboard = v end
for _, key in ipairs({
    "SetPropagateKeyboardInput", "SetClampRectInsets", "SetDesaturated",
    "SetTextInsets", "SetNumeric", "SetMaxLetters", "HighlightText", "SetHitRectInsets",
    "SetClipsChildren", "SetToplevel", "SetBlendMode", "SetFixedFrameStrata", "SetFixedFrameLevel",
    "SetHighlightTexture", "SetOrder", "SetDuration", "SetFromAlpha", "SetToAlpha", "SetStartDelay",
    "SetToFinalAlpha", "Play", "Stop", "SetJustifyV", "SetMaxLines", "SetThickness", "SetAltArrowKeyMode",
    "SetValueStep", "SetObeyStepOnDrag", "SetOrientation", "SetThumbTexture", "LockHighlight",
    "UnlockHighlight", "SetStartPoint", "SetEndPoint",
}) do
    if not methods[key] then methods[key] = function() end end
end
C_Timer.After = function(_, callback) callback() end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function geterrorhandler() return error end
function IsMouseButtonDown() return false end
shiftDown, controlDown = false, false
function IsShiftKeyDown() return shiftDown end
function IsControlKeyDown() return controlDown end
function GetCurrentKeyBoardFocus() return nil end
function Advance(seconds)
    now = now + seconds
    for _, frame in ipairs(objects) do
        if frame:IsVisible() then frame:Fire("OnUpdate", seconds) end
    end
end
'''

SCENARIO = r'''
local ns = ...
local function Noop() end
local opened = 0

ns.Engine = {
    running = false, options = {},
    Initialize = Noop,
    IsRunning = function(self) return self.running end,
    StartModel = function(self, _, options) self.running = true; self.options = options; return true end,
    StopEncounter = function(self) self.running = false; self.options = {} end,
    StartEncounter = function(self) self.encounterStarted = true end,
    GetModel = function() return nil end,
    Tick = Noop,
    GetCooldowns = function() return {} end,
    GetLiveMechanics = function() return {} end,
}
ns.Registry = { GetByKey = function(_, key) assert(key == "demo"); return { name = "Demo" } end }
ns.Options = {
    Initialize = Noop, ApplyPendingSettings = Noop, RefreshPreviewButton = Noop,
    Open = function(self) opened = opened + 1; self.frame:Show(); return true end,
    Close = function(self) self.frame:Hide(); return true end,
}
for _, key in ipairs({ "HealerProfileUI", "MinimapButton", "BigWigsSync", "Commands" }) do
    ns[key] = { Initialize = Noop }
end

local events = ns.eventFrame
events:Fire("OnEvent", "ADDON_LOADED", "DDingUI_RaidHelper")
assert(events.events.PLAYER_REGEN_DISABLED, "combat start must end edit mode")
assert(not events.events.COMBAT_LOG_EVENT_UNFILTERED and not events.events.COMBAT_LOG_EVENT)

local UI = ns.TimelineUI
local frame = UI.frame
local db = ns.db
assert(frame.editHUD and frame.editHUD.box, "HUD must come from StyleLib CreateMoverHUD")
assert(frame.editHUD.box.points.TOPRIGHT[2] == "BOTTOMRIGHT", "C5: readout sits below the frame")

-- Entering preview closes the settings window and opens the remote, grid and HUD.
ns.Options.frame = CreateFrame("Frame", nil, UIParent)
ns.Options.frame:Show()
assert(UI:SetPreviewMode(true))
assert(UI:IsPreviewMode() and UI:IsEditSessionActive())
assert(not ns.Options.frame:IsShown(), "settings window closes on entry")
local remote = UI.editRemote
assert(remote and remote:IsShown() and remote.keyboard, "edit remote opens with key capture")
assert(remote:GetWidth() == 300)
assert(remote.buttons["완료"] and remote.buttons["초기화"] and remote.buttons["실행 취소"] and remote.buttons["다시 실행"])
assert(remote.frameDropdown, "two edit modules (timeline / alert): frame selector")
assert(UI.editGrid:IsShown() and UI.editGrid:GetSpacing() == 32)
assert(frame.editHUD:IsShown())
assert(frame.editHUD.box.text:GetText():find("^X 0  Y %-180  "), frame.editHUD.box.text:GetText())
assert(remote.nameText:GetText() == "공격대 타임라인")
assert(remote.yField.editBox:GetText() == "-180")
local accent = UI.accentFrom
assert(frame.border[1] == accent[1] and frame.border[3] == accent[3], "accent edit border")

-- Keyboard nudge (1px, Shift 10px) writes ns.db.position.
remote:GetScript("OnKeyDown")(remote, "UP")
assert(db.position.y == -179 and db.position.x == 0)
shiftDown = true
remote:GetScript("OnKeyDown")(remote, "LEFT")
shiftDown = false
assert(db.position.x == -10 and db.position.y == -179)
assert(frame.points.CENTER[3] == -10 and frame.points.CENTER[4] == -179, "frame re-anchored")
assert(frame.editHUD.box.text:GetText():find("^X %-10  Y %-179  "))

-- X/Y input, undo/redo, reset.
remote.xField.editBox:SetText("25"); remote.yField.editBox:SetText("-40")
remote:ApplyXY()
assert(db.position.x == 25 and db.position.y == -40)
controlDown = true
remote:GetScript("OnKeyDown")(remote, "Z")
assert(db.position.x == -10 and db.position.y == -179)
remote:GetScript("OnKeyDown")(remote, "Y")
assert(db.position.x == 25 and db.position.y == -40)
controlDown = false
remote.buttons["초기화"]:Fire("OnClick", "LeftButton")
assert(db.position.x == 0 and db.position.y == -180 and db.position.point == "CENTER")

-- Remote position is saved only under the approved editRemotePos key.
local before = {}
for key in pairs(db) do before[key] = true end
remote:ClearAllPoints(); remote:SetPoint("TOP", UIParent, "TOP", 40, -90)
remote.titleBar:Fire("OnDragStop")
local saved = db.editRemotePos
assert(saved and saved.point == "TOP" and saved.x == 40 and saved.y == -90)
for key in pairs(db) do assert(before[key] or key == "editRemotePos", key) end

-- Drag: HUD/guides follow the live rectangle; drop snaps to the screen center line.
-- (The alert module is parked far away so its edges do not take part in the snap.)
db.alertPosition = { point = "TOPLEFT", relativePoint = "CENTER", x = 300, y = 300 }
UI:ApplyAlertPosition()
frame:Fire("OnDragStart", "LeftButton")
assert(frame._editDragging)
frame:ClearAllPoints(); frame:SetPoint("CENTER", UIParent, "CENTER", 3, -178)
frame:Fire("OnUpdate", 0.01)
assert(frame.editHUD.box.text:GetText():find("^X 3  Y %-178  "), frame.editHUD.box.text:GetText())
assert(UI.editGuides:IsShown())
frame:Fire("OnDragStop")
assert(not UI.editGuides:IsShown())
assert(db.position.x == 0 and db.position.y == -178, db.position.x .. "," .. db.position.y)

-- A non-CENTER saved anchor is kept (anchor-relative offsets, same during and after the drag).
db.position = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 100, y = -100 }
UI:ApplyPosition()
frame:Fire("OnDragStart", "LeftButton")
frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 120, -130)
frame:Fire("OnUpdate", 0.01)
assert(frame.editHUD.box.text:GetText():find("^X 120  Y %-130  "))
frame:Fire("OnDragStop")
assert(db.position.point == "TOPLEFT" and db.position.x == 120 and db.position.y == -130)

-- Esc ends edit mode and reopens the settings window that was open.
remote:GetScript("OnKeyDown")(remote, "ESCAPE")
assert(not UI:IsPreviewMode() and not UI:IsEditSessionActive())
assert(not frame.editHUD:IsShown())
assert(opened == 1 and ns.Options.frame:IsShown(), "settings window reopens after Esc")
Advance(0.5)
assert(not remote:IsShown(), "remote closes")
assert(not UI.editGrid:IsShown(), "grid fades out and hides")
assert(frame.border[1] ~= accent[1] or frame.border[3] ~= accent[3], "edit border restored")

-- The remote reopens at the saved position (same remote, no duplicate).
assert(UI:SetPreviewMode(true))
assert(UI.editRemote == remote and remote:IsShown())

-- Combat start ends edit mode without reopening the settings window.
events:Fire("OnEvent", "PLAYER_REGEN_DISABLED")
assert(not UI:IsPreviewMode() and not UI:IsEditSessionActive())
assert(opened == 1 and not ns.Options.frame:IsShown(), "no reopen in combat")
assert(not ns.Engine.running)
assert(not remote:IsShown() and not remote.keyboard, "combat exit hides the remote at once and stops key capture")

-- Entering is blocked in combat.
combat = true
assert(not UI:SetPreviewMode(true))
assert(not UI:IsPreviewMode())
combat = false

-- With the settings window closed, leaving does not open it.
ns.Options.frame:Hide()
assert(UI:SetPreviewMode(true))
remote.buttons["완료"]:Fire("OnClick", "LeftButton")
assert(not UI:IsPreviewMode() and opened == 1 and not ns.Options.frame:IsShown())

-- The remote title-bar X ends edit mode through onDone (C12).
assert(UI:SetPreviewMode(true))
remote.titleBar.closeBtn:Fire("OnClick", "LeftButton")
assert(not UI:IsPreviewMode() and not UI:IsEditSessionActive())

-- Shared title-bar edit button (settings window) follows preview state.
local SL = ns:GetStyleLib()
local host = CreateFrame("Frame", nil, UIParent); host:SetSize(1080, 700)
local bar = SL.CreateTitleBar(host, "RaidHelper", "DDingUI RaidHelper", "1", {
    editMode = { onClick = function() UI:TogglePreviewMode() end, isActive = function() return UI:IsPreviewMode() end },
})
assert(bar.editButton and bar.editButton.label:GetText() == "편집 모드")
bar.editButton:Fire("OnClick", "LeftButton")
assert(UI:IsPreviewMode()); bar.editButton:Refresh()
assert(bar.editButton.label:GetText() == "편집 중")
assert(UI:SetPreviewMode(false)); bar.editButton:Refresh()
assert(bar.editButton.label:GetText() == "편집 모드")

-- ENCOUNTER_START keeps ending preview (and does not reopen the settings window).
ns.Options.frame:Show()
assert(UI:SetPreviewMode(true))
events:Fire("OnEvent", "ENCOUNTER_START", 1, "Boss", 16, 20)
assert(not UI:IsPreviewMode() and ns.Engine.encounterStarted and opened == 1)
'''


def run():
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


def test_edit_mode_follows_series_spec():
    run()


def test_timeline_uses_stylelib_edit_parts_without_combat_log():
    source = (ADDON_ROOT / "UI" / "Timeline.lua").read_text(encoding="utf-8")
    core = (ADDON_ROOT / "Core.lua").read_text(encoding="utf-8")
    for name in ("CreateEditRemote", "CreateEditGrid", "CreateEditGuides", "CreateMoverHUD", "SnapToGrid"):
        assert name in source, name
    assert "frame.centerV" not in source and "BOTTOMRIGHT\", frame, \"TOPRIGHT\"" not in source
    for text in (source, core):
        assert "CombatLogGetCurrentEventInfo" not in text
        assert 'RegisterEvent("COMBAT_LOG_EVENT' not in text


if __name__ == "__main__":
    run()
    test_timeline_uses_stylelib_edit_parts_without_combat_log()
    print("PASS: RaidHelper edit mode (remote, Esc, combat exit, nudge, remote position)")
