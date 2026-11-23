#!/usr/bin/env python3
"""Global X11/XWayland layout planner for all four Conky widgets.

KScreen output names identify a monitor; its logical x/y origin is added to
widget-local anchor offsets to obtain a virtual-desktop position. This assumes
XWayland and KScreen agree on geometry; verify mixed-DPI layouts on KDE.
See docs/NATIVE_WAYLAND_MIGRATION.md before reconsidering native Wayland.
"""
import configparser
from functools import lru_cache
import json
import math
from pathlib import Path
import re
import subprocess

WIDGETS = ('prayer', 'date', 'weather', 'sun_moon')


def kinds_for(widget):
    if widget == 'all':
        return WIDGETS
    if widget not in WIDGETS:
        raise ValueError(f'Unknown widget: {widget}')
    return (widget,)
ANCHORS = (
    'top-left', 'top-center', 'top-right',
    'middle-left', 'center', 'middle-right',
    'bottom-left', 'bottom-center', 'bottom-right',
)
ROOT = Path(__file__).resolve().parent.parent
LAYOUT_DIR = ROOT / 'layouts'
MANUAL_MONITORS = ROOT / 'monitor_geometry.json'
GEOMETRY_FILE = ROOT / 'widget_geometry.ini'


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
    saved = saved_manual_monitors()
    if saved:
        return saved, 'saved manual geometry (may be outdated)'
    return [], None

@lru_cache(maxsize=1)
def canvas_sizes():
    """The exact minimum-size definitions used by Lua Conky configs."""
    cp = configparser.ConfigParser(interpolation=None)
    if not cp.read(GEOMETRY_FILE, encoding='utf-8'):
        raise ValueError(f'Missing authoritative widget canvas: {GEOMETRY_FILE}')
    result = {}
    for kind in WIDGETS:
        width, height = cp.getint(kind, 'width'), cp.getint(kind, 'height')
        if width <= 0 or height <= 0:
            raise ValueError(f'Invalid canvas size for {kind}')
        result[kind] = (width, height)
    return result


def scaled_size(kind, scale):
    w, h = canvas_sizes()[kind]
    return (int(math.floor(w * scale + .5)), int(math.floor(h * scale + .5)))


def calculate_position(monitor, kind, scale, anchor, margin_x, margin_y):
    if anchor not in ANCHORS:
        raise ValueError(f'Unknown anchor {anchor}')
    w, h = scaled_size(kind, scale)
    if 'left' in anchor:
        x = margin_x
    elif 'right' in anchor:
        x = monitor['w'] - w - margin_x
    else:
        x = (monitor['w'] - w) // 2
    if anchor.startswith('top'):
        y = margin_y
    elif anchor.startswith('bottom'):
        y = monitor['h'] - h - margin_y
    else:
        y = (monitor['h'] - h) // 2
    # X11/XWayland Conky gap_x/gap_y use virtual-screen coordinates.
    return monitor['x'] + x, monitor['y'] + y


def get_boxes(cp, widget='all'):
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
        return
    print(f'Detected monitors ({source}):')
    for i, m in enumerate(displays, 1):
        print(f"  {i}. {m['name']}: {m['w']}x{m['h']} logical ({m['x']},{m['y']} compositor position)")


def _layout_intent(cp, kind):
    """Return an optional named-output/anchor layout plan."""
    if not cp.has_section('layout') or not cp.has_option('layout', kind + '_output'):
        return None
    section = cp['layout']
    try:
        output = section[kind + '_output']
        anchor = section[kind + '_anchor']
        margin_x = int(section[kind + '_margin_x'])
        margin_y = int(section[kind + '_margin_y'])
    except (KeyError, ValueError) as exc:
        raise ValueError(f'Incomplete layout intent for {kind}') from exc
    if anchor not in ANCHORS or margin_x < 0 or margin_y < 0:
        raise ValueError(f'Invalid layout intent for {kind}')
    return output, anchor, margin_x, margin_y


def check_layout(cp, widget='all'):
    displays, source = monitors()
    show_screens(displays, source)
    by_name = {mon['name']: mon for mon in displays}
    print('\nEstimated X11/XWayland rectangles (global x, y, W, H):')
    print('Positions assume XWayland and KScreen share one logical desktop.')
    print('Check visually if KDE uses mixed output scaling.')
    boxes = []
    for kind, r in get_boxes(cp, widget):
        plan = _layout_intent(cp, kind)
        print(f'  {kind.capitalize()}: {r}')
        if plan:
            output, anchor, mx, my = plan
            mon = by_name.get(output)
            print(f'    Intended output: {output}; {anchor}; margins {mx}, {my}')
            if not mon:
                print('    WARNING: intended output is disconnected or renamed.')
            else:
                expected = calculate_position(mon, kind,
                            cp.getfloat('appearance', kind + '_scale'), anchor, mx, my)
                if (r[0], r[1]) != expected:
                    print(f'    WARNING: requested offsets are stale; expected {expected}.')
                area = intersection(r, mon)
                if area < r[2] * r[3]:
                    print('    WARNING: requested window extends outside intended output.')
                else:
                    print('    Window rectangle fits intended output (ink unverified).')
            boxes.append((kind, r, output))
        elif len(displays) == 1:
            mon = displays[0]
            print(f'    ' + ('Fits output window rectangle.' if
                intersection(r, mon) == r[2]*r[3] else
                'WARNING: outside the only output window rectangle.'))
            boxes.append((kind, r, mon['name']))
        else:
            print('    No saved layout intent: checking window against detected monitors.')
            if displays and all(intersection(r, mon) < r[2]*r[3] for mon in displays):
                print('    WARNING: requested global rectangle fits NO detected output.')
            boxes.append((kind, r, None))
    for i, (name_a, a, output_a) in enumerate(boxes):
        for name_b, b, output_b in boxes[i+1:]:
            if not output_a or output_a != output_b:
                continue
            if max(0, min(a[0]+a[2],b[0]+b[2]) - max(a[0],b[0])) * max(
                    0, min(a[1]+a[3],b[1]+b[3]) - max(a[1],b[1])):
                print(f'  NOTE: {name_a} and {name_b} rectangles overlap on {output_a}.')
    print('\nWindow sizes are shared with Lua configs via widget_geometry.ini.')
    print('They are not measured Cairo ink bounds; verify rendered glyphs/icons on KDE.')


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


def _choose_monitor(displays):
    if len(displays) == 1:
        return displays[0]
    print('Outputs: ' + ', '.join(f'{i}={m["name"]}' for i, m in enumerate(displays, 1)))
    choice = int(ask_option('Intended output number',
                tuple(str(i) for i in range(1, len(displays)+1)), '1'))
    return displays[choice-1]


def _store_intent(cp, kind, mon, anchor, margin_x, margin_y):
    if not cp.has_section('layout'):
        cp.add_section('layout')
    for suffix, value in (('output', mon['name']), ('anchor', anchor),
                          ('margin_x', margin_x), ('margin_y', margin_y)):
        cp['layout'][kind + '_' + suffix] = str(value)


def wizard(cp, widget='all'):
    displays, source = monitors()
    show_screens(displays, source)
    if not displays:
        print('Monitor detection was unavailable.')
        if ask_option('Enter monitor geometry manually now? yes/no', ('yes', 'no'), 'yes') == 'no':
            print('No changes made.')
            return None
        displays = enter_manual_monitors()
        save_manual_monitors(displays)
    print('\nChoose each widget, output, scale and one of the nine anchors.')
    print('Positions are global X11/XWayland virtual-desktop coordinates.')
    for kind in kinds_for(widget):
        print('\n' + {'prayer':'PRAYER TIMES', 'date':'DATE / HIJRI',
                       'weather':'WEATHER', 'sun_moon':'CELESTIAL ASTROLABE'}[kind])
        mon = _choose_monitor(displays)
        old = cp.getfloat('appearance', kind + '_scale')
        size_mode = ask_option('Size: 1 = keep, 2 = custom, 3 = fit within percentage',
                              ('1','2','3'), '1')
        if size_mode == '1':
            scale = old
        elif size_mode == '2':
            scale = ask_number('Scale (1 = original)', old, .3, 3)
        else:
            width_pct = ask_number('Maximum share of output width (%)', 90, 1, 100)
            height_pct = ask_number('Maximum share of output height (%)', 35, 1, 100)
            base_w, base_h = canvas_sizes()[kind]
            fit = min(mon['w'] * width_pct / 100 / base_w,
                      mon['h'] * height_pct / 100 / base_h, 3)
            if fit < .3:
                print('Requested area is too small; minimum supported scale 0.3 is used.')
            scale = max(.3, math.floor(fit * 1000) / 1000)
        w, h = scaled_size(kind, scale)
        print(f'Design canvas: {w}x{h} on intended output {mon["name"]}')
        print('Anchors: ' + ', '.join(f'{i}={a}' for i, a in enumerate(ANCHORS, 1)))
        anchor = ANCHORS[int(ask_option('Anchor number',
                        tuple(str(i) for i in range(1, 10)),
                        '1' if kind in ('date', 'weather', 'sun_moon') else '7')) - 1]
        mx = int(ask_number('Horizontal margin (logical pixels)', 20, 0, 10000))
        my = int(ask_number('Vertical margin (logical pixels)', 20, 0, 10000))
        x, y = calculate_position(mon, kind, scale, anchor, mx, my)
        if intersection((x, y, w, h), mon) < w*h:
            print('WARNING: requested Conky window cannot fit at that anchor/margin.')
            if ask_option('Keep this placement? yes/no', ('yes','no'), 'no') == 'no':
                print('Previous widget settings retained.')
                continue
        cp['appearance'][kind + '_scale'] = str(round(scale, 3))
        cp['placement'][kind + '_x'] = str(x)
        cp['placement'][kind + '_y'] = str(y)
        _store_intent(cp, kind, mon, anchor, mx, my)
        print(f'Placed {kind}: {mon["name"]} {anchor}: x={x}, y={y}, scale={scale:.3f}')
    return cp


def reflow(cp, widget='all'):
    """Recalculate global X11 offsets from saved output/anchor/margins."""
    displays, source = monitors()
    show_screens(displays, source)
    if not displays:
        raise ValueError('No monitors detected; use --manual-screens or check KScreen.')
    lookup = {m['name']: m for m in displays}
    updates = {}
    for kind in kinds_for(widget):
        plan = _layout_intent(cp, kind)
        if not plan:
            raise ValueError(f'{kind}: no saved anchor/output. Run --layout first.')
        output, anchor, mx, my = plan
        if output not in lookup:
            raise ValueError(f'{kind}: intended output {output!r} not found. Run --layout.')
        scale = cp.getfloat('appearance', kind + '_scale')
        mon = lookup[output]
        xy = calculate_position(mon, kind, scale, anchor, mx, my)
        w, h = scaled_size(kind, scale)
        if intersection((*xy, w, h), mon) != w*h:
            raise ValueError(f'{kind}: no longer fits {output}; run --layout.')
        updates[kind] = xy
    for kind, (x, y) in updates.items():
        cp['placement'][kind + '_x'] = str(x)
        cp['placement'][kind + '_y'] = str(y)
        print(f'Reflowed {kind}: {x},{y} (global X11/XWayland position)')
    return cp


def _profile_path(name):
    if not re.fullmatch(r'[A-Za-z0-9_-]{1,40}', name):
        raise ValueError('Layout name must be 1-40 letters, numbers, underscores or hyphens.')
    return LAYOUT_DIR / (name + '.ini')


def _selected_layout_keys(widget):
    kinds = kinds_for(widget)
    return (('appearance', [kind + '_scale' for kind in kinds]),
            ('layout', [kind + '_' + attr for kind in kinds
                        for attr in ('output', 'anchor', 'margin_x', 'margin_y')]))


def save_layout(cp, name, widget='all'):
    """Save declarative layout, not stale, machine-dependent numeric offsets."""
    for kind in kinds_for(widget):
        if _layout_intent(cp, kind) is None:
            raise ValueError(f'{kind}: configure with --layout before saving a preset.')
    path = _profile_path(name)
    LAYOUT_DIR.mkdir(parents=True, exist_ok=True)
    saved = configparser.ConfigParser(interpolation=None)
    if path.exists():
        saved.read(path, encoding='utf-8')
    # Rebuild, don't retain stale numeric placement keys in an old preset.
    if saved.has_section('placement'):
        saved.remove_section('placement')
    for section, keys in _selected_layout_keys(widget):
        if not saved.has_section(section):
            saved.add_section(section)
        for key in keys:
            if cp.has_option(section, key):
                saved[section][key] = cp[section][key]
    with path.open('w', encoding='utf-8') as file:
        file.write('# X11/XWayland layout: canvas scale + named output/anchor intent.\n')
        saved.write(file)
    return path


def use_layout(cp, name, widget='all'):
    """Apply an intent preset and resolve new offsets for *current* KScreen."""
    path = _profile_path(name)
    if not path.is_file():
        raise ValueError(f'Layout not found: {name}. Saved layouts: {", ".join(list_layouts()) or "none"}')
    saved = configparser.ConfigParser(interpolation=None)
    saved.read(path, encoding='utf-8')
    for kind in kinds_for(widget):
        for suffix in ('output', 'anchor', 'margin_x', 'margin_y'):
            if not saved.has_option('layout', kind + '_' + suffix):
                raise ValueError(f'Preset {name}: missing {kind}_{suffix}; recreate it with --layout.')
        if not saved.has_option('appearance', kind + '_scale'):
            raise ValueError(f'Preset {name}: missing {kind}_scale.')
    for section, keys in _selected_layout_keys(widget):
        if not cp.has_section(section):
            cp.add_section(section)
        for key in keys:
            if saved.has_option(section, key):
                cp[section][key] = saved[section][key]
    return reflow(cp, widget)


def list_layouts():
    return sorted(p.stem for p in LAYOUT_DIR.glob('*.ini')) if LAYOUT_DIR.exists() else []
