#!/usr/bin/env python3
"""Build the shared DDingUI orange symbol as APL's transparent TGA icon."""

from pathlib import Path

from PIL import Image


ADDON_ROOT = Path(__file__).resolve().parents[1]
SOURCE = ADDON_ROOT.parent / "Branding" / "DDingUI_Symbol_Orange.png"
OUTPUT = ADDON_ROOT / "Media" / "APL_Icon.tga"
# APL currently shares the StyleLib CDM orange accent, so the source orange is kept as-is.


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    if source.size != (512, 512):
        source = source.resize((512, 512), Image.Resampling.LANCZOS)

    icon = Image.new("RGBA", source.size)
    icon.putdata([pixel if pixel[3] else (0, 0, 0, 0) for pixel in source.getdata()])

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    # WoW's texture loader and several minimap skins expect top-left TGA origin.
    # Transparent pixels must also have zero RGB or a skin may expose them as a disc.
    icon.save(OUTPUT, format="TGA", orientation=1)
    print(f"Wrote {OUTPUT} ({icon.size[0]}x{icon.size[1]}, RGBA TGA)")


if __name__ == "__main__":
    main()
