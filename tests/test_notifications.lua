-- Task 7: run real Prayer/Date draw hooks against fixed clocks and mock Cairo.
-- Never issue desktop notifications from this test.
package.preload.cairo = function() return true end
local root = (debug.getinfo(1, 'S').source:match('^@(.*/)') or './tests/') .. '../'
local real_dofile, real_time = dofile, os.time
local Prayer_Data = real_dofile(root .. 'lib/Prayer_Data.lua')
local Notify = real_dofile(root .. 'lib/Notify.lua')
local schedule = {
    Fajr='05:00', Sunrise='06:30', Dhuhr='12:00', Asr='15:00',
    Maghrib='17:15', Isha='18:45', Midnight='00:30', Lastthird='02:15',
}
local today_hijri = {day='12', month={number=7}, year='1448'}
local next_hijri = {day='13', month={number=7}, year='1448'}
local current_day
local next_day
Prayer_Data.get = function(date)
    if date == next_day then return {timings=schedule, date={hijri=next_hijri}} end
    return {timings=schedule, date={hijri=today_hijri}}
end
Prayer_Data.ensure_dates = function() end
_G.CAIRO_FONT_SLANT_NORMAL, _G.CAIRO_FONT_WEIGHT_NORMAL = 0, 0
_G.cairo_text_extents_t = {create=function() return {} end}
_G.cairo_create = function() return {color={1,1,1,1}} end
_G.cairo_set_font_size = function() end
_G.cairo_select_font_face = function() end
_G.cairo_text_extents = function(_, label, ext) ext.x_advance = #tostring(label) * 18 end
_G.cairo_move_to = function() end
_G.cairo_destroy = function() end
_G.cairo_arc = function() end
_G.cairo_rectangle = function() end
_G.cairo_fill = function() end
_G.cairo_set_line_width = function() end
_G.cairo_stroke = function() end
_G.cairo_set_source_rgba = function(cr, r,g,b,a) cr.color={r,g,b,a} end
local captured = {}
_G.cairo_show_text = function(cr, value)
    captured[#captured + 1] = {text=tostring(value), color=cr.color}
end
local surface = {acquire=function() return {} end, release=function() end}
local Weather = {get=function() return nil end}
local Icons = {code=function() return 0 end, draw=function() end}
local accent_override
local fake_settings = {
    get=function(_, name, fallback)
        if name == 'next_prayer_color' then return accent_override or fallback end
        return fallback
    end,
    scale=function() return 1 end,
    date_weather_mode=function() return 'date_only' end,
    boolean=function(_, key, fallback)
        if key == 'athan_enabled' then return false end
        return fallback
    end,
    number=function(_, key, fallback)
        if fallback ~= nil then return fallback end
        return ({date_weather_clock_size=145, date_weather_hover_temp_size=82,
                 date_weather_icon_size=72, date_weather_icon_dx=0,
                 date_weather_icon_dy=0})[key] or 0
    end,
}
local calls = {}
local fake_notify = {
    crossed = Notify.crossed,
    send_once = function(key, title, message, time)
        calls[#calls+1] = {key=key, title=title, message=message, ts=time}
        return true
    end,
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
os.time = function(parts) if parts then return real_time(parts) end return now end
_G.conky_window = {width=1400,height=350}
local function at(y,m,d,h,minute,sec)
    return real_time{year=y,month=m,day=d,hour=h,min=minute,sec=sec or 0}
end
local function timestamp(y,m,d,h,minute)
    return at(y,m,d,h,minute,0)
end
local function choose_date(t)
    current_day=Prayer_Data.shift_date(t,0)
    next_day=Prayer_Data.shift_date(t,1)
end
local function run_prayer(before, after, expected, title)
    calls={}; choose_date(before)
    assert(loadfile(root .. 'widgets/Prayer_Times.lua'))()
    now=before; conky_main()
    assert(#calls == 0, 'no notification at initialization')
    now=after; conky_main()
    assert(#calls == expected, 'unexpected reminder count ' .. #calls .. ' expected ' .. expected)
    if title then assert(calls[1].title == title, calls[1].title) end
    conky_main(); assert(#calls == expected, 'no duplicate on same instant')
    return calls
end

-- All five daily prayer thresholds, not only Asr.
for _, item in ipairs({
    {4,45,'Fajr'}, {11,45,'Dhuhr'}, {14,45,'Asr'},
    {17,0,'Maghrib'}, {18,30,'Isha'},
}) do
    local due=timestamp(2026,11,23,item[1],item[2])
    run_prayer(due-1,due,1,item[3] .. ' in 15 minutes')
end
local monday=timestamp(2026,11,23,14,44)
local sent=run_prayer(monday+59, monday+60, 1, 'Asr in 15 minutes')
assert(sent[1].key:find(':Asr:15m$', 1, false))
run_prayer(timestamp(2026,11,23,14,50), timestamp(2026,11,23,14,50)+1, 0)
run_prayer(timestamp(2026,11,23,14,45)+10, timestamp(2026,11,23,14,45)+11, 0)
run_prayer(timestamp(2026,11,23,14,44), timestamp(2026,11,23,14,47), 0)
run_prayer(timestamp(2026,11,23,6,14)+59, timestamp(2026,11,23,6,15), 1,
           'Sunrise in 15 minutes — Fajr ends soon')
run_prayer(timestamp(2026,11,24,0,14)+59, timestamp(2026,11,24,0,15), 1,
           'Midnight in 15 minutes')
run_prayer(timestamp(2026,11,27,11,44)+59, timestamp(2026,11,27,11,45), 1,
           "Jumu'ah in 15 minutes")

local function run_date(month, day, before, after, expected)
    calls={}; captured={}
    today_hijri={day='12',month={number=month},year='1448'}
    next_hijri={day=tostring(day),month={number=month},year='1448'}
    choose_date(before)
    assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
    now=before; conky_main(); assert(#calls == 0)
    now=after; conky_main()
    assert(#calls == expected, 'unexpected fasting notifications: ' .. #calls)
    if expected == 1 then
        assert(calls[1].title == string.format('Tomorrow is %d of %s', day,
            month == 7 and 'Rajab' or 'Shaban'))
        assert(calls[1].key:find(':fast$',1,false))
    end
    -- Day 12 is red, days 13-15 share the prayer accent, Ramadan stays white.
    local found
    for _, text in ipairs(captured) do
        if text.text == string.format('%02d', day) then found=text.color end
    end
    assert(found, 'hijri day was not rendered')
    if month == 9 then
        assert(found[1] == 1 and found[2] == 1 and found[3] == 1,
            'Ramadan days 12-15 must remain white')
    elseif day == 12 then
        assert(math.abs(found[1] - 200/255) < .00001 and
               math.abs(found[2] - 55/255) < .00001,
               'only day 12 should be red')
    else
        local hex = accent_override or '#efb46f'
        local r = tonumber(hex:sub(2, 3), 16) / 255
        local g = tonumber(hex:sub(4, 5), 16) / 255
        local b = tonumber(hex:sub(6, 7), 16) / 255
        assert(math.abs(found[1] - r) < .00001 and
               math.abs(found[2] - g) < .00001 and
               math.abs(found[3] - b) < .00001,
            'days 13-15 must use configured prayer accent ' .. hex)
    end
    conky_main(); assert(#calls == expected, 'fasting reminder duplicate')
end
for _, day in ipairs({13,14,15}) do
    run_date(7, day, timestamp(2026,11,23,17,14)+59,
        timestamp(2026,11,23,17,15), 1)
    run_date(9, day, timestamp(2026,11,23,17,14)+59,
        timestamp(2026,11,23,17,15), 0)
end
run_date(9,12,timestamp(2026,11,23,17,14)+59,
    timestamp(2026,11,23,17,15),0)
run_date(7,12,timestamp(2026,11,23,17,14)+59,
    timestamp(2026,11,23,17,15),0)
run_date(7,13,timestamp(2026,11,23,17,30),
    timestamp(2026,11,23,17,30)+1,0)
-- A non-default configured accent must change the date without code changes.
accent_override = '#1296a5'
run_date(7,14,timestamp(2026,11,23,17,14)+59,
    timestamp(2026,11,23,17,15),1)
accent_override = nil
print('Task 7: prayer threshold/reminder labels, restart/wake guard, three White Days and Ramadan suppression passed')
