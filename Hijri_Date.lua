-- Cairo clock and Hijri date; advances the Hijri date at Maghrib.
require('cairo')
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './'
local Surface = dofile(base .. 'Surface.lua')
local data_source = dofile(base .. 'Prayer_Data.lua')
local settings = dofile(base .. 'Settings.lua')
local SCALE = settings.scale('date')
local DAYS_ADJUSTMENT = math.floor(settings.number('behavior', 'hijri_offset_days', 0))
local MONTHS = {'Muharram', 'Safar', 'Rabi Al Awwal', 'Rabi Al Thani',
                'Jumada Al Oula', 'Jumada Al-Akhira', 'Rajab', 'Shaban',
                'Ramadan', 'Shawwal', 'Dhul Qidah', 'Dhul Hijjah'}
local WHITE = {1, 1, 1, 200 / 255}
local RED = {200 / 255, 55 / 255, 55 / 255, 200 / 255}
local FONT = settings.get('appearance', 'font', 'DejaVu Sans')
local FONT_CLOCK, FONT_DATE = 160 * SCALE, 40 * SCALE

local function text(cr, value, x, y, color)
    cairo_set_source_rgba(cr, color[1], color[2], color[3], color[4])
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, tostring(value))
end

local function width(cr, value, extents)
    cairo_text_extents(cr, tostring(value), extents)
    return extents.x_advance
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
    data_source.ensure_dates({actual_today, hijri_date,
                              data_source.date_plus(actual_today, 1)}, now)
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

    cairo_set_font_size(cr, FONT_CLOCK)
    text(cr, clock, (conky_window.width - width(cr, clock, ext)) / 2,
         FONT_CLOCK, WHITE)

    cairo_set_font_size(cr, FONT_DATE)
    text(cr, gregorian, (conky_window.width - width(cr, gregorian, ext)) / 2,
         y_gregorian, WHITE)

    if hijri_data then
        local h = hijri_data.date.hijri
        local day = tonumber(h.day)
        local month = tonumber(h.month.number)
        local year = tostring(h.year)
        if day and month and MONTHS[month] then
            local pieces = {string.format('%02d', day), MONTHS[month], year}
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
