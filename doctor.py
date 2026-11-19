#!/usr/bin/env python3
"""Check local dependencies, configuration, and optional live prayer API fetch."""
import argparse
import datetime as dt
import pathlib
import shutil
import subprocess
import sys

import configure
import layout
import prayer_fetch

ROOT = pathlib.Path(__file__).resolve().parent


def check():
    problems = 0
    if shutil.which('python3'):
        print('[OK] Python 3 available')
    executable = shutil.which('conky')
    if executable:
        print(f'[OK] Conky found: {executable}')
        output = subprocess.run([executable, '--version'], capture_output=True,
                                text=True, timeout=6, check=False)
        features = output.stdout + output.stderr
        for name, token in (('Lua Cairo', '* Cairo'), ('Mouse events', '* Mouse events')):
            if token in features:
                print(f'[OK] {name} compiled in')
            else:
                print(f'[WARN] Conky version output does not confirm {name}')
    else:
        print('[ERROR] Install Conky with Lua Cairo and mouse event support')
        problems += 1

    try:
        cp = configure.read()
        configure.validate(cp)
        print('[OK] settings.ini is valid')
        displays, how = layout.monitors()
        if displays:
            print(f'[OK] Monitor detection: {how} ({len(displays)} screens)')
        else:
            print('[INFO] No monitor geometry detected. Edit placement manually.')
        layout.check_layout(cp, 'all')
    except (ValueError, KeyError, OSError) as exc:
        print(f'[ERROR] Configuration/layout: {exc}')
        problems += 1

    audio = ROOT / 'athan.wav'
    if audio.is_file():
        if shutil.which('paplay'):
            print('[OK] Athan audio file and paplay available')
        else:
            print('[WARN] athan.wav is present but paplay is not installed')
    else:
        print('[INFO] No athan.wav yet: copy yours beside the Lua files')
    required = ('Prayer_Data.lua', 'Weather_Data.lua', 'Sun_Moon_Astrolabe.lua',
                'Weather.lua', 'conky_sun_moon.conf', 'conky_weather.conf',
                'conky_prayer_times.conf', 'conky_date.conf',
                'assets/weather/32.png')
    for rel in required:
        if not (ROOT / rel).is_file():
            print(f'[ERROR] Missing required file: {rel}')
            problems += 1
    print(f'\nDiagnostic result: {problems} error(s).')
    return 1 if problems else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--weather-fetch', action='store_true', help='download current weather to shared cache')
    parser.add_argument('--fetch', action='store_true',
                        help='attempt a live HTTPS fetch for today; saves cache')
    args = parser.parse_args()
    code = check()
    if args.fetch:
        print('\nFetching today’s prayer times from Aladhan...')
        day = dt.date.today().isoformat()
        status = prayer_fetch.main([day])
        if status:
            print('[ERROR] Live fetch failed; check network and ~/.cache/conky-prayer-times/fetch.log')
            return 1
        print('[OK] Prayer data available for ' + day)
    if args.weather_fetch:
        print('\nFetching weather from Open-Meteo...')
        import weather_fetch
        status = weather_fetch.main(['--force'])
        if status: return 1
        print('[OK] Weather cache updated')
    return code


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.TimeoutExpired) as exc:
        print(f'Error: {exc}', file=sys.stderr)
        sys.exit(1)
