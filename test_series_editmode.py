"""StyleLib 1.4 공용 편집 모드 부품(EditMode.lua)이 모든 사본에서 같은 규격으로 동작하는지 검사."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "DDingUI_FX/tests"))
from test_fx import runtime

FILES = ("Core.lua", "Colors.lua", "Gradient.lua", "Motion.lua", "Widgets.lua", "EditMode.lua")


def load_bundle(bundle):
    lua = runtime()
    lua.globals().Measure = lambda text, size: len(re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)) * size * .65
    # 모의 런타임에 없는 API 보강 (키보드·포커스·포맷 텍스트·GetPoint)
    lua.execute('''
        local M = getmetatable(UIParent).__index
        function M:GetPoint(i)
            local p, a = next(self.points)
            if not p then return nil end
            return p, a[1], a[2], a[3], a[4]
        end
        function M:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
        function M:HasFocus() return false end
        for _, k in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetClampRectInsets", "SetFrameLevel", "StartMoving", "StopMovingOrSizing" }) do
            if not M[k] then M[k] = function() end end
        end
        GetCurrentKeyBoardFocus = function() return nil end
        IsShiftKeyDown = function() return false end
        IsControlKeyDown = function() return false end
    ''')
    owner = bundle.relative_to(ROOT).parts[0]
    core = (bundle / "Core.lua").read_text(encoding="utf-8-sig")
    major = re.search(r'local MAJOR(?:, MINOR)? = "([^"]+)"', core)[1]
    for name in FILES:
        lua.execute('local source,owner=...; assert(loadstring(source))(owner)',
                    (bundle / name).read_text(encoding="utf-8-sig"), owner)
    return lua, lua.globals().LibStub.GetLibrary(lua.globals().LibStub, major)[0]


def check():
    bundles = [ROOT / "DDingUI_StyleLib"] + sorted(
        b for b in ROOT.glob("*/Libs/DDingUI_StyleLib") if b.parts[-3] != "DDingUI_UF")
    for bundle in bundles:
        lua, lib = load_bundle(bundle)
        assert lib.version >= 7, (bundle, lib.version)
        spec = lib.EditModeSpec
        assert spec.gridSpacing == 32 and spec.snapThreshold == 8 and spec.nudge == 1 and spec.nudgeShift == 10, bundle
        # 스냅 계산
        assert lua.eval("function(lib) return lib.SnapToGrid(37, 32, 8) end")(lib) == (32, True)
        assert lua.eval("function(lib) return lib.SnapToGrid(45, 32, 8) end")(lib) == (45, False)
        assert lua.eval("function(lib) return lib.SnapToCenter(5, 8) end")(lib) == (0, True)
        dx, dy = lua.eval("function(lib) return lib.SnapToRects({100,100,50,20}, {{154,0,10,10}}, 8) end")(lib)
        assert (dx, dy) == (4, 0), (bundle, dx, dy)
        # 부품 생성과 기본 동작
        lua.execute('''
            local lib, owner = ...
            local events = {}
            local remote = lib.CreateEditRemote("CDM", {
                title = "편집 모드", version = "1.0",
                frames = function() return { {text="A", value="a"}, {text="B", value="b"} } end,
                onSelectFrame = function(v) events.selected = v end,
                onNudge = function(dx, dy) events.nudge = {dx, dy} end,
                onApplyXY = function(x, y) events.xy = {x, y} end,
                onReset = function() events.reset = true end,
                onUndo = function() events.undo = true end,
                onRedo = function() events.redo = true end,
                onDone = function() events.done = true end,
                grid = { enabled = true, spacing = 32, onToggle = function(v) events.grid = v end,
                         onSpacing = function(n) events.spacing = n end },
                snap = { enabled = true, onChange = function(k, v) events.snap = k end },
                loadPosition = function() return "TOP", 5, -60 end,
                savePosition = function(p, x, y) events.saved = {p, x, y} end,
            })
            assert(remote.titleBar and remote.frameDropdown and remote.xField and remote.yField)
            assert(remote:GetWidth() == lib.EditModeSpec.remoteWidth)
            assert(remote:GetHeight() > 300, remote:GetHeight())
            assert(remote.buttons["완료"] and remote.buttons["초기화"] and remote.buttons["실행 취소"])
            -- 실제 앵커에서 버튼 영역을 계산: 좌우 여백, 중앙 정렬, 간격, 클릭 연결.
            local function checkFooter(frame, labels)
                local left, _, width = frame:Rect()
                local first, last, previousRight, top
                for _, label in ipairs(labels) do
                    local button = assert(frame.buttons[label])
                    local x, y, w, h = button:Rect()
                    assert(w > 0 and w == math.floor(w) and h == 26)
                    assert(x >= left + 14 and x + w <= left + width - 14,
                           label .. " outside footer: " .. (x - left) .. " / " .. width)
                    if previousRight then assert(math.abs(x - previousRight - 6) < .001) end
                    if top then assert(math.abs(y + h - top) < .001) end
                    first = first or x
                    last, previousRight, top = x + w, x + w, y + h
                end
                assert(math.abs((first - left) - (left + width - last)) < .001,
                       "footer must be centered")
            end
            checkFooter(remote, {"초기화", "실행 취소", "다시 실행", "완료"})
            for _, width in ipairs({280, 300, 320, 360}) do
                for mask = 0, 7 do
                    local clicked, labels = {}, {}
                    local options = {width = width, onDone = function() clicked["완료"] = true end}
                    local callbacks = {{"초기화", "onReset"}, {"실행 취소", "onUndo"}, {"다시 실행", "onRedo"}}
                    for i, def in ipairs(callbacks) do
                        if math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then
                            local label = def[1]
                            options[def[2]] = function() clicked[label] = true end
                            labels[#labels + 1] = label
                        end
                    end
                    labels[#labels + 1] = "완료"
                    local footerRemote = lib.CreateEditRemote("CDM", options)
                    checkFooter(footerRemote, labels)
                    for _, label in ipairs(labels) do
                        footerRemote.buttons[label]:GetScript("OnClick")(footerRemote.buttons[label])
                        assert(clicked[label], label .. " callback disconnected")
                    end
                end
            end
            local p, _, _, x, y = remote:GetPoint(1)
            assert(p == "TOP" and x == 5 and y == -60)
            remote:SetSelection({ name = "주 자원 바", anchor = "UIParent · CENTER", x = 12.4, y = -7.6, w = 200, h = 6 })
            assert(remote.nameText:GetText() == "주 자원 바")
            assert(remote.xField.editBox:GetText() == "12" and remote.yField.editBox:GetText() == "-8")
            remote:SetSelection(nil)
            assert(remote.nameText:GetText() == "선택된 프레임 없음")
            -- 격자 간격 순환 16→32→64→16
            remote.gridSpacingBtn:GetScript("OnClick")(remote.gridSpacingBtn)
            assert(events.spacing == 64, tostring(events.spacing))
            remote:SetGridState(true, 32)
            -- 넛지: Shift ×10
            IsShiftKeyDown = function() return false end
            remote:GetScript("OnKeyDown")(remote, "UP")
            assert(events.nudge[1] == 0 and events.nudge[2] == 1)
            IsShiftKeyDown = function() return true end
            remote:GetScript("OnKeyDown")(remote, "LEFT")
            assert(events.nudge[1] == -10 and events.nudge[2] == 0)
            -- Esc와 Ctrl+Z
            remote:GetScript("OnKeyDown")(remote, "ESCAPE")
            assert(events.done == true)
            IsControlKeyDown = function() return true end
            remote:GetScript("OnKeyDown")(remote, "Z")
            assert(events.undo == true)
            remote:SetUndoState(false, true)
            -- 제목줄 X는 onDone으로, HideAnimated는 실제 닫기
            events.done = nil
            remote.titleBar.closeBtn:GetScript("OnClick")(remote.titleBar.closeBtn)
            assert(events.done == true)
            events.done = nil
            remote:Show(); remote:HideAnimated()
            assert(events.done == nil)
            -- 무버 표면과 HUD
            local overlay = CreateFrame("Frame", nil, UIParent)
            overlay:SetSize(120, 40)
            local mover = lib.StyleMover(overlay, "CDM", { label = "시전 바" })
            assert(mover.label:GetText() == "시전 바")
            mover:SetSelected(true)
            assert(mover.brackets[1]:IsShown())
            mover:SetSelected(false)
            assert(not mover.brackets[1]:IsShown())
            mover:SetDisabled(true, "비활성화")
            assert(mover.badge:IsShown())
            assert(lib.StyleMover(overlay, "CDM") == mover) -- 두 번 입히지 않음
            local hud = lib.CreateMoverHUD(overlay, "CDM")
            hud:Update(10.6, -3.2, 120, 40)
            local hudText = hud.box.text:GetText()
            assert(hudText:find("^X 11  Y %-3  ") and hudText:find("120") and hudText:find("40$"), hudText)
            assert(hudText:byte(13) == 194 and hudText:byte(14) == 183, "middle dot expected") -- "·"
            assert(hudText:find("×", 1, true), "multiplication sign expected")
            -- 격자와 안내선
            local grid = lib.CreateEditGrid("CDM")
            grid:ShowAnimated()
            assert(grid:GetSpacing() == 32 and #grid.lines > 4)
            grid:SetSpacing(64)
            -- 격자 숨김은 끝나면 실제로 Hide
            grid:HideAnimated()
            for _, obj in ipairs(objects) do if obj.tweens then for _, tw in pairs(obj.tweens) do if tw.finish then tw.finish() end end end end
            -- 제목줄 편집 모드 버튼: isActive에 따라 "편집 모드"/"편집 중", GUI 크기 컨트롤은 그 왼쪽
            local active = false
            local bar2 = lib.CreateTitleBar(CreateFrame("Frame", nil, UIParent), "CDM", "DDingUI CDM", "1.0", {
                editMode = { onClick = function() active = not active end, isActive = function() return active end },
                scale = { get = function() return 1 end, set = function() end },
            })
            assert(bar2.editButton and bar2.editButton.label:GetText() == "편집 모드")
            bar2.editButton:GetScript("OnClick")(bar2.editButton); bar2.editButton:Refresh()
            assert(bar2.editButton.label:GetText() == "편집 중")
            assert(bar2.scaleControl and bar2.scaleControl.points.RIGHT[1] == bar2.editButton)
            local guides = lib.CreateEditGuides("CDM")
            guides:ShowAt(100, 200)
            assert(guides:IsShown())
        ''', lib, bundle.relative_to(ROOT).parts[0])
    print(f"PASS: {len(bundles)} StyleLib bundles: edit remote, mover surface, HUD, grid, guides, snap math")


if __name__ == "__main__":
    check()
