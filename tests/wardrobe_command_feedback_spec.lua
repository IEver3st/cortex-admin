local path = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local root = assert(path:match('^(.*)/tests/[^/]+$'))
local commands, events, output, replies = {}, {}, {}, {}
local realPrint = print
function print(value) output[#output + 1] = tostring(value) end
function RegisterCommand(name, fn) commands[name] = fn end
function RegisterNetEvent(name, fn) events[name] = fn end
function AddEventHandler() end
function TriggerClientEvent(name, target, ...) replies[#replies + 1] = { name = name, target = target, args = {...} } end
function GetResourceKvpString() return nil end
function GetResourceState() return 'started' end
function CreateThread() end
EsAdminServer = { hasPermission = function() return true end, allowRequest = function() return true end }
dofile(root .. '/shared/wardrobe_catalog.lua')
dofile(root .. '/server/wardrobe_catalog.lua')
local count = #output
commands.cortex_catalog(1, { 'status' })
assert(#output > count, 'Player catalog status is silent in the server console')
count = #replies
commands.cortex_catalog(1, { 'cancel' })
assert(#replies > count, 'Cancelling an idle catalog must report that no job is running')
count = #output
commands.cortex_catalog(1, { 'sample' })
assert(#output > count, 'Accepted capture command must report startup before the client responds')
-- The client bridge must retain the real network source and validate its envelope.
count = #replies
source = 1
events['cortex-admin:catalog:command'](7, 'status')
assert(replies[count + 1].name == 'cortex-admin:catalog:commandAck' and replies[count + 1].args[1] == 7)
assert(replies[#replies].target == 1 and replies[#replies].name == 'cortex-admin:catalog:message')
count = #replies
events['cortex-admin:catalog:command']({}, 'status')
events['cortex-admin:catalog:command'](8, {})
assert(#replies == count, 'Malformed command envelopes are rejected')
EsAdminServer.hasPermission = function() return false end
events['cortex-admin:catalog:command'](9, 'build')
assert(replies[#replies].args[1]:find('requires dev.takePhoto', 1, true), 'Client command cannot bypass server authorization')
EsAdminServer = nil
commands.cortex_catalog(1, { 'status' })
assert(replies[#replies].args[1]:find('permission service is unavailable', 1, true), 'Missing dependency must be explicit, not a silent handler exception')
print = realPrint
print('wardrobe command console feedback tests passed')
