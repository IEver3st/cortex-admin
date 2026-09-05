local path = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local root = assert(path:match('^(.*)/tests/[^/]+$'))
dofile(root .. '/shared/wardrobe_catalog.lua')
Config = { WardrobeCapture = { settleMs = 250 } }
EsAdmin = { state = { open = false }, setOpen = function() end }
local events, callbacks, threads = {}, {}, {}
local now, ped, color, hidden, visible = 0, nil, nil, false, true
local frames, calibrations, saves, cleared, textures = {}, 0, 0, {}, {}
local prefix = 'cortex-admin:catalog:'
function RegisterNetEvent(name, fn) events[name] = fn end
function RegisterCommand() end
function RegisterNUICallback(name, fn) callbacks[name] = fn end
function AddEventHandler() end
function SetTimeout() end
function CreateThread(fn) threads[#threads + 1] = coroutine.create(fn) end
function Wait() coroutine.yield() end
function GetGameTimer() return now end
function PlayerPedId() return 1 end
function IsEntityDead() return false end
function IsPedInAnyVehicle() return false end
function GetRenderingCam() return 0 end
function GetResourceState() return 'started' end
function GetEntityCoords() return { x = 0, y = 0, z = 0 } end
function IsEntityPositionFrozen() return false end
function FreezeEntityPosition() end
function CreateCam() return 10 end
function SetCamCoord() end
function PointCamAtCoord() end
function SetCamFov() end
function SetFocusPosAndVel() end
function SetCamActive() end
function RenderScriptCams() end
function DestroyCam() end
function ClearFocus() end
function DoesEntityExist() return true end
function DeleteEntity() end
function joaat(name) return name end
function RequestModel() end
function HasModelLoaded() return true end
function SetModelAsNoLongerNeeded() end
function CreatePed() ped = 20; return ped end
function SetEntityCollision() end
function SetEntityInvincible() end
function SetBlockingOfNonTemporaryEvents() end
function SetPedCanPlayAmbientAnims() end
function SetPedCanPlayAmbientBaseAnims() end
function SetEntityLodDist() end
function SetEntityHeading() end
function SetEntityVisible(target, value) assert(target == 20); visible = value end
function GetNumberOfPedDrawableVariations(_, slot) return slot == 11 and 1 or 0 end
function GetNumberOfPedPropDrawableVariations() return 0 end
function GetPedCollectionNameFromDrawable() return '' end
function GetPedCollectionLocalIndexFromDrawable(_, _, drawable) return drawable end
function ClearAllPedProps() end
function SetPedComponentVariation(target, slot, drawable)
    assert(target == 20 and slot ~= 0 and drawable == -1, 'only local non-head slots may be emptied')
    cleared[slot] = true
end
function SetPedCollectionPreloadVariationData() end
function HasPedPreloadVariationDataFinished() return true end
function ReleasePedPreloadVariationData() end
function SetPedCollectionComponentVariation(_, slot, _, drawable, texture)
    assert(slot == 11 and drawable == 0 and texture == 0)
    for i = 1, 11 do assert(cleared[i], 'all other garment/body slots must be cleared before the target') end
    textures[#textures + 1] = texture
end
function GetPedBoneCoords(_, bone) return { z = bone == 31086 and 1000.85 or 999.1 } end
function GetActiveScreenResolution() return 1920, 1080 end
function DisableAllControlActions() end
function IsDisabledControlJustPressed() return false end
function HideHudAndRadarThisFrame() end
function SetPedResetFlag(target, flag, enabled) assert(target == 20 and flag == 166 and enabled); hidden = true end
function DrawPoly(_, _, _, _, _, _, _, _, _, r, g, b) color = { r, g, b } end
function DrawLightWithRange() end
exports = { ['screenshot-basic'] = { requestScreenshot = function(_, options, cb)
    assert(options.encoding == 'png' and hidden, 'capture must be lossless and head-hidden')
    assert(visible == (#frames % 4 >= 2), 'the stage is measured with the local ped hidden, before either garment frame')
    frames[#frames + 1] = table.concat(color, ',')
    cb('data:image/png;base64,frame' .. #frames)
end } }
function TriggerServerEvent(name, id, step)
    if name == prefix .. 'prepare' then events[prefix .. 'prepared'](id, step, false)
    elseif name == prefix .. 'done' then events[prefix .. 'stop'](id, 'finished')
    elseif name == prefix .. 'abort' then error('unexpected capture abort') end
end
function TriggerLatentServerEvent(name, _, id, step, image)
    assert(name == prefix .. 'save' and WardrobeCatalog.validImage(image))
    saves = saves + 1
    events[prefix .. 'saved'](id, step)
end
function SendNUIMessage(data)
    if data.action ~= prefix .. 'process' then return end
    assert(data.v == 3 and #data.images == 4 and data.images[1] ~= data.images[2])
    assert(frames[#frames - 1] == '24,128,24' and frames[#frames] == '224,48,224', 'backing must change between captures')
    local reply = { id = data.id, step = data.step, capture = data.capture }
    if data.calibration then calibrations = calibrations + 1; reply.empty = true
    else reply.image = 'data:image/webp;base64,UklGR' .. string.rep('A', 200) end
    local completed = 0
    callbacks[prefix .. 'processed'](reply, function(result) completed = completed + 1; assert(result.ok) end)
    assert(completed == 1)
end
dofile(root .. '/client/wardrobe_catalog.lua')
events[prefix .. 'start']('integration', 'sample')
for _ = 1, 500 do
    now = now + 16
    local alive = false
    for _, thread in ipairs(threads) do
        if coroutine.status(thread) ~= 'dead' then
            alive = true
            local ok, err = coroutine.resume(thread); assert(ok, err)
        end
    end
    if not alive then break end
end
assert(not EsAdmin.isWardrobeCaptureActive(), 'capture must complete and release its scene')
assert(calibrations == 2 and saves == 2 and #frames == 16 and #textures == 2,
    'each body must validate isolation, then measure its stage and capture both garment backings')
print('wardrobe cutout client isolation and measured-backdrop capture integration tests passed')
