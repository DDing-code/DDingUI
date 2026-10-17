"""Toolkit 편집 모드가 StyleLib 1.4 공용 부품(C5·C12)으로 동작하는지 검사.

넛지 Shift ×10, 격자 기본값(켜짐·32, 16/32/64 순환), 설정창 복귀, 리모컨 위치 저장,
스냅 규칙(격자 숨김과 무관), 전투 자동 종료.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
SUPER = ROOT.parent
sys.path.insert(0, str(ROOT / "tests"))
from ui_runtime import runtime  # noqa: E402

STYLELIB = ("Core.lua", "Colors.lua", "Gradient.lua", "Motion.lua", "Widgets.lua", "EditMode.lua")

HARNESS = r'''
local M = getmetatable(UIParent).__index
function M:GetPoint(i)
    local p, a = next(self.points)
    if not p then return nil end
    return p, a[1], a[2], a[3], a[4]
end
function M:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function M:HasFocus() return false end
function M:GetNumChildren() return 0 end
function M:UnregisterAllEvents() self.events = {} end
for _, k in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetClampRectInsets", "SetFrameLevel",
    "StartMoving", "StopMovingOrSizing", "SetToplevel", "SetMovable", "RegisterForDrag", "RegisterForClicks",
    "SetAutoFocus", "SetJustifyH", "SetJustifyV", "SetWordWrap", "ClearFocus", "SetTextInsets", "SetMaxLetters",
    "SetNumeric", "SetCursorPosition", "HighlightText", "SetHitRectInsets", "SetObeyStepOnDrag", "SetValueStep",
    "SetMinMaxValues", "SetOrientation", "SetThumbTexture", "EnableMouseWheel", "SetSmoothing", "SetClampedToScreen" }) do
    if not M[k] then M[k] = function() end end
end
function M:GetSize() return self:GetWidth(), self:GetHeight() end
GetCurrentKeyBoardFocus = function() return nil end
IsShiftKeyDown = function() return shiftDown or false end
IsControlKeyDown = function() return false end
function strsplit(sep, s) local out = {}; for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end; return unpack(out) end
function Emit(event, ...)
    for _, f in ipairs(objects) do
        if f.events and f.events[event] and f.scripts and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
function GameTooltip:SetOwner() end
function GameTooltip:SetText() end
function GameTooltip:AddLine() end
C_Timer.After = function(_, fn) fn() end
UIParent:SetSize(1600, 900)
printed = {}
local realPrint = print
function print(...) printed[#printed + 1] = table.concat({ tostringall(...) }, " ") end
function tostringall(...) local t = {}; for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end; return unpack(t) end

-- Toolkit namespace with two registered test frames
ns = {}
ns.L = setmetatable({}, { __index = function(_, k) return k end })
ns.CHAT_PREFIX = "[T] "
ns.PrintError = function(msg) printed[#printed + 1] = "ERR " .. tostring(msg) end
ns.db = { profile = { modules = { CombatTimer = true, DeathAlert = false }, moverSettings = {},
    CombatTimer = { position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = -100 } },
    DeathAlert = { position = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 } } } }
ns.defaults = { profile = { CombatTimer = { position = { point = "CENTER", x = 0, y = -100 } } } }
ns.DDingToolKit = { modules = {}, version = "2.2.0" }
ns.CombatTimer = { enabled = true }
ns.DeathAlert = { enabled = false }
configShown = false
ns.ConfigUI = {
    IsShown = function() return configShown end,
    Hide = function() configShown = false; hidden = (hidden or 0) + 1 end,
    Show = function() configShown = true; reopened = (reopened or 0) + 1 end,
}
local timerFrame = CreateFrame("Frame", "DDingToolKit_CombatTimerFrame", UIParent)
timerFrame:SetSize(120, 40); timerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
local deathFrame = CreateFrame("Frame", "DDingToolKit_DeathAlertFrame", UIParent)
deathFrame:SetSize(400, 50); deathFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
'''


def toolkit_runtime():
    lua = runtime()
    lua.globals().Measure = lambda text, size: len(re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)) * size * .65
    lua.execute(HARNESS)
    bundle = ROOT / "Libs/DDingUI_StyleLib"
    for name in STYLELIB:
        lua.execute('local source,owner=...; assert(loadstring(source))(owner)',
                    (bundle / name).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit")
    for rel in ("UI/Controls.lua", "Core/Movers.lua"):
        lua.execute('local source,owner,ns=...; assert(loadstring(source))(owner, ns)',
                    (ROOT / rel).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('Emit("PLAYER_LOGIN")')
    return lua


def enter(lua):
    lua.execute('ns.ToolkitMovers:ToggleConfigMode()')
    assert lua.eval('ns.ToolkitMovers:IsActive()')


def test_toc_loads_editmode_and_slash_alias():
    toc = (ROOT / "DDingUI_Toolkit.toc").read_text(encoding="utf-8")
    assert toc.index("Libs\\DDingUI_StyleLib\\Widgets.lua") < toc.index("Libs\\DDingUI_StyleLib\\EditMode.lua") < toc.index("Core\\Movers.lua")
    slash = (ROOT / "Core/SlashCommands.lua").read_text(encoding="utf-8")
    assert 'command == "move" or command == "unlock" or command == "edit"' in slash
    movers = (ROOT / "Core/Movers.lua").read_text(encoding="utf-8")
    for banned in ("1, 0.67, 0.18", "1, 0.2, 0.2", "0.8, 0.8, 0.8, 0.15", "0.35, 0.80, 1.0", "DDingToolKitNudgeFrame"):
        assert banned not in movers, banned
    for required in ("Lib.CreateEditRemote(", "Lib.StyleMover(", "Lib.CreateMoverHUD(", "Lib.CreateEditGrid(",
                     "Lib.CreateEditGuides(", "Lib.SnapToGrid(", "Lib.SnapToCenter(", "Lib.SnapToRects("):
        assert required in movers, required


def test_grid_defaults_and_spacing_cycle():
    lua = toolkit_runtime()
    g = lua.globals()
    g.ns.db.profile.moverSettings.gridEnabled = False  # old saved "off" + legacy 20px spacing
    g.ns.db.profile.moverSettings.gridSize = 20
    enter(lua)
    s = g.ns.ToolkitMovers.GetEditorSettings(g.ns.ToolkitMovers)
    assert s.gridEnabled is True and s.gridSize == 32 and s.snapThreshold == 8
    saved = g.ns.db.profile.moverSettings
    lua.execute('''
        local remote = DDingUI_StyleLib and nil
        for _, f in ipairs(objects) do if f.gridSpacingBtn then remote = f end end
        assert(remote, "remote not built")
        remote.gridSpacingBtn:GetScript("OnClick")(remote.gridSpacingBtn)
    ''')
    assert s.gridSize == 64 and saved.gridSize == 64
    lua.execute('''
        for _, f in ipairs(objects) do if f.gridSpacingBtn then f.gridSpacingBtn:GetScript("OnClick")(f.gridSpacingBtn) end end
    ''')
    assert s.gridSize == 16
    # grid toggled off, snap-to-grid still works (snap follows the checkbox, not the drawn grid)
    lua.execute('for _, f in ipairs(objects) do if f.gridCheck then f.gridCheck:SetChecked(false) end end')
    assert s.gridEnabled is False and s.snapToGrid is True


def test_nudge_shift_ten_and_undo():
    lua = toolkit_runtime()
    g = lua.globals()
    enter(lua)
    lua.execute('''
        for _, f in ipairs(objects) do if f.gridSpacingBtn then remote = f end end
        local ov = _G["DDingToolKitMover_CombatTimer"]
        assert(ov and ov:IsShown() and ov.surface and ov.selectionHUD)
        ov:Fire("OnClick", "LeftButton")
        assert(ov.selectionHUD:IsShown() and ov.surface.selected)
        assert(remote.nameText:GetText() == "Combat Timer", remote.nameText:GetText())
    ''')
    def pos():
        p = g.ns.db.profile.CombatTimer.position  # SavePos replaces the table each time
        return p.x, p.y
    assert pos() == (0, -100)
    g.shiftDown = False
    lua.execute('remote:GetScript("OnKeyDown")(remote, "UP")')
    assert pos() == (0, -99)
    g.shiftDown = True
    lua.execute('remote:GetScript("OnKeyDown")(remote, "RIGHT")')
    assert pos() == (10, -99)
    lua.execute('ns.ToolkitMovers:Undo()')
    assert pos() == (0, -99)
    lua.execute('ns.ToolkitMovers:Redo()')
    assert pos() == (10, -99)
    hud = lua.eval('_G["DDingToolKitMover_CombatTimer"].selectionHUD.box.text:GetText()')
    assert hud.startswith("X 10  Y -99")
    assert lua.eval('remote.xField.editBox:GetText()') == "10"
    lua.execute('remote:GetScript("OnKeyDown")(remote, "ESCAPE")')  # Esc leaves edit mode
    assert not lua.eval('ns.ToolkitMovers:IsActive()')


def test_config_window_reopens_after_edit_mode():
    lua = toolkit_runtime()
    g = lua.globals()
    g.configShown = True
    enter(lua)
    assert g.configShown is False and g.hidden == 1
    lua.execute('ns.ToolkitMovers:ToggleConfigMode()')
    assert g.configShown is True and g.reopened == 1
    # entered without the window: nothing reopens
    g.configShown = False
    lua.execute('ns.ToolkitMovers:ToggleConfigMode(); ns.ToolkitMovers:ToggleConfigMode()')
    assert g.reopened == 1 and g.configShown is False
    # ConfigUI:Show() while editing: exit without a second Show from Movers
    g.configShown = True
    enter(lua)
    lua.execute('ns.ToolkitMovers:ToggleConfigMode({ reopenConfig = false })')
    assert g.reopened == 1 and g.configShown is False
    # combat auto-exit never reopens the window
    g.configShown = True
    enter(lua)
    lua.execute('Emit("PLAYER_REGEN_DISABLED")')
    assert not lua.eval('ns.ToolkitMovers:IsActive()') and g.configShown is False


def test_remote_position_saved_under_panel_position():
    lua = toolkit_runtime()
    g = lua.globals()
    g.ns.db.profile.moverSettings.panelPosition = lua.table(point="BOTTOM", relativePoint="BOTTOM", x=12, y=80)
    enter(lua)
    point, x, y = lua.eval('''(function()
        for _, f in ipairs(objects) do if f.gridSpacingBtn then
            local p, _, _, x, y = f:GetPoint(1); return p, x, y end end end)()''')
    assert (point, x, y) == ("BOTTOM", 12, 80)
    lua.execute('''
        for _, f in ipairs(objects) do if f.gridSpacingBtn then
            f:ClearAllPoints(); f:SetPoint("TOP", UIParent, "TOP", -40.4, -55.6)
            f.titleBar:Fire("OnDragStop")
        end end
    ''')
    saved = g.ns.db.profile.moverSettings.panelPosition
    assert (saved.point, saved.relativePoint, saved.x, saved.y) == ("TOP", "TOP", -40, -56)


def test_disabled_module_mover_and_snap_to_center():
    lua = toolkit_runtime()
    g = lua.globals()
    enter(lua)
    assert lua.eval('_G["DDingToolKitMover_DeathAlert"].surface.disabled') is True
    assert lua.eval('_G["DDingToolKitMover_DeathAlert"].surface.badge:IsShown()') is True
    lua.execute('''
        local ov = _G["DDingToolKitMover_CombatTimer"]
        ov:Fire("OnClick", "LeftButton")
        ns.ToolkitMovers:SetSelectedPosition(5, -100)
    ''')
    pos = g.ns.db.profile.CombatTimer.position
    assert (pos.x, pos.y) == (5, -100)  # typed values are exact; snapping applies to drags only


def test_party_tracker_stays_in_edit_mode_across_preview_states():
    lua = toolkit_runtime()
    lua.execute('''
        ns.db.profile.modules.PartyTracker = true
        ns.db.profile.PartyTracker = {
            position = { point="CENTER", relativePoint="CENTER", x=-500, y=-110 },
            manaPosition = { point="CENTER", relativePoint="CENTER", x=0, y=-150 },
        }
        local main = CreateFrame("Frame", "DDingToolKit_PartyTrackerFrame", UIParent)
        main:SetSize(150, 200); main:SetPoint("CENTER", UIParent, "CENTER", -500, -110); main:Hide()
        local mana = CreateFrame("Frame", "DDingToolKit_PartyTrackerManaFrame", UIParent)
        mana:SetSize(150, 150); mana:SetPoint("CENTER", UIParent, "CENTER", 0, -150); mana:Hide()
        previewEntered = 0
        ns.PartyTracker = {
            enabled = true,
            EnterEditPreview = function() previewEntered = previewEntered + 1; main:Show(); mana:Show() end,
            ExitEditPreview = function() main:Hide(); mana:Hide() end,
        }
        ns.DDingToolKit.modules.PartyTracker = ns.PartyTracker
    ''')
    enter(lua)
    lua.execute('''
        assert(previewEntered == 1)
        assert(_G.DDingToolKit_PartyTrackerFrame:IsShown())
        assert(_G.DDingToolKitMover_PartyTracker:IsShown())
        assert(_G.DDingToolKitMover_PartyTracker_Mana:IsShown())
        for _, f in ipairs(objects) do if f.gridSpacingBtn then remote = f end end
        assert(remote and remote.previewControl:GetValue() == false)
        remote.previewControl.buttons[2]:Fire("OnClick", "LeftButton")
        assert(remote.previewControl:GetValue() == true)
        assert(_G.DDingToolKitMover_PartyTracker:IsShown())
        assert(_G.DDingToolKitMover_PartyTracker_Mana:IsShown())
    ''')
