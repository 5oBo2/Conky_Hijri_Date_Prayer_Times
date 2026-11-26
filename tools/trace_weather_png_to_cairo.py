#!/usr/bin/env python3
"""Trace the ORIGINAL weather artwork into native Cairo filled vector paths.

This is an offline asset-authoring tool. It is NOT called by Conky.

The 20 original weather PNGs (256x256) are the source of truth; their alpha
silhouettes, including cloud overlap and precipitation, are converted to
sub-pixel polygons. Five transparency layers retain soft edge antialiasing.
The existing measured clear-sun / clear-moon transforms identify the celestial
strokes; no clouds are redrawn or reconstructed from generic shapes.

Requires: Pillow, numpy, opencv-python and scikit-image ONLY to regenerate.
Runtime dependencies: Cairo (already used by Conky) and the generated Lua.

Run from repository root:
  python3 tools/trace_weather_png_to_cairo.py
"""
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageFilter
from skimage.measure import find_contours

ROOT = Path(__file__).resolve().parents[1]
ORIGINALS = ROOT / 'assets/weather'
OUTPUT = ROOT / 'lib/Weather_Icon_Paths.lua'
IDS = (0, 5, 6, 9, 13, 14, 17, 20, 26, 29, 30, 31, 32, 33,
       34, 37, 41, 45, 46, 47)
# (standalone icon, scale, x offset, y offset) on the original 256px canvas.
CELESTIAL = {
    29: (31, 0.900, 52, 13),
    30: (32, 0.750, 49, 22),
    33: (31, 1.000, 15, 0),
    34: (32, 1.000, 0, 0),
    37: (32, 0.675, 57, 4),
    41: (32, 0.675, 57, 7),
    45: (31, 0.900, 57, -1),
    46: (31, 0.900, 62, -9),
    47: (31, 0.900, 51, -10),
}
# Five opacity bands reconstruct the original soft white outlines rather than
# thick procedural strokes with arbitrary clouds and sun/moon geometry.
THRESHOLDS = (.025, .12, .28, .52, .84)
EFFECTIVE = (.055, .19, .40, .69, 1.0)
OPACITIES = [EFFECTIVE[0]] + [
    (EFFECTIVE[i] - EFFECTIVE[i - 1]) / (1 - EFFECTIVE[i - 1])
    for i in range(1, len(EFFECTIVE))
]
SIMPLIFY_PX = .48

# The original cloud outlines form enclosed dark cavities below the sun/moon.
# Those cavities are reliable guides to the *cloud strokes* at intersections:
# otherwise the 7px-dilated celestial template mistakenly claims cloud ink.
# Counts refer to the fixed, user-supplied source pack, not generic clouds.
CLOUD_CAVITIES = {
    29: 1, 30: 2, 33: 1, 34: 1, 37: 2, 41: 2,
    45: 2, 46: 2, 47: 2,
}
# All nine compound icons have a foreground cloud that must remain white at
# celestial contact points. Six also contain a separate rear cloud.
FRONT_CLOUD_ICONS = frozenset((29, 30, 33, 34, 37, 41, 45, 46, 47))
REAR_CLOUD_ICONS = frozenset((30, 37, 41, 45, 46, 47))
# In 30/37/41, standalone sun rays are visibly drawn inside the rear cloud.
# Preserve those disconnected sun-ray strokes; only the *cloud boundary*
# outranks the central sun disk at its intersections. For 34 the bottom ray
# meets the foreground cloud seam and must not recolor that edge.
PRESERVE_SUN_RAYS = frozenset((30, 37, 41))
CLOUD_EDGE_OUTER_PX = 9
CLOUD_EDGE_INNER_PX = 2


def load_icon(icon_id):
    return Image.open(ORIGINALS / f'{icon_id}.png').convert('RGBA')


def sun_rays_on_compound(icon_id):
    """Raster guidance for the disconnected rays of the source 32.png sun."""
    template_id, scale, dx, dy = CELESTIAL[icon_id]
    if template_id != 32:
        return np.zeros((256, 256), dtype=bool)
    rgba = np.asarray(load_icon(32), dtype=np.float32)
    ink = rgba[:, :, 3] * rgba[:, :, 0] / (255 * 255)
    count, components, stats, _ = cv2.connectedComponentsWithStats(
        (ink > .25).astype(np.uint8))
    if count < 9:
        raise ValueError('Source 32.png sun rays changed: review the trace masks')
    disk_id = max(range(1, count), key=lambda i: stats[i, cv2.CC_STAT_AREA])
    rays = np.where((components != 0) & (components != disk_id), 255, 0)
    guidance = Image.fromarray(rays.astype('uint8')).transform(
        (256, 256), Image.Transform.AFFINE,
        (1 / scale, 0, -dx / scale, 0, 1 / scale, -dy / scale),
        resample=Image.Resampling.BILINEAR,
    )
    # Account for source antialiasing and subpixel registration.
    return cv2.dilate((np.asarray(guidance) > 40).astype('uint8'),
                      cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))) > 0


def cloud_seam_mask(icon_id, intensity):
    """Return the real cloud-outline band, not a cloud bounding rectangle.

    On this source pack the first enclosed interior above all others is the
    clear-sun/moon cavity; the following 1-2 enclosed interiors are clouds.
    The 5px close stabilizes the outline at the original antialiased seams.
    If that topology changes with a future PNG edit, fail regeneration rather
    than silently recolor a cloud as a sun or moon.
    """
    source_core = (intensity >= .25).astype('uint8') * 255
    sealed = cv2.morphologyEx(source_core, cv2.MORPH_CLOSE,
                             np.ones((5, 5), dtype=np.uint8))
    count, labels, stats, _ = cv2.connectedComponentsWithStats(255 - sealed)
    cavities = []
    for idx in range(1, count):
        x, y, w, h, area = map(int, stats[idx])
        if area > 200 and x > 0 and y > 0 and x + w < 256 and y + h < 256:
            cavities.append(idx)
    if len(cavities) != 1 + CLOUD_CAVITIES[icon_id]:
        raise ValueError(f'{icon_id}.png cloud cavity topology changed; '
                         'review the sun/moon split before regenerating')
    clouds = np.isin(labels, cavities[1:]).astype('uint8')
    def disk(radius):
        return cv2.getStructuringElement(
            cv2.MORPH_ELLIPSE, (radius * 2 + 1, radius * 2 + 1))
    outside = cv2.dilate(clouds, disk(CLOUD_EDGE_OUTER_PX)) > 0
    inside = cv2.erode(clouds, disk(CLOUD_EDGE_INNER_PX)) > 0
    seam = outside & ~inside
    if icon_id in PRESERVE_SUN_RAYS:
        seam &= ~sun_rays_on_compound(icon_id)
    return seam


def foreground_cloud_mask(icon_id, intensity):
    """Extract the source cloud outline that must be drawn in front.

    IDs 29/33/34 contain one cloud cavity, so that sole cloud is foreground.
    IDs 30/37/41/45/46/47 contain two cloud cavities; the lower-centroid cloud
    is the foreground cloud, while the other remains behind the celestial arc.
    In both cases only original cloud pixels are assigned to the final white
    pass; no cloud geometry is synthesized.
    """
    if icon_id not in FRONT_CLOUD_ICONS:
        return np.zeros((256, 256), dtype=np.float32)
    core = (intensity >= .25).astype('uint8') * 255
    sealed = cv2.morphologyEx(core, cv2.MORPH_CLOSE,
                              np.ones((5, 5), dtype=np.uint8))
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(255 - sealed)
    cavities = []
    for idx in range(1, count):
        x, y, w, h, area = map(int, stats[idx])
        if area > 200 and x > 0 and y > 0 and x + w < 256 and y + h < 256:
            cavities.append(idx)
    expected = 1 + CLOUD_CAVITIES[icon_id]
    if len(cavities) != expected:
        raise ValueError(f'{icon_id}.png cloud cavity topology changed; '
                         'review foreground layering before regenerating')
    cloud_cavities = cavities[1:]
    front_id = max(cloud_cavities, key=lambda idx: centroids[idx][1])
    cavity = (labels == front_id).astype('uint8')
    outer = cv2.dilate(cavity, cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (CLOUD_EDGE_OUTER_PX * 2 + 1,
                            CLOUD_EDGE_OUTER_PX * 2 + 1))) > 0
    inner = cv2.erode(cavity, cv2.getStructuringElement(
        cv2.MORPH_ELLIPSE, (CLOUD_EDGE_INNER_PX * 2 + 1,
                            CLOUD_EDGE_INNER_PX * 2 + 1))) > 0
    return (outer & ~inner).astype(np.float32) * intensity


def separate_intensity(icon_id):
    """Return back-white, celestial-gold and foreground-white ink layers."""
    image = load_icon(icon_id)
    if image.size != (256, 256):
        raise ValueError(f'{icon_id}: icon must be 256x256')
    rgba = np.asarray(image).astype(np.float32)
    intensity = (rgba[:, :, 3] / 255.0) * (rgba[:, :, 0] / 255.0)
    if icon_id in (31, 32):
        return np.zeros_like(intensity), intensity, np.zeros_like(intensity)
    if icon_id not in CELESTIAL:
        return intensity, np.zeros_like(intensity), np.zeros_like(intensity)

    template_id, scale, dx, dy = CELESTIAL[icon_id]
    ref = load_icon(template_id).getchannel('A')
    inv = 1 / scale
    guidance = ref.transform(
        (256, 256), Image.Transform.AFFINE,
        (inv, 0, -dx * inv, 0, inv, -dy * inv),
        resample=Image.Resampling.BILINEAR,
    )
    guide = guidance.point(lambda x: 255 if x > 60 else 0).filter(
        ImageFilter.MaxFilter(7))
    celestial_mask = np.asarray(guide) > 0
    celestial = intensity * celestial_mask

    # The celestial stroke is behind the foreground cloud. On the six
    # two-cloud icons it also passes over the separate rear cloud; on 29/33/34
    # the sole cloud is foreground. Split the foreground outline into its own
    # pass so white cloud ink cleanly occludes gold at every contact.
    foreground = foreground_cloud_mask(icon_id, intensity)
    celestial[foreground > 0] = 0
    neutral_back = np.maximum(0, intensity - foreground - celestial)
    return neutral_back, celestial, foreground


def contours(intensity, threshold):
    """Trace original pixel-level isocontours at subpixel accuracy."""
    padded = np.pad(np.asarray(intensity, dtype=np.float32), 1)
    rings = []
    for contour in find_contours(padded, threshold, fully_connected='high'):
        # skimage coordinates refer to pixel centers, while Cairo coordinates
        # refer to pixel edges. +0.5 aligns traced contours to original PNG.
        xy = np.asarray(contour[:, ::-1] - 0.5, dtype=np.float32)
        poly = cv2.approxPolyDP(xy.reshape(-1, 1, 2), SIMPLIFY_PX,
                               closed=True).reshape(-1, 2)
        if len(poly) >= 3:
            rings.append(poly)
    return rings


def fmt(v):
    return format(float(np.around(v, 1)), '.1f').rstrip('0').rstrip('.') if '.' in format(float(np.around(v, 1)), '.1f') else str(v)


def format_tier(loops):
    if not loops:
        return '{}'
    chunks = []
    for loop in loops:
        coords = [fmt(v) for pair in loop for v in pair]
        chunks.append('{' + ','.join(coords) + '}')
    return '{' + ','.join(chunks) + '}'


def generate():
    sections = [
        '-- AUTOGENERATED from assets/weather/*.png. DO NOT HAND EDIT.\n',
        '-- Rebuild with: python3 tools/trace_weather_png_to_cairo.py\n',
        '-- All original clouds, overlapping cloud silhouettes, rays, crescents\n',
        '-- and weather marks come from pixel-accurate source contours.\n',
        '-- Coordinates use the ORIGINAL 256x256 icon canvas.\n',
        'return {\n',
    ]
    for icon_id in IDS:
        neutral, celestial, foreground = separate_intensity(icon_id)
        sections.append(f'[{icon_id}]={{\n')
        for label, ink in (('n', neutral), ('c', celestial), ('f', foreground)):
            if not np.any(ink):
                continue
            sections.append(f'  {label}={{\n')
            for threshold in THRESHOLDS:
                rings = contours(ink, threshold)
                sections.append('    ' + format_tier(rings) + ',\n')
            sections.append('  },\n')
        sections.append('},\n')
    sections.append('}\n')
    OUTPUT.write_text(''.join(sections), encoding='utf8')
    print(f'Traced {len(IDS)} weather PNGs -> {OUTPUT} '
          f'({OUTPUT.stat().st_size:,} bytes)')


if __name__ == '__main__':
    generate()
