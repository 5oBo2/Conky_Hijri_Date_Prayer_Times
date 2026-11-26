-- Shared, non-blocking cache access for both Conky widgets.
-- Simple, validated line-based cache; no third-party Lua JSON library needed.
local base = debug.getinfo(1, 'S').source:match('^@(.*/)') or './lib/'
local settings = dofile(base .. 'Settings.lua')
local M = {}

M.script_dir = base .. '../workers/'
local home = assert(os.getenv('HOME'), 'HOME is not set')
local xdg_cache = os.getenv('XDG_CACHE_HOME')
if not xdg_cache or xdg_cache == '' then xdg_cache = home .. '/.cache' end
M.cache_dir = xdg_cache .. '/conky-prayer-times'

local loaded = {}
local next_launch_at = 0
local EVENT_CACHE = M.cache_dir .. '/next-hijri-holiday.cache'
local EVENT_CACHE_TTL = 12 * 60 * 60
local EVENT_PASSED_REFRESH_SECONDS = 60 * 60

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

local REQUIRED = {'Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha', 'Midnight', 'Lastthird'}

-- Defense in depth: the worker creates these canonical records, and Lua
-- rejects any cache entry that does not match the same approved rule.
local HIJRI_EVENT_RULES = {
    islamic_new_year = {name='Islamic New Year', day=1, month=1},
    ashura = {name='Ashura', day=10, month=1},
    mawlid_al_nabi = {name='Mawlid al-Nabi', day=12, month=3},
    isra_and_miraj = {name='Isra and Mi\'raj', day=27, month=7},
    laylat_al_baraat = {name='Laylat al-Bara\'at', day=15, month=8},
    ramadan_begins = {name='Ramadan begins', day=1, month=9},
    eid_al_fitr = {name='Eid al-Fitr', day=1, month=10},
    hajj_begins = {name='Hajj begins', day=8, month=12},
    day_of_arafah = {name='Day of Arafah', day=9, month=12},
    eid_al_adha = {name='Eid al-Adha', day=10, month=12},
}

function M.get(date)
    if not date or not date:match('^%d%d%d%d%-%d%d%-%d%d$') then return nil end
    if loaded[date] then return loaded[date] end
    local f = io.open(M.cache_dir .. '/' .. date .. '.cache', 'rb')
    if not f then return nil end
    local header = f:read('*l')
    if header ~= 'CONKY_PRAYER_V2' then f:close(); return nil end
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

local function read_event_cache()
    local f = io.open(EVENT_CACHE, 'rb')
    if not f then return nil end
    local header = f:read('*l')
    if header ~= 'CONKY_HIJRI_EVENT_V2' then f:close(); return nil end
    local fields = {}
    for line in f:lines() do
        local key, value = line:match('^([%w_]+)=(.*)$')
        if not key or fields[key] then f:close(); return nil end
        fields[key] = value
    end
    f:close()
    local fetched_at = tonumber(fields.fetched_at)
    local name = fields.name
    local hijri_date = fields.hijri_date
    local gregorian_date = fields.gregorian_date
    local method = fields.calendar_method
    local event_key = fields.event_key
    local base_hijri_year = tonumber(fields.base_hijri_year)
    local rule = event_key and HIJRI_EVENT_RULES[event_key]
    if not fetched_at or not name or not hijri_date or not gregorian_date
       or method ~= 'HJCoSA' or not rule
       or name ~= rule.name or not base_hijri_year
       or base_hijri_year < 1 or base_hijri_year % 1 ~= 0 then
        return nil
    end
    local hday, hmonth, hyear = hijri_date:match('^(%d%d)%-(%d%d)%-(%d%d%d%d)$')
    if not hday or tonumber(hday) ~= rule.day
       or tonumber(hmonth) ~= rule.month
       or tonumber(hyear) < base_hijri_year
       or tonumber(hyear) > base_hijri_year + 1 then return nil end
    if not gregorian_date:match('^%d%d%d%d%-%d%d%-%d%d$')
       or M.date_plus(gregorian_date, 0) ~= gregorian_date then return nil end
    return {
        event_key = event_key,
        name = name,
        hijri_date = hijri_date,
        gregorian_date = gregorian_date,
        calendar_method = method,
        base_hijri_year = base_hijri_year,
        fetched_at = fetched_at,
    }
end

function M.get_next_hijri_event(now, displayed_date)
    now = now or os.time()
    local event = read_event_cache()
    if not event or now < event.fetched_at
       or now - event.fetched_at > EVENT_CACHE_TTL then return nil end
    -- displayed_date already includes the widget's Hijri offset and Maghrib
    -- rollover, so compare against it rather than the raw civil date.
    if displayed_date and event.gregorian_date < displayed_date then return nil end
    return event
end

-- Start a worker when the event cache is missing, stale, or has fallen behind
-- the Hijri date currently displayed by the widget. The draw loop never waits.
-- Event refreshes share the existing prayer worker and OS-level file lock.
function M.ensure_dates(dates, now, displayed_date, hijri_year)
    local missing, seen = {}, {}
    for _, date in ipairs(dates) do
        if date and not seen[date] then
            seen[date] = true
            if not M.get(date) then missing[#missing + 1] = date end
        end
    end
    local cached_event = read_event_cache()
    local event_year_changed = cached_event and hijri_year
        and cached_event.base_hijri_year ~= tonumber(hijri_year)
    local event_expired = not cached_event or now < cached_event.fetched_at
        or now - cached_event.fetched_at > EVENT_CACHE_TTL
        or event_year_changed
    local event_passed = cached_event and displayed_date
        and cached_event.gregorian_date < displayed_date
    local refresh_passed_event = event_passed
        and now - cached_event.fetched_at >= EVENT_PASSED_REFRESH_SECONDS
    -- Do not fetch the event calendar until the current prayer cache provides
    -- a Hijri year. The worker needs that year to request this and next year.
    local fetch_event = hijri_year ~= nil
        and (event_expired or refresh_passed_event)
    if #missing == 0 and not fetch_event then return end
    if now < next_launch_at then return end
    next_launch_at = now + 90 -- failures are retried later, not in a blocking loop
    local args = {}
    for _, date in ipairs(missing) do args[#args + 1] = shell_quote(date) end
    if fetch_event then
        args[#args + 1] = '--event'
        args[#args + 1] = '--hijri-year'
        args[#args + 1] = shell_quote(tonumber(hijri_year))
        args[#args + 1] = '--displayed-date'
        args[#args + 1] = shell_quote(displayed_date or os.date('%Y-%m-%d', now))
        if event_passed then args[#args + 1] = '--event-force' end
    end
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
