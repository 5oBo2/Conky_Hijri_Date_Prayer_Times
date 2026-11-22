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

---

## Architecture Dependency Order

```text
Task 1 (Repo Organization)
   ├──► Task 2 (Named Hover Zones in Hover_State.lua)
   │       ├──► Task 4 (Aladhan Lastthird + Click Toggle) ──► Task 5 (Next-Prayer Highlight + Jumu'ah) ──► Task 6 (Second Hover Zone) ──► Task 7 (Unified Notify Service + Ramadan Fix)
   │       └──► Task 8 (Astrolabe Hover Prayer Markers)
   └──► Task 3 (Shared Weather_Icons.lua)
```

---

## Task Checklist

### [ ] Task 1: Reorganize Repository Directory Structure
**Goal:** Move files out of the single flat root directory into a clean, maintainable layout while keeping user-facing CLI entrypoints simple.

**Target Layout (adapt only if an existing script/autostart requires an adjustment—document any deviation):**
- Root (user-facing entrypoints & config):
  - `settings.ini`, `README.md`, `ROADMAP.md`
  - `install.sh`, `start.sh`, `restart.py`, `configure.py`, `doctor.py`, `upgrade_settings.py`, `restart_new.py`
- `configs/`: `conky_prayer_times.conf`, `conky_date.conf`, `conky_weather.conf`, `conky_sun_moon.conf`
- `widgets/`: `Prayer_Times.lua`, `Hijri_Date.lua`, `Weather.lua`, `Sun_Moon_Astrolabe.lua`
- `lib/`: `Settings.lua`, `Surface.lua`, `Hover_State.lua`, `Prayer_Data.lua`, `Weather_Data.lua` (future `Weather_Icons.lua` and `Notify.lua` will live here)
- `workers/`: `prayer_fetch.py`, `weather_fetch.py`, `layout.py`
- `docs/`: `HOVER_ZONE.md` (and any new technical notes)
- `assets/`: existing `assets/weather/*.png` (and optional `athan.wav` search path—check both root and `assets/` for `athan.wav` for backward compatibility!)

**Implementation Notes:**
- Audit every `dofile(...)`, `lua_load`, `assets/weather/` path, `settings.ini` path, `prayer_fetch.py` / `weather_fetch.py` invocation, `restart.py` `CONFIGS` paths, `start.sh`, `install.sh`, `doctor.py`, `configure.py` (`import layout`), and `README.md`.
- Introduce a reliable root-resolution pattern in Lua (e.g., resolving `ROOT` from `debug.getinfo(1, 'S').source` or passing `package.path`) and Python (`sys.path` / `ROOT = Path(__file__).resolve().parent.parent` for `workers/`).
- Preserve backward compatibility for user files at root (`settings.ini`, `athan.wav`, `monitor_geometry.json`, `layouts/`).
- **Config evaluation:** No new `settings.ini` keys needed.

**Acceptance & Verification:**
- [ ] `python3 configure.py --check` passes.
- [ ] `python3 doctor.py` passes with 0 errors.
- [ ] `python3 restart.py --list` and `python3 restart.py` find, stop, and restart all 4 `configs/conky_*.conf` instances cleanly.
- [ ] All 4 widgets render normally with fonts, weather PNG icons, prayer data, and weather data loaded.
- [ ] Findings & Handoff Log updated.

---

### [ ] Task 2: Upgrade `lib/Hover_State.lua` for Named Multi-Zone Support
**Goal:** Allow a single Conky window to define and query multiple independent hover zones (e.g., `'weather'` vs `'hijri'`, or `'fajr_sunrise'` vs individual prayer columns) without them triggering each other.

**Implementation Notes:**
- Extend `Hover_State.lua` so one `Hover.new(timeout, area)` instance can track **named zones** alongside existing single-zone usage:
  - Keep `state:set_zones(zones)` and `state:visible(now)` working identically for existing callers (backward compatible).
  - Add `state:set_zone(name, rect_or_rects)` (or `set_named_zones({ name = rect, ... })`) and `state:visible(name_or_now, maybe_now)`:
    - When `mouse_enter` / `mouse_move` fires, determine which named zone(s) contain `(event.x, event.y)` and mark only those active (updating `last_input_at`), clearing non-matching zones immediately.
    - When `mouse_leave` fires or the Wayland failsafe `timeout` expires, clear all active zones.
    - Expose a helper if needed (e.g., `state:active_zone(now)` returning the active zone name or `nil`).
- Update `widgets/Hijri_Date.lua` and `widgets/Prayer_Times.lua` to ensure zero regression in existing hover zones (`date_and_weather` 3-day forecast and `fajr_sunrise` elapsed timer).
- **Config evaluation:** No new `settings.ini` keys needed.

**Acceptance & Verification:**
- [ ] Existing `Hijri_Date.lua` right-side weather hover still opens/closes as before.
- [ ] Existing `Prayer_Times.lua` `fajr_sunrise` hover (and `hover_area` modes `fajr_sunrise` / `content` / `window`) still behaves identically.
- [ ] Unit/smoke test in Lua confirms two named zones in one `Hover` instance trigger independently and expire on `mouse_leave` and timeout.
- [ ] Findings & Handoff Log updated.

---

### [ ] Task 3: Deduplicate Weather Icon Mapping & Drawing (`lib/Weather_Icons.lua`)
**Goal:** Eliminate the duplicate `icon_code(wmo, day)` mapping and PNG surface cache currently copy-pasted across `Weather.lua` and `Hijri_Date.lua`.

**Implementation Notes:**
- Create `lib/Weather_Icons.lua` containing:
  - `M.code(wmo, day)` (the full WMO-to-PNG mapping including code `97` -> `37`/`47`).
  - `M.draw(cr, id, x, y, size)` (lazy PNG surface cache loading from `<ROOT>/assets/weather/<id>.png`).
- Refactor `widgets/Weather.lua` and `widgets/Hijri_Date.lua` to call `Weather_Icons.code(...)` and `Weather_Icons.draw(...)` and remove their local copies.
- **Config evaluation:** No new `settings.ini` keys needed.

**Acceptance & Verification:**
- [ ] `Weather.lua` and `Hijri_Date.lua` render identical weather icons (current conditions + 3-day hover forecast) with no missing PNGs.
- [ ] Only one copy of `icon_code` exists in the codebase.
- [ ] Findings & Handoff Log updated.

---

### [ ] Task 4: Aladhan `Lastthird` Caching & Click Toggle on Midnight Column
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
- [ ] Clicking the 7th column toggles between `Midnight` (`times.Midnight`) and `Last 3rd` (`times.Lastthird`).
- [ ] Between Isha and Midnight, toggling the 7th column to `Last 3rd` does **not** alter `Till Midnight` in the countdown row.
- [ ] Findings & Handoff Log updated (including Conky `button_down` behavior notes).

---

### [ ] Task 5: Next-Prayer Subtle Row Highlight & Dynamic `Jumu'ah` Naming
**Goal:** Make the upcoming prayer stand out gently in the 7-column row, and display `Jumu'ah` instead of `Dhuhr` whenever the displayed/next Dhuhr is Friday's Jumu'ah prayer.

**Implementation Notes:**
1. **Subtle Brightness Highlight:**
   - In `widgets/Prayer_Times.lua`, use a brighter color (`alpha = 1.0`, e.g., `{1, 1, 1, 1}`) for the column matching `upcoming.name` (both header and time), and slightly softer white (e.g., `{1, 1, 1, 165/255}` or `{1, 1, 1, 180/255}`) for the other columns so the contrast is clear yet minimal and refined.
   - Check edge case: if `upcoming` is tomorrow's `Fajr` (after Isha), the `Fajr` column highlights. If `upcoming` is `Dhuhr`/`Jumu'ah`, match the 3rd column cleanly.
2. **Dynamic `Jumu'ah` Naming:**
   - Helper `prayer_display_name(name, ts)`: if `name == 'Dhuhr'` and `os.date('*t', ts).wday == 6` (Friday in Lua: `1=Sun .. 6=Fri`), return `"Jumu'ah"`.
   - **Font Glyph Check:** Verify `ITC Avant Garde Pro XLt` renders `"Jumu'ah"` (ASCII `'`) cleanly with no missing-glyph box. (Do NOT use `ʿ` U+02BF unless verified in the font!)
   - Apply this naming to:
     - The main 7-column row on Fridays (`os.date('*t', now).wday == 6`).
     - `Till Jumu'ah` countdown when the upcoming prayer is Friday's Dhuhr (even if viewed on Thursday after Dhuhr? Note: if `upcoming` is Thursday's Dhuhr, it says `Till Dhuhr`; once Thursday's Dhuhr passes and the *next* Dhuhr is Friday's, or on Friday itself, `Till Jumu'ah` / `Since Jumu'ah` applies).
     - Check horizontal spacing so `"Jumu'ah"` does not collide with `"Asr"` at `prayer_scale` values.
- **Config evaluation:** Skip config—this is automatic visual polish and calendar logic.

**Acceptance & Verification:**
- [ ] Upcoming prayer column is visibly brighter than the other 6 columns without harsh boxes or color clashes.
- [ ] Simulate Friday (`wday == 6`) and confirm main row + `Till Jumu'ah` + `Since Jumu'ah` render `"Jumu'ah"` cleanly with no overlap or tofu glyphs.
- [ ] Findings & Handoff Log updated.

---

### [ ] Task 6: Prayer Widget Second Hover Zone (Hover Any Prayer for Its Countdown)
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

**Acceptance & Verification:**
- [ ] Hovering `Isha` while `Asr` is next displays `Till Asr` (Col 1) and `Till Isha` (Col 2).
- [ ] Hovering `Dhuhr` after `Isha` (before `Midnight`) displays `Till Fajr` (Col 1), `Till Midnight` (Col 2), and `Till Dhuhr` (Col 3).
- [ ] Hovering the already-next prayer shows nothing extra.
- [ ] Hovering `fajr_sunrise` zone (above Fajr/Sunrise) still shows `Since <previous>` independently.
- [ ] Findings & Handoff Log updated.

---

### [ ] Task 7: Unified Notification Service + Pre-Prayer Alerts & White Days / Ramadan Fasting Logic
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
- [ ] `python3 configure.py --check` and interactive wizard validate the new `[behavior]` keys.
- [ ] `lib/Notify.lua` sends a test `notify-send` once and skips duplicate calls with the same key even across restarts.
- [ ] Simulated/live test triggers 15-minute warnings for prayer, Sunrise, and Midnight (using `"Jumu'ah"` on Friday).
- [ ] Simulated Maghrib rollover to day `13`, `14`, `15` sends `"Tomorrow is <day> of <Month>"` when `month ~= 9`, and sends **nothing** when `month == 9` (Ramadan).
- [ ] Simulated Ramadan `month == 9` renders days `12..15` in `WHITE`, not `RED`.
- [ ] Findings & Handoff Log updated.

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
   - When `hover:visible(now)` is `true`, draw crisp micro-ticks / dots + compact minimal labels (e.g., `F`, `D`, `A`, `M`, `I` or short labels staggered cleanly above/below to avoid collisions) on **both** the circular dial and the 24h timeline bar.
- **Config evaluation:** Check whether `sun_moon_hover_failsafe_seconds` (or reusing `hover_failsafe_seconds`) is appropriate in `settings.ini` + `configure.py`. Document the decision.

**Acceptance & Verification:**
- [ ] Idle Astrolabe looks identical to before (no extra clutter).
- [ ] Hovering over the dial or timeline bar reveals all 5 prayer markers on **both** the circular dial and the 24h bar, positioned accurately relative to Sunrise/Sunset and the current time cursor.
- [ ] Moving the cursor off the Astrolabe clears the markers cleanly (and respects Wayland failsafe timeout).
- [ ] Findings & Handoff Log updated.

---

## Findings & Handoff Log
> **Instructions for Agents:** Append a dated entry under each task you complete (or attempt). Never delete prior entries. Include: files modified/created, environment quirks (Conky version, Wayland/X11 mouse hook behavior, font glyph checks), design decisions, and exact test commands run.

### Baseline Environment Notes (Pre-Task 1)
- **Aladhan API:** `/v1/timings` returns `"Lastthird"` (lowercase `t`) inside `data.timings`. Cache header is currently `CONKY_PRAYER_V1` without `Lastthird`.
- **Font:** Default `appearance.font` is `ITC Avant Garde Pro XLt`. Watch out for unsupported Unicode characters (use ASCII `'` in `"Jumu'ah"` rather than `ʿ` U+02BF).
- **Conky Mouse Hook Caveat:** `conky_prayer_times.conf`, `conky_date.conf`, and `conky_sun_moon.conf` use `own_window_type = 'normal'`. Verify `button_down` delivery on the target Conky binary during Task 4.

### Task 1 Log
- *Status:* Pending
- *Notes:* —

### Task 2 Log
- *Status:* Pending
- *Notes:* —

### Task 3 Log
- *Status:* Pending
- *Notes:* —

### Task 4 Log
- *Status:* Pending
- *Notes:* —

### Task 5 Log
- *Status:* Pending
- *Notes:* —

### Task 6 Log
- *Status:* Pending
- *Notes:* —

### Task 7 Log
- *Status:* Pending
- *Notes:* —

### Task 8 Log
- *Status:* Pending
- *Notes:* —