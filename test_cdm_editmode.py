"""CDM 편집 모드가 시리즈 공용 규격(C5·C12)으로 동작하는지 검사한다.

실제 DDingUI_CDM/Core/Movers.lua를 StyleLib 사본(EditMode.lua 포함)과 함께 모의 런타임에 올린다.
  * Esc(리모컨 OnKeyDown)로 편집 모드가 끝난다,
  * 리모컨 격자 버튼이 간격을 바꾸면 보이는 격자와 스냅이 같은 간격·같은 원점(화면 중앙)을 쓴다,
  * HUD·리모컨 X/Y는 드래그 중과 놓은 뒤가 같은 앵커 상대 오프셋이다,
  * moverSettings.gridEnabled는 종료 시점의 실제 값으로 저장되고 editRemotePos 같은 다른 키를 지우지 않는다,
  * 리모컨을 옮긴 위치는 editRemotePos에 저장되고 다시 만들 때 복원된다,
  * 진입 때 열려 있던 설정창은 종료 때 다시 열린다, `/dcm edit`가 편집 모드 토글로 분기한다.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from test_series_editmode import load_bundle

MOVERS_STUBS = r'''
local M = getmetatable(UIParent).__index
function M:GetName() return self.name end
function M:GetRect() return self:Rect() end
function M:GetLeft() local x = self:Rect(); return x end
function M:GetBottom() local _, y = self:Rect(); return y end
function M:GetRight() local x, _, w = self:Rect(); return x + w end
function M:GetTop() local _, y, _, h = self:Rect(); return y + h end
function M:GetSize() return self:GetWidth(), self:GetHeight() end
function M:GetNumPoints() local n = 0; for _ in pairs(self.points) do n = n + 1 end; return n end
function M:SetParent(p) self.parent = p end
function M:Raise() end
function M:GetFrameStrata() return self.strata or "MEDIUM" end
function M:GetObjectType() return self.kind end
function M:SetIgnoreParentAlpha() end
function M:IsProtected() return false end
function M:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
function M:HasFocus() return false end
function M:GetObjectType() return self.kind end
for _, k in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetClampRectInsets", "StartMoving", "StopMovingOrSizing", "SetMotionScriptsWhileDisabled", "SetUserPlaced", "SetResizable", "SetPushedTextOffset", "SetHighlightTexture", "SetDisabledFontObject", "SetFontObject", "UnregisterEvent", "SetMaxLetters", "SetTextInsets", "SetCursorPosition", "HighlightText", "SetNumeric", "SetFocus" }) do
    if not M[k] then M[k] = function() end end
end
function M:Disable() self.enabled = false end
function M:Enable() self.enabled = true end
GetCurrentKeyBoardFocus = function() return nil end
IsShiftKeyDown = function() return false end
IsControlKeyDown = function() return false end
function hooksecurefunc(a, b, c)
    if type(a) == "table" then
        local old = a[b]; a[b] = function(...) local r = { old(...) }; c(...); return unpack(r) end
    else
        local old = _G[a]; _G[a] = function(...) local r = { old(...) }; b(...); return unpack(r) end
    end
end
function strsplit(sep, str) local out = {}; for part in (str .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end; return unpack(out) end
function wipe(t) for k in pairs(t) do t[k] = nil end; return t end
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 250 end
function GetPhysicalScreenSize() return 2560, 1440 end
afterTimers = {}
C_Timer.After = function(delay, fn) afterTimers[#afterTimers + 1] = fn end
function RunAfterTimers() local pending = afterTimers; afterTimers = {}; for _, fn in ipairs(pending) do fn() end end
function UIFrameFadeIn(f) f:SetAlpha(1); f:Show() end
function UIFrameFadeOut(f) f:SetAlpha(0) end
cursor = { 600, 500 }
function GetCursorPosition() return cursor[1], cursor[2] end
printed = {}
addon = {
    VERSION = "2.2.0",
    db = { profile = { castBar = { attachTo = "UIParent", anchorPoint = "CENTER", selfPoint = "CENTER", offsetX = 100, offsetY = -40 }, movers = {}, moverSettings = { gridEnabled = false, snapThreshold = 12, gridSize = 32 } }, global = {} },
}
function addon:Print(...) printed[#printed + 1] = table.concat({ ... }, " ") end
function addon:Scale(v) return v end
function addon:ResolveAnchorFrame(name) return (name and _G[name]) or UIParent end
configOpened = 0
function addon:OpenConfig() configOpened = configOpened + 1 end
-- 편집 대상: 시전 바 (UIParent CENTER 기준 100, -40)
castBar = CreateFrame("Frame", "DDingUICastBar", UIParent)
castBar:SetSize(200, 20)
castBar:SetPoint("CENTER", UIParent, "CENTER", 100, -40)
addon.castBar = castBar
'''


def movers_runtime():
    lua, lib = load_bundle(ROOT / "DDingUI_CDM/Libs/DDingUI_StyleLib")
    lua.globals().Measure = lambda text, size: len(re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", str(text))) * size * .65
    lua.execute(MOVERS_STUBS)
    ns = lua.table(Addon=lua.globals().addon, L=lua.table())
    lua.execute('local source, ns = ...; assert(loadstring(source, "@Movers.lua"))("DDingUI_CDM", ns)',
                (ROOT / "DDingUI_CDM/Core/Movers.lua").read_text(encoding="utf-8-sig"), ns)
    lua.execute("Movers = addon.Movers; Movers:LoadSettings(); Movers:CreateEditRemote()")
    return lua


def test_escape_exits_and_config_reopens():
    lua = movers_runtime()
    lua.execute(r'''
        -- 진입 때 설정창이 열려 있었다 → 닫히고, 종료 후 다시 열린다
        local cfg = CreateFrame("Frame", "DDingUI_ConfigFrame", UIParent)
        cfg:Show()
        Movers:ToggleConfigMode()
        assert(Movers.ConfigMode and not cfg:IsShown(), "entering edit mode must close the settings window")
        local remote = Movers.NudgeFrame
        assert(remote and remote:IsShown() and remote.titleBar and remote.gridSpacingBtn, "StyleLib edit remote not shown")
        assert(Movers.Grid and Movers.Grid:IsShown() and Movers.Settings.gridEnabled, "grid must be on at entry")
        assert(Movers.CreatedMovers["DDingUI_PlayerCastBar"].mover.surface, "mover surface must be StyleMover")
        remote:GetScript("OnKeyDown")(remote, "ESCAPE")
        assert(not Movers.ConfigMode, "Esc did not leave edit mode")
        RunAfterTimers()
        assert(configOpened == 1, "settings window was not reopened after exit: " .. configOpened)
        -- 설정창이 닫혀 있던 진입은 종료 후에도 열지 않는다
        cfg:Hide(); configOpened = 0
        Movers:ToggleConfigMode(); Movers:ToggleConfigMode(); RunAfterTimers()
        assert(configOpened == 0, "settings window opened although it was closed before")
    ''')


def test_grid_spacing_shared_by_visible_grid_and_snap():
    lua = movers_runtime()
    lua.execute(r'''
        Movers:ToggleConfigMode()
        local remote = Movers.NudgeFrame
        Movers.Settings.snapToFrames = false; Movers.Settings.snapToCenter = false
        -- 리모컨 격자 버튼: 32 → 64
        remote.gridSpacingBtn:GetScript("OnClick")(remote.gridSpacingBtn)
        assert(Movers.Settings.gridSize == 64 and Movers.Grid:GetSpacing() == 64 and Movers:GetGridSpacing() == 64,
            "visible grid and snap spacing differ: " .. tostring(Movers.Grid:GetSpacing()) .. " / " .. tostring(Movers.Settings.gridSize))
        -- 드래그: 화면 중앙(640,450)에서 오른쪽 67px → 격자 원점(중앙) 기준 64로 스냅
        local mover = Movers.CreatedMovers["DDingUI_PlayerCastBar"].mover
        local cx, cy = mover:GetCenter()
        cursor = { cx, cy }
        mover:Fire("OnDragStart")
        cursor = { 640 + 67, 450 + 5 }
        Movers._dragUpdateFrame:Fire("OnUpdate", 0.016)
        local x, y = mover:GetCenter()
        assert(math.abs(x - (640 + 64)) < 0.01 and math.abs(y - (450 + 0)) < 0.01,
            "snap origin/spacing is not the screen-centre grid: " .. x .. "," .. y)
        mover:Fire("OnDragStop")
        -- 16으로 바꾸면 스냅도 16 간격
        remote.gridSpacingBtn:GetScript("OnClick")(remote.gridSpacingBtn)
        assert(Movers.Settings.gridSize == 16 and Movers.Grid:GetSpacing() == 16)
        cx, cy = mover:GetCenter(); cursor = { cx, cy }
        mover:Fire("OnDragStart")
        cursor = { 640 + 50, 450 }
        Movers._dragUpdateFrame:Fire("OnUpdate", 0.016)
        x = mover:GetCenter()
        assert(math.abs(x - (640 + 48)) < 0.01, "16px grid snap failed: " .. x)
        mover:Fire("OnDragStop")
        Movers:ToggleConfigMode()
    ''')


def test_hud_offset_is_anchor_relative_during_and_after_drag():
    lua = movers_runtime()
    lua.execute(r'''
        Movers:ToggleConfigMode()
        Movers.Settings.snapEnabled = false
        local mover = Movers.CreatedMovers["DDingUI_PlayerCastBar"].mover
        Movers.SelectedMover = mover
        Movers.NudgeFrame:UpdateSelection()
        local function hud() return mover.hud.box.text:GetText() end
        assert(hud():find("^X 100  Y %-40  "), "HUD before drag: " .. hud())
        assert(Movers.NudgeFrame.xField.editBox:GetText() == "100" and Movers.NudgeFrame.yField.editBox:GetText() == "-40")
        local cx, cy = mover:GetCenter()
        cursor = { cx, cy }
        mover:Fire("OnDragStart")
        cursor = { cx + 30, cy + 10 }
        Movers._dragUpdateFrame:Fire("OnUpdate", 0.016)
        local during = hud()
        assert(during:find("^X 130  Y %-30  "), "HUD during drag must be anchor-relative, got: " .. during)
        assert(Movers.NudgeFrame.xField.editBox:GetText() == "130", "remote X during drag: " .. Movers.NudgeFrame.xField.editBox:GetText())
        mover:Fire("OnDragStop")
        local after = hud()
        assert(after == during, "HUD jumped after drop: " .. during .. " -> " .. after)
        local _, _, _, px, py = mover:GetPoint(1)
        assert(px == 130 and py == -30, "saved offset differs from HUD: " .. px .. "," .. py)
        -- X/Y 입력도 같은 기준
        Movers:ApplyMoverOffset(12, -7)
        assert(hud():find("^X 12  Y %-7  "), "ApplyMoverOffset: " .. hud())
        Movers:ToggleConfigMode()
    ''')


def test_grid_setting_saved_as_real_value_and_remote_position():
    lua = movers_runtime()
    lua.execute(r'''
        local settings = addon.db.profile.moverSettings
        settings.editRemotePos = { point = "TOPLEFT", x = 40, y = -90 }
        Movers:ToggleConfigMode()                 -- 격자 켜짐
        Movers:ToggleConfigMode()
        assert(settings.gridEnabled == true, "grid left on must be saved as true")
        assert(settings.editRemotePos and settings.editRemotePos.x == 40, "SaveSettings wiped editRemotePos")
        assert(settings.snapThreshold == 12, "stored snapThreshold must be kept as read")
        Movers:ToggleConfigMode()
        Movers:HideGrid()                         -- 리모컨 격자 체크 해제와 같은 경로
        assert(not Movers.Settings.gridEnabled)
        Movers:ToggleConfigMode()
        assert(settings.gridEnabled == false, "grid turned off must be saved as false")
        -- 리모컨을 옮기면 editRemotePos에 저장되고, 새로 만들 때 복원된다
        local remote = Movers.NudgeFrame
        remote:ClearAllPoints(); remote:SetPoint("TOP", UIParent, "TOP", 123, -77)
        remote.titleBar:GetScript("OnDragStop")()
        assert(settings.editRemotePos.point == "TOP" and settings.editRemotePos.x == 123 and settings.editRemotePos.y == -77,
            "remote position not saved")
        Movers.NudgeFrame = nil
        local rebuilt = Movers:CreateEditRemote()
        local p, _, _, x, y = rebuilt:GetPoint(1)
        assert(p == "TOP" and x == 123 and y == -77, "remote position not restored: " .. tostring(p) .. "," .. tostring(x))
    ''')


def test_remote_controls_drive_movers():
    lua = movers_runtime()
    lua.execute(r'''
        Movers:ToggleConfigMode()
        local remote = Movers.NudgeFrame
        local mover = Movers.CreatedMovers["DDingUI_PlayerCastBar"].mover
        -- 프레임 선택 드롭다운 항목에 무버가 있고 선택하면 선택된다
        remote.frameDropdown:SetValue("DDingUI_PlayerCastBar")
        Movers.SelectedMover = mover; remote:UpdateSelection()
        assert(remote.nameText:GetText() == "Player Cast Bar", remote.nameText:GetText())
        -- 방향키·Shift·Ctrl+Z (리모컨이 처리)
        remote:GetScript("OnKeyDown")(remote, "RIGHT")
        local _, _, _, x = mover:GetPoint(1); assert(x == 101, "arrow nudge: " .. x)
        IsShiftKeyDown = function() return true end
        remote:GetScript("OnKeyDown")(remote, "UP")
        local _, _, _, _, y = mover:GetPoint(1); assert(y == -30, "shift nudge: " .. y)
        IsShiftKeyDown = function() return false end
        IsControlKeyDown = function() return true end
        remote:GetScript("OnKeyDown")(remote, "Z")
        _, _, _, _, y = mover:GetPoint(1); assert(y == -40, "ctrl+z: " .. y)
        IsControlKeyDown = function() return false end
        -- 9점 격자: 좌클릭 = 앵커점, 우클릭 = 기준점
        remote._anchorDots.TOP:GetScript("OnClick")(remote._anchorDots.TOP, "RightButton")
        local sp = mover:GetPoint(1)
        assert(sp == "TOP" and remote._selfPointCurrent == "TOP", "self point via grid: " .. tostring(sp))
        -- 완료 버튼 = 종료
        remote.buttons["완료"]:GetScript("OnClick")(remote.buttons["완료"])
        assert(not Movers.ConfigMode)
    ''')


def test_dcm_edit_alias_and_lock_notice():
    main = (ROOT / "DDingUI_CDM/Core/Main.lua").read_text(encoding="utf-8")
    assert 'input:match("^%s*edit%s*$")' in main and "self.Movers:ToggleConfigMode()" in main
    movers = (ROOT / "DDingUI_CDM/Core/Movers.lua").read_text(encoding="utf-8")
    assert 'SLASH_DDINGUIMOVERS1 = "/dduimove"' in movers and 'SLASH_DDINGUIMOVERS2 = "/ddmove"' in movers
    assert 'SLASH_DDINGUIGRID1 = "/ddgrid"' in movers
    lock = (ROOT / "DDingUI_CDM/Core/EditModeLock.lua").read_text(encoding="utf-8")
    assert "/dcm edit" in lock and "편집모드(/dcm)" not in lock
    # 하드코딩 파랑/노랑 무버 색과 옛 독자 위젯은 없다
    assert "0.4, 0.6, 1" not in movers and "1, 0.8, 0, 1" not in movers
    for stale in ("PositionNudgeFrame", "ResetAllPositions", "CreateFlatSlider", "DDingUI_NudgeFrame", "GRID_SPACING"):
        assert stale not in movers, stale
    toc = (ROOT / "DDingUI_CDM/DDingUI_CDM.toc").read_text(encoding="utf-8")
    assert re.search(r"Widgets\.lua\s*\nLibs\\DDingUI_StyleLib\\EditMode\.lua\s*\nLibs\\DDingUI_StyleLib\\ProceduralGlow\.lua", toc)


if __name__ == "__main__":
    test_escape_exits_and_config_reopens()
    test_grid_spacing_shared_by_visible_grid_and_snap()
    test_hud_offset_is_anchor_relative_during_and_after_drag()
    test_grid_setting_saved_as_real_value_and_remote_position()
    test_remote_controls_drive_movers()
    test_dcm_edit_alias_and_lock_notice()
    print("CDM edit mode: Esc, shared grid/snap, anchor-relative HUD, saved settings, remote position, controls OK")
