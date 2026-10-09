#!/usr/bin/env python3
"""Build the horizontal edge-fade mask used by RaidHelper's combat bar.

The mask is stretched over the whole bar, so the fade always covers the same
share of the bar width whatever width the user picks. Both the alpha channel
and the grey level carry the ramp, so the result is the same whichever channel
the client samples for a MaskTexture.
"""

from pathlib import Path

from PIL import Image


ADDON_ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ADDON_ROOT / "Media" / "RaidHelper_FadeMask.tga"
WIDTH, HEIGHT = 256, 32
FADE_SHARE = 0.12  # Must match FADE_SHARE in UI/Timeline.lua.


def ramp(x: float) -> float:
    """Opacity at a horizontal position 0..1: smoothstep in, flat, smoothstep out."""
    edge = min(x, 1.0 - x) / FADE_SHARE
    edge = max(0.0, min(1.0, edge))
    return edge * edge * (3.0 - 2.0 * edge)


def main() -> None:
    row = []
    for column in range(WIDTH):
        value = round(255 * ramp((column + 0.5) / WIDTH))
        row.append((value, value, value, value))

    image = Image.new("RGBA", (WIDTH, HEIGHT))
    image.putdata(row * HEIGHT)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    # Top-left origin like the other RaidHelper TGAs.
    image.save(OUTPUT, format="TGA", orientation=1)
    print(f"Wrote {OUTPUT} ({WIDTH}x{HEIGHT}, RGBA TGA, fade {FADE_SHARE:.0%} each side)")


if __name__ == "__main__":
    main()
