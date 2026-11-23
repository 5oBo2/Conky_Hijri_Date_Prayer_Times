"""X11/XWayland runtime and placement checks without a live KDE session."""
import contextlib
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import sys

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
import doctor
from workers import layout


class NativeRuntimeTests(unittest.TestCase):
    def check_version(self, version, session='wayland', display=':0',
                      has_x11=True, has_xlib=True):
        with tempfile.TemporaryDirectory() as td:
            conky = Path(td) / 'conky'
            if has_xlib:
                (Path(td) / 'libcairo_xlib.so').touch()
            x_section = 'X11:\n  * Mouse events\n' if has_x11 else 'X11:\n'
            conky.write_text('#!/bin/sh\ncat <<EOF\nconky ' + version +
                             ' compiled for Linux\nLua bindings:\n  * Cairo\n' +
                             x_section + 'Wayland:\n  * Mouse events\n' +
                             'Package library path: ' + td + '\nEOF\n')
            conky.chmod(0o755)
            with patch.dict(os.environ, {'XDG_SESSION_TYPE': session,
                                          'WAYLAND_DISPLAY': 'wayland-0',
                                          'DISPLAY': display,
                                          'PATH': td + os.pathsep + os.environ['PATH']}):
                with contextlib.redirect_stdout(io.StringIO()):
                    return doctor.check_runtime()

    def test_supported_and_unsupported_conky(self):
        self.assertEqual(self.check_version('1.24.2'), 0)
        self.assertEqual(self.check_version('1.23.0-pre'), 0)
        self.assertNotEqual(self.check_version('1.22.2-pre'), 0)
        self.assertEqual(self.check_version('1.24.2', 'x11'), 0)
        self.assertNotEqual(self.check_version('1.24.2', display=''), 0)
        self.assertNotEqual(self.check_version('1.24.2', has_x11=False), 0)
        self.assertNotEqual(self.check_version('1.24.2', has_xlib=False), 0)

    def test_global_monitor_placement(self):
        monitor = {'name': 'HDMI-A-1', 'x': 1920, 'y': 1080,
                   'w': 2560, 'h': 1440}
        self.assertEqual(layout.calculate_position(monitor, 'weather', 1,
                                                   'top-left', 30, 40), (1950, 1120))
        self.assertEqual(layout.calculate_position(monitor, 'weather', 1,
                                                   'bottom-right', 10, 20),
                         (1920+2560-340-10, 1080+1440-172-20))
        self.assertEqual(layout.intersection((1930, 1090, 100, 100), monitor), 10000)
        self.assertEqual(layout.intersection((0, 100, 100, 100), monitor), 0)

if __name__ == '__main__':
    unittest.main()
