-- Traced Cairo weather glyphs: original WMO mapping and shared widget renderer.
-- Run: TZ=Africa/Cairo texlua tests/test_weather_icons.lua
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './tests/'
local root = base .. '../'
local Icons = dofile(root .. 'lib/Weather_Icons.lua')
local Shapes = dofile(root .. 'lib/Weather_Icon_Paths.lua')
local cases = {
    {0,32,31}, {1,34,33}, {2,30,29}, {3,26,26}, {45,20,20},
    {48,20,20}, {51,9,45}, {53,9,45}, {55,6,45}, {56,5,5},
    {57,5,5}, {61,9,45}, {63,6,45}, {65,6,45}, {66,5,5},
    {67,5,5}, {71,13,13}, {73,14,14}, {75,14,14}, {77,17,17},
    {80,9,45}, {81,6,45}, {82,6,45}, {85,41,46}, {86,14,46},
    {95,37,47}, {96,0,0}, {97,37,47}, {99,0,0}, {999,26,26},
}
for _, row in ipairs(cases) do
    assert(Icons.code(row[1], true) == row[2], 'day WMO ' .. row[1])
    assert(Icons.code(row[1], false) == row[3], 'night WMO ' .. row[1])
end

package.preload.cairo = function() return true end
local function noop() end
for _, fn in ipairs({
    'cairo_select_font_face', 'cairo_set_font_size', 'cairo_show_text',
    'cairo_destroy', 'cairo_set_line_width', 'cairo_stroke',
    'cairo_set_line_cap', 'cairo_set_line_join',
    'cairo_pattern_add_color_stop_rgba', 'cairo_set_source',
    'cairo_pattern_destroy', 'cairo_save', 'cairo_restore',
    'cairo_translate', 'cairo_scale', 'cairo_new_path',
    'cairo_set_fill_rule', 'cairo_move_to', 'cairo_line_to',
    'cairo_close_path', 'cairo_fill', 'cairo_curve_to',
    'cairo_arc', 'cairo_rectangle',
}) do _G[fn] = noop end
_G.CAIRO_FONT_SLANT_NORMAL = 0
_G.CAIRO_FONT_WEIGHT_NORMAL = 0
_G.CAIRO_FONT_WEIGHT_BOLD = 1
_G.CAIRO_FILL_RULE_EVEN_ODD = 1
_G.cairo_create = function() return {} end
_G.cairo_pattern_create_linear = function() return {} end
_G.cairo_text_extents_t = {create = function() return {} end}
_G.cairo_text_extents = function(_, value, ext)
    ext.x_advance = #tostring(value) * 14
    ext.x_bearing, ext.y_bearing = 0, -20
    ext.width, ext.height = ext.x_advance, 22
end
_G.cairo_image_surface_create_from_png = function()
    error('traced Cairo weather renderer must not load PNG assets')
end
_G.cairo_set_source_surface = function()
    error('traced Cairo weather renderer must not paint PNG surfaces')
end
_G.cairo_mask_surface = function()
    error('traced Cairo weather renderer must not use PNG alpha masks')
end
local fills, colors, scales, lines, closing, current_color = {}, {}, {}, 0, 0, nil
_G.cairo_set_source_rgba = function(_, r,g,b,a)
    current_color = {r,g,b,a}
    colors[#colors+1] = current_color
end
_G.cairo_fill = function()
    fills[#fills+1] = current_color
end
_G.cairo_scale = function(_,sx,sy) scales[#scales+1] = {sx,sy} end
_G.cairo_line_to = function() lines=lines+1 end
_G.cairo_close_path = function() closing=closing+1 end
_G.cairo_set_fill_rule = function(_,rule)
    assert(rule == CAIRO_FILL_RULE_EVEN_ODD,
        'contour holes and overlapping geometry need even-odd fill')
end
local function reset()
    fills,colors,scales,lines,closing,current_color={}, {}, {}, 0, 0, nil
end
local hex = dofile(root .. 'lib/Settings.lua').get(
    'appearance', 'next_prayer_color', '#efb46f')
local accent = {}
for c=1,3 do
    local k=2+(c-1)*2
    accent[c]=tonumber(hex:sub(k,k+1),16)/255
end
local function is_color(r,g,b)
    for _,c in ipairs(fills) do
        if math.abs(c[1]-r)<0.00001 and math.abs(c[2]-g)<0.00001
            and math.abs(c[3]-b)<0.00001 then return true end
    end
    return false
end
local function has_white() return is_color(1,1,1) end
local function has_accent()
    return is_color(accent[1],accent[2],accent[3])
end
local CELESTIAL = {[29]=true,[30]=true,[31]=true,[32]=true,
    [33]=true,[34]=true,[37]=true,[41]=true,[45]=true,
    [46]=true,[47]=true}
local FRONT_CLOUD = {[29]=true,[30]=true,[33]=true,[34]=true,
    [37]=true,[41]=true,[45]=true,[46]=true,[47]=true}
local REAR_CLOUD = {[30]=true,[37]=true,[41]=true,
    [45]=true,[46]=true,[47]=true}
local ALL = {0,5,6,9,13,14,17,20,26,29,30,31,32,33,34,37,41,45,46,47}
for _,id in ipairs(ALL) do
    assert(Shapes[id], 'every original weather icon must have a path: ' .. id)
    assert((Shapes[id].f ~= nil) == (FRONT_CLOUD[id] == true),
        'only the six approved layered icons have a foreground cloud pass: ' .. id)
    reset()
    Icons.draw({}, id, 1, 2, 80)
    assert(#fills >= 4 and lines > 5 and closing > 0,
        'icon ' .. id .. ' must render actual filled Cairo contours')
    assert(#scales==1 and math.abs(scales[1][1]-80/256)<0.000001,
        'source 256px coordinate system and requested icon size must match')
    if CELESTIAL[id] then
        assert(has_accent(), 'sun/moon must use configured accent: ' .. id)
        assert(has_white() == (id ~= 31 and id ~= 32),
            'compound celestial icons must keep white clouds: ' .. id)
    else
        assert(has_white() and not has_accent(),
            'non-celestial weather icons must remain neutral: ' .. id)
    end
end

-- The nine approved compound icons must be painted in source overlap order:
-- neutral/rear white, accent sun/moon, then foreground white cloud. The six
-- two-cloud icons require a white rear pass; 29/33/34 have one foreground cloud.
local function is_white_color(color)
    return math.abs(color[1]-1)<0.00001
        and math.abs(color[2]-1)<0.00001
        and math.abs(color[3]-1)<0.00001
end
local function is_accent_color(color)
    return math.abs(color[1]-accent[1])<0.00001
        and math.abs(color[2]-accent[2])<0.00001
        and math.abs(color[3]-accent[3])<0.00001
end
for id in pairs(FRONT_CLOUD) do
    reset()
    Icons.draw({}, id, 0, 0, 100)
    local first_accent, last_accent = nil, nil
    for i, color in ipairs(fills) do
        if is_accent_color(color) then
            first_accent = first_accent or i
            last_accent = i
        end
    end
    assert(first_accent and last_accent and last_accent < #fills,
        'celestial layer must precede the foreground white cloud pass: ' .. id)
    local white_before, white_after = false, false
    for i, color in ipairs(fills) do
        if is_white_color(color) and i < first_accent then white_before = true end
        if is_white_color(color) and i > last_accent then white_after = true end
    end
    assert(white_after,
        'foreground cloud must be drawn after the celestial layer: ' .. id)
    if REAR_CLOUD[id] then
        assert(white_before,
            'two-cloud icon must also draw its rear cloud before the celestial layer: ' .. id)
    end
end

-- The original 26.png outlines *two different overlapping clouds*. This is
-- a source-vector trace, not a reusable generic one-cloud spline.
assert(Shapes[26].n and #Shapes[26].n[5] >= 2,
    'overcast icon must retain multiple distinct original cloud contours')
assert(not Shapes[26].c, 'overcast icon must have no invented celestial paths')
assert(not Shapes[26].f, 'overcast icon needs no separate foreground color pass')
reset()
Icons.draw({},999,0,0,64)
assert(has_white() and not has_accent(), 'unknown WMO icon uses traced overcast')
reset()
Icons.draw({},26,0,0,0)
assert(#fills == 0, 'zero-size weather icon is a no-op')

-- A different configured accent only recolors celestial paths. It never
-- requires regenerating or loading any image and clouds stay white.
local real_dofile = dofile
_G.dofile = function(path)
    if path:match('lib/Settings%.lua$') then
        return {get=function() return '#1296a5' end}
    end
    return real_dofile(path)
end
local Teal = assert(loadfile(root .. 'lib/Weather_Icons.lua'))()
_G.dofile = real_dofile
reset()
Teal.draw({},29,0,0,70)
assert(is_color(0x12/255,0x96/255,0xa5/255) and has_white(),
    'alternate accent changes moon to teal without affecting cloud whites')

-- Both production widgets must use the same native Cairo path drawing,
-- including the current Date weather glyph and its three-day hover forecast.
local settings=real_dofile(root .. 'lib/Settings.lua')
local fake_surface={acquire=function() return {} end,release=noop}
local weather={
    temperature=23, high=30, low=18, humidity=60,
    code=97, is_day=1, fetched=os.time(),
    forecast={
        {day='Mon',code=97,high=25,low=17},
        {day='Tue',code=2,high=24,low=16},
        {day='Wed',code=99,high=22,low=15},
    },
}
local fake_weather={get=function() return weather end}
local fake_prayer={
    shift_date=function() return '2026-11-22' end,
    date_plus=function() return '2026-11-23' end,
    ensure_dates=noop,
    timestamp=function() return os.time()+10000 end,
    get=function() return {timings={Maghrib='20:00'},date={hijri={
        day='10',month={number=8},year='1448',
    }}} end,
}
_G.dofile=function(path)
    if path:match('lib/Surface%.lua$') then return fake_surface end
    if path:match('lib/Weather_Data%.lua$') then return fake_weather end
    if path:match('lib/Prayer_Data%.lua$') then return fake_prayer end
    if path:match('lib/Settings%.lua$') then return settings end
    return real_dofile(path)
end
_G.conky_window={width=1000,height=290}
reset()
assert(loadfile(root .. 'widgets/Weather.lua'))()
conky_main()
local n_weather=#fills
assert(n_weather > 0 and has_white() and has_accent(),
    'Weather widget must draw traced white clouds and gold sun')

reset()
assert(loadfile(root .. 'widgets/Hijri_Date.lua'))()
conky_main()
local n_date_idle=#fills
assert(n_date_idle > 0 and has_accent(),
    'Date idle must draw current traced weather glyph')
assert(conky_on_mouse({type='mouse_enter',x=950,y=30})==false)
conky_main()
assert(#fills > n_date_idle * 3,
    'Date hover must draw current icon plus three forecast glyphs')
_G.dofile=real_dofile
print('PASS: 20 source-traced Cairo icons, three-layer celestial/cloud occlusion, WMO map and Weather/Date integration')
