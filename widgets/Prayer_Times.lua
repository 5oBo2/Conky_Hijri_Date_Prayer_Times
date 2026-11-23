-- Cairo prayer times, absolute-timestamp countdowns and optional mouse hover.
-- Local system timezone must match the chosen Aladhan location.
require('cairo')
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './widgets/'
local root = base .. '../'
local Surface = dofile(root .. 'lib/Surface.lua')
local data_source = dofile(root .. 'lib/Prayer_Data.lua')
local settings = dofile(root .. 'lib/Settings.lua')
local Hover = dofile(root .. 'lib/Hover_State.lua')
local SCALE = settings.scale('prayer')
local ENABLE_ATHAN = settings.boolean('behavior', 'athan_enabled', true)

local PRAYERS = {'Fajr', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'}
local LABELS = {'Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha', 'Midnight'}
local RED = {200 / 255, 55 / 255, 55 / 255, 200 / 255}
local WHITE = {1, 1, 1, 200 / 255}
local FONT = settings.get('appearance', 'font', 'DejaVu Sans')
local FONT_LARGE, FONT_SMALL = 50 * SCALE, 20 * SCALE
local ELAPSED_VISIBLE_SECONDS = math.max(0, settings.number('behavior', 'elapsed_minutes', 60)) * 60
local HOVER_AREA = settings.get('behavior', 'hover_area', 'content')
local hover = Hover.new(settings.number('behavior', 'hover_failsafe_seconds', 5))
local last_draw_time = nil
local last_athan_event = nil
local show_last_third = false

-- With lua_mouse_hook = 'on_mouse' in the config, Conky calls this function.
function conky_on_mouse(event)
    if event.type == 'button_down' and event.button == 'left'
       and hover:contains('midnight_column', event.x, event.y) then
        show_last_third = not show_last_third
        return true -- prevent a click on the desktop/window behind Conky
    end
    return hover:mouse(event, os.time())
end

local function add_event(out, name, date, text)
    local ts = data_source.timestamp(date, text)
    if ts then out[#out + 1] = {name = name, ts = ts} end
end

local function midnight_timestamp(date, times)
    local actual_date = date
    -- The API's Midnight 00:xx refers to the night following today's Isha.
    if data_source.minutes(times.Midnight) < data_source.minutes(times.Maghrib) then
        actual_date = data_source.date_plus(date, 1)
    end
    return data_source.timestamp(actual_date, times.Midnight)
end

local function schedule(now)
    local today = data_source.shift_date(now, 0)
    local dates = {today, data_source.shift_date(now, -1),
                   data_source.shift_date(now, 1)}
    data_source.ensure_dates(dates, now)
    local today_data = data_source.get(today)
    local prayers, extras = {}, {}
    for _, date in ipairs(dates) do
        local day = data_source.get(date)
        if day then
            local times = day.timings
            for _, name in ipairs(PRAYERS) do
                add_event(prayers, name, date, times[name])
            end
            local fajr = data_source.timestamp(date, times.Fajr)
            local sunrise = data_source.timestamp(date, times.Sunrise)
            if fajr and sunrise and fajr <= now and now < sunrise then
                extras[#extras + 1] = {name = 'Sunrise', ts = sunrise}
            end
            local isha = data_source.timestamp(date, times.Isha)
            local midnight = midnight_timestamp(date, times)
            if isha and midnight and isha <= now and now < midnight then
                extras[#extras + 1] = {name = 'Midnight', ts = midnight}
            end
        end
    end
    table.sort(prayers, function(a, b) return a.ts < b.ts end)
    table.sort(extras, function(a, b) return a.ts < b.ts end)

    local previous, upcoming
    for _, prayer in ipairs(prayers) do
        if prayer.ts <= now then previous = prayer
        elseif not upcoming then upcoming = prayer end
    end
    return today_data, prayers, previous, upcoming, extras[1]
end

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function check_athan(now, prayers)
    -- No playback at startup and no late playback after sleep or clock jumps.
    if ENABLE_ATHAN and last_draw_time and now >= last_draw_time and now - last_draw_time <= 120 then
        for _, event in ipairs(prayers) do
            if last_draw_time < event.ts and event.ts <= now
               and now - event.ts <= 60 and last_athan_event ~= event.ts then
                last_athan_event = event.ts
                local audio = root .. 'athan.wav'
                local f = io.open(audio, 'rb')
                if not f then
                    audio = root .. 'assets/athan.wav'
                    f = io.open(audio, 'rb')
                end
                if f then
                    f:close()
                    os.execute('paplay ' .. shell_quote(audio) .. ' >/dev/null 2>&1 &')
                end
            end
        end
    end
    last_draw_time = now
end

local function text(cr, value, font_size, x, y, color)
    cairo_set_font_size(cr, font_size)
    cairo_set_source_rgba(cr, color[1], color[2], color[3], color[4])
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, tostring(value))
end

local function countdown(cr, prefix, event, now, x, y, alert)
    if not event then return end
    local seconds = math.max(0, (prefix == 'Since ' and now - event.ts)
                                  or (event.ts - now))
    local hh, mm = data_source.hms(seconds)
    local minute_color = (alert and RED or WHITE)
    text(cr, prefix .. event.name, FONT_SMALL, x - 10 * SCALE, y, WHITE)
    text(cr, hh, FONT_LARGE, x, y + FONT_LARGE, WHITE)
    text(cr, mm, FONT_LARGE, x + FONT_LARGE + 12 * SCALE, y + FONT_LARGE, minute_color)
end

function conky_main()
    if not conky_window then return end
    local now = os.time()
    local today, events, previous, upcoming, extra = schedule(now)
    check_athan(now, events)

    local cs = Surface.acquire()
    if not cs then return end
    local cr = cairo_create(cs)
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)

    if not today then
        hover:set_zone('fajr_sunrise', nil)
        hover:set_zone('midnight_column', nil)
        text(cr, 'Fetching prayer times...', FONT_SMALL, 20 * SCALE, 110 * SCALE, WHITE)
    else
        local times = today.timings
        local extents = cairo_text_extents_t:create()
        local max_width = 0
        cairo_set_font_size(cr, FONT_LARGE)
        for _, name in ipairs(LABELS) do
            cairo_text_extents(cr, times[name], extents)
            if extents.x_advance > max_width then max_width = extents.x_advance end
        end
        local gap = 25 * SCALE
        local stride = max_width + gap
        local total = max_width * #LABELS + gap * (#LABELS - 1)
        local x0 = (conky_window.width - total) / 2
        local y0 = 150 * SCALE
        -- Hover only over meaningful visible content, not the huge empty
        -- transparent area of the window. 'window' in settings.ini restores
        -- the whole-window behavior if preferred.
        -- 'fajr_sunrise' is a small, scale-aware hotspot above the first two
        -- headings (the red-box location in the user's screenshot). It moves
        -- with the prayer row and doesn't require screen or global coordinates.
        -- Hover_State.lua compares event.x/event.y in Conky-local pixels.
        local zone_left = x0 - 22 * SCALE
        local zone_top = y0 - FONT_LARGE - 75 * SCALE
        local zone_right = x0 + stride + 50 * SCALE
        local zone_bottom = y0 - FONT_LARGE + 15 * SCALE
        if HOVER_AREA == 'fajr_sunrise' then
            hover:set_zone('fajr_sunrise', {zone_left, zone_top, zone_right, zone_bottom})
        elseif HOVER_AREA == 'window' then
            hover:set_zone('fajr_sunrise', {0, 0, conky_window.width, conky_window.height})
        else
            -- 'content' spans two visible areas but remains one named zone.
            hover:set_zone('fajr_sunrise', {
                {x0 - 20 * SCALE, 0, x0 + 300 * SCALE, 82 * SCALE},
                {x0 - 20 * SCALE, 65 * SCALE,
                 x0 + total + 20 * SCALE, conky_window.height},
            })
        end
        -- Optional temporary outline to show the effective hover hotspot.
        if HOVER_AREA == 'fajr_sunrise' and
           settings.boolean('behavior', 'hover_debug_outline', false) then
            cairo_set_source_rgba(cr, 1, 0.28, 0.28, 0.8)
            cairo_set_line_width(cr, math.max(1, SCALE))
            cairo_rectangle(cr, zone_left, zone_top,
                zone_right - zone_left, zone_bottom - zone_top)
            cairo_stroke(cr)
        end
        local midnight_x = x0 + (#LABELS - 1) * stride
        -- Include the longer header as well as the large time in the hitbox.
        cairo_set_font_size(cr, FONT_SMALL)
        cairo_text_extents(cr, 'Midnight', extents)
        local header_width = extents.x_advance
        cairo_text_extents(cr, 'Last 3rd', extents)
        header_width = math.max(header_width, extents.x_advance)
        hover:set_zone('midnight_column', {
            midnight_x - 15 * SCALE, y0 - FONT_LARGE - FONT_SMALL - 10 * SCALE,
            midnight_x + math.max(max_width, header_width) + 15 * SCALE,
            y0 + 10 * SCALE,
        })
        for i, name in ipairs(LABELS) do
            local x = x0 + (i - 1) * stride
            local label = name == 'Midnight' and show_last_third and 'Last 3rd' or name
            local time = name == 'Midnight' and show_last_third and times.Lastthird or times[name]
            text(cr, label, FONT_SMALL, x - 10 * SCALE, y0 - FONT_LARGE, WHITE)
            text(cr, time, FONT_LARGE, x, y0, WHITE)
        end

        if previous and (hover:visible('fajr_sunrise', now) or now - previous.ts <= ELAPSED_VISIBLE_SECONDS) then
            local elapsed = now - previous.ts
            countdown(cr, 'Since ', previous, now, x0, 20 * SCALE,
                      elapsed > 5 * 60 and elapsed < 20 * 60)
        end
        if upcoming then
            countdown(cr, 'Till ', upcoming, now, x0, y0 + 30 * SCALE,
                      upcoming.ts - now <= 15 * 60)
        end
        if extra then
            countdown(cr, 'Till ', extra, now, x0 + stride, y0 + 30 * SCALE,
                      extra.ts - now <= 15 * 60)
        end
    end
    cairo_destroy(cr)
    Surface.release(cs)
end
