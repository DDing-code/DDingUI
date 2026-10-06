"""Pack 48 individually generated animation drawings into one staged WoW TGA.

python DDingUI_FX/tools/build_murasaki.py
Extracts cells, registers authored centers/sizes and converts emission to RGBA.
Motion is drawn in each cell; no static-art animation or frame interpolation.
"""
from pathlib import Path
from hashlib import sha256
import json
import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'artifacts/DDingUI_FX/murasaki'
STAGING = ART / 'v9-build'
CELL, PAD, COLS, ROWS, FRAMES, FPS = 512, 32, 8, 8, 48, 24

# Authored origins measured from the silhouette, not the moving bright nucleus.
# Release/afterimage origins stay fixed instead of tracking departing particles.
ORIGINS = (
    (183.896, 191.618), (180.223, 189.572), (177.317, 190.244), (178.589, 190.501), (183.879, 170.396), (184.002, 169.521),
    (179.507, 173.448), (179.183, 174.038), (181.627, 162.123), (182.843, 161.671), (182.159, 161.712), (179.482, 161.741),
    (192.506, 188.153), (183.494, 188.982), (176.706, 188.958), (175.583, 189.872), (187.59, 165.958), (180.298, 165.757),
    (171.19, 170.588), (174.236, 171.211), (182.451, 143.895), (178.817, 143.909), (173.935, 143.742), (172.297, 143.988),
    (186.078, 199.623), (180.11, 199.614), (172.389, 199.054), (170.593, 198.925), (184.991, 168.516), (179.652, 167.885),
    (172.449, 167.618), (169.397, 167.053), (184.795, 163.114), (178.993, 162.558), (170.848, 162.526), (168.619, 163.41),
    (160.718, 158.711), (163.928, 163.449), (175.276, 174.03), (177.724, 176.981), (223.574, 218.01), (216.927, 218.971),
    (213.616, 217.463), (215.418, 217.389), (219.456, 200.846), (213.73, 200.672), (213.533, 201.158), (216.398, 201.615),
    (192.508, 191.869), (184.85, 192.404), (176.767, 192.855), (171.671, 192.388), (182.295, 158.444), (180.007, 158.047),
    (174.758, 158.534), (170.078, 158.762), (179.808, 160.324), (176.301, 160.475), (173.211, 160.953), (173.288, 161.188),
)
# Calibrate drawn size and near-circular aspect; never enlarge a source pixel.
SCALES = {
    6: (0.989474, 0.989474),
    7: (0.959184, 0.959184),
    8: (0.921569, 0.921569),
    9: (0.899522, 0.899522),
    10: (0.890995, 0.890995),
    11: (0.886792, 0.886792),
    12: (0.979167, 0.979167),
    13: (0.969072, 0.969072),
    14: (0.944724, 0.944724),
    15: (0.94, 0.94),
    16: (0.854545, 0.854545),
    17: (0.846847, 0.846847),
    18: (0.725309, 0.759004),
    19: (0.729464, 0.754563),
    20: (0.721429, 0.748971),
    21: (0.721602, 0.746815),
    22: (0.720259, 0.745603),
    23: (0.712195, 0.736901),
    24: (0.67221, 0.696827),
    25: (0.672688, 0.695042),
    26: (0.669966, 0.693285),
    27: (0.67054, 0.693521),
    28: (0.666089, 0.695226),
    29: (0.671258, 0.689226),
    30: (0.670163, 0.68776),
    31: (0.661201, 0.681098),
    32: (0.65924, 0.678358),
    33: (0.656078, 0.673107),
    34: (0.650105, 0.670984),
    35: (0.646055, 0.66722),
    36: (0.692474, 0.696633),
    37: (0.769074, 0.76623),
    38: (0.803419, 0.805344),
    39: (0.858449, 0.8564),
    48: (0.854545, 0.854545),
    49: (0.854545, 0.854545),
    50: (0.850679, 0.850679),
    51: (0.843049, 0.843049),
    52: (0.773663, 0.773663),
    53: (0.752, 0.752),
    54: (0.744186, 0.744186),
    55: (0.756757, 0.756757),
    56: (0.707193, 0.730007),
    57: (0.700222, 0.726254),
    58: (0.693294, 0.718925),
    59: (0.698105, 0.717227),
}
# Split raised last rows in their empty gaps, retaining the full circles.
ROW_CUTS = {2: (0, 362, 696, 1087), 5: (0, 362, 690, 1087)}
# The second sheet starts earlier in the approach. Interleave its drawings by
# decreasing separation so the circles never reopen at the sheet boundary.
# Replace output frames 13-24 with twelve new, progressively overlapping poses.
FRAME_ORDER = (*range(6), 12, 6, 13, 14, 7, 8, *range(48, 60), *range(24, 48))


def native_frames():
    frames, provenance, sources = [], [], []
    for batch in range(6):
        source = (ART / 'sequence-v8/release-single-wave.png' if batch == 4
                  else ART / 'sequence-v9/fusion.png' if batch == 5
                  else ART / 'sequence-v5' / f'sequence-{batch + 1:02}.png')
        row_count = 2 if batch == 4 else 3
        with Image.open(source) as image:
            assert image.mode == 'RGB' and abs(image.width * row_count - image.height * 4) <= 16, source
            assert 340 <= image.width / 4 <= 512, source
            data = np.array(image)
        sources.append(source)
        if batch == 3:
            # Preserve v5's four launch circles, which cross nominal row cuts.
            # Its later corner streaks are excluded from the output.
            count, labels, stats, centers = cv2.connectedComponentsWithStats((data.max(axis=2) > 6).astype('uint8'))
            owners = np.full(count, -1)
            for label in range(1, count):
                cx, cy = centers[label]
                row = 0 if cy < 350 else 1 if cy < 696 else 2
                owners[label] = row * 4 + min(int(cx * 4 / data.shape[1]), 3)
            ownership = owners[labels]
        rows = ROW_CUTS.get(batch, tuple(round(row * data.shape[0] / row_count) for row in range(row_count + 1)))
        assert rows[0] == 0 and rows[-1] == data.shape[0]
        for cell in range(4 if batch == 3 else row_count * 4):
            index = (40 if batch == 4 else 48 if batch == 5 else batch * 12) + cell
            x, right = [round(col * data.shape[1] / 4) for col in (cell % 4, cell % 4 + 1)]
            y, bottom = rows[cell // 4:cell // 4 + 2]
            if batch == 3:
                yy, xx = np.where(ownership == cell)
                assert len(xx), ('missing release drawing', cell)
                x, right, y, bottom = int(xx.min()), int(xx.max()) + 1, int(yy.min()), int(yy.max()) + 1
            rgb = data[y:bottom, x:right].astype(np.float64)
            if batch == 3:
                rgb[ownership[y:bottom, x:right] != cell] = 0
                assert np.count_nonzero(rgb.max(axis=2) > 6) == len(xx), ('cut release drawing', cell)
            native = np.array((right - x, bottom - y))
            # Split native light-on-black into straight RGB/alpha for WoW BLEND.
            rgb[np.max(rgb, axis=2) <= 6] = 0
            if index == 47:
                rgb *= .15  # Finish the single wave below 1% peak light.
            alpha = np.max(rgb, axis=2)
            if batch != 3:
                assert max(alpha[0].max(), alpha[-1].max(), alpha[:, 0].max(), alpha[:, -1].max()) < 24, ('cut artwork', index)
            rgba = np.zeros((*rgb.shape[:2], 4), np.uint8)
            rgba[:, :, :3] = np.uint8(np.rint(rgb * 255 / np.maximum(alpha[:, :, None], 1)))
            rgba[:, :, 3] = np.rint(alpha).astype(np.uint8)
            restored = rgba[:, :, :3].astype(float) * rgba[:, :, 3:4] / 255
            assert np.max(np.abs(restored - rgb)) <= 1
            scale = np.array(SCALES.get(index, (1, 1)))
            assert np.all((scale > 0) & (scale <= 1)), ('native art must never be enlarged', index)
            sprite = Image.fromarray(rgba)
            size = np.rint(native * scale).astype(int)
            if np.any(size != native):
                sprite = sprite.resize(tuple(size), Image.Resampling.LANCZOS)
            shift = np.rint(256 - np.array(ORIGINS[index]) * size / native).astype(int)
            frame = Image.new('RGBA', (CELL, CELL))
            frame.paste(sprite, tuple(shift))
            box = frame.getchannel('A').getbbox()
            assert box and min(box[:2]) >= PAD and max(box[2:]) <= CELL - PAD, (index, box)
            frames.append(frame)
            provenance.append(dict(frame=index, source=source.name, source_cell=cell,
                                   source_bounds=[x, y, right, bottom],
                                   registration=shift.tolist(), native_cell=native.tolist(),
                                   native_scale=(size / native).tolist(),
                                   source_rgb_sha256=sha256(rgb.tobytes()).hexdigest()))
    assert len(frames) == len(ORIGINS) == 60
    assert len(FRAME_ORDER) == len(set(FRAME_ORDER)) == FRAMES
    assert len({frames[index].tobytes() for index in FRAME_ORDER}) == FRAMES
    provenance = [dict(provenance[source_frame], frame=frame, authored_frame=source_frame)
                  for frame, source_frame in enumerate(FRAME_ORDER)]
    return [frames[index] for index in FRAME_ORDER], provenance, sources


def build():
    STAGING.mkdir(parents=True, exist_ok=True)
    frames, provenance, sources = native_frames()
    sheet = Image.new('RGBA', (COLS * CELL, ROWS * CELL))
    for index, frame in enumerate(frames):
        sheet.paste(frame, (index % COLS * CELL, index // COLS * CELL))
    output = STAGING / 'HollowPurple.tga'
    sheet.save(output, compression=None)
    decoded_frames = []
    with Image.open(output) as delivered:
        assert delivered.mode == 'RGBA' and delivered.size == (4096, 4096)
        for index in range(COLS * ROWS):
            x, y = index % COLS * CELL, index // COLS * CELL
            frame = delivered.crop((x, y, x + CELL, y + CELL))
            if index < FRAMES:
                assert frame.tobytes() == frames[index].tobytes()
                decoded_frames.append(frame)
            else:
                assert frame.getchannel('A').getbbox() is None
    header = output.read_bytes()[:18]
    assert header[2] == 2 and header[16] == 32 and header[17] & 15 == 8
    alpha_mean = [float(np.array(f.getchannel('A')).mean()) for f in decoded_frames]
    assert min(alpha_mean) > 0
    assert alpha_mean[0] < max(alpha_mean) * .02 and alpha_mean[-1] < max(alpha_mean) * .01
    previews = [Image.alpha_composite(Image.new('RGBA', (CELL, CELL), (20, 22, 29, 255)), f).convert('RGB')
                for f in decoded_frames]
    durations = [round((i + 1) * 1000 / FPS) - round(i * 1000 / FPS) for i in range(FRAMES)]
    webp = ART / 'HollowPurple-preview-v9.webp'
    previews[0].save(webp, save_all=True, append_images=previews[1:], lossless=True,
                     quality=100, method=4, duration=durations, loop=0)
    contact = Image.new('RGB', (6 * 256, 8 * 280), (20, 22, 29))
    draw = ImageDraw.Draw(contact)
    for i, frame in enumerate(previews):
        x, y = i % 6 * 256, i // 6 * 280
        contact.paste(frame.resize((256, 256), Image.Resampling.LANCZOS), (x, y))
        draw.text((x + 8, y + 258), str(i + 1), fill=(160, 165, 178))
    contact.save(ART / 'delivered-frames-v9.png')
    palette = contact.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    gif_frames = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in previews]
    gif_durations = [round((i + 1) * 100 / FPS) * 10 - round(i * 100 / FPS) * 10 for i in range(FRAMES)]
    gif_frames[0].save(ART / 'HollowPurple-preview-v9.gif', save_all=True, append_images=gif_frames[1:],
                       duration=gif_durations, disposal=2, optimize=False, loop=0)
    previews[29].save(ART / 'HollowPurple-frame-v9.png')
    with Image.open(webp) as preview:
        assert preview.n_frames == FRAMES
        total = 0
        for i in range(FRAMES):
            preview.seek(i); preview.load(); total += preview.info['duration']
        assert total == 2000
    manifest = dict(frames=FRAMES, fps=FPS, duration_seconds=2, cell=CELL, padding=PAD,
                    columns=COLS, rows=ROWS, pages=1, authored_frame_count=FRAMES,
                    frame_generation='48 native sequential drawings; no motion overlays or interpolation',
                    alignment='authored silhouette origins; calibrated body sizes; no enlargement or brightness tracking',
                    sequence='progressive red/blue overlap and color fusion, violet condensation, forward release, one thin circular wave',
                    sources={p.name: sha256(p.read_bytes()).hexdigest() for p in sources},
                    sheet_sha256=sha256(output.read_bytes()).hexdigest(), frame_provenance=provenance,
                    alpha_mean=alpha_mean, status='staged; inspect before installing; WoW render untested')
    (STAGING / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print('PASS: 48 native drawings / 24 FPS / 2 sec; RGBA, gutters, exact TGA decoding and preview duration')


if __name__ == '__main__':
    build()
