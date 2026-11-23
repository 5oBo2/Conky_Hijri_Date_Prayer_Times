# Fajr/Sunrise hover zone

Hovering over the small region containing the Fajr and Sunrise headings shows elapsed time since the last Athan, even after the automatic elapsed-time period ends. Moving away from this zone within Conky clears the hover immediately on the next mouse event. On KDE Wayland, a missed window-leave event can still leave it visible until `hover_failsafe_seconds` expires. A stationary pointer also times out with this fallback.

The complete package defaults to:

```ini
[behavior]
hover_area = fajr_sunrise
hover_debug_outline = no
hover_failsafe_seconds = 1
elapsed_minutes = 60
```

The same visible behavior now uses a named `fajr_sunrise` hover zone. Adjust the `[behavior]` keys in your shared `settings.ini` or run `python3 configure.py --widget prayer`.

To visualize the exact active zone temporarily, set `hover_debug_outline = yes`, restart prayer Conky and look for the red outline. Turn it back to `no` after confirming.

Restart only the prayer widget with `python3 restart.py --widget prayer`, or log out and back in. You do not need to touch your KDE Autostart entries or `athan.wav`.

## Checking the screen layout

`python3 ~/.config/conky/configure.py --check-layout` validates `fajr_sunrise` and prints estimated widget rectangles. `--layout` runs the X11/XWayland global-coordinate placement assistant on any output. `--manual-screens` supplies logical geometry when KScreen cannot report it. See `NATIVE_WAYLAND_MIGRATION.md` and `../README.md`.

## One hover API for every widget

`lib/Hover_State.lua` tracks only named zones, including the current Date
`weather` and Prayer `fajr_sunrise` zones. To define multiple independent
regions within one Conky window:

```lua
local state = Hover.new(4)
state:set_zone('weather', {100, 0, 260, 90})
state:set_zone('hijri', {{0, 0, 90, 90}, {0, 100, 90, 180}})
-- Forward events with state:mouse(event, os.time()).
local show_weather = state:visible('weather', os.time())
local show_hijri = state:visible('hijri', os.time())
```

Each named zone accepts one rectangle or a list of rectangles; passing `nil`
removes it. Zones can overlap. Mouse motion activates only the zones under
that pointer, clears others immediately, and `mouse_leave` or the failsafe
expires any active zones. A mouse event without coordinates cannot locate a
zone, so hover stays hidden in that case. The Prayer `hover_area` setting
selects the named `fajr_sunrise` rectangle(s): a small hotspot, two content
rectangles, or the full Conky window. All use the same `set_zone(name, ...)`
and `visible(name, now)` API. No additional settings are required.

## Midnight / Last 3rd click zone (Prayer widget)

The seventh Prayer column is a separate named `midnight_column` zone. Its
rectangle covers the header and displayed time; a **left** `button_down`
inside it toggles `Midnight` / `Last 3rd`. This is a direct hit test using
`state:contains('midnight_column', event.x, event.y)`, so a click works even
if a hover timeout has expired. This uses the same named-zone geometry as
`set_zone(...)` and does not reintroduce any legacy hover interface.

The post-Isha **Till Midnight** countdown always uses the original
`Midnight` timestamp, regardless of which time the seventh column shows.
The selection starts at Midnight on each Prayer widget launch; no extra
`settings.ini` option is needed.

### Mouse input diagnostic (historical test notes)

Production Conky currently uses **X11 through XWayland** (`out_to_x = true`,
`out_to_wayland = false`). Earlier native-Wayland click probes worked while
an older XWayland probe did not. Those observations apply to different Conky
versions/window types, and are **not proof** that Prayer's click toggle now
works. Confirm mouse events and window stacking on Fedora 45/Conky 1.24.2.
The separate native-Wayland probe is retained for future migration evaluation;
it is not a production backend selection.
