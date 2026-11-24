-- Task 5: test the real Prayer widget draw path with deterministic dates,
-- Cairo text/color captures, and non-blocking cached schedule data.
-- Run: texlua tests/test_next_prayer.lua
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './tests/'
local root = base .. '../'
local real_dofile, real_time = dofile, os.time
local data = real_dofile(root .. 'lib/Prayer_Data.lua')
local times = {
    Fajr = '05:00', Sunrise = '06:30', Dhuhr = '12:00', Asr = '15:00',
    Maghrib = '17:15', Isha = '18:45', Midnight = '00:30', Lastthird = '02:15',
}
local day = {timings = times}
local friday_times = {}
for k, v in pairs(times) do friday_times[k] = v end
friday_times.Dhuhr = '12:07'  -- prove Thu evening displays Friday's time
local friday = {timings = friday_times}
local friday_missing = false
data.get = function(date)
    if date == '2026-11-27' then
        return not friday_missing and friday or nil
    end
    return day
end
data.ensure_dates = function() end
package.preload.cairo = function() return true end
_G.CAIRO_FONT_SLANT_NORMAL = 0
_G.CAIRO_FONT_WEIGHT_NORMAL = 0
_G.cairo_text_extents_t = {create = function() return {} end}
local noop = function() end
for _, name in ipairs({'cairo_select_font_face', 'cairo_move_to',
        'cairo_destroy', 'cairo_set_line_width', 'cairo_stroke'}) do
    _G[name] = noop
end
_G.cairo_create = function() return {_font = 20, _color = {1, 1, 1, 1}} end
_G.cairo_set_font_size = function(cr, size) cr._font = size end
_G.cairo_set_source_rgba = function(cr, r, g, b, a)
    cr._color = {r, g, b, a}
end
local dots = {}
_G.cairo_arc = function(cr, x, y, radius)
    cr._arc = {x = x, y = y, radius = radius}
end
_G.cairo_fill = function(cr)
    assert(cr._arc, 'dot fill requires an arc, not a sideline')
    dots[#dots + 1] = {x = cr._arc.x, y = cr._arc.y,
        radius = cr._arc.radius, color = cr._color}
    cr._arc = nil
end
local glyph_factor = 0.48 -- deterministic approximation for layout assertions
_G.cairo_text_extents = function(cr, s, ext)
    ext.x_advance = #tostring(s) * cr._font * glyph_factor
end
_G.cairo_move_to = function(cr, x, y) cr._x, cr._y = x, y end
local drawn = {}
_G.cairo_show_text = function(cr, value)
    drawn[#drawn + 1] = {label = tostring(value), x = cr._x, y = cr._y,
                         font = cr._font, color = cr._color}
end
local fake_surface = {acquire = function() return {} end, release = function() end}
local scale = 1
local accent_override
local fake_settings = {
    scale = function() return scale end,
    get = function(_, key, fallback)
        if key == 'next_prayer_color' then return accent_override or fallback end
        return fallback
    end,
    boolean = function(_, _, fallback) return fallback == true and false or fallback end,
    number = function(_, _, fallback) return fallback end,
}
_G.dofile = function(path)
    if path:match('lib/Surface%.lua$') then return fake_surface end
    if path:match('lib/Prayer_Data%.lua$') then return data end
    if path:match('lib/Settings%.lua$') then return fake_settings end
    return real_dofile(path)
end
local function timestamp(y, m, d, h, mi)
    return real_time{year = y, month = m, day = d, hour = h, min = mi or 0, sec = 0}
end
local now
os.time = function(parts)
    if parts then return real_time(parts) end
    return now
end
local function entry(value)
    for _, item in ipairs(drawn) do
        if item.label == value then return item end
    end
    return nil
end
local function expect(value)
    return assert(entry(value), 'missing text: ' .. value)
end
local function assert_color(color, r, g, b, a, description)
    for i, expected in ipairs({r, g, b, a}) do
        assert(math.abs(color[i] - expected) < 0.00001,
            string.format('%s channel %d = %.4f (expected %.4f)',
                description, i, color[i], expected))
    end
end
local function white(value)
    assert_color(expect(value).color, 1, 1, 1, 200 / 255, value)
end
local function gold(value)
    assert_color(expect(value).color, 239 / 255, 180 / 255,
                 111 / 255, 1, value)
end
local function marker(column_label, time_text)
    assert(#dots == 2, 'expected one halo and one filled dot')
    local dot = dots[2]
    assert(math.abs(dot.radius - 3.5 * scale) < 0.00001,
        'dot radius must scale with prayer_scale')
    assert(dot.x >= 0 and dot.x <= conky_window.width)
    assert(dot.y >= 0 and dot.y <= conky_window.height)
    local name = expect(column_label)
    local clock = expect(time_text)
    -- Both ends of the same time: label starts at the clock's left edge;
    -- dot sits a small inset from its right edge, not after the label.
    assert(math.abs(name.x - clock.x) < 0.00001,
           'highlight label must start at the left edge of its clock')
    local clock_right = clock.x + #clock.label * clock.font * glyph_factor
    assert(math.abs(dot.x - (clock_right - 5 * scale)) < 0.00001,
           'dot must be inset 5 scaled pixels from the prayer time right edge')
    local label_right = name.x + #name.label * name.font * glyph_factor
    assert(dot.x - label_right > 20 * scale,
           'marker must be far from the label, not just after its text')
    assert(math.abs(dot.y - (name.y - name.font * 0.5)) < 0.00001,
           'dot center must share the header line, above the clock')
    assert_color(dot.color, 239 / 255, 180 / 255, 111 / 255,
                 1, 'marker dot')
end
local function assert_row_fits()
    local left = math.huge
    local right = -math.huge
    for _, name in ipairs({'Fajr', 'Sunrise', "Jumu'ah", 'Asr', 'Maghrib',
                            'Isha', 'Midnight'}) do
        local item = entry(name)
        if item then
            left = math.min(left, item.x)
            right = math.max(right, item.x + #name * item.font * glyph_factor)
        end
    end
    assert(left >= 0, 'heading clipped on left')
    assert(right <= conky_window.width, 'heading clipped on right')
    local dhuhr = expect("Jumu'ah")
    local asr = expect('Asr')
    assert(dhuhr.x + #dhuhr.label * dhuhr.font * glyph_factor < asr.x,
           'Jumu\'ah overlaps Asr')
end
local function run_at(y, m, d, h, mi)
    now = timestamp(y, m, d, h, mi)
    drawn = {}
    dots = {}
    conky_main()
end
-- Run all three scales, including Maghrib boundary and next-day Dhuhr
-- times that differ from the civil day's cached time.
for _, s in ipairs({0.65, 1, 1.5}) do
    scale = s
    _G.conky_window = {width = 1111 * s, height = 265 * s}
    assert(loadfile(root .. 'widgets/Prayer_Times.lua'))()

    -- Thursday before Maghrib: no Jumu'ah and the original (unaccented)
    -- times/other labels remain the same white as before Task 5.
    run_at(2026, 11, 26, 11, 30)
    expect('Dhuhr')
    expect('Till Dhuhr')
    assert(not entry("Jumu'ah"))
    gold('Dhuhr')
    white('Fajr')
    white('Asr')
    white('12:00') -- no brightened time, even for the next prayer
    marker('Dhuhr', '12:00')

    -- Regression for the screenshot: after Dhuhr, the countdown reads
    -- 'Till Asr'. Therefore Asr (not Dhuhr) owns the gold label and dot.
    run_at(2026, 11, 26, 12, 30)
    expect('Till Asr')
    white('Dhuhr')
    gold('Asr')
    marker('Asr', '15:00')

    -- Before Thursday Maghrib, Thursday's Dhuhr is still Dhuhr.
    run_at(2026, 11, 26, 17, 14)
    expect('Dhuhr')
    assert(not entry("Jumu'ah"))
    white('12:00')
    white('Asr')
    gold('Maghrib')
    marker('Maghrib', '17:15')

    -- At the exact Maghrib boundary, the Islamic display day becomes
    -- Friday. Use Friday's cached Dhuhr time (12:07) in the third column,
    -- while Thursday's Isha remains today's time (18:45).
    run_at(2026, 11, 26, 17, 15)
    expect("Jumu'ah")
    expect('12:07')
    assert(not entry('Dhuhr') and not entry('12:00'))
    white("Jumu'ah")
    white('12:07')
    white('18:45')
    gold('Isha')
    marker('Isha', '18:45')
    assert_row_fits()

    -- Thursday evening and Friday early morning continue displaying
    -- Jumu'ah, including with tomorrow's Fajr highlighted.
    run_at(2026, 11, 26, 23, 0)
    expect("Jumu'ah")
    expect('12:07')
    gold('Fajr')
    white('05:00')
    marker('Fajr', '05:00')
    run_at(2026, 11, 27, 0, 1)
    expect("Jumu'ah")
    expect('12:07')

    -- Friday's upcoming Dhuhr uses event-date naming in the countdown.
    run_at(2026, 11, 27, 11, 30)
    expect("Jumu'ah")
    expect('Till Jumu\'ah')
    assert(not entry('Dhuhr') and not entry('Till Dhuhr'))
    gold("Jumu'ah")
    white('12:07')
    white('Fajr')
    white('Asr')
    marker("Jumu'ah", '12:07')
    assert_row_fits()

    run_at(2026, 11, 27, 12, 30)
    expect('Since Jumu\'ah')
    white("Jumu'ah")
    gold('Asr')
    white('12:07')
    marker('Asr', '15:00')
    assert_row_fits()

    -- Friday Maghrib starts Saturday: Jumu'ah must revert to Dhuhr
    -- immediately, while Saturday Dhuhr time is from Saturday's cache.
    run_at(2026, 11, 27, 17, 14)
    expect("Jumu'ah")
    run_at(2026, 11, 27, 17, 15)
    expect('Dhuhr')
    expect('12:00')
    assert(not entry("Jumu'ah"))
    gold('Isha')
    marker('Isha', '18:45')

    -- The original seventh-column toggle remains intact.
    run_at(2026, 11, 28, 11, 30)
    expect('Dhuhr')
    local hover
    for i = 1, 30 do
        local name, val = debug.getupvalue(conky_on_mouse, i)
        if name == 'hover' then hover = val; break end
    end
    local r = assert(hover and hover.zones.midnight_column[1])
    assert(conky_on_mouse({type = 'button_down', button = 'left',
                           x = (r[1] + r[3]) / 2, y = (r[2] + r[4]) / 2}))
    run_at(2026, 11, 28, 11, 30)
    expect('Last 3rd')
    expect('02:15')
    assert(not entry('Midnight'))

    -- Missing tomorrow cache: never mislabel Thursday's Dhuhr time as
    -- Friday's. Fetch proceeds asynchronously and row uses a placeholder.
    friday_missing = true
    run_at(2026, 11, 26, 17, 15)
    expect("Jumu'ah")
    expect('--:--')
    assert(not entry('12:00'))
    friday_missing = false
end

-- Click only the marker to mute, click again to unmute, then advance to
-- another prayer; the next event must default to the configured accent.
scale = 1
conky_window = {width = 1111, height = 265}
assert(loadfile(root .. 'widgets/Prayer_Times.lua'))()
run_at(2026, 11, 26, 17, 14)
local active_hover
for i = 1, 40 do
    local name, value = debug.getupvalue(conky_on_mouse, i)
    if name == 'hover' then active_hover = value; break end
end
local box = assert(active_hover.zones.next_prayer_athan_dot)[1]
local dx, dy = (box[1] + box[3]) / 2, (box[2] + box[4]) / 2
assert(conky_on_mouse({type='button_down', button='left', x=dx, y=dy}))
run_at(2026, 11, 26, 17, 14)
assert_color(dots[2].color, 200/255, 55/255, 55/255, 200/255, 'muted dot')
gold('Maghrib') -- the upcoming label never changes on mute
assert(conky_on_mouse({type='button_down', button='left', x=dx, y=dy}))
run_at(2026, 11, 26, 17, 14)
marker('Maghrib', '17:15')
assert(conky_on_mouse({type='button_down', button='left', x=dx, y=dy}))
run_at(2026, 11, 26, 17, 15)
marker('Isha', '18:45') -- muting Maghrib must not carry over

-- A custom hex color is picked up when Conky reloads the widget.
accent_override = '#123abc'
scale = 1
conky_window = {width = 1111, height = 265}
assert(loadfile(root .. 'widgets/Prayer_Times.lua'))()
run_at(2026, 11, 27, 11, 30)
assert_color(expect("Jumu'ah").color, 0x12 / 255, 0x3a / 255,
             0xbc / 255, 1, 'custom upcoming-prayer label')
assert_color(dots[2].color, 0x12 / 255, 0x3a / 255,
             0xbc / 255, 1, 'custom marker')
white('12:07')

accent_override = 'not-a-color'
local ok, err = pcall(function()
    assert(loadfile(root .. 'widgets/Prayer_Times.lua'))()
end)
assert(not ok and tostring(err):match('appearance%.next_prayer_color'),
       'invalid accent must fail with a clear setting name')
_G.dofile = real_dofile
os.time = real_time
print('Option 05 dot and Islamic-day boundary verified')
