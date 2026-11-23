"""Offline regression tests for the prayer cache V2 schema and fetch worker."""
import io
import pathlib
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from workers import prayer_fetch

DATE = '2026-11-22'
SIGNATURE = 'test-location'
TIMES = {
    'Fajr': '05:00 (EET)', 'Sunrise': '06:30 (EET)',
    'Dhuhr': '12:00 (EET)', 'Asr': '15:00 (EET)',
    'Maghrib': '17:15 (EET)', 'Isha': '18:45 (EET)',
    'Midnight': '00:30 (EET)', 'Lastthird': '02:15 (EET)',
}


def payload():
    return {
        'code': 200, '_settings_signature': SIGNATURE,
        'data': {
            'timings': dict(TIMES),
            'date': {'hijri': {'day': '15', 'month': {'number': 6}, 'year': '1448'}},
        },
    }


class PrayerCacheTests(unittest.TestCase):
    def test_lastthird_required_in_api_response(self):
        value = payload()
        self.assertTrue(prayer_fetch.valid(value, SIGNATURE))
        del value['data']['timings']['Lastthird']
        self.assertFalse(prayer_fetch.valid(value, SIGNATURE))
        value['data']['timings']['Lastthird'] = 'not a time'
        self.assertFalse(prayer_fetch.valid(value, SIGNATURE))

    def test_v2_cache_and_v1_rejected(self):
        content = prayer_fetch.cache_content(DATE, payload(), SIGNATURE)
        self.assertTrue(content.startswith('CONKY_PRAYER_V2\n'))
        self.assertIn('Lastthird=02:15\n', content)
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / f'{DATE}.cache'
            path.write_text(content, encoding='utf-8')
            self.assertTrue(prayer_fetch.cache_is_current(path, SIGNATURE, DATE))
            path.write_text(content.replace('CONKY_PRAYER_V2', 'CONKY_PRAYER_V1', 1), encoding='utf-8')
            self.assertFalse(prayer_fetch.cache_is_current(path, SIGNATURE, DATE))
            path.write_text(content.replace('Lastthird=02:15\n', ''), encoding='utf-8')
            self.assertFalse(prayer_fetch.cache_is_current(path, SIGNATURE, DATE))

    def test_old_cache_is_refetched_then_reused(self):
        with tempfile.TemporaryDirectory() as directory:
            cache_dir = pathlib.Path(directory)
            path = cache_dir / f'{DATE}.cache'
            old = prayer_fetch.cache_content(DATE, payload(), SIGNATURE).replace(
                'CONKY_PRAYER_V2', 'CONKY_PRAYER_V1', 1)
            path.write_text(old, encoding='utf-8')
            fake_location = {'mode': 'coordinates'}
            with mock.patch.object(prayer_fetch, 'CACHE_DIR', cache_dir), \
                 mock.patch.object(prayer_fetch, 'get_location', return_value=(fake_location, SIGNATURE)), \
                 mock.patch.object(prayer_fetch, 'fetch', return_value=payload()) as fetch:
                self.assertEqual(prayer_fetch.main([DATE]), 0)
                fetch.assert_called_once_with(DATE, fake_location, SIGNATURE)
                self.assertTrue(prayer_fetch.cache_is_current(path, SIGNATURE, DATE))
                self.assertEqual(prayer_fetch.main([DATE]), 0)
                fetch.assert_called_once()  # V2 cache is reused; no duplicate request

    def test_aladhan_fetch_keeps_lastthird_not_computed(self):
        import json
        value = payload()
        value.pop('_settings_signature')
        response = io.BytesIO(json.dumps(value).encode('utf-8'))
        location = {
            'mode': 'coordinates', 'latitude': '30.0', 'longitude': '31.0',
            'method': 'auto', 'school': '0', 'midnight_mode': '1',
        }
        with mock.patch.object(prayer_fetch.urllib.request, 'urlopen', return_value=response) as request:
            result = prayer_fetch.fetch(DATE, location, SIGNATURE)
        self.assertEqual(result['data']['timings']['Lastthird'], '02:15 (EET)')
        url = request.call_args.args[0].full_url
        self.assertIn('/v1/timings/22-11-2026?', url)
        self.assertIn('midnightMode=1', url)


if __name__ == '__main__':
    unittest.main()
