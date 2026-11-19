-- Shared, non-blocking cache access for both Conky widgets.
-- Simple, validated line-based cache; no third-party Lua JSON library needed.
local settings = dofile((debug.getinfo(1, 'S').source:match('^@(.*/)') or './') .. 'Settings.lua')
local M = {}

local source = debug.getinfo(1, 'S').source
M.script_dir = source:match('^@(.*/)') or './'
local home = assert(os.getenv('HOME'), 'HOME is not set')
local xdg_cache = os.getenv('XDG_CACHE_HOME')
if not xdg_cache or xdg_cache == '' then xdg_cache = home .. '/.cache' end
M.cache_dir = xdg_cache .. '/conky-prayer-times'

local loaded = {}
local next_launch_at = 0

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

function M.shift_date(timestamp, days)
    local dt = os.date('*t', timestamp)
    return os.date('%Y-%m-%d', os.time({
        year = dt.year, month = dt.month, day = dt.day + days,
        hour = 12, min = 0, sec = 0
    }))
end

function M.date_plus(date, days)
    local y, m, d = date:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    if not y then return nil end
    return M.shift_date(os.time({
        year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = 12, min = 0, sec = 0
    }), days)
end

function M.minutes(s)
    if type(s) ~= 'string' then return nil end
    local h, m = s:match('^%s*(%d%d?):(%d%d)')
    h, m = tonumber(h), tonumber(m)
    if not h or not m or h > 23 or m > 59 then return nil end
    return h * 60 + m
end

function M.timestamp(date, time_string)
    local y, m, d = date:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    local minutes = M.minutes(time_string)
    if not y or not minutes then return nil end
    return os.time({year = tonumber(y), month = tonumber(m), day = tonumber(d),
                    hour = math.floor(minutes / 60), min = minutes % 60, sec = 0})
end

local REQUIRED = {'Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha', 'Midnight'}

function M.get(date)
    if not date or not date:match('^%d%d%d%d%-%d%d%-%d%d$') then return nil end
    if loaded[date] then return loaded[date] end
    local f = io.open(M.cache_dir .. '/' .. date .. '.cache', 'rb')
    if not f then return nil end
    local header = f:read('*l')
    if header ~= 'CONKY_PRAYER_V1' then f:close(); return nil end
    local fields = {}
    for line in f:lines() do
        local k, v = line:match('^([%w_]+)=(.*)$')
        if not k or fields[k] then f:close(); return nil end
        fields[k] = v
    end
    f:close()
    if fields.signature ~= settings.location_signature() or fields.date ~= date then
        return nil
    end
    local timings = {}
    for _, name in ipairs(REQUIRED) do
        if not M.minutes(fields[name]) then return nil end
        timings[name] = fields[name]
    end
    local day, month, year = tonumber(fields.hijri_day),
                             tonumber(fields.hijri_month), tonumber(fields.hijri_year)
    if not day or day < 1 or day > 30 or not month or month < 1 or month > 12
       or not year or year < 1 then return nil end
    local data = {
        timings = timings,
        date = {hijri = {
            day = tostring(day), month = {number = month}, year = tostring(year)
        }}
    }
    loaded[date] = data
    return data
end

-- Start a worker only if a date is missing. Never block Conky's drawing loop.
-- Multiple Conky instances share the worker's OS-level file lock.
function M.ensure_dates(dates, now)
    local missing, seen = {}, {}
    for _, date in ipairs(dates) do
        if date and not seen[date] then
            seen[date] = true
            if not M.get(date) then missing[#missing + 1] = date end
        end
    end
    if #missing == 0 or now < next_launch_at then return end
    next_launch_at = now + 90 -- failures are retried later, not in a blocking loop
    local args = {}
    for _, date in ipairs(missing) do args[#args + 1] = shell_quote(date) end
    -- Ensure log redirection succeeds on first launch.
    os.execute('mkdir -p ' .. shell_quote(M.cache_dir))
    local command = 'python3 ' .. shell_quote(M.script_dir .. 'prayer_fetch.py') ..
                    ' ' .. table.concat(args, ' ') .. ' >>' .. shell_quote(M.cache_dir .. '/fetch.log') .. ' 2>&1 &'
    os.execute(command)
end

function M.hms(seconds)
    local total_minutes = math.max(0, math.floor(seconds / 60))
    return string.format('%02d', math.floor(total_minutes / 60)),
           string.format('%02d', total_minutes % 60)
end

return M
