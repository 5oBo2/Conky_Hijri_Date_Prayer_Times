#!/usr/bin/env python3
"""Interactive editor for the shared settings.ini (no extra dependencies).

Run `python3 configure.py`, press Enter to retain any existing value.
Alternatively edit settings.ini directly; all four widgets read that file.
"""

import argparse
import configparser
import pathlib
import re
import sys

import layout

PATH = pathlib.Path(__file__).resolve().with_name("settings.ini")


def read():
    cp = configparser.ConfigParser(
        interpolation=None, inline_comment_prefixes=("#", ";")
    )
    if not cp.read(PATH, encoding="utf-8"):
        raise ValueError(f"Could not find {PATH}")
    return cp


def validate(cp):
    loc = cp["location"]
    if loc.get("mode") not in ("city", "coordinates"):
        raise ValueError("location.mode must be city or coordinates")
    if loc["mode"] == "city":
        if not loc.get("city", "").strip() or not loc.get("country", "").strip():
            raise ValueError("City and country are required for city mode")
    else:
        latitude, longitude = float(loc["latitude"]), float(loc["longitude"])
        if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
            raise ValueError("Coordinates out of range")
    method = loc.get("method", "auto")
    if method != "auto" and int(method) < 0:
        raise ValueError("Invalid method ID")
    if loc.getint("school") not in (0, 1):
        raise ValueError("school must be 0 or 1")
    if loc.getint("midnight_mode") not in (0, 1):
        raise ValueError("midnight_mode must be 0 or 1")
    for key in ("prayer_scale", "date_scale", "weather_scale", "sun_moon_scale"):
        scale = cp.getfloat("appearance", key)
        if not 0.3 <= scale <= 3:
            raise ValueError(f"{key} must be between 0.3 and 3")
    if cp.getint("behavior", "elapsed_minutes") < 0:
        raise ValueError("elapsed_minutes must be nonnegative")
    if cp.getint("behavior", "hover_failsafe_seconds", fallback=5) < 0:
        raise ValueError("hover_failsafe_seconds must be nonnegative")
    if cp.getint("behavior", "weather_hover_failsafe_seconds", fallback=4) < 0:
        raise ValueError("weather_hover_failsafe_seconds must be nonnegative")
    if cp.get("behavior", "hover_area", fallback="content") not in (
        "content",
        "window",
        "fajr_sunrise",
    ):
        raise ValueError("hover_area must be content, window or fajr_sunrise")
    cp.getboolean("behavior", "hover_debug_outline", fallback=False)
    cp.getint("behavior", "hijri_offset_days")
    cp.getboolean("behavior", "athan_enabled")
    if not 5 <= cp.getint("behavior", "weather_refresh_minutes") <= 180:
        raise ValueError("weather_refresh_minutes must be between 5 and 180")
    for key in ("weather_icon_x", "weather_icon_y"):
        value = cp.getfloat(
            "appearance", key, fallback=174 if key.endswith("_x") else -13
        )
        if not -400 <= value <= 700:
            raise ValueError(f"{key} must be between -400 and 700")
    if not 40 <= cp.getfloat("appearance", "weather_icon_size", fallback=137) <= 400:
        raise ValueError("weather_icon_size must be between 40 and 400")
    cp.getboolean("appearance", "clock_weather_combined", fallback=False)
    if not 40 <= cp.getfloat("appearance", "combined_clock_size", fallback=145) <= 300:
        raise ValueError("combined_clock_size must be between 40 and 300")
    if (
        not 20
        <= cp.getfloat("appearance", "combined_hover_temp_size", fallback=82)
        <= 250
    ):
        raise ValueError("combined_hover_temp_size must be between 20 and 250")
    if (
        not 20
        <= cp.getfloat("appearance", "combined_weather_icon_size", fallback=72)
        <= 250
    ):
        raise ValueError("combined_weather_icon_size must be between 20 and 250")
    for key in ("combined_weather_icon_dx", "combined_weather_icon_dy"):
        value = cp.getfloat("appearance", key, fallback=0)
        if not -300 <= value <= 300:
            raise ValueError(f"{key} must be between -300 and 300")
    if not cp.get("appearance", "font").strip():
        raise ValueError("font must not be empty")
    for key in (
        "prayer_x",
        "prayer_y",
        "date_x",
        "date_y",
        "weather_x",
        "weather_y",
        "sun_moon_x",
        "sun_moon_y",
    ):
        cp.getint("placement", key)


def prompt(label, value):
    new = input(f"{label} [{value}]: ").strip()
    return new if new else value


def change(cp, section, key, label):
    cp[section][key] = prompt(label, cp[section][key])


def save_preserving_comments(cp):
    # Keep headings and explanations in settings.ini when the wizard writes it.
    # Keys are only replaced within their matching section.
    lines = PATH.read_text(encoding="utf-8").splitlines(keepends=True)
    section = None
    output = []
    for line in lines:
        match = re.match(r"^\s*\[([\w_]+)\]\s*$", line.strip())
        if match:
            section = match.group(1)
        item = re.match(r"^(\s*([\w_]+)\s*=\s*)([^\r\n]*)(\r?\n?)$", line)
        if item and section and section in cp and item.group(2) in cp[section]:
            value = cp[section][item.group(2)]
            line = item.group(1) + value + (item.group(4) or "\n")
        output.append(line)
    tmp = PATH.with_suffix(".ini.tmp")
    tmp.write_text("".join(output), encoding="utf-8")
    tmp.replace(PATH)


def main():
    parser = argparse.ArgumentParser(description="Configure the Conky widgets")
    parser.add_argument(
        "--widget",
        choices=(
            "prayer",
            "date",
            "weather",
            "sun_moon",
            "new",
            "both",
            "all",
            "shared",
        ),
        help="configure any widget or all four (prompt if omitted)",
    )
    parser.add_argument("--show", action="store_true", help="print current values")
    parser.add_argument("--check", action="store_true", help="validate settings")
    parser.add_argument(
        "--screens", action="store_true", help="list detected monitor geometry"
    )
    parser.add_argument(
        "--layout",
        action="store_true",
        help="interactive monitor-aware placement assistant",
    )
    parser.add_argument(
        "--manual-screens",
        action="store_true",
        help="enter monitor coordinates manually and save for later layout checks",
    )
    parser.add_argument(
        "--check-layout",
        action="store_true",
        help="estimate widget bounds and warn about clipping/offscreen placement",
    )
    parser.add_argument(
        "--save-layout",
        metavar="NAME",
        help="save current sizes/positions as a named preset",
    )
    parser.add_argument(
        "--use-layout",
        metavar="NAME",
        help="activate saved sizes/positions, leaving location and behavior alone",
    )
    parser.add_argument(
        "--list-layouts", action="store_true", help="list saved layout presets"
    )
    args = parser.parse_args()
    if args.widget == "shared" and (
        args.layout or args.check_layout or args.save_layout or args.use_layout
    ):
        parser.error("--widget shared is for the configuration wizard, not layouts")
    from upgrade_settings import upgrade

    upgrade()
    cp = read()
    if args.screens:
        displays, source = layout.monitors()
        layout.show_screens(displays, source)
        return
    if args.manual_screens:
        displays = layout.enter_manual_monitors()
        layout.save_manual_monitors(displays)
        print("Saved screen geometry for the layout wizard and future checks.")
        return
    if args.check_layout:
        validate(cp)
        layout.check_layout(cp, args.widget or "all")
        return
    if args.list_layouts:
        print("Saved layouts: " + (", ".join(layout.list_layouts()) or "(none)"))
        return
    if args.save_layout:
        validate(cp)
        path = layout.save_layout(cp, args.save_layout, args.widget or "all")
        print(f"Saved layout: {path}")
        return
    if args.use_layout:
        layout.use_layout(cp, args.use_layout, args.widget or "all")
        validate(cp)
        save_preserving_comments(cp)
        print(
            f"Activated layout {args.use_layout} for {args.widget or 'both'}. Restart affected Conky instances."
        )
        return
    if args.layout:
        if layout.wizard(cp, args.widget or "all") is None:
            return
        validate(cp)
        save_preserving_comments(cp)
        print(
            f"Saved monitor-aware placement for {args.widget or 'both'}. Restart affected Conky instances."
        )
        return
    if args.show:
        for section in cp.sections():
            print(f"[{section}]")
            for key, value in cp.items(section):
                print(f"  {key} = {value}")
        return
    if args.check:
        validate(cp)
        print("settings.ini: valid")
        return

    print("\nConky widget setup")
    print(
        "Press Enter to keep the displayed value. Changes are written to settings.ini;"
    )
    print("you may edit settings.ini by hand at any time.\n")
    target = args.widget or prompt(
        "Configure: prayer / date / weather / sun_moon / new / both / all / shared",
        "all",
    )
    target = {"1": "prayer", "2": "date", "3": "shared", "4": "both"}.get(
        target, target
    )
    if target not in (
        "prayer",
        "date",
        "weather",
        "sun_moon",
        "new",
        "shared",
        "both",
        "all",
    ):
        raise ValueError(
            "Choose prayer, date, weather, sun_moon, new, shared, both, or all"
        )

    if target in ("both", "all", "shared"):
        print("\nShared settings (location and font affect all four widgets)")
        current_mode = cp["location"]["mode"]
        choice = prompt(
            "Location: 1 = city/country, 2 = coordinates",
            "1" if current_mode == "city" else "2",
        )
        if choice not in ("1", "2"):
            raise ValueError("Please choose 1 or 2")
        cp["location"]["mode"] = "city" if choice == "1" else "coordinates"
        if choice == "1":
            for key, label in [
                ("city", "City"),
                ("country", "Country"),
                ("state", "State/region (optional)"),
            ]:
                change(cp, "location", key, label)
        else:
            change(cp, "location", "latitude", "Latitude")
            change(cp, "location", "longitude", "Longitude")
        change(cp, "location", "method", "Prayer calculation method (auto or ID)")
        change(cp, "location", "school", "Asr school (0 = standard, 1 = Hanafi)")
        change(cp, "location", "midnight_mode", "Midnight convention (0 or 1)")
        change(cp, "appearance", "font", "Font (must be installed)")

    if target in ("both", "all", "prayer"):
        print("\nPrayer widget only")
        change(cp, "appearance", "prayer_scale", "Prayer widget scale (1.0 = original)")
        change(
            cp, "behavior", "elapsed_minutes", "Auto-show elapsed minutes after Athan"
        )
        change(cp, "behavior", "hover_area", "Hover area (fajr_sunrise/content/window)")
        change(
            cp,
            "behavior",
            "hover_failsafe_seconds",
            "Hover failsafe seconds on Wayland (0 = disable)",
        )
        change(
            cp, "behavior", "hover_debug_outline", "Show hover zone outline (yes/no)"
        )
        change(cp, "behavior", "athan_enabled", "Play Athan audio (yes/no)")

    if target in ("both", "all", "date"):
        print("\nDate/Hijri widget only")
        change(
            cp, "appearance", "date_scale", "Date/clock widget scale (1.0 = original)"
        )
        change(
            cp,
            "appearance",
            "clock_weather_combined",
            "Combine Clock | Weather inside Date widget (yes/no)",
        )
        change(cp, "behavior", "hijri_offset_days", "Hijri date offset (days)")

    if target in ("new", "all", "weather"):
        print("\nWeather widget")
        change(cp, "appearance", "weather_scale", "Weather scale (1.0 = original)")
        change(
            cp,
            "appearance",
            "weather_icon_x",
            "Weather icon X inside widget (left = smaller)",
        )
        change(
            cp,
            "appearance",
            "weather_icon_y",
            "Weather icon Y inside widget (up = smaller)",
        )
        change(
            cp,
            "appearance",
            "weather_icon_size",
            "Weather icon size in pixels (before widget scale)",
        )
        change(
            cp,
            "appearance",
            "combined_weather_icon_size",
            "Combined mode weather icon size",
        )
        change(
            cp,
            "appearance",
            "combined_weather_icon_dx",
            "Combined mode icon horizontal nudge",
        )
        change(
            cp,
            "appearance",
            "combined_weather_icon_dy",
            "Combined mode icon vertical nudge",
        )
        change(
            cp,
            "behavior",
            "weather_hover_failsafe_seconds",
            "Combined weather hover failsafe (seconds)",
        )
        change(
            cp, "behavior", "weather_refresh_minutes", "Weather refresh (5..180 min)"
        )

    if target in ("new", "all", "sun_moon"):
        print("\nCelestial Astrolabe (transparent Sun / Moon)")
        change(
            cp, "appearance", "sun_moon_scale", "Astrolabe scale (1.0 = design size)"
        )

    if target != "shared":
        print("\nPosition / screen layout")
        placement_method = prompt(
            "Position: keep / auto (monitor and corner) / manual (X/Y)", "keep"
        ).lower()
        if placement_method == "auto":
            if layout.wizard(cp, target) is None:
                print("Positioning cancelled; retaining previous X/Y settings.")
        elif placement_method == "manual":
            for kind in ("prayer", "date", "weather", "sun_moon"):
                if target == "both" and kind not in ("prayer", "date"):
                    continue
                if target == "new" and kind not in ("weather", "sun_moon"):
                    continue
                if target not in ("both", "new", "all", kind):
                    continue
                for coordinate in ("x", "y"):
                    change(
                        cp,
                        "placement",
                        f"{kind}_{coordinate}",
                        f"{kind.capitalize()} {coordinate.upper()}",
                    )
        elif placement_method != "keep":
            raise ValueError("Position method must be keep, auto or manual")
    validate(cp)
    save_preserving_comments(cp)
    print(
        f"\nSaved {target} settings to {PATH}. You can edit this file directly later."
    )
    print("Apply changes with: python3 restart.py (or --widget NAME)")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, ValueError, configparser.Error) as exc:
        print(f"Configuration error: {exc}", file=sys.stderr)
        sys.exit(2)
    except (EOFError, KeyboardInterrupt):
        print("\nCancelled without saving.", file=sys.stderr)
        sys.exit(1)
