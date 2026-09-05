local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local root = assert(sourcePath:match('^(.*)/tests/[^/]+$'))
dofile(root .. '/shared/wardrobe_catalog.lua')
local P = WardrobeCatalog
local item = { gender = 'female', kind = 'component', slot = 11, drawable = 4, collection = 'custom_pack' }
local key = assert(P.key(item))
assert(P.version == 2 and key:find('wardrobe:v2:', 1, true) == 1, 'mannequin images must not be reused as cutouts')
item.globalDrawable = 700
assert(P.key(item) == key, 'global reindex must not change persistent identity')
for _, value in ipairs({ -1, 0.5, math.huge, 65536 }) do
    item.drawable = value; assert(not P.key(item))
end
item.drawable = 0/0; assert(not P.key(item)); item.drawable = 4
item.collection = string.rep('a', 97); assert(not P.key(item))
item.collection = 'bad\nname'; assert(not P.key(item)); item.collection = 'custom_pack'
assert(not P.key(false) and not P.key({}))
assert(not P.validImage('data:image/svg+xml;base64,abc'))
assert(not P.validImage('data:image/webp;base64,' .. string.rep('A', 66000)))
local photo = 'data:image/webp;base64,UklGR' .. string.rep('A', 200)
assert(P.validImage(photo))
assert(P.validStored(P.emptyMarker) and not P.validImage(P.emptyMarker), 'empty slots can be checkpointed without posing as an image')

local events, commands, lifecycle, sent, kvp, threads = {}, {}, {}, {}, {}, {}
local permitted, limited, writes, seconds = true, false, 0, 1000
local oldTime = os.time
os.time = function() return seconds end
EsAdminServer = {
    hasPermission = function(src) return permitted and src == 1 end,
    allowRequest = function() return not limited end,
}
function RegisterNetEvent(name, fn) events[name] = fn end
function RegisterCommand(name, fn) commands[name] = fn end
function AddEventHandler(name, fn) lifecycle[name] = fn end
function TriggerClientEvent(name, target, ...) sent[#sent+1] = { name = name, target = target, args = {...} } end
function TriggerLatentClientEvent(name, target, _, ...) TriggerClientEvent(name, target, ...) end
function GetResourceKvpString(k) return kvp[k] end
function SetResourceKvp(k, value) kvp[k] = value; writes = writes + 1 end
function GetResourceState() return 'started' end
function CreateThread(fn) threads[#threads+1] = coroutine.create(fn) end
function Wait() coroutine.yield() end
json = { encode = function() return 'completed' end }
dofile(root .. '/server/wardrobe_catalog.lua')
local prefix = 'cortex-admin:catalog:'
local function invoke(name, src, ...) source = src; events[prefix .. name](...) end
local function start(mode)
    commands.cortex_catalog(1, {mode or 'build'})
    assert(sent[#sent].name == prefix .. 'start')
    return sent[#sent].args[1]
end
permitted = false
commands.cortex_catalog(1, {'build'})
assert(sent[#sent].name == prefix .. 'message' and writes == 0)
permitted = true
local id = start()
invoke('save', 1, id, 1, photo); assert(writes == 0, 'save without prepare rejected')
invoke('done', 1, id); assert(not kvp[P.statusKey], 'empty completion rejected')
invoke('prepare', 2, id, 1, item); assert(writes == 0, 'another source cannot claim job')
invoke('prepare', 1, id, 1, item); assert(sent[#sent].args[3] == false)
invoke('save', 1, id, 2, photo); assert(writes == 0, 'wrong sequence rejected')
invoke('save', 1, id, 1, photo); assert(kvp[key] == photo and writes == 1)
invoke('save', 1, id, 1, photo); assert(writes == 1, 'duplicate completion rejected')
invoke('done', 1, id); assert(kvp[P.statusKey])
local nextId = start()
invoke('save', 1, id, 1, photo); assert(writes == 2, 'old session cannot write')
invoke('prepare', 1, nextId, 1, item); assert(sent[#sent].args[3] == true, 'resumed builds skip persisted items')
commands.cortex_catalog(1, {'cancel'})
local rebuild = start('rebuild')
invoke('prepare', 1, rebuild, 1, item); assert(sent[#sent].args[3] == false)
permitted = false
invoke('save', 1, rebuild, 1, photo); assert(writes == 2, 'revoked permission cannot persist')
permitted = true
source = 1; lifecycle.playerDropped()
local resumed = start()
invoke('prepare', 1, resumed, 1, {}); assert(sent[#sent].name == prefix .. 'stop', 'malformed job terminates')
local timed = start()
local watchdog = threads[#threads]
assert(coroutine.resume(watchdog))
seconds = seconds + 100
assert(coroutine.resume(watchdog))
assert(sent[#sent].name == prefix .. 'stop', 'abandoned jobs expire')
-- Restart the module, keeping the server KVP store.
dofile(root .. '/server/wardrobe_catalog.lua')
local restarted = start()
invoke('prepare', 1, restarted, 1, item); assert(sent[#sent].args[3] == true)
commands.cortex_catalog(1, {'cancel'})
invoke('read', 1, 7, item); assert(sent[#sent].args[2].photo == photo)
invoke('read', 2, 8, item); assert(sent[#sent].args[2].error == 'forbidden')
limited = true
invoke('read', 1, 9, item); assert(sent[#sent].args[2].error == 'rate_limited')
limited = false
invoke('read', 1, 10, {}); assert(sent[#sent].args[2].error == 'invalid_item')
kvp[key] = P.emptyMarker
invoke('read', 1, 11, item); assert(sent[#sent].args[2].empty == true and sent[#sent].args[2].photo == nil)
local emptyResume = start()
invoke('prepare', 1, emptyResume, 1, item); assert(sent[#sent].args[3] == true, 'empty drawable markers are resumable')
commands.cortex_catalog(1, { 'cancel' })
os.time = oldTime

-- Client interruption cleanup, preserving the player's previous freeze state.
local nui, timeout, frozen, deleted, destroyed, focusCleared = {}, {}, {}, {}, {}, 0
local rendering = -1
Config = { WardrobeCapture = { settleMs = 750 } }
EsAdmin = { state = { open = false, allowed = { ['player.setAppearance'] = true } }, setOpen = function() end }
function RegisterNUICallback(name, fn) nui[name] = fn end
function SetTimeout(_, fn) timeout[#timeout+1] = fn end
function GetCurrentResourceName() return 'cortex-admin' end
function PlayerPedId() return 10 end
function IsEntityDead() return false end
function IsPedInAnyVehicle() return false end
function GetRenderingCam() return rendering end
function GetEntityCoords() return { x = 1, y = 2, z = 3 } end
local wasFrozen = false
function IsEntityPositionFrozen() return wasFrozen end
function FreezeEntityPosition(ped, value) frozen[ped] = value end
function CreateCam() return 22 end
function SetCamCoord() end
function PointCamAtCoord() end
function SetCamFov() end
function SetFocusPosAndVel() end
function SetCamActive() end
function RenderScriptCams() end
function ClearFocus() focusCleared = focusCleared + 1 end
function DestroyCam(cam) destroyed[cam] = true end
function DoesEntityExist() return true end
function DeleteEntity(ped) deleted[ped] = true end
function SetModelAsNoLongerNeeded() end
function TriggerServerEvent() end
function joaat(model) return model == 'mp_m_freemode_01' and 100 or 101 end
function GetEntityModel() return 100 end
function GetNumberOfPedDrawableVariations() return 20 end
function GetPedCollectionNameFromDrawable() return 'custom_pack' end
function GetPedCollectionLocalIndexFromDrawable() return 4 end
function RequestModel() end
function HasModelLoaded() return true end
function CreatePed() return 44 end
function SetEntityCollision() end
function SetEntityInvincible() end
function SetBlockingOfNonTemporaryEvents() end
function SetPedCanPlayAmbientAnims() end
function SetPedCanPlayAmbientBaseAnims() end
function SetEntityLodDist() end
function SetEntityHeading() end
function GetGameTimer() return 100 end
dofile(root .. '/client/wardrobe_catalog.lua')
events[prefix .. 'start']('a', 'build')
assert(frozen[10] == true and EsAdmin.isWardrobeCaptureActive())
assert(coroutine.resume(threads[#threads])) -- Create the mannequin, then wait for the server prepare response.
lifecycle.onResourceStop('cortex-admin')
assert(frozen[10] == false and destroyed[22] and deleted[44] and focusCleared == 1 and not EsAdmin.isWardrobeCaptureActive())
wasFrozen = true
events[prefix .. 'start']('b', 'sample')
rendering = 33 -- Another resource has taken over.
events[prefix .. 'stop']('b', 'cancelled')
assert(frozen[10] == true and focusCleared == 1, 'cleanup preserves prior freeze and other camera owner')
local replies, result = 0, nil
local function reply(value) replies = replies+1; result = value end
nui[prefix .. 'processed']({}, reply); assert(replies == 1 and not result.ok)
EsAdmin.state.open = true
nui[prefix .. 'photo']({ kind = 'component', slot = 11, drawable = 4 }, reply)
assert(replies == 1)
timeout[#timeout]()
assert(replies == 2 and result.error == 'timeout')
events[prefix .. 'photo'](1, { ok = true, photo = photo })
assert(replies == 2, 'late response must not complete callback twice')
nui[prefix .. 'photo']({ kind = 'component', slot = 11, drawable = -1 }, reply)
assert(replies == 3 and result.error == 'invalid_item')
local commandRequests = {}
function TriggerServerEvent(name, ...) commandRequests[#commandRequests + 1] = { name = name, args = {...} } end
local feedback, originalPrint = {}, print
print = function(text) feedback[#feedback + 1] = text end
commands.cortex_catalog(0, { 'status' })
assert(commandRequests[1].name == prefix .. 'command' and commandRequests[1].args[2] == 'status')
assert(feedback[1]:find('Requesting status', 1, true), 'F8 immediately confirms local command receipt')
local expired = timeout[#timeout]
events[prefix .. 'commandAck'](commandRequests[1].args[1])
expired()
assert(#feedback == 1, 'Acknowledged command must not report a timeout')
commands.cortex_catalog(0, { 'sample' })
timeout[#timeout]()
assert(feedback[#feedback]:find('No server acknowledgement', 1, true), 'Missing server handler reports reload instructions')
print = originalPrint
print('wardrobe catalog persistence, permissions, replay, timeout and client cleanup tests passed')
