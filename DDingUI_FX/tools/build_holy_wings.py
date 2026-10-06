"""Bake v19 light-wing art with v22 continuous unfurling. Inspect staging before installing.

python DDingUI_FX/tools/build_holy_wings.py
Uses installed Pillow, NumPy, OpenCV and SciPy; no generated pose swaps or optical flow.
"""
from hashlib import sha256
from math import sin, cos, pi, radians
from pathlib import Path
import json
import cv2
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "artifacts/DDingUI_FX/holy-wings"
SOURCE = ART / "HolyWings-light-source-v19.png"
STAGING = ART / "v22-build"
CELL, PAD, COLS, ROWS = 512, 32, 8, 8
FRAME_COUNT, FPS, TRANSITION = 120, 30, 34
SCALE, OFFSET, SAMPLE = .34, (512 - 1254 * .34) / 2, 2
SOURCE_ROOT = np.array([563., 684.])
ELBOW = np.array([370., 505.])


def smooth(t):
    t = np.clip(t, 0, 1)
    return t * t * (3 - 2 * t)


def fan_open(x, y, t, inverse=False):
    """Open individual rays around a fixed root, preserving every ray's radius."""
    opening = .18 + .82 * smooth(t / 1.05)
    opening *= 1 - .25 * smooth((t - (FRAME_COUNT - TRANSITION) / FPS) / .9)
    dx, dy = SOURCE_ROOT[0] - x, y - SOURCE_ROOT[1]
    radius = np.hypot(dx, dy)
    spread = 1 - (1 - opening) * smooth((radius - 35) / 80)
    angle, folded = np.arctan2(dy, dx), radians(-68)
    angle = folded + ((angle - folded) / spread if inverse else (angle - folded) * spread)
    valid = (angle >= -pi) & (angle <= pi)
    return SOURCE_ROOT[0] - radius * np.cos(angle), SOURCE_ROOT[1] + radius * np.sin(angle), valid


def deform(x, y, t):
    """Fixed shoulder, elbow rotation and delayed fan rotation of the same painted surface."""
    # Cross the middle of a downstroke as the fan finishes opening, not a turning point.
    phase = 2 * pi * (t - 1.05) / 3.8 + pi + .3
    shoulder = radians(2.2) * sin(phase)
    outward = ((x - SOURCE_ROOT[0]) * -193 + (y - SOURCE_ROOT[1]) * -179) / (193**2 + 179**2)
    weight = smooth((outward - .25) / .75)
    u, v = x - ELBOW[0], y - ELBOW[1]
    # A ray within the outer fan rotates together; never change source width or height.
    sector = v / np.maximum(np.hypot(u, v), 1)
    fan = radians(5) * sin(phase - .3)
    fan += radians(1.8) * sector * sin(phase - .65)
    yaw = radians(12) * sin(phase - .45)
    ex = (u * np.cos(fan) - v * np.sin(fan)) * cos(yaw)
    ey = u * np.sin(fan) + v * np.cos(fan)
    qx = x + (ELBOW[0] + ex - x) * weight - SOURCE_ROOT[0]
    qy = y + (ELBOW[1] + ey - y) * weight - SOURCE_ROOT[1]
    return (SOURCE_ROOT[0] + qx * cos(shoulder) - qy * sin(shoulder),
            SOURCE_ROOT[1] + qx * sin(shoulder) + qy * cos(shoulder))


def load_art():
    source = Image.open(SOURCE)
    assert source.mode == "RGBA" and source.size == (1254, 1254)
    data = np.array(source)
    alpha = data[:, :, 3]
    assert alpha.min() == 0 and alpha.max() > 240
    count, labels, stats, centers = cv2.connectedComponentsWithStats((alpha > 200).astype(np.uint8))
    bodies = sorted(range(1, count), key=lambda k: stats[k, 4], reverse=True)[:2]
    bodies.sort(key=lambda k: centers[k, 0])
    assert stats[bodies[0], 0] + stats[bodies[0], 2] < 627 < stats[bodies[1], 0]
    # Assign translucent fringes to their nearest solid component without repainting pixels.
    nearest = distance_transform_edt(labels == 0, return_distances=False, return_indices=True)
    owners = labels[tuple(nearest)]
    body = data.copy()
    # Retain the entire translucent ribbon/halo layer, including the source glints.
    body[:, :, 3] = np.where(alpha >= 3, alpha, 0)
    soft_light = (alpha > 10) & (alpha < 180)
    assert np.array_equal(body[soft_light], data[soft_light]), "Source halo was removed"
    shards, stars = [], []
    for k in range(1, count):
        x, y, width, height, area = stats[k]
        # Two long light diamonds and seven small glints from this source, never feather cutouts.
        shard = 450 <= area <= 550 and height > width * 1.6
        star = 60 <= area <= 110 and max(width, height) < 25
        if not (shard or star):
            continue
        box = (max(0, x - 24), max(0, y - 24), min(1254, x + width + 24), min(1254, y + height + 24))
        part = data[box[1]:box[3], box[0]:box[2]].copy()
        mask = owners[box[1]:box[3], box[0]:box[2]] == k
        part[:, :, 3] = np.where(mask & (part[:, :, 3] >= 3), part[:, :, 3], 0)
        (shards if shard else stars).append((Image.fromarray(part), centers[k]))
    assert len(shards) == 2 and len(stars) == 7
    premult = body.astype(np.float32) / 255
    premult[:, :, :3] *= premult[:, :, 3:4]
    return body, premult, shards, stars


def wing_pose(premult, t, source_labels):
    size = CELL * SAMPLE
    yy, xx = np.mgrid[:size, :size].astype(np.float32)
    tx = ((xx + .5) / SAMPLE - OFFSET) / SCALE - .5
    ty = ((yy + .5) / SAMPLE - OFFSET) / SCALE - .5
    right = tx >= 627
    target_x = np.where(right, 1253 - tx, tx)
    target_x, ty, valid = fan_open(target_x, ty, t, inverse=True)
    qx, qy = target_x.copy(), ty.copy()
    for _ in range(8):
        fx, fy = deform(qx, qy, t)
        qx += target_x - fx
        qy += ty - fy
    fx, fy = deform(qx, qy, t)
    mapped_x = np.where(right, 1253 - qx, qx).astype(np.float32)
    sampled = cv2.remap(premult, mapped_x, qy.astype(np.float32), cv2.INTER_LANCZOS4,
                        borderMode=cv2.BORDER_CONSTANT)
    # The inverse fan can reach the other source wing; each side owns only its own half.
    sampled[~valid | (qx >= 627)] = 0
    # Outside the source, transparent padding has no inverse-surface constraint.
    visible = sampled[:, :, 3] > 1 / 255
    error = max(float(np.max(np.abs(fx - target_x)[visible])), float(np.max(np.abs(fy - ty)[visible])))
    assert error < .1, (t, error)
    sampled = np.clip(cv2.resize(sampled, (CELL, CELL), interpolation=cv2.INTER_AREA), 0, 1)
    sampled[:, :, :3] /= np.maximum(sampled[:, :, 3:4], 1e-6)
    # Let the translucent light breathe while the white-hot cores stay unchanged.
    fringe = 1 - smooth((sampled[:, :, 3] - .45) / .4)
    sampled[:, :, 3] *= 1 + .12 * sin(2 * pi * t / 2.8) * fringe
    sampled[:, :, :3][sampled[:, :, 3] < 1 / 255] = 0
    labels = cv2.remap(source_labels, mapped_x, qy.astype(np.float32), cv2.INTER_NEAREST,
                       borderMode=cv2.BORDER_CONSTANT)
    labels = cv2.resize(labels, (CELL, CELL), interpolation=cv2.INTER_NEAREST).astype(np.int32)
    return Image.fromarray(np.uint8(np.clip(sampled * 255, 0, 255))), labels


def particle_path(start, end, progress, bend):
    delta = end - start
    normal = np.stack((-delta[..., 1], delta[..., 0]), axis=-1)
    normal /= np.maximum(np.linalg.norm(delta, axis=-1, keepdims=True), 1)
    control = np.clip((start + end) / 2 + normal * np.asarray(bend)[..., None], PAD + 12, CELL - PAD - 12)
    u = smooth(progress)[..., None]
    return (1 - u) ** 2 * start + 2 * (1 - u) * u * control + u ** 2 * end


def make_formation(body):
    rng = np.random.default_rng(20)
    alpha = body[:, :, 3]
    points = []
    # Jittered source anchors partition the actual light into small irregular fragments.
    for y in range(0, alpha.shape[0], 28):
        for x in range(0, alpha.shape[1], 28):
            ys, xs = np.where(alpha[y:y + 28, x:x + 28] > 140)
            if len(xs) < 5:
                continue
            k = rng.integers(len(xs))
            points.append((x + xs[k], y + ys[k]))
    points = np.array(points)
    markers = np.zeros(alpha.shape, dtype=np.int32)
    empty = np.ones(alpha.shape, dtype=bool)
    for k, (x, y) in enumerate(points):
        markers[y, x], empty[y, x] = k, False
    nearest = distance_transform_edt(empty, return_distances=False, return_indices=True)
    labels = markers[tuple(nearest)].astype(np.float32)
    targets = points.astype(float) * SCALE + OFFSET
    count = len(points)
    side = np.where(points[:, 0] < 627, -1, 1)
    roots = np.column_stack((np.where(side < 0, SOURCE_ROOT[0], 1253 - SOURCE_ROOT[0]),
                             np.full(count, SOURCE_ROOT[1]))) * SCALE + OFFSET
    clouds = []
    for _ in range(2):
        angles = rng.uniform(0, 2 * pi, count)
        radius = rng.uniform(45, 90, count)
        cloud = targets + np.column_stack((np.cos(angles), np.sin(angles))) * radius[:, None]
        # Reflect into the safe area instead of piling clipped particles along an edge.
        cloud = np.where(cloud < PAD + 12, 2 * (PAD + 12) - cloud, cloud)
        cloud = np.where(cloud > CELL - PAD - 12, 2 * (CELL - PAD - 12) - cloud, cloud)
        clouds.append(cloud)
    # A small pool of light at each root fans outward; no wide random starting cloud.
    clouds[0] = roots + np.column_stack((side * rng.uniform(8, 25, count), rng.uniform(-24, 24, count)))
    reach = np.clip(np.linalg.norm(targets - roots, axis=1) / 245, 0, 1)
    formation = dict(points=points, labels=labels, incoming=clouds[0], outgoing=clouds[1],
                     birth=rng.uniform(.01, .12, count),
                     arrival=np.clip(.34 + .58 * reach ** .8 + rng.uniform(0, .035, count), .36, .98),
                     release=rng.uniform(0, .45, count), life=rng.uniform(.45, .65, count),
                     bend=rng.uniform(18, 34, count) * np.where(points[:, 0] < 627, -1, 1))
    assert count > 500 and np.unique(labels).size == count
    assert np.array_equal(labels[points[:, 1], points[:, 0]], np.arange(count))
    assert np.allclose(particle_path(clouds[0], targets, np.zeros(count), formation['bend']), clouds[0])
    assert np.allclose(particle_path(clouds[0], targets, np.ones(count), formation['bend']), targets)
    assert np.max(formation['arrival']) + .10 < (TRANSITION - 1) / FPS
    assert np.max(formation['release'] + formation['life']) < (TRANSITION - 1) / FPS
    for incoming in (True, False):
        positions = []
        for i in range(TRANSITION):
            t = (i if incoming else FRAME_COUNT - TRANSITION + i) / FPS
            targets = attached(points, t)
            if incoming:
                u = (t - formation['birth']) / (formation['arrival'] - formation['birth'])
                start, end = clouds[0], targets
            else:
                u = (i / FPS - formation['release']) / formation['life']
                start, end = targets, clouds[1]
            positions.append(particle_path(start, end, u, formation['bend']))
        speed = np.linalg.norm(np.diff(positions, axis=0), axis=-1).max()
        assert speed < 16, ("Particle moves too far in one frame", incoming, speed)
    left = points[points[:, 0] < 627].T
    opened_x, opened_y, _ = fan_open(*left, 1.1)
    folded_x, folded_y, _ = fan_open(*left, 0)
    radii = np.hypot(left[0] - SOURCE_ROOT[0], left[1] - SOURCE_ROOT[1])
    assert np.allclose((opened_x, opened_y), left)
    assert np.allclose(np.hypot(folded_x - SOURCE_ROOT[0], folded_y - SOURCE_ROOT[1]), radii)
    outer = radii > 115
    full_angles = np.arctan2(left[1] - SOURCE_ROOT[1], SOURCE_ROOT[0] - left[0])[outer]
    folded_angles = np.arctan2(folded_y - SOURCE_ROOT[1], SOURCE_ROOT[0] - folded_x)[outer]
    assert np.ptp(folded_angles) < np.ptp(full_angles) * .25, "Rays are not folded before opening"
    return formation


def transition(pose, labels, t, formation, stars):
    out_start = (FRAME_COUNT - TRANSITION) / FPS
    if (TRANSITION - 1) / FPS < t < out_start:
        return pose.copy()
    targets = attached(formation['points'], t)
    if t < out_start:
        u = np.clip((t - formation['birth']) / (formation['arrival'] - formation['birth']), 0, 1)
        age = t - formation['arrival']
        coverage = smooth((age + .10) / .20)
        active = (t > formation['birth']) & (age < .12)
        start, end = formation['incoming'], targets
        opacity = smooth((t - formation['birth']) / .10) * (1 - smooth(age / .12))
    else:
        age = t - out_start - formation['release']
        u = np.clip(age / formation['life'], 0, 1)
        coverage = 1 - smooth((age + .04) / .15)
        active = (age > -.04) & (u < 1)
        start, end = targets, formation['outgoing']
        opacity = smooth((age + .04) / .12) * (1 - smooth((u - .6) / .4))
    centers = particle_path(start, end, u, formation['bend'])
    data = np.array(pose)
    # Each patch condenses only when its particle arrives; soften seams, not the source art.
    mask = cv2.GaussianBlur(coverage[labels].astype(np.float32), (0, 0), 1.6)
    data[:, :, 3] = np.uint8(np.rint(data[:, :, 3] * mask))
    frame = Image.fromarray(data)
    for k in np.flatnonzero(active):
        # Keep flying material as light points, never enlarged polygonal source cutouts.
        light = opacity[k] * (.45 + .45 * sin(pi * u[k]) ** .5)
        star = stars[k % len(stars)][0]
        size = (8 + k % 5 * 2) * (.55 + .45 * smooth(u[k] / .3))
        if k % 3 == 0:
            for lag in (.10, .05):
                tail = particle_path(start[k], end[k], max(0, u[k] - lag), formation['bend'][k])
                place(frame, star, tail, size * .7, 0, light * .25)
        place(frame, star, centers[k], size, 0, light)
    return frame


def place(frame, sprite, center, size, angle, opacity):
    if opacity <= 0:
        return
    scale = size / max(sprite.size)
    assert scale <= 1, "Never enlarge a source component"
    cutout = sprite.resize(tuple(max(1, round(d * scale)) for d in sprite.size), Image.Resampling.LANCZOS)
    cutout = cutout.rotate(angle, Image.Resampling.BICUBIC, expand=True)
    cutout.putalpha(cutout.getchannel("A").point([round(a * min(1, opacity)) for a in range(256)]))
    frame.alpha_composite(cutout, (round(center[0] - cutout.width / 2), round(center[1] - cutout.height / 2)))


def attached(point, t):
    x, y = np.asarray(point).T
    right = x >= 627
    qx, qy = deform(np.where(right, 1253 - x, x), y, t)
    qx, qy, _ = fan_open(qx, qy, t)
    return np.stack((np.where(right, 1253 - qx, qx), qy), axis=-1) * SCALE + OFFSET


def add_particles(frame, t, shards, stars, behind=False):
    tail = 1 - smooth((t - 3.65) / .30)
    for k in range(18):
        depth = k % 3
        if (depth == 0) != behind:
            continue
        born, life = .25 + k * .18, (1.9, 1.65, 1.4)[depth]
        age = t - born
        if not 0 < age < life:
            continue
        sprite, source_origin = shards[k % len(shards)]
        origin = source_origin - np.array([0, 120 + depth * 12])
        side = -1 if origin[0] < 627 else 1
        center = attached(origin, born) + (side * (age * 14 + sin(age * 1.8) * 7), -age * (14 + depth * 5))
        opacity = smooth(age / .24) * (1 - smooth((age / life - .65) / .35)) * tail
        opacity *= (.38, .7, .95)[depth]
        angle = side * (18 + sin(age * 1.5) * 12)
        place(frame, sprite, center, (12, 19, 26)[depth], angle, opacity)
    if behind:
        return
    # Source glints keep their real positions/scale, with a few broad, slow flashes.
    strength = min(1, t / .85) * tail
    for k, (sprite, point) in enumerate(stars):
        pulse = max(0, sin(t * 2.5 + k * 1.6)) ** 8
        place(frame, sprite, attached(point, t), max(sprite.size) * SCALE * 1.1, 0, pulse * .5 * strength)


def build():
    body, premult, shards, stars = load_art()
    formation = make_formation(body)
    sequence, poses, tips = [], [], []
    for i in range(FRAME_COUNT):
        t = i / FPS
        assert np.allclose(deform(*SOURCE_ROOT, t), SOURCE_ROOT)
        assert np.allclose(fan_open(*SOURCE_ROOT, t)[:2], SOURCE_ROOT)
        tips.append(attached(np.array([180., 190.]), t))
        pose, labels = wing_pose(premult, t, formation['labels'])
        _, _, components, _ = cv2.connectedComponentsWithStats((np.array(pose)[:, :, 3] > 100).astype(np.uint8))
        assert (components[1:, 4] > 400).sum() == 2, "Inverse fan sampled an extra wing"
        poses.append(pose)
        formed = transition(pose, labels, t, formation, stars)
        if i == TRANSITION - 1:
            assert formed.tobytes() == pose.tobytes(), "Fragments did not reconstruct the source"
        frame = Image.new("RGBA", (CELL, CELL))
        add_particles(frame, t, shards, stars, behind=True)
        frame = Image.alpha_composite(frame, formed)
        add_particles(frame, t, shards, stars)
        if i in (0, FRAME_COUNT - 1):
            assert frame.getchannel('A').getbbox() is None, "Particles must clear before the end"
        sequence.append(frame)
        if i % FPS == FPS - 1:
            print(f"Rendered {i + 1}/{FRAME_COUNT} frames", flush=True)
    assert len({pose.tobytes() for pose in poses}) == FRAME_COUNT
    assert np.linalg.norm(np.diff(tips[TRANSITION:FRAME_COUNT - TRANSITION], axis=0), axis=1).max() < 1.5
    assert np.linalg.norm(np.diff(tips, axis=0), axis=1).max() < 4
    handoff = np.diff(tips[TRANSITION - 4:TRANSITION + 12], axis=0)
    assert np.linalg.norm(handoff, axis=1).min() > .4, "Wing stalls just after forming"
    assert np.all(np.sum(handoff[:-1] * handoff[1:], axis=1) > 0), "Wing reverses during handoff"
    assert np.ptp(np.array(tips[:TRANSITION]), axis=0).max() > 3
    assert np.ptp(np.array(tips[-TRANSITION:]), axis=0).max() > 3
    motion_delta = [np.abs(np.array(a, dtype=float)[:, :, 3] - np.array(b, dtype=float)[:, :, 3]).mean() / 255
                    for a, b in zip(poses, poses[1:])]
    assert max(motion_delta[TRANSITION:FRAME_COUNT - TRANSITION - 1]) < .018
    frame_delta = [np.abs(np.array(a, dtype=float)[:, :, 3] - np.array(b, dtype=float)[:, :, 3]).mean() / 255
                   for a, b in zip(sequence, sequence[1:])]
    # Traveling particles change pixels by design; detect flashes from total opacity instead.
    coverage = [np.array(frame)[:, :, 3].mean() / 255 for frame in sequence]
    coverage_delta = float(np.abs(np.diff(coverage)).max())
    assert coverage_delta < .020, "Abrupt total-light change"
    mask = np.array(poses[18])[:, :, 3] > 220
    ratios = np.array(sequence[18])[:, :, 3][mask] / np.array(poses[18])[:, :, 3][mask]
    assert ratios.min() < .05 and ratios.max() > .95, "Uniform fade regression"
    for i in (12, 110):
        outside = (np.array(poses[i])[:, :, 3] == 0) & (np.array(sequence[i])[:, :, 3] > 8)
        assert outside.sum() > 100, "Missing particle transport outside the wing silhouette"
    assert sequence[-1].getchannel("A").getbbox() is None
    capacity = COLS * ROWS
    STAGING.mkdir(exist_ok=True)
    paths = [STAGING / "HolyWings.tga", STAGING / "HolyWings_2.tga"]
    for page, path in enumerate(paths):
        atlas = Image.new("RGBA", (COLS * CELL, ROWS * CELL))
        for i, frame in enumerate(sequence[page * capacity:(page + 1) * capacity]):
            bounds = frame.getchannel("A").getbbox()
            if bounds:
                left, top, right, bottom = bounds
                assert min(left, top) >= PAD and max(right, bottom) <= CELL - PAD, (page, i, bounds)
            atlas.paste(frame, (i % COLS * CELL, i // COLS * CELL))
        atlas.save(path, compression=None)
        atlas.save(path.with_suffix(".png"))
    # Preview only decoded TGA pixels, following the row/page order in Playback.lua.
    frames = []
    for page, path in enumerate(paths):
        with Image.open(path) as atlas:
            assert atlas.mode == "RGBA" and atlas.size == (4096, 4096)
            for i in range(min(capacity, FRAME_COUNT - page * capacity)):
                x, y = i % COLS * CELL, i // COLS * CELL
                frame = atlas.crop((x, y, x + CELL, y + CELL))
                assert frame.tobytes() == sequence[page * capacity + i].tobytes()
                background = Image.new("RGBA", (CELL, CELL), (20, 22, 29, 255))
                frames.append(Image.alpha_composite(background, frame).convert("RGB"))
            if page == 1:
                assert atlas.crop((0, CELL * 7, 4096, 4096)).getchannel("A").getbbox() is None
        header = path.read_bytes()[:18]
        assert header[2] == 2 and header[16] == 32 and header[17] & 15 == 8
    durations = [round((i + 1) * 4000 / FRAME_COUNT / 10) * 10 - round(i * 4000 / FRAME_COUNT / 10) * 10
                 for i in range(FRAME_COUNT)]
    # One palette avoids GIF colors changing between frames. WebP preserves the decoded pixels.
    samples = Image.new("RGB", (CELL * 4, CELL * 3))
    for i, index in enumerate(range(0, FRAME_COUNT, 10)):
        samples.paste(frames[index], (i % 4 * CELL, i // 4 * CELL))
    palette = samples.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    gif_frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    preview = ART / "HolyWings-preview-v22.gif"
    gif_frames[0].save(preview, save_all=True, append_images=gif_frames[1:], loop=0, duration=durations, disposal=2, optimize=False)
    webp_durations = [round((i + 1) * 4000 / FRAME_COUNT) - round(i * 4000 / FRAME_COUNT) for i in range(FRAME_COUNT)]
    frames[0].save(ART / "HolyWings-preview-v22.webp", save_all=True, append_images=frames[1:],
                   lossless=True, quality=100, method=4, loop=0, duration=webp_durations)
    with Image.open(ART / "HolyWings-preview-v22.webp") as decoded:
        total = 0
        assert decoded.n_frames == FRAME_COUNT
        for i in range(decoded.n_frames):
            decoded.seek(i)
            decoded.load()
            total += decoded.info["duration"]
            if i % FPS == 0:
                assert decoded.convert("RGB").tobytes() == frames[i].tobytes()
        assert total == 4000
    with Image.open(preview) as gif:
        total = 0
        for i in range(gif.n_frames):
            gif.seek(i)
            total += gif.info["duration"]
        assert total == 4000
    contact = Image.new("RGB", (256 * 8, 256 * 3))
    for i, index in enumerate([0, 4, 8, 12, 16, 20, 26, 33, 38, 45, 53, 60, 68, 76, 83, 86, 89, 93, 97, 101, 105, 109, 114, 119]):
        contact.paste(frames[index].resize((256, 256), Image.Resampling.LANCZOS), (i % 8 * 256, i // 8 * 256))
    contact.save(ART / "delivered-frames-v22.png")
    frames[45].save(ART / "HolyWings-frame-v22.png")
    manifest = dict(source_sha256=sha256(SOURCE.read_bytes()).hexdigest(), frames=FRAME_COUNT, fps=FPS,
                    cell=CELL, columns=COLS, rows=ROWS, pages=2, max_alpha_delta=max(motion_delta),
                    particle_fragments=len(formation['points']), transition_frames=TRANSITION,
                    transition_style="root light unfolds into a fixed-radius fan, then scatters",
                    min_handoff_speed=float(np.linalg.norm(handoff, axis=1).min()),
                    max_frame_alpha_delta=max(frame_delta),
                    max_coverage_delta=coverage_delta,
                    sheets={p.name: sha256(p.read_bytes()).hexdigest() for p in paths},
                    status="staged; inspect preview before copying into Media")
    (STAGING / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"PASS: {len(formation['points'])} particle arrivals/departures, source halo preserved, fixed roots, {FRAME_COUNT} unique poses, max full-frame alpha delta {max(frame_delta):.4f}; two verified TGA pages staged")


if __name__ == "__main__":
    build()
