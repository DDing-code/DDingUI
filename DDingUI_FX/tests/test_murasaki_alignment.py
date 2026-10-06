"""Check round, stable spheres and an outgoing release in the delivered TGA.

python DDingUI_FX/tests/test_murasaki_alignment.py [optional staged TGA]
"""
from pathlib import Path
import sys
import cv2
import numpy as np
from PIL import Image
from scipy.ndimage import binary_fill_holes, gaussian_filter1d
from scipy.signal import find_peaks

ROOT = Path(__file__).resolve().parents[1]


def check(path=ROOT / 'Media/HollowPurple.tga'):
    centers, diameters, roundness, reach, energy, central = [], [], [], [], [], []
    approach_sizes, fusion_sizes, paired_roundness, circular_release, release_radius = [], [], [], [], []
    yy, xx = np.mgrid[:512, :512]
    radius = np.hypot(xx - 255.5, yy - 255.5)
    radius_bins = radius.astype(int).ravel()
    bin_pixels = np.maximum(1, np.bincount(radius_bins))
    sectors = ((np.arctan2(yy - 255.5, xx - 255.5) + np.pi) * 16 / (2 * np.pi)).astype(int).clip(0, 15)
    order = np.argsort(radius.ravel())
    with Image.open(path) as sheet:
        for index in range(48):
            x, y = index % 8 * 512, index // 8 * 512
            rgba = np.array(sheet.crop((x, y, x + 512, y + 512))).astype(float)
            emission = rgba[:, :, :3] * rgba[:, :, 3:4] / 255
            light = emission.max(axis=2)
            energy.append(float(light.sum()))
            assert energy[-1] > 0, ('empty frame', index)
            cumulative = np.cumsum(light.ravel()[order])
            reach.append(float(radius.ravel()[order[np.searchsorted(cumulative, cumulative[-1] * .9)]]))
            central.append(float(light[radius < 80].sum() / light.sum()))
            if index >= 40:
                profile = np.bincount(radius_bins, weights=light.ravel()) / bin_pixels
                profile = gaussian_filter1d(profile, 1)
                crests, _ = find_peaks(profile, distance=10, prominence=profile.max() * .12)
                assert len(crests) == 1, ('wave must be a single line', index, crests.tolist())
                angular_light = np.bincount(sectors[radius > 100], weights=light[radius > 100], minlength=16)
                circular_release.append(float(angular_light.min() / angular_light.max()))
                release_radius.append(float((radius * light).sum() / light.sum()))
            if not 2 <= index < 36:
                continue
            mask = (light > 24).astype('uint8')
            # Geometry uses the filled silhouette, not a moving bright center.
            mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9,9)))
            mask = binary_fill_holes(mask).astype('uint8')
            mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9,9)))
            count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask)
            parts = sorted(range(1, count), key=lambda k: stats[k, 4], reverse=True)
            assert parts and stats[parts[0], 4] > 400, ('missing orb body', index)
            if 6 <= index < 25:
                body_y, body_x = np.where(np.isin(labels, parts[:2]))
                size = (np.ptp(body_x) + 1, np.ptp(body_y) + 1)
                if index < 18:
                    approach_sizes.append(size)
                if index >= 11:
                    fusion_sizes.append(size)
            if index < 18 and len(parts) > 1 and stats[parts[1], 4] > stats[parts[0], 4] * .3:
                centers.append(np.mean(centroids[parts[:2]], axis=0))
            else:
                centers.append(centroids[parts[0]])
            if index < 18:
                # Fit each exposed outer arc; the overlap itself is not the
                # boundary of either red/blue circle.
                contours, _ = cv2.findContours(np.isin(labels, parts[:2]).astype('uint8'), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
                points = np.concatenate([contour[:, 0] for contour in contours]).astype(float)
                for side in (-1, 1):
                    arc = points[(points[:, 0] - 255.5) * side > 16]
                    fit = np.linalg.lstsq(np.c_[2 * arc, np.ones(len(arc))], (arc * arc).sum(axis=1), rcond=None)[0]
                    circle_radius = np.sqrt(fit[2] + np.sum(fit[:2] ** 2))
                    distances = np.linalg.norm(arc - fit[:2], axis=1)
                    paired_roundness.append(float(np.percentile(abs(distances - circle_radius), 95)))
            if index >= 20:
                contours, _ = cv2.findContours((labels == parts[0]).astype('uint8'), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
                center, axes, _ = cv2.fitEllipse(contours[0])
                diameters.append(float(np.mean(axes)))
                distances = np.linalg.norm(contours[0][:, 0] - center, axis=1)
                roundness.append(float(np.percentile(abs(distances - np.mean(axes) / 2), 95)))
                assert max(axes) / min(axes) < 1.025, ('oval sphere', index, axes)
    centers = np.array(centers)
    error = np.linalg.norm(centers - (255.5, 255.5), axis=1)
    step = np.linalg.norm(np.diff(centers, axis=0), axis=1)
    assert error.max() < 2, ('orb leaves anchor', float(error.max()))
    assert step.max() < 2, ('orb jumps between frames', float(step.max()))
    approach_sizes = np.array(approach_sizes)
    assert np.max(np.diff(approach_sizes[:, 0])) <= 1, ('circles separate again', approach_sizes.tolist())
    assert np.ptp(approach_sizes[:, 1]) < 2.5, ('approaching circles change size', approach_sizes.tolist())
    fusion_steps = np.diff(np.array(fusion_sizes), axis=0)
    assert np.max(abs(fusion_steps[:, 0])) <= 22, ('fusion snaps to one sphere', fusion_sizes)
    assert np.max(fusion_steps[:, 0]) <= 3, ('fusion reopens', fusion_sizes)
    assert np.max(abs(fusion_steps[:, 1])) <= 5, ('fusion body changes size abruptly', fusion_sizes)
    assert np.ptp(diameters) < 2.5, ('sphere breathes', diameters)
    assert max(roundness) < 2.5, ('irregular circular edge', roundness)
    assert max(paired_roundness) < 4, ('irregular red/blue circle', paired_roundness)
    assert max(reach[36:42]) > max(reach[20:36]) * 1.5, ('missing forward release', reach[36:42])
    assert min(reach[42:]) > max(reach[20:36]) * 1.5, ('afterimage shrinks back', reach[42:])
    assert max(central[42:]) < .01, ('central orb remains after release', central[42:])
    assert energy[-1] < max(energy) * .01
    assert min(circular_release) > .35, ('release has angular gaps or X-shaped jets', circular_release)
    assert min(np.diff(release_radius)) >= -1, ('circular release contracts', release_radius)
    print(f'PASS: center error {error.max():.2f}px; step {step.max():.2f}px; held diameter spread {np.ptp(diameters):.2f}px; circular edge error purple {max(roundness):.2f}px / red-blue {max(paired_roundness):.2f}px; exactly one wave per frame, 360-degree coverage {min(circular_release):.3f}, outward movement and empty center')


if __name__ == '__main__':
    check(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'Media/HollowPurple.tga')
