#!/usr/bin/env python3
"""Launch/stop a full-screen original-PNG vs Cairo weather icon probe."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'configs' / 'conky_weather_icon_probe.conf'
CACHE = Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'conky-prayer-times'
PID_FILE = CACHE / 'weather-icon-probe.pid'
LOG_FILE = CACHE / 'weather-icon-probe.log'


def _run(command: list[str]) -> str | None:
    try:
        result = subprocess.run(command, capture_output=True, text=True,
                                check=False, timeout=4)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout if result.returncode == 0 else None


def detect_screen() -> tuple[int, int, int, int, str]:
    """Prefer the primary XRandR monitor; fall back to the X screen bounds."""
    output = _run(['xrandr', '--current'])
    if output:
        primary = re.search(
            r'^\S+ connected primary\s+.*?(\d+)x(\d+)\+(-?\d+)\+(-?\d+)',
            output, re.MULTILINE)
        if primary:
            w, h, x, y = map(int, primary.groups())
            return w, h, x, y, 'primary XRandR monitor'
        screen = re.search(r'Screen \d+:.*?current\s+(\d+)\s+x\s+(\d+)', output)
        if screen:
            w, h = map(int, screen.groups())
            return w, h, 0, 0, 'X screen bounds'

    output = _run(['xdpyinfo'])
    if output:
        match = re.search(r'dimensions:\s+(\d+)x(\d+) pixels', output)
        if match:
            w, h = map(int, match.groups())
            return w, h, 0, 0, 'X display bounds'
    raise RuntimeError('Cannot detect the X11/XWayland screen size. '
                       'Pass --width and --height explicitly.')


def _read_pid() -> int | None:
    try:
        pid = int(PID_FILE.read_text().strip())
    except (OSError, ValueError):
        return None
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        PID_FILE.unlink(missing_ok=True)
        return None
    except PermissionError:
        return pid
    # Avoid signalling an unrelated process if the PID file outlives a reboot
    # and the operating system later reuses that PID.
    try:
        command_line = Path(f'/proc/{pid}/cmdline').read_bytes()
    except OSError:
        command_line = b''
    if b'conky_weather_icon_probe.conf' not in command_line:
        PID_FILE.unlink(missing_ok=True)
        return None
    return pid


def stop() -> int:
    pid = _read_pid()
    if pid is None:
        print('Weather icon probe is not running.')
        return 0
    try:
        os.killpg(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    PID_FILE.unlink(missing_ok=True)
    print('Stopped the weather icon probe.')
    return 0


def start(width: int | None, height: int | None,
          x: int | None, y: int | None) -> int:
    conky = shutil.which('conky')
    if not conky:
        raise RuntimeError('Conky was not found in PATH.')
    if not CONFIG.is_file():
        raise RuntimeError(f'Missing probe config: {CONFIG}')

    if width is None or height is None:
        detected_w, detected_h, detected_x, detected_y, source = detect_screen()
        width = detected_w if width is None else width
        height = detected_h if height is None else height
        x = detected_x if x is None else x
        y = detected_y if y is None else y
    else:
        source = 'manual dimensions'
    x = 0 if x is None else x
    y = 0 if y is None else y
    if width < 640 or height < 480:
        raise RuntimeError(f'Screen size {width}x{height} is too small for the atlas.')

    existing = _read_pid()
    if existing is not None:
        print(f'Weather icon probe is already running (PID {existing}).')
        print('Close it with: python3 tools/weather_icon_probe.py --stop')
        return 0

    CACHE.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update({
        'CONKY_WEATHER_PROBE_WIDTH': str(width),
        'CONKY_WEATHER_PROBE_HEIGHT': str(height),
        'CONKY_WEATHER_PROBE_X': str(x),
        'CONKY_WEATHER_PROBE_Y': str(y),
    })
    with LOG_FILE.open('w', encoding='utf-8') as log:
        process = subprocess.Popen(
            [conky, '-c', str(CONFIG)], cwd=ROOT, env=env,
            stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
            start_new_session=True)
    PID_FILE.write_text(str(process.pid) + '\n', encoding='ascii')
    time.sleep(0.8)
    if process.poll() is not None:
        PID_FILE.unlink(missing_ok=True)
        details = LOG_FILE.read_text(encoding='utf-8', errors='replace')
        raise RuntimeError('Conky exited while starting the probe.\n' + details[-4000:])

    print(f'Weather icon probe opened at {width}x{height} ({source}).')
    print('Each tile compares ORIGINAL PNG (left) with CAIRO VECTOR (right).')
    print('Configured celestial accent:', _configured_accent())
    print('Close it with: python3 tools/weather_icon_probe.py --stop')
    print('Conky log:', LOG_FILE)
    return 0


def _configured_accent() -> str:
    settings = ROOT / 'settings.ini'
    try:
        text = settings.read_text(encoding='utf-8')
    except OSError:
        return '(settings.ini unavailable)'
    section = ''
    for line in text.splitlines():
        match = re.match(r'^\s*\[([^]]+)\]\s*$', line)
        if match:
            section = match.group(1).lower()
        elif section == 'appearance':
            match = re.match(r'^\s*next_prayer_color\s*=\s*(#[0-9a-fA-F]{6})', line)
            if match:
                return match.group(1)
    return '#efb46f (default)'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stop', action='store_true', help='close the running probe')
    parser.add_argument('--width', type=int, help='override detected screen width')
    parser.add_argument('--height', type=int, help='override detected screen height')
    parser.add_argument('--x', type=int, help='override left offset (multi-monitor layouts)')
    parser.add_argument('--y', type=int, help='override top offset (multi-monitor layouts)')
    args = parser.parse_args()
    try:
        if args.stop:
            return stop()
        if (args.width is None) != (args.height is None):
            parser.error('--width and --height must be supplied together')
        return start(args.width, args.height, args.x, args.y)
    except RuntimeError as exc:
        print(f'weather_icon_probe: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
