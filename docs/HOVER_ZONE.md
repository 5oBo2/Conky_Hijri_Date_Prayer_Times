# Prayer elapsed-time hotspot (above Fajr only)

The `Since <last prayer>` hover is triggered **only in the empty region
immediately above the Fajr heading**, not by hovering on Fajr's time/name,
Sunrise, or any other prayer column. Per the user-provided reference screenshot,
its box is one **full prayer label + time hitbox high**, directly above Fajr,
with a `3 * prayer_scale` gap. Its width follows the measured Fajr column.
The prayer-column hitboxes start at their visible labels rather than extending
into the upper blank space, so both hover functions remain independent.
Positions are calculated from the row geometry and `prayer_scale`, never
virtual-desktop coordinates. Its internal name is `elapsed_above_fajr`.

Task 6 added independent hover zones for all seven prayer columns. The old
`hover_area = fajr_sunrise/content/window` configuration and its broad zones
were removed because they overlapped prayer columns and incorrectly revealed
the elapsed countdown. An old `hover_area` entry in an existing `settings.ini`
is now ignored; it can be deleted. `configure.py` no longer prompts for it.

Relevant settings:

```ini
[behavior]
elapsed_minutes = 60
hover_debug_outline = no
hover_failsafe_seconds = 0
```

`elapsed_minutes` controls automatic elapsed-time visibility immediately after
a prayer; it is independent of the hover hotspot. `hover_debug_outline = yes`
draws the actual full-column-height Fajr-only hover rectangle in red for diagnosis.
`hover_failsafe_seconds = 0` disables timeout while the pointer is stationary;
`mouse_move` outside the hotspot or `mouse_leave` then clears it. This is the
verified workaround for the one-second stationary-hover disappearance on the
current XWayland setup. If the window manager does not deliver `mouse_leave`,
a hover may remain until the next pointer event. Do not set a short failsafe
by default just to disguise missing leave events.

Restart only Prayer Times through KDE Autostart after editing its configuration
or applying a patch. There is no need to restart the other widgets.

## Checking the screen layout

`python3 configure.py --check-layout` estimates widget rectangles and
`--layout` performs X11/XWayland multi-monitor placement. This is independent
of the local hover-zone rectangles. See `NATIVE_WAYLAND_MIGRATION.md` and
`../README.md` for backend limitations.

## One hover API for every widget

`lib/Hover_State.lua` tracks named zones, including Date's `weather`,
Prayer's `elapsed_above_fajr`, and Prayer's seven `prayer_column_N` zones.
For independent regions inside a Conky window:

```lua
local state = Hover.new(0)
state:set_zone('weather', {100, 0, 260, 90})
state:set_zone('hijri', {{0, 0, 90, 90}, {0, 100, 90, 180}})
-- Forward events with state:mouse(event, os.time()).
local show_weather = state:visible('weather', os.time())
local show_hijri = state:visible('hijri', os.time())
```

Each named zone accepts one rectangle or a list of rectangles; `nil` removes
it. Mouse movement activates only the zones under the pointer, clearing
others immediately, and `mouse_leave` clears all. Coordinates missing from a
mouse event cannot activate a hitbox. The elapsed hotspot and the seven
visible prayer-column zones are deliberately **disjoint**, unlike the removed
broad area modes.

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


## Hover an individual prayer column (Task 6)

The Prayer widget defines `prayer_column_1` through `prayer_column_7` as
seven separate named zones covering each visible heading and clock time.
The rectangles are computed from the same Cairo text measurement, `x0`,
`stride`, and `prayer_scale` used to draw the row, so they move whenever the
widget layout changes. They coexist with `elapsed_above_fajr` (elapsed
countdown above Fajr) and `midnight_column` (click toggle). The elapsed
hotspot ends **before** the prayer-column hitboxes begin; hovering over
prayer names or times cannot also trigger elapsed time.

On movement, the first matching prayer column selects the nearest timestamp
at or after now from cached yesterday/today/tomorrow schedules. The main
`Till <NextPrayer>` countdown remains fixed in column 1, and the Sunrise /
Midnight special countdown, when present, remains in column 2. A distinct
hovered prayer goes in column 2 otherwise, or column 3 while the special
countdown is present. Hovering the already-visible next/special event avoids
duplicates. A hovered Dhuhr event gets the name `Jumu'ah` when its timestamp
falls on Friday. The seventh column targets `Lastthird` when toggled, not
`Midnight`, without altering the after-Isha `Till Midnight` counter.

The API's post-midnight `Midnight` / `Lastthird` values belong to the night
following their source schedule's Maghrib. The next-event lookup explicitly
shifts those event timestamps to the following civil date when appropriate;
this also handles early morning lookups using yesterday's cache. Missing
future data causes no countdown rather than a misleading fallback.

The hover respects `behavior.hover_failsafe_seconds`; use `0` on the
verified XWayland setup for steady stationary hover until mouse movement
leaves a zone or `mouse_leave` is delivered. The window's mouse-hook must
deliver coordinates for named-zone hit testing. The offline regression
`texlua tests/test_prayer_hover.lua` tests real widget draw and mouse hooks,
seven hitboxes, duplicate suppression, the two/three countdown layout,
Jumu'ah, and midnight rollover at three scales; it does not substitute for
live KDE visual verification.
