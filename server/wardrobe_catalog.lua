local Policy = WardrobeCatalog
local session, sequence = nil, 0
local prefix = 'cortex-admin:catalog:'

local function authorized(src)
    return src > 0 and EsAdminServer.hasPermission(src, 'dev.takePhoto')
end

local function tell(src, message)
    print(('[wardrobe-catalog] source=%d %s'):format(src, message))
    if src ~= 0 then TriggerClientEvent(prefix .. 'message', src, message) end
end

local function finish(reason, complete)
    local old = session
    if not old then return end
    session = nil
    if complete then
        SetResourceKvp(Policy.statusKey, json.encode({ at = os.time(), saved = old.saved, skipped = old.skipped }))
    end
    TriggerClientEvent(prefix .. 'stop', old.source, old.id, reason)
    if old.saved > 0 then TriggerClientEvent(prefix .. 'changed', -1) end
    print(('[wardrobe-catalog] %s: source=%d saved=%d skipped=%d'):format(reason, old.source, old.saved, old.skipped))
end

local function command(src, args)
    if type(EsAdminServer) ~= 'table' or type(EsAdminServer.hasPermission) ~= 'function'
        or type(EsAdminServer.allowRequest) ~= 'function' then
        return tell(src, 'Cortex permission service is unavailable. Check server/main.lua startup errors.')
    end
    if src ~= 0 and not authorized(src) then return tell(src, 'Catalog generation requires dev.takePhoto permission.') end
    local mode = args[1] or 'status'
    if mode == 'status' then
        return tell(src, session and ('Running: %d saved, %d cached.'):format(session.saved, session.skipped)
            or ('Idle. Last cutout build: ' .. (GetResourceKvpString(Policy.statusKey) or 'never') .. '. Use /cortex_catalog build.'))
    end
    if mode == 'cancel' then
        if not session then return tell(src, 'No catalog job is running.') end
        finish('Cancelled; saved previews retained.')
        return tell(src, 'Catalog job cancelled.')
    end
    if mode ~= 'build' and mode ~= 'update' and mode ~= 'rebuild' and mode ~= 'sample' then
        return tell(src, 'Usage: cortex_catalog [sample|build|update|rebuild|status|cancel]')
    end
    if src == 0 then return tell(src, 'Run generation from an authorized player client.') end
    if session then return tell(src, 'A catalog job is already running. Use status or cancel.') end
    if not EsAdminServer.allowRequest(src, 'catalog-start', 2, 10000) then return tell(src, 'Wait a few seconds before starting another job.') end
    if GetResourceState('screenshot-basic') ~= 'started' then return tell(src, 'Start screenshot-basic before generating previews.') end
    sequence = sequence + 1
    session = { id = ('%d:%d'):format(os.time(), sequence), source = src, force = mode == 'rebuild' or mode == 'sample',
        saved = 0, skipped = 0, count = 0, step = 0, touched = os.time(), sample = mode == 'sample', seen = {} }
    local current = session
    tell(src, ('Starting %s; waiting for the capture client.'):format(mode))
    TriggerClientEvent(prefix .. 'start', src, current.id, mode)
    -- No idle polling: this watchdog exists only for the current job.
    CreateThread(function()
        while session == current do
            Wait(5000)
            if session == current and (os.time() - current.touched > 90 or not authorized(current.source)) then
                finish('Timed out or permission revoked; run build to resume.')
            end
        end
    end)
end

RegisterCommand('cortex_catalog', command, false)

-- Explicit F8/chat bridge: client receipt is immediate; authority stays here.
RegisterNetEvent(prefix .. 'command', function(request, mode)
    local src = source
    if type(request) ~= 'number' or request % 1 ~= 0 or request < 1 or request > 2147483647
        or type(mode) ~= 'string' or #mode > 16 then return end
    TriggerClientEvent(prefix .. 'commandAck', src, request)
    if type(EsAdminServer) == 'table' and type(EsAdminServer.allowRequest) == 'function'
        and not EsAdminServer.allowRequest(src, 'catalog-command', 5, 2000) then
        return tell(src, 'Too many catalog commands; wait a moment.')
    end
    command(src, { mode })
end)

local function owns(src, id)
    return session and session.source == src and session.id == id and authorized(src)
end

RegisterNetEvent(prefix .. 'prepare', function(id, step, item)
    local src = source
    if not owns(src, id) or not EsAdminServer.allowRequest(src, 'catalog-write', 20, 1000) then return end
    local key = Policy.key(item)
    if not key or session.pending or step ~= session.step + 1 or session.seen[key]
        or session.count >= Policy.maxItems then return finish('Invalid catalog sequence.') end
    session.step, session.touched = step, os.time()
    session.count = session.count + 1
    session.seen[key] = true
    local cached = not session.force and GetResourceKvpString(key)
    local skip = cached and Policy.validStored(cached) or false
    if skip then session.skipped = session.skipped + 1
    else session.pending = { key = key, step = step } end
    TriggerClientEvent(prefix .. 'prepared', src, id, step, skip)
end)

RegisterNetEvent(prefix .. 'save', function(id, step, data)
    local src = source
    if not owns(src, id) or not session.pending or session.pending.step ~= step then return end
    if not Policy.validStored(data) then return finish('Invalid or oversized thumbnail.') end
    SetResourceKvp(session.pending.key, data)
    -- Confirm persistence before acknowledging this item as complete.
    if GetResourceKvpString(session.pending.key) ~= data then return finish('Thumbnail persistence failed.') end
    session.pending, session.touched, session.saved = nil, os.time(), session.saved + 1
    TriggerClientEvent(prefix .. 'saved', src, id, step)
end)

RegisterNetEvent(prefix .. 'done', function(id)
    if not owns(source, id) or session.pending or session.count == 0 then return end
    finish(('Finished: %d saved, %d cached.'):format(session.saved, session.skipped), not session.sample)
end)

RegisterNetEvent(prefix .. 'abort', function(id)
    if owns(source, id) then finish('Capture stopped; saved previews retained.') end
end)

RegisterNetEvent(prefix .. 'read', function(request, item)
    local src = source
    if type(request) ~= 'number' or request % 1 ~= 0 or request < 1 or request > 2147483647 then return end
    local result = { ok = false, error = 'forbidden' }
    if EsAdminServer.hasPermission(src, 'player.setAppearance') then
        if not EsAdminServer.allowRequest(src, 'catalog-read', 72, 5000) then
            result.error = 'rate_limited'
        else
            local key = Policy.key(item)
            if key then
                local cached = GetResourceKvpString(key)
                result = { ok = true, empty = cached == Policy.emptyMarker }
                if Policy.validImage(cached) then result.photo = cached end
            else result.error = 'invalid_item' end
        end
    end
    TriggerLatentClientEvent(prefix .. 'photo', src, 256000, request, result)
end)

AddEventHandler('playerDropped', function()
    if session and session.source == source then finish('Capture client disconnected; saved previews retained.') end
end)

print('[wardrobe-catalog] Server ready (cutout-4). Transparent catalog v2. Command: cortex_catalog status')
