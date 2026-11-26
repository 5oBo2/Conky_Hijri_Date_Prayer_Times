-- Task 6: execute the real Prayer drawing/mouse hooks against deterministic
-- cached data and an instrumented Cairo surface. No KDE session needed.
-- Run: texlua tests/test_prayer_hover.lua
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './tests/'
local root = base .. '../'
local real_dofile, real_time = dofile, os.time
local data = real_dofile(root .. 'lib/Prayer_Data.lua')
local times = {
    Fajr = '05:00', Sunrise = '06:30', Dhuhr = '12:00', Asr = '15:00',
    Maghrib = '17:15', Isha = '18:45', Midnight = '00:30', Lastthird = '02:15',
}
local friday_times = {}
for k, v in pairs(times) do friday_times[k] = v end
friday_times.Dhuhr = '12:07'
local available = {}
data.get = function(date)
    if available[date] == false then return nil end
    return {timings = date == '2026-11-27' and friday_times or times}
end
data.ensure_dates = function() end
package.preload.cairo = function() return true end
_G.CAIRO_FONT_SLANT_NORMAL = 0
_G.CAIRO_FONT_WEIGHT_NORMAL = 0
_G.cairo_text_extents_t = {create = function() return {} end}
local noop = function() end
for _, name in ipairs({'cairo_select_font_face', 'cairo_move_to',
        'cairo_destroy', 'cairo_set_line_width', 'cairo_stroke',
        'cairo_arc', 'cairo_rectangle', 'cairo_fill'}) do _G[name] = noop end
_G.cairo_create = function() return {font = 20, color = {1,1,1,1}} end
_G.cairo_set_font_size = function(cr, size) cr.font = size end
_G.cairo_set_source_rgba = function(cr, r, g, b, a) cr.color = {r,g,b,a} end
_G.cairo_text_extents = function(cr, str, extent)
    extent.x_advance = #tostring(str) * cr.font * 0.48
end
_G.cairo_move_to = function(cr, x, y) cr.x, cr.y = x, y end
local drawn = {}
_G.cairo_show_text = function(cr, str)
    drawn[#drawn + 1] = {label = tostring(str), x = cr.x, y = cr.y,
                         font = cr.font, color = cr.color}
end
local stub_surface = {acquire = function() return {} end,
                      release = function() end}
local scale = 1
local fake_settings = {
    scale = function() return scale end,
    get = function(_, _, fallback) return fallback end,
    number = function(_, key, fallback)
        if key == 'hover_failsafe_seconds' then return 0 end
        return fallback
    end,
    boolean = function(section, key, fallback)
        return key == 'athan_enabled' and false or fallback
    end,
}
_G.dofile = function(path)
    if path:match('lib/Surface%.lua$') then return stub_surface end
    if path:match('lib/Prayer_Data%.lua$') then return data end
    if path:match('lib/Settings%.lua$') then return fake_settings end
    return real_dofile(path)
end
local now
os.time = function(parts)
    if parts then return real_time(parts) end
    return now
end
local function timestamp(y, m, d, h, min)
    return real_time{year=y, month=m, day=d, hour=h, min=min or 0, sec=0}
end
local function time_at(y, m, d, h, min)
    now = timestamp(y, m, d, h, min)
end
local function find_label(label)
    for _, item in ipairs(drawn) do
        if item.label == label then return item end
    end
end
local function expect(label)
    return assert(find_label(label), 'missing text: ' .. label)
end
local function absent(label)
    assert(not find_label(label), 'unexpected text: ' .. label)
end
local function assert_text_color(label, expected, description)
    local item = expect(label)
    assert(item.color, 'missing captured Cairo color for ' .. label)
    for i = 1, 4 do
        assert(math.abs(item.color[i] - expected[i]) < 0.00001,
            (description or label) .. ' has unexpected color channel ' .. i)
    end
end
local function draw()
    drawn = {}
    conky_main()
end
local function get_hover()
    for i = 1, 30 do
        local key, val = debug.getupvalue(conky_on_mouse, i)
        if key == 'hover' then return val end
    end
    error('no hover state found in mouse hook')
end
local function zone(i)
    local state = get_hover()
    return assert(state.zones['prayer_column_' .. i],
                  'missing column hover ' .. i)[1]
end
local function move_to(i)
    local z = zone(i)
    local x, y = (z[1] + z[3])/2, (z[2] + z[4])/2
    assert(conky_on_mouse({type='mouse_move', x=x, y=y}) == false)
end
local function no_hover()
    assert(conky_on_mouse({type='mouse_leave'}) == false)
end
local function ensure_third_column(first, second, third)
    local a, b, c = expect(first), expect(second), expect(third)
    local stride = zone(2)[1] - zone(1)[1]
    assert(math.abs((c.x - b.x) - stride) < 0.01, 'third countdown must occupy third column')
    assert(math.abs((b.x - a.x) - stride) < 0.01, 'second countdown must occupy second column')
    local glyph_width = #third * c.font * 0.48
    assert(c.x + glyph_width < conky_window.width, 'third-column label clipped')
end
for _, s in ipairs({0.65, 1, 1.2, 1.5}) do
    scale = s
    _G.conky_window = {width = 1111*s, height = 265*s}
    assert(loadfile(root .. 'widgets/Prayer_Times.lua'))()
    -- Hitboxes must be independent, disjoint, inside their window and scaled.
    time_at(2026, 11, 26, 13, 0) -- Asr next
    draw()
    for i = 1, 7 do
        local z = zone(i)
        assert(z[1] >= 0 and z[3] <= conky_window.width)
        assert(z[2] >= 0 and z[4] <= conky_window.height)
        if i > 1 then assert(zone(i-1)[3] < z[1], 'column hitboxes overlap') end
    end
    expect('Till Asr')
    move_to(6) -- Isha
    draw()
    expect('Till Asr')
    local second = expect('Till Isha')
    assert(math.abs((second.x - expect('Till Asr').x) -
           (zone(2)[1]-zone(1)[1])) < 0.01, 'hover uses column two')
    no_hover()
    draw()
    absent('Till Isha')
    move_to(4) -- upcoming Asr already visible
    draw()
    absent('Till Isha')
    assert(#drawn > 0)
    no_hover()

    -- Existing Fajr/Sunrise -> Sunrise second countdown remains untouched;
    -- selected Maghrib goes in the THIRD countdown column.
    time_at(2026, 11, 26, 5, 30)
    draw()
    move_to(5)
    draw()
    ensure_third_column('Till Dhuhr', 'Till Sunrise', 'Till Maghrib')
    no_hover()
    draw()
    move_to(2) -- extra already Sunrise: don't duplicate
    draw()
    assert(not find_label('Till Maghrib'))
    assert(#drawn > 0)
    no_hover()

    -- On Thursday night, hovered Dhuhr is Friday Jumu'ah using Friday's
    -- actual 12:07 event, not Thursday's already-past 12:00.
    time_at(2026, 11, 26, 20, 0)
    draw()
    move_to(3)
    draw()
    ensure_third_column('Till Fajr', 'Till Midnight', "Till Jumu'ah")
    no_hover()
    draw()
    move_to(7) -- displayed Midnight duplicates the extra; ignore
    draw()
    absent("Till Jumu'ah")
    no_hover()

    local z = zone(7)
    assert(conky_on_mouse({type='button_down', button='left',
        x=(z[1]+z[3])/2, y=(z[2]+z[4])/2}) == true)
    draw()
    expect('Last 3rd')
    move_to(7) -- now seventh column targets Lastthird, not Midnight
    draw()
    ensure_third_column('Till Fajr', 'Till Midnight', 'Till Last 3rd')
    no_hover()

    -- After midnight, the selected Lastthird belongs to *yesterday's*
    -- schedule: 02:15 of today's civil date (not tomorrow 02:15).
    time_at(2026, 11, 27, 1, 0)
    draw()
    move_to(7)
    draw()
    expect('Till Last 3rd')
    assert(find_label('01') and find_label('15'),
           'yesterday\'s Lastthird occurs in 1h15, not 25h15')
    no_hover()

    -- Last Third must keep its normal white countdown color even inside the
    -- final 15 minutes; ordinary prayer countdowns retain their red alert.
    time_at(2026, 11, 27, 2, 1) -- Lastthird 02:15: fourteen minutes away.
    draw()
    move_to(7)
    draw()
    expect('Till Last 3rd')
    assert_text_color('14', {1, 1, 1, 200/255},
        'Last Third final-15-minute countdown')
    no_hover()

    time_at(2026, 11, 26, 17, 2) -- Maghrib 17:15: thirteen minutes away.
    draw()
    expect('Till Maghrib')
    assert_text_color('13', {200/255, 55/255, 55/255, 200/255},
        'ordinary prayer final-15-minute alert')

    -- Next-day rollover for normal prayers; Saturday after Isha -> Sunday Dhuhr.
    time_at(2026, 11, 28, 20, 0)
    draw()
    move_to(3)
    draw()
    ensure_third_column('Till Fajr', 'Till Midnight', 'Till Dhuhr')
    no_hover()

    -- The elapsed-time trigger is ONLY above Fajr, not over Fajr's
    -- header/time, Sunrise, or the other prayer columns. The hitbox must
    -- remain inside the widget at every supported scale and never intersect
    -- the first prayer-column hitbox (even at its top/bottom boundaries).
    time_at(2026, 11, 28, 16, 30)
    draw()
    absent('Since Asr')
    local state = get_hover()
    local above = assert(state.zones.elapsed_above_fajr[1])
    assert(#state.zones.elapsed_above_fajr == 1)
    assert(above[1] >= 0 and above[3] <= conky_window.width)
    assert(above[2] >= 0 and above[4] < zone(1)[2])
    assert(above[3] < zone(2)[1], 'elapsed hover must not extend to Sunrise')
    -- The user-supplied reference box is a full prayer-column hitbox high,
    -- directly above Fajr, with a small gap and no overlap.
    local fajr = zone(1)
    local elapsed_height = above[4] - above[2]
    local fajr_height = fajr[4] - fajr[2]
    assert(math.abs(elapsed_height - fajr_height) < 0.01,
           'elapsed zone must have the height of a prayer label + time')
    assert(math.abs((fajr[2] - above[4]) - 3*s) < 0.01,
           'elapsed and Fajr zones must have a small, scaled gap')
    assert(above[1] <= fajr[1] and above[3] >= fajr[3] - 2*s,
           'elapsed box should cover approximately one full prayer column')
    local upper_x, upper_y = (above[1]+above[3])/2, (above[2]+above[4])/2
    assert(conky_on_mouse({type='mouse_move', x=upper_x, y=upper_y}) == false)
    draw()
    expect('Since Asr')
    -- With hover_failsafe_seconds = 0, stationary hover remains active.
    now = now + 5
    draw()
    expect('Since Asr')
    -- Actual column hover must not cause the unrelated elapsed timer.
    for i = 1, 7 do
        move_to(i)
        draw()
        absent('Since Asr')
    end
    -- A point directly to the right of the hotspot must not activate it.
    assert(conky_on_mouse({type='mouse_move',
        x=above[3]+2*s, y=upper_y}) == false)
    draw()
    absent('Since Asr')
    -- A point immediately below the hotspot must not activate it either.
    assert(conky_on_mouse({type='mouse_move',
        x=upper_x, y=above[4]+2*s}) == false)
    draw()
    absent('Since Asr')
    no_hover()
    draw()
    absent('Since Asr')

    -- If the selected date is not cached, do not show an incorrect countdown.
    available['2026-11-29'] = false
    time_at(2026, 11, 28, 20, 0)
    draw()
    move_to(3)
    draw()
    absent('Till Dhuhr')
    no_hover()
    available['2026-11-29'] = nil

    -- Missing *today* data removes the hitboxes rather than leaving stale
    -- interactive targets at their previous positions.
    available['2026-11-26'] = false
    time_at(2026, 11, 26, 13, 0)
    draw()
    assert(get_hover().zones.prayer_column_1 == nil)
    assert(get_hover().zones.prayer_column_7 == nil)
    available['2026-11-26'] = nil

    -- Zero failsafe is a deliberate live setting: stationary pointer
    -- stays active until it leaves the hitbox. Mouse leave clears it.
    time_at(2026, 11, 26, 13, 0)
    draw()
    move_to(6)
    draw()
    expect('Till Isha')
    now = now + 5
    draw()
    expect('Till Isha')
    no_hover()
    draw()
    absent('Till Isha')
end
_G.dofile, os.time = real_dofile, real_time
print('Task 6: seven hover zones, countdown positions, duplicates, rollover, Jumu\'ah and toggle passed')
