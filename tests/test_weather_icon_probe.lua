-- Headless integration test for the full-screen PNG-vs-Cairo comparison probe.
local root = arg[0]:match('^(.*)/tests/') or '.'
root = root .. '/'

package.preload['cairo'] = function() return true end
package.preload['cairo_xlib'] = function() return true end

CAIRO_FONT_SLANT_NORMAL = 0
CAIRO_FONT_WEIGHT_NORMAL = 0
CAIRO_FONT_WEIGHT_BOLD = 1
CAIRO_FILL_RULE_EVEN_ODD = 1
CAIRO_STATUS_SUCCESS = 0

local pngs = {}
local function noop() end
for _, name in ipairs({
    'cairo_save', 'cairo_restore', 'cairo_translate', 'cairo_scale',
    'cairo_set_source_surface', 'cairo_paint', 'cairo_new_path',
    'cairo_move_to', 'cairo_line_to', 'cairo_close_path',
    'cairo_set_source_rgba', 'cairo_fill', 'cairo_fill_preserve',
    'cairo_set_line_width', 'cairo_stroke', 'cairo_set_fill_rule',
    'cairo_select_font_face', 'cairo_set_font_size', 'cairo_show_text',
    'cairo_arc', 'cairo_new_sub_path', 'cairo_rectangle',
}) do _G[name] = noop end

cairo_xlib_surface_create = function() return {kind='xlib'} end
cairo_surface_destroy = noop
cairo_create = function() return {kind='context'} end
cairo_destroy = noop
cairo_image_surface_create_from_png = function(path)
    local file = assert(io.open(path, 'rb'), 'missing original PNG: ' .. path)
    file:close()
    pngs[#pngs + 1] = path
    return {path=path}
end
cairo_surface_status = function() return CAIRO_STATUS_SUCCESS end
cairo_text_extents_t = {create=function()
    return {x_bearing=0, y_bearing=-8, width=40, height=10}
end}
cairo_text_extents = function(_, value, ext)
    ext.width = #tostring(value) * 5
end

conky_window = {width=1920, height=1080, display=1, drawable=1, visual=1}
assert(loadfile(root .. 'widgets/Weather_Icon_Probe.lua'))()
assert(type(conky_main) == 'function', 'probe must expose conky_main')
assert(type(conky_on_mouse) == 'function', 'probe must expose its close button hook')
conky_main()

assert(#pngs == 20, 'probe must load all 20 original PNGs exactly once')
local ids = {}
for _, path in ipairs(pngs) do
    local id = tonumber(path:match('/(%d+)%.png$'))
    assert(id, 'unexpected PNG path: ' .. path)
    assert(not ids[id], 'duplicate original PNG: ' .. id)
    ids[id] = true
end
for _, id in ipairs({0,5,6,9,13,14,17,20,26,29,30,31,32,33,34,37,41,45,46,47}) do
    assert(ids[id], 'missing original icon ' .. id)
end

local old_exit = os.exit
local exited = false
os.exit = function(code) exited = (code == 0) end
conky_on_mouse({type='button_down', button=1, x=conky_window.width - 50, y=25})
os.exit = old_exit
assert(exited, 'clicking the visible close control must close the probe')

print('Weather icon probe: all 20 PNG originals, vector draw calls and close control passed')
