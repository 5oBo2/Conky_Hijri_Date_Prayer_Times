-- Offline Lua integration checks for V2 cache and the real Prayer widget's click path.
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './tests/'
local root = base .. '../'
local real_dofile = dofile
local real_open = io.open
local settings = real_dofile(root .. 'lib/Settings.lua')
local signature = settings.location_signature()
local cache_text = 'signature=' .. signature .. '\ndate=%s\n' ..
    'Fajr=05:00\nSunrise=06:30\nDhuhr=12:00\nAsr=15:00\n' ..
    'Maghrib=17:15\nIsha=18:45\nMidnight=00:30\nLastthird=02:15\n' ..
    'hijri_day=15\nhijri_month=6\nhijri_year=1448\n'
local cache_by_date = {
    ['2026-11-20'] = 'CONKY_PRAYER_V1\n' .. cache_text:format('2026-11-20'),
    ['2026-11-21'] = 'CONKY_PRAYER_V2\n' ..
        cache_text:format('2026-11-21'):gsub('Lastthird=02:15\n', ''),
    ['2026-11-22'] = 'CONKY_PRAYER_V2\n' .. cache_text:format('2026-11-22'),
}
local function fake_file(text)
    local lines = {}
    for line in text:gmatch('[^\n]+') do lines[#lines + 1] = line end
    local next_line = 1
    return {
        read = function() local v = lines[next_line]; next_line = next_line + 1; return v end,
        lines = function() return function()
            local v = lines[next_line]; next_line = next_line + 1; return v
        end end,
        close = function() end,
    }
end
io.open = function(path, mode)
    local date = path:match('(%d%d%d%d%-%d%d%-%d%d)%.cache$')
    if date then return cache_by_date[date] and fake_file(cache_by_date[date]) end
    return real_open(path, mode)
end
local data_source = real_dofile(root .. 'lib/Prayer_Data.lua')
assert(data_source.get('2026-11-20') == nil, 'V1 must be rejected')
assert(data_source.get('2026-11-21') == nil, 'V2 missing Lastthird must be rejected')
local cached = assert(data_source.get('2026-11-22'))
assert(cached.timings.Lastthird == '02:15')
assert(cached.timings.Midnight == '00:30')
io.open = real_open

local Hover = real_dofile(root .. 'lib/Hover_State.lua')
local h = Hover.new(5)
h:set_zone('midnight_column', {100, 80, 190, 170})
assert(h:contains('midnight_column', 100, 170))
assert(not h:contains('midnight_column', nil, 130))
assert(not h:contains('midnight_column', 99, 130))
assert(not h:contains('missing', 140, 130))
h:mouse({type = 'mouse_enter', x = 140, y = 130}, 10)
assert(h:visible('midnight_column', 10) and not h:visible('midnight_column', 15))
assert(h:contains('midnight_column', 140, 130), 'click hit testing ignores hover timeout')
h:set_zone('midnight_column', nil)
assert(not h:contains('midnight_column', 140, 130))

package.preload.cairo = function() return true end
local function noop() end
local calls = {
    'cairo_select_font_face', 'cairo_set_font_size', 'cairo_set_source_rgba',
    'cairo_move_to', 'cairo_destroy', 'cairo_rectangle', 'cairo_fill', 'cairo_set_line_width',
    'cairo_stroke', 'cairo_arc',
}
for _, name in ipairs(calls) do _G[name] = noop end
_G.CAIRO_FONT_SLANT_NORMAL = 0
_G.CAIRO_FONT_WEIGHT_NORMAL = 0
_G.cairo_create = function() return {} end
_G.cairo_text_extents_t = {create = function() return {} end}
_G.cairo_text_extents = function(_, s, ext) ext.x_advance = #tostring(s) * 14 end
local rendered = {}
_G.cairo_show_text = function(_, s) rendered[#rendered + 1] = tostring(s) end
local function displayed(value)
    for _, label in ipairs(rendered) do if label == value then return true end end
    return false
end
local surface = {acquire = function() return {} end, release = function() end}
local default_settings = {
    scale = function() return 1 end,
    get = function(section, key, default)
        return default
    end,
    boolean = function(section, key, default)
        if section == 'behavior' and key == 'athan_enabled' then return false end
        return default
    end,
    number = function(_, _, default) return default end,
}
local real_time = os.time
local today = os.date('*t')
local evening = real_time{year = today.year, month = today.month, day = today.day,
                          hour = 20, min = 30, sec = 0}
os.time = function(parts) if parts then return real_time(parts) end return evening end
local available = true
data_source.get = function() return available and cached or nil end
data_source.ensure_dates = noop
_G.dofile = function(path)
    if path:match('lib/Surface%.lua$') then return surface end
    if path:match('lib/Prayer_Data%.lua$') then return data_source end
    if path:match('lib/Settings%.lua$') then return default_settings end
    return real_dofile(path)
end
_G.conky_window = {width = 1400, height = 255}
assert(loadfile(root .. 'widgets/Prayer_Times.lua'))()
local mouse, draw = assert(conky_on_mouse), assert(conky_main)
local state
for i = 1, 30 do
    local name, value = debug.getupvalue(mouse, i)
    if name == 'hover' then state = value; break end
end
assert(state, 'click handler must reuse named hover zones')
local function render()
    rendered = {}
    draw()
end
render()
assert(displayed('Midnight') and displayed('00:30'))
assert(displayed('Till Midnight'), 'after-Isha countdown must be present')
assert(not displayed('Last 3rd') and not displayed('02:15'))
local rectangle = assert(state.zones.midnight_column)[1]
assert(rectangle[3] - rectangle[1] >= #'Last 3rd' * 14,
       'clickable column includes the full alternate header')
local x, y = (rectangle[1] + rectangle[3]) / 2, (rectangle[2] + rectangle[4]) / 2
assert(mouse({type = 'button_up', button = 'left', x = x, y = y}) == false)
assert(mouse({type = 'button_down', button = 'right', x = x, y = y}) == false)
assert(mouse({type = 'button_down', button = 'left', x = x - 500, y = y}) == false)
assert(mouse({type = 'button_down', button = 'left'}) == false)
render()
assert(displayed('Midnight') and not displayed('Last 3rd'))
assert(mouse({type = 'button_down', button = 'left', x = x, y = y}) == true)
render()
assert(displayed('Last 3rd') and displayed('02:15'))
assert(not displayed('Midnight'), '7th-column header must change, not merely add a label')
assert(displayed('Till Midnight'), '7th-column toggle must not change post-Isha extra')
assert(mouse({type = 'button_down', button = 'left', x = x, y = y}) == true)
render()
assert(displayed('Midnight') and displayed('00:30') and not displayed('Last 3rd'))
available = false
render()
assert(state.zones.midnight_column == nil, 'no clickable area without data')
assert(mouse({type = 'button_down', button = 'left', x = x, y = y}) == false)
_G.dofile = real_dofile
os.time = real_time
print('Task 4: V2 cache, named-zone hit testing, and real widget click/countdown paths passed')
