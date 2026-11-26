"""Offline source-fidelity and layer-order checks for native Cairo weather art.

Runtime Conky uses no Python, PNG reader or geometry packages. These tests
require optional authoring dependencies (Pillow/numpy/OpenCV/scikit-image/
pycairo) and skip on production machines without them.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

HAS_DEPS = all(importlib.util.find_spec(lib) is not None for lib in (
    'PIL', 'numpy', 'cv2', 'skimage', 'cairo'))
ROOT = Path(__file__).resolve().parents[1]
LAYERED_CONTACT_ICONS = frozenset((29, 30, 33, 34, 37, 41, 45, 46, 47))
REAR_CLOUD_ICONS = frozenset((30, 37, 41, 45, 46, 47))


@unittest.skipUnless(HAS_DEPS, 'optional vector authoring dependencies unavailable')
class WeatherVectorFidelityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import cairo
        import numpy as np
        from PIL import Image
        from tools import trace_weather_png_to_cairo as trace
        cls.cairo, cls.np, cls.Image, cls.trace = cairo, np, Image, trace

    def render_white(self, icon_id):
        """Reconstruct the source outline using the production n/c/f order."""
        crlib = self.cairo
        image = crlib.ImageSurface(crlib.FORMAT_ARGB32, 256, 256)
        ctx = crlib.Context(image)
        layers = self.trace.separate_intensity(icon_id)
        for ink in layers:
            for threshold, alpha in zip(self.trace.THRESHOLDS,
                                        self.trace.OPACITIES):
                rings = self.trace.contours(ink, threshold)
                ctx.new_path()
                ctx.set_fill_rule(crlib.FILL_RULE_EVEN_ODD)
                for ring in rings:
                    ctx.move_to(*map(float, ring[0]))
                    for x, y in ring[1:]:
                        ctx.line_to(float(x), float(y))
                    ctx.close_path()
                ctx.set_source_rgba(1, 1, 1, alpha)
                ctx.fill()
        return self.np.ndarray((256, 256, 4), dtype=self.np.uint8,
                               buffer=image.get_data()).copy()[:, :, 3]

    def source_ink(self, icon_id):
        rgba = self.np.asarray(self.trace.load_icon(icon_id), dtype='float32')
        return rgba[:, :, 3] * rgba[:, :, 0] / (255 * 255)

    def test_all_20_original_silhouettes_remain_within_pixel_tolerance(self):
        for icon_id in self.trace.IDS:
            with self.subTest(icon=icon_id):
                original = self.source_ink(icon_id) * 255
                rendered = self.render_white(icon_id)
                src_core, traced_core = original > 120, rendered > 120
                overlap = (src_core & traced_core).sum()
                union = (src_core | traced_core).sum()
                iou = overlap / max(union, 1)
                mae = self.np.abs(original-rendered).mean()
                self.assertGreaterEqual(iou, 0.94,
                    f'icon {icon_id} changed silhouette too much: IoU={iou:.3f}')
                self.assertLess(mae, 2.0,
                    f'icon {icon_id} changed brightness too much: MAE={mae:.2f}')

    def test_three_color_layers_recombine_to_original_source_ink(self):
        for icon_id in self.trace.IDS:
            with self.subTest(icon=icon_id):
                neutral, celestial, foreground = self.trace.separate_intensity(icon_id)
                source = self.source_ink(icon_id)
                combined = neutral + celestial + foreground
                self.assertLess(float(self.np.max(
                    self.np.abs(combined - source))), 0.00001)
                self.assertEqual(int(self.np.count_nonzero(
                    (celestial > 0) & (foreground > 0))), 0,
                    'foreground cloud must occlude, not overlap, celestial ink')
                if icon_id in (31, 32):
                    self.assertEqual(int(self.np.count_nonzero(neutral)), 0)
                    self.assertEqual(int(self.np.count_nonzero(foreground)), 0)
                elif icon_id not in self.trace.CELESTIAL:
                    self.assertEqual(int(self.np.count_nonzero(celestial)), 0)

    def test_front_cloud_layer_wins_at_all_nine_approved_contacts(self):
        """One-cloud icons occlude the celestial arc; two-cloud icons preserve both overlaps."""
        for icon_id in self.trace.IDS:
            with self.subTest(icon=icon_id):
                neutral, celestial, foreground = self.trace.separate_intensity(icon_id)
                has_front_layer = bool(self.np.count_nonzero(foreground))
                self.assertEqual(has_front_layer,
                                 icon_id in LAYERED_CONTACT_ICONS)
                if icon_id not in LAYERED_CONTACT_ICONS:
                    continue
                source = self.source_ink(icon_id)
                seam = self.trace.cloud_seam_mask(icon_id, source)
                self.assertGreater(int(self.np.count_nonzero(seam)), 100)
                if icon_id in REAR_CLOUD_ICONS:
                    self.assertGreater(int(self.np.count_nonzero(
                        (celestial > .25) & seam)), 100,
                        'celestial curve must remain visible over the rear cloud')
                else:
                    self.assertEqual(int(self.np.count_nonzero(
                        (celestial > .25) & seam)), 0,
                        'single foreground cloud must fully occlude celestial ink at contact')
                self.assertGreater(int(self.np.count_nonzero(
                    (foreground > .25) & seam)), 100,
                    'foreground cloud contour must remain white at contact')
                self.assertEqual(int(self.np.count_nonzero(
                    (celestial > 0) & (foreground > 0))), 0)
                self.np.testing.assert_allclose(
                    neutral + celestial + foreground, source, atol=0.00001)

    def test_disconnected_sun_rays_remain_colored_in_rear_clouds(self):
        """The sun rays in 30/37/41 stay gold even where they cross cloud fill."""
        for icon_id in self.trace.PRESERVE_SUN_RAYS:
            with self.subTest(icon=icon_id):
                _neutral, celestial, _foreground = self.trace.separate_intensity(icon_id)
                rays = self.trace.sun_rays_on_compound(icon_id)
                self.assertGreater(int(self.np.count_nonzero(
                    (celestial > .4) & rays)), 35)

    def test_generated_data_is_deterministic_and_contains_all_layers(self):
        original = (ROOT / 'lib/Weather_Icon_Paths.lua').read_bytes()
        with tempfile.TemporaryDirectory() as directory:
            previous = self.trace.OUTPUT
            try:
                self.trace.OUTPUT = Path(directory) / 'Weather_Icon_Paths.lua'
                self.trace.generate()
                self.assertEqual(original, self.trace.OUTPUT.read_bytes())
            finally:
                self.trace.OUTPUT = previous
        text = (ROOT / 'lib/Weather_Icons.lua').read_text()
        self.assertIn('fill_contours(cr, icon.n', text)
        self.assertIn('fill_contours(cr, icon.c', text)
        self.assertIn('fill_contours(cr, icon.f', text)
        self.assertNotIn('cairo_image_surface_create_from_png', text)
        self.assertNotIn('cairo_mask_surface', text)
        self.assertIn('Weather_Icon_Paths.lua', text)


if __name__ == '__main__':
    unittest.main()
