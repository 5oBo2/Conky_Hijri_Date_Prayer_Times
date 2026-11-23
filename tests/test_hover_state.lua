-- Run with: lua tests/test_hover_state.lua  (or texlua on systems without lua)
-- Pure Lua: no display server, Conky, Cairo library, or network required.
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './tests/'
local root = base .. '../'
local Hover = dofile(root .. 'lib/Hover_State.lua')

local function move(state, x, y, now, event_type)
    assert(state:mouse({type = event_type or 'mouse_move', x = x, y = y}, now) == false)
end

-- One and multiple rectangles, inclusive edges, overlaps and independent activity.
local hover = Hover.new(4)
hover:set_zone('weather', {0, 0, 20, 20})
hover:set_zone('hijri', {{10, 10, 30, 30}, {40, 0, 60, 20}})
move(hover, 0, 20, 100, 'mouse_enter')
assert(hover:visible('weather', 100))
assert(not hover:visible('hijri', 100))
move(hover, 15, 15, 101)
assert(hover:visible('weather', 101) and hover:visible('hijri', 101))
move(hover, 50, 10, 102)
assert(not hover:visible('weather', 102) and hover:visible('hijri', 102))
assert(not hover:visible('unknown', 102))
assert(hover:visible('hijri', 105))
assert(not hover:visible('hijri', 106)) -- exact expiry boundary
move(hover, 5, 5, 110)
hover:set_zone('weather', {0, 0, 22, 22}) -- redrawing geometry preserves activity
assert(hover:visible('weather', 110))
hover:set_zone('weather', nil)
assert(not hover:visible('weather', 110))
move(hover, 15, 15, 111)
assert(hover:visible('hijri', 111))
move(hover, nil, nil, 112) -- no coordinates: fail closed for every zone
assert(not hover:visible('hijri', 112))
move(hover, 15, 15, 113)
assert(hover:mouse({type = 'mouse_leave'}, 114) == false)
assert(not hover:visible('hijri', 114))
assert(not pcall(function() hover:set_zone('', {1, 2, 3, 4}) end))
assert(not pcall(function() hover:visible(114) end)) -- no old visible(now) API
assert(hover.set_zones == nil) -- no old set_zones API

local no_expiry = Hover.new(0)
no_expiry:set_zone('window', {0, 0, 100, 100})
move(no_expiry, 50, 50, 10)
assert(no_expiry:visible('window', 100000))

-- Run the actual widget draw paths with mocked Cairo and cache data, so zone
-- geometry is defined by the widgets (not by the test) before mouse events.
package.preload.cairo = function() return true end
local function noop() end
local calls = {
    'cairo_select_font_face', 'cairo_set_font_size', 'cairo_set_source_rgba',
    'cairo_move_to', 'cairo_destroy', 'cairo_rectangle', 'cairo_fill', 'cairo_set_line_width',
    'cairo_stroke', 'cairo_pattern_add_color_stop_rgba', 'cairo_set_source',
    'cairo_pattern_destroy', 'cairo_save', 'cairo_restore', 'cairo_translate',
    'cairo_scale', 'cairo_set_source_surface', 'cairo_paint', 'cairo_curve_to',
    'cairo_close_path', 'cairo_line_to', 'cairo_set_line_cap', 'cairo_set_line_join',
}
for _, call in ipairs(calls) do _G[call] = noop end
_G.CAIRO_FONT_SLANT_NORMAL = 0
_G.CAIRO_FONT_WEIGHT_NORMAL = 0
_G.cairo_create = function() return {} end
_G.cairo_pattern_create_linear = function() return {} end
_G.cairo_image_surface_create_from_png = function() return {} end
_G.cairo_text_extents_t = {create = function() return {} end}
_G.cairo_text_extents = function(_, value, ext)
    ext.x_advance = #tostring(value) * 14
    ext.x_bearing, ext.y_bearing = 0, -20
    ext.width, ext.height = ext.x_advance, 22
end
local drawn = {}
_G.cairo_show_text = function(_, value) drawn[#drawn + 1] = tostring(value) end
local function drawn_text(value)
    for _, s in ipairs(drawn) do if s == value then return true end end
    return false
end

local real_dofile = dofile
local real_settings = real_dofile(root .. 'lib/Settings.lua')
local real_prayer_data = real_dofile(root .. 'lib/Prayer_Data.lua')
local date_mode = 'date_and_weather'
local fake_settings = setmetatable({
    get = function(section, key, default)
        return real_settings.get(section, key, default)
    end,
    date_weather_mode = function() return date_mode end,
}, {__index = real_settings})
local times = {
    Fajr = '05:00', Sunrise = '06:30', Dhuhr = '12:00', Asr = '15:00',
    Maghrib = '17:15', Isha = '18:45', Midnight = '00:00'
}
local available = true
local day = {timings = times, date = {hijri = {
    day = '15', month = {number = 8}, year = '1448'
}}}
real_prayer_data.ensure_dates = noop
real_prayer_data.get = function() return available and day or nil end
local fake_surface = {acquire = function() return {} end, release = function() end}
local fake_weather = {get = function() return {
    temperature = 23, code = 0, is_day = 1, high = 30, low = 18,
    humidity = 60, forecast = {
        {day = 'Tomorrow', high = 29, low = 18, code = 0},
        {day = 'Next day', high = 28, low = 17, code = 2},
        {day = 'Day three', high = 27, low = 16, code = 3},
    }
} end}
_G.dofile = function(path)
    if path:match('lib/Surface%.lua$') then return fake_surface end
    if path:match('lib/Prayer_Data%.lua$') then return real_prayer_data end
    if path:match('lib/Weather_Data%.lua$') then return fake_weather end
    if path:match('lib/Settings%.lua$') then return fake_settings end
    return real_dofile(path)
end
local function get_hover(callback)
    for i = 1, 30 do
        local name, value = debug.getupvalue(callback, i)
        if name == 'hover' then return value end
    end
    error('widget callback lost its hover state')
end

-- Prayer: only the upper Fajr hotspot activates elapsed time. The old
-- full-content/window modes were removed because they overlapped prayer
-- column hover targets and caused the observed false activations.
assert(loadfile(root .. 'widgets/Prayer_Times.lua'))()
local on_mouse, draw = assert(conky_on_mouse), assert(conky_main)
local state = get_hover(on_mouse)
_G.conky_window = {width = 1400, height = 255}
draw()
local rectangles = assert(state.zones.elapsed_above_fajr)
assert(#rectangles == 1)
local rect = rectangles[1]
assert(rect[1] >= 0 and rect[3] <= conky_window.width)
assert(rect[2] >= 0 and rect[4] < 255)
move(state, (rect[1] + rect[3]) / 2,
     (rect[2] + rect[4]) / 2, os.time())
assert(state:visible('elapsed_above_fajr', os.time()))
on_mouse({type = 'mouse_move', x = 700, y = 150})
assert(not state:visible('elapsed_above_fajr', os.time()))
on_mouse({type = 'mouse_move', x = 1390, y = 245})
assert(not state:visible('elapsed_above_fajr', os.time()))
on_mouse({type = 'mouse_leave'})
assert(not state:visible('elapsed_above_fajr', os.time()))
available = false
draw() -- no prayer data removes the hotspot
assert(state.zones.elapsed_above_fajr == nil)
available = true

-- Date: real draw sets the weather hitbox; hover reveals forecast text.
date_mode = 'date_and_weather'
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
local date_mouse, date_draw = assert(conky_on_mouse), assert(conky_main)
local date_hover = get_hover(date_mouse)
_G.conky_window = {width = 1000, height = 290}
date_draw()
local rect = assert(date_hover.zones.weather)[1]
local x, y = (rect[1] + rect[3]) / 2, (rect[2] + rect[4]) / 2
assert(date_mouse({type = 'mouse_enter', x = x, y = y}) == false)
assert(date_hover:visible('weather', os.time()))
drawn = {}
date_draw()
assert(drawn_text('Tomorrow')) -- real Date hover branch reached
assert(date_mouse({type = 'mouse_move', x = 0, y = 240}) == false)
assert(not date_hover:visible('weather', os.time()))
drawn = {}
date_draw()
assert(not drawn_text('Tomorrow'))
date_mouse({type = 'mouse_leave'})
assert(not date_hover:visible('weather', os.time()))

-- Date-only mode has no weather zone and cannot activate it.
date_mode = 'date_only'
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
local date_only_mouse = assert(conky_on_mouse)
local date_only_hover = get_hover(date_only_mouse)
conky_main()
assert(date_only_hover.zones.weather == nil)
assert(date_only_mouse({type = 'mouse_enter', x = x, y = y}) == false)
assert(not date_only_hover:visible('weather', os.time()))
_G.dofile = real_dofile

print('PASS: named hover zones, Fajr-only elapsed hotspot, Date forecast, mouse leave and timeouts')
