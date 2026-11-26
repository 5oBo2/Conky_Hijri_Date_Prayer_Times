-- Task 15: Shared Lua access to the cached curated AlAdhan event.
local root = (debug.getinfo(1, 'S').source:match('^@(.*/)') or './tests/') .. '../'
local real_getenv, real_execute = os.getenv, os.execute
local temp_home = os.tmpname()
os.remove(temp_home)
os.execute = function(command)
    return real_execute(command)
end
os.execute('mkdir -p ' .. string.format('%q', temp_home))
os.getenv = function(key)
    if key == 'HOME' then return temp_home end
    if key == 'XDG_CACHE_HOME' then return nil end
    return real_getenv(key)
end
local Prayer_Data = dofile(root .. 'lib/Prayer_Data.lua')
os.getenv = real_getenv
local cache_dir = Prayer_Data.cache_dir
os.execute('mkdir -p ' .. string.format('%q', cache_dir))
local cache_path = cache_dir .. '/next-hijri-holiday.cache'

local function write_event(fetched_at, name, hijri_date, gregorian_date,
                           event_key, base_year)
    local file = assert(io.open(cache_path, 'wb'))
    file:write('CONKY_HIJRI_EVENT_V2\n')
    file:write('fetched_at=' .. tostring(fetched_at) .. '\n')
    file:write('base_hijri_year=' .. tostring(base_year or 1448) .. '\n')
    file:write('event_key=' .. (event_key or 'isra_and_miraj') .. '\n')
    file:write('name=' .. (name or 'Isra and Mi\'raj') .. '\n')
    file:write('hijri_date=' .. (hijri_date or '27-07-1448') .. '\n')
    file:write('gregorian_date=' .. (gregorian_date or '2027-01-05') .. '\n')
    file:write('calendar_method=HJCoSA\n')
    file:close()
end

-- Fresh curated data is available only while the event is on/after the
-- widget's displayed Hijri source date.
write_event(1000)
local event = Prayer_Data.get_next_hijri_event(2000, '2026-11-26')
assert(event and event.name == 'Isra and Mi\'raj')
assert(event.event_key == 'isra_and_miraj')
assert(event.hijri_date == '27-07-1448')
assert(event.gregorian_date == '2027-01-05')
assert(event.base_hijri_year == 1448)
assert(Prayer_Data.get_next_hijri_event(2000, '2027-01-06') == nil,
    'an event earlier than the displayed Hijri date must not be presented as upcoming')
assert(Prayer_Data.get_next_hijri_event(1000 + 12*60*60 + 1, '2026-11-26') == nil,
    'expired event cache must not be presented')

-- The Lua cache reader independently enforces the curated allowlist.
write_event(1000, 'Urs of an individual', '22-06-1448', '2026-12-02',
            'individual_urs', 1448)
assert(Prayer_Data.get_next_hijri_event(2000, '2026-11-26') == nil,
    'an excluded Urs must never be accepted from the event cache')
write_event(1000, 'Ashura', '10-01-1448', '2026-06-25',
            'isra_and_miraj', 1448)
assert(Prayer_Data.get_next_hijri_event(2000, '2026-11-26') == nil,
    'an approved key with a mismatched name/date must be rejected')
write_event(1000, 'Isra and Mi\'raj', '27-07-1448', '2027-01-05',
            'isra_and_miraj', 1448)
assert(Prayer_Data.get_next_hijri_event(2000, '2026-11-26') ~= nil,
    'a matching canonical event must remain accepted')

-- A missing event cache requests both the source Hijri year and displayed date.
os.remove(cache_path)
local commands = {}
os.execute = function(command)
    commands[#commands+1] = command
    return true
end
Prayer_Data.ensure_dates({}, 20000, '2026-11-26', 1448)
assert(#commands == 2, 'ensure_dates should create cache dir and launch the worker')
assert(commands[2]:find('%-%-event'),
    'missing event cache should request a curated event fetch')
assert(commands[2]:find('%-%-hijri%-year')
    and commands[2]:find('1448'),
    'worker must receive the current Hijri year')
assert(commands[2]:find('%-%-displayed%-date'),
    'worker must receive the widget displayed date')

-- A cached event from a different base year is refreshed even before TTL expiry.
write_event(20000, 'Isra and Mi\'raj', '27-07-1448', '2027-01-05',
            'isra_and_miraj', 1448)
commands = {}
Prayer_Data.ensure_dates({}, 21000, '2027-06-07', 1449)
assert(#commands == 2)
assert(commands[2]:find('%-%-hijri%-year')
    and commands[2]:find('1449'),
    'Hijri year rollover must refresh the event calendar: ' .. tostring(commands[2]))

-- A passed event gets a forced refresh, but only after the one-hour guard.
write_event(2000, 'Isra and Mi\'raj', '27-07-1448', '2026-11-25',
            'isra_and_miraj', 1448)
commands = {}
Prayer_Data.ensure_dates({}, 30000, '2026-11-26', 1448)
assert(#commands == 2)
assert(commands[2]:find('%-%-event%-force'),
    'a cached event behind the displayed Hijri date should force a refresh')

-- No event-calendar request is launched until the prayer cache supplies a
-- Hijri year. This avoids guessing a Hijri year from the Gregorian year.
commands = {}
os.remove(cache_path)
Prayer_Data.ensure_dates({}, 40000, '2026-11-26', nil)
assert(#commands == 0,
    'event worker must wait until a reliable current Hijri year is available')

os.execute = real_execute
os.remove(cache_path)
os.execute('rm -rf ' .. string.format('%q', temp_home))
print('Task 15: curated event cache freshness, year rollover, displayed-date selection and background refresh passed')
