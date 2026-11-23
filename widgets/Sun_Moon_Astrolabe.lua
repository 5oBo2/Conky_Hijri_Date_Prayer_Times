-- Celestial Astrolabe: the single canonical Conky Sun/Moon widget.
-- Borderless transparent design adapted from Concept A in ai_studio_code.html.
-- Uses the SAME font, scale, moon-phase calculation and local sun/prayer data
-- as the previous Sun_Moon design, with smooth phase illumination.
-- The sun indicator represents day progress; the blue indicator represents
-- progress through the NIGHT interval (not the Moon's position in the sky).
require('cairo')
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './widgets/'
local root = base .. '../'
local Surface = dofile(root .. 'lib/Surface.lua')
local Weather = dofile(root .. 'lib/Weather_Data.lua')
local Prayer = dofile(root .. 'lib/Prayer_Data.lua')
local Hover = dofile(root .. 'lib/Hover_State.lua')
local Markers = dofile(root .. 'lib/Astrolabe_Prayer_Markers.lua')
local settings = dofile(root .. 'lib/Settings.lua')
local SCALE = settings.scale('sun_moon')
local FONT = settings.get('appearance', 'font', 'DejaVu Sans')
local PI = math.pi
local CX, CY, R = 190, 166, 104
local WIDTH, HEIGHT = 416, 432
local WHITE = { 0.937, 0.949, 1.0 }
local MUTED = { 0.553, 0.596, 0.678 }
local GOLD = { 1.0, 0.831, 0.439 }
local BLUE = { 0.388, 0.702, 0.929 }
local CORAL = { 1.0, 0.522, 0.376 }
local ROSE = { 0.961, 0.431, 0.510 }
local last_prayer_ensure = 0
-- Use the existing suite-wide hover failsafe. The user's XWayland setup
-- uses 0: a stationary pointer remains active until a leave/move event.
local hover = Hover.new(settings.number('behavior', 'hover_failsafe_seconds', 0))

function conky_on_mouse(event)
    return hover:mouse(event, os.time())
end

local function hover_rectangle(x1, y1, x2, y2)
    -- Cairo's design-space coordinates are translated by (18,18) AFTER scaling.
    -- Conky mouse coordinates are window pixels, not Cairo design coordinates.
    return {(x1 + 18) * SCALE, (y1 + 18) * SCALE,
            (x2 + 18) * SCALE, (y2 + 18) * SCALE}
end

local function update_hover_zones()
    hover:set_zone('astrolabe', {
        hover_rectangle(24, 19, 356, 307),  -- dial, tick ring and captions
        hover_rectangle(20, 310, 360, 382), -- 24-hour bar and duration labels
    })
end

local function color(cr, c, alpha)
    cairo_set_source_rgba(cr, c[1], c[2], c[3], alpha == nil and 1 or alpha)
end
local function dot(cr, x, y, r, c, a)
    color(cr, c, a)
    cairo_arc(cr, x, y, r, 0, 2 * PI)
    cairo_fill(cr)
end
local function rounded(cr, x, y, w, h, radius)
    local r = math.min(radius, w / 2, h / 2)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x + w - r, y + r, r, -PI / 2, 0)
    cairo_arc(cr, x + w - r, y + h - r, r, 0, PI / 2)
    cairo_arc(cr, x + r, y + h - r, r, PI / 2, PI)
    cairo_arc(cr, x + r, y + r, r, PI, 3 * PI / 2)
    cairo_close_path(cr)
end
local function text_at(cr, s, x, y, size, c, align, bold, tracking)
    -- ALL text uses the user's appearance.font: ITC Avant Garde Pro XLt by default.
    -- 'tracking' adds letter spacing to headings while retaining that family.
    s = tostring(s)
    cairo_select_font_face(cr, FONT, CAIRO_FONT_SLANT_NORMAL,
        bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    cairo_set_font_size(cr, size)
    color(cr, c or WHITE)
    local ext = cairo_text_extents_t:create()
    cairo_text_extents(cr, s, ext)
    local space = tracking or 0
    -- Cairo's toy text API does not support kerning with letter-spacing; draw
    -- one UTF-8 codepoint at a time ONLY when tracking is requested.
    if space > 0 then
        local pieces = {}
        for byte in s:gmatch('[%z\1-\127\194-\244][\128-\191]*') do pieces[#pieces + 1] = byte end
        if #pieces < 1 then return end
        local widths, total = {}, 0
        for i, ch in ipairs(pieces) do
            cairo_text_extents(cr, ch, ext)
            widths[i] = ext.x_advance
            total = total + ext.x_advance
        end
        total = total + space * (#pieces - 1)
        if align == 'center' then x = x - total / 2 end
        if align == 'right' then x = x - total end
        for i, ch in ipairs(pieces) do
            cairo_move_to(cr, x, y)
            cairo_show_text(cr, ch)
            x = x + widths[i] + space
        end
    else
        if align == 'center' then x = x - ext.x_advance / 2 end
        if align == 'right' then x = x - ext.x_advance end
        cairo_move_to(cr, x, y)
        cairo_show_text(cr, s)
    end
end
local function clamp(v) return math.max(0, math.min(1, v)) end
local function lerp(a, b, t) return a + (b - a) * t end
local function mix(a, b, t)
    return { lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t) }
end
local function point(angle)
    return CX + R * math.cos(angle), CY + R * math.sin(angle)
end
local function time_fraction(ts)
    local t = os.date('*t', ts)
    return (t.hour * 3600 + t.min * 60 + t.sec) / 86400
end
local function duration(seconds)
    local mins = math.floor(math.max(0, seconds) / 60 + 0.5)
    return string.format('%dh %02dm', math.floor(mins / 60), mins % 60)
end

-- Same approximate geocentric lunar algorithm as the original, with a
-- continuous moon-cycle fraction so the lit terminator is smooth, not 8-step.
local function moon_phase(now)
    local jd = now / 86400 + 2440587.5
    local t = (jd - 2451545.0) / 36525
    local function sine(deg) return math.sin(deg * PI / 180) end
    local sun_m = 357.5291092 + 35999.0502909 * t
    local sun_l = 280.46646 + 36000.76983 * t +
        (1.914602 - 0.004817 * t) * sine(sun_m) + 0.019993 * sine(2 * sun_m)
    local moon_m = 134.9633964 + 477198.8675055 * t
    local d = 297.8501921 + 445267.1114034 * t
    local moon_l = 218.3164477 + 481267.88123421 * t
        + 6.289 * sine(moon_m) + 1.274 * sine(2 * d - moon_m)
        + 0.658 * sine(2 * d) + 0.214 * sine(2 * moon_m)
        - 0.186 * sine(sun_m) - 0.059 * sine(2 * d - 2 * moon_m)
        - 0.057 * sine(2 * d - sun_m - moon_m)
    local separation = (moon_l - sun_l) % 360
    local illuminated = (1 - math.cos(separation * PI / 180)) / 2
    local labels = { 'New Moon', 'Waxing Crescent', 'First Quarter', 'Waxing Gibbous',
        'Full Moon', 'Waning Gibbous', 'Last Quarter', 'Waning Crescent' }
    local index = math.floor(((separation + 22.5) % 360) / 45) + 1
    return labels[index], math.floor(illuminated * 100 + 0.5), separation / 360, illuminated
end

-- Reuse the original location/timezone behavior, cache, and sunrise/Maghrib
-- precedence. This requires the same Weather_Data.lua and Prayer_Data.lua.
local function sun_schedule(now, weather)
    -- Weather.get() deliberately serves stale cache while refreshing in the
    -- background. After suspend or a date rollover, yesterday's solar times
    -- must NEVER be treated as today's (they would show NIGHT 100% all day).
    local today = os.date('%Y-%m-%d', now)
    local events = {}
    if weather and weather.local_date == today then
        events = {
            sunrise = weather.sunrise,
            sunset = weather.sunset,
            yesterday_sunset = weather.yesterday_sunset,
            tomorrow_sunrise = weather.tomorrow_sunrise,
            sunrise_label = weather.sunrise_label,
            sunset_label = weather.sunset_label,
        }
    end
    -- Prayer data is an independent, date-keyed fallback, including while a
    -- fresh weather response is still in flight after waking the computer.
    do
        local yesterday = Prayer.date_plus(today, -1)
        local tomorrow = Prayer.date_plus(today, 1)
        if now - last_prayer_ensure > 60 or now < last_prayer_ensure then
            Prayer.ensure_dates({ today, yesterday, tomorrow }, now)
            last_prayer_ensure = now
        end
        local d0, d1, d2 = Prayer.get(yesterday), Prayer.get(today), Prayer.get(tomorrow)
        if d0 then
            events.yesterday_sunset = Prayer.timestamp(yesterday, d0.timings.Maghrib)
                or events.yesterday_sunset
        end
        if d1 then
            events.sunrise = Prayer.timestamp(today, d1.timings.Sunrise) or events.sunrise
            events.sunset = Prayer.timestamp(today, d1.timings.Maghrib) or events.sunset
            events.sunrise_label = d1.timings.Sunrise
            events.sunset_label = d1.timings.Maghrib
        end
        if d2 then
            events.tomorrow_sunrise = Prayer.timestamp(tomorrow, d2.timings.Sunrise)
                or events.tomorrow_sunrise
        end
    end
    for _, k in ipairs({ 'yesterday_sunset', 'sunrise', 'sunset', 'tomorrow_sunrise',
        'sunrise_label', 'sunset_label' }) do
        if not events[k] then return nil end
    end
    if not (events.yesterday_sunset < events.sunrise and
            events.sunrise < events.sunset and
            events.sunset < events.tomorrow_sunrise) then
        return nil
    end
    local day = now >= events.sunrise and now < events.sunset
    local frac
    if day then
        frac = clamp((now - events.sunrise) / (events.sunset - events.sunrise))
    elseif now < events.sunrise then
        frac = clamp((now - events.yesterday_sunset) / (events.sunrise - events.yesterday_sunset))
    else
        frac = clamp((now - events.sunset) / (events.tomorrow_sunrise - events.sunset))
    end
    -- Midnight is the midpoint of the relevant sunset-to-sunrise interval.
    -- Before sunrise, use last night's interval rather than tonight's.
    local night_start = now < events.sunrise and events.yesterday_sunset or events.sunset
    local night_end = now < events.sunrise and events.sunrise or events.tomorrow_sunrise
    return {
        day = day,
        fraction = frac,
        sunrise = events.sunrise_label:sub(1, 5),
        sunset = events.sunset_label:sub(1, 5),
        sunrise_ts = events.sunrise,
        sunset_ts = events.sunset,
        yesterday_sunset_ts = events.yesterday_sunset,
        tomorrow_sunrise_ts = events.tomorrow_sunrise,
        noon = os.date('%H:%M', math.floor((events.sunrise + events.sunset) / 2)),
        midnight = os.date('%H:%M', math.floor((night_start + night_end) / 2)),
        day_seconds = events.sunset - events.sunrise,
        night_seconds = events.tomorrow_sunrise - events.sunset,
    }
end

local function draw_dial(cr, schedule)
    local day = schedule and schedule.day or false
    local frac = schedule and schedule.fraction or 0
    -- Watch-dial skeleton and luxury 48-tick chapter ring.
    cairo_set_line_width(cr, 0.7)
    color(cr, WHITE, .055)
    cairo_arc(cr, CX, CY, R + 5, 0, 2 * PI)
    cairo_stroke(cr)
    for i = 0, 47 do
        local angle = i * 2 * PI / 48
        local major = i % 12 == 0
        local a, b = R + 9, R + (major and 16 or 12.5)
        local co, si = math.cos(angle), math.sin(angle)
        cairo_move_to(cr, CX + a * co, CY + a * si)
        cairo_line_to(cr, CX + b * co, CY + b * si)
        color(cr, WHITE, major and .32 or .13)
        cairo_set_line_width(cr, major and 1.3 or .8)
        cairo_stroke(cr)
    end
    for i = 1, 39 do
        local t = i / 40
        local dx, dy = point(PI + PI * t)
        dot(cr, dx, dy, 1.4, GOLD, day and (t <= frac and .92 or .23) or .20)
        local nx, ny = point(PI * t)
        dot(cr, nx, ny, 1.3, BLUE, not day and (t <= frac and .87 or .23) or .19)
    end
    -- Colored, elevation-dependent active arc on the sun half; icy blue at night.
    if schedule and frac > 0.002 then
        if day then
            local n = math.max(1, math.floor(96 * frac))
            for i = 0, n - 1 do
                local a = PI + PI * frac * i / n
                local b = PI + PI * frac * (i + 1) / n
                local t = frac * (i + .5) / n
                local col = t < .5 and mix(CORAL, GOLD, 2 * t) or mix(GOLD, ROSE, (t - .5) * 2)
                cairo_arc(cr, CX, CY, R, a, b + .003)
                cairo_set_line_width(cr, 6)
                color(cr, col, .07)
                cairo_stroke(cr)
                cairo_arc(cr, CX, CY, R, a, b + .003)
                cairo_set_line_width(cr, 2.7)
                color(cr, col, .94)
                cairo_stroke(cr)
            end
        else
            cairo_arc(cr, CX, CY, R, 0, PI * frac)
            cairo_set_line_width(cr, 7)
            color(cr, BLUE, .075)
            cairo_stroke(cr)
            cairo_arc(cr, CX, CY, R, 0, PI * frac)
            cairo_set_line_width(cr, 2.8)
            color(cr, BLUE, .95)
            cairo_stroke(cr)
        end
    end
    -- Solar noon, computed from the source time data, never hardcoded.
    text_at(cr, 'SOLAR NOON · ' .. (schedule and schedule.noon or '--:--'),
        CX, CY - R - 23, 9.4, MUTED, 'center', true, 1.1)
    -- Match the top caption on the opposite side of the night arc.
    -- Keep enough room for the watch ticks and the DAY/NIGHT summary below.
    text_at(cr, 'SOLAR MIDNIGHT · ' .. (schedule and schedule.midnight or '--:--'),
        CX, CY + R + 33, 9.4, MUTED, 'center', true, 1.1)
    -- Horizon line with the gap deliberately reserved for central Moon.
    local line = cairo_pattern_create_linear(22, 0, 358, 0)
    cairo_pattern_add_color_stop_rgba(line, 0, 1, 1, 1, 0)
    cairo_pattern_add_color_stop_rgba(line, .18, 1, 1, 1, .35)
    cairo_pattern_add_color_stop_rgba(line, .40, 1, 1, 1, .12)
    cairo_pattern_add_color_stop_rgba(line, .60, 1, 1, 1, .12)
    cairo_pattern_add_color_stop_rgba(line, .82, 1, 1, 1, .35)
    cairo_pattern_add_color_stop_rgba(line, 1, 1, 1, 1, 0)
    cairo_set_source(cr, line)
    cairo_set_line_width(cr, 1)
    cairo_move_to(cr, 22, CY)
    cairo_line_to(cr, CX - 43, CY)
    cairo_move_to(cr, CX + 43, CY)
    cairo_line_to(cr, 358, CY)
    cairo_stroke(cr)
    cairo_pattern_destroy(line)
    dot(cr, CX - R, CY, 3.6, CORAL, 1)
    dot(cr, CX + R, CY, 3.6, ROSE, 1)
    text_at(cr, schedule and schedule.sunrise or '--:--', CX - R - 13, CY - 6,
        14, WHITE, 'right', true)
    text_at(cr, 'SUNRISE', CX - R - 13, CY + 11, 8.5, CORAL, 'right', true, .7)
    text_at(cr, schedule and schedule.sunset or '--:--', CX + R + 13, CY - 6,
        14, WHITE, 'left', true)
    text_at(cr, 'SUNSET', CX + R + 13, CY + 11, 8.5, ROSE, 'left', true, .7)
    -- The moving body is SUN by day, NIGHT-PROGRESS INDICATOR by night.
    if schedule then
        local angle = day and (PI + PI * frac) or (PI * frac)
        local x, y = point(angle)
        local c = day and GOLD or BLUE
        local glow = cairo_pattern_create_radial(x, y, 0, x, y, day and 19 or 16)
        cairo_pattern_add_color_stop_rgba(glow, 0, c[1], c[2], c[3], .26)
        cairo_pattern_add_color_stop_rgba(glow, 1, c[1], c[2], c[3], 0)
        cairo_set_source(cr, glow)
        cairo_arc(cr, x, y, day and 19 or 16, 0, 2 * PI)
        cairo_fill(cr)
        cairo_pattern_destroy(glow)
        dot(cr, x, y, day and 5.5 or 4.2, day and { 1, .97, .83 } or { .52, .80, 1 }, 1)
        dot(cr, x, y, 1.7, WHITE, .9)
    end
end

local function lit_shape(cr, cx, cy, r, illum, waxing)
    if illum < .001 then return false end
    -- Start along the lit outside limb; return along an elliptical terminator.
    -- This yields a continuous geometrically accurate apparent phase.
    local n = 70
    local outer_sign = waxing and 1 or -1
    local terminator_sign = waxing and (1 - 2 * illum) or (2 * illum - 1)
    for i = 0, n do
        local y = -r + 2 * r * i / n
        local d = math.sqrt(math.max(0, r * r - y * y))
        local x = cx + outer_sign * d
        if i == 0 then
            cairo_move_to(cr, x, cy + y)
        else
            cairo_line_to(cr, x, cy + y)
        end
    end
    for i = n, 0, -1 do
        local y = -r + 2 * r * i / n
        local d = math.sqrt(math.max(0, r * r - y * y))
        cairo_line_to(cr, cx + terminator_sign * d, cy + y)
    end
    cairo_close_path(cr)
    return true
end

local function draw_moon(cr, phase_name, illum_pct, cycle, illum, day)
    local mx, my, r = CX, CY - 17, 29
    -- Cool outer lunar halo.
    local aura = cairo_pattern_create_radial(mx, my, 6, mx, my, 65)
    cairo_pattern_add_color_stop_rgba(aura, 0, .71, .82, 1, .14 + illum * .12)
    cairo_pattern_add_color_stop_rgba(aura, 1, .71, .82, 1, 0)
    cairo_set_source(cr, aura)
    cairo_arc(cr, mx, my, 65, 0, 2 * PI)
    cairo_fill(cr)
    cairo_pattern_destroy(aura)
    -- Earthshine on the unlit disc, plus subtle blue-grey mare features.
    local shade = cairo_pattern_create_radial(mx - 9, my - 11, 2, mx, my, r * 1.35)
    cairo_pattern_add_color_stop_rgba(shade, 0, .12, .16, .24, 1)
    cairo_pattern_add_color_stop_rgba(shade, 1, .055, .075, .125, 1)
    cairo_arc(cr, mx, my, r, 0, 2 * PI)
    cairo_set_source(cr, shade)
    cairo_fill(cr)
    cairo_pattern_destroy(shade)
    cairo_save(cr)
    cairo_arc(cr, mx, my, r - .5, 0, 2 * PI)
    cairo_clip(cr)
    local texture = { { -.22, -.28, .25, .08 }, { .28, -.16, .20, .075 },
        { .12,  .24,  .28, .06 }, { -.32, .18, .15, .07 } }
    for _, t in ipairs(texture) do
        dot(cr, mx + t[1] * r, my + t[2] * r, t[3] * r, { .56, .64, .78 }, t[4])
    end
    cairo_restore(cr)
    -- Illuminate precisely the waxing or waning portion of the disk.
    cairo_save(cr)
    local waxing = cycle < .5
    if lit_shape(cr, mx, my, r, illum, waxing) then
        cairo_clip(cr)
        local light = cairo_pattern_create_radial(mx + (waxing and 10 or -10), my - 11, 0,
            mx, my, 45)
        cairo_pattern_add_color_stop_rgba(light, 0, 1, .994, .965, day and .94 or 1)
        cairo_pattern_add_color_stop_rgba(light, .73, .86, .89, .95, day and .92 or 1)
        cairo_pattern_add_color_stop_rgba(light, 1, .62, .68, .79, day and .92 or 1)
        cairo_arc(cr, mx, my, r, 0, 2 * PI)
        cairo_set_source(cr, light)
        cairo_fill(cr)
        cairo_pattern_destroy(light)
        -- Smooth maria and crater marks clipped by the phase terminator.
        local maria = { { -.22, -.28, .25, .23 }, { .28, -.16, .20, .18 },
            { .12,  .24,  .28, .19 }, { -.32, .18, .15, .17 },
            { -.03, -.04, .10, .12 }, { .39, .34, .11, .12 } }
        for _, t in ipairs(maria) do
            dot(cr, mx + t[1] * r, my + t[2] * r, t[3] * r, { .28, .35, .47 }, t[4])
        end
        for _, t in ipairs({ { -.43, -.35, .08 }, { .40, -.27, .055 }, { -.1, .42, .07 },
            { .21,  .12,  .06 }, { -.42, .13, .05 } }) do
            cairo_arc(cr, mx + t[1] * r, my + t[2] * r, t[3] * r, 0, 2 * PI)
            color(cr, { .37, .43, .53 }, .22)
            cairo_set_line_width(cr, .75)
            cairo_stroke(cr)
        end
    end
    cairo_restore(cr)
    cairo_arc(cr, mx, my, r, 0, 2 * PI)
    color(cr, { .63, .75, .95 }, .27)
    cairo_set_line_width(cr, .85)
    cairo_stroke(cr)
    text_at(cr, string.upper(phase_name), CX, CY + 34, 12.5, WHITE, 'center', true, .75)
    text_at(cr, string.format('%d%% illuminated · Day %.1f', illum_pct, cycle * 29.53059),
        CX, CY + 51, 10.2, MUTED, 'center')
end

local function add_stop(p, at, c, alpha)
    cairo_pattern_add_color_stop_rgba(p, clamp(at), c[1], c[2], c[3], alpha or 1)
end
local function draw_timeline(cr, now, schedule)
    if schedule then
        text_at(cr, 'DAY', 28, 318, 9.5, GOLD, 'left', true, .9)
        text_at(cr, duration(schedule.day_seconds), 28, 338, 18, WHITE)
        text_at(cr, 'NIGHT', 352, 318, 9.5, BLUE, 'right', true, .9)
        text_at(cr, duration(schedule.night_seconds), 352, 338, 18, WHITE, 'right')
        text_at(cr, (schedule.day and 'DAY ' or 'NIGHT ') ..
            string.format('%d%%', math.floor(schedule.fraction * 100 + .5)),
            CX, 335, 9.8, MUTED, 'center', true, .5)
    else
        text_at(cr, 'WAITING FOR SUNRISE / SUNSET DATA', CX, 330, 10.4, MUTED, 'center')
    end
    local x, y, w, h = 28, 352, 324, 8
    cairo_save(cr)
    rounded(cr, x, y, w, h, 4)
    cairo_clip(cr)
    if schedule then
        local sr = time_fraction(schedule.sunrise_ts)
        local ss = time_fraction(schedule.sunset_ts)
        local bar = cairo_pattern_create_linear(x, 0, x + w, 0)
        add_stop(bar, 0, { .118, .169, .282 })
        add_stop(bar, math.max(0, sr - .04), { .220, .243, .447 })
        add_stop(bar, sr, CORAL)
        add_stop(bar, math.min(1, sr + .05), GOLD)
        add_stop(bar, math.max(0, ss - .05), GOLD)
        add_stop(bar, ss, ROSE)
        add_stop(bar, math.min(1, ss + .04), { .220, .243, .447 })
        add_stop(bar, 1, { .118, .169, .282 })
        cairo_rectangle(cr, x, y, w, h)
        cairo_set_source(cr, bar)
        cairo_fill(cr)
        cairo_pattern_destroy(bar)
    else
        cairo_rectangle(cr, x, y, w, h)
        color(cr, { .18, .22, .32 }, .85)
        cairo_fill(cr)
    end
    cairo_restore(cr)
    color(cr, { 1, 1, 1 }, .11)
    rounded(cr, x, y, w, h, 4)
    cairo_set_line_width(cr, .6)
    cairo_stroke(cr)
    local pos = x + time_fraction(now) * w
    dot(cr, pos, y + h / 2, 8, WHITE, .24)
    rounded(cr, pos - 2, y - 3, 4, h + 6, 2)
    color(cr, WHITE, 1)
    cairo_fill(cr)
end

-- Overlay is drawn only on hover, after the normal dial and timeline.
-- The five labels remain small and unboxed to preserve the idle design.
local function draw_dial_prayer_markers(cr, markers)
    for _, marker in ipairs(markers) do
        local dx, dy = math.cos(marker.angle), math.sin(marker.angle)
        local tint = marker.daytime and GOLD or BLUE
        cairo_set_line_width(cr, 1.3)
        color(cr, tint, .88)
        cairo_move_to(cr, CX + (R - 8) * dx, CY + (R - 8) * dy)
        cairo_line_to(cr, CX + (R + 4) * dx, CY + (R + 4) * dy)
        cairo_stroke(cr)
        dot(cr, CX + (R - 8) * dx, CY + (R - 8) * dy, 2.1, tint, .95)
        text_at(cr, marker.short,
            CX + (R - 23) * dx, CY + (R - 23) * dy + 3,
            9.4, WHITE, 'center', true)
    end
end

local function draw_bar_prayer_markers(cr, markers)
    local x, y, w, h = 28, 352, 324, 8
    for _, marker in ipairs(markers) do
        local mx = x + marker.bar_fraction * w
        local tint = marker.daytime and GOLD or BLUE
        color(cr, tint, .96)
        cairo_set_line_width(cr, 1.4)
        cairo_move_to(cr, mx, y - 3)
        cairo_line_to(cr, mx, y + h + 4)
        cairo_stroke(cr)
        dot(cr, mx, y + h / 2, 2.2, tint, .95)
        text_at(cr, marker.short, mx, y + h + 17, 9.4, WHITE, 'center', true)
    end
end

function conky_main()
    if not conky_window then return end
    local now = os.time()
    local weather = Weather.get(now)
    local schedule = sun_schedule(now, weather)
    update_hover_zones()
    local markers = hover:visible('astrolabe', now) and Markers.build(now, schedule, Prayer)
    local phase_name, illum_pct, cycle, illum = moon_phase(now)
    local surface = Surface.acquire()
    if not surface then return end
    local cr = cairo_create(surface)
    cairo_set_antialias(cr, CAIRO_ANTIALIAS_BEST)
    cairo_scale(cr, SCALE, SCALE)
    -- Window pixels outside the dial and labels remain fully transparent.
    cairo_translate(cr, 18, 18) -- preserve the original Astrolabe layout and padding
    draw_dial(cr, schedule)
    draw_moon(cr, phase_name, illum_pct, cycle, illum, schedule and schedule.day or false)
    draw_timeline(cr, now, schedule)
    if markers then
        draw_dial_prayer_markers(cr, markers)
        draw_bar_prayer_markers(cr, markers)
    end
    cairo_destroy(cr)
    Surface.release(surface)
end
