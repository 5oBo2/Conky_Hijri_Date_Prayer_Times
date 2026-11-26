-- Task 14: Worldline Gregorian hover, fixed row geometry and independent
-- weather hover zones. Run: texlua tests/test_gregorian_hover.lua
package.preload.cairo = function() return true end
local root = (debug.getinfo(1, 'S').source:match('^@(.*/)') or './tests/') .. '../'
local real_dofile, real_time = dofile, os.time
local Prayer_Data = real_dofile(root .. 'lib/Prayer_Data.lua')
local Notify = real_dofile(root .. 'lib/Notify.lua')
local schedule = {
    Fajr='05:00', Sunrise='06:30', Dhuhr='12:00', Asr='15:00',
    Maghrib='17:15', Isha='18:45', Midnight='00:30', Lastthird='02:15',
}
local hijri = {day='12', month={number=7}, year='1448'}
Prayer_Data.get = function()
    return {timings=schedule, date={hijri=hijri}}
end
Prayer_Data.ensure_dates = function() end

_G.CAIRO_FONT_SLANT_NORMAL, _G.CAIRO_FONT_WEIGHT_NORMAL = 0, 0
_G.CAIRO_LINE_CAP_ROUND, _G.CAIRO_LINE_JOIN_ROUND = 0, 0
_G.cairo_text_extents_t = {create=function() return {} end}
local captured, rectangles = {}, {}
_G.cairo_create = function() return {font=20, color={1,1,1,1}} end
_G.cairo_set_font_size = function(cr, size) cr.font=size end
_G.cairo_select_font_face = function() end
_G.cairo_text_extents = function(cr, value, ext)
    ext.x_advance = #tostring(value) * cr.font * 0.5
    ext.y_bearing = -cr.font * 0.8
    ext.height = cr.font
end
_G.cairo_set_source_rgba = function(cr, r,g,b,a) cr.color={r,g,b,a} end
_G.cairo_move_to = function(cr, x,y) cr.x,cr.y=x,y end
_G.cairo_show_text = function(cr, value)
    captured[#captured+1] = {text=tostring(value),x=cr.x,y=cr.y,
        font=cr.font,color=cr.color}
end
_G.cairo_rectangle = function(cr,x,y,w,h)
    rectangles[#rectangles+1] = {x=x,y=y,w=w,h=h,color=cr.color}
end
_G.cairo_fill = function() end
_G.cairo_set_line_width = function() end
_G.cairo_line_to = function() end
_G.cairo_stroke = function() end
_G.cairo_pattern_create_linear = function() return {} end
_G.cairo_pattern_add_color_stop_rgba = function() end
_G.cairo_set_source = function() end
_G.cairo_pattern_destroy = function() end
_G.cairo_destroy = function() end
local surface = {acquire=function() return {} end, release=function() end}
local Weather = {get=function() return nil end}
local Icons = {code=function() return 0 end, draw=function() end}
local weather_mode = 'date_only'
local scale = 1
local fake_settings = {
    get=function(_, _, fallback) return fallback end,
    scale=function() return scale end,
    date_weather_mode=function() return weather_mode end,
    boolean=function(_, _, fallback) return fallback end,
    number=function(_, key, fallback)
        local values = {
            hijri_offset_days=0,
            date_weather_hover_failsafe_seconds=0,
            date_weather_clock_size=145,
            date_weather_hover_temp_size=82,
            date_weather_icon_size=72,
            date_weather_icon_dx=0,
            date_weather_icon_dy=0,
        }
        return values[key] or fallback or 0
    end,
}
local fake_notify = {
    crossed=function() return false end,
    send_once=function() return false end,
}
_G.dofile = function(path)
    if path:match('lib/Prayer_Data%.lua$') then return Prayer_Data end
    if path:match('lib/Notify%.lua$') then return fake_notify end
    if path:match('lib/Surface%.lua$') then return surface end
    if path:match('lib/Settings%.lua$') then return fake_settings end
    if path:match('lib/Weather_Data%.lua$') then return Weather end
    if path:match('lib/Weather_Icons%.lua$') then return Icons end
    return real_dofile(path)
end

local now
os.time = function(parts)
    if parts then return real_time(parts) end
    return now
end
local function at(y,m,d,h,mi)
    return real_time{year=y,month=m,day=d,hour=h or 12,min=mi or 0,sec=0}
end
_G.conky_window = {width=720,height=360}

local function reset_capture()
    captured, rectangles = {}, {}
end
local function find_text(value)
    for _, item in ipairs(captured) do
        if item.text == value then return item end
    end
end
local function expect(value)
    return assert(find_text(value), 'missing rendered text: ' .. value)
end
local function absent(value)
    assert(not find_text(value), 'unexpected rendered text: ' .. value)
end
local function get_hover()
    for i=1,30 do
        local name, value = debug.getupvalue(conky_on_mouse, i)
        if name == 'hover' then return value end
    end
    error('Gregorian mouse hook does not expose shared hover state')
end
local function draw()
    reset_capture()
    conky_main()
end
local function enter_zone(name)
    local rect = assert(get_hover().zones[name], 'missing hover zone: ' .. name)[1]
    local x, y = (rect[1]+rect[3])/2, (rect[2]+rect[4])/2
    assert(conky_on_mouse({type='mouse_move',x=x,y=y}) == false)
end
local function leave()
    assert(conky_on_mouse({type='mouse_leave'}) == false)
end

-- Date-only mode must still receive mouse events and reveal Worldline.
now = at(2026,11,26,12,30)
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
draw()
local idle_date = os.date('%A |  %d %B %Y', now)
local idle_gregorian = expect(idle_date)
local idle_hijri = expect('Rajab')
local idle_clock = expect('1230')
local state = get_hover()
assert(state.zones.gregorian, 'Gregorian hover zone must always be present')
assert(state.zones.weather == nil, 'weather zone must be absent in date_only mode')
enter_zone('gregorian')
draw()
absent(idle_date)
local day_count = expect('330 / 365')
local progress_title = expect('YEAR PROGRESS')
expect('90.4%')
expect('WEEK 48')
expect('35 DAYS LEFT')
local right_track = assert(rectangles[1], 'missing Worldline track')
local group_right = right_track.x + right_track.w
local day_right = day_count.x + #day_count.text * day_count.font * 0.5
assert(math.abs((day_count.x + group_right) / 2 - conky_window.width / 2) < 0.001,
    'the complete Worldline group must be centered in the widget')
assert(progress_title.x >= day_right + 18 - 0.001,
    'progress block must start after the measured day count and its gap')
for _, label in ipairs({'YEAR PROGRESS', '90.4%', 'WEEK 48', '35 DAYS LEFT'}) do
    local item = expect(label)
    local rendered_right = item.x + #item.text * item.font * 0.5
    assert(item.x >= right_track.x - 0.001 and
        rendered_right <= group_right + 0.001,
        label .. ' must remain fully inside the right progress column')
end
assert(math.abs(expect('Rajab').y - idle_hijri.y) < 0.001,
    'Gregorian reveal must not move the Hijri row')
assert(math.abs(expect('Rajab').font - idle_hijri.font) < 0.001,
    'Gregorian reveal must not shrink the Hijri font')
assert(math.abs(expect('1230').y - idle_clock.y) < 0.001,
    'Gregorian reveal must not move the clock')
assert(#rectangles == 2, 'Worldline must draw track and progress fill')
assert(math.abs(rectangles[2].w / rectangles[1].w - 330/365) < 0.002,
    'year progress fill must match day-of-year / year length')
leave()
draw()
expect(idle_date)
absent('YEAR 2026')

-- Hitboxes and the reveal remain inside the Date window at supported scales.
for _, value in ipairs({0.65, 1, 1.5}) do
    scale = value
    _G.conky_window = {width=720*value,height=360*value}
    now = at(2026,11,26,12,30)
    assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
    draw()
    local rect = assert(get_hover().zones.gregorian)[1]
    assert(rect[1] >= 0 and rect[2] >= 0
        and rect[3] <= conky_window.width and rect[4] <= conky_window.height,
        'Gregorian hover hitbox must stay inside the widget at scale ' .. value)
    enter_zone('gregorian')
    draw()
    local scaled_day = expect('330 / 365')
    local scaled_track = assert(rectangles[1])
    local scaled_right = scaled_track.x + scaled_track.w
    local scaled_day_right = scaled_day.x + #scaled_day.text * scaled_day.font * 0.5
    assert(math.abs((scaled_day.x + scaled_right) / 2 - conky_window.width / 2) < 0.01,
        'Worldline group must remain centered at scale ' .. value)
    assert(scaled_day_right <= scaled_track.x + 0.001,
        'day count and progress column must not overlap at scale ' .. value)
    leave()
end
scale = 1
_G.conky_window = {width=720,height=360}

-- Leap-year end: 366/366, ISO week 01, no days remaining.
now = at(2024,12,31)
draw()
enter_zone('gregorian')
draw()
expect('366 / 366')
expect('100.0%')
expect('WEEK 01')
expect('0 DAYS LEFT')
leave()

-- Gregorian and weather hover zones remain independent in date+weather mode.
weather_mode = 'date_and_weather'
now = at(2026,11,26,12,30)
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
draw()
state = get_hover()
assert(state.zones.gregorian and state.zones.weather,
    'date+weather mode must retain both independent hover zones')
enter_zone('gregorian')
draw()
assert(get_hover():visible('gregorian', now), 'Gregorian zone should activate')
assert(not get_hover():visible('weather', now), 'Gregorian hover must not activate weather')
leave()
draw()
enter_zone('weather')
draw()
assert(get_hover():visible('weather', now), 'weather zone should still activate')
assert(not get_hover():visible('gregorian', now), 'weather hover must not activate Gregorian')
leave()

_G.dofile, os.time = real_dofile, real_time
print('Task 14: reference-matched two-column Worldline, Hijri font preservation, leap-year/ISO-week data and independent weather hover passed')
