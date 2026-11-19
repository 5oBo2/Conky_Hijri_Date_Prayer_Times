#!/usr/bin/env python3
"""Idempotently migrate baseline/Weather-v2/Celestial settings to one settings.ini.

Preserves user comments and current values. If the prior alternative Astrolabe
had explicit sun_moon_astrolabe_x/y placement, migrate it to sun_moon_x/y because
there is now exactly one (Astrolabe) Moon widget.
"""
import configparser
from pathlib import Path
import re

CONFIG = Path(__file__).resolve().with_name('settings.ini')
OPTIONS = {
    'appearance': {
        'weather_scale': '1.0',
        'sun_moon_scale': '1.0',
        'weather_icon_x': '174',
        'weather_icon_y': '-13',
        'weather_icon_size': '137',
    },
    'behavior': {'weather_refresh_minutes': '20'},
    'placement': {
        'weather_x': '40', 'weather_y': '40',
        'sun_moon_x': '420', 'sun_moon_y': '40',
    },
}
SECTION_RE = re.compile(r'^\s*\[([A-Za-z_][\w]*)\]\s*$')
KEY_RE = re.compile(r'^(\s*)([\w]+)(\s*=\s*)([^\r\n]*)(\r?\n?)$')


def upgrade(path=CONFIG):
    path = Path(path)
    original = path.read_text(encoding='utf-8')
    cp = configparser.ConfigParser(interpolation=None,
                                   inline_comment_prefixes=('#', ';'))
    cp.read_string(original)
    # Only migrate explicit alternative-widget coordinates. Otherwise keep
    # whatever existing sun_moon_x/y the user already chose.
    legacy_coords = {}
    for axis in ('x', 'y'):
        old = f'sun_moon_astrolabe_{axis}'
        if cp.has_option('placement', old):
            legacy_coords[f'sun_moon_{axis}'] = cp.get('placement', old)
    output = []
    changes = []
    section = None
    seen = set()

    def missing_for(section_name):
        if section_name not in OPTIONS:
            return
        for key, value in OPTIONS[section_name].items():
            if (section_name, key) not in seen:
                if output and not output[-1].endswith('\n'):
                    output.append('\n')
                value = legacy_coords.get(key, value) if section_name == 'placement' else value
                output.append(f'{key} = {value}\n')
                changes.append(f'added {section_name}.{key}')
                seen.add((section_name, key))

    for line in original.splitlines(keepends=True):
        match = SECTION_RE.match(line.strip())
        if match:
            missing_for(section)
            section = match.group(1).lower()
            seen.add(('section', section))
            output.append(line)
            continue
        item = KEY_RE.match(line)
        if item and section:
            key = item.group(2).lower()
            if section == 'placement' and key in ('sun_moon_astrolabe_x', 'sun_moon_astrolabe_y'):
                changes.append(f'removed legacy placement.{key}')
                continue
            seen.add((section, key))
            if section == 'placement' and key in legacy_coords:
                new_value = legacy_coords[key]
                if item.group(4).strip() != new_value:
                    line = ''.join((item.group(1), item.group(2), item.group(3),
                                    new_value, item.group(5) or '\n'))
                    changes.append(f'migrated placement.{key} from Astrolabe placement')
        output.append(line)
    missing_for(section)
    for section_name in OPTIONS:
        if ('section', section_name) not in seen:
            if output and not output[-1].endswith('\n'):
                output.append('\n')
            output.append(f'\n[{section_name}]\n')
            for key, value in OPTIONS[section_name].items():
                value = legacy_coords.get(key, value) if section_name == 'placement' else value
                output.append(f'{key} = {value}\n')
                changes.append(f'added {section_name}.{key}')
    result = ''.join(output)
    if result != original:
        temporary = path.with_name(path.name + '.tmp')
        temporary.write_text(result, encoding='utf-8')
        temporary.replace(path)
    return changes


if __name__ == '__main__':
    changes = upgrade()
    print('Settings migration: ' + (', '.join(changes) or 'already up-to-date'))
