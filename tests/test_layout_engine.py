"""Offline checks for every widget/anchor in global X11/XWayland space."""
import configparser
import contextlib
import io
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import configure
from workers import layout


class LayoutEngineTests(unittest.TestCase):
    def setUp(self):
        self.first = {'name': 'HDMI-A-2', 'x': 0, 'y': 0,
                      'w': 1920, 'h': 1080}
        self.second = {'name': 'DP-2', 'x': 1920, 'y': 0,
                       'w': 1920, 'h': 1080}
        self.cp = configure.read()

    def test_shared_lua_window_sizes(self):
        for kind in layout.WIDGETS:
            self.assertEqual(layout.scaled_size(kind, 1),
                             layout.canvas_sizes()[kind])
            self.assertEqual(layout.scaled_size(kind, 2),
                             tuple(d*2 for d in layout.canvas_sizes()[kind]))
            filename = 'prayer_times' if kind == 'prayer' else kind
            conf = (ROOT / 'configs' / ('conky_' + filename + '.conf')).read_text()
            self.assertIn("geometry.dimension('%s', 'width', scale)" % kind, conf)
            self.assertIn("geometry.dimension('%s', 'height', scale)" % kind, conf)

    def test_all_nine_anchors_for_all_four_widgets(self):
        # Named output origins MUST be added to global X11 coordinates.
        for kind in layout.WIDGETS:
            w, h = layout.scaled_size(kind, 1)
            for anchor in layout.ANCHORS:
                x, y = layout.calculate_position(self.second, kind, 1,
                                                  anchor, 20, 15)
                expected_x = (20 if 'left' in anchor else
                              1920-w-20 if 'right' in anchor else (1920-w)//2) + self.second['x']
                expected_y = (15 if anchor.startswith('top') else
                              1080-h-15 if anchor.startswith('bottom') else (1080-h)//2) + self.second['y']
                self.assertEqual((x, y), (expected_x, expected_y), (kind, anchor))
                self.assertEqual(layout.intersection((x, y, w, h), self.second), w*h)

    def test_multi_output_wizard_uses_named_output_global_origin(self):
        # Output 2; keep scale; top-right; margin_x=20; margin_y=15.
        answers = iter(['2', '1', '3', '20', '15'])
        with patch.object(layout, 'monitors', return_value=([self.first, self.second], 'fixture')):
            with patch('builtins.input', side_effect=lambda *_: next(answers)):
                with contextlib.redirect_stdout(io.StringIO()):
                    layout.wizard(self.cp, 'date')
        self.assertEqual(self.cp.get('layout', 'date_output'), 'DP-2')
        self.assertEqual(self.cp.get('layout', 'date_anchor'), 'top-right')
        self.assertEqual(self.cp.getint('placement', 'date_x'), 1920 + 1200)
        self.assertEqual(self.cp.getint('placement', 'date_y'), 15)

    def test_conversion_of_prior_local_requests_via_saved_intent(self):
        # Simulate the wrong native Wayland placement from the previous release.
        for kind in layout.WIDGETS:
            layout._store_intent(self.cp, kind, self.second, 'top-left', 20, 15)
            self.cp['placement'][kind + '_x'] = '20'
            self.cp['placement'][kind + '_y'] = '15'
        with patch.object(layout, 'monitors', return_value=([self.first, self.second], 'fixture')):
            with contextlib.redirect_stdout(io.StringIO()):
                layout.reflow(self.cp)
        for kind in layout.WIDGETS:
            self.assertEqual(self.cp.getint('placement', kind + '_x'), 1940)
            self.assertEqual(self.cp.getint('placement', kind + '_y'), 15)

    def test_layout_with_vertical_or_negative_monitor_origins(self):
        mon = {'name': 'vertical', 'x': -1920, 'y': -1080, 'w': 1920, 'h': 1080}
        self.assertEqual(layout.calculate_position(mon, 'date', 1, 'top-left', 20, 30),
                         (-1900, -1050))
        self.assertEqual(layout.intersection((-1900, -1050, 700, 290), mon), 700*290)

    def test_reflow_after_monitor_resize_and_stale_geometry_check(self):
        layout._store_intent(self.cp, 'date', self.second, 'bottom-right', 20, 15)
        newer = {**self.second, 'w': 2560, 'h': 1440}
        with patch.object(layout, 'monitors', return_value=([self.first, newer], 'fixture')):
            with contextlib.redirect_stdout(io.StringIO()):
                layout.reflow(self.cp, 'date')
        self.assertEqual(self.cp.getint('placement', 'date_x'), 1920+2560-700-20)
        self.assertEqual(self.cp.getint('placement', 'date_y'), 1440-290-15)
        with patch.object(layout, 'monitors', return_value=([self.first, self.second], 'fixture')):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                layout.check_layout(self.cp, 'date')
        self.assertIn('stale', out.getvalue())
        self.assertIn('outside intended output', out.getvalue())

    def test_no_partial_reflow_if_intended_output_missing(self):
        layout._store_intent(self.cp, 'prayer', self.first, 'top-left', 20, 20)
        layout._store_intent(self.cp, 'date', self.second, 'top-right', 20, 20)
        original = dict(self.cp.items('placement'))
        with patch.object(layout, 'monitors', return_value=([self.first], 'fixture')):
            with self.assertRaisesRegex(ValueError, 'not found'):
                layout.reflow(self.cp, 'all')
        self.assertEqual(original, dict(self.cp.items('placement')))

    def test_preset_saves_intent_not_stale_runtime_offsets(self):
        layout._store_intent(self.cp, 'date', self.second, 'top-right', 22, 40)
        with tempfile.TemporaryDirectory() as tmp:
            with patch.object(layout, 'LAYOUT_DIR', Path(tmp)):
                path = layout.save_layout(self.cp, 'desk', 'date')
                saved = configparser.ConfigParser()
                saved.read(path)
                self.assertFalse(saved.has_section('placement'))
                self.assertEqual(saved['layout']['date_output'], 'DP-2')
                with patch.object(layout, 'monitors', return_value=([self.first, self.second], 'fixture')):
                    with contextlib.redirect_stdout(io.StringIO()):
                        layout.use_layout(self.cp, 'desk', 'date')
                self.assertEqual(self.cp.getint('placement', 'date_x'), 1920+1920-700-22)

    def test_new_layout_section_is_persisted_in_existing_settings(self):
        layout._store_intent(self.cp, 'date', self.second, 'top-right', 20, 15)
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / 'settings.ini'
            target.write_text((ROOT / 'settings.ini').read_text())
            with patch.object(configure, 'PATH', target):
                configure.save_preserving_comments(self.cp)
                saved = configparser.ConfigParser()
                saved.read(target)
                self.assertEqual(saved['layout']['date_output'], 'DP-2')
                self.assertEqual(saved['location']['city'], 'Cairo')
                self.assertIn('X11/XWayland virtual-desktop coordinates', target.read_text())
                self.assertNotIn('docs/WAYLAND_LAYOUT.md', target.read_text())


if __name__ == '__main__':
    unittest.main()
