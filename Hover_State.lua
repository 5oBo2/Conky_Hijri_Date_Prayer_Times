-- Hover state with a geometry-based hitbox and a failsafe for lost mouse_leave.
-- No X11 cursor polling: that is unreliable on KDE Plasma Wayland/XWayland.
local Hover = {}

function Hover.new(timeout_seconds, area)
    local state = {
        active = false,
        last_input_at = nil,
        timeout = math.max(0, tonumber(timeout_seconds) or 5),
        area = area or 'content',
        zones = nil,
    }

    function state:set_zones(zones)
        -- Each zone: {left, top, right, bottom}, in Conky-local pixels.
        self.zones = zones
    end

    function state:within(x, y)
        if self.area == 'window' or not self.zones then return true end
        if type(x) ~= 'number' or type(y) ~= 'number' then
            -- Older builds may omit coordinates; defer to enter/leave + failsafe.
            return true
        end
        for _, z in ipairs(self.zones) do
            if x >= z[1] and x <= z[3] and y >= z[2] and y <= z[4] then
                return true
            end
        end
        return false
    end

    function state:mouse(event, now)
        if event.type == 'mouse_leave' then
            self.active = false
            self.last_input_at = nil
        elseif event.type == 'mouse_enter' or event.type == 'mouse_move' then
            self.active = self:within(event.x, event.y)
            self.last_input_at = self.active and now or nil
        end
        return false -- always allow other windows to receive mouse events
    end

    function state:visible(now)
        -- The compositor can lose mouse_leave when crossing monitors quickly.
        -- Wayland forbids generic global cursor polling, so use a bounded
        -- no-input fallback instead of letting hover remain stuck forever.
        -- Caveat: a completely stationary pointer also expires after timeout.
        if self.active and self.timeout > 0 and self.last_input_at
           and now - self.last_input_at >= self.timeout then
            self.active = false
            self.last_input_at = nil
        end
        return self.active
    end

    return state
end

return Hover
