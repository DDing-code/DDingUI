#!/usr/bin/env python3
"""Build DDingUI StyleLib 1.3 media (rounded 9-slice masks + logo ring pieces).

All textures are white (tinted in Lua with SetVertexColor) except the slider thumb,
which bakes its dark capsule + white rings. Output: DDingUI_StyleLib/Media/*.tga
(top-left origin, fully transparent pixels have zero RGB).

Rounded masks: ddsl_round{R}.tga (fill) and ddsl_round{R}_border.tga (1px outline).
Texture size = 2*M + 2 where M = slice margin; Lua uses SetTextureSliceMargins(M, M, M, M).
Corners are superellipse ("continuous", Apple-like) rather than circular arcs.
"""

import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
OUT = ROOT / "Media"
SOURCE_LOGO = REPO / "Branding" / "DDingUI_Symbol_Orange.png"

SS = 8                 # supersampling factor
EXPONENT = 4.5         # superellipse exponent (2 = circle, higher = squarer)
RADII = (2, 3, 4, 6, 8, 10, 14)


def margin_for(radius):
    # Continuous corners start earlier than a circular arc of the same visual radius.
    return max(2, int(math.ceil(radius * 1.3)))


def save(img, name):
    OUT.mkdir(parents=True, exist_ok=True)
    data = np.array(img.convert("RGBA"))
    data[data[:, :, 3] == 0] = 0
    Image.fromarray(data, "RGBA").save(OUT / name, format="TGA", orientation=1)


def rounded_alpha(size, margin, inset=0.0):
    """Coverage (0..1) of a superellipse-cornered square of `size` px, shrunk by `inset` px."""
    n = size * SS
    c = (np.arange(n) + 0.5) / SS                      # pixel-centre coordinates
    x, y = np.meshgrid(c, c)
    lo, hi = inset, size - inset
    m = max(0.01, margin - inset)
    dx = np.maximum(0, np.maximum(lo + m - x, x - (hi - m))) / m
    dy = np.maximum(0, np.maximum(lo + m - y, y - (hi - m))) / m
    inside = (dx ** EXPONENT + dy ** EXPONENT <= 1.0) & (x >= lo) & (x <= hi) & (y >= lo) & (y <= hi)
    return inside.reshape(size, SS, size, SS).mean(axis=(1, 3))


def white(alpha):
    a = (np.clip(alpha, 0, 1) * 255 + 0.5).astype(np.uint8)
    rgba = np.zeros(a.shape + (4,), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = a
    return Image.fromarray(rgba, "RGBA")


def build_rounded():
    for r in RADII:
        m = margin_for(r)
        size = 2 * m + 2
        fill = rounded_alpha(size, m)
        border = np.clip(fill - rounded_alpha(size, m, inset=1.0), 0, 1)
        save(white(fill), f"ddsl_round{r}.tga")
        save(white(border), f"ddsl_round{r}_border.tga")
        print(f"round{r}: {size}x{size}, slice margin {m}")


# Logo ring geometry measured from Branding/DDingUI_Symbol_Orange.png (512x512):
# both rings are ellipses rx~133 ry~148 (outer), stroke ~31, centres x=212 / x=302, y=255.
RING_CY = 255.5
RING_RX = 117.5   # mid-stroke radii
RING_RY = 132.5
LEFT_CX, RIGHT_CX = 212.5, 302.5
CROP = (70, 99, 442, 412)   # tight box around the symbol (+8px padding)
CROP_OUT = (256, 215)


def build_rings():
    src = np.array(Image.open(SOURCE_LOGO).convert("RGBA")).astype(np.float32)
    alpha = src[:, :, 3] / 255.0
    h, w = alpha.shape
    y, x = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5

    def ring_dist(cx):
        return np.abs(np.sqrt(((x - cx) / RING_RX) ** 2 + ((y - RING_CY) / RING_RY) ** 2) - 1.0)

    left_mask = ring_dist(LEFT_CX) <= ring_dist(RIGHT_CX)
    pieces = {
        "ddsl_rings.tga": alpha,
        "ddsl_ring_left.tga": alpha * left_mask,
        "ddsl_ring_right.tga": alpha * (~left_mask),
    }
    for name, a in pieces.items():
        img = white(a).crop(CROP).resize(CROP_OUT, Image.Resampling.LANCZOS)
        save(img, name)
    print("rings:", ", ".join(pieces), f"{CROP_OUT[0]}x{CROP_OUT[1]}")


def build_thumb():
    """24x14 slider thumb at 4x (96x56): dark capsule + 1px light rim + white rings."""
    w, h, k = 24, 14, 4
    W, H = w * k * SS // SS, h * k
    cap = rounded_alpha(max(W, H), H / 2)  # square canvas; crop to capsule below
    cap = np.array(Image.fromarray((cap * 255).astype(np.uint8)).resize((W, W)))[: H, :] / 255.0
    # Build the capsule directly for exact proportions.
    yy, xx = np.mgrid[0:H * SS, 0:W * SS].astype(np.float32) / SS + 0.5 / SS
    r = H / 2
    cx = np.clip(xx, r, W - r)
    d = np.sqrt((xx - cx) ** 2 + (yy - r) ** 2)
    cap = (d <= r).reshape(H, SS, W, SS).mean(axis=(1, 3))
    rim = np.clip(cap - (d <= r - 1.5 * k / 4).reshape(H, SS, W, SS).mean(axis=(1, 3)), 0, 1)

    rings = Image.open(SOURCE_LOGO).convert("RGBA").crop(CROP)
    ring_h = int(H * 0.62)
    ring_w = int(ring_h * (CROP[2] - CROP[0]) / (CROP[3] - CROP[1]))
    rings = np.array(rings.resize((ring_w, ring_h), Image.Resampling.LANCZOS))[:, :, 3] / 255.0
    ring_layer = np.zeros((H, W))
    ox, oy = (W - ring_w) // 2, (H - ring_h) // 2
    ring_layer[oy:oy + ring_h, ox:ox + ring_w] = rings

    rgba = np.zeros((H, W, 4), np.float32)
    base = np.array([28, 28, 30], np.float32)
    rgba[..., :3] = base
    rgba[..., :3] = rgba[..., :3] * (1 - rim[..., None] * 0.18) + 255 * rim[..., None] * 0.18
    rgba[..., :3] = rgba[..., :3] * (1 - ring_layer[..., None]) + 255 * ring_layer[..., None]
    rgba[..., 3] = cap * 255
    save(Image.fromarray(rgba.astype(np.uint8), "RGBA"), "ddsl_thumb_rings.tga")
    print(f"thumb: {W}x{H} (drawn at {w}x{h})")


if __name__ == "__main__":
    build_rounded()
    build_rings()
    build_thumb()
