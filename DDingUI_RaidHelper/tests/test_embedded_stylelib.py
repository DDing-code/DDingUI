from pathlib import Path
import unittest


ADDON_ROOT = Path(__file__).resolve().parents[1]
TOC_PATH = ADDON_ROOT / "DDingUI_RaidHelper.toc"


class EmbeddedStyleLibTests(unittest.TestCase):
    def test_stylelib_is_embedded_and_not_a_hard_dependency(self):
        lines = TOC_PATH.read_text(encoding="utf-8-sig").splitlines()
        entries = [
            line.strip()
            for line in lines
            if line.strip() and not line.lstrip().startswith("#")
        ]

        self.assertNotIn("## Dependencies: DDingUI_StyleLib", lines)
        self.assertIn("## OptionalDeps: BigWigs", lines)

        embedded = [
            r"Libs\LibStub\LibStub.lua",
            r"Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua",
            r"Libs\LibDataBroker-1.1.lua",
            r"Libs\LibDBIcon-1.0\LibDBIcon-1.0.lua",
            r"Libs\DDingUI_StyleLib\Core.lua",
            r"Libs\DDingUI_StyleLib\Colors.lua",
            r"Libs\DDingUI_StyleLib\Gradient.lua",
            r"Libs\DDingUI_StyleLib\Motion.lua",
            r"Libs\DDingUI_StyleLib\TableUtils.lua",
            r"Libs\DDingUI_StyleLib\Delay.lua",
            r"Libs\DDingUI_StyleLib\ColorNames.lua",
            r"Libs\DDingUI_StyleLib\DesignTokens.lua",
            r"Libs\DDingUI_StyleLib\PixelUtil.lua",
            r"Libs\DDingUI_StyleLib\ObjectPool.lua",
            r"Libs\DDingUI_StyleLib\Animation.lua",
            r"Libs\DDingUI_StyleLib\WidgetRefresh.lua",
            r"Libs\DDingUI_StyleLib\GlowEffects.lua",
            r"Libs\DDingUI_StyleLib\CascadingMenu.lua",
            r"Libs\DDingUI_StyleLib\DragSorter.lua",
            r"Libs\DDingUI_StyleLib\DualRow.lua",
            r"Libs\DDingUI_StyleLib\Widgets.lua",
            r"Libs\DDingUI_StyleLib\EditMode.lua",
            r"Libs\DDingUI_StyleLib\ProceduralGlow.lua",
        ]

        for relative_path in embedded:
            self.assertIn(relative_path, entries)
            self.assertTrue(
                (ADDON_ROOT / relative_path.replace("\\", "/")).is_file(),
                relative_path,
            )

        self.assertLess(
            entries.index(r"Libs\DDingUI_StyleLib\Core.lua"),
            entries.index("Core.lua"),
        )
        # StyleLib 1.4 edit-mode parts build on Widgets (remote buttons, inputs).
        self.assertEqual(
            entries.index(r"Libs\DDingUI_StyleLib\EditMode.lua"),
            entries.index(r"Libs\DDingUI_StyleLib\Widgets.lua") + 1,
        )

    def test_embedded_stylelib_uses_a_private_libstub_major(self):
        style_root = ADDON_ROOT / "Libs" / "DDingUI_StyleLib"
        lua_sources = [path.read_text(encoding="utf-8") for path in style_root.glob("*.lua")]

        self.assertTrue(lua_sources)
        self.assertTrue(
            all('"DDingUI-StyleLib-1.0"' not in source for source in lua_sources)
        )
        self.assertTrue(
            all(
                "DDingUI-RaidHelper-StyleLib-1.0" in source
                for source in lua_sources
            )
        )
        core_source = (style_root / "Core.lua").read_text(encoding="utf-8")
        self.assertIn("DDingUI_RaidHelperStyleLib = lib", core_source)
        self.assertNotIn("DDingUI_StyleLib = lib", core_source)

    def test_options_use_a_standalone_stylelib_window(self):
        options_source = (ADDON_ROOT / "Options.lua").read_text(encoding="utf-8")
        modern_source = (ADDON_ROOT / "UI" / "OptionsWindow.lua").read_text(
            encoding="utf-8"
        )
        toc_entries = [
            line.strip()
            for line in TOC_PATH.read_text(encoding="utf-8-sig").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]

        self.assertIn("CreateSettingsPanel", options_source)
        self.assertIn("CreateTreeMenu", options_source)
        self.assertIn("PRIMARY_WIDTH", modern_source)
        self.assertIn("MODULE_WIDTH", modern_source)
        self.assertIn("CreateModernCooldownPage", modern_source)
        self.assertLess(
            toc_entries.index("Options.lua"),
            toc_entries.index(r"UI\OptionsWindow.lua"),
        )
        self.assertNotIn("Settings.RegisterCanvasLayoutCategory", options_source)
        self.assertNotIn("InterfaceOptions_AddCategory", options_source)
        self.assertNotIn("Settings.RegisterCanvasLayoutCategory", modern_source)
        self.assertNotIn("InterfaceOptions_AddCategory", modern_source)

    def test_embedded_sliders_have_a_large_click_target(self):
        widgets_source = (
            ADDON_ROOT / "Libs" / "DDingUI_StyleLib" / "Widgets.lua"
        ).read_text(encoding="utf-8")

        # Series slider spec (StyleLib 1.2): 28px hit area around a 6px track, 16px thumb.
        self.assertIn("trackHeight = 6, hitHeight = 28", widgets_source)
        self.assertIn("thumbSize = 16", widgets_source)
        self.assertIn(
            "local pad = (SPEC.hitHeight - SPEC.trackHeight) / 2",
            widgets_source,
        )
        self.assertIn(
            'slider:SetPoint("TOPLEFT", track, "TOPLEFT", 0, pad)',
            widgets_source,
        )
        self.assertIn(
            'slider:SetPoint("BOTTOMRIGHT", track, "BOTTOMRIGHT", 0, -pad)',
            widgets_source,
        )
        # The common slider uses a visible solid 16px thumb; legacy Media remains for other callers.
        self.assertIn("thumbWidth = 24, thumbHeight = 14", widgets_source)
        self.assertIn("thumb:SetColorTexture(u(C.text.normal))", widgets_source)
        self.assertNotIn('thumb:SetTexture(Lib.MediaPath .. "ddsl_thumb_rings")', widgets_source)
        self.assertTrue((ADDON_ROOT / "Libs" / "DDingUI_StyleLib" / "Media" / "ddsl_thumb_rings.tga").exists())


if __name__ == "__main__":
    unittest.main()
