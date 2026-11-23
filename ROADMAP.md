# Conky Islamic & Weather Suite — Implementation Roadmap & Agent Runbook

This document is the single source of truth for evolving the Conky widget suite. Tasks are ordered strictly by dependency so each step builds cleanly on the previous one without rework or back-and-forth refactoring.

---

## Agent Operating Rules (Read Before Doing Any Work)

1. **One Task Per Session:** Implement **only the single task requested by the user** (or the next unchecked `[ ]` task if told "next task"). Do **not** start future tasks prematurely.
2. **Test Before Marking Done:** Every task has explicit acceptance criteria and verification steps. Do not check off a task until all checks pass.
3. **Configuration Policy (Mandatory Evaluation):**
   - For every task, explicitly decide whether any new behavior naturally needs user configuration (e.g., toggles, lead times, thresholds).
   - **If YES:** Add it to `settings.ini` (with comments and sensible defaults), `configure.py` (interactive wizard + `validate(cp)`), `Settings.lua` (if typed helper/validation is needed), and `README.md`.
   - **If NO:** Do **not** invent unnecessary settings; keep `settings.ini` clean.
4. **Shared Cache & Restart Safety:**
   - Never block Conky's `conky_main()` draw loop with network calls or synchronous sleeps.
   - Cache format changes must bump the cache header version (e.g., `CONKY_PRAYER_V1` -> `CONKY_PRAYER_V2`) so existing user caches automatically refresh instead of crashing or returning missing fields.
5. **Mandatory Documentation & Handoff Protocol:**
   - Before finishing a task, record your work in the **Findings & Handoff Log** at the bottom of this file (what changed, exact paths, Conky/KDE/Wayland quirks discovered, edge cases handled, and test output).
   - Future or parallel agents MUST read the **Findings & Handoff Log** first so nobody hits the same pitfall twice.
6. **Small Project, Simple Fixes:** This is a small personal project, not a public compatibility platform. If existing structure, assumptions, or code create a clear hindrance, **fix or replace them directly at the source**. Prefer deleting an obsolete approach over layering workarounds on top. Avoid speculative abstractions, migrations, aliases, or preserving bad decisions merely because they already exist. Preserve user data and working behavior, not unnecessary implementation details.
7. **Patch Handoff:** Deliver changes as a unified `.patch` relative to the project root, together with the exact terminal command to apply it from `~/Downloads`. Do not assume the project is a Git repository. State what was verified and what still requires testing on the user's desktop.

---

## Architecture Dependency Order

```text
Task 9 (Full-Settings Profiles) [independent]
Task 10 (Astrolabe Wake/Date Guard) [independent; prerequisite for reliable Task 8 markers]
Task 1 (Repo Organization)
   ├──► Task 2 (Named Hover Zones in Hover_State.lua)
   │       ├──► Task 4 (Aladhan Lastthird + Click Toggle) ──► Task 5 (Next-Prayer Highlight + Jumu'ah) ──► Task 6 (Second Hover Zone) ──► Task 7 (Unified Notify Service + Ramadan Fix)
   │       └──► Task 8 (Astrolabe Hover Prayer Markers; requires Task 10)
   └──► Task 3 (Shared Weather_Icons.lua)
```

---

## Task Checklist

### [ ] Task 1: Reorganize Repository Directory Structure — Implemented; Live Rendering Confirmed, Extended CLI Checks Open
**Goal:** Move files out of the single flat root directory into a clean, maintainable layout while keeping user-facing CLI entrypoints simple.

**Target Layout (adapt only if an existing script/autostart requires an adjustment—document any deviation):**
- Root (user-facing entrypoints & config):
  - `settings.ini`, `README.md`, `ROADMAP.md`
  - `install.sh`, `start.sh`, `restart.py`, `configure.py`, `doctor.py`, `upgrade_settings.py`, `restart_new.py`
- `configs/`: `conky_prayer_times.conf`, `conky_date.conf`, `conky_weather.conf`, `conky_sun_moon.conf`
- `widgets/`: `Prayer_Times.lua`, `Hijri_Date.lua`, `Weather.lua`, `Sun_Moon_Astrolabe.lua`
- `lib/`: `Settings.lua`, `Surface.lua`, `Hover_State.lua`, `Prayer_Data.lua`, `Weather_Data.lua`, `Weather_Icons.lua` (future `Notify.lua` will live here)
- `workers/`: `prayer_fetch.py`, `weather_fetch.py`, `layout.py`
- `docs/`: `HOVER_ZONE.md` (and any new technical notes)
- `assets/`: existing `assets/weather/*.png` (and optional `athan.wav` search path—check both root and `assets/` for `athan.wav` for backward compatibility!)

**Implementation Notes:**
- Audit every `dofile(...)`, `lua_load`, `assets/weather/` path, `settings.ini` path, `prayer_fetch.py` / `weather_fetch.py` invocation, `restart.py` `CONFIGS` paths, `start.sh`, `install.sh`, `doctor.py`, `configure.py` (`import layout`), and `README.md`.
- Introduce a reliable root-resolution pattern in Lua (e.g., resolving `ROOT` from `debug.getinfo(1, 'S').source` or passing `package.path`) and Python (`sys.path` / `ROOT = Path(__file__).resolve().parent.parent` for `workers/`).
- Preserve user files (`settings.ini`, `athan.wav`, `monitor_geometry.json`, `layouts/`, and named full-settings snapshots in `profiles/`). Do not treat saved profiles as layout-only presets.
- **Config evaluation:** No new `settings.ini` keys needed.

**Acceptance & Verification:**
- [x] `python3 configure.py --check` passes.
- [ ] `python3 doctor.py` passes with 0 errors on the actual desktop (0 errors in an isolated fixture with a stub Conky and a temporary icon).
- [ ] `python3 restart.py --list` and `python3 restart.py` find, stop, and restart all 4 `configs/conky_*.conf` instances cleanly on the actual desktop (simulated four-process cycle passed).
- [x] All 4 widgets render normally with fonts, weather PNG icons, prayer data, and weather data loaded (user confirmed restored functionality on 2026-11-23).
- [x] Findings & Handoff Log updated.

---

### [ ] Task 2: Upgrade `lib/Hover_State.lua` for Named Multi-Zone Support — Implemented; User-Reported Functional, Alternate-Zone Checks Open
**Goal:** Allow a single Conky window to define and query multiple independent hover zones (e.g., `'weather'` vs `'hijri'`, or `'elapsed_above_fajr'` vs individual prayer columns) without them triggering each other.

**Implementation Notes:**
- Use one `Hover.new(timeout)` state with **named zones only** (no legacy single-zone state or parallel API):
  - `state:set_zone(name, rect_or_rects)` defines one rectangle or a list; `nil` removes it.
  - `state:visible(name, now)` queries the named zone only.
  - On `mouse_enter` / `mouse_move`, activate only named zones containing `(event.x, event.y)` and immediately clear non-matching zones. Missing coordinates cannot identify a zone and leave hover hidden.
  - On `mouse_leave` or the Wayland failsafe timeout, clear active zones. Geometry updates must not reset active hover.
- Use the same API in **both** `widgets/Hijri_Date.lua` (`weather`) and `widgets/Prayer_Times.lua` (`elapsed_above_fajr`). Elapsed-time activation is a single, disjoint hotspot above Fajr. Do not reintroduce broad `content`/`window` modes overlapping Task 6 prayer columns. Preserve Date 3-day forecast and the Prayer elapsed timer.
- **Config evaluation:** No new `settings.ini` keys needed.

**Acceptance & Verification:**
- [x] Existing `Hijri_Date.lua` right-side weather hover still opens/closes as before (user reported no missing functionality after restoration; not independently re-probed).
- [ ] Live KDE: elapsed countdown appears **only** above Fajr (outside the automatic `elapsed_minutes` interval), never over the row's seven prayer headings/times; stationary hover is steady with failsafe zero.
- [x] Unit/smoke test in Lua confirms two named zones in one `Hover` instance trigger independently and expire on `mouse_leave` and timeout (`texlua tests/test_hover_state.lua`).
- [x] Findings & Handoff Log updated.

---

### [x] Task 3: Deduplicate Weather Icon Mapping & Drawing (`lib/Weather_Icons.lua`) — Implemented and Live Functionality Confirmed
**Goal:** Eliminate the duplicate `icon_code(wmo, day)` mapping and PNG surface cache currently copy-pasted across `Weather.lua` and `Hijri_Date.lua`.

**Implementation Notes:**
- Create `lib/Weather_Icons.lua` containing:
  - `M.code(wmo, day)` (the full WMO-to-PNG mapping including code `97` -> `37`/`47`).
  - `M.draw(cr, id, x, y, size)` (lazy PNG surface cache loading from `<ROOT>/assets/weather/<id>.png`).
- Refactor `widgets/Weather.lua` and `widgets/Hijri_Date.lua` to call `Weather_Icons.code(...)` and `Weather_Icons.draw(...)` and remove their local copies.
- **Config evaluation:** No new `settings.ini` keys needed.

**Acceptance & Verification:**
- [x] `Weather.lua` and `Hijri_Date.lua` render with their current/forecast icons and no missing functionality reported on 2026-11-23; exact icon identity remains covered by offline WMO mapping tests.
- [x] Only one WMO-to-PNG mapping exists in `lib/Weather_Icons.lua` (no widget-local `icon_code` functions).
- [x] Findings & Handoff Log updated.

---

### [ ] Task 4: Aladhan `Lastthird` Caching & Click Toggle on Midnight Column — Implemented; Live Click Confirmed, Live Fetch Check Open
**Goal:** Fetch `Lastthird` directly from the Aladhan API (not calculated manually) and allow left-clicking the Midnight column in `Prayer_Times.lua` to toggle that column between `Midnight` and `Last 3rd`, while keeping the post-Isha `Till Midnight` countdown unaffected.

**Critical Pre-Check (Do First!):**
- Test whether Conky's `lua_mouse_hook` on this machine/Conky build delivers `button_down` / `button_up` events with `own_window_type = 'normal'`. (Some Conky 1.22.x X11/XWayland builds drop button events.)
- Log the exact `conky --version`, session type (`XDG_SESSION_TYPE`), and whether `button_down` fires in the **Findings & Handoff Log**. If `button_down` is dropped by Conky, check `own_window_type` / Conky behavior or document the workaround clearly before finalizing.

**Implementation Notes:**
1. **`workers/prayer_fetch.py` & `lib/Prayer_Data.lua`:**
   - Aladhan `/v1/timings` returns `"Lastthird"` inside `data.timings`.
   - Bump cache version from `CONKY_PRAYER_V1` to `CONKY_PRAYER_V2` and add `'Lastthird'` to `REQUIRED_TIMES` / `REQUIRED`. (Bumping to `V2` ensures stale `V1` cache files automatically trigger a fresh fetch.)
2. **`widgets/Prayer_Times.lua`:**
   - Track a toggle state (`show_last_third = false` by default).
   - Register a clickable hitbox covering the 7th column (`Midnight` / `Last 3rd` label + time).
   - On left click inside that hitbox (`event.type == 'button_down'` and `event.button == 'left'`), flip `show_last_third = not show_last_third`.
   - Render the 7th column header as `'Midnight'` with `times.Midnight` when `false`, or `'Last 3rd'` with `times.Lastthird` when `true`.
   - **Invariant:** The countdown row below (`extra` = `Till Midnight` shown after Isha until Midnight, alongside `Till Fajr`) MUST always show `Till Midnight` regardless of what the 7th column is toggled to.
- **Config evaluation:** Consider adding an optional default in `settings.ini` only if useful (e.g., `midnight_column_default = midnight` / `last_third`), or skip if click-toggling starts at `midnight` cleanly. Document the decision.

**Acceptance & Verification:**
- [ ] `python3 doctor.py --fetch` populates `Lastthird=` in `~/.cache/conky-prayer-times/<today>.cache` with header `CONKY_PRAYER_V2`.
- [x] Clicking the 7th column toggles between `Midnight` (`times.Midnight`) and `Last 3rd` (`times.Lastthird`). User confirmed live switching and responsiveness after locally setting `update_interval = 0.25` (2026-11-23).
- [x] Between Isha and Midnight, toggling the 7th column to `Last 3rd` does **not** alter `Till Midnight` in the countdown row (passed simulated real widget draw path; desktop rendering still unverified).
- [x] Findings & Handoff Log updated (including Conky `button_down` behavior notes).

---

### [x] Task 5: Next-Prayer Sideline Accent & Maghrib-Based `Jumu'ah` Naming — Implemented; User-Verified Styling, Maghrib Live Transition Still To Observe
**Goal:** Make the upcoming canonical prayer visible without brightening or changing its clock time, and label the displayed Islamic day's Dhuhr correctly across the Maghrib boundary.

**Implementation (revised after live user feedback, 2026-11-23):**
1. **Option 03 from the user-supplied HTML (`isha-highlight-variations.html`):** A single 3px-at-scale vertical sideline, plus the next-prayer **name** in warm gold `#efb46f`. No box, glow, animation, other-color change, or brightness contrast in times. Restore original `WHITE` alpha 200/255 for every row time and all other names. Only canonical next-prayer events get the accent, including tomorrow's Fajr; not Sunrise or Midnight / Last 3rd.
2. **Configurable accent:** `appearance.next_prayer_color = #RRGGBB` in `settings.ini` (optional, default `#efb46f`). One setting controls both stroke and next-prayer label. Validate hex values with a clear error. Do not modify users' active `settings.ini` in a patch.
3. **Islamic day at Maghrib:** The row's Dhuhr/Jumu'ah identity changes at the **local Maghrib timestamp**. At Thursday Maghrib the third column becomes `Jumu'ah` using **Friday's actual cached Dhuhr time**; at Friday Maghrib it becomes Saturday's `Dhuhr` and time. Keep other row columns on the current civil day's schedule, so Thursday Isha continues to be Thursday Isha. Show `--:--` until next-day cache is ready; never mislabel Thursday Dhuhr time as Friday Jumu'ah.
4. **Real event countdowns:** Keep canonical `Dhuhr` event names for sorting, athan, columns, and timestamps. For `Till`/`Since` countdowns only, use `Jumu'ah` when the Dhuhr event occurs on civil Friday. This is independent of the row's label once the Islamic night begins.
5. **Font and geometry:** Use ASCII `Jumu'ah` for the selected font; reserve measured heading widths and ensure the scale-adjusted left stroke stays inside the widget bounds at supported scales.

**Acceptance & Verification:**
- [x] On live KDE, user confirmed the sideline highlight and Jumu'ah update are working (2026-11-23); the previous brightness-only highlight was removed. Not a separate measured check at every scale.
- [x] Offline regression: at exact Thursday Maghrib Jumu'ah begins, at exact Friday Maghrib it ends, next-day Dhuhr time is used, countdowns still use Friday event timestamps, and the next Fajr/other prayer gets the sideline.
- [x] Offline regression: hex setting defaults to `#efb46f`, accepts a custom value, and rejects invalid colors; line positioning fits 0.65, 1.0 and 1.5 scales.
- [ ] On live KDE, verify Thursday and Friday Maghrib transitions with actual Aladhan caches, 7-column spacing, and the `ITC Avant Garde Pro XLt` glyphs. The logic is tested offline but the real transition has not yet been observed.
- [x] Findings & Handoff Log updated. User accepted Task 5 and requested moving to Task 6 (2026-11-23). The rare live Thursday/Friday Maghrib boundary remains a separately tracked verification item, not a blocker for Task 6.

### [x] Task 6: Prayer Widget Second Hover Zone (Hover Any Prayer for Its Countdown) — Implemented and User-Verified
**Goal:** Hovering over any prayer column in the main 7-column row temporarily displays `Till <HoveredPrayer>` in the countdown area without disturbing the primary `Till <NextPrayer>` (or post-Fajr/post-Isha secondary timers).

**Behavioral Specification:**
- Using named zones in `lib/Hover_State.lua` (from Task 2), register one hitbox per prayer column in the 7-column row (`Fajr`, `Sunrise`, `Dhuhr`/`Jumu'ah`, `Asr`, `Maghrib`, `Isha`, `Midnight`/`Last 3rd`).
- Let `target` be the currently hovered column:
  - **If `target` is already the `upcoming` prayer** (shown in Column 1): **do nothing** (do not duplicate it).
  - *(Edge case check: If `extra` is currently shown in Column 2 (`Sunrise` or `Midnight`) and user hovers that exact same `Sunrise` or `Midnight` column, decide cleanly—either ignore like `upcoming` or document; ignoring duplicates is cleanest.)*
  - Otherwise, find the **next upcoming timestamp `>= now`** for `target` (using `today` or `tomorrow` from `dates` already loaded in `schedule(now)`, handling post-00:00 `Midnight` / `Lastthird` timestamps properly).
  - **Placement in the countdown row (`y0 + 30 * SCALE`):**
    - **Normal prayers** (when `extra` is `nil`, i.e., no `Till Sunrise` or `Till Midnight` in Column 2): render the hovered prayer countdown in **Column 2 (`x0 + stride`)**.
    - **During Fajr -> Sunrise or Isha -> Midnight** (when `extra` is active in Column 2): render the hovered prayer countdown in **Column 3 (`x0 + 2 * stride`)**.
  - Respect `Jumu'ah` naming if the hovered Dhuhr timestamp falls on a Friday, and respect the 7th column's toggle (`Midnight` vs `Last 3rd`) if hovered!
- Check `configs/conky_prayer_times.conf` (`minimum_width = 1100 * scale`) to verify Column 3 (`x0 + 2 * stride`) never clips horizontally.
- **Config evaluation:** Uses existing `hover_failsafe_seconds` (or check if prayer hover needs anything separate—avoid duplicate keys unless needed).

**Implementation (2026-11-23):**
- `widgets/Prayer_Times.lua` registers seven independent, scale-aware `prayer_column_<1..7>` zones using measured row geometry. They coexist with the disjoint `elapsed_above_fajr` hotspot and clickable `midnight_column`; no separate hover API or new settings keys.
- The selected column is resolved to the next actual timestamp `>= now` from yesterday/today/tomorrow's cached schedules. Midnight and Lastthird are assigned their correct post-midnight **civil date**, including a pending event from yesterday's schedule. Hovering the seventh column respects the existing `Midnight` / `Last 3rd` toggle; Friday Dhuhr countdowns show `Jumu'ah` based on the event timestamp.
- The existing upcoming countdown stays in countdown Column 1. When there is no Sunrise/Midnight extra, the hovered countdown uses Column 2; when extra is present, it uses Column 3. Hovering the upcoming event or the already-visible extra does not duplicate it. Leaving the window or reaching the existing `hover_failsafe_seconds` removes the temporary countdown; a stationary pointer may time out by design.
- `test_prayer_hover.lua` executes real drawing and mouse hooks with stubbed Cairo, checking seven disjoint hitboxes at 0.65/1/1.5 scales, countdown placements, no duplicates, Friday Jumu'ah, post-midnight Lastthird, toggle behavior, cache misses, the separate elapsed-time hotspot, and timeout. No current runtime config, positioning, surface, or autostart changes.

**Acceptance & Verification:**
- [x] Offline: hovering `Isha` while `Asr` is next displays `Till Asr` (Col 1) and `Till Isha` (Col 2).
- [x] Offline: hovering `Dhuhr` after `Isha` (before `Midnight`) displays `Till Fajr` (Col 1), `Till Midnight` (Col 2), and `Till Dhuhr` (Col 3) when the next Dhuhr is Sunday; on Thursday night it correctly says `Till Jumu'ah` for Friday.
- [x] Offline: hovering an already-visible upcoming or Sunrise/Midnight extra event produces no duplicate countdown; seventh-column hover follows Last 3rd toggle and rollover.
- [x] Offline: `elapsed_above_fajr` shows `Since <previous>` only from the full-column-sized rectangle above Fajr, not on any prayer column; mouse_leave clears hover, and failsafe zero keeps stationary hover steady; countdown Column 3 fits test windows.
- [x] Live KDE: user confirmed working seven-column countdowns, steady stationary hover with `hover_failsafe_seconds = 0`, and the full-column-sized elapsed hotspot above Fajr (2026-11-23).
- [x] Findings & Handoff Log updated.

---

### [ ] Task 7: Unified Notification Service + Pre-Prayer Alerts & White Days / Ramadan Fasting Logic — Implemented Offline; Live KDE Verification Pending
**Goal:** Create a shared desktop notification service (`notify-send`) supporting 15-minute pre-event prayer warnings and post-Maghrib Hijri fasting reminders (13, 14, 15), with full Ramadan suppression.

**Implementation Notes:**
1. **Create `lib/Notify.lua`:**
   - Sends desktop notifications via `notify-send` (escaped safely with `shell_quote`, non-blocking `&`, graceful no-op if `notify-send` is unavailable).
   - **Persistent Deduplication:** Store sent notification keys (e.g., `2026-11-22:Asr:15m`, `1448-07-13:fast`) in `~/.cache/conky-notifications/sent.cache` (with `XDG_CACHE_HOME` support, pruning old entries) so `restart.py` or multiple draws never re-fire the same notification.
   - **Startup / Sleep-Wake Guard:** Do not blast stale notifications immediately at process startup or after long suspend (`now - last_check <= 120` or checking narrow active windows).
2. **Mode 1 — 15-Minute Pre-Event Reminders (in `widgets/Prayer_Times.lua`):**
   - Monitor the next upcoming event among all 5 prayers (`Fajr`, `Dhuhr`/`Jumu'ah`, `Asr`, `Maghrib`, `Isha`), plus `Sunrise` and `Midnight`.
   - When `0 < event.ts - now <= lead_seconds` (default `15 * 60`s), fire `Notify.send_once(...)` (e.g., title `"Asr in 15 minutes"` or `"Sunrise in 15 minutes — Fajr ends soon"`, `"Midnight in 15 minutes"`).
   - Use `Jumu'ah` in the notification text when Friday's Dhuhr is upcoming.
3. **Mode 2 — White Days Fasting Reminder & Ramadan Suppression (in `widgets/Hijri_Date.lua`):**
   - At/after Maghrib (`rollover == true`, when the displayed Hijri date advances to the new Islamic night/day):
     - If `month ~= 9` (NOT Ramadan) and `day` is `13`, `14`, or `15`: send `Notify.send_once(...)` once per Hijri date—e.g. `"Tomorrow is 13 of Rajab"` / `"Sunnah fasting reminder (Ayyam al-Bid)"`.
     - If `month == 9` (Ramadan): **do NOT send** the 13/14/15 fasting notification.
   - **Ramadan Red-Coloring Fix in `Hijri_Date.lua`:**
     - Currently line ~325 colors `day >= 12 and day <= 15` in `RED`. Change this so during Ramadan (`month == 9`), days `12`–`15` use normal `WHITE` (no red highlighting).
- **Config evaluation (YES — add to `settings.ini`, `configure.py`, `doctor.py`):**
  - `[behavior]`:
    - `notifications_enabled = yes`
    - `notify_prayer_minutes = 15` (0 disables pre-prayer notifications, range `0..60`)
    - `notify_fasting_days = yes` (White Days 13/14/15 reminder)
  - Check `notify-send` availability in `doctor.py` (warn as `[INFO]`/`[WARN]` if missing, not fatal error).

**Acceptance & Verification:**
- [x] `python3 configure.py --check` and interactive wizard validate the new `[behavior]` keys (offline).
- [x] `lib/Notify.lua` invokes a **fake** `notify-send` once and skips duplicates across separate Lua processes (offline). Live KDE notification appearance remains untested.
- [x] Simulated 15-minute warnings for all five prayers, Sunrise, Midnight and Friday `"Jumu'ah"`; live timing/desktop display remains untested.
- [x] Simulated Maghrib rollover for dates 13/14/15, with Ramadan suppression; still requires a live boundary verification.
- [x] Simulated Ramadan `month == 9` renders days `12..15` in `WHITE`, not `RED`.
- [x] Findings & Handoff Log updated.
- [ ] Live KDE: verify actual notifications, restart deduplication, Sunrise/Midnight reminders, Maghrib transitions and Ramadan behavior.

---

### [ ] Task 8: Celestial Astrolabe Hover Micro-Markers (5 Prayers on Dial & 24h Bar)
**Goal:** Keep the Celestial Astrolabe minimalist when idle, and on hover reveal subtle micro-markers for all 5 prayers (`Fajr`, `Dhuhr`, `Asr`, `Maghrib`, `Isha`) on **both** the circular dial and the 24h timeline bar.

**Implementation Notes:**
1. **`configs/conky_sun_moon.conf`:**
   - Add `lua_mouse_hook = 'on_mouse'` and set `update_interval = 0.25` (or keep `1` if responsive enough—verify smooth hover enter/leave; `Hijri_Date.lua` uses `0.25` when hover is active).
2. **`widgets/Sun_Moon_Astrolabe.lua`:**
   - Integrate `Hover_State.lua` (with a zone covering the dial + timeline bar).
   - Extract the 5 prayer timestamps (`Fajr`, `Dhuhr`, `Asr`, `Maghrib`, `Isha`) from `Prayer_Data.lua` (already loaded in `sun_schedule`):
     - **Important Night-Arc Alignment:** For the circular dial, daytime prayers (`sunrise <= ts <= sunset`) map onto the upper semicircle (`PI + PI * (ts - sunrise) / (sunset - sunrise)`). Nighttime prayers (`Maghrib`, `Isha`, `Fajr`) MUST match whichever night interval the dial is currently representing (`yesterday_sunset -> sunrise` before sunrise, or `sunset -> tomorrow_sunrise` after sunrise), mapped onto `0 .. PI`.
     - **24h Timeline Bar (`x = 28, w = 324`):** Map each of today's 5 prayers via `time_fraction(ts)` onto `x + frac * w`.
   - When `hover:visible('astrolabe', now)` is `true`, draw crisp micro-ticks / dots + compact minimal labels (e.g., `F`, `D`, `A`, `M`, `I` or short labels staggered cleanly above/below to avoid collisions) on **both** the circular dial and the 24h timeline bar.
- **Config evaluation:** Check whether `sun_moon_hover_failsafe_seconds` (or reusing `hover_failsafe_seconds`) is appropriate in `settings.ini` + `configure.py`. Document the decision.

**Acceptance & Verification:**
- [ ] Idle Astrolabe looks identical to before (no extra clutter).
- [ ] Hovering over the dial or timeline bar reveals all 5 prayer markers on **both** the circular dial and the 24h bar, positioned accurately relative to Sunrise/Sunset and the current time cursor.
- [ ] Moving the cursor off the Astrolabe clears the markers cleanly (and respects Wayland failsafe timeout).
- [ ] Findings & Handoff Log updated.

---

### [ ] Task 9: Named Full-Settings Profiles (Home / Office) — Implemented, Desktop Verification Pending
**Goal:** Save and switch complete, named configurations without making every widget maintain separate configuration code.

**Implementation Notes:**
- Keep exactly one active `settings.ini`, consumed unchanged by the existing Lua and Python readers. Store optional complete snapshots as `profiles/<name>.ini` (including location, appearance, behavior, and placement); these differ from `layouts/` presets, which save only placement and scale.
- Expose `configure.py --save-profile home`, `--save-profile office`, `--list-profiles`, and `--use-profile home`. Validate before saving/loading, prevent path traversal through profile names, and atomically activate a snapshot. Do not auto-overwrite a saved profile when switching away from unsaved edits.
- Document that switching requires restarting **all four widgets**, and location-keyed data caches will refresh naturally. Keep profile copies when installing from another project directory.
- **Config evaluation:** No new `settings.ini` keys. Profiles hold existing keys rather than adding per-location settings or a second active settings parser.

**Acceptance & Verification:**
- [x] Save two different snapshots, switch between them, and confirm behavior, appearance, and placement are restored; `configure.py --check` succeeds after each switch. (Location restoration follows the same full-file copy; verify visually with the desktop test.)
- [x] Invalid or missing profiles cannot modify the active file; list/save/use work without Git or other dependencies.
- [ ] Restart all four Conky windows after switching and verify they use the selected location, fonts, sizes, and positions, with no stale location-specific cache display.
- [x] Findings & Handoff Log updated.

---

### [ ] Task 10: Astrolabe Sleep/Wake and Midnight Rollover Guard — Implemented, Desktop Verification Pending
**Goal:** Never show daytime as `NIGHT 100%` after suspend or at a date rollover, even if the weather cache still contains yesterday's solar timestamps. The lunar phase and 24-hour bar already follow the current clock and do not need rewriting.

**Implementation Notes:**
- `Weather_Data.lua` intentionally returns its last cached result while a background refresh runs. In `Sun_Moon_Astrolabe.lua`, trust cached sunrise/sunset timestamps **only when `weather.local_date` equals today's system-local date**. Independently try the date-keyed prayer cache for yesterday/today/tomorrow; if neither has a complete ordered schedule, render the existing waiting state rather than a fabricated night percentage.
- Keep network fetches non-blocking and retain the existing assumption (documented in README) that the machine's timezone matches the configured location. Handle the system clock moving backward too.
- **Config evaluation:** No new keys; this is a correctness fix.

**Acceptance & Verification:**
- [x] Simulated 15:14 with a stale previous-day weather cache: DAY progress from today's prayer schedule, not `NIGHT 100%`; with the prayer cache missing too, the schedule reports waiting.
- [x] Simulated fresh current-day weather without prayer data: correct daytime; before sunrise and after sunset: night progress.
- [ ] On the user's machine, verify the dial immediately after lock/unlock, sleep/wake, and midnight rollover, and after background fetch completion. Confirm the bar cursor and lunar phase remain correct.
- [x] Findings & Handoff Log updated.

---

### [ ] Task 11: Return to Native Wayland — BLOCKED ON VERIFIED UPSTREAM SUPPORT
**Goal:** Replace the temporary Conky X11/XWayland rendering backend with
native Wayland only when the user's actual KDE environment passes all
acceptance criteria. **Do not implement merely because a new release ships.**

**Mandatory reference:** [docs/NATIVE_WAYLAND_MIGRATION.md](docs/NATIVE_WAYLAND_MIGRATION.md)
is the architecture decision record, upstream issue list, rationale for the
current XWayland backend and detailed migration acceptance gate. Read it and
recheck Conky upstream (particularly #2111, #2418 and #2432) before touching
backend code or layout calculations.

**Acceptance:** Clean SIGTERM/systemd stops for each widget; widgets remain
visible after desktop clicks and Show Desktop; reliable named-output selection
for independent native surfaces on both monitors even when the opposite output
has focus; all four widgets × nine anchors, scaling and Cairo clipping checks;
reliable hover/click input; restart, autostart, logout and hotplug tests.
**Cairo surface gate:** Verify `conky_surface()` produces visible Cairo pixels
on native Wayland and on XWayland with double buffering (or use a fully tested
alternative), not just status=0. Only then replace the deprecated Xlib surface
adapter and its explicit ownership cleanup. See the reproducible 2026-11-23
rendering tests in the mandatory migration document. Record
actual Fedora/KDE/Conky versions, logs and desktop observations. If any gate
fails, retain XWayland and keep this task unchecked. Once complete, replace
obsolete backend-specific assumptions instead of supporting parallel layouts.

---

## Findings & Handoff Log
> **Instructions for Agents:** Append a dated entry under each task you complete (or attempt). Never delete prior entries. Include: files modified/created, environment quirks (Conky version, Wayland/X11 mouse hook behavior, font glyph checks), design decisions, and exact test commands run.

### Baseline Environment Notes (Pre-Task 1)
- **Aladhan API:** `/v1/timings` returns `"Lastthird"` (lowercase `t`) inside `data.timings`. Cache header is currently `CONKY_PRAYER_V1` without `Lastthird`.
- **Font:** Default `appearance.font` is `ITC Avant Garde Pro XLt`. Watch out for unsupported Unicode characters (use ASCII `'` in `"Jumu'ah"` rather than `ʿ` U+02BF).
- **Conky Mouse Hook Caveat:** `conky_prayer_times.conf`, `conky_date.conf`, and `conky_sun_moon.conf` use `own_window_type = 'normal'`. Verify `button_down` delivery on the target Conky binary during Task 4.

### Task 1 Log
- *Status:* Implemented 2026-11-22; desktop rendering, real Conky process restart, and real `doctor.py` check remain open.
- *Files:* Moved `conky_*.conf` to `configs/`, 4 renderer `.lua` files to `widgets/`, 5 support `.lua` files to `lib/`, `prayer_fetch.py`/`weather_fetch.py`/`layout.py` to `workers/`, and `HOVER_ZONE.md` to `docs/`; added `workers/__init__.py`. Updated the moved Lua/Python files, `start.sh`, `restart.py`, `configure.py`, `doctor.py`, `install.sh`, `README.md`, `docs/HOVER_ZONE.md`, and this roadmap. Existing `settings.ini` stays at root, unmodified; no new keys are needed.
- *Path decisions:* Config and renderer Lua paths are computed relative to each source file, using `../` to reach the root from `configs/`, `widgets/`, or `lib/`. Worker scripts resolve `Path(__file__).resolve().parent.parent` to read root `settings.ini`; `layout.py` continues to store `layouts/` and `monitor_geometry.json` at root. The Athan check tries root `athan.wav` first, then `assets/athan.wav`. The installer backs up the existing destination and preserves active settings, profiles, layouts, manual monitor geometry, root Athan, and existing assets; only known superseded flat code is deleted. Retired `restart_new.py` and `upgrade_settings.py` remain unchanged in the supplied source archive as roadmap-listed root files, but are intentionally not installed (existing installer behavior).
- *Missing input:* The supplied `Archive.zip` has **no `assets/weather/*.png`**. This patch does not create image files or remove existing ones. `doctor.py` requires `assets/weather/32.png`, so a genuine 0-error diagnostic depends on the existing installed icon pack (plus a Conky binary). Do not report the fixture result as live validation.
- *Verification:* `python3 configure.py --check` passed. `python3 -m compileall -q configure.py doctor.py restart.py workers` and `bash -n start.sh install.sh` passed. A `texlua` harness loaded all four `configs/conky_*.conf`, verified each `lua_load`, loaded all four renderer files with Cairo modules stubbed, and confirmed shared settings and prayer worker paths. An isolated temporary-directory test using a stub `conky` executable and a temporary placeholder `assets/weather/32.png` produced `doctor.py` **0 errors**; it also saved/switched Home and Office profiles, verified worker layout paths, launched/listed/restarted/stopped four mock Conky processes, and verified installer backups plus retention of `settings.ini`, icon, layout, monitor geometry, audio, and profile. No real Cairo rendering, display backend, fonts, PNG pack, network calls, or KDE/Wayland process tests were available in this environment.

### Task 2 Log
- *Status:* Named-zone implementation unified 2026-11-22; real Conky/KDE hover verification still open.
- *Files:* `lib/Hover_State.lua`, `widgets/Hijri_Date.lua`, `widgets/Prayer_Times.lua`, `tests/test_hover_state.lua`, `docs/HOVER_ZONE.md`, `ROADMAP.md`. No new `settings.ini` keys or installer changes.
- *Architecture:* One API: `Hover.new(timeout)`, `set_zone(name, rect_or_rects)`, `visible(name, now)`, and `mouse(event, now)`. Deleted single-zone `active` and scalar timestamp state, `area` dispatch, `set_zones(...)`, and overloaded `visible(now)`. Date uses zone `weather`; Prayer uses `fajr_sunrise` with geometry based on its existing `hover_area` setting (`fajr_sunrise`, `content`, or full `window`). All zones fail closed if event coordinates are missing (rather than guessing where the pointer is); zero timeout disables expiry.
- *Verification:* `texlua tests/test_hover_state.lua` covers independent and overlapping zones, multi-rectangle zones, deletion, updates, missing coordinates, leave, timeout, rejection of the old signature, and both real widget draw/mouse paths with Cairo and cache stubbed. `python3 configure.py --check` passed. Actual desktop Conky/Wayland rendering and hover timing were not exercised; keep the two live-widget acceptance boxes unchecked.

### Task 3 Log
- *Status:* Implemented 2026-11-22; actual desktop Cairo rendering and installed PNG pack verification pending.
- *Files:* Added `lib/Weather_Icons.lua` and `tests/test_weather_icons.lua`; updated `widgets/Weather.lua`, `widgets/Hijri_Date.lua`, `README.md`, and `ROADMAP.md`. No new `settings.ini` keys needed.
- *Architecture:* Moved the unchanged full WMO mapping (including `97` -> `37`/`47`) and lazy PNG surface cache/drawing into one module. Both widget paths now call `Weather_Icons.code` and `Weather_Icons.draw`; no widget-local PNG loader, mapping, old API, or compatibility wrapper remains. Each Conky Lua process owns its own cache.
- *Verification:* `texlua tests/test_weather_icons.lua` passed all 30 WMO+fallback cases for both day/night, lazy cached PNG paths, and the actual Weather current and Date current/three-day-hover drawing paths with Cairo and caches mocked. `texlua tests/test_hover_state.lua` and `python3 configure.py --check` passed. Tests confirmed `97` uses PNG `37` during day and `47` at night, and repeated IDs are only loaded once per module instance. No real PNG icons were present in the supplied archive, and no Conky/Cairo display was available; visually confirm current/forecast images on the user's desktop before checking the remaining rendering acceptance box.

### Task 4 Log
- *Status:* Implemented 2026-11-22; actual Conky click dispatch, `doctor.py --fetch` HTTPS fetch, and desktop rendering remain unverified.
- *Files:* Updated `workers/prayer_fetch.py`, `lib/Prayer_Data.lua`, `lib/Hover_State.lua`, `widgets/Prayer_Times.lua`, `README.md`, `docs/HOVER_ZONE.md`, and this roadmap; added `tests/test_prayer_cache.py`, `tests/test_prayer_click.lua`, `tests/conky_mouse_probe.conf`, and `tests/conky_mouse_probe.lua`. `settings.ini` is untouched.
- *Cache and UI:* Both cache writer and reader require `CONKY_PRAYER_V2` with Aladhan's exact `Lastthird` value; V1 and incomplete V2 are rejected and refetched (not accepted through a compatibility parser). `Prayer_Times.lua` uses one `show_last_third` boolean starting false and one named `midnight_column` zone for direct left-button hit testing. Only the seventh displayed label/time change; `schedule()` still computes post-Isha `extra` from `times.Midnight` (unaffected). The click is consumed only when inside the column. No default setting was added: starting on Midnight each widget launch is sufficient.
- *Conky pre-check/environment:* In the patch-building environment, `conky --version` is **not available** (`conky` not installed); `XDG_SESSION_TYPE` is **unset** (a `DISPLAY=:0` variable alone does not establish a KDE/X11 session). Therefore real `button_down` / `button_up` delivery with `own_window_type = 'normal'` is **unknown, not passed or failed**. Synthetic Lua events `button_down` (`button='left'`) work and wrong buttons/regions do not toggle. Conky's documented mouse-hook API uses these event values; some X11/XWayland builds may drop button events. Added the isolated `tests/conky_mouse_probe.conf` + `.lua` for the user to record `conky --version`, `XDG_SESSION_TYPE`, and `button_down` / `button_up` from a real desktop, without altering the production implementation. If click delivery fails on the user's Conky binary, first inspect that log and the installed mouse-event build support; do not change window type speculatively.
- *Verification:* `PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p test_prayer_cache.py -v` passed 4 tests (API `Lastthird` required, V2 encoding, V1 rejected/refetched, no duplicate fetch with current V2, mocked Aladhan fetch retains API value). `texlua tests/test_prayer_click.lua` passed (Lua cache V1/incomplete V2 rejection, named-zone direct hit-testing, real widget toggle in both directions, click filtering, missing-data hitbox removal, and `Till Midnight` preserved after Isha). `texlua tests/test_hover_state.lua`, `texlua tests/test_weather_icons.lua`, and `python3 configure.py --check` passed. No real Conky, mouse events, live Aladhan HTTPS, or display rendering was available to verify here.

### Task 4 Desktop Follow-Up (2026-11-22)
- *User environment:* KDE Plasma Wayland (`XDG_SESSION_TYPE=wayland`) with Conky `1.22.2-pre-`, compiled with both X11 and Wayland mouse-event support. Terminal output `desktop window ... is root window` / `drawing to created window ...` strongly indicates the supplied mouse probe used the X11/XWayland backend. The user reports the seventh-column toggle does not work; the old probe was invisible except during a screenshot, so **button delivery has not yet been directly established**.
- *Root cause of diagnostic failure:* `tests/conky_mouse_probe.conf` reused desktop-widget flags `below` plus transparency; this is unsuitable for a foreground click test on KDE Plasma. The probe now uses an opaque, above-stack normal window, forces X11 for controlled comparison, and reports movement, buttons and coordinate types. Added a separately named native-Wayland probe without changing any of the four production configs.
- *Upstream finding:* Conky issue <https://github.com/brndnmtthws/conky/issues/2288> documents missing `button_down` / `button_up` and malformed coordinates in 1.22.2; fixes landed by May 2026 and are included in 1.23.0. The presence of compiled mouse-event support does not prove the runtime delivers button clicks. If the corrected probe confirms the missing events, upgrade Conky rather than add a redundant input system or change prayer widget geometry speculatively.
- *Status:* Task 4 click acceptance **open** until an actual visible probe yields correct left-button events and the seventh column toggles. No Task 5 implementation started.

### Native Wayland Migration Log (2026-11-22; pending actual Fedora 45 desktop verification)
- *User observation:* Conky `1.22.2-pre` on Fedora 44 / Plasma Wayland logs mouse movements but **no clicks** in the X11/XWayland probe; the native Wayland probe logs `button_down button=left` and `button_up button=left`, with numeric coordinates. The click handler itself is not the culprit. The previously delivered Prayer-only native patch was **not** applied; this changes all widgets together.
- *Distribution check:* Fedora 44 packages `conky-1.22.2-3.fc44`; Fedora 45 packages `conky-1.24.2-3.fc45` (Fedora package listings, checked 2026-11-22). Conky 1.23.0 added `conky_surface()` to enable backend-independent Lua/Cairo drawing. **Upgrade to Fedora 45/Conky 1.24.2 before installing this migration patch.**
- *Architecture:* All four `configs/conky_*.conf` explicitly enable native Wayland and disable X output. They use a transparent `desktop` layer-shell role and no obsolete ARGB/transparent X11 settings. `lib/Surface.lua` exclusively returns Conky's own `conky_surface()` (no `cairo_xlib`, fallback or surface destruction). All four widgets use that one API. Native runtime validation in `doctor.py` is invoked by `start.sh`, failing closed on old Conky or a non-Wayland session. Remove the old X11 mouse probe; retain one visible native-Wayland event probe. No new user-config key was needed.
- *Placement caveat:* Conky 1.24.2's Wayland layer-shell API does not allow choosing a named output per widget; gap X/Y are output-local, **not** KDE virtual desktop pixel coordinates. Remove XRandR placement fallback and global-coordinate math. Auto-layout runs only with one active monitor; multiple outputs require manual output-local positions and real KDE confirmation. Preserve existing user settings/profiles (no automatic conversions or guessed monitor assignments).
- *Offline verification:* `texlua tests/test_native_wayland.lua`, `texlua tests/test_hover_state.lua`, `texlua tests/test_weather_icons.lua`, `texlua tests/test_prayer_click.lua`, `python3 -m unittest discover -s tests -p 'test_*.py'` (7 tests), `python3 configure.py --check`, and `bash -n start.sh install.sh` all passed. The test fixture verifies the runtime gate accepts `1.24.2` and rejects `1.22.2-pre`, and verifies layout computations are output-local. Full patch application against the prior diagnostic baseline checked separately. **Real Conky 1.24.2 / KDE** layering over wallpaper, opacity, positioning, four-widget Cairo output, hover and column click still open. Do not check off Task 4 or advance to Task 5 until visible desktop testing passes.
- *Upstream caveat:* Conky 1.24.3 release notes changed handling of Wayland `own_window_hints` and layer-shell `normal` stacking. Fedora 45's currently published 1.24.2 does not include those later changes; this patch uses `desktop` to request a native layer-shell rather than pretending `normal`+`below` will work. Test actual Plasma visibility before considering another window role.

### XWayland acceptance and prayer-click responsiveness (user confirmation, 2026-11-23)
- **User's live confirmation:** All four widgets displayed correctly under the restored Fedora 45 / Conky 1.24.2 X11/XWayland setup, with no missing functionality. The Midnight/Last 3rd left-click toggle works, and reducing Prayer Times `update_interval` from 1 to **0.25** in the installed `configs/conky_prayer_times.conf` eliminated the objectionable click-to-redraw lag. This interval was changed **manually** by the user; do not include the config line in the Task 5 patch (it would conflict with the already-modified working file).
- **Scope of confirmation:** Close the reported blank-widget Cairo regression and record the live click/regular-use check. This does **not** establish that `python3 doctor.py --fetch`, all `restart.py` modes, profile switching, simulated suspend/midnight rollover, or each alternate hover mode has been tested on desktop. The corresponding narrowly defined acceptance checkboxes remain open; do not misrepresent the historical 1.22.2 mouse-hook report as describing the current 1.24.2 behavior.

### Task 5 Log (2026-11-23)
- *Status:* Implemented and tested offline. Real KDE/Conky visual verification remains open; do not check off the Task 5 heading until the user confirms the column contrast and the Friday ASCII text in the actual selected font.
- *Files:* `widgets/Prayer_Times.lua`, `tests/test_next_prayer.lua`, `README.md`, `ROADMAP.md`. No `settings.ini`, XWayland, Cairo surface, autostart, cache-format, or notification changes.
- *Behavior:* The next canonical prayer (`Fajr`, `Dhuhr`, `Asr`, `Maghrib`, or `Isha`) has alpha 1.0 on **both** its main-row heading and time; all six other columns use 180/255. After Isha the next-day Fajr is highlighted, while the next-prayer and post-Isha `Till Midnight` countdown behavior remains unchanged. `prayer_display_name(name, ts)` changes only Friday-dated `Dhuhr` events to ASCII `Jumu'ah`: Friday's main-row heading, upcoming `Till Jumu'ah`, and elapsed `Since Jumu'ah`. Schedule events stay canonically named `Dhuhr` so sorting and column matching do not change. The row reserves measured width for Friday's longer heading and the alternate `Last 3rd` title. No new settings: fixed subtle styling and calendar-based naming are automatic.
- *Verification:* `texlua tests/test_next_prayer.lua` exercises Friday before/after noon, Thursday and Saturday names, tomorrow's Fajr highlight, alpha values, countdowns, Midnight/Last 3rd interaction, and no Jumu'ah/Asr overlap at scales 0.65, 1.0, 1.5 (mock Cairo). Existing four Lua regression suites, 15 Python tests, `python3 configure.py --check`, `python3 -m compileall -q .` and `bash -n start.sh install.sh` passed offline. **Still requires visible testing** in the actual `ITC Avant Garde Pro XLt` font (glyphs, alignment and contrast) and real Friday scheduling; no live Conky available in patch environment.

### Task 5 visual revision / Maghrib boundary (2026-11-23)
- *User feedback:* Initial all-white next-column brightness was too prominent. Replace that emphasis rather than layering more styling over it. The requested reference is **variation 03 (vertical accent line)** from `isha-highlight-variations.html`: a gold line and gold **name only**, using its `#efb46f` color. The change is cosmetic; all large times keep their pre-Task-5 white alpha and no other widget is touched.
- *Day semantics:* The row label advances with the Islamic date at **local Maghrib**. Thursday at Maghrib => Friday Jumu'ah; Friday at Maghrib => Saturday Dhuhr. The third column must use the corresponding next civil day's cached Dhuhr clock time after Maghrib. If the next-day cache is still fetching, show `--:--` rather than displaying yesterday's clock time as Jumu'ah. All other displayed columns keep today's timings; real `Till`/`Since` event labels and athan timing remain timestamp-based.
- *Configuration:* `appearance.next_prayer_color` is optional, defaults to `#efb46f`, accepts `#RRGGBB`, and is shared by the sideline and its label. Existing `settings.ini` is intentionally not patched; see the README for how to override. Keep the user's existing `update_interval = 0.25` untouched.
- *Verification:* The new offline test exercises exact Maghrib transitions, different Thursday/Friday Dhuhr times, absent next-day cache, default/custom/invalid colors, scaled sideline placement, unchanged white time colors, and the Midnight/Last 3rd click. This **supersedes** the original Task 5 bright-white behavior described in the historical log above. User has not yet confirmed the new style on the actual desktop; leave Task 5 unchecked until then.

### Task 6 Log
- *Status:* Pending
- *Notes:* —

### Task 7 Log (2026-11-23)
- *Status:* Implemented and tested offline; KDE notification display and actual calendar transitions remain **unverified**.
- *Files:* `lib/Notify.lua`, `widgets/Prayer_Times.lua`, `widgets/Hijri_Date.lua`, `settings.ini`, `configure.py`, `doctor.py`, `tests/test_notifications.lua`, `tests/test_notify_service.py`, `docs/NOTIFICATIONS.md`, `README.md`.
- *Design:* Two independent event paths share one `send_once` API. A notification is sent only when a running widget witnesses a time threshold crossing (cold start, restart or sleep/wake must never backfill stale reminders). Date allows a two-minute cache-arrival grace period only after witnessing Maghrib. No network access or blocking sleeps in the Conky draw hook.
- *Dedup:* Atomic per-key `mkdir` markers under XDG_CACHE_HOME, plus a non-authoritative `sent.cache` audit log; attempts from multiple Conky instances or after restart are not repeated. `notify-send` title/body arguments are shell-quoted and launched in the background. Old key markers are pruned after 60 days.
- *Ramadan:* Hijri month 9 suppresses Ayyam al-Bid reminder on 13/14/15 and day-number red highlight on days 12/13/14/15.
- *Verification:* Simulated all five prayer events, Jumu'ah, Sunrise, Midnight, startup/wake guard, dates 13/14/15 and Ramadan styling. Separate-process fake notify-send integration confirmed quoted titles/messages and dedup. Normal widget rendering and layout tests still pass. **Do not mark Task 7 complete until user's live KDE results.**


### Task 8 Log
- *Status:* Pending
- *Notes:* —
### Task 9 Log
- *Status:* Implemented in patch on 2026-11-22; still needs live four-widget profile-switch verification.
- *Files:* `configure.py`, `install.sh`, `README.md`, `ROADMAP.md`; snapshots created by the user in `profiles/`, not bundled into the patch. The user's active `settings.ini` is untouched.
- *Design:* Full-file snapshots keep the existing active `settings.ini` model; `layouts/` presets stay independent. No schema migration, new settings keys, or automatic overwriting of a profile on switch.
- *Verification:* `python3 configure.py --check`, `--save-profile home`, `--save-profile office` with different values, `--list-profiles`, `--use-profile home/office`, and settings checks passed. Rejected `../bad`, missing profile, and invalid profile without modifying the active file. `python3 -m compileall -q configure.py weather_fetch.py prayer_fetch.py` and `bash -n install.sh` passed. Desktop Conky is unavailable in the patch-building environment.

### Task 10 Log
- *Status:* Implemented in patch on 2026-11-22; live KDE sleep/wake check remains open.
- *Files:* `Sun_Moon_Astrolabe.lua`, `README.md`, `ROADMAP.md`.
- *Finding:* `Weather_Data.lua` keeps previous cache values while refreshing. Previously, `sun_schedule()` used those previous-day values while also skipping the prayer fallback when weather existed but its `local_date` was wrong. The clock-based cursor and moon phase can remain correct while the dial is stale.
- *Verification:* Executed a Lua schedule harness against the actual `sun_schedule()` function (via `texlua`): previous-day weather + current-day prayer = DAY 83.9% at 15:14; previous-day weather + no prayer = waiting; current-day weather + no prayer = DAY; before sunrise / after sunset = NIGHT. No actual Conky/KDE session or suspend capability available here.

### Layout architecture revision (2026-11-23; offline implemented, live validation pending)
- **Scope:** All four widgets and all nine anchors, not a widget-specific date/weather offset workaround. Added `widget_geometry.ini`, shared by Python `workers/layout.py` and Lua `lib/Widget_Geometry.lua`; dimensions are identical minimum Conky window canvases, *not* guaranteed Cairo ink bounds.
- **Multi-monitor boundary:** [Conky #2111](https://github.com/brndnmtthws/conky/issues/2111) still open; KScreen output names/geometry cannot force Conky 1.24.2 surfaces to an output. Removed obsolete absolute-virtual-desktop claims and Python global-coordinate addition. Multi-output operations require explicit `--allow-unverified-output`, otherwise leave active settings untouched; intent does not equal actual placement.
- **Data model:** The wizard stores `[layout]` target output, anchor, X/Y margins per widget, plus derived local runtime offsets in `[placement]`. `--reflow-layout` recalculates coordinates when geometry/scale changes. Named layout presets now store intent/scales, not old raw X/Y; coordinate-only presets need recreation. Full-settings profiles continue to be snapshots.
- **Verification:** Python unit tests exercise 4 widgets × 9 anchors, multi-output opt-in and refusal, reflow, stale detection, persistence and declarative presets; existing Lua native-Wayland, hover, weather and prayer test suites run offline. Live dual-monitor KDE Conky placement and actual Cairo ink clipping are **not verified**. See `docs/WAYLAND_LAYOUT.md` for future feature triggers and acceptance criteria.

### Temporary XWayland restoration (2026-11-23; desktop verification pending)
- **Decision:** Reverted four Conky configs to explicit X11 output via XWayland while keeping KDE on Wayland. Current Conky 1.24.2 native Wayland failures: stop timeout/ABRT, widgets obscured by desktop clicks, inability to target the second monitor independently. Not proven resolved by a later version.
- **Architecture:** Kept shared `widget_geometry.ini`, backend-neutral Cairo surface, and single layout engine; all nine anchors calculate X11 global coordinates from KScreen output geometry plus local anchor offsets. Reflow saved `[layout]` intent without overwriting the user's active `settings.ini` in the patch. Removed the experimental multi-monitor opt-in as no longer appropriate.
- **Future:** ROADMAP Task 11 stays blocked; `docs/NATIVE_WAYLAND_MIGRATION.md` documents root causes, upstream links and full acceptance gate. Do not migrate just because the upstream Conky version changes.
- **Tests and remaining work:** 15 Python tests, four `texlua` suites, configuration validation and shell syntax passed offline. Patch installation is validated separately; live KDE visual stacking, mouse-click behavior, XWayland geometry alignment, Cairo clipping and clean systemd shutdown require confirmation from the user. The historical native Wayland log above records the previous architecture, not the current one.

### XWayland Cairo regression and surface restoration (2026-11-23; live functionality confirmed)
- **Evidence:** User's XWayland screen is 3840×1080 with all four windows mapped
  on-screen. Conky built-in Date text appeared. A `conky_surface()` Cairo probe
  with double buffering drew nothing; with single buffering its rectangle
  appeared but flickered (Cairo statuses 0). With Xlib surface creation and
  double buffering the rectangle appeared without flicker (statuses 0).
  Date systemd stops now exit cleanly under XWayland. Upstream root cause not
  established. See `docs/NATIVE_WAYLAND_MIGRATION.md` for exact tests and
  acceptance criteria. The isolated probe was not enough by itself; the
  subsequent full-widget test was confirmed by the user (see below).
- **Files:** `lib/Surface.lua`, four `widgets/*.lua`, `doctor.py`, the XWayland
  regression tests and their Lua drawing stubs, `README.md`,
  `docs/NATIVE_WAYLAND_MIGRATION.md`, and this roadmap.
- **Decision:** XWayland/Conky 1.24.2 explicitly uses deprecated `cairo_xlib`
  to create widget-owned Cairo surfaces; every widget releases each surface
  after destroying the context. No silent `conky_surface()` fallback. Native
  Wayland remains blocked by Task 11. Keep existing layout and autostart.
- **Verification:** Offline Lua and Python tests cover surface acquisition,
  ownership, all four widget renderer paths, X11 configuration, and layout.
  **Live user confirmation (2026-11-23):** After applying the Xlib restoration,
  all four widgets worked as before and no functionality was missing. This
  closes the immediate blank-widget regression. Do not conflate this report
  with explicit testing of every hover/click path, Show Desktop, logout/login,
  hotplug, mixed-DPI or future native Wayland releases. Task 11 remains blocked.


### Task 6 — Prayer-column countdown hover (2026-11-23; offline implemented, live validation pending)
- **Task 5 handoff:** User confirmed the sideline style and Jumu'ah changes appear correctly and requested Task 6. Marked Task 5 feature complete; an actual Thursday/Friday Maghrib rollover still needs live observation and is not falsely claimed as tested.
- **Design:** Added one named `prayer_column_1` through `prayer_column_7` hover zone per on-screen prayer; these share `lib/Hover_State.lua` with the existing upper elapsed-time hotspot and Midnight toggle click target. Countdown 1 (`Till upcoming`) and conditional countdown 2 (`Till Sunrise` / `Till Midnight`) are untouched; only one additional hovered target may occupy the next free slot. No new user settings or backend-specific code.
- **Temporal correctness:** Look up the next occurrence from previously loaded cached yesterday/today/tomorrow dates, not from whichever civil-day time happens to be printed in the row. Correctly carry post-midnight `Midnight` / `Lastthird` from the previous schedule; use event-date Jumu'ah naming. Ignore a hovered target if that event is already shown as upcoming/extra. Missing future caches never fabricate a countdown.
- **Verification:** `texlua tests/test_prayer_hover.lua` tests real widget draw/mouse code at three scales with deterministic cache; existing Task 4/5 tests and Python tests run offline. No live KDE verification is claimed until user confirms. The named hover's stationary-pointer timeout is inherited from `hover_failsafe_seconds` (default site value can be as low as 1 second) and is intentional under the current hover API.

### Task 6 Hover-Region Regression Follow-Up (2026-11-23; offline fixed, live verification pending)
- **User report:** New prayer-column hover countdowns work; `hover_failsafe_seconds = 0` stops stationary-hover flicker, but elapsed `Since` also appears when hovering over Fajr/Sunrise's visible row instead of only the empty area above Fajr. The screenshot marks both regions. Do not mistake timeout configuration for a hitbox correction.
- **Root cause:** Prayer's older `hover_area` modes registered a hotspot reaching into the visible prayer row; `content` and `window` modes were even broader. These areas overlap Task 6's per-prayer zones.
- **Resolution:** Removed the `hover_area` modes and wizard prompt, renamed the single internal zone to `elapsed_above_fajr`, and sized it from Cairo's measured `x0`, `max_width` and `prayer_scale` so its bottom remains above the column hover zones. `settings.ini` is intentionally excluded from the patch because it contains active user settings: an existing `hover_area` line is ignored and can be deleted. The optional red debug outline traces the single new zone. `hover_failsafe_seconds = 0` remains a user preference, not a forced source-code setting.
- **Verification:** `texlua tests/test_prayer_hover.lua` checks the upper hotspot, all seven forbidden column regions, right/bottom boundaries, scaling (0.65, 1, 1.5) and persistent stationary hover with zero failsafe. `texlua tests/test_hover_state.lua` checks the real Prayer/Date mouse hooks. Live KDE acceptance still pending; do not mark Task 6 completed until the user confirms. No changes to the Xlib surface renderer, refresh rate, placement, or autostart.

### Task 6 — Elapsed Hover Box Sized to Reference Screenshot (2026-11-23; KDE verification pending)
- **User correction:** The first nonoverlapping `elapsed_above_fajr` rectangle was too short. The provided screenshot specifies a box directly above Fajr with roughly the same height and width as a visible prayer name+time column; the rest of Task 6 works and `hover_failsafe_seconds = 0` stopped stationary hover blinking.
- **Geometry:** Share the measured Fajr column width and prayer-row top/bottom coordinates. The elapsed hotspot has the **same height as one prayer-column hitbox** and sits directly above it with a `3 * prayer_scale` gap; all seven column hitboxes now begin at the visible heading area instead of reaching far into the upper blank space. Keep the elapsed hotspot, all seven prayer zones, and the Midnight click zone independent. The screenshot's approximately 157×85 pixel red box is a **reference at that particular user scale**, not a hardcoded rectangle to paste into other displays/scales.
- **Regression gate:** Check equal hitbox heights, a nonoverlapping scaled gap, all seven column zones, pointer-leave behavior and scale variants offline. Verify the enlarged hotspot and column-hover behavior in a live KDE session before marking Task 6 complete. No settings, Xlib surface, autostart or layout changes.

### Task 6 User Acceptance (2026-11-23)
- User confirmed the enlarged elapsed-time hover box above Fajr is working and requested proceeding. Task 6 is now complete; the XWayland hover failsafe remains explicitly configured as `0` in the user's local settings.
