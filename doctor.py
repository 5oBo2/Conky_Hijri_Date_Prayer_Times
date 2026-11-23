#!/usr/bin/env python3
"""Check local dependencies, configuration, and optional live prayer API fetch."""
import argparse
import datetime as dt
import os
import re
import pathlib
import shutil
import subprocess
import sys

import configure
from workers import layout, prayer_fetch

ROOT = pathlib.Path(__file__).resolve().parent


def check_runtime():
    """Check the X11/XWayland Conky build and its cairo_xlib module."""
    problems = 0
    executable = shutil.which('conky')
    if not executable:
        print('[ERROR] Conky missing (Fedora 45 provides 1.24.2).')
        return 1
    print(f'[OK] Conky found: {executable}')
    try:
        output = subprocess.run([executable, '--version'], capture_output=True,
                                text=True, timeout=6, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f'[ERROR] Could not check Conky version: {exc}')
        return 1
    features = output.stdout + output.stderr
    version = re.search(r'\bconky\s+(\d+)\.(\d+)\.(\d+)', features, re.I)
    if not version or tuple(map(int, version.groups())) < (1, 23, 0):
        print('[ERROR] Conky 1.23+ is required by the current project runtime. '
              'Fedora 44 ships 1.22.2; Fedora 45 ships 1.24.2.')
        problems += 1
    else:
        print('[OK] Conky version meets the project requirement (1.23+)')
    x11_features = features.split('X11:', 1)[1].split('Wayland:', 1)[0] if 'X11:' in features else ''
    if '* Cairo' not in features or '* Mouse events' not in x11_features:
        print('[ERROR] Conky must be built with Lua Cairo and X11 mouse events')
        problems += 1
    else:
        print('[OK] Lua Cairo and X11 mouse events compiled in')
    # Conky --version normally reports its Lua plugin library directory.
    # We require cairo_xlib specifically: conky_surface() is not a reliable
    # substitute with XDBE double buffering on the tested Conky 1.24.2 build.
    match = re.search(r'(?m)^\s*Package library path:\s*(\S+)\s*$', features)
    if match:
        binding = pathlib.Path(match.group(1)) / 'libcairo_xlib.so'
        if binding.is_file():
            print(f'[OK] Xlib Cairo binding found: {binding}')
        else:
            print(f'[ERROR] Xlib Cairo binding missing: {binding}')
            problems += 1
    else:
        print('[WARN] Conky did not report its package library path; '
              'cairo_xlib will be required when widgets load')
    if not os.environ.get('DISPLAY'):
        print('[ERROR] DISPLAY is unset. Start from a live X11/XWayland session.')
        problems += 1
    else:
        session = os.environ.get('XDG_SESSION_TYPE', '').lower()
        if session == 'wayland':
            print('[OK] KDE Wayland session with X11 DISPLAY for XWayland')
        else:
            print('[OK] X11 DISPLAY available (session: ' + (session or 'unknown') + ')')
    return problems


def check():
    problems = 0
    if shutil.which('python3'):
        print('[OK] Python 3 available')
    problems += check_runtime()

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
    if not audio.is_file():
        audio = ROOT / 'assets/athan.wav'
    if audio.is_file():
        if shutil.which('paplay'):
            print('[OK] Athan audio file and paplay available')
        else:
            print('[WARN] athan.wav is present but paplay is not installed')
    else:
        print('[INFO] No athan.wav yet: place it at the project root or in assets/')
    required = ('lib/Settings.lua', 'lib/Surface.lua', 'lib/Hover_State.lua',
                'lib/Prayer_Data.lua', 'lib/Weather_Data.lua',
                'widgets/Prayer_Times.lua', 'widgets/Hijri_Date.lua',
                'widgets/Sun_Moon_Astrolabe.lua', 'widgets/Weather.lua',
                'configs/conky_sun_moon.conf', 'configs/conky_weather.conf',
                'configs/conky_prayer_times.conf', 'configs/conky_date.conf',
                'workers/prayer_fetch.py', 'workers/weather_fetch.py',
                'workers/layout.py', 'assets/weather/32.png')
    for rel in required:
        if not (ROOT / rel).is_file():
            print(f'[ERROR] Missing required file: {rel}')
            problems += 1
    print(f'\nDiagnostic result: {problems} error(s).')
    return 1 if problems else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-only', action='store_true',
                        help='validate Conky X11/XWayland runtime before launching widgets')
    parser.add_argument('--weather-fetch', action='store_true', help='download current weather to shared cache')
    parser.add_argument('--fetch', action='store_true',
                        help='attempt a live HTTPS fetch for today; saves cache')
    args = parser.parse_args()
    if args.runtime_only:
        return 1 if check_runtime() else 0
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
        from workers import weather_fetch
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
