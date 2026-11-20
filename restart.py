#!/usr/bin/env python3
"""List, stop, or restart only this project’s Conky windows (never killall)."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
CONFIGS = {
    'prayer': {'conky_prayer_times.conf'},
    'date': {'conky_date.conf'},
    'weather': {'conky_weather.conf'},
    'sun_moon': {'conky_sun_moon.conf'},
}
GROUPS = {
    'all': tuple(CONFIGS),
}


def selected_configs(widget):
    keys = GROUPS.get(widget, (widget,))
    return {ROOT / filename for kind in keys for filename in CONFIGS[kind]}


def matching_pids(widget='all', proc=Path('/proc')):
    targets = {str(p.resolve()) for p in selected_configs(widget)}
    found = []
    try:
        entries = proc.iterdir()
    except OSError as exc:
        raise RuntimeError(f'Cannot read process list at {proc}: {exc}') from exc
    for entry in entries:
        if not entry.name.isdigit() or int(entry.name) == os.getpid():
            continue
        try:
            # Avoid touching anyone else's process, including other users'
            # Conky configurations in different directories.
            if entry.stat().st_uid != os.getuid():
                continue
            argv = [os.fsdecode(a) for a in (entry / 'cmdline').read_bytes().split(b'\0') if a]
            if not argv or Path(argv[0]).name != 'conky':
                continue
            for index, arg in enumerate(argv[1:], start=1):
                conf = None
                if arg in ('-c', '--config') and index + 1 < len(argv):
                    conf = argv[index + 1]
                elif arg.startswith('--config='):
                    conf = arg.partition('=')[2]
                if conf and str(Path(conf).expanduser().resolve()) in targets:
                    found.append(int(entry.name))
                    break
        except (OSError, ValueError, PermissionError):
            continue
    return sorted(found)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--widget', choices=tuple(CONFIGS) + tuple(GROUPS), default='all',
                        help='which widget(s) to restart (default: all four)')
    parser.add_argument('--list', action='store_true', help='show matching PIDs; do not stop/start')
    parser.add_argument('--stop-only', action='store_true', help='stop matching PIDs; do not restart')
    args = parser.parse_args(argv)
    try:
        current = matching_pids(args.widget)
    except RuntimeError as exc:
        parser.error(str(exc))
    print(f'{args.widget} running PIDs: ' + (', '.join(map(str, current)) or '(none)'))
    if args.list:
        return 0
    for pid in current:
        try:
            os.kill(pid, signal.SIGTERM)
            print('Stopped:', pid)
        except ProcessLookupError:
            continue
        except PermissionError as exc:
            print(f'Cannot stop {pid}: {exc}', file=sys.stderr)
            return 1
    if current:
        for _ in range(40):
            if not any(pid in matching_pids(args.widget) for pid in current):
                break
            time.sleep(.1)
        else:
            print('A prior Conky process is still running; aborting to avoid duplicates.', file=sys.stderr)
            return 1
    if args.stop_only:
        return 0
    return subprocess.run(['bash', str(ROOT / 'start.sh'), '--widget', args.widget],
                          check=False).returncode


if __name__ == '__main__':
    sys.exit(main())
