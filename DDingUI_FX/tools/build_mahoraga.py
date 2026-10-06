"""Bake the generated summoning components into staged WoW TGA pages.

python DDingUI_FX/tools/build_mahoraga.py
Uses the existing sprite placement helper and installed Pillow/NumPy/OpenCV/SciPy.
"""
from pathlib import Path
from hashlib import sha256
from math import sin, cos, pi, ceil
import json
import cv2
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt, binary_fill_holes
from build_holy_wings import place, smooth

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'artifacts/DDingUI_FX/mahoraga'
SOURCE = ART / 'Mahoraga-source-v1.png'
RIG_SOURCE = ART / 'Mahoraga-parts-v2.png'
JOINT_PAINT = ART / 'Mahoraga-joint-paint-v2.png'
SPARK = ROOT / 'artifacts/DDingUI_FX/holy-wings/GoldSpark-source.png'
PORTAL_SOURCE = ART / 'Mahoraga-portal-source-v3.png'
SHROUD_SOURCE = ART / 'Mahoraga-shroud-source-v3.png'
SHROUD_MATTE = ART / 'Mahoraga-shroud-matte-v3.png'
STAGING = ART / 'v3-build'
CELL, PAD, COLS, ROWS = 512, 32, 8, 8
FRAMES, FPS = 120, 24


def components():
    source = Image.open(SOURCE)
    assert source.mode == 'RGBA' and source.getchannel('A').getextrema() == (0, 255)
    data = np.array(source)
    _, labels, stats, centers = cv2.connectedComponentsWithStats((data[:, :, 3] > 12).astype('uint8'))
    main = sorted(range(1, len(stats)), key=lambda k: stats[k, 4], reverse=True)[:4]
    assert all(stats[k, 4] > 100000 for k in main)
    nearest = distance_transform_edt(~np.isin(labels, main), return_distances=False, return_indices=True)
    owners = labels[tuple(nearest)]
    parts = {}
    for k in main:
        x, y = centers[k]
        name = ('body' if x < source.width / 2 else 'wheel') if y < source.height / 2 else ('portal' if x < source.width / 2 else 'burst')
        rgba = data.copy()
        rgba[:, :, 3] = np.where((owners == k) & (data[:, :, 3] >= 3), data[:, :, 3], 0)
        part = Image.fromarray(rgba)
        if name == 'wheel':
            # Anchor to the hub, not the asymmetric outer glow, so rotation cannot wobble.
            part = part.crop((629, 12, 1269, 652))
        else:
            part = part.crop(part.getchannel('A').getbbox())
        parts[name] = part
        part.save(STAGING / f'{name}.png')
    assert set(parts) == {'body', 'wheel', 'portal', 'burst'}
    return parts


def character_parts():
    source = Image.open(RIG_SOURCE)
    assert source.mode == 'RGBA' and source.size == (1774, 887)
    data = np.array(source)
    # The generated joint correction is RGB: use only its interior paint patches.
    # The accepted RGBA source remains the alpha authority; never import a checkerboard.
    paint = np.array(Image.open(JOINT_PAINT).convert('RGB'))
    assert paint.shape == data[:, :, :3].shape
    mask = np.zeros(data.shape[:2], np.uint8)
    for x, y, rx, ry, angle in ((736, 46, 40, 16, 0), (551, 170, 24, 36, -20),
                              (862, 177, 24, 41, 0), (1675, 99, 29, 49, -30),
                              (1490, 339, 48, 38, 37), (323, 426, 35, 22, 30),
                              (602, 538, 32, 51, 25), (785, 755, 45, 55, 40),
                              (1021, 538, 58, 30, -30)):
        cv2.ellipse(mask, (x, y), (rx, ry), angle, 0, 360, 255, -1)
    blend = cv2.GaussianBlur(mask.astype(np.float32) / 255, (15, 15), 3)
    blend *= smooth((distance_transform_edt(data[:, :, 3] > 240) - 5) / 4)
    data[:, :, :3] = np.uint8(np.rint(data[:, :, :3] * (1 - blend[:, :, None]) + paint * blend[:, :, None]))
    _, labels, stats, centers = cv2.connectedComponentsWithStats((data[:, :, 3] > 12).astype('uint8'))
    main = sorted(range(1, len(stats)), key=lambda k: stats[k, 4], reverse=True)[:8]
    assert all(stats[k, 4] > 25000 for k in main)
    # Generated parts cross nominal grid lines; use their alpha islands, not equal-cell crops.
    main = sorted([k for k in main if centers[k, 1] < 430], key=lambda k: centers[k, 0]) + sorted(
        [k for k in main if centers[k, 1] >= 430], key=lambda k: centers[k, 0])
    nearest = distance_transform_edt(~np.isin(labels, main), return_distances=False, return_indices=True)
    owners = labels[tuple(nearest)]
    parts = {}
    for name, k in zip(('head', 'torso', 'legs', 'sword_upper', 'sword_lower', 'free_upper', 'free_lower', 'cloth'), main):
        rgba = data.copy()
        rgba[:, :, 3] = np.where((owners == k) & (data[:, :, 3] >= 3), data[:, :, 3], 0)
        part = Image.fromarray(rgba)
        box = part.getchannel('A').getbbox()
        part = part.crop(box)
        part.save(STAGING / f'rig-{name}.png')
        premult = np.array(part).astype(np.float32) / 255
        premult[:, :, :3] *= premult[:, :, 3:4]
        if name in ('sword_upper', 'free_upper'):
            # Feather just the overlapping elbow end so no hard cut line crosses the joint.
            y, x = np.mgrid[:part.height, :part.width]
            pivot, axis = ((1490, 308), (-.53, .85)) if name == 'sword_upper' else ((772, 717), (.54, .84))
            along = (x + box[0] - pivot[0]) * axis[0] + (y + box[1] - pivot[1]) * axis[1]
            premult *= (1 - smooth((along - 8) / 35))[:, :, None]
        origin = np.array(box[:2])
        if name == 'cloth':
            premult = np.pad(premult, ((96, 96), (96, 96), (0, 0)))
            origin -= 96
        parts[name] = (premult, origin)
    return parts


def character_pose(parts, t):
    """Articulated joints on the same painted parts; feet stay planted after emergence."""
    canvas = np.zeros((CELL * 2, CELL * 2, 4), np.float32)
    lift = smooth((t - .60) / 1.00)
    rise = (1 - lift) * 312
    opening = smooth((t - 1.90) / .62)
    settling = smooth((t - 2.55) / .70)
    phase = 2 * pi * (t - 2.1) / 2.7
    breath = sin(phase) * smooth((t - 1.8) / .5)

    def matrix(pivot, target, scale, angle):
        a = angle * pi / 180
        r = np.array([[cos(a), -sin(a)], [sin(a), cos(a)]]) * scale
        return np.column_stack((r, np.array(target) - r @ np.array(pivot)))

    def point(transform, xy):
        return transform[:, :2] @ np.array(xy) + transform[:, 2]

    def draw(name, pivot, target, scale, angle):
        part, origin = parts[name]
        if name == 'cloth':
            # A delayed bend travels down the painted ribbons, with a fixed waist attachment.
            y, x = np.mgrid[:part.shape[0], :part.shape[1]].astype(np.float32)
            u, v = x + origin[0] - pivot[0], y + origin[1] - pivot[1]
            radius = np.hypot(u, v)
            bend = 7 * pi / 180 * smooth((radius - 50) / 400) * np.sin(phase - radius / 260)
            tx = pivot[0] + u * np.cos(bend) + v * np.sin(bend) - origin[0]
            ty = pivot[1] - u * np.sin(bend) + v * np.cos(bend) - origin[1]
            part = cv2.remap(part, tx.astype(np.float32), ty.astype(np.float32), cv2.INTER_LINEAR)
        transform = matrix(pivot, target, scale, angle)
        m = transform.copy() * 2
        m[:, 2] += m[:, :2] @ origin
        h, w = part.shape[:2]
        corners = np.array([(0, 0), (w, 0), (0, h), (w, h)]) @ m[:, :2].T + m[:, 2]
        low = np.maximum(0, np.floor(corners.min(0) - 2).astype(int))
        high = np.minimum(CELL * 2, np.ceil(corners.max(0) + 2).astype(int))
        if np.all(high > low):
            m[:, 2] -= low
            painted = cv2.warpAffine(part, m, tuple(high - low), flags=cv2.INTER_LINEAR)
            region = canvas[low[1]:high[1], low[0]:high[0]]
            region[:] = painted + region * (1 - painted[:, :, 3:4])
        return transform

    waist = (258, 253 + rise)
    torso_angle = 6 - 9 * opening + 2 * settling + .8 * breath
    torso_target = (259, 255 + rise - 1.5 * breath)
    torso = matrix((735, 358), torso_target, .34, torso_angle)
    left_shoulder = point(torso, (582, 150))
    right_shoulder = point(torso, (850, 174))
    left_angle = torso_angle - 9 + 26 * opening - 7 * settling + 2 * sin(phase - .3)
    right_angle = torso_angle + 12 - 32 * opening + 8 * settling - 2 * sin(phase - .5)
    left_upper = matrix((1609, 140), left_shoulder, .25, left_angle)
    right_upper = matrix((656, 557), right_shoulder, .25, right_angle)
    left_elbow = point(left_upper, (1490, 319))
    right_elbow = point(right_upper, (778, 729))
    left_lower_angle = left_angle - 16 + 28 * opening - 8 * settling + 3 * sin(phase - .7)
    right_lower_angle = right_angle + 17 - 35 * opening + 9 * settling - 4 * sin(phase - .85)

    # Forearms sit underneath overlapping upper arms; shoulder caps tuck behind the torso.
    left_lower = draw('sword_lower', (298, 474), left_elbow, .29, left_lower_angle)
    right_lower = draw('free_lower', (1043, 577), right_elbow, .29, right_lower_angle)
    draw('sword_upper', (1609, 140), left_shoulder, .25, left_angle)
    draw('free_upper', (656, 557), right_shoulder, .25, right_angle)
    draw('torso', (735, 358), torso_target, .34, torso_angle)
    draw('legs', (1124, 62), waist, .415, 0)
    neck = point(torso, (735, 96))
    neck[1] += 7 * (1 - smooth((t - 2.00) / .44)) - 1.3 * breath
    head_angle = torso_angle + 12 - 17 * smooth((t - 2.00) / .44) + 3 * settling + 1.3 * sin(phase - .25)
    head = draw('head', (262, 338), neck, .29, head_angle)
    draw('cloth', (1348, 479), (274, 255 + rise), .30, -5 + 7 * sin(phase - .75))
    straight = np.zeros_like(canvas)
    straight[:, :, 3] = canvas[:, :, 3]
    np.divide(canvas[:, :, :3], canvas[:, :, 3:4], out=straight[:, :, :3], where=canvas[:, :, 3:4] > 0)
    image = Image.fromarray(np.uint8(np.clip(np.rint(straight * 255), 0, 255))).resize((CELL, CELL), Image.Resampling.LANCZOS)
    landmarks = np.array([point(head, (275, 278)), point(left_lower, (237, 658)),
                          point(right_lower, (1127, 811)), (158, 398 + rise), (360, 398 + rise)])
    return image, landmarks


def summon_sprites():
    portal_source = Image.open(PORTAL_SOURCE)
    assert portal_source.mode == 'RGBA' and portal_source.size == (1774, 887)
    portals = []
    for i in range(8):
        col, row = i % 4, i // 4
        box = (round(col * 443.5), round(row * 443.5), round((col + 1) * 443.5), round((row + 1) * 443.5))
        # A fixed projection and floor anchor preserve scale across the painted phases.
        portal = portal_source.crop(box).resize((418, 222), Image.Resampling.LANCZOS)
        portal.save(STAGING / f'portal-phase-{i}.png')
        portals.append(portal)
    assert len({p.getchannel('A').tobytes() for p in portals}) == 8
    alpha = [np.array(p.getchannel('A'), dtype=np.float32) for p in portals]
    steps = [float(np.abs(alpha[i] - alpha[(i + 1) % 8]).mean()) for i in range(8)]
    assert min(steps) > 1 and steps[-1] < max(steps[:-1]) * 2, 'Portal freeze or loop jump'

    # image_gen supplied this exact color sheet and a separate silhouette matte.
    # Keep genuine mouth cavities opaque, while the torn center remains transparent.
    colors = Image.open(SHROUD_SOURCE).convert('RGB')
    matte = Image.open(SHROUD_MATTE).convert('L')
    assert colors.size == matte.size == (1536, 1024)
    shrouds = []
    yy, xx = np.mgrid[:512, :512]
    for i in range(6):
        col, row = i % 3, i // 3
        box = (col * 512, row * 512, (col + 1) * 512, (row + 1) * 512)
        rgba = np.array(colors.crop(box).convert('RGBA'))
        mask = np.array(matte.crop(box)) > 128
        mouth = binary_fill_holes(mask) & (yy < 180) & (np.abs(xx - 260) < 95)
        mask |= mouth
        # The matte is generated art too: remove its narrow boundary uncertainty before packing.
        coverage = np.clip((distance_transform_edt(mask) - 2) / 1.5, 0, 1)
        rgba[:, :, 3] = np.uint8(np.rint(coverage * 255))
        rgba[coverage == 0, :3] = 0
        shroud = Image.fromarray(rgba)
        shroud.save(STAGING / f'shroud-phase-{i}.png')
        shrouds.append(shroud)
    assert all(np.array(s.getchannel('A'))[230:360, 205:305].mean() < 5 for s in shrouds[4:])
    assert all(np.array(s.getchannel('A'))[230:360, 205:305].mean() > 240 for s in shrouds[:3])
    return portals, shrouds


def wheel_sprite(wheel, phase, radius, t):
    """Assemble eight painted sectors, then sweep light over the spokes and rim."""
    sector = np.minimum(7, np.floor(phase * 8).astype(int))
    glow_distance = (phase - t * .62 + .5) % 1 - .5
    beam = np.exp(-(glow_distance / .085) ** 2)
    shock = np.exp(-((t - 1.77) / .11) ** 2) + .6 * np.exp(-((t - 2.22) / .12) ** 2)
    light = np.clip(.63 * beam + .65 * shock, 0, .9)
    rgba = wheel.copy()
    rgba[:, :, :3] = np.uint8(wheel[:, :, :3] * (1 - light[:, :, None]) + np.array([255, 247, 202]) * light[:, :, None])
    if t < 1.1:
        assembled = Image.new('RGBA', (640, 640))
        for k in range(8):
            amount = smooth((t - .20 - k * .060) / .22)
            part = rgba.copy()
            part[:, :, 3] = np.uint8(part[:, :, 3] * ((sector == k) & (radius > 57)) * amount)
            angle = (k + .5) * pi / 4
            shift = -72 * (1 - amount)
            m = np.float32([[1, 0, shift * cos(angle)], [0, 1, shift * sin(angle)]])
            part = cv2.warpAffine(part, m, (640, 640), flags=cv2.INTER_LINEAR)
            assembled = Image.alpha_composite(assembled, Image.fromarray(part))
        hub = rgba.copy()
        hub[:, :, 3] = np.uint8(hub[:, :, 3] * (radius <= 57) * smooth((t - .16) / .30))
        rgba = np.array(Image.alpha_composite(assembled, Image.fromarray(hub)))
    rgba[:, :, 3] = np.uint8(np.rint(rgba[:, :, 3] * (1 - smooth((t - 4.02 - .34 * phase) / .27))))
    return Image.fromarray(rgba)


def render():
    parts = components()
    portals, shrouds = summon_sprites()
    rig = character_parts()
    posed = [character_pose(rig, index / FPS) for index in range(FRAMES)]
    landmarks = np.stack([entry[1] for entry in posed])
    # Real relative motion, not a translating/bobbing cutout. Both feet are fixed after landing.
    assert np.ptp(landmarks[48:87, 3:], axis=0).max() < .001
    relative = landmarks[48:87, :3] - landmarks[48:87, 3:4]
    assert np.linalg.norm(np.ptp(relative, axis=0), axis=1).min() > 4
    assert np.linalg.norm(np.ptp(relative, axis=0), axis=1)[1:].min() > 20
    # Project the portal and ground shockwave onto a shallow floor plane.
    ground_burst = parts['burst'].resize((424, 126), Image.Resampling.LANCZOS)
    wheel = np.array(parts['wheel'])
    wy, wx = np.mgrid[:wheel.shape[0], :wheel.shape[1]]
    wheel_phase = (np.arctan2(wy - 320, wx - 320) + 2 * pi) % (2 * pi) / (2 * pi)
    wheel_radius = np.hypot(wx - 320, wy - 320)
    assert wheel_sprite(wheel, wheel_phase, wheel_radius, 1.20).tobytes() != wheel_sprite(wheel, wheel_phase, wheel_radius, 1.45).tobytes()
    spark = Image.open(SPARK).convert('RGBA')
    spark = spark.crop(spark.getchannel('A').point(lambda a: a if a >= 3 else 0).getbbox())
    spark = spark.resize((48, 64), Image.Resampling.LANCZOS)

    rng = np.random.default_rng(923)
    yy, xx = np.mgrid[:CELL, :CELL]
    grain = rng.random((CELL // 8, CELL // 8)).repeat(8, 0).repeat(8, 1)
    release = 3.90 + .48 * (1 - np.clip((yy - 114) / 300, 0, 1)) + .10 * grain
    departing = []
    pose_arrays = [np.array(entry[0]) for entry in posed]
    for x0, x1 in ((150, 193), (332, 372)):
        assert np.array_equal(pose_arrays[48][378:404, x0:x1], pose_arrays[85][378:404, x0:x1]), 'Rendered feet slid'
    for y in range(4, CELL, 12):
        for x in range(4, CELL, 12):
            # Sample the moving pose at this patch's release time, not the original standing pose.
            birth_frame = min(FRAMES - 1, round(release[y, x] * FPS))
            if pose_arrays[birth_frame][y, x, 3] > 180:
                departing.append((x, y, release[y, x], rng.uniform(.28, .40), rng.uniform(-12, 12)))
    assert len(departing) > 150
    frames, poses, intro_poses = [], [], []
    for index in range(FRAMES):
        t = index / FPS
        frame = Image.new('RGBA', (CELL, CELL))
        opening = smooth(t / .72)
        closing = 1 - smooth((t - 4.30) / .65)
        portal_size = 418 * (.28 + .72 * opening) * (.35 + .65 * closing)
        portal = portals[(index // 2) % 8]
        portal_center = (256, 403 - 40 * portal_size / 418)
        place(frame, portal, portal_center, portal_size, 0, opening * closing)
        # A moving second rim adds depth without moving the floor anchor.
        place(frame, ground_burst, (256, 403), 330 + 50 * sin(t * 2.2) ** 2, 0,
              opening * closing * (.12 + .04 * sin(t * 3)))

        # Orbiting light rises from the ink pool; the same paths continue behind and in front.
        ambient = []
        for k in range(88):
            born, life = .03 + k * .038, 1.32 + (k % 3) * .12
            u = (t - born) / life
            if not 0 < u < 1:
                continue
            angle = k * 2.399963 + u * 3.6
            radius = 170 * (1 - u) + 38
            x = 256 + cos(angle) * radius
            y = 402 - 245 * u + sin(angle) * 16
            strength = smooth(u / .14) * (1 - smooth((u - .70) / .30))
            ambient.append((k, x, y, strength))
            if k % 3 != 0:
                place(frame, spark, (x, y), 12 + (k % 4) * 4, 0, strength)
                if k % 2 == 0:
                    for lag in (.025, .05):
                        v = max(0, u - lag)
                        a = k * 2.399963 + v * 3.6
                        r = 170 * (1 - v) + 38
                        place(frame, spark, (256 + cos(a) * r, 402 - 245 * v + sin(a) * 16),
                              10, 0, strength * .45)

        wheel_x = 256
        wheel_y = 237 - 127 * smooth((t - .28) / .95)
        angle = -24 * t - 45 * smooth((t - 1.58) / .16) - 45 * smooth((t - 2.13) / .18) - 45 * smooth((t - 3.0) / .22)
        wheel_size = 140 * (.60 + .40 * smooth((t - .28) / .78))
        place(frame, wheel_sprite(wheel, wheel_phase, wheel_radius, t), (wheel_x, wheel_y), wheel_size, angle, 1)
        for k in range(8):
            theta = k * pi / 4 - angle * pi / 180
            pulse = smooth((t - .28 - k * .0675) / .2) * (1 - smooth((t - 4.02 - k * .0425) / .27))
            pulse *= .3 + .7 * (.5 + .5 * sin(t * 9 - k * pi / 4)) ** 4
            place(frame, spark, (wheel_x + cos(theta) * wheel_size * .40,
                                wheel_y + sin(theta) * wheel_size * .40), 10, 0, pulse * .7)

        # Arrival: a large painted burst and two expanding floor waves, behind the body.
        lingering = smooth((t - 2.10) / .30) * (1 - smooth((t - 3.30) / .60))
        place(frame, parts['burst'], (256, 258), 355, t * 18, lingering * (.19 + .05 * sin(t * 2.7)))
        for start, life, peak in [(1.58, .95, 1.0), (2.12, .70, .65)]:
            u = (t - start) / life
            if 0 < u < 1:
                pulse = smooth(u / .12) * (1 - smooth((u - .42) / .58))
                size = 145 + 237 * smooth(u / .60)
                place(frame, parts['burst'], (256, 258), size, u * 27, pulse * peak)
                place(frame, ground_burst, (256, 404), 120 + 304 * smooth(u), 0, pulse * .80)

        character = pose_arrays[index].copy()
        character[:, :, 3] = np.uint8(np.rint(character[:, :, 3] * (1 - smooth((t - release) / .20))))
        character[:, :, :3] = np.uint8(character[:, :, :3] * (.32 + .68 * smooth((t - 1.00) / .64)))
        floor_mask = 1 - smooth((np.arange(CELL)[:, None] - 408) / 10)
        # Reveal the body before the wrapping opens, so its torn center never goes empty.
        reveal = smooth((t - 1.86) / .12)
        head_reveal = np.where(yy < 177, smooth((t - 2.03) / .14), 1)
        character[:, :, 3] = np.uint8(np.rint(character[:, :, 3] * floor_mask * reveal * head_reveal))
        body_layer = Image.fromarray(character)
        frame = Image.alpha_composite(frame, body_layer)
        poses.append(body_layer)

        # Painted wrapping poses: bow, mouth opening, roar, tearing, then flying strips.
        intro = Image.new('RGBA', (CELL, CELL))
        if .55 < t < 2.74:
            thresholds = (.55, 1.38, 1.58, 1.91, 2.15, 2.37)
            stage = min(5, sum(t >= start for start in thresholds) - 1)
            rise = 292 * (1 - smooth((t - .55) / .95))
            sway = 2.5 * sin(t * 3.3) * (1 - smooth((t - 1.58) / .35))
            opacity = smooth((t - .55) / .16) * (1 - smooth((t - 2.38) / .35))
            place(intro, shrouds[stage], (256, 414 - 234 * 350 / 512 + rise), 350, sway, opacity)
            cover = np.array(intro)
            cover[:, :, 3] = np.uint8(np.rint(cover[:, :, 3] * floor_mask))
            intro = Image.fromarray(cover)
            frame = Image.alpha_composite(frame, intro)
        intro_poses.append(intro)

        # Small fragments travel upward as their matching source patches dissolve.
        for k, (x, y, born, life, drift) in enumerate(departing):
            u = (t - born) / life
            if not 0 < u < 1:
                continue
            sx = x + (x - 256) * .10 * u + drift * sin(pi * u)
            sy = y - 48 * u
            strength = smooth(u / .16) * (1 - smooth((u - .55) / .45))
            place(frame, spark, (sx, sy), 6 + k % 3 * 2, k % 45, strength * .90)
        for k, x, y, strength in ambient:
            if k % 3 == 0:
                place(frame, spark, (x, y), 12 + k % 4 * 4, 0, strength * .85)
        # Composite the matching front half of this painted phase at the same floor anchor.
        front = np.array(portal)
        front[:, :, 3] = np.uint8(np.rint(front[:, :, 3] * smooth((np.arange(222)[:, None] - 151) / 12)))
        place(frame, Image.fromarray(front), portal_center, portal_size, 0, opening * closing)
        frames.append(frame)
        if index % FPS == FPS - 1:
            print(f'Rendered {index + 1}/{FRAMES}', flush=True)

    assert frames[0].getchannel('A').getbbox() is None
    assert frames[-1].getchannel('A').getbbox() is None
    assert len({frame.tobytes() for frame in frames}) >= FRAMES - 1
    assert intro_poses[24].getchannel('A').getbbox() != intro_poses[42].getchannel('A').getbbox()
    assert poses[42].getchannel('A').getbbox() is None and poses[60].getchannel('A').getbbox() is not None
    assert intro_poses[42].getchannel('A').getbbox() is not None and intro_poses[66].getchannel('A').getbbox() is None
    assert np.array(poses[47])[240:290, 228:282, 3].mean() > 200, 'Body appeared after its shroud opened'
    assert poses[114].getchannel('A').getbbox() is None
    for i, frame in enumerate(frames):
        bounds = frame.getchannel('A').getbbox()
        if bounds:
            assert min(bounds[:2]) >= PAD and max(bounds[2:]) <= CELL - PAD, (i, bounds)
    body_previews = []
    for pose in poses:
        bg = Image.new('RGBA', (CELL, CELL), (20, 22, 29, 255))
        body_previews.append(Image.alpha_composite(bg, pose).convert('RGB'))
    times = [round((i + 1) * 1000 / FPS) - round(i * 1000 / FPS) for i in range(FRAMES)]
    body_previews[0].save(STAGING / 'body-motion.webp', save_all=True, append_images=body_previews[1:],
                          lossless=True, duration=times, loop=0)
    (STAGING / 'motion-check.json').write_text(json.dumps(dict(
        head_hand_travel_px=np.linalg.norm(np.ptp(relative, axis=0), axis=1).tolist(),
        feet_travel_px=float(np.ptp(landmarks[48:87, 3:], axis=0).max())), indent=2), encoding='utf-8')
    return frames, len(departing)


def build():
    STAGING.mkdir(parents=True, exist_ok=True)
    frames, fragments = render()
    capacity = COLS * ROWS
    paths, previews, alpha_sums = [], [], []
    for page in range(ceil(FRAMES / capacity)):
        name = 'Mahoraga.tga' if page == 0 else f'Mahoraga_{page + 1}.tga'
        path = STAGING / name
        atlas = Image.new('RGBA', (COLS * CELL, ROWS * CELL))
        for i, frame in enumerate(frames[page * capacity:(page + 1) * capacity]):
            atlas.paste(frame, (i % COLS * CELL, i // COLS * CELL))
        atlas.save(path, compression=None)
        atlas.save(path.with_suffix('.png'))
        paths.append(path)
        with Image.open(path) as decoded:
            assert decoded.mode == 'RGBA' and decoded.size == (4096, 4096)
            for i in range(min(capacity, FRAMES - page * capacity)):
                x, y = i % COLS * CELL, i // COLS * CELL
                cell = decoded.crop((x, y, x + CELL, y + CELL))
                assert cell.tobytes() == frames[page * capacity + i].tobytes()
                alpha_sums.append(float(np.array(cell)[:, :, 3].mean() / 255))
                bg = Image.new('RGBA', (CELL, CELL), (20, 22, 29, 255))
                previews.append(Image.alpha_composite(bg, cell).convert('RGB'))
            if page == 1:
                assert decoded.crop((0, 7 * CELL, 4096, 4096)).getchannel('A').getbbox() is None
        header = path.read_bytes()[:18]
        assert header[2] == 2 and header[16] == 32 and header[17] & 15 == 8
    assert all(x > 0 for x in alpha_sums[1:-2]), 'Unexpected blank frame inside animation'
    assert abs(alpha_sums[64] - alpha_sums[63]) < .01, 'Page boundary flash'
    duration = FRAMES * 1000 / FPS
    times = [round((i + 1) * 1000 / FPS) - round(i * 1000 / FPS) for i in range(FRAMES)]
    webp = ART / 'Mahoraga-preview-v3.webp'
    previews[0].save(webp, save_all=True, append_images=previews[1:], lossless=True,
                     quality=100, method=4, duration=times, loop=0)
    samples = Image.new('RGB', (CELL * 4, CELL * 3))
    for i, index in enumerate(range(0, FRAMES, 10)):
        samples.paste(previews[index], (i % 4 * CELL, i // 4 * CELL))
    palette = samples.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    gif_frames = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in previews]
    gif_times = [round((i + 1) * 100 / FPS) * 10 - round(i * 100 / FPS) * 10 for i in range(FRAMES)]
    gif_frames[0].save(ART / 'Mahoraga-preview-v3.gif', save_all=True, append_images=gif_frames[1:],
                       duration=gif_times, disposal=2, loop=0, optimize=False)
    with Image.open(webp) as decoded:
        assert decoded.n_frames == FRAMES
        total = 0
        for i in range(decoded.n_frames):
            decoded.seek(i); decoded.load()
            total += decoded.info['duration']
        assert total == duration
    contact = Image.new('RGB', (256 * 6, 256 * 4))
    for i, index in enumerate(range(0, FRAMES, 5)):
        contact.paste(previews[index].resize((256, 256), Image.Resampling.LANCZOS), (i % 6 * 256, i // 6 * 256))
    contact.save(ART / 'delivered-frames-v3.png')
    previews[48].save(ART / 'Mahoraga-frame-v3.png')
    manifest = dict(source_sha256=sha256(SOURCE.read_bytes()).hexdigest(),
                    rig_source_sha256=sha256(RIG_SOURCE.read_bytes()).hexdigest(),
                    joint_paint_sha256=sha256(JOINT_PAINT.read_bytes()).hexdigest(),
                    spark_sha256=sha256(SPARK.read_bytes()).hexdigest(),
                    portal_source_sha256=sha256(PORTAL_SOURCE.read_bytes()).hexdigest(),
                    shroud_source_sha256=sha256(SHROUD_SOURCE.read_bytes()).hexdigest(),
                    shroud_matte_sha256=sha256(SHROUD_MATTE.read_bytes()).hexdigest(),
                    portal_phases=8, shroud_phases=6,
                    frames=FRAMES, fps=FPS, duration_seconds=duration / 1000, cell=CELL,
                    columns=COLS, rows=ROWS, pages=len(paths), particle_fragments=fragments,
                    page_boundary_alpha_delta=abs(alpha_sums[64] - alpha_sums[63]),
                    sheets={p.name: sha256(p.read_bytes()).hexdigest() for p in paths},
                    status='staged; inspect before installing; WoW render untested')
    (STAGING / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(f'PASS: {FRAMES} frames / {FPS} FPS / 5 sec; RGBA, gutters, exact TGA decoding and page continuity; {fragments} dissolving light anchors')


if __name__ == '__main__':
    build()
