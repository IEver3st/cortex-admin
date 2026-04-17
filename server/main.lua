local Actions = EsAdminActions

local actionIndex = {}
for _, action in ipairs(Actions.actions) do
    actionIndex[action.id] = action
end

local worldState = {}
local mathAbs = math.abs
local mathFloor = math.floor
local stringUpper = string.upper
local tonumber = tonumber
local type = type

local allowedWorldWeather = {
    EXTRASUNNY = true,
    CLEAR = true,
    CLOUDS = true,
    SMOG = true,
    FOGGY = true,
    OVERCAST = true,
    RAIN = true,
    THUNDER = true,
    CLEARING = true,
    NEUTRAL = true,
    SNOW = true,
    BLIZZARD = true,
    SNOWLIGHT = true,
    XMAS = true,
    HALLOWEEN = true,
}

local allowedPlayerActions = {
    kick = true,
    ban = true,
    freeze = true,
    bring = true,
}

local allowedResourceActions = {
    start = true,
    stop = true,
    ensure = true,
    restart = true,
    refresh = true,
}

local uiPresence = {}

local function trimString(value, maxLength)
    if type(value) ~= 'string' then
        return nil
    end

    value = value:match('^%s*(.-)%s*$')
    if value == '' then
        return nil
    end

    if maxLength and #value > maxLength then
        value = value:sub(1, maxLength)
    end

    return value
end

local function toInteger(value, minValue, maxValue)
    local number = tonumber(value)
    if not number or number ~= number then
        return nil
    end

    number = mathFloor(number)

    if minValue and number < minValue then
        return nil
    end

    if maxValue and number > maxValue then
        return nil
    end

    return number
end

local function toBoolean(value)
    if value == true or value == false then
        return value
    end

    if value == 1 or value == '1' or value == 'true' then
        return true
    end

    if value == 0 or value == '0' or value == 'false' then
        return false
    end

    return nil
end

local function normalizeWeather(value)
    local weather = trimString(value, 24)
    if not weather then
        return nil
    end

    weather = stringUpper(weather)
    if not allowedWorldWeather[weather] then
        return nil
    end

    return weather
end

local function sanitizeCoords(coords)
    if type(coords) ~= 'table' then
        return nil
    end

    local x = tonumber(coords.x)
    local y = tonumber(coords.y)
    local z = tonumber(coords.z)
    if not x or not y or not z then
        return nil
    end

    if x ~= x or y ~= y or z ~= z then
        return nil
    end

    if mathAbs(x) > 20000 or mathAbs(y) > 20000 or mathAbs(z) > 20000 then
        return nil
    end

    return {
        x = x,
        y = y,
        z = z,
    }
end

local function hasPermission(src, actionId)
    -- Check for full admin access via es_admin ACE
    if IsPlayerAceAllowed(src, Config.Permissions.all) then
        return true
    end

    -- QBX Permission Bridge: When QBX is active, check if the player belongs to
    -- a configured QBX admin group (god, admin, mod, etc.) and resolve permissions
    -- from Config.QBXPermissions mapping. This lets QBX admins use the menu
    -- without needing separate es_admin.* ACE entries.
    if Config.HasQBX then
        local action = actionIndex[actionId]
        local tab = action and action.tab
        local qbxResult = EsAdminBridge.checkQBXPermission(src, actionId, tab)
        if qbxResult == true then return true end
        if qbxResult == false then return false end
        -- nil = no QBX group matched, fall through to standard ACE checks
    end

    -- Check for command permission (if player can open the menu, they likely should have access)
    -- This is a fallback for servers without fully configured ACE permissions
    if IsPlayerAceAllowed(src, 'command.' .. Config.Command)
        or IsPlayerAceAllowed(src, 'command.esadmin')
        or IsPlayerAceAllowed(src, 'command') then
        -- If no specific permissions are denied, allow access when player has menu command access
        local actionPerm = Config.ActionPermissions[actionId]
        if actionPerm and not IsPlayerAceAllowed(src, actionPerm) then
            -- Check if specific action permission exists and is denied
            return false
        end
        return true
    end

    -- Check for specific action permission
    local actionPerm = Config.ActionPermissions[actionId]
    if actionPerm and IsPlayerAceAllowed(src, actionPerm) then
        return true
    end

    -- Check for tab-level permission
    local action = actionIndex[actionId]
    local tab = action and action.tab
    if tab and Config.Permissions[tab] and IsPlayerAceAllowed(src, Config.Permissions[tab]) then
        return true
    end

    return false
end

local function buildPermissionSnapshot(src)
    local allowed = {}
    for _, action in ipairs(Actions.actions) do
        allowed[action.id] = hasPermission(src, action.id)
    end
    return allowed
end

RegisterNetEvent('es_admin:server:requestPermissions', function()
    local src = source
    TriggerClientEvent('es_admin:client:permissions', src, buildPermissionSnapshot(src))
end)

RegisterNetEvent('es_admin:server:setWorldState', function(payload)
    local src = source
    if type(payload) ~= 'table' then return end

    local changedState = {}

    if payload.weather ~= nil and hasPermission(src, 'world.weather') then
        local weather = normalizeWeather(payload.weather)
        if weather then
            worldState.weather = weather
            changedState.weather = weather
        end
    end

    if payload.hour ~= nil and hasPermission(src, 'world.time') then
        local hour = toInteger(payload.hour, 0, 23)
        local minute = toInteger(payload.minute, 0, 59) or 0

        if hour then
            worldState.hour = hour
            worldState.minute = minute
            changedState.hour = hour
            changedState.minute = minute
        end
    end

    if payload.freezeTime ~= nil and hasPermission(src, 'world.freezeTime') then
        local freezeTime = toBoolean(payload.freezeTime)
        if freezeTime ~= nil then
            worldState.freezeTime = freezeTime
            changedState.freezeTime = freezeTime
        end
    end

    if payload.blackout ~= nil and hasPermission(src, 'world.blackout') then
        local blackout = toBoolean(payload.blackout)
        if blackout ~= nil then
            worldState.blackout = blackout
            changedState.blackout = blackout
        end
    end

    if next(changedState) then
        TriggerClientEvent('es_admin:client:updateWorldState', -1, changedState)
    end
end)

RegisterNetEvent('es_admin:server:requestWorldState', function()
    local src = source
    if next(worldState) == nil then return end
    TriggerClientEvent('es_admin:client:updateWorldState', src, worldState)
end)

RegisterNetEvent('es_admin:server:setUiPresence', function(data)
    local src = source
    if type(data) ~= 'table' then
        return
    end

    uiPresence[src] = data.open == true
end)

RegisterNetEvent('es_admin:server:requestWardrobeShareTargets', function(requestId)
    local src = source
    if type(requestId) ~= 'string' or requestId == '' then
        return
    end

    local targets = {}
    for playerId, isOpen in pairs(uiPresence) do
        if playerId ~= src and isOpen == true and GetPlayerName(playerId) then
            targets[#targets + 1] = playerId
        end
    end

    table.sort(targets)
    TriggerClientEvent('es_admin:client:receiveWardrobeShareTargets', src, requestId, targets)
end)

RegisterNetEvent('es_admin:server:shareWardrobe', function(data)
    local src = source
    if type(data) ~= 'table' then
        return
    end

    local target = toInteger(data.target, 1)
    if not target or target == src or not GetPlayerName(target) then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target player is unavailable.')
        return
    end

    if uiPresence[target] ~= true then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target player must have the menu open.')
        return
    end

    local outfit = data.outfit
    if type(outfit) ~= 'table'
        or type(outfit.DrawableVariations) ~= 'table'
        or type(outfit.PropVariations) ~= 'table' then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Shared wardrobe payload was invalid.')
        return
    end

    local shareId = ('wardrobe:%d:%d:%d'):format(src, target, GetGameTimer())
    local senderName = GetPlayerName(src) or ('Player %d'):format(src)

    TriggerClientEvent('es_admin:client:receiveWardrobeShare', target, {
        shareId = shareId,
        senderId = src,
        senderName = senderName,
        title = type(data.title) == 'string' and data.title or 'Current Outfit',
        outfit = outfit,
    })

    TriggerClientEvent('es_admin:client:notify', src, 'success', ('Shared current outfit with %s.'):format(GetPlayerName(target) or ('Player %d'):format(target)))
    TriggerClientEvent('es_admin:client:notify', target, 'info', ('%s shared an outfit with you.'):format(senderName))
end)

RegisterNetEvent('es_admin:server:playerAction', function(data)
    local src = source
    if type(data) ~= 'table' then return end

    local action = trimString(data.action, 16)
    local target = toInteger(data.target, 1)

    if not action or not allowedPlayerActions[action] or not target then return end
    if not GetPlayerName(target) then return end

    if action == 'kick' then
        if not hasPermission(src, 'player.kick') then return end
        DropPlayer(target, trimString(data.reason, 160) or 'Kicked by staff.')
    elseif action == 'ban' then
        if not hasPermission(src, 'player.ban') then return end
        local identifiers = GetPlayerIdentifiers(target)
        local reason = trimString(data.reason, 160) or 'Banned by staff.'
        local duration = toInteger(data.duration, 0, 525600)
        local adminName = GetPlayerName(src) or 'Console'
        EsAdminServer.addBan(identifiers, reason, adminName, duration)
        DropPlayer(target, reason)
    elseif action == 'freeze' then
        if not hasPermission(src, 'player.freeze') then return end
        TriggerClientEvent('es_admin:client:freeze', target, toBoolean(data.enabled) == true)
    elseif action == 'bring' then
        if not hasPermission(src, 'player.bring') then return end
        local coords = sanitizeCoords(data.coords)
        local heading = tonumber(data.heading)
        if not coords then return end
        if heading and heading == heading then
            heading = heading % 360
        else
            heading = nil
        end
        TriggerClientEvent('es_admin:client:teleport', target, coords, heading)
    end
end)

AddEventHandler('playerConnecting', function(name, setKickReason)
    local identifiers = GetPlayerIdentifiers(source)
    local entry = EsAdminServer.findBan(identifiers)
    if entry then
        local expiresText = entry.expires and os.date('%c', entry.expires) or 'Never'
        setKickReason(('Banned: %s (Expires: %s)'):format(entry.reason or 'No reason', expiresText))
        CancelEvent()
    end
end)

AddEventHandler('playerDropped', function()
    uiPresence[source] = nil
end)

-- =============================================================================
-- RESOURCE MANAGEMENT
-- =============================================================================

local function getResourceList()
    local resources = {}
    local num = GetNumResources()

    for i = 0, num - 1 do
        local name = GetResourceByFindIndex(i)
        if name then
            local state = GetResourceState(name)
            local version = GetResourceMetadata(name, 'version', 0) or 'Unknown'
            local author = GetResourceMetadata(name, 'author', 0) or 'Unknown'
            local description = GetResourceMetadata(name, 'description', 0) or 'No description'
            
            table.insert(resources, {
                name = name,
                state = state, -- started, stopped, starting, stopping, missing
                version = version,
                author = author,
                description = description
            })
        end
    end

    -- Sort resources alphabetically by name
    table.sort(resources, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    return resources
end

local addonVehiclesCache = {
    list = {},
    expiresAt = 0,
}

local ADDON_VEHICLES_CACHE_MS = 60000

local function trim(value)
    if type(value) ~= 'string' then
        return ''
    end
    return (value:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function stripQuotes(value)
    local normalized = trim(value)
    local first = normalized:sub(1, 1)
    local last = normalized:sub(-1)
    if (first == '"' and last == '"') or (first == "'" and last == "'") then
        return trim(normalized:sub(2, -2))
    end
    return normalized
end

local function prettifyModelName(model)
    local normalized = trim(model):gsub('_', ' ')
    return normalized:gsub('(%a)([%w]*)', function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

local isWindows = package and package.config and package.config:sub(1, 1) == '\\' or false

local function normalizePath(value)
    return trim(value):gsub('\\', '/')
end

local function resolveMetaDataSource(ownerResourceName, filePath)
    local normalizedPath = normalizePath(stripQuotes(filePath))
    if normalizedPath == '' then
        return nil, nil
    end

    local linkedResource, linkedPath = normalizedPath:match('^@([^/\\]+)/(.+)$')
    if linkedResource and linkedPath then
        linkedResource = trim(linkedResource)
        linkedPath = normalizePath(trim(linkedPath))
        if linkedResource == '' or linkedPath == '' then
            return nil, nil
        end
        return linkedResource, linkedPath
    end

    return ownerResourceName, normalizedPath
end

local function makeMetaTargetKey(dataResourceName, path)
    return ('%s|%s'):format((dataResourceName or ''):lower(), (path or ''):lower())
end

local function addUniqueMetaTarget(out, seen, ownerResourceName, dataResourceName, rawPath)
    local normalizedPath = normalizePath(stripQuotes(rawPath))
    if normalizedPath == '' or trim(dataResourceName) == '' then
        return false
    end

    local key = makeMetaTargetKey(dataResourceName, normalizedPath)
    if seen[key] then
        return false
    end

    seen[key] = true
    out[#out + 1] = {
        ownerResource = ownerResourceName,
        dataResource = dataResourceName,
        path = normalizedPath,
    }
    return true
end

local function parseDataFileEntry(entry)
    if type(entry) ~= 'string' or entry == '' then
        return nil, nil
    end

    local dataType, filePath = entry:match('^%s*([^%s]+)%s+(.+)%s*$')
    if not dataType or not filePath then
        return nil, nil
    end

    dataType = stripQuotes(dataType):upper()
    filePath = stripQuotes(filePath)
    return dataType, filePath
end

local function buildWildcardFallbackCandidates(wildcardPattern)
    local candidates = {}
    local seen = {}
    local pattern = normalizePath(stripQuotes(wildcardPattern))
    if pattern == '' then
        return candidates
    end

    local basename = pattern:match('([^/]+)$') or 'vehicles.meta'
    basename = basename:gsub('%*', '')
    if basename == '' then
        basename = 'vehicles.meta'
    end

    local compact = pattern
    compact = compact:gsub('/%*%*/', '/')
    compact = compact:gsub('%*%*/', '')
    compact = compact:gsub('/%*', '/')
    compact = compact:gsub('%*', '')
    compact = compact:gsub('//+', '/')
    compact = compact:gsub('^/', '')

    local function push(path)
        local normalized = normalizePath(path)
        if normalized == '' then
            return
        end
        local lowerPath = normalized:lower()
        if seen[lowerPath] then
            return
        end
        seen[lowerPath] = true
        candidates[#candidates + 1] = normalized
    end

    if compact ~= '' then
        push(compact)
    end

    local folder = compact:match('^(.*)/[^/]*$')
    if folder and folder ~= '' then
        push(folder .. '/' .. basename)
    end

    if basename ~= '' then
        push('data/' .. basename)
        push(basename)
    end

    return candidates
end

local function quotePath(path)
    if isWindows then
        return '"' .. tostring(path):gsub('"', '""') .. '"'
    end
    return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

local function runCommand(command)
    local rows = {}
    if not io or type(io.popen) ~= 'function' then
        return rows
    end

    local pipe = io.popen(command)
    if not pipe then
        return rows
    end

    for line in pipe:lines() do
        if line and line ~= '' then
            rows[#rows + 1] = line
        end
    end

    pipe:close()
    return rows
end

local function listFilesRecursively(absPath)
    local quotedPath = quotePath(absPath)
    local primaryCommand = isWindows
        and ('dir /s /b %s 2>nul'):format(quotedPath)
        or ('find %s -type f 2>/dev/null'):format(quotedPath)
    local fallbackCommand = isWindows
        and ('find %s -type f 2>/dev/null'):format(quotedPath)
        or ('dir /s /b %s 2>nul'):format(quotedPath)

    local rows = runCommand(primaryCommand)
    if #rows == 0 then
        rows = runCommand(fallbackCommand)
    end

    return rows
end

local function pathMatchesWildcard(path, wildcardPattern)
    local normalizedPath = normalizePath(path):lower()
    local pattern = normalizePath(wildcardPattern):lower()

    local firstStar = pattern:find('*', 1, true)
    if not firstStar then
        return normalizedPath == pattern
    end

    local lastStar = firstStar
    local cursor = firstStar + 1
    while true do
        local pos = pattern:find('*', cursor, true)
        if not pos then
            break
        end
        lastStar = pos
        cursor = pos + 1
    end

    local prefix = pattern:sub(1, firstStar - 1)
    if prefix ~= '' and normalizedPath:sub(1, #prefix) ~= prefix then
        return false
    end

    local suffix = pattern:sub(lastStar + 1)
    if suffix ~= '' then
        if #normalizedPath < #suffix then
            return false
        end
        if normalizedPath:sub(-#suffix) ~= suffix then
            return false
        end
    end

    return true
end

local function collectWildcardMetaPathsFromMetadata(ownerResourceName, dataResourceName, wildcardPattern, seen, out, stats)
    local function pushIfMatches(rawPath, sourceResourceName)
        local resolvedDataResource, resolvedPath = resolveMetaDataSource(sourceResourceName, rawPath)
        if not resolvedDataResource or not resolvedPath then
            return
        end

        local lowerPath = resolvedPath:lower()
        if lowerPath:find('*', 1, true) then
            return
        end

        if pathMatchesWildcard(lowerPath, wildcardPattern) then
            local added = addUniqueMetaTarget(out, seen, ownerResourceName, resolvedDataResource, resolvedPath)
            if added and ownerResourceName ~= resolvedDataResource then
                stats.linkedMetadataTargets = stats.linkedMetadataTargets + 1
            end
        end
    end

    local fileKeys = { 'file', 'files' }
    for i = 1, #fileKeys do
        local key = fileKeys[i]
        local count = GetNumResourceMetadata(dataResourceName, key) or 0
        for index = 0, count - 1 do
            local value = GetResourceMetadata(dataResourceName, key, index)
            if type(value) == 'string' then
                pushIfMatches(value, dataResourceName)
            end
        end
    end

    local dataFileCount = GetNumResourceMetadata(dataResourceName, 'data_file') or 0
    for i = 0, dataFileCount - 1 do
        local entry = GetResourceMetadata(dataResourceName, 'data_file', i)
        local dataType, filePath = parseDataFileEntry(entry)
        if dataType == 'VEHICLE_METADATA_FILE' and filePath then
            pushIfMatches(filePath, dataResourceName)
        end
    end
end

local function collectWildcardMetaPaths(ownerResourceName, dataResourceName, wildcardPattern, seen, out, stats)
    collectWildcardMetaPathsFromMetadata(ownerResourceName, dataResourceName, wildcardPattern, seen, out, stats)

    local resourcePath = normalizePath(GetResourcePath(dataResourceName) or '')
    if resourcePath == '' then
        return
    end

    local files = listFilesRecursively(resourcePath)
    for i = 1, #files do
        local absolute = normalizePath(files[i])
        if absolute ~= '' then
            local lowerAbsolute = absolute:lower()
            local lowerRoot = resourcePath:lower()
            if lowerAbsolute:sub(1, #lowerRoot) == lowerRoot then
                local relative = absolute:sub(#resourcePath + 1):gsub('^/', '')
                local lowerRelative = relative:lower()
                if pathMatchesWildcard(lowerRelative, wildcardPattern) then
                    local added = addUniqueMetaTarget(out, seen, ownerResourceName, dataResourceName, relative)
                    if added and ownerResourceName ~= dataResourceName then
                        stats.linkedMetadataTargets = stats.linkedMetadataTargets + 1
                    end
                end
            end
        end
    end
end

local function getVehicleMetaTargets(resourceName, stats)
    local targets = {}
    local seen = {}
    local count = GetNumResourceMetadata(resourceName, 'data_file') or 0
    local hasVehicleMetadataDeclaration = false

    for i = 0, count - 1 do
        local entry = GetResourceMetadata(resourceName, 'data_file', i)
        local dataType, filePath = parseDataFileEntry(entry)
        if dataType == 'VEHICLE_METADATA_FILE' and filePath then
            hasVehicleMetadataDeclaration = true
            local dataResourceName, resolvedPath = resolveMetaDataSource(resourceName, filePath)

            if dataResourceName and resolvedPath and resolvedPath ~= '' then
                if resolvedPath:find('*', 1, true) then
                    local countBefore = #targets
                    collectWildcardMetaPaths(resourceName, dataResourceName, resolvedPath, seen, targets, stats)

                    if #targets == countBefore then
                        local fallbackCandidates = buildWildcardFallbackCandidates(resolvedPath)
                        for idx = 1, #fallbackCandidates do
                            local candidate = fallbackCandidates[idx]
                            local content = LoadResourceFile(dataResourceName, candidate)
                            if content and content ~= '' then
                                local added = addUniqueMetaTarget(targets, seen, resourceName, dataResourceName, candidate)
                                if added and resourceName ~= dataResourceName then
                                    stats.linkedMetadataTargets = stats.linkedMetadataTargets + 1
                                end
                            end
                        end
                    end
                else
                    local added = addUniqueMetaTarget(targets, seen, resourceName, dataResourceName, resolvedPath)
                    if added and resourceName ~= dataResourceName then
                        stats.linkedMetadataTargets = stats.linkedMetadataTargets + 1
                    end
                end
            end
        end
    end

    if #targets == 0 and hasVehicleMetadataDeclaration then
        -- Fallback for wildcard declarations that do not resolve to direct file paths.
        collectWildcardMetaPaths(resourceName, resourceName, '*vehicles.meta', seen, targets, stats)
    end

    return targets, hasVehicleMetadataDeclaration
end

local function parseVehiclesMeta(xml, ownerResourceName, dataResourceName, metaPath, byModel, stats, metadataModelsByResource)
    if type(xml) ~= 'string' or xml == '' then
        return
    end

    for item in xml:gmatch('<Item.->(.-)</Item>') do
        local modelName = trim(item:match('<modelName>%s*([^<]+)%s*</modelName>'))
        if modelName ~= '' then
            local normalizedModel = modelName:lower()
            if not byModel[normalizedModel] then
                local gameName = trim(item:match('<gameName>%s*([^<]+)%s*</gameName>'))
                local makeName = trim(item:match('<vehicleMakeName>%s*([^<]+)%s*</vehicleMakeName>'))
                local label = gameName ~= '' and gameName or prettifyModelName(normalizedModel)

                byModel[normalizedModel] = {
                    model = normalizedModel,
                    name = label,
                    gameName = gameName ~= '' and gameName or nil,
                    makeName = makeName ~= '' and makeName or nil,
                    resource = dataResourceName,
                    metaPath = metaPath,
                    sourceType = 'metadata',
                    ownerResource = ownerResourceName,
                    dataResource = dataResourceName,
                }
                stats.metadataModels = stats.metadataModels + 1
                metadataModelsByResource[dataResourceName] = (metadataModelsByResource[dataResourceName] or 0) + 1
            else
                stats.duplicateModels = stats.duplicateModels + 1
            end
        end
    end
end

local function getStreamVehicleModels(resourceName)
    local resourcePath = normalizePath(GetResourcePath(resourceName) or '')
    if resourcePath == '' then
        return {}
    end

    local models = {}
    local seenModels = {}
    local files = listFilesRecursively(resourcePath)
    local lowerRoot = resourcePath:lower()

    for i = 1, #files do
        local absolute = normalizePath(files[i])
        if absolute ~= '' then
            local lowerAbsolute = absolute:lower()
            if lowerAbsolute:sub(1, #lowerRoot) == lowerRoot then
                local relative = absolute:sub(#resourcePath + 1):gsub('^/', '')
                local lowerRelative = relative:lower()
                local inStreamFolder = lowerRelative:sub(1, 7) == 'stream/'
                    or lowerRelative:find('/stream/', 1, true) ~= nil
                if inStreamFolder and lowerRelative:sub(-4) == '.yft' and lowerRelative:sub(-7) ~= '_hi.yft' then
                    local modelName = lowerRelative:match('([^/]+)%.yft$')
                    if modelName and modelName ~= '' and not seenModels[modelName] then
                        seenModels[modelName] = true
                        models[#models + 1] = modelName
                    end
                end
            end
        end
    end

    table.sort(models)
    return models
end

local function getAddonVehicles(forceRefresh)
    local now = GetGameTimer()
    if not forceRefresh and now < addonVehiclesCache.expiresAt then
        return addonVehiclesCache.list
    end

    local byModel = {}
    local metadataModelsByResource = {}
    local stats = {
        scannedResources = 0,
        resourcesWithVehicleMetadataDeclaration = 0,
        resourcesWithResolvedVehicleMeta = 0,
        parsedVehicleMetaFiles = 0,
        metadataModels = 0,
        streamFallbackModels = 0,
        duplicateModels = 0,
        linkedMetadataTargets = 0,
        fallbackResources = 0,
    }

    local num = GetNumResources()
    for i = 0, num - 1 do
        local resourceName = GetResourceByFindIndex(i)
        if resourceName and GetResourceState(resourceName) == 'started' then
            stats.scannedResources = stats.scannedResources + 1
            local metaTargets, hasVehicleMetadataDeclaration = getVehicleMetaTargets(resourceName, stats)
            if hasVehicleMetadataDeclaration then
                stats.resourcesWithVehicleMetadataDeclaration = stats.resourcesWithVehicleMetadataDeclaration + 1
            end

            if #metaTargets > 0 then
                stats.resourcesWithResolvedVehicleMeta = stats.resourcesWithResolvedVehicleMeta + 1
            end

            for idx = 1, #metaTargets do
                local target = metaTargets[idx]
                local content = LoadResourceFile(target.dataResource, target.path)
                if content and content ~= '' then
                    stats.parsedVehicleMetaFiles = stats.parsedVehicleMetaFiles + 1
                    parseVehiclesMeta(
                        content,
                        target.ownerResource,
                        target.dataResource,
                        target.path,
                        byModel,
                        stats,
                        metadataModelsByResource
                    )
                end
            end
        end
    end

    for i = 0, num - 1 do
        local resourceName = GetResourceByFindIndex(i)
        if resourceName and GetResourceState(resourceName) == 'started' then
            local hasMetadataModels = (metadataModelsByResource[resourceName] or 0) > 0
            if not hasMetadataModels then
                local streamModels = getStreamVehicleModels(resourceName)
                if #streamModels > 0 then
                    stats.fallbackResources = stats.fallbackResources + 1
                end

                for idx = 1, #streamModels do
                    local model = streamModels[idx]
                    if not byModel[model] then
                        byModel[model] = {
                            model = model,
                            name = prettifyModelName(model),
                            resource = resourceName,
                            metaPath = 'stream/*.yft',
                            sourceType = 'stream_fallback',
                            ownerResource = resourceName,
                            dataResource = resourceName,
                        }
                        stats.streamFallbackModels = stats.streamFallbackModels + 1
                    else
                        stats.duplicateModels = stats.duplicateModels + 1
                    end
                end
            end
        end
    end

    local list = {}
    for _, entry in pairs(byModel) do
        list[#list + 1] = entry
    end

    table.sort(list, function(a, b)
        local nameA = (a.name or a.model or ''):lower()
        local nameB = (b.name or b.model or ''):lower()
        if nameA ~= nameB then
            return nameA < nameB
        end
        return (a.model or ''):lower() < (b.model or ''):lower()
    end)

    addonVehiclesCache.list = list
    addonVehiclesCache.expiresAt = now + ADDON_VEHICLES_CACHE_MS
    if #list == 0 then
        print(('[es_admin] WARNING: Addon vehicle scan found 0 entries (started resources: %d, metadata declarations: %d, resources with resolved metadata paths: %d, parsed vehicles.meta files: %d, linked metadata targets: %d, stream fallback models: %d, duplicates skipped: %d). Verify data_file paths and wildcard support.'):format(
            stats.scannedResources,
            stats.resourcesWithVehicleMetadataDeclaration,
            stats.resourcesWithResolvedVehicleMeta,
            stats.parsedVehicleMetaFiles,
            stats.linkedMetadataTargets,
            stats.streamFallbackModels,
            stats.duplicateModels
        ))
    else
        print(('[es_admin] Addon vehicle scan indexed %d models (metadata models: %d, stream fallback models: %d, duplicates skipped: %d, started resources: %d, metadata declarations: %d, resources with resolved metadata paths: %d, parsed vehicles.meta files: %d, linked metadata targets: %d, fallback resources: %d)'):format(
            #list,
            stats.metadataModels,
            stats.streamFallbackModels,
            stats.duplicateModels,
            stats.scannedResources,
            stats.resourcesWithVehicleMetadataDeclaration,
            stats.resourcesWithResolvedVehicleMeta,
            stats.parsedVehicleMetaFiles,
            stats.linkedMetadataTargets,
            stats.fallbackResources
        ))
    end
    return list
end

local currentResourceName = GetCurrentResourceName()
local photoCaptureDir = normalizePath(('%s/photos'):format(GetResourcePath(currentResourceName)))
local photoCaptureDirReady = false

local function ensurePhotoCaptureDir()
    if photoCaptureDirReady then
        return true
    end

    local command
    if isWindows then
        local quotedPath = quotePath(photoCaptureDir)
        command = ('if not exist %s mkdir %s'):format(quotedPath, quotedPath)
    else
        command = ('mkdir -p %s'):format(quotePath(photoCaptureDir))
    end

    local ok = os.execute(command)
    if ok == true or ok == 0 then
        photoCaptureDirReady = true
        return true
    end

    return false
end

local function sanitizePhotoFileSegment(value)
    value = tostring(value or 'player')
    value = value:gsub('[^%w%-_]+', '_')
    value = value:gsub('_+', '_')
    value = value:gsub('^_+', '')
    value = value:gsub('_+$', '')

    if value == '' then
        return 'player'
    end

    return value:sub(1, 32)
end

local function buildPhotoCapturePath(src)
    local playerName = sanitizePhotoFileSegment(GetPlayerName(src))
    local stamp = os.date('%Y%m%d-%H%M%S')
    local fileName = ('%s-%d-%s.jpg'):format(stamp, src, playerName)
    return normalizePath(('%s/%s'):format(photoCaptureDir, fileName)), ('photos/%s'):format(fileName)
end

local function invalidateAddonVehiclesCache(reason)
    addonVehiclesCache.expiresAt = 0
    print(('[es_admin] addon vehicle cache invalidated (%s)'):format(reason or 'unspecified'))
end

RegisterNetEvent('es_admin:server:requestAddonVehicles', function()
    local src = source
    local canSpawnVehicles = hasPermission(src, 'vehicle.spawn')
    local playerName = GetPlayerName(src) or 'unknown'
    if not canSpawnVehicles then
        print(('[es_admin] requestAddonVehicles: %s (%d) does not have vehicle.spawn permission; sending list for UI visibility only.'):format(playerName, src))
    end

    local vehicles = getAddonVehicles(false)
    print(('[es_admin] requestAddonVehicles: sending %d addon vehicles to %s (%d)'):format(#vehicles, playerName, src))
    TriggerClientEvent('es_admin:client:setAddonVehicles', src, vehicles)
end)

RegisterNetEvent('es_admin:server:takePhoto', function()
    local src = source
    if not hasPermission(src, 'dev.takePhoto') then return end

    if GetResourceState('screenshot-basic') ~= 'started' then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'screenshot-basic is not running.')
        return
    end

    if not ensurePhotoCaptureDir() then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Failed to prepare the photo output folder.')
        return
    end

    local absolutePath, relativePath = buildPhotoCapturePath(src)

    exports['screenshot-basic']:requestClientScreenshot(src, {
        fileName = absolutePath,
        encoding = 'jpg',
        quality = 0.95,
    }, function(err)
        if err then
            print(('[es_admin] failed to capture photo for %s (%d): %s'):format(GetPlayerName(src) or 'unknown', src, tostring(err)))
            TriggerClientEvent('es_admin:client:notify', src, 'error', 'Photo capture failed.')
            return
        end

        TriggerClientEvent('es_admin:client:copyText', src, absolutePath)
        TriggerClientEvent('es_admin:client:notify', src, 'success', ('Photo saved to %s. Full path copied to clipboard.'):format(relativePath))
    end)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == currentResourceName then
        return
    end
    invalidateAddonVehiclesCache(('resource start: %s'):format(resourceName or 'unknown'))
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == currentResourceName then
        return
    end
    invalidateAddonVehiclesCache(('resource stop: %s'):format(resourceName or 'unknown'))
end)

RegisterNetEvent('es_admin:server:requestResources', function()
    local src = source
    if not hasPermission(src, 'server.resources') then return end
    
    TriggerClientEvent('es_admin:client:setResources', src, getResourceList())
end)

RegisterNetEvent('es_admin:server:resourceAction', function(data)
    local src = source
    if type(data) ~= 'table' then return end

    local action = trimString(data.action, 16)
    local name = trimString(data.name, 64)

    if not action or not allowedResourceActions[action] or not name then return end
    if not hasPermission(src, 'server.resources') then return end
    if GetResourceState(name) == 'missing' then
        TriggerClientEvent('es_admin:client:notify', src, 'error', ('Resource not found: %s'):format(name))
        return
    end

    if action == 'start' then
        if GetResourceState(name) == 'stopped' then
            StartResource(name)
            print(string.format('^3[es_admin] ^7Admin %s started resource: %s', GetPlayerName(src), name))
            TriggerClientEvent('es_admin:client:notify', src, 'success', string.format('Started %s', name))
        else
            TriggerClientEvent('es_admin:client:notify', src, 'error', string.format('%s is already %s', name, GetResourceState(name)))
        end
    elseif action == 'stop' then
        if GetResourceState(name) == 'started' then
            StopResource(name)
            print(string.format('^3[es_admin] ^7Admin %s stopped resource: %s', GetPlayerName(src), name))
            TriggerClientEvent('es_admin:client:notify', src, 'success', string.format('Stopped %s', name))
        else
            TriggerClientEvent('es_admin:client:notify', src, 'error', string.format('%s is not running', name))
        end
    elseif action == 'ensure' or action == 'restart' then
        StopResource(name)
        StartResource(name)
        print(string.format('^3[es_admin] ^7Admin %s restarted resource: %s', GetPlayerName(src), name))
        TriggerClientEvent('es_admin:client:notify', src, 'success', string.format('Restarted %s', name))
    elseif action == 'refresh' then
        ExecuteCommand('refresh')
        print(string.format('^3[es_admin] ^7Admin %s triggered global resource refresh', GetPlayerName(src)))
        TriggerClientEvent('es_admin:client:notify', src, 'info', 'Resource list refreshed')
    end

    -- Send updated list back to the sender
    TriggerClientEvent('es_admin:client:setResources', src, getResourceList())
end)

AddEventHandler('playerJoining', function()
    if next(worldState) == nil then return end
    TriggerClientEvent('es_admin:client:updateWorldState', source, worldState)
end)

-- =============================================================================
-- INVENTORY MANAGEMENT (QBX / ox_inventory)
-- =============================================================================

RegisterNetEvent('es_admin:server:getItems', function()
    local src = source
    if not hasPermission(src, 'inventory.giveItem') then return end

    local items = EsAdminBridge.getAllItems()
    if type(items) ~= 'table' then
        items = {}
    end

    TriggerClientEvent('es_admin:client:setItems', src, items)
end)

RegisterNetEvent('es_admin:server:giveItem', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'inventory.giveItem') then return end

    local target = toInteger(data.target, 1)
    local itemName = trimString(data.item, 64)
    local amount = toInteger(data.amount, 1, 10000) or 1

    if not target or not itemName then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end

    -- Verify target is online
    local targetName = GetPlayerName(target)
    if not targetName then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local success, err = EsAdminBridge.giveItem(target, itemName, amount)

    if success then
        local adminName = GetPlayerName(src) or 'Admin'
        print(string.format('^3[es_admin] ^7%s gave %dx %s to %s (ID: %d)', adminName, amount, itemName, targetName, target))
        TriggerClientEvent('es_admin:client:notify', src, 'success', string.format('Gave %dx %s to %s', amount, itemName, targetName))
    else
        TriggerClientEvent('es_admin:client:notify', src, 'error', err or 'Failed to give item')
    end
end)

-- =============================================================================
-- GARAGE MANAGEMENT (QBX / qbx_vehicles)
-- =============================================================================

RegisterNetEvent('es_admin:server:getPlayerGarage', function()
    local src = source
    if not hasPermission(src, 'garage.spawnVehicle') then return end

    local citizenid = EsAdminBridge.getPlayerCitizenId(src)
    if not citizenid then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Could not determine your citizen ID')
        return
    end

    local vehicles = EsAdminBridge.getPlayerVehicles(citizenid)
    if type(vehicles) ~= 'table' then
        vehicles = {}
    end

    TriggerClientEvent('es_admin:client:setGarageVehicles', src, vehicles)
end)

RegisterNetEvent('es_admin:server:spawnGarageVehicle', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'garage.spawnVehicle') then return end

    local vehicleId = toInteger(data.vehicleId, 1)
    if not vehicleId then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Invalid vehicle ID')
        return
    end

    local citizenid = EsAdminBridge.getPlayerCitizenId(src)
    if not citizenid then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Could not determine your citizen ID')
        return
    end

    -- Fetch the specific vehicle to verify ownership
    local vehicles = EsAdminBridge.getPlayerVehicles(citizenid)
    if type(vehicles) ~= 'table' then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Garage data is unavailable right now')
        return
    end

    local targetVehicle = nil
    for _, veh in ipairs(vehicles) do
        if veh.id == vehicleId then
            targetVehicle = veh
            break
        end
    end

    if not targetVehicle then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Vehicle not found in your garage')
        return
    end

    -- Send vehicle data to client for spawning
    TriggerClientEvent('es_admin:client:spawnGarageVehicle', src, {
        id = targetVehicle.id,
        model = targetVehicle.model,
        label = targetVehicle.label,
        props = targetVehicle.props,
        plate = targetVehicle.plate,
    })
end)

local function giveVehicleKeys(src, vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false, 'Vehicle not found'
    end

    if GetResourceState('qbx_vehiclekeys') ~= 'started' then
        return false, 'qbx_vehiclekeys is not running'
    end

    local ok, err = pcall(function()
        exports.qbx_vehiclekeys:GiveKeys(src, vehicle, true)
    end)

    if not ok then
        return false, tostring(err)
    end

    return true
end

RegisterNetEvent('es_admin:server:giveVehicleKeys', function(data)
    local src = source
    local silent = type(data) == 'table' and data.silent == true

    local hasAccess = hasPermission(src, 'vehicle.giveKeys')
    if not hasAccess and silent then
        hasAccess = hasPermission(src, 'vehicle.spawn')
            or hasPermission(src, 'vehicle.personal')
            or hasPermission(src, 'garage.spawnVehicle')
    end
    if not hasAccess then return end

    local function notifyError(message)
        if silent then return end
        TriggerClientEvent('es_admin:client:notify', src, 'error', message)
    end

    local playerPed = GetPlayerPed(src)
    if playerPed == 0 then
        notifyError('Could not resolve your player ped')
        return
    end

    local currentVehicle = GetVehiclePedIsIn(playerPed, false)
    if currentVehicle == 0 then
        notifyError('You are not in a vehicle')
        return
    end

    local vehicle = currentVehicle
    if type(data) == 'table' and data.netId then
        local netId = tonumber(data.netId)
        if netId then
            local fromNetId = NetworkGetEntityFromNetworkId(netId)
            if fromNetId ~= 0 then
                vehicle = fromNetId
            end
        end
    end

    if vehicle ~= currentVehicle then
        notifyError('You must be inside the selected vehicle')
        return
    end

    local success, err = giveVehicleKeys(src, vehicle)
    if not success then
        notifyError(('Failed to give keys: %s'):format(err))
        return
    end

    if not silent then
        TriggerClientEvent('es_admin:client:notify', src, 'success', 'Vehicle keys granted')
    end
end)

-- =============================================================================
-- QBX PLAYER MANAGEMENT COMMANDS
-- =============================================================================

RegisterNetEvent('es_admin:server:killPlayer', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.kill') then return end

    local target = tonumber(data.target)
    if not target or not GetPlayerName(target) then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    TriggerClientEvent('es_admin:client:killPed', target)
    local adminName = GetPlayerName(src) or 'Admin'
    print(string.format('^3[es_admin] ^7%s killed %s (ID: %d)', adminName, GetPlayerName(target), target))
    TriggerClientEvent('es_admin:client:notify', src, 'success', 'Killed ' .. GetPlayerName(target))
end)

RegisterNetEvent('es_admin:server:revivePlayer', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.reviveTarget') then return end

    local target = tonumber(data.target)
    if not target or not GetPlayerName(target) then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    TriggerClientEvent('es_admin:client:revivePed', target)
    local adminName = GetPlayerName(src) or 'Admin'
    print(string.format('^3[es_admin] ^7%s revived %s (ID: %d)', adminName, GetPlayerName(target), target))
    TriggerClientEvent('es_admin:client:notify', src, 'success', 'Revived ' .. GetPlayerName(target))
end)

RegisterNetEvent('es_admin:server:sitInVehicle', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.sitInVehicle') then return end

    local target = tonumber(data.target)
    if not target or not GetPlayerName(target) then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local targetPed = GetPlayerPed(target)
    local veh = GetVehiclePedIsIn(targetPed, false)
    if veh == 0 then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target is not in a vehicle')
        return
    end

    -- Get target vehicle's net ID and send to admin client
    local netId = NetworkGetNetworkIdFromEntity(veh)
    TriggerClientEvent('es_admin:client:sitInVehicle', src, netId)
end)

RegisterNetEvent('es_admin:server:setJob', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.setJob') then return end
    if not Config.HasQBX then return end

    local target = toInteger(data.target, 1)
    local jobName = trimString(data.job, 64)
    local jobGrade = toInteger(data.grade, 0, 99) or 0
    if not target or not jobName then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        player.Functions.SetJob(jobName, jobGrade)
    end)

    if ok then
        TriggerClientEvent('es_admin:client:notify', src, 'success', string.format('Set %s job to %s (grade %d)', GetPlayerName(target), jobName, jobGrade))
    else
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('es_admin:server:setGang', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.setGang') then return end
    if not Config.HasQBX then return end

    local target = toInteger(data.target, 1)
    local gangName = trimString(data.gang, 64)
    local gangGrade = toInteger(data.grade, 0, 99) or 0
    if not target or not gangName then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        player.Functions.SetGang(gangName, gangGrade)
    end)

    if ok then
        TriggerClientEvent('es_admin:client:notify', src, 'success', string.format('Set %s gang to %s (grade %d)', GetPlayerName(target), gangName, gangGrade))
    else
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('es_admin:server:setMoney', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not Config.HasQBX then return end

    local actionId = data.actionId or 'player.setCash'
    if not hasPermission(src, actionId) then return end

    local target = toInteger(data.target, 1)
    local moneyType = trimString(data.moneyType, 32) or 'cash'
    local amount = toInteger(data.amount, 0, 1000000000)
    if not target or amount == nil then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        player.Functions.SetMoney(moneyType, amount, 'admin-set')
    end)

    if ok then
        TriggerClientEvent('es_admin:client:notify', src, 'success', string.format('Set %s %s to $%s', GetPlayerName(target), moneyType, tostring(amount)))
    else
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('es_admin:server:giveMoney', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.giveMoney') then return end
    if not Config.HasQBX then return end

    local target = toInteger(data.target, 1)
    local moneyType = trimString(data.moneyType, 32) or 'cash'
    local amount = toInteger(data.amount, 1, 1000000000)
    if not target or not amount or amount <= 0 then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        player.Functions.AddMoney(moneyType, amount, 'admin-give')
    end)

    if ok then
        TriggerClientEvent('es_admin:client:notify', src, 'success', string.format('Gave $%s %s to %s', tostring(amount), moneyType, GetPlayerName(target)))
    else
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('es_admin:server:setMetadata', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not Config.HasQBX then return end

    local actionId = data.actionId
    if not actionId or not hasPermission(src, actionId) then return end

    local target = toInteger(data.target, 1)
    local key = trimString(data.key, 64)
    local value = data.value

    if type(value) == 'string' then
        value = value:match('^%s*(.-)%s*$')
        if value == '' then
            value = nil
        elseif #value > 160 then
            value = value:sub(1, 160)
        end
    end

    if actionId == 'player.setFood' or actionId == 'player.setThirst' or actionId == 'player.setStress' then
        value = tonumber(value)
        if not value then
            TriggerClientEvent('es_admin:client:notify', src, 'error', 'Value must be a number')
            return
        end

        if value < 0 then value = 0 end
        if value > 100 then value = 100 end
        value = math.floor(value + 0.5)
    elseif type(value) == 'string' then
        local numeric = tonumber(value)
        if numeric ~= nil then
            value = numeric
        end
    end

    if not target or not key then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        player.Functions.SetMetaData(key, value)
    end)

    if ok then
        TriggerClientEvent('es_admin:client:notify', src, 'success', string.format('Set %s %s to %s', GetPlayerName(target), key, tostring(value)))
    else
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('es_admin:server:openInventory', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.openInventory') then return end
    if not Config.HasOxInventory then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'No inventory system detected')
        return
    end

    local target = tonumber(data.target)
    if not target or not GetPlayerName(target) then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local ok, err = pcall(function()
        exports.ox_inventory:forceOpenInventory(src, 'player', target)
    end)

    if not ok then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Failed to open inventory: ' .. tostring(err))
    end
end)

RegisterNetEvent('es_admin:server:setRoutingBucket', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.setRoutingBucket') then return end

    local target = toInteger(data.target, 1)
    local bucket = toInteger(data.bucket, 0, 65535) or 0
    if not target or not GetPlayerName(target) then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    SetPlayerRoutingBucket(target, bucket)
    TriggerClientEvent('es_admin:client:notify', src, 'success', string.format('Set %s routing bucket to %d', GetPlayerName(target), bucket))
end)

RegisterNetEvent('es_admin:server:adminCar', function()
    local src = source
    if not hasPermission(src, 'vehicle.adminCar') then return end
    if not Config.HasQBX or not Config.HasQBXVehicles then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'QBX vehicles not available')
        return
    end

    local citizenid = EsAdminBridge.getPlayerCitizenId(src)
    if not citizenid then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Could not determine your citizen ID')
        return
    end

    -- Request vehicle props from client
    TriggerClientEvent('es_admin:client:getVehicleProps', src)
end)

RegisterNetEvent('es_admin:server:adminCarSave', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'vehicle.adminCar') then return end
    if not Config.HasQBX or not Config.HasQBXVehicles then return end

    local citizenid = EsAdminBridge.getPlayerCitizenId(src)
    if not citizenid then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Could not determine your citizen ID')
        return
    end

    local model = data.model
    local props = data.props
    if not model or not props then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'No vehicle data')
        return
    end

    local ok, result = pcall(function()
        return exports.qbx_vehicles:CreatePlayerVehicle({
            model = model,
            citizenid = citizenid,
            props = props,
            garage = 'pillboxgarage',
            state = 0,
        })
    end)

    if ok and result then
        TriggerClientEvent('es_admin:client:notify', src, 'success', 'Vehicle saved to your garage')
    else
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Failed to save vehicle: ' .. tostring(result))
    end
end)

RegisterNetEvent('es_admin:server:pullStash', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'server.pullStash') then return end
    if not Config.HasOxInventory then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'No inventory system detected')
        return
    end

    local stashName = trimString(data.stash, 80)
    if not stashName then
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Stash name required')
        return
    end

    local ok, err = pcall(function()
        exports.ox_inventory:forceOpenInventory(src, 'stash', stashName)
    end)

    if ok then
        TriggerClientEvent('es_admin:client:notify', src, 'success', 'Opened stash: ' .. stashName)
    else
        TriggerClientEvent('es_admin:client:notify', src, 'error', 'Failed to open stash: ' .. tostring(err))
    end
end)
