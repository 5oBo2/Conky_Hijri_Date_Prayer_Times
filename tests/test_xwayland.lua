-- Stubbed regression: all four configs explicitly require X11/XWayland.
-- Run: texlua tests/test_xwayland.lua
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './tests/'
local root = base .. '../'
local settings = dofile(root .. 'lib/Settings.lua')
local geometry = dofile(root .. 'lib/Widget_Geometry.lua')
for _, name in ipairs({'prayer_times', 'date', 'weather', 'sun_moon'}) do
    _G.conky = {}
    dofile(root .. 'configs/conky_' .. name .. '.conf')
    local c = assert(conky.config)
    assert(c.out_to_wayland == false and c.out_to_x == true, name .. ': X11/XWayland only')
    assert(c.own_window_type == 'normal', name .. ': X11 normal window')
    assert(c.own_window_hints:find('below', 1, true), name .. ': below stacking hint')
    local kind = name == 'prayer_times' and 'prayer' or name
    assert(c.minimum_width == geometry.dimension(kind, 'width', settings.scale(kind)))
    assert(c.minimum_height == geometry.dimension(kind, 'height', settings.scale(kind)))
    assert(c.double_buffer == true, name .. ': X11 double buffering required')
    assert(c.lua_load:find('widgets/', 1, true), name .. ': Lua renderer missing')
end

-- The tested Xlib surface is explicitly selected, even if conky_surface()
-- exists; each acquired surface must be destroyed exactly once.
package.preload.cairo = function() return true end
package.preload.cairo_xlib = function() return true end
local created, destroyed = {}, {}
local window = {display = 'display', drawable = 'drawable', visual = 'visual',
                width = 700, height = 290}
_G.conky_window = window
_G.conky_surface = function() error('must not call conky_surface on XWayland') end
_G.cairo_xlib_surface_create = function(display, drawable, visual, width, height)
    assert(display == window.display and drawable == window.drawable)
    assert(visual == window.visual and width == window.width and height == window.height)
    local surface = {}
    created[#created+1] = surface
    return surface
end
_G.cairo_surface_destroy = function(surface)
    destroyed[#destroyed+1] = surface
end
local Surface = dofile(root .. 'lib/Surface.lua')
local first = assert(Surface.acquire())
local second = assert(Surface.acquire())
assert(first ~= second and #created == 2)
Surface.release(first)
Surface.release(second)
Surface.release(nil)
assert(#destroyed == 2 and destroyed[1] == first and destroyed[2] == second)
_G.conky_window = nil
assert(Surface.acquire() == nil, 'cannot draw before X11 window exists')
print('PASS: all X11/XWayland widget configs, Xlib surfaces and explicit ownership')
