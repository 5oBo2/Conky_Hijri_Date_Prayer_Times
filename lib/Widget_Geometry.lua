-- One authoritative design canvas shared with workers/layout.py.
-- Sizes are minimum window dimensions, NOT guaranteed Cairo ink extents.
local root = (debug.getinfo(1, 'S').source:match('^@(.*/)') or './lib/') .. '../'
local file, err = io.open(root .. 'widget_geometry.ini', 'r')
if not file then error('Cannot read widget_geometry.ini: ' .. tostring(err)) end
local sizes, current = {}, nil
for line in file:lines() do
    local name = line:match('^%s*%[([%w_]+)%]%s*$')
    if name then
        current = name
        sizes[current] = sizes[current] or {}
    elseif current then
        local key, value = line:match('^%s*([%w_]+)%s*=%s*(%d+)%s*$')
        if key then sizes[current][key] = tonumber(value) end
    end
end
file:close()
local M = {}
function M.dimension(kind, axis, scale)
    local value = sizes[kind] and sizes[kind][axis]
    assert(value and value > 0, 'Missing widget canvas dimension: ' .. kind .. '.' .. axis)
    return math.floor(value * scale + 0.5)
end
return M
