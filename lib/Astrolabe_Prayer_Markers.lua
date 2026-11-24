-- Pure prayer-marker positioning for the Celestial Astrolabe.
-- The 24h bar uses today's prayers. The dial depicts today's daylight,
-- but its night arc depicts either LAST night's interval (before sunrise)
-- or TONIGHT's interval (from sunrise onward).
local M = {}
local PI = math.pi
local NAMES = {'Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'}
local LETTERS = {Fajr = 'F', Dhuhr = 'D', Asr = 'A', Maghrib = 'M', Isha = 'I'}

local function timestamp(prayer, date, data, name)
    return data and data.timings and prayer.timestamp(date, data.timings[name])
end

local function fraction(ts, first, last)
    if not ts or not first or not last or last <= first
       or ts < first or ts > last then return nil end
    return (ts - first) / (last - first)
end

local function local_day_fraction(ts)
    local t = os.date('*t', ts)
    return (t.hour * 3600 + t.min * 60 + t.sec) / 86400
end

function M.build(now, schedule, prayer)
    if not schedule then return nil end
    local today = os.date('%Y-%m-%d', now)
    local previous = prayer.date_plus(today, -1)
    local following = prayer.date_plus(today, 1)
    local today_data = prayer.get(today)
    if not today_data then return nil end

    local before_sunrise = now < schedule.sunrise_ts
    local night_start = before_sunrise and schedule.yesterday_sunset_ts or schedule.sunset_ts
    local night_end = before_sunrise and schedule.sunrise_ts or schedule.tomorrow_sunrise_ts
    local night_evening_date = before_sunrise and previous or today
    local night_evening_data, night_morning_data
    if before_sunrise then
        night_evening_data, night_morning_data = prayer.get(previous), today_data
    else
        night_evening_data, night_morning_data = today_data, prayer.get(following)
    end
    local night_morning_date = before_sunrise and today or following
    if not night_evening_data or not night_morning_data then return nil end

    local dial_ts = {
        Fajr = timestamp(prayer, night_morning_date, night_morning_data, 'Fajr'),
        Dhuhr = timestamp(prayer, today, today_data, 'Dhuhr'),
        Asr = timestamp(prayer, today, today_data, 'Asr'),
        Maghrib = timestamp(prayer, night_evening_date, night_evening_data, 'Maghrib'),
        Isha = timestamp(prayer, night_evening_date, night_evening_data, 'Isha'),
    }
    -- The API attaches Lastthird to the evening's schedule, but its clock
    -- time occurs AFTER midnight. Resolve it on the following civil date.
    -- The Islamic last third runs from Lastthird until the NEXT Fajr,
    -- not sunrise; the dial's entire night half continues to sunrise.
    local third_start = timestamp(prayer, night_morning_date,
        night_evening_data, 'Lastthird')
    local fajr_end = dial_ts.Fajr
    local last_third
    if third_start and fajr_end and night_start < third_start
        and third_start < fajr_end and fajr_end < night_end then
        last_third = {
            start_ts = third_start, end_ts = fajr_end,
            start_angle = PI * fraction(third_start, night_start, night_end),
            end_angle = PI * fraction(fajr_end, night_start, night_end),
        }
    end
    local markers = {}
    markers.last_third = last_third
    for _, name in ipairs(NAMES) do
        local bar_ts = timestamp(prayer, today, today_data, name)
        local daylight = name == 'Dhuhr' or name == 'Asr'
        local portion
        if daylight then
            portion = fraction(dial_ts[name], schedule.sunrise_ts, schedule.sunset_ts)
        else
            portion = fraction(dial_ts[name], night_start, night_end)
        end
        if portion == nil or bar_ts == nil then
            -- Never draw a partial or invented five-prayer overlay.
            return nil
        end
        markers[#markers + 1] = {
            name = name,
            short = LETTERS[name],
            daytime = daylight,
            angle = (daylight and PI or 0) + PI * portion,
            bar_fraction = local_day_fraction(bar_ts),
            dial_ts = dial_ts[name],
            bar_ts = bar_ts,
        }
    end
    return markers
end

-- Match the existing 24-hour bar's .05-day sunrise/sunset transition
-- windows, normalized onto the actual daylight semicircle of the dial.
function M.golden_windows(schedule, seconds)
    if not schedule or not schedule.sunrise_ts or not schedule.sunset_ts
        or schedule.sunset_ts <= schedule.sunrise_ts then return nil end
    local span = schedule.sunset_ts - schedule.sunrise_ts
    local length = math.min(math.max(0, seconds or 0), span / 2)
    if length == 0 then return nil end
    local angle = PI * length / span
    return {
        {start_angle = PI, end_angle = PI + angle},
        {start_angle = 2 * PI - angle, end_angle = 2 * PI},
    }
end

return M
