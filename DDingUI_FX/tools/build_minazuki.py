"""Pack 40 native painted Minazuki cels; python DDingUI_FX/tools/build_minazuki.py."""
from hashlib import sha256
from pathlib import Path
import json

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).parent / 'sources/minazuki'
ART = ROOT / 'artifacts/DDingUI_FX/minazuki'
STAGING = ART / 'build'
CELL, FPS, COUNT = 512, 11, 40


def drawings():
    frames = []
    # Generated rows have unequal spacing; fixed measured pool anchors avoid camera drift.
    layouts = (
        ('gather', [0, 316, 628, 940, 1254], [157, 471, 783, 1097],
         [(0, 380, 307), (380, 690, 650), (690, 972, 950), (972, 1254, 1216)]),
        ('flow', [0, 320, 630, 938, 1254], [165, 475, 783, 1091],
         [(0, 333, 307), (333, 669, 615), (669, 981, 924), (981, 1254, 1225)]),
        ('drain', [0, 313, 628, 941, 1254], [156, 470, 784, 1097],
         [(420, 800, 683), (800, 1160, 1017)]),
    )
    for name, edges, anchors, rows in layouts:
        with Image.open(SOURCE / (name + '.png')) as image:
            assert image.mode == 'RGBA' and image.size == (1254, 1254)
            source = np.array(image)
        source[source[:, :, 3] <= 1] = 0
        image = Image.fromarray(source)
        for top, bottom, baseline in rows:
            for col in range(4):
                sprite = image.crop((edges[col], top, edges[col+1], bottom))
                frame = Image.new('RGBA', (CELL, CELL))
                frame.paste(sprite, (256 - anchors[col] + edges[col], 408 - baseline + top))
                frames.append(frame)
    assert len(frames) == COUNT and len({f.tobytes() for f in frames}) == COUNT
    return frames


def build():
    STAGING.mkdir(parents=True, exist_ok=True)
    frames = drawings()
    decoded, hashes, bounds, opacity = [], {}, [], []
    for i, frame in enumerate(frames):
        alpha = frame.getchannel('A')
        box = alpha.getbbox()
        assert box and min(box[:2]) >= 32 and max(box[2:]) <= CELL-32, (i, box)
        bounds.append(box)
        opacity.append(float(np.array(alpha).mean() / 255))
    assert opacity[0] < .005 and opacity[-1] < .005
    assert max(abs(a-b) for a, b in zip(opacity[1:], opacity[:-1])) < .04
    for page in range(3):
        sheet = Image.new('RGBA', (2048, 2048))
        for i, frame in enumerate(frames[page*16:(page+1)*16]):
            sheet.paste(frame, (i % 4 * CELL, i // 4 * CELL))
        path = STAGING / ('Minazuki' + (f'_{page+1}' if page else '') + '.tga')
        sheet.save(path, compression=None)
        header = path.read_bytes()[:18]
        assert header[2] == 2 and header[16] == 32 and header[17] & 15 == 8
        with Image.open(path) as restored:
            assert restored.mode == 'RGBA' and restored.size == (2048, 2048)
            for i in range(16):
                x, y = i % 4 * CELL, i // 4 * CELL
                frame = restored.crop((x, y, x+CELL, y+CELL))
                index = page*16+i
                if index < COUNT:
                    assert frame.tobytes() == frames[index].tobytes()
                    decoded.append(frame)
                else:
                    assert frame.getchannel('A').getbbox() is None
        hashes[path.name] = sha256(path.read_bytes()).hexdigest()
    previews = [Image.alpha_composite(Image.new('RGBA', (CELL, CELL), (20, 22, 29, 255)), f).convert('RGB')
                for f in decoded]
    durations = [round((i+1)*1000/FPS) - round(i*1000/FPS) for i in range(COUNT)]
    previews[0].save(ART / 'Minazuki-preview.webp', save_all=True, append_images=previews[1:],
                     duration=durations, lossless=True, loop=0)
    contact = Image.new('RGB', (8*192, 5*216), (20, 22, 29))
    labels = ImageDraw.Draw(contact)
    for i, frame in enumerate(previews):
        x, y = i % 8 * 192, i // 8 * 216
        contact.paste(frame.resize((192, 192), Image.Resampling.LANCZOS), (x, y))
        labels.text((x+8, y+194), str(i+1), fill='white')
        frame.save(STAGING / f'frame-{i:03}.png')
    contact.save(ART / 'delivered-frames.png')
    previews[20].save(ART / 'Minazuki-thumbnail.png')
    with Image.open(ART / 'Minazuki-preview.webp') as preview:
        assert preview.n_frames == COUNT
        for i, original in enumerate(previews):
            preview.seek(i)
            assert preview.convert('RGB').tobytes() == original.tobytes()
    manifest = dict(frames=COUNT, fps=FPS, seconds=COUNT/FPS, cell=CELL, columns=4, rows=4,
                    pages=3, upscaling=False, interpolation=False, alpha_mean=opacity,
                    visible_bounds=bounds, sheet_sha256=hashes,
                    sources={p.name: sha256(p.read_bytes()).hexdigest() for p in SOURCE.glob('*.png')},
                    status='TGA roundtrip and preview checked; actual WoW rendering unverified')
    (STAGING / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print('PASS: 40 unique native cels, RGBA, transparent margins/end, 3 TGA roundtrips, WebP pixel equality')


if __name__ == '__main__':
    build()
