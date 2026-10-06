from pathlib import Path
import unittest

from PIL import Image


ADDON_ROOT = Path(__file__).resolve().parents[1]
ICON_PATH = ADDON_ROOT / "Media" / "RaidHelper_Icon.tga"
POINT_COLOR = (214, 92, 255)


class BrandIconTests(unittest.TestCase):
    def test_icon_is_a_wow_safe_transparent_tga(self):
        header = ICON_PATH.read_bytes()[:18]
        self.assertEqual(header[2], 2)
        self.assertEqual(header[16], 32)
        self.assertEqual(header[17] & 0x0F, 8)
        self.assertTrue(header[17] & 0x20)

        image = Image.open(ICON_PATH).convert("RGBA")
        self.assertEqual(image.size, (512, 512))

        transparent = 0
        colored = 0
        for red, green, blue, alpha in image.getdata():
            if alpha == 0:
                transparent += 1
                self.assertEqual((red, green, blue), (0, 0, 0))
            else:
                colored += 1
                self.assertEqual((red, green, blue), POINT_COLOR)

        self.assertGreater(transparent, 0)
        self.assertGreater(colored, 0)


if __name__ == "__main__":
    unittest.main()
