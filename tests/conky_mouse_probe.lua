-- Diagnostic ONLY: report whether the actual Conky backend delivers input.
-- Mouse movements are throttled to one line per second.
local last_move_second

function conky_on_mouse(event)
    if event.type == 'mouse_move' then
        local now = os.time()
        if now == last_move_second then return false end
        last_move_second = now
    end
    io.stdout:write(string.format(
        'event=%s button=%s x=%s (%s) y=%s (%s)\n',
        tostring(event.type), tostring(event.button),
        tostring(event.x), type(event.x), tostring(event.y), type(event.y)))
    io.stdout:flush()
    return event.type == 'button_down' or event.type == 'button_up'
end
