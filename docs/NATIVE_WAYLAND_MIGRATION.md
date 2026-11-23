# Native Wayland migration — blocked (decision record, 2026-11-23)

## Current supported architecture

**KDE Plasma remains a Wayland session.** Conky 1.24.2 currently renders
through **X11/XWayland**, not through native Wayland. All four widget configs
explicitly set `out_to_x = true` and `out_to_wayland = false`. On the tested
Conky 1.24.2 build, `lib/Surface.lua` **explicitly uses `cairo_xlib`**, not
`conky_surface()`, to render into a working X11/XDBE drawing surface. This is
a temporary dependency on a **deprecated API**, detailed below. The Python
layout engine applies named-output intent using global X11 virtual-desktop
positions derived from KScreen logical geometry. One engine covers all four
widgets and all nine anchors; no Date-only or Weather-only workaround.

This is a deliberately temporary decision, **not a recommendation to log into
an Xorg desktop session**. Avoid reintroducing side-by-side native and X11
configuration or invisible monitor-placement heuristics. Keep user settings,
profiles, anchor choices, and widget renderers independent of the backend.

## Why native Wayland was deferred

Observed on the user's Fedora 45 KDE Wayland desktop with Conky
`1.24.2-3.fc45` (2026-11-23):

1. **Shutdown hangs:** systemd user autostart units time out after SIGTERM
   and finally report SIGABRT (code=6). Relevant upstream work addresses
   Wayland event-loop/buffer-release hangs; newer version alone is not proof.
2. **Desktop stacking:** native desktop widgets disappear after a click on
   the desktop, apparently behind the wallpaper. KDE/Conky classification
   and desktop namespace behavior changed in later upstream builds.
3. **Multi-monitor placement:** `HDMI-A-2` at (0,0) and `DP-2` at (1920,0),
   each 1920×1080 logical, cannot reliably be selected as separate native
   Wayland destinations. Earlier script-generated output-local offsets placed
   every widget on the first monitor, despite saved target output names.
4. **Geometry/clipping:** minimum Conky window dimensions are shared between
   Lua and Python, but not measured Cairo glyph/icon ink bounds. Visual
   clipping still requires tests for all widgets/anchors/scales.

Upstream references (recheck their current state and release notes first):
- [#2111 — missing Wayland `display` / named-output selection](https://github.com/brndnmtthws/conky/issues/2111)
- [#2418 — Wayland termination hang report](https://github.com/brndnmtthws/conky/issues/2418)
- [#2432 — KDE desktop surface namespace / stacking](https://github.com/brndnmtthws/conky/issues/2432)
- [Conky releases](https://github.com/brndnmtthws/conky/releases)

Relevant upstream fixes in Conky 1.25.x include a buffer-event-loop exit
fix and new desktop namespace handling, but **all three operational blockers
must be tested together**. Do not infer output selection or stability from a
release number or from output configuration being parsed without errors.

## XWayland Cairo rendering regression — tested diagnosis (2026-11-23)

**Do not lose this finding when replacing the backend.** The user's working
pre-native-Wayland installation ran Conky 1.22.2 with a `lib/Surface.lua`
helper that preferred `conky_surface()` if available and otherwise created an
Xlib Cairo surface. The uploaded native-Wayland migration patch removed the
Xlib path and used `conky_surface()` only. In the older Conky build, the Xlib
fallback was the operative path; Conky 1.24.2 now provides `conky_surface()`
so a mere restoration of the old *prefer-new-API-first* helper is insufficient.

After returning to X11/XWayland with Conky 1.24.2, three widgets were reported
invisible or inconsistently visible, while Prayer Times rendered. Live KDE
verification established the following **for Hijri Date**:

| Experiment | Observed result |
| --- | --- |
| `xrandr --listmonitors`, `xwininfo` | Two 1920×1080 outputs form a 3840×1080 XWayland screen; all four windows mapped on-screen |
| Native Conky text renderer, no Lua/Cairo | Text visible at the expected XWayland position |
| `conky_surface()`, `double_buffer = true` | Acquired surface, red Cairo rectangle **not visible** |
| `conky_surface()`, `double_buffer = false` | Cairo surface/context statuses both 0; red rectangle **visible but flickering** |
| `cairo_xlib_surface_create()` with `cairo_xlib`, `double_buffer = true` | Cairo surface/context statuses both 0; red rectangle **visible without flickering** |
| Date autostart SIGTERM under XWayland | Repeated stops completed cleanly in journal (no SIGABRT/timeout) |

These tests **strongly implicate an interaction between Conky 1.24.2's
`conky_surface()` and X11/XDBE buffer presentation**, but do *not* prove the
exact underlying Conky defect (e.g. which drawable is referenced). Cairo
returning status 0 does not prove that content becomes visible. This was
not a monitor-layout regression, and raising the affected window did not
restore the missing graphics.

**Current solution, live-confirmed by the user on 2026-11-23:** The one shared `lib/Surface.lua` adapter
requires Conky's `cairo_xlib` module and explicitly constructs a surface from
`conky_window.display`, `.drawable`, `.visual`, `.width`, and `.height`.
Each widget obtains a surface, creates and destroys its Cairo context, then
calls `Surface.release(surface)` to destroy the **widget-owned** Xlib surface.
Leave `double_buffer = true` in all four widget configs. Do not automatically
fall back to `conky_surface()` when the Xlib module is absent: its XDBE
rendering was demonstrably invisible on this installation. `doctor.py`
checks for the module when Conky advertises its package library path.

The original window transparency settings were separately restored for a
diagnostic trial, but **did not** fix the invisible widgets. They produce
Conky deprecation warnings on 1.24.2; cleanup is a separate, visually tested
change and is not needed to establish the Cairo surface issue.

`cairo_xlib_surface_create()` emitted a **deprecation warning** on Conky
1.24.2. It may disappear in future Conky builds. We must not treat the Xlib
path as a permanent solution or silently migrate when it is removed. Test
the replacement API on *both* XWayland (with double buffering) and native
Wayland before deleting this adapter. The Xlib rectangle probe alone did **not** prove that all four complete
widgets rendered correctly. **After applying the shared Xlib restoration
patch, the user confirmed that everything worked as before and no widget
functionality was missing.** This closes the reported blank-widget regression
on the tested desktop; it is not evidence for unrelated display configurations
or future Conky versions.

### XWayland live acceptance after changing the adapter

- [x] User confirmed all four widgets were working again after applying
      the shared Xlib restoration, with no missing functionality reported.
      Exact per-widget interaction details were not separately logged.
- [x] Production configs retain `double_buffer = true`; user reported
      that the widgets worked as before. The isolated Xlib rectangle test
      explicitly showed no flicker.
- [ ] All widgets stop cleanly, including repeated stop/start from autostart;
      inspect `journalctl --user` for Lua, Cairo, timeout, or ABRT errors.
- [ ] Verify Date hover forecast, Prayer countdown/click/hover, Weather
      updates, and Celestial Astrolabe graphic; check clipping and scaling.
- [ ] Click the desktop, use Show Desktop, log out/in, and verify visibility.

The user's functional confirmation is recorded in the ROADMAP handoff log
(2026-11-23). The remaining unchecked checks are **extended acceptance
tests**, not known current defects. Keep them distinct from the future native
Wayland migration gate, which remains blocked.

## Current X11/XWayland layout and migration procedure

`[layout]` saves `<widget>_output`, `_anchor`, `_margin_x`, `_margin_y` for
`prayer`, `date`, `weather`, `sun_moon`. `widget_geometry.ini` is the shared
unscaled window size definition. `workers/layout.py` computes:

```
local_x = margin_x | centered | (output_width - widget_width - margin_x)
local_y = margin_y | centered | (output_height - widget_height - margin_y)
gap_x = output.x + local_x
gap_y = output.y + local_y
```

`[placement]` holds derived **global** Conky X11/XWayland coordinates.
This assumes XWayland geometry matches KScreen logical coordinates. Check
visually after mixed display scaling, arrangement changes, hotplug or restart.
The geometry manifest does not measure dynamic Cairo ink extents, so even a
rectangular fit does not guarantee that content cannot clip.

After switching backend, run `python3 configure.py --reflow-layout --widget all`
**only when all widgets already have `[layout]` metadata**. The 2026-11-23
experimental layout wizard saved it for all widgets when run with `--widget all`.
This command converts that intent to global X11 coordinates and preserves
unrelated user settings. Otherwise use `python3 configure.py --layout --widget all`
and choose outputs/anchors once. Run `--check-layout` and restart widgets.
The patch deliberately does **not** overwrite live `settings.ini` because
its placement, location and user preferences can differ from the source copy.
The config writer updates obsolete native Wayland placement comments on save.
Back up `settings.ini` before reflow. The script does not measure real X11
screen mapping; verify with KDE and optionally `xrandr --query` or `xdpyinfo`.

## Gate for future migration (ROADMAP task)

**Do not migrate because a newer Conky release exists.** First verify on the
actual Fedora/KDE desktop:

- [ ] SIGTERM completes without a systemd stop timeout or ABRT for all four
      widgets, including repeat start/stop cycles, autostart, logout.
- [ ] Desktop clicks, KDE Show Desktop, task switching, and normal window
      stacking leave widgets appropriately visible above the wallpaper and
      below ordinary application windows.
- [ ] A named output can be explicitly and reliably selected *for each*
      native surface; verify 2+ displays, placement on both while focus is
      on the opposite monitor, primary changes, logout/login, hotplug.
- [ ] All four widgets support all nine anchors, scale changes and mixed-DPI
      logical dimensions without crossing monitor edges. Dynamic Cairo
      glyph/weather icon ink must fit the allocated window at every tested
      display state; test font and forecast variants.
- [ ] Hover and mouse click events work for Prayer and Date on native
      Wayland; restart and cache operations remain unaffected.
- [ ] The `conky_surface()` Cairo API visibly presents all four widgets on
      **native Wayland**, including current/forecast icons and all dynamic
      drawing. Verify it on **XWayland with `double_buffer = true` as well**,
      or document a tested renderer/backend alternative. Check both returned
      Cairo statuses and real visible pixels: successful API calls alone did
      not guarantee presentation on 1.24.2. Remove the deprecated Xlib adapter
      and its owned-surface destruction only after its replacement is proven.
- [ ] Run the automated suite plus live desktop verification, record
      Conky/KDE/Fedora versions, relevant logs, screenshots, and results.

When all criteria pass, **replace** the X11 backend and global positioning
model with the native Wayland output-binding API that upstream actually
provides. Reuse saved declarative intent, shared widget dimensions and
renderers; remove obsolete X11/window-manager assumptions rather than
maintaining both implementations for compatibility. If output targeting is
still missing, leave migration blocked; do not approximate it in Python.
