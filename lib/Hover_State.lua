-- Independent named hover zones in one Conky window.
-- Native Wayland mouse events are delivered directly through lua_mouse_hook.
local Hover = {}

local function contains(rectangles, x, y)
    for _, rect in ipairs(rectangles) do
        if x >= rect[1] and x <= rect[3] and y >= rect[2] and y <= rect[4] then
            return true
        end
    end
    return false
end

function Hover.new(timeout_seconds)
    local state = {
        timeout = math.max(0, tonumber(timeout_seconds) or 5),
        zones = {},
        last_input_at = {},
    }

    function state:set_zone(name, rect_or_rects)
        -- One rectangle or a list of them; nil removes the zone.
        -- Redraws may update geometry without resetting hover activity.
        assert(type(name) == 'string' and name ~= '', 'zone name must be a nonempty string')
        if rect_or_rects == nil then
            self.zones[name] = nil
            self.last_input_at[name] = nil
        else
            assert(type(rect_or_rects) == 'table', 'zone rectangles must be a table')
            self.zones[name] = type(rect_or_rects[1]) == 'number'
                and {rect_or_rects} or rect_or_rects
        end
    end

    function state:contains(name, x, y)
        -- Direct hit-testing for button events; independent of hover timeout.
        assert(type(name) == 'string' and name ~= '', 'zone name must be a nonempty string')
        local rectangles = self.zones[name]
        return rectangles ~= nil and type(x) == 'number' and type(y) == 'number'
            and contains(rectangles, x, y)
    end

    function state:mouse(event, now)
        if event.type == 'mouse_leave' then
            for name in pairs(self.last_input_at) do
                self.last_input_at[name] = nil
            end
        elseif event.type == 'mouse_enter' or event.type == 'mouse_move' then
            -- If coordinates are absent, no zone can be identified reliably.
            local has_coordinates = type(event.x) == 'number' and type(event.y) == 'number'
            for name in pairs(self.zones) do
                self.last_input_at[name] = has_coordinates
                    and self:contains(name, event.x, event.y) and now or nil
            end
        end
        return false -- never swallow events destined for other windows
    end

    function state:visible(name, now)
        assert(type(name) == 'string' and name ~= '', 'zone name must be a nonempty string')
        now = now or os.time()
        local last_at = self.last_input_at[name]
        -- Wayland can lose mouse_leave. A stationary pointer also expires.
        if last_at ~= nil and self.timeout > 0 and now - last_at >= self.timeout then
            self.last_input_at[name] = nil
        end
        return self.last_input_at[name] ~= nil
    end

    return state
end

return Hover
