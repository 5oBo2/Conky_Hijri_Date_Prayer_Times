-- Tiny dependency-free INI reader shared by the Conky configs and draw scripts.
-- Put this file with settings.ini in ~/.config/conky/.
local M = {}
local origin = debug.getinfo(1, 'S').source
M.dir = origin:match('^@(.*/)') or ((os.getenv('HOME') or '') .. '/.config/conky/')
local values = {}
local section
local file, err = io.open(M.dir .. 'settings.ini', 'r')
if not file then error('Cannot read settings.ini: ' .. tostring(err)) end
for line in file:lines() do
    local s = line:match('^%s*%[([%w_]+)%]%s*$')
    if s then
        section = s
        values[section] = values[section] or {}
    elseif section then
        local k, v = line:match('^%s*([%w_]+)%s*=%s*(.-)%s*$')
        if k and v and not k:match('^#') then
            values[section][k] = v:gsub('%s+[;#].*$', '')
        end
    end
end
file:close()

function M.get(section_name, key, default)
    local s = values[section_name]
    local value = s and s[key]
    if value == nil or value == '' then return default end
    return value
end
function M.number(section_name, key, default)
    local n = tonumber(M.get(section_name, key, default))
    if not n then error('Invalid number for ' .. section_name .. '.' .. key) end
    return n
end
function M.boolean(section_name, key, default)
    local v = tostring(M.get(section_name, key, default and 'yes' or 'no')):lower()
    return v == 'yes' or v == 'true' or v == '1' or v == 'on'
end
-- Date appearance has exactly two supported modes. No alternative keys.
-- This setting never changes the standalone Weather window.
function M.date_weather_mode()
    local mode = M.get('appearance', 'date_weather_mode')
    assert(mode == 'date_only' or mode == 'date_and_weather',
        'appearance.date_weather_mode must be date_only or date_and_weather')
    return mode
end
function M.scale(kind)
    local n = M.number('appearance', kind .. '_scale', 1)
    assert(n >= 0.3 and n <= 3, kind .. '_scale must be between 0.3 and 3')
    return n
end
function M.location_signature()
    local parts = {}
    for _, name in ipairs({'mode', 'city', 'country', 'state', 'latitude',
                            'longitude', 'method', 'school', 'midnight_mode'}) do
        parts[#parts+1] = tostring(M.get('location', name, ''))
    end
    return table.concat(parts, '|')
end
return M
