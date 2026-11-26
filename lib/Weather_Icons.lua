-- Pixel-faithful traced weather artwork for standalone Weather and Date.
-- The original 256x256 PNG silhouettes are stored as native Cairo fill paths.
-- All clouds, double cloud overlaps, rays, moon curves and precipitation come
-- directly from those exact icons; no procedural approximations or PNG I/O.
-- See docs/WEATHER_ICON_TINT.md before editing or regenerating path geometry.
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './lib/'
local settings = dofile(base .. 'Settings.lua')
local PATHS = dofile(base .. 'Weather_Icon_Paths.lua')
local M = {}
local hex = settings.get('appearance', 'next_prayer_color', '#efb46f')
assert(type(hex) == 'string' and hex:match('^#%x%x%x%x%x%x$'),
    'appearance.next_prayer_color must be #RRGGBB')
local ACCENT = {
    tonumber(hex:sub(2, 3), 16) / 255,
    tonumber(hex:sub(4, 5), 16) / 255,
    tonumber(hex:sub(6, 7), 16) / 255,
}
-- Five semi-transparent contour bands reconstruct the source's antialiasing.
-- Draw from widest/softest to narrowest/opaque in the 256px source canvas.
local OPACITY = { .055, .142857142857, .259259259259, .483333333333, 1 }

function M.code(wmo, day)
    -- Open-Meteo WMO weather_code and is_day -> original weather icon.
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

local function fill_contours(cr, tiers, r, g, b)
    if not tiers then return end
    for level, loops in ipairs(tiers) do
        if #loops > 0 then
            cairo_new_path(cr)
            for _, points in ipairs(loops) do
                cairo_move_to(cr, points[1], points[2])
                for j = 3, #points, 2 do
                    cairo_line_to(cr, points[j], points[j + 1])
                end
                cairo_close_path(cr)
            end
            cairo_set_source_rgba(cr, r, g, b, OPACITY[level])
            cairo_fill(cr)
        end
    end
end

function M.draw(cr, id, x, y, size)
    if not size or size <= 0 then return end
    local icon = PATHS[id] or PATHS[26]
    cairo_save(cr)
    cairo_translate(cr, x, y)
    cairo_scale(cr, size / 256, size / 256)
    cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD)
    -- Three source-derived layers preserve the original overlap order:
    -- rear clouds first, sun/moon over the rear cloud, foreground cloud last.
    -- The final white pass therefore interrupts the celestial stroke only
    -- where the source artwork shows the lower cloud in front.
    fill_contours(cr, icon.n, 1, 1, 1)
    fill_contours(cr, icon.c, ACCENT[1], ACCENT[2], ACCENT[3])
    fill_contours(cr, icon.f, 1, 1, 1)
    cairo_restore(cr)
end

return M
