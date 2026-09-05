local path = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local root = assert(path:match('^(.*)/tests/[^/]+$'))
dofile(root .. '/shared/config.lua')
dofile(root .. '/shared/wardrobe_share.lua')
Config.HasQBX = false
EsAdminActions = { actions = {} }
EsAdminServer = {}
EsAdminBridge = {}
local commands, events, replies = {}, {}, {}
local clock, permitted = 0, true
function RegisterCommand(name, handler) commands[name] = handler end
function RegisterNetEvent(name, handler) events[name] = handler end
function AddEventHandler() end
function GetGameTimer() return clock end
function GetCurrentResourceName() return 'cortex-admin' end
function GetResourcePath() return root end
function IsPlayerAceAllowed(_, permission)
    return permitted and permission == Config.ActionPermissions['world.time']
end
function TriggerClientEvent(name, target, ...)
    replies[#replies + 1] = { name = name, target = target, args = { ... } }
end
dofile(root .. '/server/main.lua')

local function invoke(args, src)
    replies = {}
    clock = clock + 5001
    commands.time(src or 1, args)
end
local function assertTime(hour, minute)
    assert(EsAdminServer.worldState.hour == hour and EsAdminServer.worldState.minute == minute)
    assert(replies[1].name == 'cortex-admin:client:updateWorldState' and replies[1].target == -1,
        'Time must broadcast to every client')
    assert(replies[1].args[1].hour == hour and replies[1].args[1].minute == minute)
end
for _, args in ipairs({
    { 'set', 'day' }, { 'day' }, { 'SET', 'DAY' },
    { 'set', '12' }, { '12' }, { '12', '00' }, { 'set', '12', '00' },
}) do
    invoke(args)
    assertTime(12, 0)
    assert(replies[2].args[1] == 'success')
end
invoke({ 'set', '23', '59' })
assertTime(23, 59)
invoke({ '0', '00' })
assertTime(0, 0)

for _, args in ipairs({
    {}, { 'set' }, { '24' }, { '-1' }, { '12', '60' }, { '12', '-1' },
    { '12.5' }, { '12', '0.5' }, { 'noon' }, { 'day', '1' },
    { 'set', 'day', '00' }, { '12', '00', 'extra' }, { 'set', '12', '00', 'extra' },
    { 'nan' }, { 'inf' }, { '1e1' },
}) do
    invoke(args)
    assert(#replies == 1 and replies[1].name == 'cortex-admin:client:notify')
    assert(replies[1].args[1] == 'error' and replies[1].args[2]:find('Usage:', 1, true))
    assert(EsAdminServer.worldState.hour == 0 and EsAdminServer.worldState.minute == 0,
        'Invalid input must not mutate time')
end

permitted = false
invoke({ 'set', '15', '30' })
assert(#replies == 1 and replies[1].args[2]:find('permission', 1, true))
assert(EsAdminServer.worldState.hour == 0)
local realPrint, consoleMessage = print, nil
print = function(message) consoleMessage = message end
invoke({ 'set', '15', '30' }, 0)
print = realPrint
assertTime(15, 30)
assert(consoleMessage:find('15:30', 1, true))

permitted = true
clock = clock + 5001
for index = 1, 15 do commands.time(1, { '12' }) end
replies = {}
commands.time(1, { '18' })
assert(#replies == 0 and EsAdminServer.worldState.hour == 12, 'Command must enforce write rate limit')

source = 1
clock = clock + 5001
replies = {}
events['cortex-admin:server:setWorldState']({ hour = 8, minute = 45 })
assertTime(8, 45)
replies = {}
events['cortex-admin:server:setWorldState']({ hour = 25, minute = 0 })
assert(#replies == 0 and EsAdminServer.worldState.hour == 8)
permitted = false
events['cortex-admin:server:setWorldState']({ hour = 10, minute = 0 })
assert(#replies == 0 and EsAdminServer.worldState.hour == 8)
source = nil
print('time command tests passed')
