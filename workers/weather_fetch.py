#!/usr/bin/env python3
"""Shared weather/sun cache worker for the independent Conky widgets; stdlib only.

Uses Open-Meteo forecast and (if city mode) geocoding. The shared cache is
atomically replaced; an advisory lock avoids duplicate concurrent downloads.
"""
import argparse
import configparser
import datetime as dt
import fcntl
import json
import math
import os
from pathlib import Path
import sys
import tempfile
import time
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / 'settings.ini'
CACHE_DIR = Path(os.environ.get('XDG_CACHE_HOME') or Path.home() / '.cache') / 'conky-sun-weather'
CACHE = CACHE_DIR / 'weather.cache'
LOCATION_KEYS = ('mode', 'city', 'country', 'state', 'latitude', 'longitude',
                 'method', 'school', 'midnight_mode')


def settings():
    cp = configparser.ConfigParser(interpolation=None, inline_comment_prefixes=('#', ';'))
    if not cp.read(CONFIG, encoding='utf-8'):
        raise ValueError(f'Missing {CONFIG}')
    loc = {key: cp.get('location', key, fallback='').strip() for key in LOCATION_KEYS}
    if loc['mode'] not in ('coordinates', 'city'):
        raise ValueError('location.mode must be coordinates or city')
    signature = '|'.join(loc.values())
    refresh = cp.getint('behavior', 'weather_refresh_minutes', fallback=20)
    if not 5 <= refresh <= 180:
        raise ValueError('weather_refresh_minutes must be 5..180')
    return loc, signature, refresh * 60


def get_json(url, params):
    request = Request(url + '?' + urlencode(params), headers={
        'User-Agent': 'Conky-Sun-Weather/1.0 (+local desktop widget)',
        'Accept': 'application/json',
    })
    with urlopen(request, timeout=18) as response:
        if response.status != 200:
            raise ValueError(f'Weather service returned HTTP {response.status}')
        return json.load(response)


def resolve_coordinates(loc):
    if loc['mode'] == 'coordinates':
        lat, lon = float(loc['latitude']), float(loc['longitude'])
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError('Latitude/longitude out of range')
        return lat, lon
    if not loc['city'] or not loc['country']:
        raise ValueError('City and country are required in city mode')
    payload = get_json('https://geocoding-api.open-meteo.com/v1/search',
                       {'name': loc['city'], 'count': 50, 'language': 'en', 'format': 'json'})
    results = payload.get('results') or []
    country = loc['country'].casefold()
    matches = [row for row in results if str(row.get('country', '')).casefold() == country
               or str(row.get('country_code', '')).casefold() == country]
    if not matches:
        raise ValueError(f'Could not find {loc["city"]} in {loc["country"]}; use coordinates mode')
    if loc['state']:
        narrowed = [row for row in matches if str(row.get('admin1', '')).casefold() == loc['state'].casefold()]
        if narrowed:
            matches = narrowed
    row = matches[0]
    return float(row['latitude']), float(row['longitude'])


def rounded(value, name, lo, hi):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not lo <= value <= hi:
        raise ValueError('Invalid weather field: ' + name)
    return int(math.floor(value + 0.5)) if value >= 0 else -int(math.floor(-value + 0.5))


def make_cache(payload, signature, now=None):
    now = now if now is not None else time.time()
    tzname = payload['timezone']
    try:
        tz = ZoneInfo(tzname)
    except ZoneInfoNotFoundError as e:
        raise ValueError('Unknown weather timezone: ' + tzname) from e
    current, daily = payload['current'], payload['daily']
    # Open-Meteo daily Unix timestamps describe midnight in the REQUESTED
    # LOCATION, not midnight UTC. Convert using the response's IANA timezone.
    # Interpreting these as UTC dates breaks locations east of Greenwich (e.g.
    # Cairo's local 00:00 is 22:00 UTC on the previous calendar date).
    dates = daily['time']
    required = ('sunrise', 'sunset', 'temperature_2m_max',
                'temperature_2m_min', 'weather_code')
    if len(dates) < 5 or any(len(daily[k]) != len(dates) for k in required):
        raise ValueError('Expected matching daily arrays: yesterday, today and next three days')
    local_today = dt.datetime.fromtimestamp(now, tz).date()
    forecast_dates = [dt.datetime.fromtimestamp(int(ts), tz).date() for ts in dates]
    if len(set(forecast_dates)) != len(forecast_dates):
        raise ValueError('Forecast contains repeated daily dates')
    try:
        today_index = forecast_dates.index(local_today)
    except ValueError as exc:
        raise ValueError('Forecast does not contain today in the location timezone; retry') from exc
    if today_index == 0 or today_index + 3 >= len(dates):
        raise ValueError('Forecast is missing yesterday or any of the next three days; retry')
    for offset in range(1, 4):
        if forecast_dates[today_index + offset] != local_today + dt.timedelta(days=offset):
            raise ValueError('Daily forecast contains a gap after today')
    previous_index, next_index = today_index - 1, today_index + 1
    def stamp(v):
        result = int(v)
        if not 946684800 <= result <= 4102444800:  # years 2000..2100
            raise ValueError('Invalid sunrise/sunset timestamp')
        return result
    events = {
        'yesterday_sunset': stamp(daily['sunset'][previous_index]),
        'sunrise': stamp(daily['sunrise'][today_index]),
        'sunset': stamp(daily['sunset'][today_index]),
        'tomorrow_sunrise': stamp(daily['sunrise'][next_index]),
    }
    if not (events['yesterday_sunset'] < events['sunrise'] < events['sunset'] < events['tomorrow_sunrise']):
        raise ValueError('Sunrise/sunset order invalid')
    # Daily weather_code describes the entire day's weather; the Date renderer
    # therefore uses the daytime variant of the matching condition icon.
    weekdays = ('Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun')
    forecast = {}
    for offset in range(1, 4):
        index = today_index + offset
        prefix = f'forecast_{offset}_'
        forecast[prefix + 'day'] = weekdays[forecast_dates[index].weekday()]
        forecast[prefix + 'high'] = str(rounded(
            daily['temperature_2m_max'][index], prefix + 'high', -110, 70))
        forecast[prefix + 'low'] = str(rounded(
            daily['temperature_2m_min'][index], prefix + 'low', -110, 70))
        forecast[prefix + 'code'] = str(rounded(
            daily['weather_code'][index], prefix + 'code', 0, 99))
        if int(forecast[prefix + 'high']) < int(forecast[prefix + 'low']):
            raise ValueError('Daily maximum cannot be below minimum')

    values = {
        'signature': signature,
        'fetched': str(int(now)),
        'local_date': str(local_today),
        'temperature': str(rounded(current['temperature_2m'], 'temperature', -110, 70)),
        'humidity': str(rounded(current['relative_humidity_2m'], 'humidity', 0, 100)),
        'high': str(rounded(daily['temperature_2m_max'][today_index], 'high', -110, 70)),
        'low': str(rounded(daily['temperature_2m_min'][today_index], 'low', -110, 70)),
        'code': str(rounded(current['weather_code'], 'code', 0, 99)),
        'is_day': str(rounded(current['is_day'], 'is_day', 0, 1)),
        # Local midnight tomorrow, as an absolute timestamp. On a new day an
        # old cache must not show yesterday's three-day forecast as current.
        'forecast_valid_until': str(int(dates[next_index])),
        **forecast,
        **{key: str(ts) for key, ts in events.items()},
        'sunrise_label': dt.datetime.fromtimestamp(events['sunrise'], tz).strftime('%H:%M'),
        'sunset_label': dt.datetime.fromtimestamp(events['sunset'], tz).strftime('%H:%M'),
    }
    for key, value in values.items():
        if any(c in key+value for c in '\n\r'):
            raise ValueError('Unexpected newline in weather cache')
    return 'CONKY_SUN_WEATHER_V2\n' + ''.join(f'{k}={v}\n' for k, v in values.items())


def cache_fresh(signature, ttl):
    try:
        lines = CACHE.read_text(encoding='utf-8').splitlines()
        if lines[0] != 'CONKY_SUN_WEATHER_V2':
            return False
        values = dict(line.split('=', 1) for line in lines[1:])
        now = time.time()
        return (values['signature'] == signature
                and 0 <= now - int(values['fetched']) <= ttl
                and now < int(values['forecast_valid_until']))
    except (ValueError, KeyError, OSError, IndexError):
        return False


def write_atomic(content):
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=CACHE_DIR,
                                     prefix='.weather-', delete=False) as f:
        tmp = Path(f.name)
        try:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        except BaseException:
            tmp.unlink(missing_ok=True)
            raise
    try:
        os.replace(tmp, CACHE)
    finally:
        tmp.unlink(missing_ok=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--force', action='store_true', help='fetch even if a fresh cache exists')
    args = parser.parse_args(argv)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    with (CACHE_DIR / '.fetch.lock').open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        loc, signature, ttl = settings()
        if not args.force and cache_fresh(signature, ttl):
            print('Weather cache already fresh')
            return 0
        lat, lon = resolve_coordinates(loc)
        payload = get_json('https://api.open-meteo.com/v1/forecast', {
            'latitude': lat, 'longitude': lon,
            'current': 'temperature_2m,relative_humidity_2m,weather_code,is_day',
            'daily': 'temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset',
            'temperature_unit': 'celsius', 'timezone': 'auto',
            'timeformat': 'unixtime', 'past_days': 1, 'forecast_days': 4,
        })
        content = make_cache(payload, signature)
        write_atomic(content)
        print('Updated weather for', loc['city'] or f'{lat:.4f},{lon:.4f}')
        return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError, TimeoutError) as exc:
        print(f'Weather fetch failed: {exc}', file=sys.stderr)
        sys.exit(1)
