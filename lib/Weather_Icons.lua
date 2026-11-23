-- Shared Open-Meteo weather condition icons for Weather and Hijri Date.
-- The surface cache is lazy and belongs to each Conky/Lua process.
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './lib/'
local root = base .. '../'
local M = {}
local icons = {}

function M.code(wmo, day)
    -- Open-Meteo WMO weather_code and is_day -> matching transparent PNG.
    if wmo == 0 then return day and 32 or 31 end                 -- clear
    if wmo == 1 then return day and 34 or 33 end                 -- mainly clear
    if wmo == 2 then return day and 30 or 29 end                 -- partly cloudy
    if wmo == 3 then return 26 end                               -- overcast
    if wmo == 45 or wmo == 48 then return 20 end                 -- fog/rime fog
    if wmo == 51 or wmo == 53 then return day and 9 or 45 end   -- drizzle
    if wmo == 55 then return day and 6 or 45 end                 -- dense drizzle
    if wmo == 56 or wmo == 57 then return 5 end                  -- freezing drizzle
    if wmo == 61 then return day and 9 or 45 end                 -- slight rain
    if wmo == 63 or wmo == 65 then return day and 6 or 45 end   -- moderate/heavy rain
    if wmo == 66 or wmo == 67 then return 5 end                  -- freezing rain (icy mix proxy)
    if wmo == 71 then return 13 end                              -- slight snowfall
    if wmo == 73 or wmo == 75 then return 14 end                 -- moderate/heavy snowfall
    if wmo == 77 then return 17 end                              -- snow grains/ice pellets proxy
    if wmo == 80 then return day and 9 or 45 end                 -- slight rain showers
    if wmo == 81 or wmo == 82 then return day and 6 or 45 end   -- heavier rain showers
    if wmo == 85 then return day and 41 or 46 end                -- slight snow showers
    if wmo == 86 then return day and 14 or 46 end                -- heavy snow showers
    if wmo == 95 or wmo == 97 then return day and 37 or 47 end   -- thunderstorm, incl. heavy
    if wmo == 96 or wmo == 99 then return 0 end    -- severe / hail thunderstorm
    return 26                                                   -- unrecognized WMO code
end
function M.draw(cr, id, x, y, size)
    if not icons[id] then
        local path = root .. 'assets/weather/' .. id .. '.png'
        icons[id] = cairo_image_surface_create_from_png(path)
    end
    local surface = icons[id]
    if not surface then return end
    cairo_save(cr)
    cairo_translate(cr, x, y)
    cairo_scale(cr, size / 256, size / 256)
    cairo_set_source_surface(cr, surface, 0, 0)
    cairo_paint(cr)
    cairo_restore(cr)
end
return M
