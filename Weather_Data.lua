-- Shared weather cache reader for independent Date, Weather and Sun windows.
-- Loads the cache without blocking; refreshes in a background Python worker.
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './'
local settings = dofile(base .. 'Settings.lua')
local home = assert(os.getenv('HOME'), 'HOME is not set')
local cache_home = os.getenv('XDG_CACHE_HOME')
if not cache_home or cache_home == '' then cache_home = home .. '/.cache' end
local cache_dir = cache_home .. '/conky-sun-weather'
local cache_file = cache_dir .. '/weather.cache'
local M = {}
local last_loaded = 0
local last_attempt = 0
local data = nil
local REQUIRED = {'temperature','high','low','humidity','code','is_day','fetched',
                  'yesterday_sunset','sunrise','sunset','tomorrow_sunrise',
                  'forecast_valid_until'}
local function quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function load()
    local file = io.open(cache_file, 'r')
    if not file then return nil end
    if file:read('*l') ~= 'CONKY_SUN_WEATHER_V2' then file:close(); return nil end
    local result = {}
    for line in file:lines() do
        local k, v = line:match('^([%w_]+)=(.*)$')
        if not k or result[k] then file:close(); return nil end
        result[k] = v
    end
    file:close()
    if result.signature ~= settings.location_signature() then return nil end
    for _, k in ipairs(REQUIRED) do
        local n = tonumber(result[k])
        if not n or n ~= n then return nil end
        result[k] = n
    end
    if result.humidity < 0 or result.humidity > 100 then return nil end
    -- Reject incomplete forecast caches; no legacy schema or migration path.
    result.forecast = {}
    local valid_days = { Mon=true, Tue=true, Wed=true, Thu=true,
                         Fri=true, Sat=true, Sun=true }
    for i = 1, 3 do
        local prefix = 'forecast_' .. i .. '_'
        local day = result[prefix .. 'day']
        local hi = tonumber(result[prefix .. 'high'])
        local lo = tonumber(result[prefix .. 'low'])
        local code = tonumber(result[prefix .. 'code'])
        if not valid_days[day] then return nil end
        if not hi or not lo or not code or hi ~= hi or lo ~= lo or code ~= code
            or hi < -110 or hi > 70 or lo < -110 or lo > 70
            or hi < lo or code < 0 or code > 99 then return nil end
        result.forecast[i] = { day = day, high = hi, low = lo, code = code }
    end
    if result.yesterday_sunset >= result.sunrise or result.sunrise >= result.sunset
       or result.sunset >= result.tomorrow_sunrise then return nil end
    if not (result.sunrise_label and result.sunset_label) then return nil end
    return result
end

function M.get(now)
    now = now or os.time()
    if now - last_loaded >= 8 or not data then
        last_loaded = now
        local refreshed = load()
        if refreshed then data = refreshed
        elseif data and data.signature ~= settings.location_signature() then data = nil end
    end
    local ttl = math.floor(settings.number('behavior', 'weather_refresh_minutes', 20) * 60)
    local stale = not data or (now - data.fetched > ttl)
                  or (data.fetched > now + 120) or (now >= data.forecast_valid_until)
    if stale and now - last_attempt >= 240 then
        last_attempt = now
        local cmd = 'mkdir -p ' .. quote(cache_dir) .. ' && python3 ' ..
             quote(base .. 'weather_fetch.py') .. ' >>' .. quote(cache_dir .. '/fetch.log') .. ' 2>&1 &'
        os.execute(cmd)
    end
    -- The shared cache may still contain yesterday's data if a fetch fails.
    -- Keep current conditions, but never show forecast labels for past days.
    if data and now >= data.forecast_valid_until then data.forecast = nil end
    return data
end

return M
