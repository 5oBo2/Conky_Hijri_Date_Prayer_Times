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
local HOVER_ZONE_PREFIX = 'prayer_column_'
local RED = {200 / 255, 55 / 255, 55 / 255, 200 / 255}
local WHITE = {1, 1, 1, 200 / 255}
-- Task 5: option 03 (side line). Only the next prayer's name and the
-- vertical stroke use the accent; every time and other label retains the
-- original WHITE color/opacity. Accept one simple RGB hex setting.
local function parse_hex_color(hex)
    assert(type(hex) == 'string' and hex:match('^#%x%x%x%x%x%x$'),
        'appearance.next_prayer_color must be #RRGGBB (e.g. #efb46f)')
    return {tonumber(hex:sub(2, 3), 16) / 255,
            tonumber(hex:sub(4, 5), 16) / 255,
            tonumber(hex:sub(6, 7), 16) / 255, 1}
end
local NEXT_COLOR = parse_hex_color(
    settings.get('appearance', 'next_prayer_color', '#efb46f'))
local FONT = settings.get('appearance', 'font', 'DejaVu Sans')
local FONT_LARGE, FONT_SMALL = 50 * SCALE, 20 * SCALE
local ELAPSED_VISIBLE_SECONDS = math.max(0, settings.number('behavior', 'elapsed_minutes', 60)) * 60
local hover = Hover.new(settings.number('behavior', 'hover_failsafe_seconds', 5))
local last_draw_time = nil
local last_athan_event = nil
local show_last_third = false

-- Countdown events refer to the actual civil-day timestamp. Their names
-- must stay independent of the Islamic-day label shown in the seven-column row.
local function prayer_display_name(name, ts)
    if name == 'Dhuhr' and os.date('*t', ts).wday == 6 then
        return "Jumu'ah"
    end
    return name
end

-- For the main row, the Islamic *display day* changes at local Maghrib,
-- not civil midnight. In particular, Thursday Maghrib begins Friday and
-- Friday Maghrib begins Saturday. Only Dhuhr's row label/time use this
-- next-day intent; Thursday Isha and the other columns remain today's.
local function row_dhuhr_date(now, today, today_data)
    if not today_data then return today end
    local maghrib = data_source.timestamp(today, today_data.timings.Maghrib)
    if maghrib and now >= maghrib then
        return data_source.date_plus(today, 1)
    end
    return today
end

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

-- The API attaches its post-midnight night markers to the *previous*
-- civil day's schedule. Convert them into actual timestamps before comparing
-- with now. This applies to both Midnight and Lastthird.
local function night_timestamp(date, times, key)
    local time, maghrib = data_source.minutes(times[key]),
                          data_source.minutes(times.Maghrib)
    if not time or not maghrib then return nil end
    local event_date = time < maghrib and data_source.date_plus(date, 1) or date
    return data_source.timestamp(event_date, times[key])
end

local function next_hover_event(target, now, dates)
    local best
    for _, date in ipairs(dates) do
        local day = data_source.get(date)
        if day then
            local times = day.timings
            local ts = (target == 'Midnight' or target == 'Lastthird')
                and night_timestamp(date, times, target)
                or data_source.timestamp(date, times[target])
            if ts and ts >= now and (not best or ts < best.ts) then
                best = {name = target == 'Lastthird' and 'Last 3rd' or target,
                        ts = ts}
            end
        end
    end
    return best
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
            local midnight = night_timestamp(date, times, 'Midnight')
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
    return today_data, prayers, previous, upcoming, extras[1], dates
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
    text(cr, prefix .. prayer_display_name(event.name, event.ts), FONT_SMALL, x - 10 * SCALE, y, WHITE)
    text(cr, hh, FONT_LARGE, x, y + FONT_LARGE, WHITE)
    text(cr, mm, FONT_LARGE, x + FONT_LARGE + 12 * SCALE, y + FONT_LARGE, minute_color)
end

function conky_main()
    if not conky_window then return end
    local now = os.time()
    local today, events, previous, upcoming, extra, dates = schedule(now)
    check_athan(now, events)

    local cs = Surface.acquire()
    if not cs then return end
    local cr = cairo_create(cs)
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL, CAIRO_FONT_WEIGHT_NORMAL)

    if not today then
        hover:set_zone('elapsed_above_fajr', nil)
        hover:set_zone('midnight_column', nil)
        for i = 1, #LABELS do hover:set_zone(HOVER_ZONE_PREFIX .. i, nil) end
        text(cr, 'Fetching prayer times...', FONT_SMALL, 20 * SCALE, 110 * SCALE, WHITE)
    else
        local times = today.timings
        local today_date = data_source.shift_date(now, 0)
        local dhuhr_date = row_dhuhr_date(now, today_date, today)
        local dhuhr_day = data_source.get(dhuhr_date)
        -- A future Friday's Jumu'ah must display Friday's time rather
        -- than relabeling the already-past Thursday Dhuhr time.
        local row_dhuhr_time = dhuhr_day and dhuhr_day.timings.Dhuhr or '--:--'
        local dhuhr_label = prayer_display_name('Dhuhr',
            assert(data_source.timestamp(dhuhr_date, '12:00')))
        local extents = cairo_text_extents_t:create()
        local max_width = 0
        -- Size each column for both its clock value and its widest possible
        -- header, including Friday's Jumu'ah and the Last 3rd toggle.
        cairo_set_font_size(cr, FONT_LARGE)
        for _, name in ipairs(LABELS) do
            cairo_text_extents(cr, times[name], extents)
            max_width = math.max(max_width, extents.x_advance)
        end
        cairo_text_extents(cr, times.Lastthird, extents)
        max_width = math.max(max_width, extents.x_advance)
        cairo_text_extents(cr, row_dhuhr_time, extents)
        max_width = math.max(max_width, extents.x_advance)
        cairo_set_font_size(cr, FONT_SMALL)
        for _, label in ipairs({'Fajr', 'Sunrise', "Jumu'ah", 'Asr',
                                 'Maghrib', 'Isha', 'Midnight', 'Last 3rd'}) do
            cairo_text_extents(cr, label, extents)
            max_width = math.max(max_width, extents.x_advance)
        end
        local gap = 25 * SCALE
        local stride = max_width + gap
        local total = max_width * #LABELS + gap * (#LABELS - 1)
        local x0 = (conky_window.width - total) / 2
        local y0 = 150 * SCALE
        -- Make the upper elapsed hotspot one heading+time hitbox high,
        -- directly above Fajr. Begin prayer hitboxes at the visible labels
        -- (not in the empty space above them), with a small disjoint gap.
        local column_top = y0 - FONT_LARGE - FONT_SMALL + 10 * SCALE
        local column_bottom = y0 + 10 * SCALE
        local column_height = column_bottom - column_top
        local hover_gap = 3 * SCALE
        local zone_left = math.max(0, x0 - 20 * SCALE)
        local zone_top = math.max(0, column_top - hover_gap - column_height)
        local zone_right = math.min(conky_window.width, x0 + max_width + 10 * SCALE)
        local zone_bottom = column_top - hover_gap
        hover:set_zone('elapsed_above_fajr', {
            zone_left, zone_top, zone_right, zone_bottom,
        })
        if settings.boolean('behavior', 'hover_debug_outline', false) then
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
            midnight_x - 15 * SCALE, column_top,
            midnight_x + math.max(max_width, header_width) + 15 * SCALE,
            column_bottom,
        })
        -- Each row column gets a separate named hover zone. Hitboxes use the
        -- same measured stride as text, never desktop/global coordinates.
        -- The seventh zone follows the current Midnight / Last 3rd toggle.
        for i = 1, #LABELS do
            local x = x0 + (i - 1) * stride
            hover:set_zone(HOVER_ZONE_PREFIX .. i, {
                x - 12 * SCALE, column_top,
                x + max_width + 12 * SCALE, column_bottom,
            })
        end
        for i, name in ipairs(LABELS) do
            local x = x0 + (i - 1) * stride
            local label = name == 'Midnight' and show_last_third and 'Last 3rd'
                          or name == 'Dhuhr' and dhuhr_label or name
            local time = name == 'Midnight' and show_last_third and times.Lastthird
                         or name == 'Dhuhr' and row_dhuhr_time or times[name]
            -- Match canonical event names. Sunrise and Midnight/Last 3rd
            -- are informational, not "next prayer" candidates.
            local is_next = upcoming and upcoming.name == name
            if is_next then
                -- HTML option 03: one solid sideline, no tile/glow/pill and
                -- no change to the time's original color or opacity.
                cairo_set_source_rgba(cr, NEXT_COLOR[1], NEXT_COLOR[2],
                                      NEXT_COLOR[3], NEXT_COLOR[4])
                cairo_rectangle(cr, x - 23 * SCALE,
                    y0 - FONT_LARGE - FONT_SMALL,
                    3 * SCALE, FONT_LARGE + FONT_SMALL + 6 * SCALE)
                cairo_fill(cr)
            end
            text(cr, label, FONT_SMALL, x - 10 * SCALE, y0 - FONT_LARGE,
                 is_next and NEXT_COLOR or WHITE)
            text(cr, time, FONT_LARGE, x, y0, WHITE)
        end

        if previous and (hover:visible('elapsed_above_fajr', now) or now - previous.ts <= ELAPSED_VISIBLE_SECONDS) then
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
        -- Hovering a different column adds a temporary countdown without
        -- replacing the primary countdown or its Sunrise/Midnight companion.
        -- Ignore both already-displayed targets rather than duplicating them.
        for i, name in ipairs(LABELS) do
            if hover:visible(HOVER_ZONE_PREFIX .. i, now) then
                local target = (name == 'Midnight' and show_last_third)
                    and 'Lastthird' or name
                if (not upcoming or target ~= upcoming.name)
                   and (not extra or target ~= extra.name) then
                    local selected = next_hover_event(target, now, dates)
                    if selected then
                        countdown(cr, 'Till ', selected, now,
                                  x0 + (extra and 2 or 1) * stride,
                                  y0 + 30 * SCALE,
                                  selected.ts - now <= 15 * 60)
                    end
                end
                break -- at most one hovered prayer countdown
            end
        end
    end
    cairo_destroy(cr)
    Surface.release(cs)
end
