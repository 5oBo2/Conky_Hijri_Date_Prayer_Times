-- Compact transparent weather widget styled to the supplied 282x155 target.
-- Always renders independently, including when the Date window shows weather.
require('cairo')
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './widgets/'
local root = base .. '../'
local Surface = dofile(root .. 'lib/Surface.lua')
local Weather = dofile(root .. 'lib/Weather_Data.lua')
local Weather_Icons = dofile(root .. 'lib/Weather_Icons.lua')
local settings = dofile(root .. 'lib/Settings.lua')
local SCALE = settings.scale('weather')
local FONT = settings.get('appearance', 'font', 'DejaVu Sans')
local WHITE = { 1, 1, 1, 0.96 }
local MUTED = { 0.73, 0.81, 0.85, 0.88 }
local BLUE = { 0.10, 0.80, 1.0, 1 }
local ORANGE = { 1, 0.47, 0.19, 1 }
-- Tunable icon placement (widget-local units, before weather_scale).
local ICON_X = settings.number('appearance', 'weather_icon_x', 130)
local ICON_Y = settings.number('appearance', 'weather_icon_y', -13)
local ICON_SIZE = settings.number('appearance', 'weather_icon_size', 137)

local function color(cr, c)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], c[4])
end
local function set_font(cr, size, heavy)
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL,
        heavy and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
end
local function txt(cr, s, x, y, size, c, heavy)
    set_font(cr, size, heavy)
    color(cr, c or WHITE)
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, tostring(s))
end
-- Cairo's ink bounds account for side bearings (notably the digit "1"),
-- so the visible gap stays equal even when the temperatures change.
local function text_extents(cr, s, size)
    set_font(cr, size, false)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, tostring(s), ext)
    return ext
end
-- Both directions share the same geometry and exact vertical midpoint.
-- Anchor this midpoint to the ink center of the temperature row, without
-- direction-specific offsets (which previously separated the arrows).
local ARROW_HALF_WIDTH = 3
local ARROW_HALF_HEIGHT = 6
local ARROW_HEAD_LENGTH = 3
local ARROW_STROKE = 1.6
local ARROW_TEXT_GAP = 5
local GROUP_GAP = 9

local function draw_arrow(cr, x, row_center_y, direction)
    local y = row_center_y
    local tip_y = y + direction * ARROW_HALF_HEIGHT
    local tail_y = y - direction * ARROW_HALF_HEIGHT
    local head_base_y = tip_y - direction * ARROW_HEAD_LENGTH

    color(cr, direction < 0 and ORANGE or BLUE)
    cairo_set_line_width(cr, ARROW_STROKE)
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND)
    cairo_set_line_join(cr, CAIRO_LINE_JOIN_ROUND)
    cairo_move_to(cr, x, tail_y)
    cairo_line_to(cr, x, tip_y)
    cairo_move_to(cr, x - ARROW_HALF_WIDTH, head_base_y)
    cairo_line_to(cr, x, tip_y)
    cairo_line_to(cr, x + ARROW_HALF_WIDTH, head_base_y)
    cairo_stroke(cr)
end

-- Place text relative to the arrow's rightmost drawn edge, taking the
-- actual glyph left side bearing into account, not just its text origin.
local function arrow_text_x(arrow_x, ext)
    return arrow_x + ARROW_HALF_WIDTH + ARROW_STROKE / 2
        + ARROW_TEXT_GAP - ext.x_bearing
end
local function droplet(cr, x, y)
    color(cr, BLUE); cairo_set_line_width(cr, 2)
    cairo_move_to(cr, x, y - 10)
    cairo_curve_to(cr, x - 5, y - 2, x - 7, y + 1, x - 5, y + 5)
    cairo_curve_to(cr, x - 2, y + 10, x + 3, y + 9, x + 5, y + 5)
    cairo_curve_to(cr, x + 7, y + 1, x + 5, y - 2, x, y - 10)
    cairo_close_path(cr); cairo_stroke(cr)
end

function conky_main()
    if not conky_window then return end
    local weather = Weather.get(os.time())
    local surface = Surface.acquire()
    if not surface then return end
    local cr = cairo_create(surface)
    cairo_scale(cr, SCALE, SCALE)
    if not weather then
        txt(cr, 'Weather', 24, 68, 39)
        txt(cr, 'Fetching current conditions…', 26, 113, 16, MUTED)
    else
        -- Target: smaller, bolder temperature above closely grouped readings.
        txt(cr, string.format('%d°', weather.temperature), 27, 62, 50, WHITE, true)

        -- Measure the ink, so orange/blue arrow-to-digit gaps are identical
        -- even for 1, negatives, or fonts with asymmetric side bearings.
        local high = string.format('%d°', weather.high)
        local low = string.format('%d°', weather.low)
        local reading_size, reading_baseline = 17, 89
        local high_ext = text_extents(cr, high, reading_size)
        local low_ext = text_extents(cr, low, reading_size)
        -- Use a shared vertical midpoint of both texts' visible ink.
        local ink_top = math.min(high_ext.y_bearing, low_ext.y_bearing)
        local ink_bottom = math.max(high_ext.y_bearing + high_ext.height,
            low_ext.y_bearing + low_ext.height)
        local row_center = reading_baseline + (ink_top + ink_bottom) / 2

        local high_arrow_x = 31
        local high_x = arrow_text_x(high_arrow_x, high_ext)
        -- The second group starts a fixed distance after the visible ink.
        local high_right = high_x + high_ext.x_bearing + high_ext.width
        local low_arrow_x = high_right + GROUP_GAP + ARROW_HALF_WIDTH + ARROW_STROKE / 2
        local low_x = arrow_text_x(low_arrow_x, low_ext)

        draw_arrow(cr, high_arrow_x, row_center, -1)
        txt(cr, high, high_x, reading_baseline, reading_size)
        draw_arrow(cr, low_arrow_x, row_center, 1)
        txt(cr, low, low_x, reading_baseline, reading_size)

        droplet(cr, 34, 114)
        local humidity = string.format('%d%%', weather.humidity)
        local humidity_ext = text_extents(cr, humidity, 18)
        -- Droplet's right-hand cubic curve reaches x+~6; its stroke adds 1.
        local humidity_x = 34 + 7 + 5 - humidity_ext.x_bearing
        txt(cr, humidity, humidity_x, 121, 18)
        Weather_Icons.draw(cr, Weather_Icons.code(weather.code, weather.is_day == 1),
            ICON_X, ICON_Y, ICON_SIZE)
        if os.time() - weather.fetched > 10800 then
            txt(cr, 'Updating…', 174, 142, 11, MUTED)
        end
    end
    cairo_destroy(cr)
    Surface.release(surface)
end
