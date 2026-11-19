# Conky — Four Transparent Widgets (Unified Edition)

**One folder, one `settings.ini`, one installer, and one layout wizard.** This combines the three source archives into four independently placed, independently scaled Conky windows for Linux/KDE Plasma:

| Widget | Source preserved | Config + renderer | Scale and placement keys |
|---|---|---|---|
| **Prayer Times** | `Archive.zip` (original prayer logic, countdown, hover, Athan) | `conky_prayer_times.conf` → `Prayer_Times.lua` | `prayer_scale`, `prayer_x`, `prayer_y` |
| **Gregorian/Hijri Date & Clock** | `Archive.zip` (original Hijri/Maghrib rollover) | `conky_date.conf` → `Hijri_Date.lua` | `date_scale`, `date_x`, `date_y` |
| **Weather v2** | `Conky_Weather_SunMoon_v2_Patch.zip` (weather visuals and sizing/positioning) | `conky_weather.conf` → `Weather.lua` | `weather_scale`, `weather_x`, `weather_y` |
| **Celestial Astrolabe** | `Celestial_Astrolabe_Transparent_Complete_Project.zip` (latest fully transparent moon design) | `conky_sun_moon.conf` → `Sun_Moon_Astrolabe.lua` | `sun_moon_scale`, `sun_moon_x`, `sun_moon_y` |

**There is no old Sun/Moon widget in this project.** The Astrolabe is the only sun/moon renderer and is the one launched by `start.sh`/KDE Autostart. It has **no rectangular background, card, shadow or backdrop**. All four read the *same* `appearance.font`, default **ITC Avant Garde Pro XLt** (the font itself is **not** distributed). Weather icons are in `assets/weather/`; the Astrolabe moon is drawn in Cairo and does not need the old `assets/moon/` images.

## 1. Install

Requires Linux, Python 3, Conky compiled with Lua and Cairo, and (for prayer hover) Conky mouse-events support. For the optional Athan, install `paplay` and provide your own `athan.wav`. Use `fc-match 'ITC Avant Garde Pro XLt'` to verify the font is installed or choose an installed font in `settings.ini`. No Python pip packages are required.

Extract the ZIP, open a terminal **inside the extracted `Conky_Unified_Four_Widgets` folder**, and run:

```bash
bash install.sh
```

The installer:

1. Copies the four-widget project to **`~/.config/conky/`** (or `$XDG_CONFIG_HOME/conky`). If a Conky directory exists, first creates a full timestamped backup alongside it.
2. **Preserves your existing `settings.ini` by default** and upgrades it by adding missing weather/Astrolabe keys. Existing prayer/Hijri location, behavior, sizes, and placement remain intact. `--reset-settings` explicitly replaces those values with the bundled defaults (after backup).
3. Moves explicit `sun_moon_astrolabe_x/y` coordinates from an earlier alternate Astrolabe installation into the canonical `sun_moon_x/y` coordinates, if you had set them. Otherwise, it preserves `sun_moon_x/y` from the older Weather v2 widget.
4. Replaces the old moon renderer with the Astrolabe, removes superseded known moon files from the installed folder **after backing them up**, and installs a single KDE/XDG Autostart entry called `conky-prayer-clock.desktop` for all four widgets.
5. In an interactive terminal, offers to launch the shared setup wizard for **all four**. On noninteractive installations, run the wizard yourself using the commands below.

Want to test first without replacing any installed files? You can run the scripts **directly in the extracted folder**, and keep them separate from `~/.config/conky`:

```bash
python3 configure.py --check
python3 configure.py --layout --widget all
bash start.sh
```

An installed Conky instance launched from the earlier folder may still be running after installing. Use the safe restart command from the installed directory rather than launching a second copy. If you previously created any *other* Autostart entries for separate widgets, disable those to avoid duplicates at login.

Optional installation flags:

```bash
bash install.sh --no-autostart --no-configure   # install but do not change autostart / prompt
bash install.sh --reset-settings               # reset configuration to bundled defaults
```

## 2. One shared configuration

The **only settings file** to maintain is `~/.config/conky/settings.ini` after installation. You can edit it by hand, or run:

```bash
python3 ~/.config/conky/configure.py                  # interactive menu, defaults to all four
python3 ~/.config/conky/configure.py --widget all     # all settings + all widgets
python3 ~/.config/conky/configure.py --widget prayer  # Prayer only
python3 ~/.config/conky/configure.py --widget date    # Hijri/clock only
python3 ~/.config/conky/configure.py --widget weather # Weather v2 only
python3 ~/.config/conky/configure.py --widget sun_moon # transparent Astrolabe only
python3 ~/.config/conky/configure.py --widget shared # shared location, prayer method and font
python3 ~/.config/conky/configure.py --widget new    # Weather + Astrolabe (legacy shortcut)
python3 ~/.config/conky/configure.py --widget both   # Prayer + Hijri (legacy shortcut)
```

Use `--widget all` for the initial setup. Press **Enter** at any wizard prompt to keep the displayed value. The editor preserves the comments in the INI file. The interactive wizard asks whether to keep existing placement, **auto-place by monitor/corner**, or enter absolute **X/Y** manually.

The four independent scales are `prayer_scale`, `date_scale`, `weather_scale`, `sun_moon_scale` (0.3–3.0). At scale 1.0, expected Conky bounds are **1100×255**, **700×290**, **340×172**, and **416×432**, respectively. These are allocated window sizes; the Astrolabe has a transparent window inside those bounds. `weather_icon_x`, `weather_icon_y`, and `weather_icon_size` move/size only the weather image without scaling the widget text.

`font` is shared across all four. Default `ITC Avant Garde Pro XLt` is used in every Cairo renderer. If your computer doesn't have it, set a font reported by `fc-list` / `fc-match`.

The original prayer and Hijri configuration remains available: `location.mode` (`city` or `coordinates`), city/country or lat/lon, Aladhan `method`, `school`, `midnight_mode`, `hijri_offset_days`, `elapsed_minutes`, `hover_area`, `hover_failsafe_seconds`, `hover_debug_outline`, and `athan_enabled`. The weather worker uses the **same** location and `weather_refresh_minutes` (5–180).

**Important timezone requirement:** The source prayer/clock logic interprets the selected location's prayer clock times using your computer's local timezone. Keep your system timezone aligned with your configured location (check `timedatectl`). For remote locations in other timezones, displayed prayer boundaries may be wrong. Hijri changes at the selected location's Maghrib. Compare prayer times with your mosque when necessary.

## 3. Place all four anywhere on your monitors

The layout wizard from `Archive.zip` + Weather v2 now works across the four widgets and understands the **larger Astrolabe footprint**:

```bash
python3 ~/.config/conky/configure.py --screens
python3 ~/.config/conky/configure.py --layout --widget all
python3 ~/.config/conky/configure.py --check-layout --widget all
```

For each widget separately, the assistant asks which monitor to use, what scale to apply, which anchor to use (top-left, center, bottom-right, etc.) and what margins to keep. It writes the chosen `*_scale` and `*_x/*_y` directly to `settings.ini`. Different widgets may be on different monitors. It detects geometry with KDE's `kscreen-doctor -o`/`-j`, then XRandR on X11, or falls back to manually saved geometry. On Wayland, Conky/XWayland coordinates can behave differently from the compositor's logical geometry; visually verify positions.

If automatic monitor detection fails:

```bash
python3 ~/.config/conky/configure.py --manual-screens
python3 ~/.config/conky/configure.py --layout --widget all
```

To place **just one** widget without changing the other three:

```bash
python3 ~/.config/conky/configure.py --layout --widget sun_moon
python3 ~/.config/conky/configure.py --check-layout --widget sun_moon
```

To keep separate *full-desktop* and *compact* positioning/scaling presets (presets do **not** change location or prayer behavior):

```bash
python3 ~/.config/conky/configure.py --save-layout full --widget all
python3 ~/.config/conky/configure.py --save-layout compact --widget all
python3 ~/.config/conky/configure.py --list-layouts
python3 ~/.config/conky/configure.py --use-layout full --widget all
python3 ~/.config/conky/configure.py --use-layout compact --widget all
```

You can also save/restore a preset for only `weather`, `date`, `prayer` or `sun_moon`. Layouts live in `~/.config/conky/layouts/` and saved monitor geometry in `monitor_geometry.json`. These files are not overwritten during installation.

## 4. Launch and restart (avoid duplicate windows)

```bash
bash ~/.config/conky/start.sh                    # launch all four, e.g. at login
bash ~/.config/conky/start.sh --new-only         # Weather + Astrolabe
bash ~/.config/conky/start.sh --existing-only    # Prayer + Hijri
bash ~/.config/conky/start.sh --widget sun_moon  # only the Astrolabe
```

`start.sh` starts new Conky processes. **After changing settings, use `restart.py`**, which stops only matching Conky instances from this installation before launching them again, without calling `killall conky` or disturbing unrelated Conky programs:

```bash
python3 ~/.config/conky/restart.py                       # safe restart all four
python3 ~/.config/conky/restart.py --widget sun_moon     # restart only Astrolabe
python3 ~/.config/conky/restart.py --widget new          # restart Weather + Astrolabe
python3 ~/.config/conky/restart.py --widget prayer       # restart only Prayer
python3 ~/.config/conky/restart.py --list                # list matching processes
python3 ~/.config/conky/restart.py --stop-only           # stop only this installation
```

The Weather v2 command `python3 restart_new.py` still works as a **small compatibility alias** for `restart.py --widget new`; the implementation is centralized in `restart.py`. After migration, the old `start_astrolabe.sh` and `conky_sun_moon_astrolabe.conf` are not needed. The canonical `conky_sun_moon.conf` **always** loads the latest transparent Astrolabe.

For live Conky errors in a terminal, run a single widget in the foreground:

```bash
conky -c ~/.config/conky/conky_sun_moon.conf
```

Press Ctrl+C to stop a foreground instance.

## 5. Data sources, offline behavior and troubleshooting

**Prayer + Hijri:** `prayer_fetch.py` and `Prayer_Data.lua` use the Aladhan API and local cache. The Hijri rollover is at Maghrib. Prayer hover, countdown, Athan behavior, and fallback rules are unchanged from `Archive.zip`. For detailed hover-zone settings see `HOVER_ZONE.md`. Athan audio (`athan.wav`) is **not included**; if you have a personal file, place it beside the other scripts and enable `athan_enabled = yes`. `paplay` is used for playback.

**Weather:** `weather_fetch.py` uses Open-Meteo (no API key for the documented noncommercial personal endpoint), updating an atomic cache in `~/.cache/conky-sun-weather/`. The widget shows temperature, high, low, humidity, and the bundled WeatherDesk-style icon. The v2 fix for weather forecast timezone/day matching is preserved. It will display a loading message until weather data is fetched.

**Astrolabe:** Uses the same shared weather data cache and prayer cache for sunrise/sunset, with prayer Sunrise/Maghrib taking precedence when available. The central cratered moon shows the current *lunar phase* via local astronomical approximation. The blue nighttime orbit indicator shows **night progress**, not Moon altitude. The solar-noon mark, watch ticks, sunrise/sunset labels, day/nigh lengths, and 24-hour gradient timeline are shown without a card background. If a valid sun schedule isn't available, the moon can still render while sunrise/sunset telemetry waits.

Diagnostics:

```bash
python3 ~/.config/conky/configure.py --check
python3 ~/.config/conky/configure.py --check-layout --widget all
python3 ~/.config/conky/doctor.py
python3 ~/.config/conky/doctor.py --fetch         # optional live prayer data request
python3 ~/.config/conky/doctor.py --weather-fetch # optional live weather request
# Inspect fetch error logs:
tail -n 40 ~/.cache/conky-prayer-times/fetch.log
tail -n 40 ~/.cache/conky-sun-weather/fetch.log
```

**If a widget is missing:** confirm the Conky build has Lua/Cairo support (`conky --version`); check the font installation, the placement coordinates, the process list (`restart.py --list`) and the fetch log. Conky's Lua settings are loaded at startup; restart after changing location/scale/font/placement. The weather cache refreshes without restarting the window.

## 6. Canonical project organization

```text
Conky_Unified_Four_Widgets/
├── README.md, HOVER_ZONE.md
├── settings.ini                         # one shared editable configuration
├── install.sh, start.sh, restart.py     # installer / launcher / safe restart
├── restart_new.py                       # tiny compatibility alias only
├── configure.py, layout.py             # four-widget setup and monitor wizard
├── upgrade_settings.py, doctor.py      # migration and diagnostics
├── Settings.lua, Surface.lua           # shared Conky helpers
├── Prayer_Data.lua, prayer_fetch.py     # Aladhan prayer data/cache
├── Weather_Data.lua, weather_fetch.py   # shared Open-Meteo weather/sun cache
├── Hover_State.lua                      # original prayer hover tracking
├── Prayer_Times.lua, conky_prayer_times.conf
├── Hijri_Date.lua, conky_date.conf
├── Weather.lua, conky_weather.conf
├── Sun_Moon_Astrolabe.lua, conky_sun_moon.conf
└── assets/weather/*.png                 # icon assets required by Weather v2
```

The obsolete Moon v2 `Sun_Moon.lua`, eight `assets/moon/` PNGs, alternate Astrolabe launcher/config, and redundant version-specific README files are intentionally excluded. **Only the four current widget implementations are packaged.** Original baseline prayer/Hijri code and the Weather v2 data/fetch behavior have not been rewritten.
