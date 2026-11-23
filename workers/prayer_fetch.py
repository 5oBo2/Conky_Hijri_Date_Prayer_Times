#!/usr/bin/env python3
"""Fetch and atomically cache Aladhan schedules without blocking Conky.

Usage: python3 workers/prayer_fetch.py YYYY-MM-DD [YYYY-MM-DD ...]
The cache is shared by all Conky processes. Requires Python 3 only.
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


def main(dates):
    location, signature = get_location()
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
        return 1 if failed else 0


if __name__ == '__main__':
    try:
        sys.exit(main(sys.argv[1:]) if len(sys.argv) > 1 else 2)
    except (ValueError, OSError, configparser.Error) as exc:
        print(f'Configuration error: {exc}', file=sys.stderr)
        sys.exit(2)
