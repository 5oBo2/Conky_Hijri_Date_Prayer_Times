-- Run with: texlua tests/test_weather_icons.lua (or lua).
-- Pure Lua: Cairo, Conky, data caches and PNG loading are stubbed.
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './tests/'
local root = base .. '../'
local Icons = dofile(root .. 'lib/Weather_Icons.lua')

-- Preserve the entire existing WMO-to-icon mapping, including code 97.
local cases = {
    {0,32,31}, {1,34,33}, {2,30,29}, {3,26,26}, {45,20,20},
    {48,20,20}, {51,9,45}, {53,9,45}, {55,6,45}, {56,5,5},
    {57,5,5}, {61,9,45}, {63,6,45}, {65,6,45}, {66,5,5},
    {67,5,5}, {71,13,13}, {73,14,14}, {75,14,14}, {77,17,17},
    {80,9,45}, {81,6,45}, {82,6,45}, {85,41,46}, {86,14,46},
    {95,37,47}, {96,0,0}, {97,37,47}, {99,0,0}, {999,26,26},
}
for _, test in ipairs(cases) do
    local wmo, daytime, nighttime = test[1], test[2], test[3]
    assert(Icons.code(wmo, true) == daytime, 'day WMO ' .. wmo)
    assert(Icons.code(wmo, false) == nighttime, 'night WMO ' .. wmo)
end

package.preload.cairo = function() return true end
local function noop() end
for _, method in ipairs({
    'cairo_select_font_face', 'cairo_set_font_size', 'cairo_set_source_rgba',
    'cairo_move_to', 'cairo_show_text', 'cairo_destroy', 'cairo_set_line_width',
    'cairo_stroke', 'cairo_pattern_add_color_stop_rgba', 'cairo_set_source',
    'cairo_pattern_destroy', 'cairo_save', 'cairo_restore', 'cairo_translate',
    'cairo_scale', 'cairo_paint', 'cairo_curve_to', 'cairo_close_path',
    'cairo_line_to', 'cairo_set_line_cap', 'cairo_set_line_join',
}) do _G[method] = noop end
_G.CAIRO_FONT_SLANT_NORMAL = 0
_G.CAIRO_FONT_WEIGHT_NORMAL = 0
_G.CAIRO_FONT_WEIGHT_BOLD = 1
_G.CAIRO_LINE_CAP_ROUND = 0
_G.CAIRO_LINE_JOIN_ROUND = 0
_G.cairo_create = function() return {} end
_G.cairo_pattern_create_linear = function() return {} end
_G.cairo_text_extents_t = {create = function() return {} end}
_G.cairo_text_extents = function(_, value, ext)
    ext.x_advance = #tostring(value) * 14
    ext.x_bearing, ext.y_bearing = 0, -20
    ext.width, ext.height = ext.x_advance, 22
end

local loads, draws = {}, {}
_G.cairo_image_surface_create_from_png = function(path)
    assert(path:match('assets/weather/%d+%.png$'), path)
    loads[#loads + 1] = path:match('(%d+)%.png$')
    return {path = path}
end
_G.cairo_set_source_surface = function(_, surface)
    draws[#draws + 1] = surface.path:match('(%d+)%.png$')
end
local function count(items, target)
    local total = 0
    for _, value in ipairs(items) do if value == target then total = total + 1 end end
    return total
end

-- One loaded surface per icon ID; repeated draws use the cached surface.
Icons.draw({}, 37, 1, 2, 256)
Icons.draw({}, 37, 3, 4, 30)
Icons.draw({}, 47, 1, 2, 10)
assert(#loads == 2 and count(loads, '37') == 1)
assert(#draws == 3 and draws[1] == '37' and draws[3] == '47')

-- Run both actual widget draw paths with the same fake current/forecast data.
local real_dofile = dofile
local settings = real_dofile(root .. 'lib/Settings.lua')
local fake_surface = {acquire = function() return {} end, release = function() end}
local weather = {
    temperature = 23, high = 30, low = 18, humidity = 60,
    code = 97, is_day = 1, fetched = os.time(),
    forecast = {
        {day = 'Mon', code = 97, high = 25, low = 17},
        {day = 'Tue', code = 2, high = 24, low = 16},
        {day = 'Wed', code = 99, high = 22, low = 15},
    },
}
local fake_weather = {get = function() return weather end}
local fake_prayer = {
    shift_date = function() return '2026-11-22' end,
    date_plus = function() return '2026-11-23' end,
    ensure_dates = noop,
    timestamp = function() return os.time() + 10000 end,
    get = function() return {timings = {Maghrib = '20:00'}, date = {hijri = {
        day = '10', month = {number = 8}, year = '1448'
    }}} end,
}
_G.dofile = function(path)
    if path:match('lib/Surface%.lua$') then return fake_surface end
    if path:match('lib/Weather_Data%.lua$') then return fake_weather end
    if path:match('lib/Prayer_Data%.lua$') then return fake_prayer end
    if path:match('lib/Settings%.lua$') then return settings end
    return real_dofile(path)
end
_G.conky_window = {width = 1000, height = 290}

loads, draws = {}, {}
assert(loadfile(root .. 'widgets/Weather.lua'))()
conky_main()
conky_main()
assert(#loads == 1 and loads[1] == '37', 'Weather must load the current icon once')
assert(#draws == 2 and draws[1] == '37' and draws[2] == '37')

loads, draws = {}, {}
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
conky_main() -- registers named weather hover area and draws current icon
assert(loads[1] == '37', 'Date idle must use the same current-condition icon')
assert(conky_on_mouse({type = 'mouse_enter', x = 950, y = 30}) == false)
local before = #draws
conky_main() -- current icon plus 3 forecast icons
assert(#draws == before + 4, 'Date hover must draw current plus three forecast icons')
assert(draws[before + 1] == '37')
assert(draws[before + 2] == '37')
assert(draws[before + 3] == '30')
assert(draws[before + 4] == '0')
assert(count(loads, '37') == 1, 'Date must cache repeated PNG IDs')
assert(count(loads, '30') == 1 and count(loads, '0') == 1)
_G.dofile = real_dofile

print('PASS: all WMO icons, cached PNG drawing, Weather current and Date current/3-day hover')
