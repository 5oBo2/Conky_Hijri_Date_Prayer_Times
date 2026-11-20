# Conky: four independent widgets

A single-folder Conky project for Linux/KDE, with one `settings.ini` and four **independent windows**:

| Widget | Rendering files | Independent size / placement |
| --- | --- | --- |
| Prayer Times | `Prayer_Times.lua`, `conky_prayer_times.conf` | `prayer_scale`, `prayer_x`, `prayer_y` |
| Clock + Gregorian/Hijri Date | `Hijri_Date.lua`, `conky_date.conf` | `date_scale`, `date_x`, `date_y` |
| Weather | `Weather.lua`, `conky_weather.conf` | `weather_scale`, `weather_x`, `weather_y` |
| Celestial Astrolabe | `Sun_Moon_Astrolabe.lua`, `conky_sun_moon.conf` | `sun_moon_scale`, `sun_moon_x`, `sun_moon_y` |

Every window is launched separately, and changing the Date display mode **never** hides, moves, resizes, stops or changes the standalone Weather widget. Both weather displays read shared Open-Meteo data, but draw independently.

## 1. Apply the vertically centered forecast fix

This ZIP contains **only three complete replacement files**:

- `Hijri_Date.lua` — vertically centers the existing three-row hover forecast
  against the clock's visible bounds, and fixes the same missing WMO code `97`.
- `Weather.lua` — recognizes Open-Meteo code `97` as a thunderstorm rather
  than incorrectly falling back to cloudy; no Weather layout/behavior changes.
- `README.md` — updated installation and weather-code verification notes.

This patch applies **on top of the existing three-day forecast update**. Keep
`weather_fetch.py`, `Weather_Data.lua`, your `settings.ini`, and the expanded
20-icon `assets/weather/` collection as they are. Standalone Weather remains
independent and only gains the code `97` mapping fix.

1. Back up the installed project:

   ```bash
   cp -a ~/.config/conky ~/.config/conky-backup-$(date +%Y%m%d-%H%M%S)
   ```

2. Extract the ZIP into `~/.config/conky/`, overwriting **only those three files**.

3. Restart Date and Weather to load the updated icon mapping and drawing code:

   ```bash
   python3 ~/.config/conky/restart.py --widget date
   python3 ~/.config/conky/restart.py --widget weather
   ```

   The independent Weather widget keeps its existing size and position. There
   is no need to refresh the weather cache just to apply these code changes.

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
Refresh it with `python3 ~/.config/conky/weather_fetch.py --force` when you
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

See Section 1 for the replacement files and restart commands.

## 4. Installing the complete project

From a **complete project folder** containing all code, configuration and `assets/weather/`:

```bash
bash install.sh
```

The installer backs up any existing `~/.config/conky` directory, then installs **this project's `settings.ini` as-is**, without migrating prior setting formats. It can also install an XDG/KDE autostart entry. Options: `--no-autostart` and `--no-configure`. The optional `athan.wav` is not bundled; supply your own file next to the project scripts if desired. Font default is `ITC Avant Garde Pro XLt`; choose an installed font if needed (`fc-match`).

System requirements: Python 3, Conky with Lua/Cairo and mouse-event support for hover effects, and internet access for prayer/weather fetches. Python third-party packages are not required. `paplay` is optional for Athan playback.

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

# Monitor-aware placement and validation
python3 ~/.config/conky/configure.py --screens
python3 ~/.config/conky/configure.py --layout --widget all
python3 ~/.config/conky/configure.py --check-layout --widget all
python3 ~/.config/conky/configure.py --manual-screens

# Optional layout presets
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

The layout assistant works with multiple monitors via KScreen or XRandR, or manual coordinates. Conky window placement under Wayland/XWayland can differ from the compositor's desktop geometry, so visually verify the computed positions. Layout presets are stored in `layouts/`; manual monitor geometry is stored in `monitor_geometry.json`.

## 6. Data and behavior

- **Prayer + Hijri:** `prayer_fetch.py` uses Aladhan to populate the cache consumed by `Prayer_Data.lua`. The Hijri date rolls at Maghrib. Prayer countdown and hover zones are configured with `elapsed_minutes`, `hover_area`, `hover_failsafe_seconds`, `hover_debug_outline`, `hijri_offset_days`, and `athan_enabled`; see `HOVER_ZONE.md`. Prayer time interpretation expects your system timezone to match the configured location.
- **Weather:** `weather_fetch.py` uses Open-Meteo without an API key for noncommercial personal use, caching current conditions, sunrise/sunset and tomorrow-through-day-three daily forecast data in `~/.cache/conky-sun-weather/`. Weather remains independent of Date; enabling `date_and_weather` adds a *second* current-weather display and its three-day hover forecast inside Date without suppressing standalone Weather. Unavailable forecast data is omitted instead of showing invented or outdated rows.
- **Astrolabe:** draws a transparent Sun/Moon dial with lunar phase, night progress and solar schedule from shared caches. The Astrolabe has no background card; icons for standalone Weather and Date weather are loaded from `assets/weather/`.

Diagnose problems with:

```bash
python3 ~/.config/conky/doctor.py
python3 ~/.config/conky/doctor.py --fetch
python3 ~/.config/conky/doctor.py --weather-fetch
conky -c ~/.config/conky/conky_date.conf
# Press Ctrl+C to close this foreground diagnostic instance
```

If a widget is missing, check `restart.py --list`, screen placement, Conky Cairo/Lua support (`conky --version`), font installation, weather icon assets, and cache logs: `~/.cache/conky-prayer-times/fetch.log` and `~/.cache/conky-sun-weather/fetch.log`. Restart a widget after modifying its configuration; shared cache updates do not require a restart.

## 7. Project files

```text
README.md, HOVER_ZONE.md
settings.ini
install.sh, start.sh, restart.py
configure.py, layout.py, doctor.py
Settings.lua, Surface.lua, Hover_State.lua
Prayer_Data.lua, prayer_fetch.py
Weather_Data.lua, weather_fetch.py
Prayer_Times.lua, conky_prayer_times.conf
Hijri_Date.lua, conky_date.conf
Weather.lua, conky_weather.conf
Sun_Moon_Astrolabe.lua, conky_sun_moon.conf
assets/weather/*.png
```

The project uses a single current configuration schema, without migration scripts, compatibility settings, or launcher aliases. This icon patch does not change the configuration schema.
