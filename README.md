# Conky: four independent widgets

A small, **X11/XWayland-backed** Conky project for Fedora/KDE Plasma, with one **active** `settings.ini`, optional named full-settings profiles, and four **independent windows**:

| Widget | Rendering files | Independent size / placement |
| --- | --- | --- |
| Prayer Times | `widgets/Prayer_Times.lua`, `configs/conky_prayer_times.conf` | `prayer_scale`, `prayer_x`, `prayer_y` |
| Clock + Gregorian/Hijri Date | `widgets/Hijri_Date.lua`, `configs/conky_date.conf` | `date_scale`, `date_x`, `date_y` |
| Weather | `widgets/Weather.lua`, `configs/conky_weather.conf` | `weather_scale`, `weather_x`, `weather_y` |
| Celestial Astrolabe | `widgets/Sun_Moon_Astrolabe.lua`, `configs/conky_sun_moon.conf` | `sun_moon_scale`, `sun_moon_x`, `sun_moon_y` |

Every window is launched separately, and changing the Date display mode **never** hides, moves, resizes, stops or changes the standalone Weather widget. Both weather displays read shared Open-Meteo data, but draw independently.

## Supported runtime: X11/XWayland on Plasma Wayland

**Temporary architectural decision (2026-11-23):** Keep KDE Plasma on
Wayland, but render all four Conky windows through XWayland with Conky's X11
backend (`out_to_x = true`, `out_to_wayland = false`). The installed Conky
1.24.2's native Wayland backend showed stop timeouts, disappearing desktop
widgets, and no reliable monitor targeting. We will revisit native Wayland
only when its acceptance tests pass; see
[docs/NATIVE_WAYLAND_MIGRATION.md](docs/NATIVE_WAYLAND_MIGRATION.md) and the
explicit blocked task in [ROADMAP.md](ROADMAP.md).

Requires Conky 1.23+ (project version floor), Lua Cairo, X11 mouse events,
**and Conky's `cairo_xlib` Lua module**; `DISPLAY` must be available (XWayland
in a Plasma Wayland session). Run `python3 doctor.py --runtime-only` to check
this before launching widgets. `lib/Surface.lua` deliberately uses
`cairo_xlib_surface_create()` with `double_buffer = true` and explicitly
releases each owned surface. On the tested Fedora 45/Conky 1.24.2 XWayland
setup, the newer `conky_surface()` API acquired a Cairo surface but did not
visibly present double-buffered drawings; disabling double buffering caused
flickering, whereas the Xlib probe rendered correctly. The Xlib API is
**deprecated**, so this is a temporary, tested backend-specific dependency,
not a silent fallback. See [the full evidence and migration gate](docs/NATIVE_WAYLAND_MIGRATION.md).

`normal` X11 windows request KDE window-manager hints to stay below ordinary
applications. On 2026-11-23, the user confirmed that the four widgets
render and behave as before after the shared Xlib surface restoration, with
no missing functionality reported. This is a live functional confirmation,
not an exhaustive test of logout/login, hotplug, or every scale/anchor.

The layout tool uses KScreen's reported **global logical desktop** origin for
each output, combined with the selected anchor, margin and widget dimensions.
Unlike native Wayland, X11/XWayland can position windows in a shared screen
coordinate space. This model assumes XWayland and KScreen expose compatible
logical geometry; mixed-DPI or unusual arrangements require visual verification.

**After migrating from the experimental native-Wayland layout**, run
`python3 configure.py --reflow-layout --widget all` to convert saved monitor
intent to X11/XWayland global placements. This recalculates all four widgets
without manually editing X/Y values. If an older profile lacks `[layout]`
intent, run `--layout --widget all` once instead. Neither command restarts
Conky; use `python3 restart.py` after validating the result.

## Prayer Times: next-prayer sideline and Jumu'ah (Task 5)

The next upcoming prayer is identified using **option 03, “Vertical accent
line,”** from `isha-highlight-variations.html`: a 3-logical-pixel vertical
stroke to the left of its column, and the prayer **name only** in warm gold
(`#efb46f`). All times and the remaining headings retain their original
white color and opacity. There are no tiles, gradients, additional labels,
brightness changes to the time, or animations. Sunrise and Midnight / Last
3rd are informational rather than normal prayer events; tomorrow's Fajr gets
the accent after Isha if it is the next prayer.

To customize the line **and** label color, optionally add this under
`[appearance]` in your existing `settings.ini`:

```ini
next_prayer_color = #efb46f
```

The default applies even without the key, so this patch deliberately does
**not** replace your personal `settings.ini`. Use a six-digit `#RRGGBB` color;
invalid values produce an explicit configuration error. Restart only Prayer
Times through KDE Autostart after changing it.

The Dhuhr column's name follows the **Islamic day boundary at the local
Maghrib prayer**, not civil midnight: Thursday Maghrib through Friday before
Maghrib displays **Jumu'ah**, and Friday Maghrib immediately reverts to
**Dhuhr** for Saturday. After Maghrib, that third column also shows the
**next civil day's cached Dhuhr time** (e.g. Friday's Jumu'ah time), avoiding
the misleading combination of a Friday label with Thursday's elapsed prayer
time. The other columns still show today's schedule (including the upcoming
Isha). If tomorrow's cache is not ready, the third column temporarily shows
`--:--` until the background fetch completes.

The `Till Jumu'ah` / `Since Jumu'ah` countdown labels depend on the actual
Friday Dhuhr event timestamp, not merely the row's Islamic-day label.
Canonical event names, athan times, the Midnight / Last 3rd click toggle,
Xlib Cairo drawing, and the `0.25`-second refresh stay unchanged. The local
system timezone must match the configured prayer location. The revised
styling and day transition have offline regression tests. The user confirmed
the visible Task 5 behavior on KDE on 2026-11-23; the exact Thursday/Friday
Maghrib transition is still awaiting observation at the real boundary.

## Prayer Times: hover an individual prayer (Task 6)

Move the pointer over any of the seven prayer **name/time columns** to see a
temporary countdown to that selected event. This does not replace the
permanent `Till <NextPrayer>` countdown. When a separate `Till Sunrise` or
`Till Midnight` countdown is showing after Fajr or Isha, the hovered prayer
appears in a third countdown column; otherwise it uses the second column.
Hovering an event already shown in either existing countdown does nothing.

This includes the **actual next occurrence** of earlier-today prayers (for
example, hovering Dhuhr at night targets tomorrow's Dhuhr), Friday
`Jumu'ah` naming, and the current seventh-column `Midnight` / `Last 3rd`
selection. Midnight/Lastthird after 00:00 use the proper next civil-day
timestamp, not today's row text interpreted as an already-past event.
If that date's cache is not available, the temporary countdown is omitted
until the background fetch completes.

The elapsed `Since` hover is restricted to a full prayer-column-sized area **above Fajr**, with a narrow gap before its visible label/time.
It no longer triggers over Fajr/Sunrise headings, times, or the other prayer
columns. The seventh-column click still toggles Midnight/Last 3rd. These are
independent named zones. For steady hover under XWayland, use
`hover_failsafe_seconds = 0` in `[behavior]`, so stationary pointers do not
time out; moving outside the hotspot or leaving the window clears it. The old
`hover_area` modes were removed, as their broad rectangles caused false
elapsed-time activations. Existing `hover_area` entries are ignored and may be
deleted from user settings; no new configuration key was added. Restart only Prayer Times after installing.

The geometry and countdown slots are covered by `tests/test_prayer_hover.lua`,
including three scales. The user confirmed the steady live hover behavior and
the full-column-sized elapsed hotspot above Fajr on KDE on 2026-11-23. See
`docs/HOVER_ZONE.md` and ROADMAP Task 6.

## Desktop notifications (Task 7)

Prayer Times and Hijri Date use a shared, non-blocking `notify-send` service
(`lib/Notify.lua`). They operate on the **same cached Aladhan prayer data** as
the widgets; no extra network requests or notification daemon are started.

Configure these `[behavior]` settings in `settings.ini` or through
`python3 configure.py` (shared, all, prayer or date):

```ini
notifications_enabled = yes
notify_prayer_minutes = 15
notify_fasting_days = yes
```

- Five prayers (Friday's Dhuhr is **Jumu'ah**), Sunrise and Midnight get a
  reminder as the widget crosses the configured lead-time threshold.
  `notify_prayer_minutes` accepts `0..60`; **0 disables pre-event reminders**.
  Sunrise warns that Fajr is ending; Midnight is independent of the seventh
  column's Midnight / Last 3rd click toggle.
- A Maghrib rollover to Hijri dates **13, 14, or 15** triggers a White Days
  (Ayyam al-Bid) fasting reminder for the following daylight period.
  **Hijri month 9 (Ramadan) suppresses these reminders** and displays dates
  12–15 in normal white, rather than using the White Days red accent.
- Cold startup, widget restarts, and large sleep/wake time jumps do **not**
  backfill missed reminders. Prayer reminders are issued only on the live
  15-minute threshold crossing. Fasting reminders require the Date widget to
  witness Maghrib, with two minutes for the next day's cache to arrive.
  Keep both widget autostart entries running across the transition.
- Event keys are claimed atomically across processes and persist in
  `${XDG_CACHE_HOME:-~/.cache}/conky-notifications/sent/`; the companion
  `sent.cache` records notifications for diagnostics. Old key markers are
  pruned after 60 days. Clearing this cache resets deduplication.

`python3 doctor.py` reports a warning (not a fatal error) if `notify-send` is
missing. The actual notification presentation depends on KDE Plasma's
notification permissions, Do Not Disturb setting, and D-Bus session.
Restart **Prayer Times and Hijri Date** after changing these settings.
See `docs/NOTIFICATIONS.md` for test cases and restart semantics.

## 1. Project setup

Install from the **complete project directory** using `bash install.sh` (see
section 4). Existing installations should retain their own `settings.ini` and
personal files. Save a full configuration profile before changing location,
appearance or placement (see section 5). All four windows share the selected
active settings file; location and cache signatures are updated on restart.

## Date hover forecast design

With `date_weather_mode = date_and_weather`, hovering over the Date widget's
weather area reveals the **next three calendar days**, starting **tomorrow**.
Each row is minimalist and right-aligned into the unused space beside the clock:

```text
Fri       [icon]
47°/34°

Sat       [icon]
45°/32°

Sun       [icon]
43°/30°
```

The example values are illustrative. In the actual layout, each icon is only
**6 logical pixels** to the right of the temperature text column, and each icon
is centered alongside its two-line day/temperatures group. The display is
transparent, without arrows, labels, outlines, or animation. Three fixed rows
use small text and icons to avoid colliding with the current-weather details
or the Gregorian/Hijri dates. The forecast hides again when hover ends.

The three-row forecast is vertically centered against the clock's **visible
glyph bounds**, not pinned to the top of the Conky window. This works with the
configured Date font and `date_scale`, without moving the clock or the dates.
The weather icons remain beside their temperatures (6 scaled pixels before
the PNG's transparent padding), in a consistent right-aligned icon column.

The forecast uses Open-Meteo's *daily* `weather_code`, not the current hourly
`is_day` field, so it intentionally chooses the **daytime variant** of the
matching PNG for each daily summary. The current temperature/icon and the
separate Weather widget retain their usual current-condition day/night rules.

### Check whether the forecast icons are correct

For forecast days, the Open-Meteo *daily* WMO code is mapped as follows:
`0` = clear (`32.png`), `1` = mainly clear (`34.png`), `2` = partly cloudy
(`30.png`), and `3` = overcast (`26.png`). WMO code `97` (heavy thunderstorm)
uses the thunderstorm icon (`37.png` by day / `47.png` by night) rather than
the cloudy fallback. Other WMO conditions use the
expanded mapping in section 3. A cloudy icon on all three days is correct
**only if the cached `forecast_1_code`, `forecast_2_code` and
`forecast_3_code` are all `3`**. Current conditions use a separate
`current.weather_code` (stored as `code` in the cache), so the current icon
can differ from the daily one.

Check the **exact values shown by your installed widget**:

```bash
grep -E '^forecast_[123]_(day|high|low|code)=' "${XDG_CACHE_HOME:-$HOME/.cache}/conky-sun-weather/weather.cache"
```

To query Open-Meteo directly, use these example coordinates from the
included default `settings.ini` (Cairo). **Replace latitude/longitude with
your own installed `[location]` coordinates if different**:

```bash
curl -fsSG 'https://api.open-meteo.com/v1/forecast' \
  --data-urlencode 'latitude=30.0444' \
  --data-urlencode 'longitude=31.23575' \
  --data-urlencode 'daily=weather_code,temperature_2m_max,temperature_2m_min' \
  --data-urlencode 'timezone=auto' \
  --data-urlencode 'forecast_days=4' \
  | python3 -m json.tool
```

The first item is *today*; the next three items correspond to the three
hover rows. The API can update after the cache was fetched, so compare the cache first.
Refresh it with `python3 ~/.config/conky/workers/weather_fetch.py --force` when you
want the widget to use newly fetched codes.

No extra setting is required; the forecast obeys `date_scale` and is enabled
only when the existing Date display mode is `date_and_weather`. In `date_only`,
no date weather or forecast is drawn. The standalone Weather widget is always
independent and is **not** given a forecast hover.

## 2. Date modes

Edit `~/.config/conky/settings.ini` in `[appearance]`:

```ini
# Clock + dates, with no weather elements inside the Date window
date_weather_mode = date_only
```

or:

```ini
# Clock + dates + current temperature/icon, with hover details inside Date
date_weather_mode = date_and_weather
```

These are the **only two valid values**. The `date_weather_mode` key is required. The separate Weather Conky window renders in **both** cases and retains its own position, scale and icon settings.

Date-only weather display controls (under `[appearance]`):

| Setting | Purpose |
| --- | --- |
| `date_weather_clock_size` | Clock size for Date's weather header before `date_scale` |
| `date_weather_hover_temp_size` | Temperature size when hovering inside Date |
| `date_weather_icon_size` | Icon size inside Date |
| `date_weather_icon_dx`, `date_weather_icon_dy` | Date weather icon nudges |

Under `[behavior]`, `date_weather_hover_failsafe_seconds` controls the Date header's weather-detail hover timeout. None of these change the standalone Weather renderer.

Standalone Weather controls are `weather_scale`, `weather_icon_x`, `weather_icon_y`, `weather_icon_size`, `weather_x`, and `weather_y`. Shared `weather_refresh_minutes` controls how often the weather worker refreshes the common cache. All four widgets share `appearance.font` and `[location]`.

Use the wizard to change Date only:

```bash
python3 ~/.config/conky/configure.py --widget date
python3 ~/.config/conky/restart.py --widget date
```

The standalone Weather widget does **not** need a restart after a Date mode change.

## 3. Weather icon mapping (expanded icon pack)

Both the standalone Weather widget and Date's main temperature use the same
Open-Meteo **current** `weather_code` and `is_day` fields. They select the same
condition icon without changing either widget's visibility or placement. Weather
icons are loaded from `assets/weather/NAME.png` and are 256×256 transparent PNGs.
Both widgets use `lib/Weather_Icons.lua` for the WMO mapping and PNG drawing;
icons are loaded lazily and cached within each Conky process, including the
Date widget's three-day hover forecast.

| Open-Meteo WMO condition codes | Daytime PNG | Nighttime PNG |
| --- | --- | --- |
| `0` clear | `32.png` | `31.png` |
| `1` mainly clear | `34.png` | `33.png` |
| `2` partly cloudy | `30.png` | `29.png` |
| `3` overcast | `26.png` | `26.png` |
| `45`, `48` fog | `20.png` | `20.png` |
| `51`, `53` drizzle | `9.png` | `45.png` |
| `55` dense drizzle | `6.png` | `45.png` |
| `56`, `57` freezing drizzle | `5.png` | `5.png` |
| `61` slight rain | `9.png` | `45.png` |
| `63`, `65` moderate/heavy rain | `6.png` | `45.png` |
| `66`, `67` freezing rain | `5.png` | `5.png` |
| `71` slight snow | `13.png` | `13.png` |
| `73`, `75` moderate/heavy snow | `14.png` | `14.png` |
| `77` snow grains | `17.png` | `17.png` |
| `80` slight rain showers | `9.png` | `45.png` |
| `81`, `82` heavier rain showers | `6.png` | `45.png` |
| `85` slight snow showers | `41.png` | `46.png` |
| `86` heavy snow showers | `14.png` | `46.png` |
| `95`, `97` thunderstorm / heavy thunderstorm | `37.png` | `47.png` |
| `96`, `99` hail thunderstorm | `0.png` | `0.png` |
| Other/unknown code | `26.png` | `26.png` |

The icon set depicts **freezing precipitation approximately** with `5.png` (mixed
rain/snow); similarly `17.png` depicts small icy pellets for snow grains. The
available art does not provide an exact pictogram for every WMO subtype.
Although the supplied archive has 49 PNG filenames, 22 files are exact copies of
another file. The code uses 20 distinct images. Wind icons (`23.png`–`25.png`)
and the hot sun (`36.png`) are not automatically selected, because the present
weather fetcher reads no wind speed and there is no configured heat threshold.

## 4. Installing the complete project

From a **complete project folder** containing all code, configuration and `assets/weather/`:

```bash
bash install.sh
```

The installer backs up any existing `~/.config/conky` directory and installs
code into `configs/`, `widgets/`, `lib/`, `workers/`, and `docs/`. On an existing
installation it **preserves** your active `settings.ini`, `profiles/`,
`layouts/`, `monitor_geometry.json`, and `athan.wav`; a new installation receives
the supplied `settings.ini`. Existing weather icons are also preserved.
Saved settings profiles remain full snapshots,
not layout presets. The installer removes superseded flat code copies after
making the backup. It can install an XDG/KDE autostart entry; options:
`--no-autostart` and `--no-configure`. The optional `athan.wav` can live at
project root or `assets/athan.wav`. Font default is `ITC Avant Garde Pro XLt`;
choose an installed font if needed (`fc-match`).

**Weather icons:** A complete installation requires the existing
`assets/weather/*.png` pack. The archive used to prepare the reorganization
patch does not include that pack; the patch does not delete or replace your
installed PNGs. If installing into a fresh directory, supply the icon pack
separately before expecting Weather and Date weather icons to render.

System requirements: Python 3, KDE Plasma Wayland with XWayland (`DISPLAY`), Conky 1.23+ with Lua/Cairo and X11 mouse events, and internet access for prayer/weather fetches. Python third-party packages are not required. `paplay` is optional for Athan playback.

## 5. Configure, position and launch

```bash
# Review / validate config
python3 ~/.config/conky/configure.py --show
python3 ~/.config/conky/configure.py --check

# Configure just one widget (or all / shared location + font)
python3 ~/.config/conky/configure.py --widget date
python3 ~/.config/conky/configure.py --widget weather
python3 ~/.config/conky/configure.py --widget all
python3 ~/.config/conky/configure.py --widget shared

# Layout and validation for all four widgets, nine anchors per output
python3 ~/.config/conky/configure.py --screens
python3 ~/.config/conky/configure.py --check-layout --widget all
python3 ~/.config/conky/configure.py --layout --widget all
# One-time native-Wayland -> XWayland conversion of saved monitor intent:
python3 ~/.config/conky/configure.py --reflow-layout --widget all
python3 ~/.config/conky/configure.py --manual-screens

# Full-settings profiles (location, appearance, behavior AND placement)
python3 ~/.config/conky/configure.py --save-profile home
# Change settings using the wizard or settings.ini, then save a second snapshot
python3 ~/.config/conky/configure.py --save-profile office
python3 ~/.config/conky/configure.py --list-profiles
python3 ~/.config/conky/configure.py --use-profile home
python3 ~/.config/conky/restart.py  # all four windows reload the selected profile

# Optional declarative layout presets (named outputs/anchors/margins/scales)
# Each selected widget must first be configured with --layout.
python3 ~/.config/conky/configure.py --save-layout desktop --widget all
python3 ~/.config/conky/configure.py --list-layouts
python3 ~/.config/conky/configure.py --use-layout desktop --widget all

# Start all, or just one (does not stop existing instances)
bash ~/.config/conky/start.sh
bash ~/.config/conky/start.sh --widget weather
bash ~/.config/conky/start.sh --widget date

# Stop/restart only this project's matching Conky processes
python3 ~/.config/conky/restart.py
python3 ~/.config/conky/restart.py --widget date
python3 ~/.config/conky/restart.py --widget weather
python3 ~/.config/conky/restart.py --list
python3 ~/.config/conky/restart.py --stop-only
```

Supported widget selectors throughout: `all`, `prayer`, `date`, `weather`, and `sun_moon`. The configuration wizard also accepts `shared` for the common location/font settings. There are no alternative selectors or historical command aliases.

`workers/layout.py` calculates placements for **all four widgets and all nine
anchors**, using the centralized `widget_geometry.ini` also read by their Lua
Conky configs. The wizard records output name, anchor and margins in `[layout]`;
`[placement]` holds the **global X11/XWayland virtual-desktop coordinates**
Conky consumes. A selected output's KScreen X/Y origin is included when deriving
those coordinates. Named layout presets store output/anchor/margin intent and
scales and are recalculated for the current monitor geometry on activation.

`--check-layout` verifies each requested window rectangle against the detected
screens, flags stale positions and overlaps, but **does not measure Cairo ink
bounds**, diagnose mixed-DPI discrepancies or prove runtime stacking. For the
reported dual-1920×1080 layout, `DP-2` begins at global `(1920,0)` and
`HDMI-A-2` at `(0,0)`. See the migration decision record for the reason the
native-Wayland layout was rejected.

Full-settings profiles are snapshots in `profiles/<name>.ini` (only names made of
letters, digits, underscores and hyphens are accepted). `settings.ini` remains
**the one active file**; switching profiles atomically replaces it. An old coordinate-only full profile
has no output/anchor intent: run `--layout` after selecting it before attempting
`--reflow-layout`. Saving an existing name overwrites its snapshot, so save the current profile before
switching if you want to retain unsaved edits. If a saved full-settings profile was created with the experimental native
Wayland layout, run `--reflow-layout --widget all` after switching to convert
its saved monitor intent into global XWayland coordinates. Profile switching does not
change running Conky instances until you restart them. If the location changes,
prayer and weather workers refresh their location-keyed caches automatically.

## 6. Data and behavior

- **Prayer + Hijri:** `workers/prayer_fetch.py` uses Aladhan to populate the `CONKY_PRAYER_V2` cache consumed by `lib/Prayer_Data.lua`, including the API's `Lastthird` time (not an estimate calculated in Lua). The Hijri date rolls at Maghrib. **Left-click the seventh Prayer column** to switch its label/time between **Midnight** and **Last 3rd**. The column starts on Midnight at each launch; the post-Isha **Till Midnight** countdown never changes with this toggle. Prayer countdown and hover zones are configured with `elapsed_minutes`, `hover_failsafe_seconds`, `hover_debug_outline`, `hijri_offset_days`, and `athan_enabled`; see `docs/HOVER_ZONE.md` for the mouse-hook diagnostic. On Fedora 45 / Conky 1.24.2 XWayland the user verified that the click toggle works. Setting `update_interval = 0.25` in `configs/conky_prayer_times.conf` (manually, on the installed widget) makes the updated column appear within the next quarter-second refresh, at the cost of four redraws per second. No new setting is needed. Prayer time interpretation expects your system timezone to match the configured location.
- **Weather:** `weather_fetch.py` uses Open-Meteo without an API key for noncommercial personal use, caching current conditions, sunrise/sunset and tomorrow-through-day-three daily forecast data in `~/.cache/conky-sun-weather/`. Weather remains independent of Date; enabling `date_and_weather` adds a *second* current-weather display and its three-day hover forecast inside Date without suppressing standalone Weather. Unavailable forecast data is omitted instead of showing invented or outdated rows.
- **Astrolabe:** draws a transparent Sun/Moon dial with lunar phase, night progress and solar schedule from shared caches. It discards weather solar timestamps from a different calendar day (including after sleep/wake), falling back to today's prayer cache or temporarily showing a waiting state until fresh data arrives. The 24-hour bar and lunar phase continue to update. **On hovering either the dial or the 24-hour bar**, five subtle `F/D/A/M/I` prayer ticks and labels appear on **both**, disappearing on mouse leave; the idle display is unchanged. The circular dial's night arc uses yesterday's Maghrib/Isha + today's Fajr before sunrise, or today's Maghrib/Isha + tomorrow's Fajr afterward; the 24h bar always uses today's five prayers. Markers wait for the required cached dates rather than invent times. The Astrolabe reuses `[behavior] hover_failsafe_seconds`; `0` keeps stationary hovering visible on the current XWayland setup. It redraws at 0.25 seconds while running. The Astrolabe has no background card; icons for standalone Weather and Date weather are loaded from `assets/weather/`.

**Task 8 live acceptance (2026-11-23):** The user confirmed the Astrolabe
hover markers look good and function correctly on KDE. The before-sunrise and
after-sunset timestamp choices passed offline tests; those specific real-world
transitions were not separately observed. Task 7 notifications still require
live verification, and Task 11 native Wayland remains blocked.

Diagnose problems with:

```bash
python3 ~/.config/conky/doctor.py
python3 ~/.config/conky/doctor.py --fetch
python3 ~/.config/conky/doctor.py --weather-fetch
conky -c ~/.config/conky/configs/conky_date.conf
# Press Ctrl+C to close this foreground diagnostic instance
```

If a widget is missing, check `restart.py --list`, screen placement, Conky Cairo/Lua support (`conky --version`), font installation, weather icon assets, and cache logs: `~/.cache/conky-prayer-times/fetch.log` and `~/.cache/conky-sun-weather/fetch.log`. Restart a widget after modifying its configuration; shared cache updates do not require a restart.

## 7. Project files

```text
settings.ini, widget_geometry.ini, README.md, ROADMAP.md
install.sh, start.sh, restart.py, configure.py, doctor.py
configs/  conky_prayer_times.conf, conky_date.conf, conky_weather.conf,
          conky_sun_moon.conf
widgets/  Prayer_Times.lua, Hijri_Date.lua, Weather.lua,
          Sun_Moon_Astrolabe.lua
lib/      Settings.lua, Widget_Geometry.lua, Surface.lua, Hover_State.lua,
          Prayer_Data.lua, Weather_Data.lua, Weather_Icons.lua
workers/  prayer_fetch.py, weather_fetch.py, layout.py
docs/     HOVER_ZONE.md, NATIVE_WAYLAND_MIGRATION.md
assets/   weather/*.png, optional athan.wav
profiles/ optional full-settings snapshots
layouts/  optional layout-only presets
```

User-owned `monitor_geometry.json` and optional root `athan.wav` remain at the
project root. The retired `restart_new.py` and `upgrade_settings.py`
compatibility scripts were removed; the installer also deletes installed copies. Launcher commands remain at the root; worker scripts can also be run
via `python3 workers/prayer_fetch.py` and `python3 workers/weather_fetch.py`.

The project uses one active configuration schema, without migration scripts or launcher aliases. Named profiles are independent copies of that same schema, not separate per-widget configuration files.

### Upcoming-prayer Athan dot

The highlighted next prayer uses option 05: a small glowing dot beside the
colored heading (time stays white). Click the dot to mute/unmute the **next**
Athan: gold/configured accent = enabled, existing widget red = muted. The mute
choice resets to enabled as the next prayer becomes upcoming. This is an
in-memory toggle for the running widget (restarting resets it), not a global
setting; `behavior.athan_enabled=no` still disables all Athan playback.

For KDE Plasma notification history, see `docs/NOTIFICATIONS.md`.
