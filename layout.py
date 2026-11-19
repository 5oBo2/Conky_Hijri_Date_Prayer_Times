#!/usr/bin/env python3
"""Monitor-aware placement helper for Conky widgets on KDE Plasma.

Only uses the Python standard library and `kscreen-doctor -o` (if installed).
Conky's X11 placement is expressed in virtual-desktop coordinates; positioning
on native Wayland depends on the compositor and may not match these estimates.
"""
import configparser
import json
import math
import os
from pathlib import Path
import re
import subprocess

BASE = {'prayer': (1100, 255), 'date': (700, 290),
        'weather': (282, 155), 'sun_moon': (416, 432)}

def kinds_for(widget):
    return {'both': ('prayer', 'date'),
            'new': ('weather', 'sun_moon'),
            'all': ('prayer', 'date', 'weather', 'sun_moon')}.get(widget, (widget,))
ANCHORS = (
    'top-left', 'top-center', 'top-right',
    'middle-left', 'center', 'middle-right',
    'bottom-left', 'bottom-center', 'bottom-right',
)
LAYOUT_DIR = Path(__file__).resolve().with_name('layouts')
MANUAL_MONITORS = Path(__file__).resolve().with_name('monitor_geometry.json')


def displays_from_kscreen_json(output):
    """Read the machine-readable JSON offered by modern KScreen releases."""
    try:
        data = json.loads(output)
    except (json.JSONDecodeError, TypeError):
        return []
    displays = []
    for item in data.get('outputs', []):
        if not isinstance(item, dict) or not item.get('connected', True):
            continue
        if not item.get('enabled', True):
            continue
        name, pos, size = item.get('name'), item.get('pos'), item.get('size')
        if not isinstance(pos, dict) or not isinstance(size, dict) or not name:
            continue
        try:
            x, y = int(pos['x']), int(pos['y'])
            w, h = int(size['width']), int(size['height'])
        except (TypeError, ValueError, KeyError):
            continue
        if w > 0 and h > 0:
            displays.append({'name': str(name), 'x': x, 'y': y, 'w': w, 'h': h})
    return displays


def displays_from_kscreen(output):
    """Parse `-o` when `-j` isn't supported.

    KScreen prints `enabled` on the same line as Output: in some releases,
    and on the NEXT line in others. Both are supported here.
    """
    output = re.sub(r'\x1b\[[0-9;]*m', '', output)  # optional ANSI colors
    chunks = re.split(r'(?=^\s*Output:\s+\d+\s+)', output, flags=re.M)
    displays = []
    for chunk in chunks:
        first = re.search(r'^\s*Output:\s+\d+\s+(\S+)', chunk, re.M)
        geometry = re.search(r'\bGeometry:\s*(-?\d+)\s*,\s*(-?\d+)\s+(\d+)x(\d+)', chunk)
        # Check every line of this output block, not just the header.
        enabled = re.search(r'\benabled\b', chunk)
        if first and geometry and enabled:
            name = first.group(1)
            x, y, w, h = map(int, geometry.groups())
            if w > 0 and h > 0:
                displays.append({'name': name, 'x': x, 'y': y, 'w': w, 'h': h})
    return displays


def _valid_monitors(items):
    good = []
    if not isinstance(items, list):
        return good
    for item in items:
        if not isinstance(item, dict):
            continue
        try:
            name = str(item['name'])
            x, y = int(item['x']), int(item['y'])
            w, h = int(item['w']), int(item['h'])
        except (ValueError, TypeError, KeyError):
            continue
        if name.strip() and w > 0 and h > 0:
            good.append({'name': name, 'x': x, 'y': y, 'w': w, 'h': h})
    return good


def saved_manual_monitors():
    try:
        data = json.loads(MANUAL_MONITORS.read_text(encoding='utf-8'))
        return _valid_monitors(data.get('monitors', []))
    except (OSError, ValueError, TypeError):
        return []


def save_manual_monitors(displays):
    good = _valid_monitors(displays)
    if not good:
        raise ValueError('Cannot save an empty/invalid monitor geometry.')
    MANUAL_MONITORS.write_text(
        json.dumps({'version': 1, 'monitors': good}, indent=2) + '\n', encoding='utf-8')


def enter_manual_monitors():
    """Let Wayland users continue if kscreen-doctor cannot be queried."""
    print('\nEnter logical monitor geometry from KDE System Settings > Display & Monitor.')
    print('Use each monitor\'s position (X,Y) and logical width/height, NOT its physical size.')
    print('Example: first 1920x1080 display X=0,Y=0; second X=1920,Y=0.')
    count = int(ask_number('Number of active displays', 2, 1, 12))
    displays = []
    for i in range(count):
        print(f'\nDisplay {i+1}:')
        name = ask('Name', f'Display-{i+1}')
        while True:
            coordinates = input('Enter X,Y,WIDTH,HEIGHT (e.g. 1920,0,2560,1440): ').strip()
            try:
                parts = [int(n.strip()) for n in coordinates.split(',')]
                if len(parts) != 4 or parts[2] < 1 or parts[3] < 1:
                    raise ValueError()
                x, y, w, h = parts
                break
            except ValueError:
                print('Use four integers separated by commas, with positive width/height.')
        displays.append({'name': name, 'x': x, 'y': y, 'w': w, 'h': h})
    return displays

def displays_from_xrandr(output):
    displays = []
    for line in output.splitlines():
        # xrandr --listmonitors: 0: +*DP-1 1920/530x1080/300+0+0 DP-1
        m = re.search(r'^\s*\d+:\s+\S+\s+(\d+)/(?:\d+)x(\d+)/(?:\d+)\+(-?\d+)\+(-?\d+)\s+(\S+)', line)
        if m:
            w, h, x, y = map(int, m.group(1, 2, 3, 4))
            displays.append({'name': m.group(5), 'x': x, 'y': y, 'w': w, 'h': h})
    return displays


def monitors():
    # `-o` prints the compositor's logical Geometry (including scaling);
    # fall back to machine-readable JSON if its text format is unrecognized.
    for flag, parser in (('-o', displays_from_kscreen),
                         ('-j', displays_from_kscreen_json)):
        try:
            result = subprocess.run(['kscreen-doctor', flag], capture_output=True,
                                    text=True, timeout=6, check=False)
            if result.returncode == 0:
                displays = parser(result.stdout)
                if displays:
                    return displays, 'kscreen-doctor ' + flag
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
            break
    # XRandR on Wayland can report only an XWayland virtual screen;
    # don't mistake it for real monitor geometry.
    if os.environ.get('XDG_SESSION_TYPE', '').lower() == 'x11':
        try:
            result = subprocess.run(['xrandr', '--listmonitors'], capture_output=True,
                                    text=True, timeout=6, check=False)
            if result.returncode == 0:
                displays = displays_from_xrandr(result.stdout)
                if displays:
                    return displays, 'xrandr --listmonitors'
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
            pass
    saved = saved_manual_monitors()
    if saved:
        return saved, 'saved manual geometry (may be outdated)'
    return [], None

def scaled_size(kind, scale):
    w, h = BASE[kind]
    return (int(math.floor(w * scale + .5)), int(math.floor(h * scale + .5)))


def calculate_position(monitor, kind, scale, anchor, margin_x, margin_y):
    if anchor not in ANCHORS:
        raise ValueError(f'Unknown anchor {anchor}')
    w, h = scaled_size(kind, scale)
    if 'left' in anchor:
        x = monitor['x'] + margin_x
    elif 'right' in anchor:
        x = monitor['x'] + monitor['w'] - w - margin_x
    else:
        x = monitor['x'] + (monitor['w'] - w) // 2
    if anchor.startswith('top'):
        y = monitor['y'] + margin_y
    elif anchor.startswith('bottom'):
        y = monitor['y'] + monitor['h'] - h - margin_y
    else:
        y = monitor['y'] + (monitor['h'] - h) // 2
    return x, y


def get_boxes(cp, widget='both'):
    for kind in kinds_for(widget):
        scale = cp.getfloat('appearance', kind + '_scale')
        w, h = scaled_size(kind, scale)
        x = cp.getint('placement', kind + '_x')
        y = cp.getint('placement', kind + '_y')
        yield kind, (x, y, w, h)


def intersection(rect, mon):
    x, y, w, h = rect
    return max(0, min(x + w, mon['x'] + mon['w']) - max(x, mon['x'])) * max(
        0, min(y + h, mon['y'] + mon['h']) - max(y, mon['y']))


def show_screens(displays, source):
    if not displays:
        print('No monitor geometry detected. Try: kscreen-doctor -o')
        print('If kscreen-doctor fails, enter geometry with: python3 configure.py --manual-screens')
        print('On X11, you can also try: xrandr --listmonitors')
        return
    print(f'Detected monitors ({source}):')
    for i, m in enumerate(displays, 1):
        print(f"  {i}. {m['name']}: {m['w']}x{m['h']} at ({m['x']},{m['y']})")


def check_layout(cp, widget='both'):
    displays, source = monitors()
    show_screens(displays, source)
    print('\nEstimated Conky rectangles (X,Y,W,H):')
    boxes = list(get_boxes(cp, widget))
    for kind, r in boxes:
        print(f'  {kind.capitalize()}: {r}')
        if displays:
            hits = [(intersection(r, m), m) for m in displays]
            count, mon = max(hits, key=lambda p: p[0])
            if count == 0:
                print('    WARNING: this is completely outside the detected monitors.')
            elif count < r[2] * r[3]:
                print(f"    WARNING: extends beyond {mon['name']} screen boundaries.")
            else:
                print(f"    Fits within {mon['name']}.")
    for i, (name_a, a) in enumerate(boxes):
        for name_b, b in boxes[i+1:]:
            if max(0, min(a[0]+a[2],b[0]+b[2]) - max(a[0],b[0])) * max(
                    0, min(a[1]+a[3],b[1]+b[3]) - max(a[1],b[1])):
                print(f'  NOTE: {name_a} and {name_b} rectangles overlap.')
    print('\nSizes are estimates from Conky minimum dimensions, not measurements'
          ' of Cairo text. For actual X11 window geometry, try `xwininfo` or KWin.')


def ask(prompt, default):
    v = input(f'{prompt} [{default}]: ').strip()
    return str(default) if not v else v


def ask_number(prompt, default, lo, hi):
    while True:
        try:
            value = float(ask(prompt, default))
            if math.isfinite(value) and lo <= value <= hi:
                return value
        except ValueError:
            pass
        print(f'Enter a number from {lo} to {hi}.')


def ask_option(prompt, choices, default):
    while True:
        v = ask(prompt, default)
        if v in choices:
            return v
        print('Choose one of: ' + ', '.join(choices))


def wizard(cp, widget='both'):
    displays, source = monitors()
    show_screens(displays, source)
    if not displays:
        print('Monitor auto-detection was unavailable.')
        if ask_option('Enter monitor geometry manually now? yes/no', ('yes', 'no'), 'yes') == 'no':
            print('No changes were made. You may edit [placement] in settings.ini instead.')
            return None
        displays = enter_manual_monitors()
        save_manual_monitors(displays)
        source = 'saved manual geometry'
    print('\nPlace the selected widget(s) on a monitor. X and Y are calculated.')
    print('Each of the four widgets can use a different monitor and scale.')
    for kind in kinds_for(widget):
        print('\n' + {'prayer':'PRAYER TIMES', 'date':'DATE / HIJRI', 'weather':'WEATHER', 'sun_moon':'CELESTIAL ASTROLABE'}[kind])
        index = int(ask_option('Monitor number', [str(i) for i in range(1, len(displays) + 1)], '1'))
        mon = displays[index - 1]
        old = cp.getfloat('appearance', kind + '_scale')
        size_mode = ask_option('Size: 1 = keep current, 2 = custom scale, 3 = fit within screen percentage', ('1','2','3'), '1')
        if size_mode == '1':
            scale = old
        elif size_mode == '2':
            scale = ask_number('Scale (1 = original)', old, .3, 3)
        else:
            width_pct = ask_number('Maximum share of monitor width (%)', 90, 1, 100)
            height_pct = ask_number('Maximum share of monitor height (%)', 35, 1, 100)
            base_w, base_h = BASE[kind]
            fit = min(mon['w'] * width_pct / 100 / base_w,
                      mon['h'] * height_pct / 100 / base_h, 3)
            if fit < .3:
                print('Requested area is too small; minimum supported scale 0.3 is used.')
            scale = max(.3, math.floor(fit * 1000) / 1000)
        w, h = scaled_size(kind, scale)
        print(f'Estimated size: {w}x{h} pixels on {mon["name"]}')
        print('Positions: ' + ', '.join(f'{i}={a}' for i, a in enumerate(ANCHORS, 1)))
        anchor = ANCHORS[int(ask_option('Position number', [str(i) for i in range(1, 10)],
                                        '1' if kind in ('date', 'weather', 'sun_moon') else '7')) - 1]
        margin_x = int(ask_number('Horizontal margin (pixels)', 20, 0, 10000))
        margin_y = int(ask_number('Vertical margin (pixels)', 20, 0, 10000))
        x, y = calculate_position(mon, kind, scale, anchor, margin_x, margin_y)
        if w > mon['w'] or h > mon['h'] or intersection((x,y,w,h), mon) < w*h:
            print('WARNING: this placement does not fit completely on the monitor.')
            if ask_option('Keep this placement? yes/no', ('yes','no'), 'no') == 'no':
                print('Retaining previous settings for this widget.')
                continue
        cp['appearance'][kind + '_scale'] = str(round(scale, 3))
        cp['placement'][kind + '_x'] = str(x)
        cp['placement'][kind + '_y'] = str(y)
        print(f'Configured {kind}: x={x}, y={y}, scale={scale:.3f}')
    return cp


def _profile_path(name):
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,40}', name):
        raise ValueError('Layout name must be 1-40 letters, numbers, underscores or hyphens.')
    return LAYOUT_DIR / (name + '.ini')


def _selected_layout_keys(widget):
    kinds = kinds_for(widget)
    return (('appearance', [kind + '_scale' for kind in kinds]),
            ('placement', [kind + '_' + axis for kind in kinds for axis in ('x', 'y')]))


def save_layout(cp, name, widget='both'):
    """Store selected widget layout; when updating a preset keep the other widget."""
    path = _profile_path(name)
    LAYOUT_DIR.mkdir(parents=True, exist_ok=True)
    saved = configparser.ConfigParser(interpolation=None)
    if path.exists():
        saved.read(path, encoding='utf-8')
    for section, keys in _selected_layout_keys(widget):
        if not saved.has_section(section):
            saved.add_section(section)
        for key in keys:
            saved[section][key] = cp[section][key]
    with path.open('w', encoding='utf-8') as file:
        file.write('# Conky size/placement only. Location and Athan settings stay unchanged.\n')
        saved.write(file)
    return path


def use_layout(cp, name, widget='both'):
    path = _profile_path(name)
    if not path.is_file():
        raise ValueError(f'Layout not found: {name}. Saved layouts: {", ".join(list_layouts()) or "none"}')
    saved = configparser.ConfigParser(interpolation=None)
    saved.read(path, encoding='utf-8')
    applied = 0
    for section, keys in _selected_layout_keys(widget):
        for key in keys:
            if saved.has_option(section, key):
                cp[section][key] = saved[section][key]
                applied += 1
    if not applied:
        raise ValueError(f'Layout {name} has no saved settings for {widget}.')
    return cp


def list_layouts():
    return sorted(p.stem for p in LAYOUT_DIR.glob('*.ini')) if LAYOUT_DIR.exists() else []
