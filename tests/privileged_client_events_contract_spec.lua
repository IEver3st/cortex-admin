local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

local function read(relativePath)
    local file = assert(io.open(resourceRoot .. '/' .. relativePath, 'rb'))
    local content = file:read('*a')
    file:close()
    return content
end

local guard = 'if not EsAdminClientSecurity.isServerOrigin(source) then return end'

local function assertGuarded(relativePath, eventName)
    local source = read(relativePath)
    local declaration = ("RegisterNetEvent('%s', function"):format(eventName)
    local startAt = assert(source:find(declaration, 1, true), ('missing event %s in %s'):format(eventName, relativePath))
    local nextEventAt = source:find('RegisterNetEvent(', startAt + #declaration, true) or (#source + 1)
    local handler = source:sub(startAt, nextEventAt - 1)
    assert(handler:find(guard, 1, true), ('%s must reject non-server event sources'):format(eventName))
end

local manifest = read('fxmanifest.lua')
local securityAt = assert(manifest:find("'client/security.lua'", 1, true), 'client security module must be in fxmanifest')
local mainAt = assert(manifest:find("'client/main.lua'", 1, true), 'client main script must be in fxmanifest')
assert(securityAt < mainAt, 'client security module must load before privileged handlers')

local privilegedEvents = {
    { 'client/main.lua', 'cortex-admin:client:updateWorldState' },
    { 'client/main.lua', 'cortex-admin:client:teleport' },
    { 'client/main.lua', 'cortex-admin:client:freeze' },
    { 'client/nui.lua', 'cortex-admin:client:killPed' },
    { 'client/nui.lua', 'cortex-admin:client:revivePed' },
    { 'client/nui.lua', 'cortex-admin:client:sitInVehicle' },
    { 'client/actions.lua', 'cortex-admin:client:spawnGarageVehicle' },
    { 'client/vmenu_compat.lua', 'cortex-admin:client:setPlayerWaypoint' },
    { 'client/vmenu_compat.lua', 'cortex-admin:client:setSpectateTarget' },
    { 'client/vmenu_compat.lua', 'cortex-admin:client:applyVmenuWorldState' },
    { 'client/vmenu_compat.lua', 'cortex-admin:client:authorizedEntitySpawn' },
}

for _, entry in ipairs(privilegedEvents) do
    assertGuarded(entry[1], entry[2])
end

local readme = read('README.md')
assert(readme:find('trusted-client boundary', 1, true), 'README must document the trusted-client limitation')
assert(readme:find('65535', 1, true), 'README must document the server-origin event check')

print('privileged client event contract tests passed')
