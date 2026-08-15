local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

dofile(resourceRoot .. '/shared/config.lua')
dofile(resourceRoot .. '/shared/wardrobe_share.lua')

local configuredRadius = 6.5
Config.WardrobeShareRadius = configuredRadius
Config.Permissions = Config.Permissions or {}
Config.Permissions.all = Config.Permissions.all or 'cortex-admin.all'
Config.ActionPermissions = Config.ActionPermissions or {}
Config.HasQBX = false

EsAdminActions = { actions = {} }
EsAdminServer = {}
EsAdminBridge = {}

local handlers = {}
local clientEvents = {}
local clock = 0
local playerCoords = {
    [1] = { x = 0.0, y = 0.0, z = 0.0 },
    [2] = { x = 0.0, y = 0.0, z = 0.0 },
}

function RegisterNetEvent(name, handler)
    handlers[name] = handler
end

function AddEventHandler() end

function TriggerClientEvent(name, target, ...)
    clientEvents[#clientEvents + 1] = {
        name = name,
        target = target,
        args = { ... },
    }
end

function GetGameTimer()
    clock = clock + 10001
    return clock
end

function IsPlayerAceAllowed()
    return true
end

function GetPlayerName(playerId)
    if playerId == 1 then return 'Sender' end
    if playerId == 2 then return 'Recipient' end
    return nil
end

function GetPlayerIdentifiers(playerId)
    return { ('license:%d'):format(playerId) }
end

function GetPlayerRoutingBucket()
    return 0
end

function GetPlayerPed(playerId)
    return playerId
end

function GetEntityCoords(ped)
    return playerCoords[ped]
end

function GetCurrentResourceName()
    return 'cortex-admin'
end

function GetResourcePath()
    return resourceRoot
end

-- Other handlers capture these globals but do not execute them in this focused test.
json = { encode = function() return '{}' end, decode = function() return {} end }
exports = {}

local printed = print
print = function() end
dofile(resourceRoot .. '/server/permissions.lua')
dofile(resourceRoot .. '/server/main.lua')
print = printed

local function invoke(name, playerId, ...)
    source = playerId
    assert(handlers[name], ('missing handler %s'):format(name))(...)
    source = nil
end

local function clearEvents()
    clientEvents = {}
end

local function findEvent(name, target)
    for index = 1, #clientEvents do
        local event = clientEvents[index]
        if event.name == name and (target == nil or event.target == target) then
            return event
        end
    end
    return nil
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local function setMenuPresence(playerId)
    invoke('cortex-admin:server:setUiPresence', playerId, { open = true })
end

local function discoverAt(distance)
    playerCoords[2].x = distance
    clearEvents()
    invoke('cortex-admin:server:requestWardrobeShareTargets', 1, 'boundary-test')
    local event = assert(findEvent('cortex-admin:client:receiveWardrobeShareTargets', 1), 'target response missing')
    local response = event.args[2]
    assertEqual(type(response), 'table', 'target response shape')
    assertEqual(response.radius, configuredRadius, 'server-owned response radius')
    assertEqual(type(response.targets), 'table', 'target list shape')
    return response.targets
end

setMenuPresence(1)
setMenuPresence(2)

assertEqual(discoverAt(configuredRadius - 0.000001)[1], 2, 'target just inside radius')
assertEqual(discoverAt(configuredRadius)[1], 2, 'target exactly on radius')
assertEqual(#discoverAt(configuredRadius + 0.000001), 0, 'target just outside radius')

local validOutfit = {
    DrawableVariations = { clothes = {} },
    PropVariations = { props = {} },
}

playerCoords[2].x = configuredRadius
clearEvents()
invoke('cortex-admin:server:shareWardrobe', 1, {
    target = 2,
    title = 'Boundary outfit',
    outfit = validOutfit,
})
assert(findEvent('cortex-admin:client:receiveWardrobeShare', 2), 'share exactly on radius should be accepted')

playerCoords[2].x = configuredRadius + 0.000001
clearEvents()
invoke('cortex-admin:server:shareWardrobe', 1, {
    target = 2,
    title = 'Outside outfit',
    outfit = validOutfit,
})
assertEqual(findEvent('cortex-admin:client:receiveWardrobeShare', 2), nil, 'share just outside radius')

print('wardrobe share server boundary tests passed')
