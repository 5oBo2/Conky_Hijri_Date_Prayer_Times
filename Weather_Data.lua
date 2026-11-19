-- Shared weather cache reader for both new Conky windows.
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
local last_fetched = 0
local last_attempt = 0
local data = nil
local REQUIRED = {'temperature','high','low','humidity','code','is_day','fetched',
                  'yesterday_sunset','sunrise','sunset','tomorrow_sunrise'}
local function quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function load()
    local file = io.open(cache_file, 'r')
    if not file then return nil end
    if file:read('*l') ~= 'CONKY_SUN_WEATHER_V1' then file:close(); return nil end
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
    local stale = not data or (now - data.fetched > ttl) or (data.fetched > now + 120)
    if stale and now - last_attempt >= 240 then
        last_attempt = now
        local cmd = 'mkdir -p ' .. quote(cache_dir) .. ' && python3 ' ..
             quote(base .. 'weather_fetch.py') .. ' >>' .. quote(cache_dir .. '/fetch.log') .. ' 2>&1 &'
        os.execute(cmd)
    end
    return data
end

return M
