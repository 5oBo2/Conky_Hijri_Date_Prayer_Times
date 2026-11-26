#!/usr/bin/env python3
"""Fetch and atomically cache Aladhan schedules without blocking Conky.

Usage:
  python3 workers/prayer_fetch.py YYYY-MM-DD [YYYY-MM-DD ...]
  python3 workers/prayer_fetch.py [YYYY-MM-DD ...] --event --hijri-year YEAR --displayed-date YYYY-MM-DD [--event-force]

The prayer and curated Hijri-event caches are shared by all Conky processes.
All network requests run in this background worker, never in the draw loop.
"""
import datetime as dt
import configparser
import fcntl
import json
import re
import os
import pathlib
import sys
import tempfile
import time
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG_FILE = ROOT / 'settings.ini'
LOCATION_KEYS = ('mode', 'city', 'country', 'state', 'latitude',
                 'longitude', 'method', 'school', 'midnight_mode')


def get_location():
    config = configparser.ConfigParser(interpolation=None,
                                       inline_comment_prefixes=('#', ';'))
    if not config.read(CONFIG_FILE, encoding='utf-8'):
        raise ValueError(f'Cannot read {CONFIG_FILE}')
    if not config.has_section('location'):
        raise ValueError('Missing [location] section in settings.ini')
    values = {key: config.get('location', key, fallback='').strip()
              for key in LOCATION_KEYS}
    if values['mode'] not in ('coordinates', 'city'):
        raise ValueError('Location mode must be coordinates or city')
    if values['mode'] == 'coordinates':
        lat, lon = float(values['latitude']), float(values['longitude'])
        if not -90 <= lat <= 90 or not -180 <= lon <= 180:
            raise ValueError('Latitude/longitude out of range')
    elif not values['city'] or not values['country']:
        raise ValueError('City and country are required in city mode')
    for key, allowed in [('school', (0, 1)), ('midnight_mode', (0, 1))]:
        if values[key] and int(values[key]) not in allowed:
            raise ValueError(f'Invalid {key}')
    if values['method'] and values['method'] != 'auto' and int(values['method']) < 0:
        raise ValueError('Invalid method')
    signature = '|'.join(values[key] for key in LOCATION_KEYS)
    return values, signature
CACHE_HOME = pathlib.Path(os.environ.get('XDG_CACHE_HOME') or
                          str(pathlib.Path.home() / '.cache'))
CACHE_DIR = CACHE_HOME / 'conky-prayer-times'
REQUIRED_TIMES = ('Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha', 'Midnight', 'Lastthird')
EVENT_CACHE_NAME = 'next-hijri-holiday.cache'
EVENT_CACHE_TTL = 12 * 60 * 60
EVENT_CALENDAR_METHOD = 'HJCoSA'


def valid(payload, signature):
    try:
        if payload.get('_settings_signature') != signature:
            return False
        data = payload['data']
        times = data['timings']
        hijri = data['date']['hijri']
        return (all(parse_time(times[name]) is not None for name in REQUIRED_TIMES)
                and 1 <= int(hijri['day']) <= 30
                and 1 <= int(hijri['month']['number']) <= 12
                and int(hijri['year']) > 0)
    except (KeyError, TypeError, ValueError, AttributeError):
        return False


def parse_time(value):
    if not isinstance(value, str):
        return None
    match = re.match(r'^\s*(\d{1,2}):(\d{2})(?:\s|$)', value)
    if not match:
        return None
    hour, minute = int(match.group(1)), int(match.group(2))
    return f'{hour:02d}:{minute:02d}' if hour <= 23 and minute <= 59 else None


def cache_content(date, payload, signature):
    if not valid(payload, signature):
        raise ValueError(f'Invalid prayer data for {date}')
    data = payload['data']
    times = data['timings']
    hijri = data['date']['hijri']
    fields = [('signature', signature), ('date', date)]
    fields.extend((name, parse_time(times[name])) for name in REQUIRED_TIMES)
    fields.extend((('hijri_day', str(int(hijri['day']))),
                   ('hijri_month', str(int(hijri['month']['number']))),
                   ('hijri_year', str(int(hijri['year'])))))
    if any('\n' in value or '\r' in value for _, value in fields):
        raise ValueError('Newline in location settings')
    return 'CONKY_PRAYER_V2\n' + ''.join(f'{k}={v}\n' for k, v in fields)


def cache_is_current(path, signature, date):
    try:
        text = path.read_text(encoding='utf-8')
        lines = text.splitlines()
        entries = dict(line.split('=', 1) for line in lines[1:])
        if lines[0] != 'CONKY_PRAYER_V2' or len(entries) != len(lines) - 1:
            return False
        if entries.get('signature') != signature or entries.get('date') != date:
            return False
        if any(parse_time(entries.get(name)) is None for name in REQUIRED_TIMES):
            return False
        return (1 <= int(entries['hijri_day']) <= 30
                and 1 <= int(entries['hijri_month']) <= 12
                and int(entries['hijri_year']) > 0)
    except (OSError, UnicodeError, IndexError, KeyError, TypeError, ValueError):
        return False

def parse_api_date(value):
    """Convert AlAdhan's DD-MM-YYYY calendar date to ISO YYYY-MM-DD."""
    if not isinstance(value, str):
        return None
    match = re.fullmatch(r'(\d{2})-(\d{2})-(\d{4})', value)
    if not match:
        return None
    day, month, year = map(int, match.groups())
    try:
        return dt.date(year, month, day).isoformat()
    except ValueError:
        return None


# Curated events shown by the Hijri hover. These are deliberately keyed by
# Hijri month/day, not by every label AlAdhan happens to publish. The annual
# calendar supplies Gregorian conversions; this allowlist controls visibility.
# Additions must also be documented in docs/HIJRI_EVENTS.md and covered by tests.
EVENT_RULES = (
    ('islamic_new_year', 'Islamic New Year', 1, 1),
    ('ashura', 'Ashura', 10, 1),
    ('mawlid_al_nabi', 'Mawlid al-Nabi', 12, 3),
    ('isra_and_miraj', 'Isra and Mi\'raj', 27, 7),
    ('laylat_al_baraat', 'Laylat al-Bara\'at', 15, 8),
    ('ramadan_begins', 'Ramadan begins', 1, 9),
    ('eid_al_fitr', 'Eid al-Fitr', 1, 10),
    ('hajj_begins', 'Hajj begins', 8, 12),
    ('day_of_arafah', 'Day of Arafah', 9, 12),
    ('eid_al_adha', 'Eid al-Adha', 10, 12),
)
EVENT_RULES_BY_KEY = {rule[0]: rule for rule in EVENT_RULES}


def valid_event(event):
    if not isinstance(event, dict):
        return False
    try:
        gregorian_date = dt.date.fromisoformat(event.get('gregorian_date', ''))
    except (TypeError, ValueError):
        return False
    hijri_date = event.get('hijri_date')
    match = re.fullmatch(r'(\d{2})-(\d{2})-(\d{4})', hijri_date or '')
    rule = EVENT_RULES_BY_KEY.get(event.get('event_key'))
    if not match or not rule:
        return False
    day, month, _year = map(int, match.groups())
    return (
        (day, month) == (rule[2], rule[3])
        and gregorian_date.isoformat() == event.get('gregorian_date')
        and isinstance(event.get('name'), str)
        and event['name'] == rule[1]
        and event.get('calendar_method') == EVENT_CALENDAR_METHOD
    )


def normalize_hijri_year_calendar(payload, year):
    """Return Hijri-date -> Gregorian-date mappings from AlAdhan's year list."""
    if not isinstance(payload, dict) or payload.get('code') != 200:
        raise ValueError(f'Invalid AlAdhan Hijri calendar response for {year}')
    rows = payload.get('data')
    if not isinstance(rows, list) or not rows:
        raise ValueError(f'Missing AlAdhan Hijri calendar rows for {year}')
    calendar = {}
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError('Invalid Hijri calendar row')
        hijri, gregorian = row.get('hijri'), row.get('gregorian')
        if not isinstance(hijri, dict) or not isinstance(gregorian, dict):
            raise ValueError('Missing Hijri/Gregorian date in calendar row')
        hijri_date = hijri.get('date')
        gregorian_date = gregorian.get('date')
        if not parse_api_date(hijri_date) or not parse_api_date(gregorian_date):
            raise ValueError('Invalid date in Hijri calendar row')
        parts = re.fullmatch(r'(\d{2})-(\d{2})-(\d{4})', hijri_date)
        if not parts or int(parts.group(3)) != int(year):
            raise ValueError(f'Hijri calendar row is outside year {year}')
        method = hijri.get('method') or EVENT_CALENDAR_METHOD
        if method != EVENT_CALENDAR_METHOD:
            raise ValueError(f'Unexpected Hijri calendar method: {method}')
        iso_gregorian = parse_api_date(gregorian_date)
        previous = calendar.get(hijri_date)
        if previous is not None and previous != iso_gregorian:
            raise ValueError(f'Conflicting Gregorian dates for {hijri_date}')
        calendar[hijri_date] = iso_gregorian
    return calendar


def fetch_hijri_year_calendar(year):
    params = {'calendarMethod': EVENT_CALENDAR_METHOD}
    url = (f'https://api.aladhan.com/v1/islamicHolidaysByHijriYear/{int(year)}?'
           + urllib.parse.urlencode(params))
    request = urllib.request.Request(url, headers={'User-Agent': 'ConkyPrayer/1.0'})
    with urllib.request.urlopen(request, timeout=8) as response:
        payload = json.load(response)
    return normalize_hijri_year_calendar(payload, year)


def normalize_hijri_to_gregorian(payload, hijri_date):
    """Normalize AlAdhan's hToG fallback for a single curated Hijri date."""
    if not isinstance(payload, dict) or payload.get('code') != 200:
        raise ValueError(f'Invalid AlAdhan hToG response for {hijri_date}')
    data = payload.get('data')
    if not isinstance(data, dict):
        raise ValueError(f'Missing AlAdhan hToG data for {hijri_date}')
    hijri, gregorian = data.get('hijri'), data.get('gregorian')
    if not isinstance(hijri, dict) or not isinstance(gregorian, dict):
        raise ValueError(f'Missing AlAdhan hToG dates for {hijri_date}')
    if hijri.get('date') != hijri_date:
        raise ValueError(f'AlAdhan hToG returned the wrong Hijri date for {hijri_date}')
    method = hijri.get('method') or EVENT_CALENDAR_METHOD
    if method != EVENT_CALENDAR_METHOD:
        raise ValueError(f'Unexpected Hijri calendar method: {method}')
    result = parse_api_date(gregorian.get('date'))
    if not result:
        raise ValueError(f'Invalid Gregorian date for {hijri_date}')
    return result


def fetch_hijri_to_gregorian(hijri_date):
    params = {'calendarMethod': EVENT_CALENDAR_METHOD}
    url = ('https://api.aladhan.com/v1/hToG/'
           + urllib.parse.quote(hijri_date, safe='') + '?'
           + urllib.parse.urlencode(params))
    request = urllib.request.Request(url, headers={'User-Agent': 'ConkyPrayer/1.0'})
    with urllib.request.urlopen(request, timeout=8) as response:
        payload = json.load(response)
    return normalize_hijri_to_gregorian(payload, hijri_date)


def build_curated_events(calendar_by_year, base_hijri_year, fallback=None):
    """Build the allowlisted event catalog for this and next Hijri year."""
    events = []
    for year in (int(base_hijri_year), int(base_hijri_year) + 1):
        calendar = calendar_by_year.get(year, {})
        for event_key, name, day, month in EVENT_RULES:
            hijri_date = f'{day:02d}-{month:02d}-{year}'
            gregorian_date = calendar.get(hijri_date)
            if not gregorian_date and fallback:
                gregorian_date = fallback(hijri_date)
            if not gregorian_date:
                raise ValueError(
                    f'No Gregorian conversion for configured event {name} ({hijri_date})')
            event = {
                'event_key': event_key,
                'name': name,
                'hijri_date': hijri_date,
                'gregorian_date': gregorian_date,
                'calendar_method': EVENT_CALENDAR_METHOD,
            }
            if not valid_event(event):
                raise ValueError(f'Invalid curated event {name} ({hijri_date})')
            events.append(event)
    return sorted(events, key=lambda item: (item['gregorian_date'], item['event_key']))


def select_next_curated_event(events, displayed_date):
    """Select only an allowlisted event on/after the widget's displayed date."""
    try:
        displayed = dt.date.fromisoformat(displayed_date)
    except (TypeError, ValueError):
        raise ValueError('Invalid displayed Gregorian date for Hijri event selection')
    for event in events:
        if not valid_event(event):
            continue
        if dt.date.fromisoformat(event['gregorian_date']) >= displayed:
            return event
    raise ValueError('No upcoming curated Islamic event in the fetched Hijri years')


def fetch_next_curated_hijri_event(hijri_year, displayed_date):
    """Fetch current/next Hijri year and select the next approved event."""
    years = (int(hijri_year), int(hijri_year) + 1)
    calendars = {year: fetch_hijri_year_calendar(year) for year in years}
    events = build_curated_events(
        calendars, hijri_year, fallback=fetch_hijri_to_gregorian)
    return select_next_curated_event(events, displayed_date)


def event_cache_content(event, base_hijri_year, fetched_at=None):
    if not valid_event(event):
        raise ValueError('Invalid curated Hijri event cache data')
    base_hijri_year = int(base_hijri_year)
    event_hijri_year = int(event['hijri_date'][-4:])
    if base_hijri_year < 1 or event_hijri_year not in (
            base_hijri_year, base_hijri_year + 1):
        raise ValueError('Curated event is outside the cached Hijri years')
    fields = [
        ('fetched_at', str(int(time.time() if fetched_at is None else fetched_at))),
        ('base_hijri_year', str(base_hijri_year)),
        ('event_key', event['event_key']),
        ('name', event['name']),
        ('hijri_date', event['hijri_date']),
        ('gregorian_date', event['gregorian_date']),
        ('calendar_method', event['calendar_method']),
    ]
    if any('\n' in value or '\r' in value for _, value in fields):
        raise ValueError('Newline in curated Hijri event data')
    return 'CONKY_HIJRI_EVENT_V2\n' + ''.join(
        f'{key}={value}\n' for key, value in fields)


def event_cache_is_current(path, now=None, hijri_year=None):
    now = int(time.time() if now is None else now)
    try:
        lines = path.read_text(encoding='utf-8').splitlines()
        if not lines or lines[0] != 'CONKY_HIJRI_EVENT_V2':
            return False
        entries = {}
        for line in lines[1:]:
            if '=' not in line:
                return False
            key, value = line.split('=', 1)
            if key in entries:
                return False
            entries[key] = value
        event = {
            'event_key': entries.get('event_key', ''),
            'name': entries.get('name', ''),
            'hijri_date': entries.get('hijri_date', ''),
            'gregorian_date': entries.get('gregorian_date', ''),
            'calendar_method': entries.get('calendar_method', ''),
        }
        fetched_at = int(entries.get('fetched_at', ''))
        base_year = int(entries.get('base_hijri_year', ''))
        event_year = int(event['hijri_date'][-4:])
        return (valid_event(event) and base_year > 0
                and event_year in (base_year, base_year + 1)
                and (hijri_year is None or base_year == int(hijri_year))
                and fetched_at <= now and now - fetched_at <= EVENT_CACHE_TTL)
    except (OSError, UnicodeError, TypeError, ValueError):
        return False


def fetch(date, location, signature):
    date_api = dt.date.fromisoformat(date).strftime('%d-%m-%Y')
    params = {'midnightMode': location['midnight_mode'] or '1',
              'school': location['school'] or '0'}
    if location['method'] not in ('', 'auto'):
        params['method'] = location['method']
    if location['mode'] == 'city':
        params.update(city=location['city'], country=location['country'])
        if location['state']:
            params['state'] = location['state']
        endpoint = 'timingsByCity'
    else:
        params.update(latitude=location['latitude'],
                      longitude=location['longitude'])
        endpoint = 'timings'
    url = (f'https://api.aladhan.com/v1/{endpoint}/{date_api}?'
           + urllib.parse.urlencode(params))
    request = urllib.request.Request(url, headers={'User-Agent': 'ConkyPrayer/1.0'})
    with urllib.request.urlopen(request, timeout=8) as response:
        payload = json.load(response)
    if payload.get('code') != 200 or not isinstance(payload.get('data'), dict):
        raise ValueError(f'Invalid prayer times response for {date}')
    payload['_settings_signature'] = signature
    if not valid(payload, signature):
        raise ValueError(f'Incomplete prayer times response for {date}')
    return payload


def atomic_write(path, content):
    fd, tmp = tempfile.mkstemp(prefix='.prayer-', dir=CACHE_DIR)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def parse_worker_args(args):
    dates = []
    event_requested = False
    force_event = False
    hijri_year = None
    displayed_date = None
    index = 0
    while index < len(args):
        value = args[index]
        if value == '--event':
            event_requested = True
        elif value == '--event-force':
            force_event = True
        elif value in ('--hijri-year', '--displayed-date'):
            index += 1
            if index >= len(args):
                raise ValueError(f'Missing value for {value}')
            option_value = args[index]
            if value == '--hijri-year':
                hijri_year = int(option_value)
                if hijri_year < 1:
                    raise ValueError('Invalid Hijri year')
            else:
                try:
                    displayed_date = dt.date.fromisoformat(option_value).isoformat()
                except ValueError:
                    raise ValueError('Invalid displayed date')
        elif value.startswith('--'):
            raise ValueError(f'Unknown option: {value}')
        else:
            dates.append(value)
        index += 1
    if force_event and not event_requested:
        raise ValueError('--event-force requires --event')
    if event_requested and (hijri_year is None or displayed_date is None):
        raise ValueError('--event requires --hijri-year and --displayed-date')
    return dates, event_requested, force_event, hijri_year, displayed_date


def main(args):
    dates, event_requested, force_event, hijri_year, displayed_date = parse_worker_args(args)
    if not dates and not event_requested:
        return 2
    location, signature = get_location() if dates else (None, None)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    with (CACHE_DIR / '.lock').open('a+') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return 0  # Another Conky instance's worker is fetching

        failed = False
        for date in dict.fromkeys(dates):
            try:
                dt.date.fromisoformat(date)
                if date != dt.date.fromisoformat(date).isoformat():
                    raise ValueError('Date must be YYYY-MM-DD')
                path = CACHE_DIR / f'{date}.cache'
                if cache_is_current(path, signature, date):
                    continue
                payload = fetch(date, location, signature)
                atomic_write(path, cache_content(date, payload, signature))
            except (OSError, ValueError, KeyError) as exc:
                print(f'{date}: {exc}', file=sys.stderr)
                failed = True

        if event_requested:
            event_path = CACHE_DIR / EVENT_CACHE_NAME
            if force_event or not event_cache_is_current(
                    event_path, hijri_year=hijri_year):
                try:
                    event = fetch_next_curated_hijri_event(
                        hijri_year, displayed_date)
                    atomic_write(event_path, event_cache_content(
                        event, base_hijri_year=hijri_year))
                except (OSError, ValueError, KeyError, TypeError) as exc:
                    print(f'curated Hijri event: {exc}', file=sys.stderr)
                    failed = True
        return 1 if failed else 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]) if len(sys.argv) > 1 else 2)
    except (ValueError, OSError, configparser.Error) as exc:
        print(f'Configuration error: {exc}', file=sys.stderr)
        sys.exit(2)
