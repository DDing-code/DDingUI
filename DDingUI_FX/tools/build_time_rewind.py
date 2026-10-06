"""Bake Time Rewind's painted components into a playable 60-frame TGA.

python DDingUI_FX/tools/build_time_rewind.py
Rigid pointer geometry and continuous particle paths; no image upscaling.
"""
from pathlib import Path
from hashlib import sha256
from math import sin, cos, pi, radians
import json

import numpy as np
from PIL import Image, ImageDraw
from build_holy_wings import place, smooth

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'artifacts/DDingUI_FX/time-rewind'
STAGING = ART / 'v2-build'
SOURCE = ART / 'sequence-v2/components.png'
CELL, PAD, FRAMES, FPS = 512, 32, 60, 20


def pose(sprite, origin, scale, angle=0, center=(256, 256), opacity=1):
    """One rigid transform around the painted pivot at a constant native scale."""
    assert 0 < scale <= 1, 'Never enlarge source art'
    c, s = cos(radians(angle)) / scale, sin(radians(angle)) / scale
    x, y = center
    frame = sprite.transform((CELL, CELL), Image.Transform.AFFINE,
                             (c, -s, origin[0] - c*x + s*y,
                              s, c, origin[1] - s*x - c*y), Image.Resampling.BICUBIC)
    if opacity < 1:
        frame.putalpha(frame.getchannel('A').point([round(a * max(0, opacity)) for a in range(256)]))
    return frame


def components():
    source = Image.open(SOURCE).convert('RGB')
    assert source.size == (1536, 1024)
    parts = []
    # Measured bounds: the first clock ornament crosses the nominal row boundary.
    for box in ((0, 0, 540, 558), (710, 35, 824, 482), (1218, 140, 1330, 481),
                (195, 675, 323, 846), (630, 598, 930, 985), (1211, 675, 1350, 848)):
        rgb = np.array(source.crop(box)).astype(float)
        alpha = rgb.max(axis=2)
        alpha[alpha <= 6] = 0
        color = np.uint8(np.rint(np.divide(rgb * 255, alpha[:, :, None],
                                         out=np.zeros_like(rgb), where=alpha[:, :, None] > 0)))
        parts.append(Image.fromarray(np.dstack((color, alpha.astype('uint8')))))
    return parts


def drawings():
    face, long_hand, short_hand, aqua, curl, gold = components()
    # Downsample each pointer once, so later angles rotate the same pixel shape.
    long_hand = pose(long_hand, (58, 397), 100/376)
    short_hand = pose(short_hand, (56, 290), 62/268)
    curl = curl.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    yy, xx = np.mgrid[:face.height, :face.width]
    sectors = np.floor(((np.arctan2(yy - 288, xx - 268) + pi / 12) % (2*pi)) / (pi / 6)).astype(int)
    pieces = []
    for k in range(12):
        rgba = np.array(face)
        rgba[:, :, 3] *= sectors == k
        pieces.append(Image.fromarray(rgba))
    yy, xx = np.mgrid[:CELL, :CELL]
    radius_grid = np.hypot(xx - 256, yy - 256)
    frames, lengths, positions = [], [], []
    for i in range(FRAMES):
        t = i / FPS
        frame = Image.new('RGBA', (CELL, CELL))
        # Assemble painted tick sectors, hold the face still, then recall inward.
        for k, piece in enumerate(pieces):
            born = smooth((t - .025 * (k % 4)) / .44)
            gone = smooth((t - 2.36 - .022 * (k % 4)) / .51)
            a = k * pi / 6
            offset = 35 * (1 - born) - 115 * gone
            frame.alpha_composite(pose(piece, (268, 288), .61,
                                       22 * (1 - born) + 28 * gone,
                                       (256 + offset*cos(a), 256 + offset*sin(a)), born * (1 - gone)))
        life = smooth(t / .24) * (1 - smooth((t - 2.42) / .65))
        for k in range(2):
            frame.alpha_composite(pose(curl, (56, 222), .78 - k * .12,
                                       95*t + 170*k, opacity=life * (.65 - k*.18)))
        hand_life = smooth((t - .16) / .30) * (1 - smooth((t - 2.39) / .32))
        # Both pointers keep the SAME source, pivot and scale for all frames.
        hand_frames = [long_hand.rotate((i-12)*10, Image.Resampling.BICUBIC, center=(256, 256)),
                       short_hand.rotate(-60 + (i-12)*1.3, Image.Resampling.BICUBIC, center=(256, 256))]
        for hand in reversed(hand_frames):
            shown = hand.copy()
            shown.putalpha(shown.getchannel('A').point([round(a * hand_life) for a in range(256)]))
            frame.alpha_composite(shown)
        current_positions = []
        for k in range(24):
            radius = (145 + (k % 4)*11 + 23*(1-smooth(t/.55))) * (1-smooth((t-2.40)/.66))
            theta = radians(k*137.508 - t*(85 + (k%3)*11))
            center = (256 + radius*cos(theta), 256 + radius*sin(theta))
            current_positions.append(center)
            place(frame, gold if k % 5 == 0 else aqua, center, 16 + (k % 3)*4,
                  40 - np.degrees(theta), life * (.65 + .15*(k%3)))
        if 12 <= i < 48:
            # Verify rendered pixels of each layer, not just the scale constants.
            lengths.append([float(radius_grid[np.array(h.getchannel('A')) > 150].max()) for h in hand_frames])
            positions.append(current_positions)
        frames.append(frame)
    lengths, positions = np.array(lengths), np.array(positions)
    assert np.ptp(lengths, axis=0).max() < 2, lengths
    travel = np.linalg.norm(np.diff(positions, axis=0), axis=2)
    assert travel.min() > 8 and travel.max() < 20, (travel.min(), travel.max())
    metrics = dict(hand_lengths_pixels=lengths.tolist(), hand_length_range=np.ptp(lengths, axis=0).tolist(),
                   particle_step_pixels=[float(travel.min()), float(travel.max())])
    return frames, metrics


def build():
    STAGING.mkdir(parents=True, exist_ok=True)
    frames, metrics = drawings()
    assert len(frames) == FRAMES and len({f.tobytes() for f in frames}) == FRAMES
    for i, frame in enumerate(frames):
        box = frame.getchannel('A').getbbox()
        if i == 0:
            assert box is None
        else:
            assert box and min(box[:2]) >= PAD and max(box[2:]) <= CELL - PAD, (i, box)
    sheet = Image.new('RGBA', (4096, 4096))
    for i, frame in enumerate(frames):
        sheet.paste(frame, (i % 8 * CELL, i // 8 * CELL))
    path = STAGING / 'TimeRewind.tga'
    sheet.save(path, compression=None)
    with path.open('rb') as handle:
        header = handle.read(18)
    assert header[2] == 2 and header[16] == 32 and header[17] & 15 == 8
    decoded_frames = []
    with Image.open(path) as decoded:
        assert decoded.mode == 'RGBA' and decoded.size == (4096, 4096)
        for i in range(64):
            x, y = i % 8 * CELL, i // 8 * CELL
            frame = decoded.crop((x, y, x + CELL, y + CELL))
            if i < FRAMES:
                assert frame.tobytes() == frames[i].tobytes()
                decoded_frames.append(frame)
            else:
                assert frame.getchannel('A').getbbox() is None
    light = [np.array(f)[:, :, 3].mean() / 255 for f in frames]
    assert light[-1] < .003
    assert max(abs(b-a) for a, b in zip(light[12:47], light[13:48])) < .015
    # Check that the outer light actually moves in the final composite TGA.
    yy, xx = np.mgrid[:CELL, :CELL]
    radius = np.hypot(xx-256, yy-256)
    angles = np.rint(np.degrees(np.arctan2(256-yy, xx-256))).astype(int) % 360
    profiles = []
    for frame in decoded_frames[12:48]:
        a = np.array(frame)
        rgb = a[:, :, :3] * (a[:, :, 3:4].astype(float) / 255)
        r, g, b = [rgb[:, :, j] for j in range(3)]
        mask = (b > r*1.10) & (g > r*1.10) & (radius > 146) & (radius < 192)
        profile = np.bincount(angles[mask], weights=b[mask], minlength=360)
        profiles.append(sum(np.roll(profile, d) for d in (-1, 0, 1)))
    shifts = [max(range(-12, 13), key=lambda d: np.dot(np.roll(a, d), b))
              for a, b in zip(profiles, profiles[1:])]
    assert min(shifts) >= 3 and max(shifts) <= 7, shifts
    metrics['observed_outer_motion_degrees_per_frame'] = shifts
    previews = [Image.alpha_composite(Image.new('RGBA', (CELL, CELL), (20, 22, 29, 255)), f).convert('RGB')
                for f in decoded_frames]
    webp = ART / 'TimeRewind-preview-v2.webp'
    previews[0].save(webp, save_all=True, append_images=previews[1:], duration=50,
                     lossless=True, quality=100, method=4, loop=0)
    contact = Image.new('RGB', (192*10, 210*6), (20, 22, 29))
    labels = ImageDraw.Draw(contact)
    for i, frame in enumerate(previews):
        x, y = i % 10 * 192, i // 10 * 210
        contact.paste(frame.resize((192, 192), Image.Resampling.LANCZOS), (x, y))
        labels.text((x+8, y+191), str(i+1), fill='white')
    contact.save(ART / 'delivered-frames-v2.png')
    palette = contact.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    gif_frames = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in previews]
    gif_frames[0].save(ART / 'TimeRewind-preview-v2.gif', save_all=True, append_images=gif_frames[1:],
                       duration=50, disposal=2, optimize=False, loop=0)
    previews[30].save(ART / 'TimeRewind-thumbnail-v2.png')
    with Image.open(webp) as preview:
        assert preview.n_frames == FRAMES
        duration = 0
        for i in range(FRAMES):
            preview.seek(i); preview.load(); duration += preview.info['duration']
        assert duration == 3000
    manifest = dict(frames=FRAMES, fps=FPS, duration_seconds=3, cell=CELL, padding=PAD,
                    columns=8, rows=8, pages=1, display_scale=1.5,
                    source_size=[1536, 1024], upscaling=False, interpolation=False,
                    composition='fixed face, two rigid hands, two moving curls, 24 orbiting motes; assembly/retraction',
                    alpha='straight RGBA from generated black emission atlas', alpha_mean=light,
                    motion_checks=metrics, sources={SOURCE.name: sha256(SOURCE.read_bytes()).hexdigest()},
                    tga_sha256=sha256(path.read_bytes()).hexdigest(),
                    status='staged; inspect before installing; actual WoW rendering unverified')
    (STAGING / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print('PASS: rigid hand lengths; moving particles; 60 unique frames; RGBA/gutters/exact decoding/3 seconds')


if __name__ == '__main__':
    build()
