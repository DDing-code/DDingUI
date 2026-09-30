"""Check the shipped title factories and fixed series branding with Lua 5.1."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "DDingUI_FX/tests"))
from test_fx import runtime

PREFIX = "|cffffffffDDing|r|cffffa300UI|r "
BRANDED = {"CDM": "DDingUI_CDM", "MJToolkit": "DDingUI_Toolkit",
           "RaidHelper": "DDingUI_RaidHelper", "FX": "DDingUI_FX"}
LOGOS = {"CDM": "DDingUI_CDM/Media/logo.tga", "MJToolkit": "DDingUI_Toolkit/logo.tga",
         "RaidHelper": "DDingUI_RaidHelper/Media/RaidHelper_Icon.tga", "FX": "DDingUI_FX/Media/logo.tga"}


def check():
    # DDingUI_UF is frozen (development stopped 2026-08-26) and keeps its old embedded StyleLib.
    bundles = [ROOT / "DDingUI_StyleLib"] + sorted(
        b for b in ROOT.glob("*/Libs/DDingUI_StyleLib") if b.parts[-3] != "DDingUI_UF")
    for bundle in bundles:
        lua = runtime()
        # WoW colour escapes do not consume layout width.
        lua.globals().Measure = lambda text, size: len(re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)) * size * .65
        owner = bundle.relative_to(ROOT).parts[0]
        core = (bundle / "Core.lua").read_text(encoding="utf-8-sig")
        major = re.search(r'local MAJOR(?:, MINOR)? = "([^"]+)"', core)[1]
        for name in ("Core.lua", "Colors.lua", "Gradient.lua", "Widgets.lua"):
            lua.execute('local source,owner=...; assert(loadstring(source))(owner)',
                        (bundle / name).read_text(encoding="utf-8-sig"), owner)
        lib = lua.globals().LibStub.GetLibrary(lua.globals().LibStub, major)[0]
        slider = lib.CreateSlider(lua.globals().UIParent, "CDM", "Value", 0, 100, 1, 50)
        thumb = slider.slider.thumb
        assert thumb.GetWidth(thumb) == thumb.GetHeight(thumb) == 16, bundle
        assert thumb.color and not thumb.texture, bundle
        scale = lib.CreateTitleScaleControl(
            lua.globals().UIParent, "CDM", lua.table_from({"label": "GUI Scale"}))
        lua.execute('''
            local box = ...
            local label
            for _, obj in ipairs(objects) do
                if obj.parent == box and obj.kind == "FontString" and obj.text == "GUI Scale" then label = obj end
            end
            assert(label)
            local track = box.slider.points.TOPLEFT[1]
            local lx, _, lw = label:Rect()
            local tx = track:Rect()
            assert(tx - lx - lw >= 8)
        ''', scale)
        for key, name in (("CDM", "CDM"), ("MJToolkit", "Toolkit"), ("UnitFrames", "UnitFrames"),
                          ("Profile", "Profile"), ("RaidHelper", "RaidHelper"), ("FX", "FX")):
            text = lib.CreateAddonTitle(key, name)
            assert text.startswith(PREFIX), (bundle, text)
            assert lib.GetChatPrefix(key, name) == text + "|cff888888:|r "
            letters = re.findall(r"\|cff([0-9a-f]{6})(.*?)\|r", text[len(PREFIX):])
            assert "".join(char for _, char in letters) == name
            assert letters[0][0] != letters[-1][0]
            bar = lib.CreateTitleBar(lua.globals().UIParent, key, "DDingUI " + name, "1.0")
            assert bar.titleText.IsShown(bar.titleText)
            if key in BRANDED:
                assert bar.titleText.GetText(bar.titleText) == lib.CreateGradientText(key, name)
                assert bar.brandTexture.texture == "Interface\\AddOns\\" + BRANDED[key] + "\\Media\\logo_wordmark.tga"
                assert list(bar.brandTexture.texCoord.values()) == [184/512, 464/512, 20/128, 108/128]
                assert list(bar.brandTexture.vertexColor.values()) == [1, 1, 1, 1]
                # StyleLib 1.3: the symbol is two ring pieces (from Branding/DDingUI_Symbol_Orange.png)
                # shipped in the owning bundle's Media folder, tinted with the addon's logo colour.
                media = "Interface\\AddOns\\" + owner + ("\\Media\\" if owner == "DDingUI_StyleLib"
                                                         else "\\Libs\\DDingUI_StyleLib\\Media\\")
                assert bar.brandLogo.leftRing.texture == media + "ddsl_ring_left", (bundle, bar.brandLogo.leftRing.texture, media)
                assert bar.brandLogo.rightRing.texture == media + "ddsl_ring_right"
                for piece in ("ddsl_ring_left.tga", "ddsl_ring_right.tga", "ddsl_rings.tga"):
                    assert (bundle / "Media" / piece).exists(), (bundle, piece)
                expected = [1, 0.416, 0, 1] if key == "CDM" else list(lib.GetAccent(key)[0].values())
                for part in (bar.brandLogo.leftRing, bar.brandLogo.rightRing):
                    got = list(part.vertexColor.values())
                    assert all(abs(a - b) < 1e-6 for a, b in zip(got, expected)), (key, got, expected)
                lua.execute('''
                    local bar=...
                    assert(bar.brandTexture.points.LEFT[1]==bar.brandLogo)
                    assert(bar.titleText.points.LEFT[1]==bar.brandTexture)
                    local lx,ly,lw,lh=bar.brandLogo:Rect()
                    local x,y,w,h=bar.brandTexture:Rect()
                    local tx,ty,tw,th=bar.titleText:Rect()
                    local vx=bar.verText:Rect()
                    assert(lh==22 and x>=lx+lw+8 and w==70 and h==22 and tx>=x+w+8 and vx>=tx+tw+6)
                ''', bar)
            else:
                assert not bar.brandTexture and bar.titleText.GetText(bar.titleText) == text
            assert lua.eval("function(bar) return bar.verText.points.LEFT[1] == bar.titleText end")(bar)

    # Every addon ships the same white/orange asset and uses its own install path.
    from PIL import Image
    canonical = ROOT / "DDingUI_CDM/Media/logo_wordmark.tga"
    for folder in BRANDED.values():
        asset = ROOT / folder / "Media/logo_wordmark.tga"
        assert asset.read_bytes() == canonical.read_bytes(), folder
        with Image.open(asset) as im:
            assert im.mode == "RGBA" and im.size == (512, 128)
            assert im.getbbox() == (48, 20, 464, 108)
    # Reuse each addon's coloured symbol; FX applies its blue preset to grayscale at runtime.
    from collections import Counter
    for key, rgb in {"CDM": (255, 106, 0), "MJToolkit": (51, 191, 230), "RaidHelper": (214, 92, 255)}.items():
        with Image.open(ROOT / LOGOS[key]) as im:
            colors = Counter((r,g,b) for r,g,b,a in im.convert("RGBA").getdata() if a > 250)
            assert colors.most_common(1)[0][0] == rgb
    # Main windows retain the shared factory's title and brand layout.
    for path in ("DDingUI_CDM_Option/GUI.lua", "DDingUI_Toolkit/Config_UI.lua",
                 "DDingUI_Profile/Core/InstallerUI.lua", "DDingUI_FX/UI.lua"):
        source = (ROOT / path).read_text(encoding="utf-8-sig")
        assert "logo_wordmark" not in source and "titleText:Hide()" not in source, path
        lua.execute("assert(loadstring(...))", source)
    source = (ROOT / "DDingUI_PersonalBar/Core.lua").read_text(encoding="utf-8-sig")
    title = re.search(r'local ADDON_TITLE = "([^"\n]+)"', source)[1]
    assert title.startswith(PREFIX)
    assert len(set(re.findall(r"\|cff([0-9a-f]{6})", title[len(PREFIX):]))) > 2
    lua.execute("assert(loadstring(...))", source)
    for path in ("DDingUI_RaidHelper/UI/OptionsWindow.lua", "DDingUI_Toolkit/Core/Movers.lua"):
        lua.execute("assert(loadstring(...))", (ROOT / path).read_text(encoding="utf-8-sig"))
    raid = (ROOT / "DDingUI_RaidHelper/UI/OptionsWindow.lua").read_text(encoding="utf-8-sig")
    assert 'titleBar.titleText:SetPoint("LEFT", titleBar, "LEFT"' not in raid
    # Exercise the actual tooltip callbacks using the shipped gradient helper.
    lua.globals().DDingUI_StyleLib = lib
    lua.globals().DDingUI_RaidHelperStyleLib = lib
    lua.execute("ns = { GetStyleLib = function() return DDingUI_RaidHelperStyleLib end }")
    launchers = [
        ("DDingUI_CDM/Core/Main.lua", "CDM", "CDM"),
        ("DDingUI_Toolkit/Core/MinimapButton.lua", "MJToolkit", "Toolkit"),
        ("DDingUI_UF/Core/Init.lua", "UnitFrames", "UnitFrames"),
        ("DDingUI_FX/Minimap.lua", "FX", "FX"),
        ("DDingUI_RaidHelper/UI/MinimapButton.lua", "RaidHelper", "RaidHelper"),
        ("DDingUI_PersonalBar/Core.lua", None, None),
        ("DDingUI_DF_Plugin/Core.lua", None, None),
    ]
    for path, key, name in launchers:
        source = (ROOT / path).read_text(encoding="utf-8-sig")
        lua.execute("assert(loadstring(...))", source)
        match = re.search(r"OnTooltipShow\s*=\s*(function\([^)]*\).*?\n[ \t]*end),", source, re.S)
        assert match, path
        title = lib.CreateAddonTitle(key, name) if key else re.search(r'local ADDON_TITLE = "([^"\n]+)"', source)[1]
        if key == "FX":
            title = lua.globals().FX.Style.CreateAddonTitle(key, name)
        for locale in ("koKR", "enUS"):
            lua.execute("local locale = ...; GetLocale = function() return locale end", locale)
            lua.globals().ADDON_TITLE = title
            result = lua.execute("""
                local callback = assert(loadstring('return ' .. ...))()
                local tt = { lines = {} }
                function tt:SetText(text) self.title = text end
                function tt:AddLine(text, r, g, b)
                    assert(r == 0.7 and g == 0.7 and b == 0.7)
                    table.insert(self.lines, text)
                end
                callback(tt)
                assert(#tt.lines == 3)
                return tt
            """, match[1])
            assert result.title == title, path
            labels = ("Left-click", "Right-click", "Drag") if locale == "enUS" and key in ("CDM", "MJToolkit", "UnitFrames") else ("좌클릭", "우클릭", "드래그")
            for i, label in enumerate(labels, 1):
                assert result.lines[i].startswith("|cffffffff" + label + "|r  "), path

    # Chat entry points must use the same shared branding, preserving message arguments.
    for path, owner, prefix in (("DDingUI_CDM/Core/Main.lua", "DDingUI", lib.GetChatPrefix("CDM", "CDM")),
                                ("DDingUI_RaidHelper/Core.lua", "ns", lib.GetChatPrefix("RaidHelper", "RaidHelper"))):
        source = (ROOT / path).read_text(encoding="utf-8-sig")
        body = re.search(r"function " + owner + r":Print\(\.\.\.\).*?\nend", source, re.S)[0]
        lua.globals().CDM_PREFIX = prefix
        lua.execute("DDingUI = {}; print = function(...) printed = {...} end")
        lua.execute(body + "\n" + owner + ":Print('message', 42)")
        assert lua.globals().printed[1] == prefix
        assert lua.globals().printed[2] == "message" and lua.globals().printed[3] == 42
    print(f"PASS: {len(bundles)} title factories, per-addon logos, fixed typography, series gradients and geometry, chat prefixes, 7 minimap tooltips")


if __name__ == "__main__":
    check()
