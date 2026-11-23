-- X11/XWayland Cairo surface adapter for Fedora 45 / Conky 1.24.2.
-- The Xlib drawable path was verified with double_buffer=true on KDE Wayland.
-- In this environment conky_surface() returned a valid surface but its
-- double-buffered drawing was invisible. Do not silently fall back to it.
-- cairo_xlib is deprecated; see docs/NATIVE_WAYLAND_MIGRATION.md.
require('cairo')
local ok, err = pcall(require, 'cairo_xlib')
assert(ok, 'XWayland rendering requires Conky cairo_xlib: ' .. tostring(err))

local Surface = {}

function Surface.acquire()
    local w = conky_window
    if not (w and w.display and w.drawable and w.visual) then
        return nil
    end
    -- The created Xlib surface is owned by the widget, not by Conky.
    return cairo_xlib_surface_create(w.display, w.drawable, w.visual,
                                     w.width, w.height)
end

function Surface.release(surface)
    if surface then cairo_surface_destroy(surface) end
end

return Surface
