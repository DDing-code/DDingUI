"""Run the shipped settings-window animations: python test_series_motion.py."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "DDingUI_FX/tests"))
from test_fx import runtime


def check():
    bundles = [ROOT / "DDingUI_StyleLib"] + sorted(ROOT.glob("*/Libs/DDingUI_StyleLib"))
    for bundle in bundles:
        lua = runtime()
        owner = bundle.relative_to(ROOT).parts[0]
        core = (bundle / "Core.lua").read_text(encoding="utf-8-sig")
        major = re.search(r'local MAJOR(?:, MINOR)? = "([^"]+)"', core)[1]
        for name in ("Core.lua", "Motion.lua"):
            lua.execute('local source,owner=...; assert(loadstring(source))(owner)',
                        (bundle / name).read_text(encoding="utf-8-sig"), owner)
        lua.globals().M = lua.globals().LibStub.GetLibrary(lua.globals().LibStub, major)[0].Motion
        lua.execute('''
            local f = CreateFrame('Frame', nil, UIParent)
            f:SetScale(.8); f:Hide()
            local hidden = 0
            f:SetScript('OnHide', function() hidden = hidden + 1 end)
            M.BindPanel(f); M.BindPanel(f) -- repeated setup must be harmless
            f:Show()
            assert(f:IsShown() and f:GetAlpha() == 0)
            assert(math.abs(f:GetScale() - .8 * .965) < .00001)
            Advance(.09)
            assert(f:GetScale() > .8 * .965 and f:GetScale() < .8)
            Advance(.1)
            assert(f:GetScale() == .8 and f:GetAlpha() == 1)
            f:Hide() -- same method called by Escape
            assert(f:IsShown() and f._ddslPanelClosing and hidden == 0)
            Advance(.07)
            assert(f:GetScale() < .8 and f:GetAlpha() < 1)
            local scale, alpha = f:GetScale(), f:GetAlpha()
            f:Show() -- reverse an unfinished close without jumping
            assert(f:GetScale() == scale and f:GetAlpha() == alpha)
            Advance(.2)
            assert(f:IsShown() and f:GetScale() == .8 and hidden == 0)
            f:Hide(); f:Hide(); Advance(.15)
            assert(not f:IsShown() and hidden == 1)
            assert(f:GetAlpha() == 1 and f:GetScale() == .8)
            f:SetScale(.65); f:SetShown(true); Advance(.2)
            assert(f:GetScale() == .65)
            f:SetShown(false); Advance(.15)
            assert(not f:IsShown() and f:GetScale() == .65 and hidden == 2)
            f:Show(); Advance(.02); f:HideImmediately(); Advance(.3)
            assert(not f:IsShown() and f:GetScale() == .65 and f:GetAlpha() == 1)
            f:Show(); Advance(.2); combat = true; f:Hide()
            assert(not f:IsShown() and not f._ddslPanelClosing)
            combat = false
        ''')
    lua = runtime()
    lua.execute('''
        FX:ToggleUI(); Advance(.2)
        FX:ToggleUI(); Advance(.05)
        assert(FX.window._ddslPanelClosing)
        FX:ToggleUI(); Advance(.2)
        assert(FX.window:IsShown() and not FX.window._ddslPanelClosing)
        FX.window.titleBar.closeBtn:Fire('OnClick', 'LeftButton')
        assert(FX.window._ddslPanelClosing)
        Advance(.15); assert(not FX.window:IsShown())
        ns = { StyleLib = FX.Style, Widgets = {
            CreateFrame = function(_, name, parent, width, height)
                local f = CreateFrame('Frame', name, parent)
                f:SetSize(width, height); return f
            end,
        } }
    ''')
    for name in ("OptionsPanelShell", "OptionsPanelVisibility"):
        lua.execute('assert(loadstring(...))("DDingUI_UF", ns)',
                    (ROOT / f"DDingUI_UF/Modules/{name}.lua").read_text(encoding="utf-8-sig"))
    lua.execute('''
        local f = ns.OptionsPanelShell:CreateMainFrame()
        local opts = { getPanel = function() return f end }
        assert(not f:IsShown())
        ns.OptionsPanelVisibility:Toggle(opts); Advance(.2)
        ns.OptionsPanelVisibility:Toggle(opts); Advance(.05)
        assert(f._ddslPanelClosing)
        ns.OptionsPanelVisibility:Toggle(opts); Advance(.2)
        assert(f:IsShown() and not f._ddslPanelClosing)
        ns.OptionsPanelVisibility:Hide(opts); Advance(.15)
        assert(not f:IsShown())
    ''')
    print(f"PASS: {len(bundles)} motion bundles, scale/fade, Escape, reopen, custom scale, immediate cleanup, FX/UF entry points")


if __name__ == "__main__":
    check()
