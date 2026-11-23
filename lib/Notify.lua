-- Task 7: shared desktop notifications, independent of the Cairo draw backend.
-- Each key is claimed by one atomic mkdir, so separate Conky processes and
-- restarts cannot repeat the same event. The sent.cache file is an audit log;
-- marker directories are the source of truth for deduplication.
local M = {}
local home = assert(os.getenv('HOME'), 'HOME is not set')
local cache_home = os.getenv('XDG_CACHE_HOME')
if not cache_home or cache_home == '' then cache_home = home .. '/.cache' end
M.cache_dir = cache_home .. '/conky-notifications'

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end
local function success(command)
    local ok = os.execute(command)
    return ok == true or ok == 0
end

-- A notification is due only if the running widget actually witnessed the
-- threshold crossing. Cold startup and large wall-clock jumps are ignored.
function M.crossed(last_check, now, threshold, grace)
    return type(last_check) == 'number' and type(now) == 'number'
        and type(threshold) == 'number' and now >= last_check
        and now - last_check <= 120
        and last_check < threshold and threshold <= now
        and now - threshold <= (grace or 15)
end

local notify_available
local did_prune = false
local function available()
    if notify_available == nil then
        notify_available = success('command -v notify-send >/dev/null 2>&1')
    end
    return notify_available
end

local function hex_key(key)
    return (key:gsub('.', function(c) return string.format('%02x', string.byte(c)) end))
end

local function prune(now)
    if did_prune then return end
    did_prune = true
    -- Old markers expire after 60 days. Only empty, hex-named directories
    -- live here; do not recursively delete any other user files.
    os.execute('find ' .. shell_quote(M.cache_dir .. '/sent') ..
        ' -mindepth 1 -maxdepth 1 -type d -mtime +60 -empty -delete' ..
        ' >/dev/null 2>&1 &')
    -- Compact the human-readable audit log on a best-effort basis.
    local path = M.cache_dir .. '/sent.cache'
    local file = io.open(path, 'r')
    if not file then return end
    local retained = {}
    for line in file:lines() do
        local timestamp = tonumber(line:match('^(%d+)\t'))
        if timestamp and timestamp >= now - 60 * 86400 and timestamp <= now + 86400 then
            retained[#retained + 1] = line
        end
    end
    file:close()
    -- Append-only log is informational, never used for deduplication. Use a
    -- distinct temporary file and rename rather than truncate in-place.
    local tmp = path .. '.' .. tostring(now) .. '.' .. tostring(math.random(1000000)) .. '.tmp'
    local out = io.open(tmp, 'w')
    if out then
        if #retained > 0 then out:write(table.concat(retained, '\n'), '\n') end
        out:close()
        os.rename(tmp, path)
    end
end

function M.send_once(key, title, message, now)
    if type(key) ~= 'string' or #key < 1 or #key > 110
       or key:find('[\n\r\t]') then return false end
    if type(title) ~= 'string' or type(message) ~= 'string' then return false end
    if not available() then return false end
    now = now or os.time()
    local dir = M.cache_dir .. '/sent'
    if not success('mkdir -p ' .. shell_quote(dir) .. ' >/dev/null 2>&1') then return false end
    prune(now)
    local marker = dir .. '/' .. hex_key(key)
    -- mkdir is atomic: only one widget/process can claim an event key.
    if not success('mkdir ' .. shell_quote(marker) .. ' >/dev/null 2>&1') then
        return false
    end
    local audit = io.open(M.cache_dir .. '/sent.cache', 'a')
    if audit then
        audit:write(tostring(now), '\t', key, '\n')
        audit:close()
    end
    -- The display command is detached; a slow D-Bus server never blocks a
    -- Conky drawing frame. Shell-quote both dynamic strings (no interpolation).
    os.execute('notify-send --app-name=Conky ' .. shell_quote(title) .. ' ' ..
        shell_quote(message) .. ' >/dev/null 2>&1 &')
    return true
end

return M
