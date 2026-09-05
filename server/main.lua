local Actions = EsAdminActions

local actionIndex = {}
for _, action in ipairs(Actions.actions) do
    actionIndex[action.id] = action
end

local worldState = {}
EsAdminServer.worldState = worldState
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
    ['goto'] = true,
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
local permissionCache = {}
local requestBuckets = {}
local pendingAdminCarRequests = {}
local PERMISSION_CACHE_MS = 10000
local ADMIN_CAR_REQUEST_MS = 5000
local configuredWardrobeShareRadius = WardrobeSharePolicy.validateRadius(Config.WardrobeShareRadius)
local WARDROBE_SHARE_RADIUS = configuredWardrobeShareRadius or WardrobeSharePolicy.DEFAULT_RADIUS

if not configuredWardrobeShareRadius then
    print(('[cortex-admin] Invalid Config.WardrobeShareRadius; using %.1fm.'):format(WARDROBE_SHARE_RADIUS))
end

local moneyActions = {
    ['player.setCash'] = 'cash',
    ['player.setBank'] = 'bank',
}

local metadataActions = {
    ['player.setFood'] = 'hunger',
    ['player.setThirst'] = 'thirst',
    ['player.setStress'] = 'stress',
    ['dev.setStress'] = 'stress',
}

local allowedMoneyTypes = {
    cash = true,
    bank = true,
}

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
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end

    if number ~= mathFloor(number) then
        return nil
    end

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

local function allowRequest(src, bucketName, maxRequests, windowMs)
    if type(src) ~= 'number' or src <= 0 then
        return false
    end

    local now = GetGameTimer()
    local playerBuckets = requestBuckets[src]
    if not playerBuckets then
        playerBuckets = {}
        requestBuckets[src] = playerBuckets
    end

    local bucket = playerBuckets[bucketName]
    if not bucket or now < bucket.startedAt or now - bucket.startedAt >= windowMs then
        playerBuckets[bucketName] = {
            startedAt = now,
            count = 1,
        }
        return true
    end

    if bucket.count >= maxRequests then
        return false
    end

    bucket.count = bucket.count + 1
    return true
end

local function getSessionIdentifier(src)
    local identifiers = GetPlayerIdentifiers(src)
    if type(identifiers) ~= 'table' then return nil end
    return identifiers[1]
end

local function sessionIdentifierMatches(src, expected)
    if type(expected) ~= 'string' or expected == '' or not GetPlayerName(src) then
        return false
    end

    local identifiers = GetPlayerIdentifiers(src)
    if type(identifiers) ~= 'table' then return false end
    for _, identifier in ipairs(identifiers) do
        if identifier == expected then return true end
    end
    return false
end

local function canOpenMenu(src)
    if IsPlayerAceAllowed(src, Config.Permissions.all)
        or IsPlayerAceAllowed(src, 'command.' .. Config.Command)
        or IsPlayerAceAllowed(src, 'command.esadmin')
        or IsPlayerAceAllowed(src, 'command.vmenu')
        or IsPlayerAceAllowed(src, 'vMenu.Everything') then
        return true
    end

    local vmenuMenus = {
        'vMenu.OnlinePlayers.Menu', 'vMenu.PlayerOptions.Menu', 'vMenu.VehicleOptions.Menu',
        'vMenu.VehicleSpawner.Menu', 'vMenu.SavedVehicles.Menu', 'vMenu.PersonalVehicle.Menu',
        'vMenu.PlayerAppearance.Menu', 'vMenu.TimeOptions.Menu', 'vMenu.WeatherOptions.Menu',
        'vMenu.WeaponOptions.Menu', 'vMenu.WeaponLoadouts.Menu', 'vMenu.VoiceChat.Menu',
        'vMenu.MiscSettings.Menu', 'vMenu.MiscSettings.All', 'vMenu.NoClip',
    }
    for index = 1, #vmenuMenus do
        if IsPlayerAceAllowed(src, vmenuMenus[index]) then return true end
    end

    return Config.HasQBX
        and EsAdminBridge
        and EsAdminBridge.isQBXAdmin
        and EsAdminBridge.isQBXAdmin(src) == true
end

local function sanitizeVariationPair(value, minDrawable)
    if type(value) ~= 'table' then
        return nil
    end

    local entryCount = 0
    for key in pairs(value) do
        if key ~= 1 and key ~= 2 then
            return nil
        end
        entryCount = entryCount + 1
    end

    if entryCount ~= 2 then
        return nil
    end

    local drawable = toInteger(value[1], minDrawable, 4096)
    local texture = toInteger(value[2], 0, 1024)
    if drawable == nil or texture == nil then
        return nil
    end

    return { drawable, texture }
end

local function sanitizeVariationMap(value, minId, maxId, minDrawable, maxEntries)
    if type(value) ~= 'table' then
        return nil
    end

    local sanitized = {}
    local count = 0

    for rawId, variation in pairs(value) do
        local id = toInteger(rawId, minId, maxId)
        local pair = sanitizeVariationPair(variation, minDrawable)
        if id == nil or pair == nil or sanitized[id] ~= nil then
            return nil
        end

        count = count + 1
        if count > maxEntries then
            return nil
        end
        sanitized[id] = pair
    end

    return sanitized
end

local function sanitizeWardrobe(outfit)
    if type(outfit) ~= 'table'
        or type(outfit.DrawableVariations) ~= 'table'
        or type(outfit.PropVariations) ~= 'table' then
        return nil
    end

    local clothes = sanitizeVariationMap(outfit.DrawableVariations.clothes, 0, 11, 0, 12)
    local props = sanitizeVariationMap(outfit.PropVariations.props, 0, 7, -1, 8)
    if not clothes or not props then
        return nil
    end

    return {
        Version = 1,
        DrawableVariations = { clothes = clothes },
        PropVariations = { props = props },
    }
end

local function sanitizeSerializable(value, depth, budget)
    local valueType = type(value)
    if valueType == 'boolean' then return value, true end
    if valueType == 'string' then
        if #value > 256 then return nil, false end
        return value, true
    end
    if valueType == 'number' then
        if value ~= value or value == math.huge or value == -math.huge or mathAbs(value) > 1000000000000 then
            return nil, false
        end
        return value, true
    end
    if valueType ~= 'table' or depth > 6 then
        return nil, false
    end

    local sanitized = {}
    for key, entry in pairs(value) do
        budget.count = budget.count + 1
        if budget.count > 384 then return nil, false end

        local keyType = type(key)
        if keyType == 'number' then
            if key ~= mathFloor(key) or key < -1 or key > 1024 then return nil, false end
        elseif keyType == 'string' then
            if key == '' or #key > 64 then return nil, false end
        else
            return nil, false
        end

        local cleanEntry, ok = sanitizeSerializable(entry, depth + 1, budget)
        if not ok then return nil, false end
        sanitized[key] = cleanEntry
    end

    return sanitized, true
end

local function sanitizeVehicleProps(props, model, plate)
    if type(props) ~= 'table' then return nil end

    local sanitized, ok = sanitizeSerializable(props, 1, { count = 0 })
    if not ok then return nil end
    sanitized.model = model
    sanitized.plate = trimString(plate, 16) or ''

    local encodedOk, encoded = pcall(json.encode, sanitized)
    if not encodedOk or type(encoded) ~= 'string' or #encoded > 65536 then
        return nil
    end
    return sanitized
end

local function arePlayersNearby(firstSource, secondSource, maxDistance)
    if GetPlayerRoutingBucket(firstSource) ~= GetPlayerRoutingBucket(secondSource) then
        return false
    end

    local firstPed = GetPlayerPed(firstSource)
    local secondPed = GetPlayerPed(secondSource)
    if not firstPed or firstPed <= 0 or not secondPed or secondPed <= 0 then
        return false
    end

    local firstCoords = GetEntityCoords(firstPed)
    local secondCoords = GetEntityCoords(secondPed)
    if not firstCoords or not secondCoords then
        return false
    end

    local dx = firstCoords.x - secondCoords.x
    local dy = firstCoords.y - secondCoords.y
    local dz = firstCoords.z - secondCoords.z
    local distanceSquared = dx * dx + dy * dy + dz * dz
    return WardrobeSharePolicy.isDistanceSquaredWithinRadius(distanceSquared, maxDistance)
end

local function hasPermission(src, actionId)
    -- Check for full admin access via cortex-admin ACE
    if IsPlayerAceAllowed(src, Config.Permissions.all) or IsPlayerAceAllowed(src, 'vMenu.Everything') then
        return true
    end

    local vmenuPermissions = Config.VmenuAcePermissions and Config.VmenuAcePermissions[actionId]
    if type(vmenuPermissions) == 'table' then
        for index = 1, #vmenuPermissions do
            local permission = vmenuPermissions[index]
            if type(permission) == 'string' and IsPlayerAceAllowed(src, permission) then return true end
        end
    end

    -- QBX Permission Bridge: When QBX is active, check if the player belongs to
    -- a configured QBX admin group (god, admin, mod, etc.) and resolve permissions
    -- from Config.QBXPermissions mapping. This lets QBX admins use the menu
    -- without needing separate cortex-admin.* ACE entries.
    if Config.HasQBX then
        local action = actionIndex[actionId]
        local tab = action and action.tab or actionId:match('^([^.]+)%.')
        local qbxResult = EsAdminBridge.checkQBXPermission(src, actionId, tab)
        if qbxResult == true then return true end
        if qbxResult == false then return false end
        -- nil = no QBX group matched, fall through to standard ACE checks
    end

    -- Check for specific action permission
    local actionPerm = Config.ActionPermissions[actionId]
    if actionPerm and IsPlayerAceAllowed(src, actionPerm) then
        return true
    end

    -- Check for tab-level permission
    local action = actionIndex[actionId]
    local tab = action and action.tab or actionId:match('^([^.]+)%.')
    if tab and Config.Permissions[tab] and IsPlayerAceAllowed(src, Config.Permissions[tab]) then
        return true
    end

    return false
end

EsAdminServer.hasPermission = hasPermission
EsAdminServer.canOpenMenu = canOpenMenu
EsAdminServer.allowRequest = allowRequest
EsAdminServer.toInteger = toInteger
EsAdminServer.toBoolean = toBoolean
EsAdminServer.trimString = trimString
EsAdminServer.sanitizeCoords = sanitizeCoords

local function buildPermissionSnapshot(src)
    local now = GetGameTimer()
    local cached = permissionCache[src]
    if cached and now < cached.expiresAt then
        return cached.allowed
    end

    local allowed = {}
    for _, action in ipairs(Actions.actions) do
        allowed[action.id] = hasPermission(src, action.id)
    end
    for actionId in pairs(Config.ActionPermissions or {}) do
        if allowed[actionId] == nil then
            allowed[actionId] = hasPermission(src, actionId)
        end
    end

    permissionCache[src] = {
        allowed = allowed,
        expiresAt = now + PERMISSION_CACHE_MS,
    }

    return allowed
end

RegisterNetEvent('cortex-admin:server:requestPermissions', function()
    local src = source
    if not allowRequest(src, 'menu-read', 12, 5000) or not canOpenMenu(src) then return end
    TriggerClientEvent('cortex-admin:client:permissions', src, buildPermissionSnapshot(src))
end)

local function buildPlayerDirectory(requester)
    local directory = {}
    local players = GetPlayers()
    for index = 1, #players do
        local playerSource = toInteger(players[index], 1, 65535)
        if playerSource and GetPlayerName(playerSource) then
            local ped = GetPlayerPed(playerSource)
            local health = ped and ped > 0 and DoesEntityExist(ped) and GetEntityHealth(ped) or nil
            directory[#directory + 1] = {
                id = playerSource,
                name = trimString(GetPlayerName(playerSource), 96) or ('Player %d'):format(playerSource),
                ping = toInteger(GetPlayerPing(playerSource), 0, 9999) or 0,
                bucket = toInteger(GetPlayerRoutingBucket(playerSource), 0, 65535) or 0,
                dead = health ~= nil and health <= 0 or false,
                isSelf = playerSource == requester,
            }
        end
    end
    table.sort(directory, function(first, second) return first.id < second.id end)
    return directory
end

RegisterNetEvent('cortex-admin:server:requestPlayerDirectory', function()
    local src = source
    if not allowRequest(src, 'player-directory-read', 6, 10000) or not canOpenMenu(src) then return end
    TriggerClientEvent('cortex-admin:client:setPlayerDirectory', src, buildPlayerDirectory(src))
end)

local function setWorldTime(hour, minute, changedState)
    hour = toInteger(hour, 0, 23)
    minute = toInteger(minute, 0, 59)
    if hour == nil or minute == nil then return false end

    worldState.hour = hour
    worldState.minute = minute
    changedState.hour = hour
    changedState.minute = minute
    return true
end

local function timeCommandReply(src, kind, message)
    if src == 0 then
        print('[cortex-admin] ' .. message)
    else
        TriggerClientEvent('cortex-admin:client:notify', src, kind, message)
    end
end

RegisterCommand('time', function(src, args)
    if src ~= 0 then
        if not allowRequest(src, 'privileged-write', 15, 5000) then return end
        if not hasPermission(src, 'world.time') then
            timeCommandReply(src, 'error', 'You do not have permission to set the time.')
            return
        end
    end

    local first = args[1] and args[1]:lower() == 'set' and 2 or 1
    local value = args[first] and args[first]:lower()
    local count = #args - first + 1
    local hour, minute
    if value == 'day' and count == 1 then
        hour, minute = 12, 0
    elseif value and value:match('^%d+$') and (count == 1 or count == 2) then
        local minuteArg = args[first + 1] or '0'
        if minuteArg:match('^%d+$') then
            hour, minute = value, minuteArg
        end
    end

    local changedState = {}
    if not setWorldTime(hour, minute, changedState) then
        timeCommandReply(src, 'error', 'Usage: /time [set] <day|hour> [minute]. Hour: 0-23; minute: 0-59 (default 00).')
        return
    end

    TriggerClientEvent('cortex-admin:client:updateWorldState', -1, changedState)
    timeCommandReply(src, 'success', ('Time set to %02d:%02d.'):format(changedState.hour, changedState.minute))
end, false) -- Authorization uses the same server-side world.time permission as the menu.

RegisterNetEvent('cortex-admin:server:setWorldState', function(payload)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
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
        setWorldTime(payload.hour, payload.minute, changedState)
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
        TriggerClientEvent('cortex-admin:client:updateWorldState', -1, changedState)
    end
end)

RegisterNetEvent('cortex-admin:server:requestWorldState', function()
    local src = source
    if not allowRequest(src, 'menu-read', 12, 5000) or not canOpenMenu(src) then return end
    if next(worldState) == nil then return end
    TriggerClientEvent('cortex-admin:client:updateWorldState', src, worldState)
end)

RegisterNetEvent('cortex-admin:server:setUiPresence', function(data)
    local src = source
    if not allowRequest(src, 'menu-presence', 8, 5000) or not canOpenMenu(src) then
        uiPresence[src] = nil
        return
    end
    if type(data) ~= 'table' then
        return
    end

    uiPresence[src] = data.open == true
end)

RegisterNetEvent('cortex-admin:server:requestWardrobeShareTargets', function(requestId)
    local src = source
    if not allowRequest(src, 'wardrobe-read', 6, 5000)
        or not canOpenMenu(src)
        or uiPresence[src] ~= true
        or type(requestId) ~= 'string'
        or requestId == ''
        or #requestId > 96 then
        return
    end

    local targets = {}
    for playerId, isOpen in pairs(uiPresence) do
        if playerId ~= src
            and isOpen == true
            and GetPlayerName(playerId)
            and arePlayersNearby(src, playerId, WARDROBE_SHARE_RADIUS) then
            targets[#targets + 1] = playerId
        end
    end

    table.sort(targets)
    TriggerClientEvent('cortex-admin:client:receiveWardrobeShareTargets', src, requestId, {
        radius = WARDROBE_SHARE_RADIUS,
        targets = targets,
    })
end)

RegisterNetEvent('cortex-admin:server:shareWardrobe', function(data)
    local src = source
    if not allowRequest(src, 'wardrobe-write', 3, 10000)
        or not canOpenMenu(src)
        or uiPresence[src] ~= true
        or type(data) ~= 'table' then
        return
    end

    local target = toInteger(data.target, 1)
    if not target or target == src or not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player is unavailable.')
        return
    end

    if uiPresence[target] ~= true then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player must have the menu open.')
        return
    end

    if not arePlayersNearby(src, target, WARDROBE_SHARE_RADIUS) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player must be nearby.')
        return
    end

    local outfit = sanitizeWardrobe(data.outfit)
    if not outfit then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Shared wardrobe payload was invalid.')
        return
    end

    local shareId = ('wardrobe:%d:%d:%d'):format(src, target, GetGameTimer())
    local senderName = GetPlayerName(src) or ('Player %d'):format(src)

    TriggerClientEvent('cortex-admin:client:receiveWardrobeShare', target, {
        shareId = shareId,
        senderId = src,
        senderName = senderName,
        title = trimString(data.title, 64) or 'Current Outfit',
        outfit = outfit,
    })

    TriggerClientEvent('cortex-admin:client:notify', src, 'success', ('Shared current outfit with %s.'):format(GetPlayerName(target) or ('Player %d'):format(target)))
    TriggerClientEvent('cortex-admin:client:notify', target, 'info', ('%s shared an outfit with you.'):format(senderName))
end)

RegisterNetEvent('cortex-admin:server:playerAction', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end

    local action = trimString(data.action, 16)
    local target = toInteger(data.target, 1)

    if not action or not allowedPlayerActions[action] or not target then return end
    if not GetPlayerName(target) then return end

    if action == 'kick' then
        if not hasPermission(src, 'player.kick') then return end
        if IsPlayerAceAllowed(target, 'vMenu.DontKickMe') then
            TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'That player is protected from kicks.')
            return
        end
        local reason = trimString(data.reason, 160) or 'Kicked by staff.'
        print(('[cortex-admin] %s kicked %s (%d): %s'):format(GetPlayerName(src) or 'Console', GetPlayerName(target) or 'Unknown', target, reason))
        DropPlayer(target, reason)
    elseif action == 'ban' then
        if not hasPermission(src, 'player.ban') then return end
        if IsPlayerAceAllowed(target, 'vMenu.DontBanMe') then
            TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'That player is protected from bans.')
            return
        end
        local identifiers = GetPlayerIdentifiers(target)
        local reason = trimString(data.reason, 160) or 'Banned by staff.'
        local duration = toInteger(data.duration, 0, 525600)
        if duration == nil then return end
        local adminName = GetPlayerName(src) or 'Console'
        local entry = EsAdminServer.addBan(identifiers, reason, adminName, duration, GetPlayerName(target))
        if not entry then
            TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'The ban could not be saved because no durable identifier was available.')
            return
        end
        print(('[cortex-admin] %s banned %s (%d, %s): %s'):format(adminName, GetPlayerName(target) or 'Unknown', target, entry.id or 'unknown', reason))
        DropPlayer(target, reason)
    elseif action == 'freeze' then
        if not hasPermission(src, 'player.freeze') then return end
        local enabled = toBoolean(data.enabled)
        if enabled == nil then return end
        TriggerClientEvent('cortex-admin:client:freeze', target, enabled)
    elseif action == 'bring' then
        if not hasPermission(src, 'player.bring') then return end
        local adminPed = GetPlayerPed(src)
        if not adminPed or adminPed <= 0 then return end
        local coords = sanitizeCoords(GetEntityCoords(adminPed))
        local heading = GetEntityHeading(adminPed)
        if not coords or not heading or heading ~= heading then return end
        heading = heading % 360
        TriggerClientEvent('cortex-admin:client:teleport', target, coords, heading)
    elseif action == 'goto' then
        if not hasPermission(src, 'player.goto') then return end
        if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) then
            TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target is in a different routing bucket.')
            return
        end
        local targetPed = GetPlayerPed(target)
        if not targetPed or targetPed <= 0 or not DoesEntityExist(targetPed) or GetEntityType(targetPed) ~= 1 then return end
        local coords = sanitizeCoords(GetEntityCoords(targetPed))
        local heading = GetEntityHeading(targetPed)
        if not coords or type(heading) ~= 'number' or heading ~= heading then return end
        TriggerClientEvent('cortex-admin:client:teleport', src, coords, heading % 360)
    end
end)

AddEventHandler('playerConnecting', function(name, setKickReason)
    local identifiers = GetPlayerIdentifiers(source)
    local entry = EsAdminServer.findBan(identifiers)
    if entry then
        local expiresAt = entry.expiresAt or entry.expires
        local expiresText = expiresAt and os.date('%c', expiresAt) or 'Never'
        setKickReason(('Banned: %s (Expires: %s)'):format(entry.reason or 'No reason', expiresText))
        CancelEvent()
    end
end)

AddEventHandler('playerDropped', function()
    uiPresence[source] = nil
    permissionCache[source] = nil
    requestBuckets[source] = nil
    pendingAdminCarRequests[source] = nil
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
local VEHICLE_META_DATA_TYPE = 'VEHICLE_METADATA_FILE'

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
    local normalized = trim(value):gsub('\\', '/')
    normalized = normalized:gsub('/+', '/')
    return normalized
end

local function getResourceRoot(resourceName)
    return normalizePath(GetResourcePath(resourceName) or '')
end

local function resolveResourceFile(resourceName, rawPath)
    local path = normalizePath(stripQuotes(rawPath))
    if path == '' then
        return nil, nil
    end

    local linkedResource, linkedPath = path:match('^@([^/]+)/(.+)$')
    if linkedResource and linkedPath then
        return trim(linkedResource), normalizePath(linkedPath)
    end

    return resourceName, path
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

local function parseDataFileExtra(extra)
    if type(extra) ~= 'string' or extra == '' then
        return nil
    end

    local filePath = extra:match('^%s*%[%s*"([^"]+)"')
        or extra:match("^%s*%[%s*'([^']+)'")
        or extra:match('"file"%s*:%s*"([^"]+)"')
        or extra:match("'file'%s*:%s*'([^']+)'")
        or extra:match('"filename"%s*:%s*"([^"]+)"')
        or extra:match("'filename'%s*:%s*'([^']+)'")
        or extra:match('"path"%s*:%s*"([^"]+)"')
        or extra:match("'path'%s*:%s*'([^']+)'")

    return filePath and stripQuotes(filePath) or nil
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

local function getRelativeResourcePath(resourceRoot, absolutePath)
    local root = normalizePath(resourceRoot)
    local absolute = normalizePath(absolutePath)
    if root == '' or absolute == '' then
        return nil
    end

    if absolute:lower():sub(1, #root) ~= root:lower() then
        return nil
    end

    return normalizePath(absolute:sub(#root + 1):gsub('^/', ''))
end

local function wildcardToPattern(wildcard)
    local pattern = normalizePath(wildcard):lower()
    pattern = pattern:gsub('([%^%$%(%)%%%.%[%]%+%-%?])', '%%%1')
    pattern = pattern:gsub('%*%*', '\0')
    pattern = pattern:gsub('%*', '[^/]*')
    pattern = pattern:gsub('\0', '.*')
    return '^' .. pattern .. '$'
end

local function pathMatchesWildcard(path, wildcard)
    return normalizePath(path):lower():match(wildcardToPattern(wildcard)) ~= nil
end

local function makeVehicleTargetKey(dataResourceName, path)
    return ('%s|%s'):format((dataResourceName or ''):lower(), (path or ''):lower())
end

local function addVehicleMetaTarget(targets, seen, ownerResourceName, dataResourceName, path)
    local normalized = normalizePath(path)
    if trim(dataResourceName) == '' or normalized == '' then
        return false
    end

    local key = makeVehicleTargetKey(dataResourceName, normalized)
    if seen[key] then
        return false
    end

    seen[key] = true
    targets[#targets + 1] = {
        ownerResource = ownerResourceName,
        dataResource = dataResourceName,
        path = normalized,
    }
    return true
end

local function getWildcardFallbackPaths(wildcardPath)
    local paths = {}
    local seen = {}

    local function push(path)
        local normalized = normalizePath(path):gsub('^/', '')
        if normalized == '' or seen[normalized:lower()] then
            return
        end
        seen[normalized:lower()] = true
        paths[#paths + 1] = normalized
    end

    local compact = normalizePath(wildcardPath)
    compact = compact:gsub('/%*%*/', '/')
    compact = compact:gsub('%*%*/', '')
    compact = compact:gsub('/%*', '/')
    compact = compact:gsub('%*', '')
    compact = compact:gsub('/+', '/')

    push(compact)
    push('data/vehicles.meta')
    push('vehicles.meta')

    return paths
end

local function expandVehicleMetaPattern(ownerResourceName, dataResourceName, wildcardPath, targets, seen, stats)
    local root = getResourceRoot(dataResourceName)
    if root == '' then
        return
    end

    local before = #targets
    local files = listFilesRecursively(root)
    for i = 1, #files do
        local relative = getRelativeResourcePath(root, files[i])
        if relative and pathMatchesWildcard(relative, wildcardPath) then
            if addVehicleMetaTarget(targets, seen, ownerResourceName, dataResourceName, relative) then
                stats.resolvedMetaFiles = stats.resolvedMetaFiles + 1
            end
        end
    end

    if #targets > before then
        return
    end

    local fallbackPaths = getWildcardFallbackPaths(wildcardPath)
    for i = 1, #fallbackPaths do
        local path = fallbackPaths[i]
        if LoadResourceFile(dataResourceName, path) then
            if addVehicleMetaTarget(targets, seen, ownerResourceName, dataResourceName, path) then
                stats.resolvedMetaFiles = stats.resolvedMetaFiles + 1
            end
        end
    end
end

local function collectVehicleMetaTargetsFromManifest(resourceName, targets, seen, stats)
    local manifest = LoadResourceFile(resourceName, 'fxmanifest.lua')
        or LoadResourceFile(resourceName, '__resource.lua')
    if type(manifest) ~= 'string' or manifest == '' then
        return false
    end

    local foundDeclaration = false
    for line in manifest:gmatch('[^\r\n]+') do
        local dataType, filePath = line:match("data_file%s*%(%s*['\"]([^'\"]+)['\"]%s*,?%s*['\"]([^'\"]+)['\"]")
        if not dataType then
            dataType, filePath = line:match("data_file%s+['\"]([^'\"]+)['\"]%s+['\"]([^'\"]+)['\"]")
        end

        if stripQuotes(dataType):upper() == VEHICLE_META_DATA_TYPE then
            foundDeclaration = true
            stats.vehicleMetaDeclarations = stats.vehicleMetaDeclarations + 1

            local dataResourceName, resolvedPath = resolveResourceFile(resourceName, filePath)
            if dataResourceName and resolvedPath then
                if resolvedPath:find('*', 1, true) then
                    expandVehicleMetaPattern(resourceName, dataResourceName, resolvedPath, targets, seen, stats)
                elseif LoadResourceFile(dataResourceName, resolvedPath) then
                    if addVehicleMetaTarget(targets, seen, resourceName, dataResourceName, resolvedPath) then
                        stats.resolvedMetaFiles = stats.resolvedMetaFiles + 1
                    end
                else
                    stats.missingMetaFiles = stats.missingMetaFiles + 1
                end
            end
        end
    end

    return foundDeclaration
end

local function collectVehicleMetaTargets(resourceName, targets, seen, stats)
    local count = GetNumResourceMetadata(resourceName, 'data_file') or 0
    local foundDeclaration = false

    for i = 0, count - 1 do
        local rawEntry = GetResourceMetadata(resourceName, 'data_file', i)
        local dataType, filePath = parseDataFileEntry(rawEntry)
        if not dataType and type(rawEntry) == 'string' then
            dataType = stripQuotes(rawEntry):upper()
            filePath = parseDataFileExtra(GetResourceMetadata(resourceName, 'data_file_extra', i))
        end

        if dataType == VEHICLE_META_DATA_TYPE and filePath then
            foundDeclaration = true
            stats.vehicleMetaDeclarations = stats.vehicleMetaDeclarations + 1

            local dataResourceName, resolvedPath = resolveResourceFile(resourceName, filePath)
            if dataResourceName and resolvedPath then
                if resolvedPath:find('*', 1, true) then
                    expandVehicleMetaPattern(resourceName, dataResourceName, resolvedPath, targets, seen, stats)
                elseif LoadResourceFile(dataResourceName, resolvedPath) then
                    if addVehicleMetaTarget(targets, seen, resourceName, dataResourceName, resolvedPath) then
                        stats.resolvedMetaFiles = stats.resolvedMetaFiles + 1
                    end
                else
                    stats.missingMetaFiles = stats.missingMetaFiles + 1
                end
            end
        end
    end

    if not foundDeclaration then
        foundDeclaration = collectVehicleMetaTargetsFromManifest(resourceName, targets, seen, stats)
    end

    return foundDeclaration
end

local function readXmlTag(block, tagName)
    local value = block:match('<%s*' .. tagName .. '%s*>%s*([^<]-)%s*<%s*/%s*' .. tagName .. '%s*>')
    return trim(value)
end

local function parseVehiclesMeta(xml, target, byModel, stats, metadataResources)
    if type(xml) ~= 'string' or xml == '' then
        return
    end

    for item in xml:gmatch('<%s*Item[^>]*>(.-)<%s*/%s*Item%s*>') do
        local model = readXmlTag(item, 'modelName'):lower()
        if model ~= '' then
            if byModel[model] then
                stats.duplicateModels = stats.duplicateModels + 1
            else
                local gameName = readXmlTag(item, 'gameName')
                local makeName = readXmlTag(item, 'vehicleMakeName')

                byModel[model] = {
                    model = model,
                    name = gameName ~= '' and gameName or prettifyModelName(model),
                    gameName = gameName ~= '' and gameName or nil,
                    makeName = makeName ~= '' and makeName or nil,
                    resource = target.ownerResource,
                    metaPath = target.path,
                    sourceType = 'metadata',
                    ownerResource = target.ownerResource,
                    dataResource = target.dataResource,
                }

                stats.metadataModels = stats.metadataModels + 1
                metadataResources[target.ownerResource] = true
            end
        end
    end
end

local function collectStreamFallbackModels(resourceName, byModel, stats)
    local root = getResourceRoot(resourceName)
    if root == '' then
        return
    end

    local files = listFilesRecursively(root)
    local added = 0
    for i = 1, #files do
        local relative = getRelativeResourcePath(root, files[i])
        local lower = relative and relative:lower() or ''
        local inStreamFolder = lower:sub(1, 7) == 'stream/' or lower:find('/stream/', 1, true) ~= nil
        if inStreamFolder and lower:sub(-4) == '.yft' and lower:sub(-7) ~= '_hi.yft' then
            local model = lower:match('([^/]+)%.yft$')
            if model and model ~= '' then
                if byModel[model] then
                    stats.duplicateModels = stats.duplicateModels + 1
                else
                    byModel[model] = {
                        model = model,
                        name = prettifyModelName(model),
                        resource = resourceName,
                        metaPath = relative,
                        sourceType = 'stream_fallback',
                        ownerResource = resourceName,
                        dataResource = resourceName,
                    }
                    stats.streamFallbackModels = stats.streamFallbackModels + 1
                    added = added + 1
                end
            end
        end
    end

    if added > 0 then
        stats.streamFallbackResources = stats.streamFallbackResources + 1
    end
end

local function getStartedResources()
    local resources = {}
    local count = GetNumResources()
    for i = 0, count - 1 do
        local resourceName = GetResourceByFindIndex(i)
        if resourceName and GetResourceState(resourceName) == 'started' then
            resources[#resources + 1] = resourceName
        end
    end
    return resources
end

local function getAddonVehicles(forceRefresh)
    local now = GetGameTimer()
    if not forceRefresh and now < addonVehiclesCache.expiresAt then
        return addonVehiclesCache.list
    end

    local byModel = {}
    local metadataResources = {}
    local metaTargets = {}
    local seenMetaTargets = {}
    local resourcesWithVehicleMeta = {}
    local stats = {
        startedResources = 0,
        vehicleMetaResources = 0,
        vehicleMetaDeclarations = 0,
        resolvedMetaFiles = 0,
        missingMetaFiles = 0,
        parsedMetaFiles = 0,
        metadataModels = 0,
        streamFallbackModels = 0,
        streamFallbackResources = 0,
        duplicateModels = 0,
    }

    local resources = getStartedResources()
    stats.startedResources = #resources

    for i = 1, #resources do
        local resourceName = resources[i]
        if collectVehicleMetaTargets(resourceName, metaTargets, seenMetaTargets, stats) then
            resourcesWithVehicleMeta[resourceName] = true
            stats.vehicleMetaResources = stats.vehicleMetaResources + 1
        end
    end

    for i = 1, #metaTargets do
        local target = metaTargets[i]
        local content = LoadResourceFile(target.dataResource, target.path)
        if content and content ~= '' then
            stats.parsedMetaFiles = stats.parsedMetaFiles + 1
            parseVehiclesMeta(content, target, byModel, stats, metadataResources)
        end
    end

    for resourceName in pairs(resourcesWithVehicleMeta) do
        if not metadataResources[resourceName] then
            collectStreamFallbackModels(resourceName, byModel, stats)
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

    if Config.Debug or #list == 0 then
        print(('[cortex-admin] Addon vehicle scan indexed %d models (metadata: %d, stream fallback: %d, duplicates: %d, started resources: %d, vehicle meta resources: %d, declarations: %d, resolved meta files: %d, missing meta files: %d, parsed meta files: %d, fallback resources: %d)'):format(
            #list,
            stats.metadataModels,
            stats.streamFallbackModels,
            stats.duplicateModels,
            stats.startedResources,
            stats.vehicleMetaResources,
            stats.vehicleMetaDeclarations,
            stats.resolvedMetaFiles,
            stats.missingMetaFiles,
            stats.parsedMetaFiles,
            stats.streamFallbackResources
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
    print(('[cortex-admin] addon vehicle cache invalidated (%s)'):format(reason or 'unspecified'))
end

RegisterNetEvent('cortex-admin:server:requestAddonVehicles', function()
    local src = source
    if not allowRequest(src, 'expensive-read', 4, 10000) then return end
    if not canOpenMenu(src) or not hasPermission(src, 'vehicle.spawn') then return end
    local vehicles = getAddonVehicles(false)
    TriggerClientEvent('cortex-admin:client:setAddonVehicles', src, vehicles)
end)

RegisterNetEvent('cortex-admin:server:takePhoto', function()
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if not hasPermission(src, 'dev.takePhoto') then return end

    if GetResourceState('screenshot-basic') ~= 'started' then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'screenshot-basic is not running.')
        return
    end

    if not ensurePhotoCaptureDir() then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed to prepare the photo output folder.')
        return
    end

    local sessionIdentifier = getSessionIdentifier(src)
    if not sessionIdentifier then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not verify your player session.')
        return
    end

    local absolutePath, relativePath = buildPhotoCapturePath(src)

    exports['screenshot-basic']:requestClientScreenshot(src, {
        fileName = absolutePath,
        encoding = 'jpg',
        quality = 0.95,
    }, function(err)
        if not sessionIdentifierMatches(src, sessionIdentifier) then return end

        if err then
            print(('[cortex-admin] failed to capture photo for %s (%d): %s'):format(GetPlayerName(src) or 'unknown', src, tostring(err)))
            TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Photo capture failed.')
            return
        end

        TriggerClientEvent('cortex-admin:client:copyText', src, absolutePath)
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', ('Photo saved to %s. Full path copied to clipboard.'):format(relativePath))
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

RegisterNetEvent('cortex-admin:server:requestResources', function()
    local src = source
    if not allowRequest(src, 'expensive-read', 4, 10000) then return end
    if not hasPermission(src, 'server.resources') then return end
    
    TriggerClientEvent('cortex-admin:client:setResources', src, getResourceList())
end)

RegisterNetEvent('cortex-admin:server:resourceAction', function(data)
    local src = source
    if not allowRequest(src, 'resource-write', 4, 10000) then return end
    if type(data) ~= 'table' then return end

    local action = trimString(data.action, 16)
    local name = trimString(data.name, 64)

    if not action or not allowedResourceActions[action] or not name then return end
    if not hasPermission(src, 'server.resources') then return end
    if action == 'refresh' then
        ExecuteCommand('refresh')
        print(string.format('^3[cortex-admin] ^7Admin %s triggered global resource refresh', GetPlayerName(src)))
        TriggerClientEvent('cortex-admin:client:notify', src, 'info', 'Resource list refreshed')
        TriggerClientEvent('cortex-admin:client:setResources', src, getResourceList())
        return
    end

    if GetResourceState(name) == 'missing' then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', ('Resource not found: %s'):format(name))
        return
    end

    if action == 'start' then
        if GetResourceState(name) == 'stopped' then
            StartResource(name)
            print(string.format('^3[cortex-admin] ^7Admin %s started resource: %s', GetPlayerName(src), name))
            TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Started %s', name))
        else
            TriggerClientEvent('cortex-admin:client:notify', src, 'error', string.format('%s is already %s', name, GetResourceState(name)))
        end
    elseif action == 'stop' then
        if GetResourceState(name) == 'started' then
            StopResource(name)
            print(string.format('^3[cortex-admin] ^7Admin %s stopped resource: %s', GetPlayerName(src), name))
            TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Stopped %s', name))
        else
            TriggerClientEvent('cortex-admin:client:notify', src, 'error', string.format('%s is not running', name))
        end
    elseif action == 'ensure' or action == 'restart' then
        StopResource(name)
        StartResource(name)
        print(string.format('^3[cortex-admin] ^7Admin %s restarted resource: %s', GetPlayerName(src), name))
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Restarted %s', name))
    end

    -- Send updated list back to the sender
    TriggerClientEvent('cortex-admin:client:setResources', src, getResourceList())
end)

AddEventHandler('playerJoining', function()
    if next(worldState) == nil then return end
    TriggerClientEvent('cortex-admin:client:updateWorldState', source, worldState)
end)

-- =============================================================================
-- INVENTORY MANAGEMENT (QBX / ox_inventory)
-- =============================================================================

RegisterNetEvent('cortex-admin:server:getItems', function()
    local src = source
    if not allowRequest(src, 'expensive-read', 4, 10000) then return end
    if not hasPermission(src, 'inventory.giveItem') then return end

    local items = EsAdminBridge.getAllItems()
    if type(items) ~= 'table' then
        items = {}
    end

    TriggerClientEvent('cortex-admin:client:setItems', src, items)
end)

RegisterNetEvent('cortex-admin:server:giveItem', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'inventory.giveItem') then return end

    local target = toInteger(data.target, 1)
    local itemName = trimString(data.item, 64)
    local amount = toInteger(data.amount, 1, 10000)

    if not target or not itemName or not amount then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end

    -- Verify target is online
    local targetName = GetPlayerName(target)
    if not targetName then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local success, err = EsAdminBridge.giveItem(target, itemName, amount)

    if success then
        local adminName = GetPlayerName(src) or 'Admin'
        print(string.format('^3[cortex-admin] ^7%s gave %dx %s to %s (ID: %d)', adminName, amount, itemName, targetName, target))
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Gave %dx %s to %s', amount, itemName, targetName))
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', err or 'Failed to give item')
    end
end)

-- =============================================================================
-- GARAGE MANAGEMENT (QBX / qbx_vehicles)
-- =============================================================================

RegisterNetEvent('cortex-admin:server:getPlayerGarage', function()
    local src = source
    if not allowRequest(src, 'expensive-read', 4, 10000) then return end
    if not hasPermission(src, 'garage.spawnVehicle') then return end

    local citizenid = EsAdminBridge.getPlayerCitizenId(src)
    if not citizenid then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not determine your citizen ID')
        return
    end

    local vehicles = EsAdminBridge.getPlayerVehicles(citizenid)
    if type(vehicles) ~= 'table' then
        vehicles = {}
    end

    TriggerClientEvent('cortex-admin:client:setGarageVehicles', src, vehicles)
end)

RegisterNetEvent('cortex-admin:server:spawnGarageVehicle', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'garage.spawnVehicle') then return end

    local vehicleId = toInteger(data.vehicleId, 1, 2147483647)
    if not vehicleId then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid vehicle ID')
        return
    end

    local citizenid = EsAdminBridge.getPlayerCitizenId(src)
    if not citizenid then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not determine your citizen ID')
        return
    end

    -- Fetch the specific vehicle to verify ownership
    local vehicles = EsAdminBridge.getPlayerVehicles(citizenid)
    if type(vehicles) ~= 'table' then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Garage data is unavailable right now')
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
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Vehicle not found in your garage')
        return
    end

    if type(EsAdminServer.authorizeModel) ~= 'function' then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Server model authorization is unavailable')
        return
    end
    local modelAllowed, modelReason = EsAdminServer.authorizeModel(src, 'vehicle', targetVehicle.model, 'garage.spawnVehicle')
    if not modelAllowed then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', modelReason == 'model_forbidden'
            and 'Your ACE permissions do not allow that whitelisted vehicle model'
            or 'Vehicle model authorization failed')
        return
    end

    -- Send vehicle data to client for spawning
    TriggerClientEvent('cortex-admin:client:spawnGarageVehicle', src, {
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

RegisterNetEvent('cortex-admin:server:giveVehicleKeys', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    local silent = type(data) == 'table' and data.silent == true

    if type(data) ~= 'table' then return end
    local authorizationActionId = trimString(data.authorizationActionId, 96)
    local keyGrantActions = {
        ['vehicle.giveKeys'] = true,
        ['vehicle.spawn'] = true,
        ['vehicle.personal'] = true,
        ['vehicle.load'] = true,
        ['garage.spawnVehicle'] = true,
    }
    if not authorizationActionId or keyGrantActions[authorizationActionId] ~= true
        or (not silent and authorizationActionId ~= 'vehicle.giveKeys')
        or not hasPermission(src, authorizationActionId) then return end

    local function notifyError(message)
        if silent then return end
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', message)
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
        local netId = toInteger(data.netId, 1, 65535)
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

    if GetEntityType(vehicle) ~= 2 then
        notifyError('The selected entity is not a vehicle')
        return
    end

    local vehicleModel = GetEntityModel(vehicle)
    if type(EsAdminServer.consumeModelAuthorization) ~= 'function'
        or not EsAdminServer.consumeModelAuthorization(
            src,
            data.authorizationToken,
            'vehicle',
            authorizationActionId,
            vehicleModel
        ) then
        notifyError('Vehicle model authorization expired or did not match this vehicle')
        return
    end

    local success, err = giveVehicleKeys(src, vehicle)
    if not success then
        notifyError(('Failed to give keys: %s'):format(err))
        return
    end

    if not silent then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', 'Vehicle keys granted')
    end
end)

-- =============================================================================
-- QBX PLAYER MANAGEMENT COMMANDS
-- =============================================================================

RegisterNetEvent('cortex-admin:server:killPlayer', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.kill') then return end

    local target = toInteger(data.target, 1)
    if not target or not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    TriggerClientEvent('cortex-admin:client:killPed', target)
    local adminName = GetPlayerName(src) or 'Admin'
    print(string.format('^3[cortex-admin] ^7%s killed %s (ID: %d)', adminName, GetPlayerName(target), target))
    TriggerClientEvent('cortex-admin:client:notify', src, 'success', 'Killed ' .. GetPlayerName(target))
end)

RegisterNetEvent('cortex-admin:server:revivePlayer', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.reviveTarget') then return end

    local target = toInteger(data.target, 1)
    if not target or not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    TriggerClientEvent('cortex-admin:client:revivePed', target)
    local adminName = GetPlayerName(src) or 'Admin'
    print(string.format('^3[cortex-admin] ^7%s revived %s (ID: %d)', adminName, GetPlayerName(target), target))
    TriggerClientEvent('cortex-admin:client:notify', src, 'success', 'Revived ' .. GetPlayerName(target))
end)

RegisterNetEvent('cortex-admin:server:sitInVehicle', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.sitInVehicle') then return end

    local target = toInteger(data.target, 1)
    if not target or not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    if GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target is in a different routing bucket')
        return
    end

    local targetPed = GetPlayerPed(target)
    if not targetPed or targetPed == 0 or not DoesEntityExist(targetPed) or GetEntityType(targetPed) ~= 1 then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player entity is unavailable')
        return
    end
    local veh = GetVehiclePedIsIn(targetPed, false)
    if veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target is not in a vehicle')
        return
    end

    -- Get target vehicle's net ID and send to admin client
    local netId = NetworkGetNetworkIdFromEntity(veh)
    if not toInteger(netId, 1, 65535) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target vehicle is not networked')
        return
    end
    TriggerClientEvent('cortex-admin:client:sitInVehicle', src, netId)
end)

RegisterNetEvent('cortex-admin:server:setJob', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.setJob') then return end
    if not Config.HasQBX then return end

    local target = toInteger(data.target, 1)
    local jobName = trimString(data.job, 64)
    local jobGrade = toInteger(data.grade, 0, 99)
    if not target or not jobName or jobGrade == nil then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        player.Functions.SetJob(jobName, jobGrade)
    end)

    if ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Set %s job to %s (grade %d)', GetPlayerName(target), jobName, jobGrade))
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('cortex-admin:server:setGang', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.setGang') then return end
    if not Config.HasQBX then return end

    local target = toInteger(data.target, 1)
    local gangName = trimString(data.gang, 64)
    local gangGrade = toInteger(data.grade, 0, 99)
    if not target or not gangName or gangGrade == nil then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        player.Functions.SetGang(gangName, gangGrade)
    end)

    if ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Set %s gang to %s (grade %d)', GetPlayerName(target), gangName, gangGrade))
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('cortex-admin:server:setMoney', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not Config.HasQBX then return end

    local actionId = trimString(data.actionId, 64)
    local moneyType = actionId and moneyActions[actionId]
    if not moneyType or not hasPermission(src, actionId) then return end

    local target = toInteger(data.target, 1)
    local amount = toInteger(data.amount, 0, 1000000000)
    if not target or amount == nil then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        player.Functions.SetMoney(moneyType, amount, 'admin-set')
    end)

    if ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Set %s %s to $%s', GetPlayerName(target), moneyType, tostring(amount)))
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('cortex-admin:server:giveMoney', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.giveMoney') then return end
    if not Config.HasQBX then return end

    local target = toInteger(data.target, 1)
    local moneyType = trimString(data.moneyType, 32)
    local amount = toInteger(data.amount, 1, 1000000000)
    if not target or not moneyType or not allowedMoneyTypes[moneyType] or not amount or amount <= 0 then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        player.Functions.AddMoney(moneyType, amount, 'admin-give')
    end)

    if ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Gave $%s %s to %s', tostring(amount), moneyType, GetPlayerName(target)))
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('cortex-admin:server:setMetadata', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not Config.HasQBX then return end

    local actionId = trimString(data.actionId, 64)
    local key = actionId and metadataActions[actionId]
    if not key or not hasPermission(src, actionId) then return end

    local target = toInteger(data.target, 1)
    local value = toInteger(data.value, 0, 100)

    if actionId == 'dev.setStress' and target ~= src then return end

    if not target or value == nil then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Invalid parameters')
        return
    end
    if not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local player = EsAdminBridge.getPlayer(target)
    if not player then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not get QBX player data')
        return
    end

    local ok, err = pcall(function()
        player.Functions.SetMetaData(key, value)
    end)

    if ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Set %s %s to %s', GetPlayerName(target), key, tostring(value)))
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed: ' .. tostring(err))
    end
end)

RegisterNetEvent('cortex-admin:server:openInventory', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.openInventory') then return end
    if not Config.HasOxInventory then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'No inventory system detected')
        return
    end

    local target = toInteger(data.target, 1)
    if not target or not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    local ok, err = pcall(function()
        exports.ox_inventory:forceOpenInventory(src, 'player', target)
    end)

    if not ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed to open inventory: ' .. tostring(err))
    end
end)

RegisterNetEvent('cortex-admin:server:setRoutingBucket', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'player.setRoutingBucket') then return end

    local target = toInteger(data.target, 1)
    local bucket = toInteger(data.bucket, 0, 65535)
    if not target or bucket == nil or not GetPlayerName(target) then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Target player not found')
        return
    end

    SetPlayerRoutingBucket(target, bucket)
    TriggerClientEvent('cortex-admin:client:notify', src, 'success', string.format('Set %s routing bucket to %d', GetPlayerName(target), bucket))
end)

RegisterNetEvent('cortex-admin:server:adminCar', function()
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if not hasPermission(src, 'vehicle.adminCar') then return end
    if not Config.HasQBX or not Config.HasQBXVehicles then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'QBX vehicles not available')
        return
    end

    local citizenid = EsAdminBridge.getPlayerCitizenId(src)
    if not citizenid then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not determine your citizen ID')
        return
    end

    pendingAdminCarRequests[src] = GetGameTimer() + ADMIN_CAR_REQUEST_MS

    -- Request vehicle props from client
    TriggerClientEvent('cortex-admin:client:getVehicleProps', src)
end)

RegisterNetEvent('cortex-admin:server:adminCarSave', function(data)
    local src = source
    if not allowRequest(src, 'admin-car-save', 2, 10000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'vehicle.adminCar') then return end
    if not Config.HasQBX or not Config.HasQBXVehicles then return end

    local deadline = pendingAdminCarRequests[src]
    pendingAdminCarRequests[src] = nil
    if not deadline or GetGameTimer() > deadline then return end

    local citizenid = EsAdminBridge.getPlayerCitizenId(src)
    if not citizenid then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Could not determine your citizen ID')
        return
    end

    local ped = GetPlayerPed(src)
    local vehicle = ped and GetVehiclePedIsIn(ped, false) or 0
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'You must remain inside the vehicle being saved')
        return
    end

    local model = GetEntityModel(vehicle)
    if toInteger(data.model) ~= model then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Vehicle changed before it could be saved')
        return
    end

    local props = sanitizeVehicleProps(data.props, model, GetVehicleNumberPlateText(vehicle))
    if not props then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'No vehicle data')
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
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', 'Vehicle saved to your garage')
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed to save vehicle: ' .. tostring(result))
    end
end)

RegisterNetEvent('cortex-admin:server:pullStash', function(data)
    local src = source
    if not allowRequest(src, 'privileged-write', 15, 5000) then return end
    if type(data) ~= 'table' then return end
    if not hasPermission(src, 'server.pullStash') then return end
    if not Config.HasOxInventory then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'No inventory system detected')
        return
    end

    local stashName = trimString(data.stash, 80)
    if not stashName then
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Stash name required')
        return
    end

    local ok, err = pcall(function()
        exports.ox_inventory:forceOpenInventory(src, 'stash', stashName)
    end)

    if ok then
        TriggerClientEvent('cortex-admin:client:notify', src, 'success', 'Opened stash: ' .. stashName)
    else
        TriggerClientEvent('cortex-admin:client:notify', src, 'error', 'Failed to open stash: ' .. tostring(err))
    end
end)
