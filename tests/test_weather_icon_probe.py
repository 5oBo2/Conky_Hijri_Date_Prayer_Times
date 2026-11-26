import importlib.util
from pathlib import Path
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    'weather_icon_probe', ROOT / 'tools' / 'weather_icon_probe.py')
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class WeatherIconProbeTests(unittest.TestCase):
    def test_prefers_primary_monitor_geometry(self):
        output = '''Screen 0: minimum 320 x 200, current 3200 x 1080, maximum 32767 x 32767
DP-1 connected 1280x1024+0+0 (normal)
HDMI-1 connected primary 1920x1080+1280+0 (normal)
'''
        with mock.patch.object(probe, '_run', return_value=output):
            self.assertEqual(probe.detect_screen(),
                             (1920, 1080, 1280, 0, 'primary XRandR monitor'))

    def test_falls_back_to_x_screen_bounds(self):
        output = '''Screen 0: minimum 320 x 200, current 2560 x 1440, maximum 32767 x 32767
DP-1 connected 2560x1440+0+0 (normal)
'''
        with mock.patch.object(probe, '_run', side_effect=[output]):
            self.assertEqual(probe.detect_screen(),
                             (2560, 1440, 0, 0, 'X screen bounds'))

    def test_falls_back_to_xdpyinfo(self):
        with mock.patch.object(probe, '_run', side_effect=[None,
                'screen #0:\n  dimensions: 1600x900 pixels (400x225 millimeters)']):
            self.assertEqual(probe.detect_screen(),
                             (1600, 900, 0, 0, 'X display bounds'))

    def test_config_and_all_source_images_exist(self):
        self.assertTrue(probe.CONFIG.is_file())
        for icon_id in (0,5,6,9,13,14,17,20,26,29,30,31,32,33,34,37,41,45,46,47):
            self.assertTrue((ROOT / 'assets' / 'weather' / f'{icon_id}.png').is_file())


if __name__ == '__main__':
    unittest.main()
