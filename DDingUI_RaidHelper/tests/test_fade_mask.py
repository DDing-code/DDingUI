from pathlib import Path
import re
import unittest

from PIL import Image


ADDON_ROOT = Path(__file__).resolve().parents[1]
MASK_PATH = ADDON_ROOT / "Media" / "RaidHelper_FadeMask.tga"
TIMELINE = ADDON_ROOT / "UI" / "Timeline.lua"


class FadeMaskTests(unittest.TestCase):
    def test_mask_is_a_wow_safe_tga(self):
        header = MASK_PATH.read_bytes()[:18]
        self.assertEqual(header[2], 2)  # uncompressed true colour
        self.assertEqual(header[16], 32)  # RGBA
        self.assertEqual(header[17] & 0x0F, 8)
        self.assertTrue(header[17] & 0x20)  # top-left origin

        image = Image.open(MASK_PATH).convert("RGBA")
        self.assertEqual(image.size, (256, 32))

    def test_mask_fades_both_edges_and_is_opaque_in_the_middle(self):
        image = Image.open(MASK_PATH).convert("RGBA")
        width, _ = image.size
        alphas = [image.getpixel((x, 0))[3] for x in range(width)]
        fade = round(width * 0.12)

        self.assertLess(alphas[0], 8)
        self.assertLess(alphas[-1], 8)
        self.assertTrue(all(value == 255 for value in alphas[fade:width - fade]))
        # Monotonic ramps, mirrored.
        self.assertEqual(alphas[:fade], sorted(alphas[:fade]))
        self.assertEqual(alphas[width - fade:], sorted(alphas[width - fade:], reverse=True))
        self.assertEqual(alphas, alphas[::-1])
        # Grey level carries the same ramp and every row is identical.
        for x in range(width):
            red, green, blue, alpha = image.getpixel((x, 0))
            self.assertEqual((red, green, blue), (alpha, alpha, alpha))
            self.assertEqual(image.getpixel((x, 31)), image.getpixel((x, 0)))

    def test_timeline_fade_share_matches_the_mask(self):
        source = TIMELINE.read_text(encoding="utf-8")
        match = re.search(r"local FADE_SHARE = ([0-9.]+)", source)
        self.assertIsNotNone(match)
        self.assertAlmostEqual(float(match.group(1)), 0.12)
        self.assertIn("RaidHelper_FadeMask.tga", source)


if __name__ == "__main__":
    unittest.main()
