# Hijri Event Display Policy

This document is the authoritative product policy for events shown by the
Hijri date hover. Keep it in sync with `EVENT_RULES` in
`workers/prayer_fetch.py`, the Ramadan/sacred-month presentation in
`widgets/Hijri_Date.lua`, and the regression tests.

The widget is intentionally a **curated calendar**, not a mirror of every
holiday or anniversary published by AlAdhan. New API entries must never become
visible automatically.

## 1. Approved countdown events

The next-event area displays only the following ten events. Dates are fixed
Hijri month/day pairs; Gregorian dates are resolved from AlAdhan's HJCoSA
calendar for the current and following Hijri years.

| Hijri date | Canonical display name | Rule key | Display |
|---|---|---|---|
| 1 Muharram | Islamic New Year | `islamic_new_year` | Countdown |
| 10 Muharram | Ashura | `ashura` | Countdown |
| 12 Rabi al-Awwal | Mawlid al-Nabi | `mawlid_al_nabi` | Countdown |
| 27 Rajab | Isra and Mi'raj | `isra_and_miraj` | Countdown |
| 15 Sha'ban | Laylat al-Bara'at | `laylat_al_baraat` | Countdown |
| 1 Ramadan | Ramadan begins | `ramadan_begins` | Countdown |
| 1 Shawwal | Eid al-Fitr | `eid_al_fitr` | Countdown |
| 8 Dhul Hijjah | Hajj begins | `hajj_begins` | Countdown |
| 9 Dhul Hijjah | Day of Arafah | `day_of_arafah` | Countdown |
| 10 Dhul Hijjah | Eid al-Adha | `eid_al_adha` | Countdown |

The event names shown by the widget are canonical application labels. The
worker allowlist in `workers/prayer_fetch.py` and the cache-validation allowlist
in `lib/Prayer_Data.lua` intentionally duplicate the same key/name/day/month
rules as defense in depth; keep both tables synchronized. Do not show all
names returned for a date. For example, AlAdhan lists an individual
birth on 1 Muharram; the application uses that date to resolve **Islamic New
Year**, and does not display the individual's birthday.

`Hajj begins` is one countdown on 8 Dhul Hijjah. AlAdhan may repeat `Hajj` on
9, 10, 11, 12 and 13 Dhul Hijjah; those repeated rows do not create extra
countdowns. Day of Arafah and Eid al-Adha are separate events on the 9th and
10th respectively.

## 2. Sacred-month annotation (not countdown events)

The four sacred months are:

| Hijri month number | Month |
|---:|---|
| 1 | Muharram |
| 7 | Rajab |
| 11 | Dhul Qidah |
| 12 | Dhul Hijjah |

During one of these months:

- The month name keeps the configured accent color.
- The Hijri hover metadata includes `HOLY MONTH`.
- Do **not** create a separate countdown for AlAdhan's `Beginning of the holy
  months` or `End of the holy months` entries. The current month annotation is
  the intended presentation.

## 3. Laylat al-Qadr window

Laylat al-Qadr is deliberately not assigned one definite date by this widget.

- During Ramadan, accent the displayed Hijri day number for days **20 through
  the last day of Ramadan**.
- Preserve the existing White Days behavior: Ramadan days 12–15 remain white.
- From day 20 onward, show the note:
  `ONE OF THESE NIGHTS MAY BE LAYLAT AL-QADR`
- Do not create a countdown for each of AlAdhan's possible nights (21, 23, 25,
  27 and 29), and do not claim that any one night is certain.

This is a broad visual reminder, not a prediction of the exact night.

## 4. Explicit exclusions

The following categories are always excluded from the next-event countdown:

- **Individual births, Urs and personal commemorations:** exclude all of them,
  including named scholars, saints, family members, companions, rulers and
  other individuals. This includes individual martyrdom/anniversary entries
  such as the martyrdom of al-Hassan.
- **Historical anniversaries:** exclude events such as the Treaty of
  Hudaybiyya and the first Adhan.
- **Other unlisted AlAdhan entries:** exclude by default, even if the API adds
  them in a future year.
- **Repeated date labels:** do not turn repeated Hajj rows or multiple
  Laylat al-Qadr candidate rows into duplicate countdowns.

No Urs, individual birthday or historical anniversary should appear unless the
user explicitly changes this policy. When multiple API labels share an
approved date, display only the canonical allowlisted label. For example,
`Mawlid (Birth) al-Nabi` is represented as `Mawlid al-Nabi`; the separate
`Veiling of the Prophet Muhammad` entry on that date is not a second event.

## 5. API source and selection algorithm

Use AlAdhan's documented Islamic Calendar API:

1. Fetch
   `GET /v1/islamicHolidaysByHijriYear/{year}?calendarMethod=HJCoSA` for the
   current Hijri year and the following Hijri year.
2. Build a mapping from each returned `hijri.date` to its `gregorian.date`.
   Validate the response code, dates, requested Hijri year and calendar
   method.
3. For each rule in `EVENT_RULES`, resolve its fixed Hijri date from that
   mapping. If the annual holidays response has no row for a configured date,
   use `GET /v1/hToG/{DD-MM-YYYY}?calendarMethod=HJCoSA` as a date-conversion
   fallback.
4. Create application-owned canonical event records from the allowlist, sort
   by Gregorian date, and select the first event whose Gregorian date is on or
   after the widget's displayed Gregorian source date.
5. Compare against the same displayed date used for the Hijri line. It already
   includes `hijri_offset_days` and Maghrib rollover; do not apply either a
   second time.

Do **not** use `/v1/nextHijriHoliday` for display selection. That endpoint
returns the next generic AlAdhan holiday and may return an Urs or another
excluded entry before the next approved occasion. It is not a curated-event
endpoint.

The application explicitly requests `HJCoSA` to match its existing Hijri
prayer-date data. The annual calendar and conversion endpoints are not
location/timezone-specific. AlAdhan notes that calculated dates can differ by
one day from local moon sightings; treat them as calendar guidance, not a
replacement for local religious authority.

## 6. Cache and failure behavior

- The selected next event is stored separately from prayer-time date caches
  in `next-hijri-holiday.cache`, using schema
  `CONKY_HIJRI_EVENT_V2`. The filename is retained from the initial V1
  implementation to avoid unnecessary path churn; the V1 header is rejected
  and the worker replaces it with V2 data.
- Cache entries include the canonical rule key, canonical display name,
  Hijri/Gregorian dates, calendar method, fetch timestamp and base Hijri year.
- Cache TTL is 12 hours. A change in the base Hijri year invalidates the
  cache. A passed event is withheld and triggers a guarded background refresh.
- Network access runs only in `workers/prayer_fetch.py`; never make HTTP
  requests in Conky's draw loop.
- If the annual calendar, fallback conversion or cache is unavailable or
  invalid, show the existing unavailable state. Never invent a date or
  countdown, and never fall back to an unfiltered `nextHijriHoliday` result.

## 7. How a future agent may add an event

Only add an event after an explicit product decision. For each approved
addition:

1. Add one canonical tuple to `EVENT_RULES` in `workers/prayer_fetch.py`:
   `(rule_key, display_name, hijri_day, hijri_month)`.
2. Add the matching key/name/day/month entry to `HIJRI_EVENT_RULES` in
   `lib/Prayer_Data.lua`. The Lua cache reader independently rejects unknown
   keys and any name/date that does not match this table.
3. Ensure the date can be resolved by the annual calendar or the `hToG`
   fallback. Do not infer a Gregorian date from a previous year's date.
4. Add the event to the approved countdown table in this document.
5. Add fixtures and tests for the event's canonical name, Hijri date,
   Gregorian conversion, selection order, and year boundary.
6. Add a negative test proving nearby Urs, births, historical anniversaries
   and unknown API rows remain excluded at both worker and cache-reader level.
7. If the event needs special visual treatment rather than an ordinary
   countdown, document and test that treatment separately. Do not overload
   `EVENT_RULES` with Laylat al-Qadr or sacred-month annotations; those are
   date-range/month-state presentation rules.

Useful regression commands:

```bash
python3 -m unittest tests.test_hijri_event_cache -v
TZ=Africa/Cairo texlua tests/test_prayer_data_event.lua
TZ=Africa/Cairo texlua tests/test_hijri_hover.lua
```

## 8. API references

- [AlAdhan Islamic Calendar API](https://aladhan.com/islamic-calendar-api)
- [AlAdhan Islamic Holy Days — 1448 AH](https://aladhan.com/islamic-holidays/1448)
