"""Offline tests for the curated AlAdhan Hijri event calendar."""
import io
import json
import pathlib
import sys
import tempfile
import unittest
from unittest import mock
from urllib.parse import urlparse, parse_qs

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from workers import prayer_fetch


# Dates are transcribed from AlAdhan's published HJCoSA 1448/1449 calendar.
# Unwanted Urs / sacred-month-marker rows are included to prove the allowlist
# does not leak generic API holidays into the widget.
CALENDAR_DATES = {
    1448: {
        '01-01-1448': '16-06-2026',
        '10-01-1448': '25-06-2026',
        '12-03-1448': '25-08-2026',
        '27-07-1448': '05-01-2027',
        '15-08-1448': '23-01-2027',
        '01-09-1448': '08-02-2027',
        '01-10-1448': '09-03-2027',
        '08-12-1448': '14-05-2027',
        '09-12-1448': '15-05-2027',
        '10-12-1448': '16-05-2027',
        '22-06-1448': '02-12-2026',  # Urs: must never be selected
        '01-07-1448': '10-12-2026',  # Beginning of holy months: annotation only
    },
    1449: {
        '01-01-1449': '06-06-2027',
        '10-01-1449': '15-06-2027',
        '12-03-1449': '14-08-2027',
        '27-07-1449': '25-12-2027',
        '15-08-1449': '12-01-2028',
        '01-09-1449': '28-01-2028',
        '01-10-1449': '26-02-2028',
        '08-12-1449': '03-05-2028',
        '09-12-1449': '04-05-2028',
        '10-12-1449': '05-05-2028',
    },
}


def api_year_payload(year, dates=None):
    dates = dates or CALENDAR_DATES[year]
    rows = []
    for hijri_date, gregorian_date in dates.items():
        rows.append({
            'hijri': {
                'date': hijri_date,
                'method': 'HJCoSA',
                'holidays': ['Urs of an unrelated person'],
            },
            'gregorian': {'date': gregorian_date},
        })
    return {'code': 200, 'status': 'OK', 'data': rows}


def iso_calendar(year):
    return prayer_fetch.normalize_hijri_year_calendar(
        api_year_payload(year), year)


class HijriEventCalendarTests(unittest.TestCase):
    def setUp(self):
        self.calendars = {year: iso_calendar(year) for year in (1448, 1449)}

    def test_allowlist_contains_only_the_ten_approved_countdown_events(self):
        self.assertEqual(
            [rule[0] for rule in prayer_fetch.EVENT_RULES],
            [
                'islamic_new_year', 'ashura', 'mawlid_al_nabi',
                'isra_and_miraj', 'laylat_al_baraat', 'ramadan_begins',
                'eid_al_fitr', 'hajj_begins', 'day_of_arafah', 'eid_al_adha',
            ])
        self.assertEqual(len(prayer_fetch.EVENT_RULES), 10)

    def test_normalizes_annual_calendar_and_validates_year_and_method(self):
        normalized = iso_calendar(1448)
        self.assertEqual(normalized['01-01-1448'], '2026-06-16')
        self.assertEqual(normalized['10-12-1448'], '2027-05-16')
        payload = api_year_payload(1448)
        payload['data'][0]['hijri']['method'] = 'UAQ'
        with self.assertRaises(ValueError):
            prayer_fetch.normalize_hijri_year_calendar(payload, 1448)
        payload = api_year_payload(1448)
        payload['data'][0]['hijri']['date'] = '01-01-1447'
        with self.assertRaises(ValueError):
            prayer_fetch.normalize_hijri_year_calendar(payload, 1448)

    def test_next_event_skips_urs_and_beginning_of_holy_months(self):
        events = prayer_fetch.build_curated_events(self.calendars, 1448)
        next_event = prayer_fetch.select_next_curated_event(events, '2026-11-26')
        self.assertEqual(next_event['event_key'], 'isra_and_miraj')
        self.assertEqual(next_event['name'], 'Isra and Mi\'raj')
        self.assertEqual(next_event['hijri_date'], '27-07-1448')
        self.assertEqual(next_event['gregorian_date'], '2027-01-05')
        self.assertNotIn('Urs', next_event['name'])
        self.assertNotIn('holy months', next_event['name'])

    def test_fetch_next_curated_event_requests_current_and_following_year(self):
        with mock.patch.object(
                prayer_fetch, 'fetch_hijri_year_calendar',
                side_effect=[self.calendars[1448], self.calendars[1449]]) as fetch:
            event = prayer_fetch.fetch_next_curated_hijri_event(
                1448, '2026-11-26')
        self.assertEqual(event['event_key'], 'isra_and_miraj')
        self.assertEqual([call.args[0] for call in fetch.call_args_list],
                         [1448, 1449])

    def test_islamic_new_year_is_synthesized_even_when_api_row_names_an_urs(self):
        events = prayer_fetch.build_curated_events(self.calendars, 1448)
        new_year = next(e for e in events if e['event_key'] == 'islamic_new_year')
        self.assertEqual(new_year['name'], 'Islamic New Year')
        self.assertEqual(new_year['hijri_date'], '01-01-1448')
        self.assertEqual(new_year['gregorian_date'], '2026-06-16')
        self.assertEqual(
            prayer_fetch.select_next_curated_event(events, '2026-06-16'),
            new_year)

    def test_major_event_dates_and_canonical_labels(self):
        events = prayer_fetch.build_curated_events(self.calendars, 1448)
        by_key_year = {(e['event_key'], e['hijri_date'][-4:]): e for e in events}
        expected = {
            ('ashura', '1448'): ('Ashura', '10-01-1448', '2026-06-25'),
            ('mawlid_al_nabi', '1448'): ('Mawlid al-Nabi', '12-03-1448', '2026-08-25'),
            ('isra_and_miraj', '1448'): ('Isra and Mi\'raj', '27-07-1448', '2027-01-05'),
            ('laylat_al_baraat', '1448'): ('Laylat al-Bara\'at', '15-08-1448', '2027-01-23'),
            ('ramadan_begins', '1448'): ('Ramadan begins', '01-09-1448', '2027-02-08'),
            ('eid_al_fitr', '1448'): ('Eid al-Fitr', '01-10-1448', '2027-03-09'),
            ('hajj_begins', '1448'): ('Hajj begins', '08-12-1448', '2027-05-14'),
            ('day_of_arafah', '1448'): ('Day of Arafah', '09-12-1448', '2027-05-15'),
            ('eid_al_adha', '1448'): ('Eid al-Adha', '10-12-1448', '2027-05-16'),
        }
        for key, value in expected.items():
            event = by_key_year[key]
            self.assertEqual((event['name'], event['hijri_date'],
                              event['gregorian_date']), value)

    def test_hijri_year_rollover_selects_from_the_next_year(self):
        events = prayer_fetch.build_curated_events(self.calendars, 1448)
        next_event = prayer_fetch.select_next_curated_event(events, '2027-06-07')
        self.assertEqual(next_event['event_key'], 'ashura')
        self.assertEqual(next_event['hijri_date'], '10-01-1449')
        self.assertEqual(next_event['gregorian_date'], '2027-06-15')

    def test_missing_fixed_date_uses_h_to_g_fallback(self):
        calendars = {1448: dict(self.calendars[1448]),
                     1449: dict(self.calendars[1449])}
        calendars[1448].pop('27-07-1448')
        calls = []
        def fallback(hijri_date):
            calls.append(hijri_date)
            return '2027-01-05'
        events = prayer_fetch.build_curated_events(calendars, 1448, fallback)
        event = next(e for e in events if e['event_key'] == 'isra_and_miraj')
        self.assertEqual(event['gregorian_date'], '2027-01-05')
        self.assertEqual(calls, ['27-07-1448'])

    def test_h_to_g_response_validation(self):
        payload = {
            'code': 200,
            'data': {
                'hijri': {'date': '01-01-1448', 'method': 'HJCoSA'},
                'gregorian': {'date': '16-06-2026'},
            },
        }
        self.assertEqual(
            prayer_fetch.normalize_hijri_to_gregorian(payload, '01-01-1448'),
            '2026-06-16')
        payload['data']['hijri']['date'] = '02-01-1448'
        with self.assertRaises(ValueError):
            prayer_fetch.normalize_hijri_to_gregorian(payload, '01-01-1448')

    def test_fetch_h_to_g_uses_the_documented_date_conversion_endpoint(self):
        payload = {
            'code': 200,
            'data': {
                'hijri': {'date': '27-07-1448', 'method': 'HJCoSA'},
                'gregorian': {'date': '05-01-2027'},
            },
        }
        response = io.BytesIO(json.dumps(payload).encode('utf-8'))
        with mock.patch.object(prayer_fetch.urllib.request, 'urlopen',
                               return_value=response) as request:
            result = prayer_fetch.fetch_hijri_to_gregorian('27-07-1448')
        self.assertEqual(result, '2027-01-05')
        url = request.call_args.args[0].full_url
        parsed = urlparse(url)
        self.assertEqual(parsed.path, '/v1/hToG/27-07-1448')
        self.assertEqual(parse_qs(parsed.query)['calendarMethod'], ['HJCoSA'])

    def test_fetch_uses_annual_holiday_endpoint_and_hjcosa_method(self):
        response = io.BytesIO(json.dumps(api_year_payload(1448)).encode('utf-8'))
        with mock.patch.object(prayer_fetch.urllib.request, 'urlopen',
                               return_value=response) as request:
            result = prayer_fetch.fetch_hijri_year_calendar(1448)
        self.assertEqual(result['01-01-1448'], '2026-06-16')
        url = request.call_args.args[0].full_url
        parsed = urlparse(url)
        self.assertEqual(parsed.path,
                         '/v1/islamicHolidaysByHijriYear/1448')
        self.assertEqual(parse_qs(parsed.query)['calendarMethod'], ['HJCoSA'])

    def test_cache_schema_ttl_and_hijri_year_invalidation(self):
        events = prayer_fetch.build_curated_events(self.calendars, 1448)
        event = prayer_fetch.select_next_curated_event(events, '2026-11-26')
        content = prayer_fetch.event_cache_content(
            event, base_hijri_year=1448, fetched_at=1000)
        self.assertTrue(content.startswith('CONKY_HIJRI_EVENT_V2\n'))
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / prayer_fetch.EVENT_CACHE_NAME
            path.write_text(content, encoding='utf-8')
            self.assertTrue(prayer_fetch.event_cache_is_current(
                path, now=1000 + prayer_fetch.EVENT_CACHE_TTL, hijri_year=1448))
            self.assertFalse(prayer_fetch.event_cache_is_current(
                path, now=1001 + prayer_fetch.EVENT_CACHE_TTL, hijri_year=1448))
            self.assertFalse(prayer_fetch.event_cache_is_current(
                path, now=1001, hijri_year=1449))
            path.write_text(content.replace('CONKY_HIJRI_EVENT_V2',
                                             'CONKY_HIJRI_EVENT_V1', 1),
                            encoding='utf-8')
            self.assertFalse(prayer_fetch.event_cache_is_current(
                path, now=1000, hijri_year=1448))

    def test_worker_event_fetch_is_year_aware_and_force_refreshes(self):
        events = prayer_fetch.build_curated_events(self.calendars, 1448)
        event = prayer_fetch.select_next_curated_event(events, '2026-11-26')
        args = ['--event', '--hijri-year', '1448',
                '--displayed-date', '2026-11-26']
        with tempfile.TemporaryDirectory() as directory:
            cache_dir = pathlib.Path(directory)
            path = cache_dir / prayer_fetch.EVENT_CACHE_NAME
            with mock.patch.object(prayer_fetch, 'CACHE_DIR', cache_dir), \
                 mock.patch.object(prayer_fetch, 'fetch_next_curated_hijri_event',
                                   return_value=event) as fetch:
                self.assertEqual(prayer_fetch.main(args), 0)
                self.assertTrue(prayer_fetch.event_cache_is_current(
                    path, hijri_year=1448))
                fetch.assert_called_once_with(1448, '2026-11-26')
                self.assertEqual(prayer_fetch.main(args), 0)
                fetch.assert_called_once()
                updated = dict(event, name='Ashura', event_key='ashura',
                               hijri_date='10-01-1448',
                               gregorian_date='2026-06-25')
                fetch.return_value = updated
                self.assertEqual(prayer_fetch.main(
                    args + ['--event-force']), 0)
                self.assertIn('name=Ashura\n',
                              path.read_text(encoding='utf-8'))
                self.assertEqual(fetch.call_count, 2)

    def test_worker_argument_validation(self):
        with self.assertRaises(ValueError):
            prayer_fetch.parse_worker_args(['--event'])
        with self.assertRaises(ValueError):
            prayer_fetch.parse_worker_args(['--event-force'])
        parsed = prayer_fetch.parse_worker_args([
            '--event', '--hijri-year', '1448',
            '--displayed-date', '2026-11-26', '2026-11-27'])
        self.assertEqual(parsed[0], ['2026-11-27'])
        self.assertTrue(parsed[1])


if __name__ == '__main__':
    unittest.main()
