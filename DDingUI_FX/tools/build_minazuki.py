"""Pack Minazuki v2 with anticipation, fast impact and recoil; python DDingUI_FX/tools/build_minazuki.py."""
from hashlib import sha256
from pathlib import Path
import json

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).parent / 'sources/minazuki'
ART = ROOT / 'artifacts/DDingUI_FX/minazuki'
STAGING = ART / 'v2-build'
CELL, FPS, COUNT = 512, 24, 88
PAGES = (COUNT + 15) // 16


def drawings():
    cels = []
    # Measured cell boundaries preserve off-grid droplets; pool anchors stay fixed.
    layouts = (
        ('gather', [(0, 380, [0, 316, 628], [157, 471], [287, 298])]),
        ('v2/gather', [
            (0, 460, [0, 418, 836, 1254], [224, 634, 1047], [408, 413, 417]),
            (460, 889, [0, 418, 836, 1254], [211, 627, 1045], [794, 794, 792]),
            (889, 1254, [0, 418, 836, 1254], [210, 629, 1043], [1182, 1185, 1184])]),
        ('v2/impact', [
            (0, 414, [0, 418, 836, 1254], [211, 627, 1045], [384, 389, 390]),
            (414, 875, [0, 433, 836, 1254], [211, 630, 1045], [806, 805, 804]),
            (875, 1254, [0, 434, 836, 1254], [212, 630, 1045], [1179, 1181, 1186])]),
        ('v2/flow', [
            (0, 430, [0, 418, 836, 1254], [211, 627, 1045], [385, 384, 383]),
            (430, 882, [0, 432, 836, 1254], [212, 630, 1045], [803, 807, 802]),
            (882, 1254, [0, 418, 836, 1254], [211, 627, 1045], [1195, 1193, 1196])]),
        ('v2/drain', [
            (485, 850, [0, 418, 836, 1254], [211, 627, 1045], [813, 813, 813]),
            (850, 1220, [0, 418, 836, 1254], [211, 627, 1045], [1171, 1171, 1171])]),
    )
    for name, rows in layouts:
        with Image.open(SOURCE / (name + '.png')) as image:
            assert image.mode == 'RGBA' and image.size == (1254, 1254)
            source = np.array(image)
        source[source[:, :, 3] <= 1] = 0
        image = Image.fromarray(source)
        for top, bottom, edges, anchors, baselines in rows:
            for col, (anchor, baseline) in enumerate(zip(anchors, baselines)):
                sprite = image.crop((edges[col], top, edges[col+1], bottom))
                frame = Image.new('RGBA', (CELL, CELL))
                frame.paste(sprite, (256 - anchor + edges[col], 420 - baseline + top))
                cels.append(frame)
    # Hold drawn cels at 24 Hz; accelerate at the existing voice's 1.77-second cue.
    exposures = [2, 2] + [4]*7 + [5, 5] + [1, 1, 1, 1, 2, 2, 2, 1, 1] + [2, 2, 3]*3 + [2]*5 + [3]
    assert len(cels) == len(exposures) == 35 and sum(exposures) == COUNT
    assert sum(exposures[:11]) / FPS == 1.75
    assert len({cel.tobytes() for cel in cels}) == 35
    return [cel for cel, duration in zip(cels, exposures) for _ in range(duration)]


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
    jumps = [abs(a-b) for a, b in zip(opacity[1:], opacity[:-1])]
    assert .06 < max(jumps[42:46]) < .10
    assert max(jumps[:41] + jumps[54:]) < .055
    body = [f.getchannel('A').point(lambda a: 255 if a > 100 else 0).getbbox() for f in frames]
    assert body[42][1] - body[45][1] > 170 and all(body[i][3] == 420 for i in range(42, 54))
    for page in range(PAGES):
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
    previews[0].save(ART / 'Minazuki-preview-v2.webp', save_all=True, append_images=previews[1:],
                     duration=durations, lossless=True, loop=0)
    contact = Image.new('RGB', (8*192, 11*216), (20, 22, 29))
    labels = ImageDraw.Draw(contact)
    for i, frame in enumerate(previews):
        x, y = i % 8 * 192, i // 8 * 216
        contact.paste(frame.resize((192, 192), Image.Resampling.LANCZOS), (x, y))
        labels.text((x+8, y+194), str(i+1), fill='white')
        frame.save(STAGING / f'frame-{i:03}.png')
    contact.save(ART / 'delivered-frames-v2.png')
    previews[46].save(ART / 'Minazuki-thumbnail-v2.png')
    # WebP coalesces held cels; verify elapsed time and every decoded pose.
    expected = []
    for frame, duration in zip(previews, durations):
        if expected and frame.tobytes() == expected[-1][0]:
            expected[-1][1] += duration
        else:
            expected.append([frame.tobytes(), duration])
    with Image.open(ART / 'Minazuki-preview-v2.webp') as preview:
        assert preview.n_frames == len(expected)
        for i, (pixels, duration) in enumerate(expected):
            preview.seek(i); preview.load()
            assert preview.convert('RGB').tobytes() == pixels
            assert preview.info['duration'] == duration
    manifest = dict(frames=COUNT, fps=FPS, seconds=COUNT/FPS, cell=CELL, columns=4, rows=4,
                    pages=PAGES, painted_cels=35, impact_seconds=1.75, upscaling=False, interpolation=False, alpha_mean=opacity,
                    visible_bounds=bounds, sheet_sha256=hashes,
                    sources={str(p.relative_to(SOURCE)): sha256(p.read_bytes()).hexdigest() for p in SOURCE.rglob('*.png')},
                    status='TGA roundtrip and preview checked; actual WoW rendering unverified')
    (STAGING / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print('PASS: 35 unique native cels, 88 timed frames, 1.75s impact, RGBA/margins/end, 6 TGA roundtrips, WebP equality')


if __name__ == '__main__':
    build()
