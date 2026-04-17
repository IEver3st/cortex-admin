EsAdminVmenuFallback = EsAdminVmenuFallback or {}

local snapshotCache = {
    expiresAt = 0,
    data = nil,
}

local VMENU_DISK_PREFIX = 'res:vMenu:'
local VMENU_PED_DISK_PREFIX = VMENU_DISK_PREFIX .. 'mp_ped_'
local VMENU_VEHICLE_DISK_PREFIX = VMENU_DISK_PREFIX .. 'veh_'
local VMENU_DEFAULT_KEY_MARKERS = {
    VMENU_DISK_PREFIX .. 'default_character',
    'default_character',
}

local isWindows = package and package.config and package.config:sub(1, 1) == '\\' or false

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    return (value:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function joinPath(base, name)
    if not base or base == '' then
        return name
    end

    local separator = isWindows and '\\' or '/'
    if base:sub(-1) == '\\' or base:sub(-1) == '/' then
        return base .. name
    end

    return base .. separator .. name
end

local function readBinaryFile(path)
    if type(path) ~= 'string' or path == '' then
        return nil
    end

    local handle = io.open(path, 'rb')
    if not handle then
        return nil
    end

    local data = handle:read('*a')
    handle:close()
    return data
end

local function collectManifestStorageFiles(blob)
    local names = {}
    local seen = {}

    if type(blob) ~= 'string' or blob == '' then
        return names
    end

    for match in blob:gmatch('%d+%.log') do
        if not seen[match] then
            seen[match] = true
            names[#names + 1] = match
        end
    end

    for match in blob:gmatch('%d+%.ldb') do
        if not seen[match] then
            seen[match] = true
            names[#names + 1] = match
        end
    end

    table.sort(names, function(a, b)
        local aNum = tonumber(a:match('^(%d+)')) or 0
        local bNum = tonumber(b:match('^(%d+)')) or 0
        if aNum ~= bNum then
            return aNum < bNum
        end
        return a < b
    end)

    return names
end

local function getKvsPath()
    local configured = Config.VmenuFallback and trim(Config.VmenuFallback.kvsPath) or ''
    if configured ~= '' then
        return configured
    end

    local convarPath = trim(GetConvar('es_admin_vmenu_kvs_path', ''))
    if convarPath ~= '' then
        return convarPath
    end

    local appData = trim(os.getenv('APPDATA'))
    if appData ~= '' then
        return joinPath(appData, 'CitizenFX\\kvs')
    end

    local home = trim(os.getenv('HOME'))
    if home ~= '' then
        return joinPath(home, '.config/CitizenFX/kvs')
    end

    return ''
end

local function extractPrintableToken(blob, startPos)
    local index = startPos
    local length = #blob

    while index <= length do
        local byte = blob:byte(index)
        if not byte or byte < 32 or byte > 126 then
            break
        end
        index = index + 1
    end

    if index <= startPos then
        return nil, startPos
    end

    return blob:sub(startPos, index - 1), index
end

local function extractBalancedJson(blob, startPos)
    if blob:sub(startPos, startPos) ~= '{' then
        return nil, startPos
    end

    local depth = 0
    local inString = false
    local escaped = false

    for index = startPos, #blob do
        local char = blob:sub(index, index)
        if inString then
            if escaped then
                escaped = false
            elseif char == '\\' then
                escaped = true
            elseif char == '"' then
                inString = false
            end
        else
            if char == '"' then
                inString = true
            elseif char == '{' then
                depth = depth + 1
            elseif char == '}' then
                depth = depth - 1
                if depth == 0 then
                    return blob:sub(startPos, index), index
                end
            end
        end
    end

    return nil, startPos
end

local function parseNamespacedJsonEntries(blob, searchPrefix, validator)
    local parsed = {}
    local scanPos = 1

    while true do
        local keyStart = blob:find(searchPrefix, scanPos, true)
        if not keyStart then
            break
        end

        local diskKey, keyEnd = extractPrintableToken(blob, keyStart)
        if not diskKey then
            scanPos = keyStart + #searchPrefix
        else
            local jsonStart = blob:find('{', keyEnd, true)
            if not jsonStart or (jsonStart - keyEnd) > 32768 then
                scanPos = keyEnd + 1
            else
                local jsonString, jsonEnd = extractBalancedJson(blob, jsonStart)
                if not jsonString then
                    scanPos = keyEnd + 1
                else
                    local ok, decoded = pcall(json.decode, jsonString)
                    if ok and type(decoded) == 'table' then
                        local storageKey = diskKey:sub(#VMENU_DISK_PREFIX + 1)
                        if not validator or validator(storageKey, decoded) then
                            parsed[storageKey] = decoded
                        end
                    end
                    scanPos = jsonEnd + 1
                end
            end
        end
    end

    return parsed
end

local function parseDefaultCharacter(blob, currentValue)
    local resolved = currentValue

    for _, marker in ipairs(VMENU_DEFAULT_KEY_MARKERS) do
        local scanPos = 1
        while true do
            local keyStart = blob:find(marker, scanPos, true)
            if not keyStart then
                break
            end

            local valueStart = blob:find('mp_ped_', keyStart + #marker, true)
            if valueStart and (valueStart - keyStart) <= 1024 then
                local value = extractPrintableToken(blob, valueStart)
                if type(value) == 'string' and value ~= '' then
                    resolved = value
                end
            end

            scanPos = keyStart + #marker
        end
    end

    return resolved
end

local function buildSnapshot(kvsPath)
    if not Config.VmenuFallback or Config.VmenuFallback.enabled == false then
        return {
            ok = false,
            reason = 'disabled',
            kvsPath = kvsPath,
            peds = {},
            vehicles = {},
            defaultKey = nil,
            readOnly = true,
        }
    end

    if kvsPath == '' then
        return {
            ok = false,
            reason = 'kvs_path_unavailable',
            kvsPath = kvsPath,
            peds = {},
            vehicles = {},
            defaultKey = nil,
            readOnly = true,
        }
    end

    local current = readBinaryFile(joinPath(kvsPath, 'CURRENT'))
    local manifestName = current and current:match('MANIFEST%-%d+') or nil
    if not manifestName then
        return {
            ok = false,
            reason = 'manifest_missing',
            kvsPath = kvsPath,
            peds = {},
            vehicles = {},
            defaultKey = nil,
            readOnly = true,
        }
    end

    local manifestBlob = readBinaryFile(joinPath(kvsPath, manifestName))
    local storageFiles = collectManifestStorageFiles(manifestBlob)
    if #storageFiles == 0 then
        return {
            ok = false,
            reason = 'storage_files_missing',
            kvsPath = kvsPath,
            peds = {},
            vehicles = {},
            defaultKey = nil,
            readOnly = true,
        }
    end

    local pedMap = {}
    local vehicleMap = {}
    local defaultKey = nil

    for _, fileName in ipairs(storageFiles) do
        local blob = readBinaryFile(joinPath(kvsPath, fileName))
        if type(blob) == 'string' and blob ~= '' then
            local parsedPeds = parseNamespacedJsonEntries(blob, VMENU_PED_DISK_PREFIX, function(_, data)
                return type(data.SaveName) == 'string' and data.ModelHash ~= nil
            end)

            for key, value in pairs(parsedPeds) do
                pedMap[key] = value
            end

            local parsedVehicles = parseNamespacedJsonEntries(blob, VMENU_VEHICLE_DISK_PREFIX, function(_, data)
                return type(data.colors) == 'table'
                    and type(data.mods) == 'table'
                    and type(data.extras) == 'table'
                    and data.Category ~= nil
                    and data.plateText ~= nil
            end)

            for key, value in pairs(parsedVehicles) do
                vehicleMap[key] = value
            end

            defaultKey = parseDefaultCharacter(blob, defaultKey)
        end
    end

    local peds = {}
    for key, value in pairs(pedMap) do
        peds[#peds + 1] = {
            key = key,
            data = value,
        }
    end

    table.sort(peds, function(a, b)
        return (a.key or ''):lower() < (b.key or ''):lower()
    end)

    local vehicles = {}
    for key, value in pairs(vehicleMap) do
        vehicles[#vehicles + 1] = {
            key = key,
            data = value,
        }
    end

    table.sort(vehicles, function(a, b)
        return (a.key or ''):lower() < (b.key or ''):lower()
    end)

    local hasData = #peds > 0 or #vehicles > 0

    return {
        ok = true,
        reason = hasData and 'parsed' or 'empty',
        kvsPath = kvsPath,
        peds = peds,
        vehicles = vehicles,
        defaultKey = defaultKey,
        readOnly = true,
    }
end

function EsAdminVmenuFallback.getSnapshot(forceRefresh)
    local now = GetGameTimer()
    local cacheMs = Config.VmenuFallback and tonumber(Config.VmenuFallback.cacheMs) or 5000
    if cacheMs == nil or cacheMs < 0 then
        cacheMs = 5000
    end

    if not forceRefresh and snapshotCache.data and now < snapshotCache.expiresAt then
        return snapshotCache.data
    end

    local kvsPath = getKvsPath()
    local snapshot = buildSnapshot(kvsPath)
    snapshot.generatedAt = os.time()

    snapshotCache.data = snapshot
    snapshotCache.expiresAt = now + cacheMs
    return snapshot
end

local function canUseFallback(src)
    if not src or src <= 0 then
        return false
    end

    if IsPlayerAceAllowed(src, Config.Permissions.all) then
        return true
    end

    if IsPlayerAceAllowed(src, 'command.' .. Config.Command)
        or IsPlayerAceAllowed(src, 'command.esadmin')
        or IsPlayerAceAllowed(src, 'command') then
        return true
    end

    if Config.HasQBX and EsAdminBridge and EsAdminBridge.isQBXAdmin then
        return EsAdminBridge.isQBXAdmin(src)
    end

    return false
end

RegisterNetEvent('es_admin:server:requestVmenuKvpSnapshot', function(requestId, forceRefresh)
    local src = source
    if type(requestId) ~= 'string' or requestId == '' then
        return
    end

    if not canUseFallback(src) then
        TriggerClientEvent('es_admin:client:receiveVmenuKvpSnapshot', src, requestId, {
            ok = false,
            reason = 'forbidden',
            peds = {},
            vehicles = {},
            defaultKey = nil,
            readOnly = true,
        })
        return
    end

    local snapshot = EsAdminVmenuFallback.getSnapshot(forceRefresh == true)
    TriggerClientEvent('es_admin:client:receiveVmenuKvpSnapshot', src, requestId, snapshot)
end)
