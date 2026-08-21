local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

local function readSource(relativePath)
    local file = assert(io.open(resourceRoot .. '/' .. relativePath, 'rb'))
    local source = file:read('*a')
    file:close()
    return source:gsub('\r\n', '\n')
end

local function assertContains(source, fragment, message)
    assert(source:find(fragment, 1, true), message or ('missing source contract: ' .. fragment))
end

local actions = readSource('client/actions.lua')
local compat = readSource('client/vmenu_compat.lua')
local server = readSource('server/vmenu_compat.lua')
local config = readSource('shared/config.lua')
local ui = readSource('ui/app.js')

assertContains(actions, "Admin.dispatchVmenuAction('execute'", 'base execute dispatcher must consult registered compatibility actions')
assertContains(actions, "Admin.dispatchVmenuAction('toggle'", 'base toggle dispatcher must consult registered compatibility actions')
assertContains(actions, "Admin.dispatchVmenuAction('select'", 'base select dispatcher must consult registered compatibility actions')
assertContains(compat, 'Admin.dispatchVmenuAction = function', 'compatibility action router must be registered explicitly')

assertContains(ui, "action.type === 'select'", 'keyboard activation must not execute select actions')
assertContains(ui, "action.type === 'workspace'", 'keyboard activation must route workspace actions')
assertContains(ui, 'setActiveTab(action.workspaceTab)', 'workspace activation must open its configured tab')
assertContains(config, "['player.setFaceFeature'] = 'cortex-admin.player'", 'face-feature UI actions must pass the action gate')
assertContains(config, "['vehicle.removePersonal'] = 'cortex-admin.vehicle'", 'saved personal vehicles must be deletable through the action gate')

local personalSetStart = assert(compat:find("executeHandlers['vehicle.personalSet']", 1, true))
local personalSetEnd = assert(compat:find("executeHandlers['vehicle.personalKickPassengers']", personalSetStart, true))
local personalSet = compat:sub(personalSetStart, personalSetEnd - 1)
assertContains(personalSet, 'currentVehicle(true)', 'only the current driver may claim a personal vehicle')
assertContains(personalSet, 'personalVehicleIdentity', 'personal vehicles must retain an identity record')
assert(not personalSet:find('SetEntityAsMissionEntity', 1, true), 'personal vehicle linking must not seize mission ownership')

assertContains(compat, 'GetEntityType(vehicle) == 2', 'personal vehicle identity must enforce entity type')
assertContains(compat, 'GetEntityModel(vehicle) == identity.model', 'personal vehicle identity must enforce model')
assertContains(compat, 'NetworkGetNetworkIdFromEntity(vehicle) == identity.networkId', 'personal vehicle identity must reject reused network IDs')
assertContains(compat, 'SetVehicleExclusiveDriver(vehicle, enabled == true)', 'exclusive driver must toggle the vehicle flag')
assertContains(compat, 'SetVehicleExclusiveDriver_2(vehicle, enabled == true and playerPed() or 0, 1)', 'exclusive driver must assign or clear the driver')
assertContains(compat, 'SetVehicleDoorsLockedForAllPlayers(vehicle, true)', 'personal locking must apply to all players')
assertContains(compat, "executeHandlers['vehicle.personalEngine']", 'personal engine must invert live engine state as an action')

assertContains(server, "RegisterNetEvent('cortex-admin:server:setPersonalVehicle'", 'server must authorize the personal vehicle session')
assertContains(server, "allowed(src, 'vehicle.personalSet')", 'personal vehicle session must enforce ACE authorization')
assertContains(server, 'GetPedInVehicleSeat(vehicle, -1) ~= ped', 'server must verify the linking player is the driver')
assertContains(server, "RegisterNetEvent('cortex-admin:server:kickPersonalVehiclePassengers'", 'passenger removal must cross an authoritative server boundary')
assertContains(server, "allowed(src, 'vehicle.personalKickPassengers')", 'passenger removal must enforce ACE authorization')
assertContains(server, 'GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(src)', 'personal vehicle mutations must enforce routing-bucket plausibility')

print('personal vehicle dispatch and authority contract tests passed')
