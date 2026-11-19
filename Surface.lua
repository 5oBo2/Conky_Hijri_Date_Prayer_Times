-- Obtain a Cairo drawing surface across Conky releases/backends.
-- conky_surface() is preferred where present; earlier builds use Xlib.
require('cairo')
local has_xlib = pcall(require, 'cairo_xlib')
local Surface = {}

function Surface.acquire()
    if type(conky_surface) == 'function' then
        local cs = conky_surface()
        if cs then return cs, false end -- owned by Conky, don't destroy
    end
    if has_xlib and conky_window and conky_window.display
       and conky_window.drawable and conky_window.visual then
        return cairo_xlib_surface_create(conky_window.display,
            conky_window.drawable, conky_window.visual,
            conky_window.width, conky_window.height), true
    end
    return nil, false
end

function Surface.release(surface, owned)
    if surface and owned then cairo_surface_destroy(surface) end
end

return Surface
