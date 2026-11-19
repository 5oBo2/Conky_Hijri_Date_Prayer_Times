-- Cairo clock and Hijri date; advances the Hijri date at Maghrib.
-- Supports optional combined "Clock | Weather" mode with hover-reveal details.
require('cairo')
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './'
local Surface = dofile(base .. 'Surface.lua')
local data_source = dofile(base .. 'Prayer_Data.lua')
local Weather = dofile(base .. 'Weather_Data.lua')
local settings = dofile(base .. 'Settings.lua')
local Hover = dofile(base .. 'Hover_State.lua')

local SCALE = settings.scale('date')
local DAYS_ADJUSTMENT = math.floor(settings.number('behavior', 'hijri_offset_days', 0))
local MONTHS = { 'Muharram', 'Safar', 'Rabi Al Awwal', 'Rabi Al Thani',
    'Jumada Al Oula', 'Jumada Al-Akhira', 'Rajab', 'Shaban',
    'Ramadan', 'Shawwal', 'Dhul Qidah', 'Dhul Hijjah' }
local WHITE = { 1, 1, 1, 200 / 255 }
local BRIGHT_WHITE = { 1, 1, 1, 0.94 }
local RED = { 200 / 255, 55 / 255, 55 / 255, 200 / 255 }
local BLUE = { 0.10, 0.80, 1.0, 1 }
local ORANGE = { 1, 0.47, 0.19, 1 }
local FONT = settings.get('appearance', 'font', 'DejaVu Sans')
local FONT_CLOCK, FONT_DATE = 160 * SCALE, 40 * SCALE

local COMBINED = settings.boolean('appearance', 'clock_weather_combined', false)
local COMBINED_CLOCK_SIZE = settings.number('appearance', 'combined_clock_size', 145) * SCALE
local COMBINED_HOVER_TEMP_SIZE = settings.number('appearance', 'combined_hover_temp_size', 82) * SCALE
local COMBINED_ICON_BASE = settings.number('appearance', 'combined_weather_icon_size', 72)
local COMBINED_ICON_DX = settings.number('appearance', 'combined_weather_icon_dx', 0) * SCALE
local COMBINED_ICON_DY = settings.number('appearance', 'combined_weather_icon_dy', 0) * SCALE
local hover = Hover.new(settings.number('behavior', 'weather_hover_failsafe_seconds', 4), 'content')
local icons = {}

function conky_on_mouse(event)
    if not COMBINED then return false end
    return hover:mouse(event, os.time())
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

local function icon_code(wmo, day)
    if wmo == 0 then return day and 32 or 31 end
    if wmo == 1 then return day and 34 or 33 end
    if wmo == 2 then return day and 30 or 29 end
    if wmo == 3 then return 26 end
    if wmo == 45 or wmo == 48 then return 20 end
    if wmo >= 51 and wmo <= 57 then return 9 end
    if wmo >= 61 and wmo <= 65 then return 11 end
    if wmo == 66 or wmo == 67 then return 9 end
    if wmo >= 71 and wmo <= 77 then return 13 end
    if wmo >= 80 and wmo <= 82 then return 39 end
    if wmo == 85 or wmo == 86 then return 42 end
    if wmo >= 95 then return 0 end
    return 26
end

local function draw_icon(cr, id, x, y, size)
    if not icons[id] then
        local path = base .. 'assets/weather/' .. id .. '.png'
        icons[id] = cairo_image_surface_create_from_png(path)
    end
    local surface = icons[id]
    if not surface then return end
    cairo_save(cr)
    cairo_translate(cr, x, y)
    cairo_scale(cr, size / 256, size / 256)
    cairo_set_source_surface(cr, surface, 0, 0)
    cairo_paint(cr)
    cairo_restore(cr)
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

local function draw_combined_header(cr, now, clock)
    local weather = Weather.get(now)
    local clock_baseline = 152 * SCALE
    local clock_ext = measure(cr, clock, COMBINED_CLOCK_SIZE)
    local clock_top = clock_baseline + clock_ext.y_bearing

    local temp_num = weather and string.format('%d', weather.temperature) or '--'
    local temp_full = temp_num .. '°'
    local idle_num_ext = measure(cr, temp_num, COMBINED_CLOCK_SIZE)
    local idle_full_ext = measure(cr, temp_full, COMBINED_CLOCK_SIZE)

    local icon_size = COMBINED_ICON_BASE * SCALE
    local icon_rel_x = idle_num_ext.x_advance + COMBINED_ICON_DX
    local weather_w = math.max(idle_full_ext.x_advance, icon_rel_x + icon_size)

    local div_gap = 22 * SCALE
    local total_w = clock_ext.x_advance + div_gap * 2 + weather_w
    local start_x = (conky_window.width - total_w) / 2
    local div_x = start_x + clock_ext.x_advance + div_gap
    local weather_x = div_x + div_gap

    hover:set_zones({ {
        div_x,
        math.max(0, clock_top - 15 * SCALE),
        weather_x + math.max(weather_w, 185 * SCALE) + 15 * SCALE,
        clock_baseline + 18 * SCALE,
    } })

    -- Clock
    cairo_set_font_size(cr, COMBINED_CLOCK_SIZE)
    text(cr, clock, start_x, clock_baseline, WHITE)

    -- Divider
    draw_divider(cr, div_x, clock_top - 4 * SCALE, clock_baseline + 6 * SCALE)

    -- Weather (Idle vs Hover)
    if weather and hover:visible(now) then
        local ratio = COMBINED_HOVER_TEMP_SIZE / COMBINED_CLOCK_SIZE
        local small_num_ext = measure(cr, temp_num, COMBINED_HOVER_TEMP_SIZE)
        local small_baseline = clock_top - small_num_ext.y_bearing + 2 * SCALE
        local small_icon_size = icon_size * ratio
        local small_icon_x = weather_x + small_num_ext.x_advance + COMBINED_ICON_DX * ratio
        local small_icon_y = small_baseline - small_icon_size * 0.86 + COMBINED_ICON_DY * ratio

        cairo_set_font_size(cr, COMBINED_HOVER_TEMP_SIZE)
        text(cr, temp_full, weather_x, small_baseline, BRIGHT_WHITE)
        draw_icon(cr, icon_code(weather.code, weather.is_day == 1),
            small_icon_x, small_icon_y, small_icon_size)
        draw_weather_details(cr, weather, weather_x, clock_baseline - 2 * SCALE, SCALE)
    else
        cairo_set_font_size(cr, COMBINED_CLOCK_SIZE)
        text(cr, temp_full, weather_x, clock_baseline, WHITE)
        if weather then
            local icon_x = weather_x + icon_rel_x
            local icon_y = clock_baseline - icon_size * 0.86 + COMBINED_ICON_DY
            draw_icon(cr, icon_code(weather.code, weather.is_day == 1),
                icon_x, icon_y, icon_size)
        end
    end
end

function conky_main()
    if not conky_window then return end
    local now = os.time()
    local actual_today = data_source.shift_date(now, 0)
    local actual_data = data_source.get(actual_today)
    local rollover = false
    if actual_data then
        local maghrib = data_source.timestamp(actual_today, actual_data.timings.Maghrib)
        rollover = maghrib ~= nil and now >= maghrib
    end
    -- Apply date adjustment to the displayed Hijri date, not to Maghrib's clock.
    local hijri_date = data_source.shift_date(now,
        DAYS_ADJUSTMENT + (rollover and 1 or 0))
    data_source.ensure_dates({ actual_today, hijri_date,
        data_source.date_plus(actual_today, 1) }, now)
    local hijri_data = actual_data and data_source.get(hijri_date)

    local cs, owned = Surface.acquire()
    if not cs then return end
    local cr = cairo_create(cs)
    local ext = cairo_text_extents_t:create()
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)

    local clock = os.date('%H%M', now)
    local gregorian = os.date('%A |  %d %B %Y', now)
    local y_gregorian = FONT_CLOCK + FONT_DATE + (FONT_DATE / 1.5)
    local y_hijri = y_gregorian + FONT_DATE + (FONT_DATE / 3)

    if COMBINED then
        draw_combined_header(cr, now, clock)
    else
        hover:set_zones(nil)
        cairo_set_font_size(cr, FONT_CLOCK)
        text(cr, clock, (conky_window.width - width(cr, clock, ext)) / 2,
            FONT_CLOCK, WHITE)
    end

    cairo_set_font_size(cr, FONT_DATE)
    text(cr, gregorian, (conky_window.width - width(cr, gregorian, ext)) / 2,
        y_gregorian, WHITE)

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
                text(cr, pieces[i], x, y_hijri,
                    i == 1 and day >= 12 and day <= 15 and RED or WHITE)
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
    Surface.release(cs, owned)
end
