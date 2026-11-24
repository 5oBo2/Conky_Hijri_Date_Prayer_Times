-- Today's five prayers on dial/bar: click to toggle overlay, golden windows
-- always present, and last-third magenta arc from Lastthird until Fajr.
-- Run: texlua tests/test_astrolabe_markers.lua
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './tests/'
local root = base .. '../'
local real_dofile, real_time = dofile, os.time
_G.conky = {}
real_dofile(root .. 'configs/conky_sun_moon.conf')
assert(conky.config.lua_mouse_hook == 'on_mouse', 'Astrolabe mouse hook missing')
assert(conky.config.update_interval == 0.25, 'Astrolabe refresh should be responsive')
assert(conky.config.double_buffer and conky.config.out_to_x and
       not conky.config.out_to_wayland, 'keep verified XWayland renderer')
local Markers = real_dofile(root .. 'lib/Astrolabe_Prayer_Markers.lua')
local prayer = real_dofile(root .. 'lib/Prayer_Data.lua')
local times = {Fajr='05:00', Sunrise='06:30', Dhuhr='12:00', Asr='15:00',
    Maghrib='17:15', Isha='18:45', Lastthird='02:15'}
local yesterday = {timings={Fajr='05:01', Sunrise='06:31', Dhuhr='12:01',
    Asr='15:01', Maghrib='17:10', Isha='18:41', Lastthird='02:12'}}
local today = {timings=times}
local tomorrow = {timings={Fajr='05:08', Sunrise='06:32', Dhuhr='12:03',
    Asr='15:03', Maghrib='17:14', Isha='18:47', Lastthird='02:21'}}
local lookup = {
    ['2026-11-22'] = yesterday,
    ['2026-11-23'] = today,
    ['2026-11-24'] = tomorrow,
}
prayer.get = function(date) return lookup[date] end
prayer.ensure_dates = function() end
local function ts(date, s) return prayer.timestamp(date, s) end
local schedule = {
    yesterday_sunset_ts = ts('2026-11-22', '17:10'),
    sunrise_ts = ts('2026-11-23', '06:30'),
    sunset_ts = ts('2026-11-23', '17:15'),
    tomorrow_sunrise_ts = ts('2026-11-24', '06:32'),
}
local function near(a,b) return math.abs(a-b) < 0.0000001 end
local names = {'Fajr','Dhuhr','Asr','Maghrib','Isha'}
local function assert_markers(markers)
    assert(markers and #markers == 5, 'exactly five markers required')
    for i, name in ipairs(names) do
        local m = markers[i]
        assert(m.name == name, 'marker order')
        assert(m.bar_ts == ts('2026-11-23', times[name]), 'bar must use TODAY')
        assert(near(m.bar_fraction, prayer.minutes(times[name]) / 1440), 'bar mapping')
        assert(m.angle >= 0 and m.angle <= 2 * math.pi, 'dial angle bounds')
    end
    assert(markers[2].angle > math.pi and markers[2].angle < 2 * math.pi)
    assert(markers[3].angle > markers[2].angle and markers[3].angle < 2 * math.pi)
end
local before = ts('2026-11-23', '04:00')
local afternoon = ts('2026-11-23', '14:00')
local night = ts('2026-11-23', '20:00')
local early = Markers.build(before, schedule, prayer)
assert_markers(early)
assert(early[1].dial_ts == ts('2026-11-23', '05:00'))
assert(early[4].dial_ts == ts('2026-11-22', '17:10'))
assert(early[5].dial_ts == ts('2026-11-22', '18:41'))
assert(near(early[4].angle, 0), 'last-night Maghrib begins night arc')
assert(early[1].angle < math.pi and early[5].angle < early[1].angle)
local after = Markers.build(afternoon, schedule, prayer)
assert_markers(after)
assert(after[1].dial_ts == ts('2026-11-24', '05:08'))
assert(after[4].dial_ts == ts('2026-11-23', '17:15'))
assert(after[5].dial_ts == ts('2026-11-23', '18:45'))
assert(near(after[4].angle, 0))
assert(after[5].angle < after[1].angle and after[1].angle < math.pi)
assert(after.last_third.start_ts == ts('2026-11-24', '02:15'),
    "after sunrise must use today's Lastthird on next civil date")
assert(after.last_third.end_ts == ts('2026-11-24', '05:08'),
    'following Fajr ends tahajjud window, never sunrise')
assert(after.last_third.start_angle > 0 and
       after.last_third.end_angle > after.last_third.start_angle and
       after.last_third.end_angle < math.pi)
local windows = Markers.golden_windows(schedule, 0.05 * 86400)
assert(#windows == 2)
assert(near(windows[1].start_angle, math.pi))
assert(near(windows[1].end_angle, math.pi + math.pi * 4320 /
       (schedule.sunset_ts - schedule.sunrise_ts)))
assert(near(windows[2].end_angle, 2 * math.pi))
assert(near(windows[2].start_angle, 3 * math.pi - windows[1].end_angle))
assert(not Markers.golden_windows(nil, 4320))
assert_markers(Markers.build(night, schedule, prayer))
assert(not Markers.build(afternoon, nil, prayer))
lookup['2026-11-24'] = nil
assert(not Markers.build(afternoon, schedule, prayer), 'missing tomorrow: no partial dial')
assert_markers(Markers.build(before, schedule, prayer))
lookup['2026-11-24'] = tomorrow
lookup['2026-11-22'] = nil
assert(not Markers.build(before, schedule, prayer), 'missing yesterday: no partial dial')
lookup['2026-11-22'] = yesterday
local broken = {}
for k,v in pairs(schedule) do broken[k]=v end
broken.sunset_ts = broken.sunrise_ts
assert(not Markers.build(afternoon, broken, prayer), 'invalid daylight interval')

-- Render with mock Cairo: no reveal on hover, left-click toggles persistently,
-- both golden arcs always visible, magenta arc only when prayer overlay is on.
package.preload.cairo = function() return true end
local function noop() end
local cfuncs = {
 'cairo_set_source_rgba','cairo_arc','cairo_fill','cairo_new_sub_path',
 'cairo_line_to','cairo_close_path','cairo_set_line_width','cairo_stroke',
 'cairo_select_font_face','cairo_set_font_size','cairo_move_to','cairo_save',
 'cairo_restore','cairo_clip','cairo_pattern_add_color_stop_rgba',
 'cairo_set_source','cairo_pattern_destroy','cairo_set_antialias',
 'cairo_scale','cairo_translate','cairo_destroy','cairo_rectangle',
}
for _, name in ipairs(cfuncs) do _G[name] = noop end
local arcs, strokes = {}, {}
local active_arc, active_color
_G.cairo_set_source_rgba = function(_, r, g, b, alpha)
    active_color = {r, g, b, alpha}
end
_G.cairo_stroke = function()
    if active_arc then
        strokes[#strokes + 1] = {arc = active_arc, color = active_color}
    end
    active_arc = nil
end
_G.cairo_move_to = function() active_arc = nil end
_G.cairo_line_to = function() active_arc = nil end
_G.cairo_fill = function() active_arc = nil end
_G.cairo_arc = function(_, _, _, radius, start_angle, end_angle)
    active_arc = {r = radius, a = start_angle, b = end_angle}
    arcs[#arcs + 1] = active_arc
end
_G.cairo_create = function() return {} end
_G.cairo_pattern_create_linear = function() return {} end
_G.cairo_pattern_create_radial = function() return {} end
_G.CAIRO_FONT_SLANT_NORMAL = 0
_G.CAIRO_FONT_WEIGHT_NORMAL = 0
_G.CAIRO_FONT_WEIGHT_BOLD = 1
_G.CAIRO_ANTIALIAS_BEST = 0
_G.cairo_text_extents_t = {create = function() return {} end}
_G.cairo_text_extents = function(_, s, ext) ext.x_advance = #s * 5 end
local rendered = {}
_G.cairo_show_text = function(_, s) rendered[#rendered+1] = s end
local function marker_labels_at_end()
    if #rendered < 10 then return 0 end
    local expected = {'F','D','A','M','I','F','D','A','M','I'}
    for i,name in ipairs(expected) do
        if rendered[#rendered - 10 + i] ~= name then return 0 end
    end
    return 10
end
local now = afternoon
os.time = function(tbl)
    if tbl then return real_time(tbl) end
    return now
end
local render_scale = 1.5
local fake_settings = {
    scale = function() return render_scale end,
    get = function(_,_,fallback) return fallback end,
    number = function(_, key, fallback)
        if key == 'hover_failsafe_seconds' then return 0 end
        return fallback
    end,
}
local fake_weather = {get = function() return {
    local_date = '2026-11-23',
    yesterday_sunset=schedule.yesterday_sunset_ts,
    sunrise=schedule.sunrise_ts, sunset=schedule.sunset_ts,
    tomorrow_sunrise=schedule.tomorrow_sunrise_ts,
    sunrise_label='06:30', sunset_label='17:15',
} end}
local fake_surface = {acquire=function() return {} end, release=noop}
_G.dofile = function(path)
    if path:match('lib/Surface%.lua$') then return fake_surface end
    if path:match('lib/Weather_Data%.lua$') then return fake_weather end
    if path:match('lib/Prayer_Data%.lua$') then return prayer end
    if path:match('lib/Settings%.lua$') then return fake_settings end
    return real_dofile(path)
end
_G.conky_window={width=624,height=648}
real_dofile(root .. 'widgets/Sun_Moon_Astrolabe.lua')
local function frame()
    rendered = {}
    arcs = {}
    strokes = {}
    active_arc = nil
    active_color = nil
    conky_main()
    return marker_labels_at_end()
end
local function count_arcs(radius, a, b)
    local found = 0
    for _, arc in ipairs(arcs) do
        if near(arc.r, radius) and
           (not a or (near(arc.a, a) and near(arc.b, b))) then
            found = found + 1
        end
    end
    return found
end
local function assert_overlay_opacity(radius, start_angle, end_angle, main_opacity, glow_opacity)
    local alpha_values = {}
    for _, s in ipairs(strokes) do
        if s.arc and s.color and near(s.arc.r, radius) and
            near(s.arc.a, start_angle) and near(s.arc.b, end_angle) then
            alpha_values[#alpha_values + 1] = s.color[4]
        end
    end
    assert(#alpha_values == 2, 'overlay needs a translucent main stroke and glow')
    assert(near(alpha_values[1], glow_opacity), 'soft glow alpha must scale with opacity setting')
    assert(near(alpha_values[2], main_opacity), 'main stroke alpha must match opacity setting')
end
assert(frame()==0, 'idle must not draw prayer labels')
for _, window in ipairs(windows) do
    assert(count_arcs(104, window.start_angle, window.end_angle) == 2,
        'golden band must overlay the daylight dial track, not an inset ring')
    assert_overlay_opacity(104, window.start_angle, window.end_angle, 0.60, 0.60 * 0.17)
end
assert(count_arcs(92) == 0, 'golden bands must not render on an inset ring')
assert(count_arcs(91) == 0, 'last third must be hidden while idle')
-- After scaling 1.5, dial center is (190+18,166+18)*1.5.
assert(conky_on_mouse({type='mouse_enter',x=312,y=276}) == false)
assert(conky_on_mouse({type='mouse_move',x=312,y=276}) == false)
assert(frame()==0, 'hover must NOT reveal prayer labels')
assert(conky_on_mouse({type='button_down',button='right',x=312,y=276}) == false)
assert(conky_on_mouse({type='button_up',button='left',x=312,y=276}) == false)
assert(conky_on_mouse({type='button_down',button='left',x=4,y=4}) == false)
assert(frame()==0, 'right clicks, button_up and outside clicks do not toggle')
assert(conky_on_mouse({type='button_down',button='left',x=312,y=276}) == true)
assert(frame()==10, 'left click on dial shows dial and bar prayer markers')
assert(count_arcs(104, after.last_third.start_angle, after.last_third.end_angle) == 2,
    'last third must overlay the dial track and end at NEXT Fajr')
assert_overlay_opacity(104, after.last_third.start_angle, after.last_third.end_angle,
    0.60, 0.60 * 0.15)
assert(count_arcs(91) == 0, 'last third must not render on an inset ring')
for _, window in ipairs(windows) do
    assert(count_arcs(104, window.start_angle, window.end_angle) == 2,
        'golden windows remain aligned with dial when prayers shown')
end
-- Moving outside and leaving must not clear a click-toggle.
conky_on_mouse({type='mouse_move',x=10,y=10})
conky_on_mouse({type='mouse_leave'})
now = now + 100
assert(frame()==10, 'click toggled overlay must persist across leave and time')
-- Timeline y=(352+18)*1.5, and x=(28+18)*1.5.
assert(conky_on_mouse({type='button_down',button='left',x=200,y=555}) == true)
assert(frame()==0, 'left click on bar hides both prayer and last-third overlays')
assert(count_arcs(104, after.last_third.start_angle, after.last_third.end_angle) == 0,
    'last third disappears when prayer overlay is off')
-- Hitboxes must use real Conky window coordinates at all common scales.
for _, scale in ipairs({0.65, 1, 1.5}) do
    render_scale = scale
    _G.conky_window = {width=math.ceil(416*scale), height=math.ceil(432*scale)}
    real_dofile(root .. 'widgets/Sun_Moon_Astrolabe.lua')
    assert(frame()==0)
    conky_on_mouse({type='mouse_move',x=208*scale,y=184*scale})
    assert(frame()==0, 'hover must not toggle on scale ' .. scale)
    assert(conky_on_mouse({type='button_down',button='left',x=208*scale,y=184*scale}))
    assert(frame()==10, 'dial click zone scale ' .. scale)
    assert(conky_on_mouse({type='button_down',button='left',x=200*scale,y=370*scale}))
    assert(frame()==0, 'bar click zone scale ' .. scale)
    assert(not conky_on_mouse({type='button_down',button='left',x=2,y=2}))
    assert(frame()==0, 'outside scaled hitboxes ' .. scale)
end
-- Missing tomorrow cache suppresses incomplete overlay, keeps golden bands.
lookup['2026-11-24'] = nil
assert(conky_on_mouse({type='button_down',button='left',x=208*render_scale,y=184*render_scale}))
assert(frame()==0, 'missing dates suppress incomplete prayer overlay')
for _, window in ipairs(windows) do
    assert(count_arcs(104, window.start_angle, window.end_angle) == 2,
        'golden windows remain independent of prayer cache')
end
os.time = real_time
_G.dofile = real_dofile
print('PASS: click-only toggle, in-track golden bands and last-third overlay, scales, missing data')
