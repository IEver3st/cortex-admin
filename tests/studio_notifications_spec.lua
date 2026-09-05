local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local root = assert(sourcePath:match('^(.*)/tests/[^/]+$'))
local active, emitted = false, 0
local callbacks, threads = {}, {}
EsAdmin = {
    state = { open = true, allowed = { ['player.saveMpPed'] = true, ['player.setAppearance'] = true } },
    isCharacterStudioActive = function() return active end,
}
Config = { ActionPermissions = { ['player.saveMpPed'] = true, ['player.setAppearance'] = true } }
exports = { ['cortex-lib'] = { notify = function() emitted = emitted + 1 end } }
local file = assert(io.open(root .. '/client/main.lua', 'rb'))
local source = file:read('*a'); file:close()
local first = assert(source:find('local function notify(', 1, true))
local last = assert(source:find('EsAdmin.notify = notify', first, true))
EsAdmin.notify = assert(load(source:sub(first, last - 1) .. '\nreturn notify'))()
function RegisterNUICallback(name, handler) callbacks[name] = handler end
function RegisterNetEvent() end
function CreateThread(handler) threads[#threads + 1] = coroutine.create(handler) end
dofile(root .. '/client/nui.lua')

for _, kind in ipairs({ 'success', 'info', 'warning', 'error' }) do
    active = true
    EsAdmin.notify(kind, 'studio')
end
assert(emitted == 0, 'An open studio must not emit any notification type')
active = false
EsAdmin.notify('success', 'admin')
assert(emitted == 1, 'Notifications outside the studio must still work')

EsAdmin.executeAction = function()
    coroutine.yield()
    EsAdmin.notify('success', 'saved after studio closed')
    EsAdmin.notify('error', 'error after studio closed')
    return true
end
local replies = 0
active = true
callbacks['cortex-admin:action']({ id = 'player.saveMpPed' }, function(result)
    assert(result.ok); replies = replies + 1
end)
local pending = threads[#threads]
active = false
assert(coroutine.resume(pending))
EsAdmin.notify('info', 'unrelated work while studio request is pending')
assert(emitted == 2, 'Pending studio work must not mute unrelated coroutines')
assert(coroutine.resume(pending))
assert(replies == 1 and emitted == 2, 'Delayed studio completion must stay silent and reply once')
assert(EsAdmin.silentNotificationThreads[pending] == nil, 'Completed requests must release suppression')

EsAdmin.setPedAppearance = function()
    active = false
    EsAdmin.notify('error', 'studio callback failed after closing')
    error('expected test failure')
end
active = true
callbacks['cortex-admin:setAppearance']({ type = 'component', id = 11, drawable = 0, texture = 0 }, function(result)
    assert(not result.ok and result.error == 'internal_error'); replies = replies + 1
end)
assert(replies == 2 and emitted == 2, 'Synchronous failure must stay silent and reply once')
assert(EsAdmin.silentNotificationThreads[coroutine.running()] == nil, 'Exceptions must restore suppression')
EsAdmin.notify('info', 'normal admin notification')
assert(emitted == 3)
print('studio notification suppression, delayed completion and exception cleanup tests passed')
