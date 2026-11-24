# Task 7 — Notification service: behavior and handoff

## Current architecture (XWayland, Conky 1.24.2)

- `lib/Notify.lua` is the one shared notification sender. It uses `notify-send`
  detached in the shell and quotes arbitrary title/body strings. There are no
  network calls in the draw loop, and notification failures must not prevent
  Cairo rendering. It does **not** depend on the current Xlib Cairo adapter.
- `widgets/Prayer_Times.lua` monitors threshold crossings for five prayers,
  Sunrise, and Midnight using the already-loaded Aladhan timestamps.
  Jumu'ah is the Friday Dhuhr event, not the label for Thursday's elapsed
  Dhuhr. The 7th column's Last 3rd toggle does **not** replace Midnight.
- `widgets/Hijri_Date.lua` monitors Maghrib in the configured location.
  The next displayed Islamic day (with existing Hijri offset) is the basis of
  the White Days 13/14/15 reminder; these are **suppressed for month 9**.
  In Ramadan the day-number styling for days 12..15 is WHITE, not RED.
- Both widgets respect `[behavior]` `notifications_enabled=yes|no`,
  `notify_prayer_minutes=0..60`, and `notify_fasting_days=yes|no`.
  Defaults are yes / 15 / yes. Settings are exposed by `configure.py`,
  validated by `configure.py --check`, and diagnosed by `doctor.py`.

## Timing safety

Cold start is not a reminder event. A running widget must observe crossing
of the scheduled threshold; checks older than 120 seconds (sleep/wake) are
ignored, and notifications more than 15 seconds late are suppressed.
Pre-prayer reminders are therefore not backfilled after a restart, disconnection
or prolonged pause. This is intentional: no stale notification bursts.

At the Maghrib boundary the Date widget opens a two-minute window for the
already-async next-day Hijri cache to be ready. A Date widget started after
Maghrib will not invent a missed boundary. If the widget was offline then,
**there is no late White Days reminder**. Keep Date running continuously for
this feature. These are calendar reminders, not religious rulings; dates can
vary by calculation method/location/offset.

## Persistent deduplication and process model

The first sender to create an event-specific directory under
`${XDG_CACHE_HOME:-$HOME/.cache}/conky-notifications/sent/` claims the key.
`mkdir` is atomic even across the user's separate autostart Conky processes.
The file `sent.cache` is only a human-readable append-only audit log and is
**not used to decide whether a notification was sent**. Keys include the
civil day, event name and lead duration (`YYYY-MM-DD:Asr:15m`), or Hijri
`YYYY-MM-DD:fast` for White Days. Expired markers (60 days old) are pruned.

The event is marked when queued to `notify-send`; KDE might suppress it
(e.g., Do Not Disturb). We do not replay it after that because replay could
spam. The sender gracefully does nothing when `notify-send` is missing.
Changing `settings.ini` does not retroactively fire past notifications.

## Verification (do not confuse offline and live checks)

Offline:

```sh
texlua tests/test_notifications.lua
python3 -m unittest tests/test_notify_service.py -v
python3 configure.py --check
```

The Python test runs a **fake** `notify-send`, verifying shell argument
quoting and a persistent dedup key after launching the Lua program twice.
The Lua test stubs the notification backend and checks the real widget draw
hooks: all five prayers, Sunrise, Midnight, Friday Jumu'ah, timestamp
crossings/startup and wake guards, days 13/14/15, and Ramadan days 12–15.

Live KDE acceptance still required:

1. With desktop notifications enabled and Do Not Disturb off, verify a prayer
   reminder approximately 15 minutes before a prayer, then restart Prayer
   Times and confirm it does not repeat.
2. Observe a Sunrise or Midnight reminder; check Friday's Jumu'ah name.
3. At the next Maghrib preceding Hijri 13, 14, or 15, confirm one White Days
   notice; verify Ramadan suppression when its date arrives.
4. Verify notification settings can be disabled and that restarting either
   widget does not affect Xlib drawing, independent KDE autostart or hover.

If Conky is upgraded or returned to native Wayland, repeat these acceptance
tests; this service itself is not supposed to require X11/Xlib.

## Plasma notification history

The sender now creates a hidden `conky-prayer-reminders.desktop` application
identity in `${XDG_DATA_HOME:-$HOME/.local/share}/applications` on the first
notification, and sends the `desktop-entry` hint with `transient=false`. This
helps Plasma associate reminders with an app and retain them in its history
*after the temporary popup disappears*. Plasma still decides what to store.

In **System Settings → Notifications → Application Settings**, ensure **Show
in History** is enabled for **Conky Prayer Reminders** (or **Other
Applications**, if your Plasma version groups it there). Test with a new
reminder; already missed reminders are not replayed. This does not pin a
popup on the screen or guarantee history survives user-clearing or system
retention limits. The `.cache/conky-notifications/sent.cache` file is a
deduplication audit trail, **not** the Plasma notification center history.
