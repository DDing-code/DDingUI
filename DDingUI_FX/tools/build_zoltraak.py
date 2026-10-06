"""Bake generated Zoltraak artwork into playable RGBA TGA pages.

python DDingUI_FX/tools/build_zoltraak.py
Stages assets for visual inspection before copying into Media; never upscales art.
"""
from pathlib import Path
from hashlib import sha256
from math import pi
import json

import numpy as np
from PIL import Image, ImageFilter
from build_holy_wings import place, smooth

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'artifacts/DDingUI_FX/zoltraak'
STAGING = ART / 'v5-build'
CELL, PAD, COLS, ROWS, FRAMES, FPS = 512, 32, 8, 8, 96, 24
ORIGIN = (256, 256)


def load_art():
    sources = [ART / 'Zoltraak-seal-v2.png']
    for path in sources:
        with Image.open(path) as image:
            assert image.mode == 'RGBA', path
            lo, hi = image.getchannel('A').getextrema()
            assert lo == 0 and hi >= 240, path
    return {'seal': Image.open(sources[0]).resize((512, 512), Image.Resampling.LANCZOS)}, sources


def seal_pose(sprite, t):
    yy, xx = np.mgrid[:512, :512]
    radius = np.hypot(xx - 256, yy - 256) / 256
    angle = (np.arctan2(yy - 256, xx - 256) + 2 * pi) % (2 * pi) / (2 * pi)
    # Keep the front-facing pivot fixed; inner geometry turns against the outer rune ring.
    outer = smooth((radius - .78) / .018)
    result = Image.new('RGBA', sprite.size)
    charge = smooth((t - .55) / 1.30)
    for weight, rotation, stagger, sweep_speed in ((outer, -t * 8, 0, .30), (1 - outer, t * 11, .12, -.23)):
        rgba = np.array(sprite.rotate(rotation, Image.Resampling.BICUBIC))
        phase = (angle * 3 + np.floor(radius * 4) * .21) % 1
        birth = phase * .60 + radius * .02 + stagger
        death = 3.20 + phase * .44 + radius * .02
        visible = smooth((t - birth) / .13) * (1 - smooth((t - death) / .30))
        # Light travels on the existing painted strokes, never through their empty centers.
        distance = (angle - t * sweep_speed + .5) % 1 - .5
        light = np.exp(-(distance / .055) ** 2) * smooth((t - .42) / .30)
        if stagger:
            for k in range(6):
                theta = -pi / 2 + k * pi / 3 - t * 11 * pi / 180
                cx, cy = 256 + 128 * np.cos(theta), 256 + 128 * np.sin(theta)
                ring = np.exp(-((np.hypot(xx - cx, yy - cy) - 57) / 10) ** 2)
                light += ring * np.exp(-((t - (.80 + k * .15)) / .18) ** 2)
        whiten = np.minimum(.75, charge * .18 + light * .55)
        rgb = rgba[:, :, :3].astype(float)
        rgba[:, :, :3] = np.uint8(np.rint(rgb + (255 - rgb) * whiten[:, :, None]))
        gain = 1 + charge * .45 + light * 1.35
        rgba[:, :, 3] = np.uint8(np.rint(np.minimum(255, rgba[:, :, 3] * gain) * visible * weight))
        result = Image.alpha_composite(result, Image.fromarray(rgba))
    # A narrow halo follows the lines; the crisp source remains the top layer.
    halo = Image.new('RGBA', sprite.size, (65, 170, 255, 0))
    halo.putalpha(result.getchannel('A').filter(ImageFilter.GaussianBlur(2.2)).point(lambda a: round(a * .65)))
    return Image.alpha_composite(halo, result)


def animate(parts):
    frames = []
    for index in range(FRAMES):
        frame = Image.new('RGBA', (CELL, CELL))
        if index not in (0, FRAMES - 1):
            place(frame, seal_pose(parts['seal'], index / FPS), ORIGIN, 424, 0, 1)
        frames.append(frame)
    return frames


def build():
    STAGING.mkdir(parents=True, exist_ok=True)
    parts, sources = load_art()
    frames = animate(parts)
    assert len(frames) == FRAMES
    assert len(sources) == 1 and sources[0].name == 'Zoltraak-seal-v2.png'
    assert max(f.getchannel('A').crop((244, 244, 268, 268)).getextrema()[1] for f in frames) < 16, 'Seal center must stay empty'
    for i, frame in enumerate(frames):
        box = frame.getchannel('A').getbbox()
        if i in (0, FRAMES - 1):
            assert box is None
        else:
            assert box is not None, ('unexpected blank', i)
            assert min(box[:2]) >= PAD and max(box[2:]) <= CELL - PAD, (i, box)
    assert len({f.tobytes() for f in frames[1:-1]}) == FRAMES - 2
    paths, decoded_frames = [], []
    for page in range(2):
        sheet = Image.new('RGBA', (COLS * CELL, ROWS * CELL))
        page_frames = frames[page * 64:(page + 1) * 64]
        for i, frame in enumerate(page_frames):
            sheet.paste(frame, ((i % COLS) * CELL, (i // COLS) * CELL))
        path = STAGING / ('Zoltraak.tga' if page == 0 else 'Zoltraak_2.tga')
        sheet.save(path, compression=None)
        paths.append(path)
        with Image.open(path) as decoded:
            assert decoded.mode == 'RGBA' and decoded.size == (4096, 4096)
            for i in range(64):
                x, y = (i % COLS) * CELL, (i // COLS) * CELL
                frame = decoded.crop((x, y, x + CELL, y + CELL))
                if i < len(page_frames):
                    assert frame.tobytes() == page_frames[i].tobytes()
                    decoded_frames.append(frame)
                else:
                    assert frame.getchannel('A').getbbox() is None
        header = path.read_bytes()[:18]
        assert header[2] == 2 and header[16] == 32 and header[17] & 15 == 8

    alpha = [float(np.array(f)[:, :, 3].mean() / 255) for f in decoded_frames]
    assert abs(alpha[64] - alpha[63]) < .012, 'Page boundary flash'
    previews = [Image.alpha_composite(Image.new('RGBA', (CELL, CELL), (20, 22, 29, 255)), f).convert('RGB')
                for f in decoded_frames]
    duration = [round((i + 1) * 1000 / FPS) - round(i * 1000 / FPS) for i in range(FRAMES)]
    webp = ART / 'Zoltraak-preview-v5.webp'
    previews[0].save(webp, save_all=True, append_images=previews[1:], lossless=True, quality=100,
                     method=4, duration=duration, loop=0)
    contact = Image.new('RGB', (256 * 6, 256 * 4))
    for i, frame in enumerate(previews[::4]):
        contact.paste(frame.resize((256, 256), Image.Resampling.LANCZOS), (i % 6 * 256, i // 6 * 256))
    contact.save(ART / 'delivered-frames-v5.png')
    palette = contact.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    gif_frames = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in previews]
    gif_duration = [round((i + 1) * 100 / FPS) * 10 - round(i * 100 / FPS) * 10 for i in range(FRAMES)]
    gif_frames[0].save(ART / 'Zoltraak-preview-v5.gif', save_all=True, append_images=gif_frames[1:],
                       duration=gif_duration, disposal=2, optimize=False, loop=0)
    previews[48].save(ART / 'Zoltraak-frame-v5.png')
    with Image.open(webp) as preview:
        assert preview.n_frames == FRAMES
        times = []
        for i in range(FRAMES):
            preview.seek(i); preview.load(); times.append(preview.info['duration'])
        assert sum(times) == 4000
    manifest = dict(frames=FRAMES, fps=FPS, duration_seconds=4, cell=CELL, padding=PAD,
                    columns=COLS, rows=ROWS, pages=2, composition='seal only; flowing rune light; no discharge or particles', display_scale=2,
                    page_boundary_alpha_delta=abs(alpha[64] - alpha[63]),
                    sources={p.name: sha256(p.read_bytes()).hexdigest() for p in sources},
                    sheets={p.name: sha256(p.read_bytes()).hexdigest() for p in paths},
                    status='staged; inspect before installing; WoW render untested')
    (STAGING / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print('PASS: 96 frames / 24 FPS / 4 sec; RGBA, gutters, page continuity, exact TGA decoding and preview duration')


if __name__ == '__main__':
    build()
