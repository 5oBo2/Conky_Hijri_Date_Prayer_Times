-- Task 13: Whisper clock hover, local timezone and live UTC detail.
-- Run with TZ=Africa/Cairo: TZ=Africa/Cairo texlua tests/test_clock_hover.lua
package.preload.cairo = function() return true end
local root = (debug.getinfo(1, 'S').source:match('^@(.*/)') or './tests/') .. '../'
local real_dofile, real_time = dofile, os.time
local Prayer_Data = real_dofile(root .. 'lib/Prayer_Data.lua')
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
local captured = {}
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
    local label = tostring(value)
    captured[#captured+1] = {
        text=label, x=cr.x, y=cr.y, font=cr.font,
        width=#label * cr.font * 0.5, color=cr.color,
    }
end
_G.cairo_rectangle = function() end
_G.cairo_fill = function() end
_G.cairo_set_line_width = function() end
_G.cairo_line_to = function() end
_G.cairo_stroke = function() end
_G.cairo_arc = function() end
_G.cairo_pattern_create_linear = function() return {} end
_G.cairo_pattern_add_color_stop_rgba = function() end
_G.cairo_set_source = function() end
_G.cairo_pattern_destroy = function() end
_G.cairo_destroy = function() end

local surface = {acquire=function() return {} end, release=function() end}
local Weather = {get=function() return nil end}
local Icons = {code=function() return 0 end, draw=function() end}
local weather_mode = 'date_only'
local fake_settings = {
    get=function(_, _, fallback) return fallback end,
    scale=function() return 1 end,
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
local function at(y,m,d,h,mi,sec)
    return real_time{year=y,month=m,day=d,hour=h or 12,min=mi or 0,sec=sec or 0}
end
_G.conky_window = {width=720,height=360}

local function reset_capture() captured = {} end
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
    error('clock mouse hook does not expose shared hover state')
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
local function offset_label(timestamp)
    local raw = os.date('%z', timestamp) or ''
    local sign, hours, minutes = raw:match('^([+-])(%d%d):?(%d%d)$')
    return sign and string.format('UTC%s%s:%s', sign, hours, minutes) or 'UTC'
end

-- Date-only: idle time remains clean; hover reveals Whisper seconds and
-- timezone/UTC details inside the original clock footprint.
now = at(2026,11,26,12,30,5)
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
draw()
local idle_time = expect('12:30')
local gregorian = expect(os.date('%A', now))
local hijri_month = expect('Rajab')
absent(':05')
absent(os.date('%Z', now))
local state = get_hover()
assert(state.zones.clock, 'clock hover zone must exist in date_only mode')
assert(state.zones.weather == nil, 'weather zone must be absent in date_only mode')
assert(state.zones.gregorian, 'Gregorian hover zone must remain present')
local clock_rect = state.zones.clock[1]
local greg_rect = state.zones.gregorian[1]
assert(clock_rect[4] < greg_rect[2],
    'clock details hitbox must not overlap Gregorian hitbox')
enter_zone('clock')
draw()
local main = expect('12:30')
local seconds = expect(':05')
local zone = expect(os.date('%Z', now))
local offset = expect(offset_label(now))
local utc_marker = expect(' · UTC ')
local utc_time = expect(os.date('!%H:%M:%S', now))
local iana_zone = expect(os.getenv('TZ'))
assert(zone.y == offset.y and offset.y == iana_zone.y
    and iana_zone.y == utc_marker.y and utc_marker.y == utc_time.y,
    'timezone, offset, IANA identifier and UTC clock must share one line')
assert(seconds.x >= main.x + main.width,
    'seconds must sit immediately to the right of HH:MM')
assert(seconds.y > main.y,
    'seconds must be bottom-aligned, not raised above the main time')
assert(seconds.font < main.font,
    'seconds must use smaller Whisper typography')
assert(offset.y == zone.y,
    'timezone and UTC offset must share one line')
assert(math.abs((zone.y - main.y) - 26) < 0.001,
    'timezone metadata must sit on the raised clock guide line')
assert(math.abs(gregorian.y - expect(os.date('%A', now)).y) < 0.001,
    'clock hover must not move Gregorian date')
assert(math.abs(hijri_month.y - expect('Rajab').y) < 0.001,
    'clock hover must not move Hijri date')
assert(seconds.x + seconds.width <= clock_rect[3] - 8,
    'inline seconds must stay inside the reserved clock footprint')
assert(iana_zone.x >= clock_rect[1] + 4
    and utc_time.x + utc_time.width <= clock_rect[3] - 4,
    'the complete timezone/UTC information line must fit inside the clock slot')
leave()
draw()
expect(idle_time.text)
absent(':05')
absent(os.date('%Z', now))

-- Cairo daylight-saving time is read from the host timezone database, not
-- hardcoded: the same renderer must show EEST/+03 in summer when applicable.
now = at(2026,7,1,12,30,5)
draw()
enter_zone('clock')
draw()
expect(os.date('%Z', now))
expect(offset_label(now))
expect(os.getenv('TZ'))
expect(' · UTC ')
expect(os.date('!%H:%M:%S', now))
leave()

-- date_and_weather: clock and weather have distinct hitboxes. Hovering the
-- clock reveals time details without activating the weather forecast area.
weather_mode = 'date_and_weather'
now = at(2026,11,26,12,30,5)
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
draw()
state = get_hover()
assert(state.zones.clock and state.zones.weather,
    'date+weather mode must retain both clock and weather zones')
clock_rect = state.zones.clock[1]
local weather_rect = state.zones.weather[1]
assert(clock_rect[3] < weather_rect[1],
    'clock and weather hover zones must not overlap')
enter_zone('clock')
draw()
expect(':05')
assert(get_hover():visible('clock', now), 'clock hover should activate')
assert(not get_hover():visible('weather', now),
    'clock hover must not activate weather')
leave()

_G.dofile, os.time = real_dofile, real_time
print('Task 13: Whisper inline seconds, local timezone/DST, IANA zone, single-line UTC clock, fixed layout and independent hover zones passed')
