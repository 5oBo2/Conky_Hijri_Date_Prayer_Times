-- Task 15: Hijri month number and curated Islamic event hover.
-- Run: TZ=Africa/Cairo texlua tests/test_hijri_hover.lua
package.preload.cairo = function() return true end
local root = (debug.getinfo(1, 'S').source:match('^@(.*/)') or './tests/') .. '../'
local real_dofile, real_time = dofile, os.time
local Prayer_Data = real_dofile(root .. 'lib/Prayer_Data.lua')
local schedule = {
    Fajr='05:00', Sunrise='06:30', Dhuhr='12:00', Asr='15:00',
    Maghrib='17:15', Isha='18:45', Midnight='00:30', Lastthird='02:15',
}
local hijri = {day='16', month={number=6}, year='1448'}
local next_event = {
    name='Eid al-Fitr',
    hijri_date='01-10-1448',
    gregorian_date='2026-12-10',
    calendar_method='HJCoSA',
}
local ensure_calls = {}
Prayer_Data.get = function()
    return {timings=schedule, date={hijri=hijri}}
end
Prayer_Data.ensure_dates = function(dates, timestamp, displayed_date, hijri_year)
    ensure_calls = {dates=dates, now=timestamp, displayed_date=displayed_date,
        hijri_year=hijri_year}
end
Prayer_Data.get_next_hijri_event = function(_, displayed_date)
    if next_event and next_event.gregorian_date >= displayed_date then
        return next_event
    end
    return nil
end

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
local scale = 1
local hijri_offset = 0
local fake_settings = {
    get=function(_, _, fallback) return fallback end,
    scale=function() return scale end,
    date_weather_mode=function() return weather_mode end,
    boolean=function(_, _, fallback) return fallback end,
    number=function(_, key, fallback)
        local values = {
            hijri_offset_days=hijri_offset,
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
    error('Hijri mouse hook does not expose shared hover state')
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

-- Idle Hijri line remains the same; the new hover zone is separate from
-- Gregorian and clock zones and uses the already adjusted display date.
now = at(2026,11,26,12,30)
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
draw()
local idle_day = expect('16')
local idle_month = expect('Jumada Al-Akhira')
local idle_year = expect('1448')
local idle_clock = expect('12:30')
local idle_gregorian = expect(os.date('%A', now))
local state = get_hover()
assert(state.zones.hijri and state.zones.gregorian and state.zones.clock,
    'Hijri, Gregorian and clock zones must all exist')
local hijri_rect = state.zones.hijri[1]
local greg_rect = state.zones.gregorian[1]
assert(hijri_rect[2] > greg_rect[4],
    'Hijri hover hitbox must not overlap the Gregorian row')
assert(ensure_calls.displayed_date == '2026-11-26',
    'event lookup must receive the currently displayed Hijri source date')
assert(ensure_calls.hijri_year == 1448,
    'event lookup must receive the current prayer-cache Hijri year')

enter_zone('hijri')
draw()
local month_number = expect('06')
expect('/12')
local month_name = expect('Jumada Al-Akhira')
expect('1448 AH · DAY 16')
expect('NEXT ISLAMIC EVENT')
expect('Eid al-Fitr')
local countdown = expect('IN 14 DAYS')
expect('10 Dec 2026')
expect('01-10-1448 AH')
assert(month_number.color[1] > month_number.color[2] * 0.8
    and month_number.color[2] > month_number.color[3] * 0.6,
    'month index should use the configured gold accent')
assert(month_name.y > month_number.y - 20,
    'month name should sit alongside the large month index')
assert(math.abs(expect('12:30').y - idle_clock.y) < 0.001,
    'Hijri hover must not move the clock')
assert(math.abs(expect(os.date('%A', now)).y - idle_gregorian.y) < 0.001,
    'Hijri hover must not move the Gregorian date')
assert(countdown.color[1] > countdown.color[2] * 0.8,
    'event countdown should use the configured accent')
leave()
draw()
expect('16')
expect('Jumada Al-Akhira')
expect('1448')
absent('NEXT ISLAMIC EVENT')

-- Sacred months are annotated, not treated as countdown events. The idle
-- month name is already gold; hover explicitly says HOLY MONTH.
hijri = {day='16', month={number=7}, year='1448'}
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
draw()
enter_zone('hijri')
draw()
expect('1448 AH · DAY 16 · HOLY MONTH')
leave()

-- Ramadan days 20 through the end are accented. The hover note deliberately
-- says one of these nights may be Laylat al-Qadr; no individual night is
-- presented as certain.
hijri = {day='19', month={number=9}, year='1448'}
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
draw()
local ramadan_19 = expect('19')
assert(ramadan_19.color[1] > 0.9 and ramadan_19.color[2] > 0.9
    and ramadan_19.color[3] > 0.9,
    'Ramadan day 19 should keep the ordinary white date color')
enter_zone('hijri')
draw()
absent('ONE OF THESE NIGHTS MAY BE LAYLAT AL-QADR')
leave()

hijri = {day='20', month={number=9}, year='1448'}
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
draw()
local ramadan_20 = expect('20')
assert(ramadan_20.color[1] > ramadan_20.color[2]
    and ramadan_20.color[2] > ramadan_20.color[3],
    'Ramadan day 20 should use the configured gold accent')
enter_zone('hijri')
draw()
expect('ONE OF THESE NIGHTS MAY BE LAYLAT AL-QADR')
expect('1448 AH · DAY 20')
leave()

hijri = {day='30', month={number=9}, year='1448'}
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
draw()
local ramadan_30 = expect('30')
assert(ramadan_30.color[1] > ramadan_30.color[2]
    and ramadan_30.color[2] > ramadan_30.color[3],
    'Ramadan final day should use the configured gold accent')
enter_zone('hijri')
draw()
expect('ONE OF THESE NIGHTS MAY BE LAYLAT AL-QADR')
leave()

-- Event labels are application-owned canonical ASCII, not raw AlAdhan
-- holiday strings. The renderer displays the canonical label unchanged.
next_event = {
    name='Isra and Mi\'raj',
    hijri_date='27-07-1448',
    gregorian_date='2027-01-05',
    calendar_method='HJCoSA',
}
draw()
enter_zone('hijri')
draw()
local event_title = expect('Isra and Mi\'raj')
assert(event_title.x >= 0
    and event_title.x + event_title.width <= conky_window.width,
    'canonical event title must fit the widget')
leave()

-- Long names and metadata must be shortened to their measured event column,
-- rather than clipped at the widget's right edge.
next_event = {
    name=string.rep('An exceptionally long upcoming Islamic event name ', 4),
    hijri_date='22-06-1448',
    gregorian_date='2026-12-02',
    calendar_method='HJCoSA',
}
draw()
enter_zone('hijri')
draw()
local has_ellipsis = false
for _, item in ipairs(captured) do
    assert(item.x >= -0.001
        and item.x + item.width <= conky_window.width + 0.001,
        'no Hijri hover text may clip at the widget edge: ' .. item.text)
    if item.text:match('%.%.%.$') then has_ellipsis = true end
end
assert(has_ellipsis, 'long event title should be truncated with an ASCII ellipsis')
leave()

-- The next event is today relative to the widget's displayed Hijri date.
next_event = {
    name='Ashura',
    hijri_date='10-01-1448',
    gregorian_date='2026-11-26',
    calendar_method='HJCoSA',
}
draw()
enter_zone('hijri')
draw()
expect('Ashura')
expect('TODAY')
leave()

-- A configured +1 Hijri offset is already included in the displayed date
-- passed to the event lookup; the event countdown remains aligned with it.
hijri_offset = 1
next_event = {
    name='Adjusted-date event',
    hijri_date='01-07-1448',
    gregorian_date='2026-11-27',
    calendar_method='HJCoSA',
}
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
draw()
assert(ensure_calls.displayed_date == '2026-11-27',
    'configured Hijri offset must flow into the event date comparison')
enter_zone('hijri')
draw()
expect('Adjusted-date event')
expect('TODAY')
leave()
hijri_offset = 0

-- After Maghrib, the displayed Hijri source date rolls forward and is used
-- for the event countdown too.
now = at(2026,11,26,18,0)
next_event = {
    name='Tomorrow Hijri event',
    hijri_date='01-07-1448',
    gregorian_date='2026-11-27',
    calendar_method='HJCoSA',
}
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
draw()
assert(ensure_calls.displayed_date == '2026-11-27',
    'Maghrib rollover must be included in the event date comparison')
enter_zone('hijri')
draw()
expect('Tomorrow Hijri event')
expect('TODAY')
leave()

-- Year boundary arithmetic and unavailable/stale event handling.
now = at(2026,12,31,12,0)
hijri = {day='29', month={number=12}, year='1448'}
next_event = {
    name='Islamic New Year',
    hijri_date='01-01-1449',
    gregorian_date='2027-01-02',
    calendar_method='HJCoSA',
}
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
draw()
enter_zone('hijri')
draw()
expect('IN 2 DAYS')
expect('2 Jan 2027')
leave()

next_event = nil
draw()
enter_zone('hijri')
draw()
expect('Event data unavailable')
expect('Waiting for AlAdhan event data')
leave()

-- The reveal and its hitbox fit at compact, normal and enlarged scales.
for _, value in ipairs({0.65, 1, 1.5}) do
    scale = value
    hijri = {day='16', month={number=6}, year='1448'}
    next_event = {
        name='Eid al-Fitr',
        hijri_date='01-10-1448',
        gregorian_date='2027-01-15',
        calendar_method='HJCoSA',
    }
    now = at(2026,11,26,12,30)
    _G.conky_window = {width=720*scale,height=360*scale}
    assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
    draw()
    local rect = assert(get_hover().zones.hijri)[1]
    assert(rect[1] >= 0 and rect[2] >= 0
        and rect[3] <= conky_window.width and rect[4] <= conky_window.height,
        'Hijri hover hitbox must remain inside the widget at scale ' .. scale)
    enter_zone('hijri')
    draw()
    for _, label in ipairs({'06', 'Jumada Al-Akhira', 'NEXT ISLAMIC EVENT',
            'Eid al-Fitr', 'IN 50 DAYS'}) do
        local item = expect(label)
        assert(item.x >= -0.001 and item.x + item.width <= conky_window.width + 0.001,
            label .. ' must not clip at scale ' .. scale)
    end
    leave()
end

-- Weather, Gregorian and Hijri hitboxes remain independent in combined mode.
scale = 1
_G.conky_window = {width=720,height=360}
weather_mode = 'date_and_weather'
now = at(2026,11,26,12,30)
next_event = {
    name='Eid al-Fitr',
    hijri_date='01-10-1448',
    gregorian_date='2026-12-10',
    calendar_method='HJCoSA',
}
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
draw()
state = get_hover()
assert(state.zones.hijri and state.zones.gregorian and state.zones.weather,
    'combined mode must expose all date and weather hover zones')
enter_zone('hijri')
draw()
assert(get_hover():visible('hijri', now), 'Hijri hover should activate')
assert(not get_hover():visible('gregorian', now),
    'Hijri hover must not activate Gregorian')
assert(not get_hover():visible('weather', now),
    'Hijri hover must not activate weather')
leave()

_G.dofile, os.time = real_dofile, real_time
print('Task 15: Hijri month number, curated event countdown, sacred-month annotation, Laylat al-Qadr window and independent hover zones passed')
