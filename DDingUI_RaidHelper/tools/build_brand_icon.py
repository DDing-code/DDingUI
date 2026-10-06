#!/usr/bin/env python3
"""Build the exact DDingUI symbol as RaidHelper's transparent TGA icon."""

from pathlib import Path

from PIL import Image


ADDON_ROOT = Path(__file__).resolve().parents[1]
SOURCE = ADDON_ROOT.parent / "Branding" / "DDingUI_Symbol_Orange.png"
OUTPUT = ADDON_ROOT / "Media" / "RaidHelper_Icon.tga"
POINT_COLOR = (214, 92, 255)  # #D65CFF, shared with the RaidHelper accent preset.


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    if source.size != (512, 512):
        source = source.resize((512, 512), Image.Resampling.LANCZOS)

    alpha = source.getchannel("A")
    icon = Image.new("RGBA", source.size)
    icon.putdata(
        [POINT_COLOR + (value,) if value else (0, 0, 0, 0) for value in alpha.getdata()]
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    # WoW's texture loader and several minimap skins expect top-left TGA origin.
    # Transparent pixels must also have zero RGB or a skin may expose them as a disc.
    icon.save(OUTPUT, format="TGA", orientation=1)
    print(f"Wrote {OUTPUT} ({icon.size[0]}x{icon.size[1]}, RGBA TGA)")


if __name__ == "__main__":
    main()
