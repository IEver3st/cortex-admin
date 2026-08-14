EsAdminVmenuFallback = EsAdminVmenuFallback or {}

local snapshotCache = {
    expiresAt = 0,
    data = nil,
}

local requestRateBySource = {}
local REQUEST_WINDOW_MS = 10000
local REQUEST_LIMIT = 4
local VMENU_DISK_PREFIX = 'res:vMenu:'
local MAX_KEY_BYTES = 192
local MAX_DOMAIN_ENTRIES = 1024
local MAX_JSON_BYTES = 1024 * 1024

local isWindows = package and package.config and package.config:sub(1, 1) == '\\' or false

local function trim(value)
    if type(value) ~= 'string' then return '' end
    return (value:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function joinPath(base, name)
    if type(base) ~= 'string' or base == '' then return name end
    local separator = isWindows and '\\' or '/'
    if base:sub(-1) == '\\' or base:sub(-1) == '/' then return base .. name end
    return base .. separator .. name
end

local function getKvsPath()
    local configured = Config.VmenuFallback and trim(Config.VmenuFallback.kvsPath) or ''
    if configured ~= '' then return configured end

    local convarPath = trim(GetConvar('cortex-admin_vmenu_kvs_path', ''))
    if convarPath ~= '' then return convarPath end

    local appData = trim(os.getenv('APPDATA'))
    if appData ~= '' then return joinPath(appData, 'CitizenFX\\kvs') end

    local homePath = trim(os.getenv('HOME'))
    if homePath ~= '' then return joinPath(homePath, '.config/CitizenFX/kvs') end
    return ''
end

local function unpackNumber(format, value, position)
    local ok, decoded, nextPosition = pcall(string.unpack, format, value, position)
    if not ok then return nil end
    return decoded, nextPosition
end

-- CitizenFX stores each KVP value as a MessagePack scalar. vMenu itself writes
-- JSON strings for complex values and strings/integers for preferences. Decode
-- only bounded scalar wrappers here; JSON interpretation remains a separate step.
local function decodeKvpScalar(value)
    if type(value) ~= 'string' or value == '' then return nil, 'empty_value' end
    local marker = value:byte(1)
    if not marker then return nil, 'empty_value' end

    if marker <= 0x7f then
        if #value ~= 1 then return nil, 'trailing_scalar_data' end
        return marker
    end
    if marker >= 0xe0 then
        if #value ~= 1 then return nil, 'trailing_scalar_data' end
        return marker - 0x100
    end
    if marker >= 0xa0 and marker <= 0xbf then
        local length = marker & 0x1f
        if #value ~= length + 1 then return nil, 'invalid_fixstr' end
        return value:sub(2)
    end

    if marker == 0xc0 then return nil, 'nil_value' end
    if marker == 0xc2 or marker == 0xc3 then
        if #value ~= 1 then return nil, 'trailing_scalar_data' end
        return marker == 0xc3
    end

    local numericFormats = {
        [0xca] = '>f', [0xcb] = '>d',
        [0xcc] = '>I1', [0xcd] = '>I2', [0xce] = '>I4', [0xcf] = '>I8',
        [0xd0] = '>i1', [0xd1] = '>i2', [0xd2] = '>i4', [0xd3] = '>i8',
    }
    local format = numericFormats[marker]
    if format then
        local decoded, nextPosition = unpackNumber(format, value, 2)
        if decoded == nil or nextPosition ~= #value + 1 then return nil, 'invalid_number' end
        if type(decoded) == 'number' and (decoded ~= decoded or decoded == math.huge or decoded == -math.huge) then
            return nil, 'non_finite_number'
        end
        return decoded
    end

    local length, startPosition
    if marker == 0xd9 then
        length = value:byte(2)
        startPosition = 3
    elseif marker == 0xda then
        length = unpackNumber('>I2', value, 2)
        startPosition = 4
    elseif marker == 0xdb then
        length = unpackNumber('>I4', value, 2)
        startPosition = 6
    end
    if length ~= nil then
        if length < 0 or length > MAX_JSON_BYTES or startPosition + length - 1 ~= #value then
            return nil, 'invalid_string'
        end
        return value:sub(startPosition)
    end

    return nil, ('unsupported_msgpack_%02x'):format(marker)
end

local function decodeJsonString(value)
    if type(value) ~= 'string' or value == '' or #value > MAX_JSON_BYTES then return nil end
    local first = value:match('^%s*(.)')
    if first ~= '{' and first ~= '[' then return nil end
    local ok, decoded = pcall(json.decode, value)
    if not ok or type(decoded) ~= 'table' then return nil end
    return decoded
end

local function safeKey(value)
    if type(value) ~= 'string' or value == '' or #value > MAX_KEY_BYTES then return nil end
    if value:find('[%z\1-\31\127]') then return nil end
    return value
end

local function appendEntry(list, key, data)
    if #list >= MAX_DOMAIN_ENTRIES then return false end
    list[#list + 1] = { key = key, data = data }
    return true
end

local function sortEntries(list)
    table.sort(list, function(first, second)
        return (first.key or ''):lower() < (second.key or ''):lower()
    end)
end

local function emptySnapshot(reason, kvsPath, parser)
    return {
        ok = false,
        reason = reason,
        kvsPath = kvsPath,
        peds = {},
        mpPeds = {},
        nonMpPeds = {},
        vehicles = {},
        pedCategories = {},
        vehicleCategories = {},
        weaponLoadouts = {},
        settings = {},
        defaultKey = nil,
        defaultLoadout = nil,
        temporaryLoadout = nil,
        parser = parser or {},
        readOnly = true,
        localHostOnly = true,
        scope = 'server_host',
    }
end

local function buildSnapshot(kvsPath)
    if not Config.VmenuFallback or Config.VmenuFallback.enabled == false then
        return emptySnapshot('disabled', kvsPath)
    end
    if kvsPath == '' then return emptySnapshot('kvs_path_unavailable', kvsPath) end
    if not EsAdminLevelDb or type(EsAdminLevelDb.readNamespace) ~= 'function' then
        return emptySnapshot('leveldb_reader_unavailable', kvsPath)
    end

    local okRead, values, parser = pcall(EsAdminLevelDb.readNamespace, kvsPath, VMENU_DISK_PREFIX)
    if not okRead then return emptySnapshot('filesystem_unavailable', kvsPath, { error = tostring(values) }) end
    if type(values) ~= 'table' then
        return emptySnapshot(type(parser) == 'table' and parser.reason or 'read_failed', kvsPath, parser)
    end

    local snapshot = emptySnapshot('empty', kvsPath, parser)
    local invalid = 0
    local decodedCount = 0
    local truncated = false

    for rawKey, rawValue in pairs(values) do
        local key = safeKey(rawKey)
        local scalar, scalarReason = decodeKvpScalar(rawValue)
        if not key or (scalar == nil and scalarReason ~= 'nil_value') then
            invalid = invalid + 1
        else
            decodedCount = decodedCount + 1
            local complex = decodeJsonString(scalar)
            local appended = true

            if key:sub(1, 7) == 'mp_ped_' and type(complex) == 'table' then
                appended = appendEntry(snapshot.mpPeds, key, complex)
            elseif key:sub(1, 4) == 'ped_' and type(complex) == 'table' then
                appended = appendEntry(snapshot.nonMpPeds, key, complex)
            elseif key:sub(1, 4) == 'veh_' and type(complex) == 'table' then
                appended = appendEntry(snapshot.vehicles, key, complex)
            elseif key:sub(1, 22) == 'mp_character_category_' and type(complex) == 'table' then
                appended = appendEntry(snapshot.pedCategories, key, complex)
            elseif key:sub(1, 19) == 'saved_veh_category_' and type(complex) == 'table' then
                appended = appendEntry(snapshot.vehicleCategories, key, complex)
            elseif key:sub(1, 34) == 'vmenu_string_saved_weapon_loadout_' and type(complex) == 'table' then
                appended = appendEntry(snapshot.weaponLoadouts, key, complex)
            elseif key == 'vmenu_string_default_loadout' then
                snapshot.defaultLoadout = scalar
            elseif key == 'vmenu_temp_weapons_loadout_before_respawn' then
                snapshot.temporaryLoadout = complex or scalar
            elseif key == 'vmenu_default_character' and type(scalar) == 'string' then
                snapshot.defaultKey = safeKey(scalar)
            elseif key:sub(1, 9) == 'settings_' then
                local settingKey = safeKey(key:sub(10))
                if settingKey and snapshot.settings[settingKey] == nil then
                    if type(scalar) == 'string' then
                        local lowered = scalar:lower()
                        if lowered == 'true' then scalar = true elseif lowered == 'false' then scalar = false end
                    end
                    snapshot.settings[settingKey] = scalar
                end
            end

            if not appended then truncated = true end
        end
    end

    sortEntries(snapshot.mpPeds)
    sortEntries(snapshot.nonMpPeds)
    sortEntries(snapshot.vehicles)
    sortEntries(snapshot.pedCategories)
    sortEntries(snapshot.vehicleCategories)
    sortEntries(snapshot.weaponLoadouts)
    snapshot.peds = snapshot.mpPeds -- Backward-compatible field used by the existing importer.

    local domainCount = #snapshot.mpPeds + #snapshot.nonMpPeds + #snapshot.vehicles
        + #snapshot.pedCategories + #snapshot.vehicleCategories + #snapshot.weaponLoadouts
    local settingCount = 0
    for _ in pairs(snapshot.settings) do settingCount = settingCount + 1 end
    local hasScalarData = snapshot.defaultKey ~= nil or snapshot.defaultLoadout ~= nil or snapshot.temporaryLoadout ~= nil

    snapshot.ok = true
    snapshot.reason = (domainCount > 0 or settingCount > 0 or hasScalarData) and 'parsed' or 'empty'
    snapshot.parser = snapshot.parser or {}
    snapshot.parser.decodedCount = decodedCount
    snapshot.parser.invalidCount = invalid
    snapshot.parser.truncated = truncated
    snapshot.counts = {
        mpPeds = #snapshot.mpPeds,
        nonMpPeds = #snapshot.nonMpPeds,
        vehicles = #snapshot.vehicles,
        pedCategories = #snapshot.pedCategories,
        vehicleCategories = #snapshot.vehicleCategories,
        weaponLoadouts = #snapshot.weaponLoadouts,
        settings = settingCount,
    }
    return snapshot
end

function EsAdminVmenuFallback.getSnapshot(forceRefresh)
    local now = GetGameTimer()
    local cacheMs = Config.VmenuFallback and tonumber(Config.VmenuFallback.cacheMs) or 5000
    if cacheMs == nil or cacheMs < 0 or cacheMs > 60000 then cacheMs = 5000 end
    if not forceRefresh and snapshotCache.data and now < snapshotCache.expiresAt then return snapshotCache.data end

    local snapshot = buildSnapshot(getKvsPath())
    snapshot.generatedAt = os.time()
    snapshotCache.data = snapshot
    snapshotCache.expiresAt = now + cacheMs
    return snapshot
end

local function canUseFallback(src)
    if type(src) ~= 'number' or src <= 0 then return false end
    if IsPlayerAceAllowed(src, Config.Permissions.all) then return true end
    if IsPlayerAceAllowed(src, 'command.' .. Config.Command) or IsPlayerAceAllowed(src, 'command.esadmin')
        or IsPlayerAceAllowed(src, 'command.vmenu') or IsPlayerAceAllowed(src, 'vMenu.Everything') then
        return true
    end
    if Config.HasQBX and EsAdminBridge and EsAdminBridge.isQBXAdmin then
        return EsAdminBridge.isQBXAdmin(src)
    end
    return false
end

local function allowSnapshotRequest(src)
    local now = GetGameTimer()
    local bucket = requestRateBySource[src]
    if not bucket or now < bucket.startedAt or now - bucket.startedAt >= REQUEST_WINDOW_MS then
        requestRateBySource[src] = { startedAt = now, count = 1 }
        return true
    end
    if bucket.count >= REQUEST_LIMIT then return false end
    bucket.count = bucket.count + 1
    return true
end

RegisterNetEvent('cortex-admin:server:requestVmenuKvpSnapshot', function(requestId, forceRefresh)
    local src = source
    if not allowSnapshotRequest(src) or type(requestId) ~= 'string' or requestId == '' or #requestId > 96 then return end

    if not canUseFallback(src) then
        TriggerClientEvent('cortex-admin:client:receiveVmenuKvpSnapshot', src, requestId, emptySnapshot('forbidden', ''))
        return
    end

    TriggerClientEvent(
        'cortex-admin:client:receiveVmenuKvpSnapshot',
        src,
        requestId,
        EsAdminVmenuFallback.getSnapshot(forceRefresh == true)
    )
end)

AddEventHandler('playerDropped', function()
    requestRateBySource[source] = nil
end)
