-- Cairo clock and Hijri date; advances the Hijri date at Maghrib.
-- Date modes: date_only or date_and_weather (hover-reveal details).
-- The independent Weather.lua window remains visible in either mode.
require('cairo')
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './widgets/'
local root = base .. '../'
local Surface = dofile(root .. 'lib/Surface.lua')
local data_source = dofile(root .. 'lib/Prayer_Data.lua')
local Weather = dofile(root .. 'lib/Weather_Data.lua')
local Weather_Icons = dofile(root .. 'lib/Weather_Icons.lua')
local settings = dofile(root .. 'lib/Settings.lua')
local Hover = dofile(root .. 'lib/Hover_State.lua')
local Notify = dofile(root .. 'lib/Notify.lua')

local SCALE = settings.scale('date')
local NOTIFY_FASTING = settings.boolean('behavior', 'notifications_enabled', true)
    and settings.boolean('behavior', 'notify_fasting_days', true)
local last_date_check
local fasting_window_end
local DAYS_ADJUSTMENT = math.floor(settings.number('behavior', 'hijri_offset_days', 0))
local MONTHS = { 'Muharram', 'Safar', 'Rabi Al Awwal', 'Rabi Al Thani',
    'Jumada Al Oula', 'Jumada Al-Akhira', 'Rajab', 'Shaban',
    'Ramadan', 'Shawwal', 'Dhul Qidah', 'Dhul Hijjah' }
-- The four sacred months share the configured accent; White Days still
-- color only the day number and retain their separate Ramadan rules.
local SACRED_MONTHS = { [1] = true, [7] = true, [11] = true, [12] = true }
local WHITE = { 1, 1, 1, 200 / 255 }
local BRIGHT_WHITE = { 1, 1, 1, 0.94 }
local RED = { 200 / 255, 55 / 255, 55 / 255, 200 / 255 }
-- Share the upcoming-prayer accent with the three White Days (13–15).
local function configured_accent()
    local hex = settings.get('appearance', 'next_prayer_color', '#efb46f')
    assert(type(hex) == 'string' and hex:match('^#%x%x%x%x%x%x$'),
        'appearance.next_prayer_color must be #RRGGBB')
    return {tonumber(hex:sub(2, 3), 16) / 255,
            tonumber(hex:sub(4, 5), 16) / 255,
            tonumber(hex:sub(6, 7), 16) / 255, 200 / 255}
end
local ACCENT = configured_accent()
local BLUE = { 0.10, 0.80, 1.0, 1 }
local ORANGE = { 1, 0.47, 0.19, 1 }
local FONT = settings.get('appearance', 'font', 'DejaVu Sans')
local FONT_CLOCK, FONT_DATE = 160 * SCALE, 40 * SCALE

local DATE_SHOW_WEATHER = settings.date_weather_mode() == 'date_and_weather'
local DATE_WEATHER_CLOCK_SIZE = settings.number('appearance', 'date_weather_clock_size') * SCALE
local DATE_WEATHER_HOVER_TEMP_SIZE = settings.number('appearance', 'date_weather_hover_temp_size') * SCALE
local DATE_WEATHER_ICON_BASE = settings.number('appearance', 'date_weather_icon_size')
local DATE_WEATHER_ICON_DX = settings.number('appearance', 'date_weather_icon_dx') * SCALE
local DATE_WEATHER_ICON_DY = settings.number('appearance', 'date_weather_icon_dy') * SCALE
local hover = Hover.new(settings.number('behavior', 'date_weather_hover_failsafe_seconds'))

function conky_on_mouse(event)
    -- Weather and Gregorian date use independent named hover zones. The
    -- Gregorian interaction is available in both date_only and date+weather.
    return hover:mouse(event, os.time())
end

-- Keep the initial startup after Maghrib silent. Only the live widget
-- witnessing the Maghrib boundary opens a two-minute grace window for the
-- next-day prayer/Hijri cache to become available asynchronously.
local function check_fasting_reminder(now, maghrib, hijri_data, rollover)
    if NOTIFY_FASTING and maghrib and
       Notify.crossed(last_date_check, now, maghrib, 120) then
        fasting_window_end = maghrib + 120
    end
    last_date_check = now
    if not NOTIFY_FASTING or not rollover or not fasting_window_end
       or now > fasting_window_end or not hijri_data then return end
    local h = hijri_data.date.hijri
    local day, month = tonumber(h.day), tonumber(h.month.number)
    if not day or not month or month == 9 or day < 13 or day > 15
       or not MONTHS[month] then return end
    local key = string.format('%s-%02d-%02d:fast', tostring(h.year), month, day)
    local title = string.format('Tomorrow is %d of %s', day, MONTHS[month])
    if Notify.send_once(key, title, 'Sunnah fasting reminder (Ayyam al-Bid)', now) then
        fasting_window_end = nil
    end
end

local function text(cr, value, x, y, color)
    cairo_set_source_rgba(cr, color[1], color[2], color[3], color[4])
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, tostring(value))
end

local function width(cr, value, extents)
    cairo_text_extents(cr, tostring(value), extents)
    return extents.x_advance
end

local function measure(cr, value, size)
    cairo_set_font_size(cr, size)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, tostring(value), ext)
    return ext
end

-- Worldline Gregorian reveal. The day count and progress instrument form one
-- measured group, centered as a whole. Text extents determine the column split
-- so the small labels can never overlap the large day count.
local function draw_gregorian_worldline(cr, now, widget_width, baseline_y, max_width)
    local date = os.date('*t', now)
    local year = date.year
    local day_of_year = tonumber(os.date('%j', now)) or date.yday or 1
    local leap = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
    local year_length = leap and 366 or 365
    local days_remaining = math.max(0, year_length - day_of_year)
    local iso_week = tonumber(os.date('%V', now)) or 1
    local progress = day_of_year / year_length

    local day_label = string.format('%d / %d', day_of_year, year_length)
    local title = 'YEAR PROGRESS'
    local percentage = string.format('%.1f%%', progress * 100)
    local week_label = string.format('WEEK %02d', iso_week)
    local remaining_label = string.format('%d DAYS LEFT', days_remaining)

    local day_size = 36 * SCALE
    local small_size = 9 * SCALE
    local column_gap = 18 * SCALE
    local label_gap = 12 * SCALE
    local day_ext = measure(cr, day_label, day_size)
    local title_ext = measure(cr, title, small_size)
    local percentage_ext = measure(cr, percentage, small_size)
    local week_ext = measure(cr, week_label, small_size)
    local remaining_ext = measure(cr, remaining_label, small_size)

    -- Reserve enough width for both right-hand label rows, based on the
    -- rendered font metrics rather than fixed percentage columns.
    local right_min_width = math.max(
        title_ext.x_advance + percentage_ext.x_advance + label_gap,
        week_ext.x_advance + remaining_ext.x_advance + label_gap)
    local required_width = day_ext.x_advance + column_gap + right_min_width
    local available_width = math.max(1, math.min(max_width,
        widget_width - 32 * SCALE))

    -- On unusually narrow widgets, scale the typography down uniformly rather
    -- than clipping the labels or allowing them to collide with the day count.
    if required_width > available_width then
        local fit = available_width / required_width
        day_size = day_size * fit
        small_size = small_size * fit
        column_gap = column_gap * fit
        label_gap = label_gap * fit
        day_ext = measure(cr, day_label, day_size)
        title_ext = measure(cr, title, small_size)
        percentage_ext = measure(cr, percentage, small_size)
        week_ext = measure(cr, week_label, small_size)
        remaining_ext = measure(cr, remaining_label, small_size)
        right_min_width = math.max(
            title_ext.x_advance + percentage_ext.x_advance + label_gap,
            week_ext.x_advance + remaining_ext.x_advance + label_gap)
        required_width = day_ext.x_advance + column_gap + right_min_width
    end

    local group_width = math.min(available_width,
        math.max(465 * SCALE, required_width))
    local left_x = (widget_width - group_width) / 2
    local right_x = left_x + day_ext.x_advance + column_gap
    local right_width = group_width - day_ext.x_advance - column_gap
    local right_edge = right_x + right_width

    local quiet = {120 / 255, 117 / 255, 112 / 255, 1}
    local top_y = baseline_y - 38 * SCALE
    local bottom_y = baseline_y - 7 * SCALE

    cairo_set_font_size(cr, day_size)
    text(cr, day_label, left_x, baseline_y - 13 * SCALE, ACCENT)

    cairo_set_font_size(cr, small_size)
    text(cr, title, right_x, top_y, quiet)
    text(cr, percentage, right_edge - percentage_ext.x_advance,
        top_y, quiet)

    local bar_y = baseline_y - 26 * SCALE
    local bar_height = math.max(2, 3 * SCALE)
    cairo_set_source_rgba(cr, quiet[1], quiet[2], quiet[3], 0.30)
    cairo_rectangle(cr, right_x, bar_y, right_width, bar_height)
    cairo_fill(cr)
    cairo_set_source_rgba(cr, ACCENT[1], ACCENT[2], ACCENT[3], ACCENT[4])
    cairo_rectangle(cr, right_x, bar_y, right_width * progress, bar_height)
    cairo_fill(cr)

    text(cr, week_label, right_x, bottom_y, quiet)
    text(cr, remaining_label,
        right_edge - remaining_ext.x_advance, bottom_y, quiet)
end

-- Resolve the active IANA timezone from the process environment or the
-- system timezone configuration. Never bake a city or zone into the widget.
local function timezone_id_from(value)
    if type(value) ~= 'string' then return nil end
    value = value:match('^%s*(.-)%s*$') or ''
    value = value:gsub('^:', '')
    local from_path = value:match('/zoneinfo/(.+)$')
    if from_path then value = from_path end
    if value:match('^[%w_+%-]+/[%w_+%-/]+$') then return value end
    if value == 'UTC' or value == 'GMT' then return value end
    return nil
end

local function detect_timezone_id()
    local from_env = timezone_id_from(os.getenv('TZ'))
    if from_env then return from_env end

    -- On most Linux desktops /etc/localtime is a symlink into zoneinfo.
    local ok, pipe = pcall(io.popen, 'readlink -f /etc/localtime 2>/dev/null', 'r')
    if ok and pipe then
        local path = pipe:read('*l')
        pipe:close()
        local from_link = timezone_id_from(path)
        if from_link then return from_link end
    end

    -- Debian/Ubuntu and some other distributions keep the zone name here
    -- even when /etc/localtime is a copied file rather than a symlink.
    local file = io.open('/etc/timezone', 'r')
    if file then
        local configured = file:read('*l')
        file:close()
        local from_file = timezone_id_from(configured)
        if from_file then return from_file end
    end
    return 'Local'
end

local TIMEZONE_ID = detect_timezone_id()

-- Whisper clock reveal. Keep the idle HH:MM footprint reserved while
-- shrinking the main digits just enough to fit low-aligned seconds inline.
-- All clock metadata is presented together on one centered line.
local function draw_clock_reveal(cr, now, idle_size, slot_left, slot_right, baseline)
    local main = os.date('%H:%M', now)
    local seconds = ':' .. os.date('%S', now)
    local main_size = idle_size * 0.78
    local seconds_size = idle_size * 0.21
    local main_ext = measure(cr, main, main_size)
    local seconds_ext = measure(cr, seconds, seconds_size)
    local row_gap = 4 * SCALE
    local row_width = main_ext.x_advance + row_gap + seconds_ext.x_advance
    local slot_width = math.max(0, slot_right - slot_left)
    local row_x = slot_left + (slot_width - row_width) / 2
    local main_baseline = baseline - 20 * SCALE
    local seconds_baseline = main_baseline + main_ext.y_bearing
        + main_ext.height - seconds_ext.y_bearing - seconds_ext.height
        - 3 * SCALE

    cairo_set_font_size(cr, main_size)
    text(cr, main, row_x, main_baseline, WHITE)
    cairo_set_font_size(cr, seconds_size)
    text(cr, seconds, row_x + main_ext.x_advance + row_gap,
        seconds_baseline, ACCENT)

    local zone_name = os.date('%Z', now)
    if not zone_name or zone_name == '' then zone_name = 'LOCAL' end
    local raw_offset = os.date('%z', now) or ''
    local sign, hours, minutes = raw_offset:match('^([+-])(%d%d):?(%d%d)$')
    local offset = sign and string.format('UTC%s%s:%s', sign, hours, minutes)
        or 'UTC'
    local utc_time = os.date('!%H:%M:%S', now)

    local muted = {1, 1, 1, 105 / 255}
    local details = {
        {zone_name, ACCENT},
        {' · ', muted},
        {offset, WHITE},
        {' · ', muted},
        {TIMEZONE_ID, WHITE},
        {' · UTC ', muted},
        {utc_time, muted},
    }
    local detail_size = 9 * SCALE
    local available_width = math.max(1, slot_width - 12 * SCALE)
    local function measure_details(size)
        local total = 0
        for _, part in ipairs(details) do
            part.ext = measure(cr, part[1], size)
            total = total + part.ext.x_advance
        end
        return total
    end
    local detail_width = measure_details(detail_size)
    if detail_width > available_width then
        detail_size = detail_size * available_width / detail_width
        detail_width = measure_details(detail_size)
    end

    local detail_x = slot_left + (slot_width - detail_width) / 2
    -- Lift the unified timezone line into the clock's lower guide line.
    local detail_baseline = baseline + 6 * SCALE
    cairo_set_font_size(cr, detail_size)
    for _, part in ipairs(details) do
        text(cr, part[1], detail_x, detail_baseline, part[2])
        detail_x = detail_x + part.ext.x_advance
    end
end

local function draw_divider(cr, x, top_y, bottom_y)
    local pat = cairo_pattern_create_linear(0, top_y, 0, bottom_y)
    cairo_pattern_add_color_stop_rgba(pat, 0.0, 1, 1, 1, 0.0)
    cairo_pattern_add_color_stop_rgba(pat, 0.2, 1, 1, 1, 0.58)
    cairo_pattern_add_color_stop_rgba(pat, 0.8, 1, 1, 1, 0.58)
    cairo_pattern_add_color_stop_rgba(pat, 1.0, 1, 1, 1, 0.0)
    cairo_set_source(cr, pat)
    cairo_set_line_width(cr, math.max(1.5, 1.2 * SCALE))
    cairo_move_to(cr, x, top_y)
    cairo_line_to(cr, x, bottom_y)
    cairo_stroke(cr)
    cairo_pattern_destroy(pat)
end

local function draw_arrow(cr, x, row_center_y, direction, s)
    local half_w = 3 * s
    local half_h = 6 * s
    local head_len = 3 * s
    local tip_y = row_center_y + direction * half_h
    local tail_y = row_center_y - direction * half_h
    local head_base_y = tip_y - direction * head_len
    local c = direction < 0 and ORANGE or BLUE
    cairo_set_source_rgba(cr, c[1], c[2], c[3], c[4])
    cairo_set_line_width(cr, 1.6 * s)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
    cairo_move_to(cr, x, tail_y)
    cairo_line_to(cr, x, tip_y)
    cairo_move_to(cr, x - half_w, head_base_y)
    cairo_line_to(cr, x, tip_y)
    cairo_line_to(cr, x + half_w, head_base_y)
    cairo_stroke(cr)
end

local function droplet(cr, x, y, s)
    cairo_set_source_rgba(cr, BLUE[1], BLUE[2], BLUE[3], BLUE[4])
    cairo_set_line_width(cr, 2 * s)
    cairo_move_to(cr, x, y - 10 * s)
    cairo_curve_to(cr, x - 5 * s, y - 2 * s, x - 7 * s, y + 1 * s, x - 5 * s, y + 5 * s)
    cairo_curve_to(cr, x - 2 * s, y + 10 * s, x + 3 * s, y + 9 * s, x + 5 * s, y + 5 * s)
    cairo_curve_to(cr, x + 7 * s, y + 1 * s, x + 5 * s, y - 2 * s, x, y - 10 * s)
    cairo_close_path(cr)
    cairo_stroke(cr)
end

local function draw_weather_details(cr, weather, x_start, baseline_y, s)
    local reading_size = 18 * s
    local high = string.format('%d°', weather.high)
    local low = string.format('%d°', weather.low)
    local humidity = string.format('%d%%', weather.humidity)

    local high_ext = measure(cr, high, reading_size)
    local low_ext = measure(cr, low, reading_size)
    local hum_ext = measure(cr, humidity, reading_size)

    local ink_top = math.min(high_ext.y_bearing, low_ext.y_bearing)
    local ink_bottom = math.max(high_ext.y_bearing + high_ext.height,
        low_ext.y_bearing + low_ext.height)
    local row_center = baseline_y + (ink_top + ink_bottom) / 2

    local ahw = 3 * s
    local ast = 1.6 * s
    local atg = 5 * s
    local group_gap = 12 * s

    local high_arrow_x = x_start + ahw + ast / 2
    local high_x = high_arrow_x + ahw + ast / 2 + atg - high_ext.x_bearing
    local high_right = high_x + high_ext.x_bearing + high_ext.width

    local low_arrow_x = high_right + group_gap + ahw + ast / 2
    local low_x = low_arrow_x + ahw + ast / 2 + atg - low_ext.x_bearing
    local low_right = low_x + low_ext.x_bearing + low_ext.width

    local droplet_x = low_right + group_gap + 7 * s
    local humidity_x = droplet_x + 7 * s + 5 * s - hum_ext.x_bearing

    draw_arrow(cr, high_arrow_x, row_center, -1, s)
    cairo_set_font_size(cr, reading_size)
    text(cr, high, high_x, baseline_y, BRIGHT_WHITE)

    draw_arrow(cr, low_arrow_x, row_center, 1, s)
    cairo_set_font_size(cr, reading_size)
    text(cr, low, low_x, baseline_y, BRIGHT_WHITE)

    droplet(cr, droplet_x, baseline_y - 7 * s, s)
    cairo_set_font_size(cr, reading_size)
    text(cr, humidity, humidity_x, baseline_y, BRIGHT_WHITE)
end

-- Tomorrow through the following two days; compact two-line rows and
-- tightly spaced icons on the RIGHT. Only the Date hover draws this forecast.
local function draw_three_day_forecast(cr, weather, clock_top, clock_bottom)
    local forecast = weather.forecast
    if not forecast or #forecast ~= 3 then return end

    local day_size = 14 * SCALE
    local temp_size = 16 * SCALE
    local icon_size = 27 * SCALE
    local icon_gap = 6 * SCALE
    local right_margin = 12 * SCALE
    local row_step = 42 * SCALE

    -- Measure the widest temperature pair once, so the day/temperature
    -- labels and the icon column remain aligned for all three days.
    local text_width = 0
    local temperatures = {}
    local forecast_top, forecast_bottom = math.huge, -math.huge
    for i, day in ipairs(forecast) do
        temperatures[i] = string.format('%d°/%d°', day.high, day.low)
        local day_ext = measure(cr, day.day, day_size)
        local temp_ext = measure(cr, temperatures[i], temp_size)
        text_width = math.max(text_width, temp_ext.x_advance)

        -- Measure the visible ink and the icon, not just text baselines.
        -- This keeps the COMPLETE three-row group centered on the clock's
        -- actual visible height across fonts, scales and temperature widths.
        local row_offset = (i - 1) * row_step
        forecast_top = math.min(forecast_top,
            row_offset + 13 * SCALE + day_ext.y_bearing,
            row_offset + 32 * SCALE + temp_ext.y_bearing,
            row_offset + 4 * SCALE)
        forecast_bottom = math.max(forecast_bottom,
            row_offset + 13 * SCALE + day_ext.y_bearing + day_ext.height,
            row_offset + 32 * SCALE + temp_ext.y_bearing + temp_ext.height,
            row_offset + 4 * SCALE + icon_size)
    end
    local top = (clock_top + clock_bottom - forecast_top - forecast_bottom) / 2
    local icon_x = conky_window.width - right_margin - icon_size
    local label_x = icon_x - icon_gap - text_width

    for i, day in ipairs(forecast) do
        local row_y = top + (i - 1) * row_step
        cairo_set_font_size(cr, day_size)
        text(cr, day.day, label_x, row_y + 13 * SCALE, WHITE)
        cairo_set_font_size(cr, temp_size)
        text(cr, temperatures[i], label_x, row_y + 32 * SCALE, BRIGHT_WHITE)
        Weather_Icons.draw(cr, Weather_Icons.code(day.code, true), icon_x, row_y + 4 * SCALE, icon_size)
    end
end

local function draw_date_weather_header(cr, now, clock)
    local weather = Weather.get(now)
    local clock_baseline = 152 * SCALE
    local clock_ext = measure(cr, clock, DATE_WEATHER_CLOCK_SIZE)
    local clock_top = clock_baseline + clock_ext.y_bearing

    local temp_num = weather and string.format('%d', weather.temperature) or '--'
    local temp_full = temp_num .. '°'
    local idle_num_ext = measure(cr, temp_num, DATE_WEATHER_CLOCK_SIZE)
    local idle_full_ext = measure(cr, temp_full, DATE_WEATHER_CLOCK_SIZE)

    local icon_size = DATE_WEATHER_ICON_BASE * SCALE
    local icon_rel_x = idle_num_ext.x_advance + DATE_WEATHER_ICON_DX
    local weather_w = math.max(idle_full_ext.x_advance, icon_rel_x + icon_size)

    local div_gap = 22 * SCALE
    local total_w = clock_ext.x_advance + div_gap * 2 + weather_w
    local start_x = (conky_window.width - total_w) / 2
    local div_x = start_x + clock_ext.x_advance + div_gap
    local weather_x = div_x + div_gap

    local clock_right = start_x + clock_ext.x_advance
    hover:set_zone('clock', {
        start_x - 8 * SCALE, 0,
        clock_right + 8 * SCALE, clock_baseline + 29 * SCALE,
    })
    hover:set_zone('weather', {
        div_x,
        0, -- includes the first forecast row, above the clock numerals
        conky_window.width, -- hover stays active over the right forecast area
        clock_baseline + 18 * SCALE,
    })

    -- Clock: the reveal stays within the idle clock's reserved footprint.
    if hover:visible('clock', now) then
        draw_clock_reveal(cr, now, DATE_WEATHER_CLOCK_SIZE,
            start_x, clock_right, clock_baseline)
    else
        cairo_set_font_size(cr, DATE_WEATHER_CLOCK_SIZE)
        text(cr, clock, start_x, clock_baseline, WHITE)
    end

    -- Divider
    draw_divider(cr, div_x, clock_top - 4 * SCALE, clock_baseline + 6 * SCALE)

    -- Weather (Idle vs Hover)
    if weather and hover:visible('weather', now) then
        local ratio = DATE_WEATHER_HOVER_TEMP_SIZE / DATE_WEATHER_CLOCK_SIZE
        local small_num_ext = measure(cr, temp_num, DATE_WEATHER_HOVER_TEMP_SIZE)
        local small_baseline = clock_top - small_num_ext.y_bearing + 2 * SCALE
        local small_icon_size = icon_size * ratio
        local small_icon_x = weather_x + small_num_ext.x_advance + DATE_WEATHER_ICON_DX * ratio
        local small_icon_y = small_baseline - small_icon_size * 0.86 + DATE_WEATHER_ICON_DY * ratio

        cairo_set_font_size(cr, DATE_WEATHER_HOVER_TEMP_SIZE)
        text(cr, temp_full, weather_x, small_baseline, BRIGHT_WHITE)
        Weather_Icons.draw(cr, Weather_Icons.code(weather.code, weather.is_day == 1),
            small_icon_x, small_icon_y, small_icon_size)
        draw_weather_details(cr, weather, weather_x, clock_baseline - 2 * SCALE, SCALE)
        local clock_bottom = clock_baseline + clock_ext.y_bearing + clock_ext.height
        draw_three_day_forecast(cr, weather, clock_top, clock_bottom)
    else
        cairo_set_font_size(cr, DATE_WEATHER_CLOCK_SIZE)
        text(cr, temp_full, weather_x, clock_baseline, WHITE)
        if weather then
            local icon_x = weather_x + icon_rel_x
            local icon_y = clock_baseline - icon_size * 0.86 + DATE_WEATHER_ICON_DY
            Weather_Icons.draw(cr, Weather_Icons.code(weather.code, weather.is_day == 1),
                icon_x, icon_y, icon_size)
        end
    end
end

function conky_main()
    if not conky_window then return end
    local now = os.time()
    local actual_today = data_source.shift_date(now, 0)
    local actual_data = data_source.get(actual_today)
    local maghrib = actual_data and
        data_source.timestamp(actual_today, actual_data.timings.Maghrib)
    local rollover = maghrib ~= nil and now >= maghrib
    -- Apply date adjustment to the displayed Hijri date, not to Maghrib's clock.
    local hijri_date = data_source.shift_date(now,
        DAYS_ADJUSTMENT + (rollover and 1 or 0))
    data_source.ensure_dates({ actual_today, hijri_date,
        data_source.date_plus(actual_today, 1) }, now)
    local hijri_data = actual_data and data_source.get(hijri_date)
    check_fasting_reminder(now, maghrib, hijri_data, rollover)

    local cs = Surface.acquire()
    if not cs then return end
    local cr = cairo_create(cs)
    local ext = cairo_text_extents_t:create()
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)

    local clock = os.date('%H:%M', now)
    local gregorian = os.date('%A |  %d %B %Y', now)
    local y_gregorian = FONT_CLOCK + FONT_DATE + (FONT_DATE / 1.5)
    local y_hijri = y_gregorian + FONT_DATE + (FONT_DATE / 3)

    if DATE_SHOW_WEATHER then
        draw_date_weather_header(cr, now, clock)
    else
        hover:set_zone('weather', nil)
        local clock_ext = measure(cr, clock, FONT_CLOCK)
        local clock_x = (conky_window.width - clock_ext.x_advance) / 2
        local clock_right = clock_x + clock_ext.x_advance
        hover:set_zone('clock', {
            clock_x - 8 * SCALE, 0,
            clock_right + 8 * SCALE, FONT_CLOCK + 29 * SCALE,
        })
        if hover:visible('clock', now) then
            draw_clock_reveal(cr, now, FONT_CLOCK,
                clock_x, clock_right, FONT_CLOCK)
        else
            cairo_set_font_size(cr, FONT_CLOCK)
            text(cr, clock, clock_x, FONT_CLOCK, WHITE)
        end
    end

    local gregorian_ext = measure(cr, gregorian, FONT_DATE)
    local gregorian_x = (conky_window.width - gregorian_ext.x_advance) / 2
    local worldline_width = math.max(1,
        conky_window.width - 32 * SCALE)
    local zone_width = math.min(conky_window.width,
        math.max(math.min(465 * SCALE, worldline_width),
            gregorian_ext.x_advance + 16 * SCALE))
    local zone_left = (conky_window.width - zone_width) / 2
    local zone_top = math.max(0, y_gregorian - 36 * SCALE)
    local zone_bottom = math.min(conky_window.height or math.huge,
        y_gregorian + 8 * SCALE)
    hover:set_zone('gregorian', {
        zone_left, zone_top, zone_left + zone_width, zone_bottom,
    })

    if hover:visible('gregorian', now) then
        draw_gregorian_worldline(cr, now, conky_window.width,
            y_gregorian, worldline_width)
    else
        cairo_set_font_size(cr, FONT_DATE)
        text(cr, gregorian, gregorian_x, y_gregorian, WHITE)
    end

    -- Cairo font size is drawing state, not scoped to a helper. Restore the
    -- original date size before measuring or drawing the Hijri row so the
    -- Gregorian reveal can never shrink the Hijri date.
    cairo_set_font_size(cr, FONT_DATE)
    if hijri_data then
        local h = hijri_data.date.hijri
        local day = tonumber(h.day)
        local month = tonumber(h.month.number)
        local year = tostring(h.year)
        if day and month and MONTHS[month] then
            local pieces = { string.format('%02d', day), MONTHS[month], year }
            local margin = FONT_DATE / 2.5
            local widths = {}
            local total = margin * 2
            for i = 1, 3 do
                widths[i] = width(cr, pieces[i], ext)
                total = total + widths[i]
            end
            local x = (conky_window.width - total) / 2
            for i = 1, 3 do
                local piece_color = WHITE
                if i == 1 and month ~= 9 then
                    if day == 12 then piece_color = RED
                    elseif day >= 13 and day <= 15 then piece_color = ACCENT end
                elseif i == 2 and SACRED_MONTHS[month] then
                    piece_color = ACCENT
                end
                text(cr, pieces[i], x, y_hijri, piece_color)
                x = x + widths[i] + margin
            end
        end
    else
        local loading = 'Fetching Hijri date...'
        text(cr, loading,
            (conky_window.width - width(cr, loading, ext)) / 2,
            y_hijri, WHITE)
    end
    cairo_destroy(cr)
    Surface.release(cs)
end
