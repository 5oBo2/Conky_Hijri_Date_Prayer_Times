-- Full-screen source comparison: original PNG on the left, production Cairo
-- vector renderer on the right. This is a developer probe, not a live widget.
require('cairo')
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './widgets/'
local root = base .. '../'
local Surface = dofile(root .. 'lib/Surface.lua')
local Weather_Icons = dofile(root .. 'lib/Weather_Icons.lua')
local settings = dofile(root .. 'lib/Settings.lua')

local ICONS = {
    {0,  'SEVERE THUNDERSTORM'},
    {5,  'FREEZING PRECIPITATION'},
    {6,  'MODERATE / HEAVY RAIN'},
    {9,  'LIGHT RAIN'},
    {13, 'LIGHT SNOW'},
    {14, 'MODERATE / HEAVY SNOW'},
    {17, 'SNOW GRAINS'},
    {20, 'FOG'},
    {26, 'OVERCAST · TWO CLOUDS'},
    {29, 'PARTLY CLOUDY · NIGHT'},
    {30, 'PARTLY CLOUDY · DAY'},
    {31, 'CLEAR · NIGHT'},
    {32, 'CLEAR · DAY'},
    {33, 'MAINLY CLEAR · NIGHT'},
    {34, 'MAINLY CLEAR · DAY'},
    {37, 'THUNDERSTORM · DAY'},
    {41, 'SNOW SHOWERS · DAY'},
    {45, 'RAIN · NIGHT'},
    {46, 'SNOW SHOWERS · NIGHT'},
    {47, 'THUNDERSTORM · NIGHT'},
}

local PNG_SURFACES = {}
local FONT = settings.get('appearance', 'font', 'DejaVu Sans')
local ACCENT = settings.get('appearance', 'next_prayer_color', '#efb46f')
local CLOSE_BOUNDS

local function rgba(cr, r, g, b, a)
    cairo_set_source_rgba(cr, r, g, b, a or 1)
end

local function color_hex(cr, hex, alpha)
    local value = tostring(hex or '#efb46f')
    if not value:match('^#%x%x%x%x%x%x$') then value = '#efb46f' end
    rgba(cr,
        tonumber(value:sub(2, 3), 16) / 255,
        tonumber(value:sub(4, 5), 16) / 255,
        tonumber(value:sub(6, 7), 16) / 255,
        alpha or 1)
end

local function font(cr, size, weight)
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL,
        weight or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
end

local function text(cr, value, x, y, size, color, weight)
    font(cr, size, weight)
    color_hex(cr, color or '#f0eeee')
    cairo_move_to(cr, x, y)
    cairo_show_text(cr, tostring(value))
end

local function centered_text(cr, value, center_x, baseline, size, color, weight)
    font(cr, size, weight)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, tostring(value), ext)
    text(cr, value, center_x - ext.x_bearing - ext.width / 2,
        baseline, size, color, weight)
end

local function rounded_rect(cr, x, y, width, height, radius)
    local r = math.min(radius, width / 2, height / 2)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + width - r, y + r, r, -math.pi / 2, 0)
    cairo_arc(cr, x + width - r, y + height - r, r, 0, math.pi / 2)
    cairo_arc(cr, x + r, y + height - r, r, math.pi / 2, math.pi)
    cairo_arc(cr, x + r, y + r, r, math.pi, math.pi * 1.5)
    cairo_close_path(cr)
end

local function load_png(icon_id)
    if PNG_SURFACES[icon_id] then return PNG_SURFACES[icon_id] end
    local filename = root .. 'assets/weather/' .. tostring(icon_id) .. '.png'
    local surface = cairo_image_surface_create_from_png(filename)
    if not surface or cairo_surface_status(surface) ~= (CAIRO_STATUS_SUCCESS or 0) then
        error('Cannot load original weather PNG: ' .. filename)
    end
    PNG_SURFACES[icon_id] = surface
    return surface
end

local function draw_original(cr, icon_id, x, y, size)
    local surface = load_png(icon_id)
    cairo_save(cr)
    cairo_translate(cr, x, y)
    cairo_scale(cr, size / 256, size / 256)
    cairo_set_source_surface(cr, surface, 0, 0)
    cairo_paint(cr)
    cairo_restore(cr)
end

local function draw_tile(cr, icon, index, x, y, width, height, icon_size, gap, scale)
    local id, name = icon[1], icon[2]
    rounded_rect(cr, x, y, width, height, 9 * scale)
    rgba(cr, 0.145, 0.145, 0.145, 1)
    cairo_fill_preserve(cr)
    rgba(cr, 0.25, 0.25, 0.25, 1)
    cairo_set_line_width(cr, math.max(1, scale))
    cairo_stroke(cr)

    text(cr, string.format('%02d', id), x + 13 * scale,
        y + 23 * scale, 12 * scale, ACCENT, CAIRO_FONT_WEIGHT_BOLD)
    text(cr, name, x + 42 * scale,
        y + 23 * scale, 11 * scale, '#e9e6e3')

    local pair_width = icon_size * 2 + gap
    local first_x = x + (width - pair_width) / 2
    local icon_y = y + 27 * scale
    draw_original(cr, id, first_x, icon_y, icon_size)
    Weather_Icons.draw(cr, id, first_x + icon_size + gap, icon_y, icon_size)

    local label_y = y + height - 8 * scale
    centered_text(cr, 'ORIGINAL PNG', first_x + icon_size / 2,
        label_y, 8.5 * scale, '#aaa6a2')
    centered_text(cr, 'CAIRO VECTOR', first_x + icon_size + gap + icon_size / 2,
        label_y, 8.5 * scale, ACCENT)
end

function conky_main()
    if not conky_window then return end
    local width, height = conky_window.width, conky_window.height
    if not width or not height or width < 100 or height < 100 then return end

    local surface = Surface.acquire()
    if not surface then return end
    local cr = cairo_create(surface)

    -- Opaque background makes the original and vector alpha edges comparable.
    rgba(cr, 0.118, 0.118, 0.118, 1)
    cairo_paint(cr)

    local scale = math.max(0.68, math.min(1.45,
        math.min(width / 1920, height / 1080)))
    local margin = math.max(15, width * 0.020)
    local header_h = math.max(62, height * 0.082)
    local footer_h = math.max(25, height * 0.030)
    local columns, rows = 4, 5
    local gap = math.max(8, width * 0.008)
    local cell_w = (width - 2 * margin - (columns - 1) * gap) / columns
    local cell_h = (height - header_h - footer_h - 2 * margin
        - (rows - 1) * gap) / rows
    local icon_size = math.min(128 * scale, cell_w * 0.28, cell_h * 0.52)
    local icon_gap = math.max(8 * scale, icon_size * 0.16)

    text(cr, 'WEATHER ICON ATLAS', margin, 34 * scale,
        23 * scale, '#f1eeeb', CAIRO_FONT_WEIGHT_NORMAL)
    text(cr, 'Original PNG  vs  production Cairo vector  ·  all 20 source icons',
        margin, 55 * scale, 10.5 * scale, '#aaa6a2')

    local legend_x = width - margin - 230 * scale
    color_hex(cr, ACCENT, 1)
    cairo_arc(cr, legend_x, 30 * scale, 5 * scale, 0, math.pi * 2)
    cairo_fill(cr)
    text(cr, 'CELESTIAL ACCENT', legend_x + 13 * scale, 34 * scale,
        9 * scale, ACCENT)
    text(cr, ACCENT, legend_x + 13 * scale, 51 * scale,
        9 * scale, '#aaa6a2')

    local close_w, close_h = 76 * scale, 28 * scale
    local close_x, close_y = width - margin - close_w, 14 * scale
    CLOSE_BOUNDS = {x=close_x, y=close_y, width=close_w, height=close_h}
    rounded_rect(cr, close_x, close_y, close_w, close_h, 5 * scale)
    rgba(cr, 0.18, 0.18, 0.18, 1)
    cairo_fill_preserve(cr)
    color_hex(cr, ACCENT, 0.9)
    cairo_set_line_width(cr, math.max(1, scale))
    cairo_stroke(cr)
    centered_text(cr, 'CLOSE', close_x + close_w / 2,
        close_y + 18 * scale, 9 * scale, ACCENT)

    for index, icon in ipairs(ICONS) do
        local row = math.floor((index - 1) / columns)
        local column = (index - 1) % columns
        local x = margin + column * (cell_w + gap)
        local y = header_h + margin + row * (cell_h + gap)
        draw_tile(cr, icon, index, x, y, cell_w, cell_h,
            icon_size, icon_gap, scale)
    end

    text(cr, '20 ORIGINAL PNGs  ·  20 LIVE CAIRO RENDERS  ·  Click CLOSE or run: python3 tools/weather_icon_probe.py --stop',
        margin, height - 10 * scale, 8.5 * scale, '#8f8b87')

    cairo_destroy(cr)
    Surface.release(surface)
end


-- A visible close control prevents the full-screen override window from
-- trapping the desktop behind it. The launcher --stop command is a fallback.
function conky_on_mouse(event)
    if not (event and event.type == 'button_down'
        and (event.button == 1 or event.button == 'left')
        and CLOSE_BOUNDS) then
        return false
    end
    local x, y = tonumber(event.x), tonumber(event.y)
    local b = CLOSE_BOUNDS
    if x and y and x >= b.x and x <= b.x + b.width
       and y >= b.y and y <= b.y + b.height then
        os.exit(0)
    end
    return false
end
