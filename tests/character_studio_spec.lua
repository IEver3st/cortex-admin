local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local root = assert(sourcePath:match('^(.*)/tests/[^/]+$'))
dofile(root .. '/shared/appearance_catalog.lua')
dofile(root .. '/shared/appearance_index.lua')
dofile(root .. '/shared/appearance_randomizer.lua')

local total = 0
for _, gender in ipairs({ 'male', 'female' }) do
    local ids = {}
    for _, style in ipairs({ 'polished', 'casual', 'street', 'sport', 'utility', 'biker', 'resort', 'nightlife', 'designer' }) do
        for _, palette in ipairs({ 'neutral', 'tonal', 'varied' }) do
            local families = AppearanceRandomizer.getOutfitFamilies(gender, style, palette)
            assert(#families >= 2, 'Every style needs varied silhouettes')
            for _, family in ipairs(families) do
                local pools = family.pools
                for _, top in ipairs(pools.tops) do
                    for _, component in ipairs(top.components) do
                        if component.component == 8 then
                            assert((component.globalDrawable or component.drawable) == (gender == 'female' and 14 or 15))
                            assert(component.texture == 0, 'Bare undershirts must not inherit a top texture')
                        end
                        if component.globalDrawable then
                            assert(AppearanceIndex[gender][component.component][component.globalDrawable], 'Missing stable catalog identity')
                        end
                    end
                end
                for t = 1, #pools.tops do
                    for b = 1, #pools.bottoms do
                        for f = 1, #pools.shoes do
                            local picks = { tops = t, bottoms = b, shoes = f }
                            local outfit = assert(AppearanceRandomizer.assembleOutfit(pools, false, function(_, category) return picks[category] end))
                            assert(#outfit.components == 5 and #outfit.accessories == 0)
                            ids[outfit.id] = true
                        end
                    end
                end
                local unavailable = AppearanceRandomizer.filterPiecePools(pools, function(_, category) return category ~= 'shoes' end)
                assert(AppearanceRandomizer.assembleOutfit(unavailable, false) == nil, 'Unavailable families must not produce partial outfits')
            end
        end
    end
    local count = 0
    for _ in pairs(ids) do count = count + 1 end
    assert(count >= 1000, 'Each gender needs at least 1000 distinct authored combinations')
    total = total + count
    print(gender .. ' family combinations: ' .. count)
end

-- Execute the actual camera module against deterministic native stubs.
local ped, rendering, vehicle, dead = 1, -1, false, false
local frozen, cameras, threads, stopHandler = {}, {}, {}, nil
local lod, focus, refreshes, clearCount = { [1] = 80, [2] = 900 }, 1, 0, 0
local cameraCoords, targetCoords, activeCamera = {}, {}, nil
local brokenBone = false
local idleSway, idleHeading = 0, 0
local cameraWrites, rootShift = 0, 0
local commands, clock, focusPosition, lastDiagnostic = {}, 0, nil, nil
local renderedOverride = nil
local scriptRendering, deferRenderingHandle = false, false
json = { encode = function(value) lastDiagnostic = value; return value.phase end }
function RegisterCommand(name, handler) commands[name] = handler end
function GetGameTimer() return clock end
function GetFinalRenderedCamCoord() return renderedOverride or cameraCoords[rendering] or GetEntityCoords() end
function GetFinalRenderedCamRot() return { x = 0, y = 0, z = 180 } end
function GetFinalRenderedCamFov() return 36 end
function GetCamCoord(cam) return cameraCoords[cam] end
function GetNumberOfStreamingRequests() return 0 end
EsAdmin = { state = { open = true, allowed = { ['player.setAppearance'] = true } } }
function PlayerPedId() return ped end
function DoesEntityExist(entity) return entity > 0 end
function IsEntityDead() return dead end
function IsPedInAnyVehicle() return vehicle end
function IsEntityPositionFrozen(entity) return frozen[entity] == true end
function FreezeEntityPosition(entity, value) frozen[entity] = value end
function GetRenderingCam() return rendering end
function CreateCam(_, active)
    assert(not active, 'Camera must be positioned before activation')
    local cam = #cameras + 1; cameras[cam] = true; return cam
end
function SetCamActive(cam, active)
    if active then
        assert(cameraCoords[cam] and targetCoords[cam], 'Never activate an unpositioned camera')
        activeCamera = cam
    elseif activeCamera == cam then activeCamera = nil end
end
function DoesCamExist(cam) return cameras[cam] == true end
function DestroyCam(cam) cameras[cam] = false end
function RenderScriptCams(active)
    scriptRendering = active
    rendering = active and not deferRenderingHandle and activeCamera or -1
end
function IsCamActive(cam) return cameras[cam] == true and activeCamera == cam end
function GetEntityHeading() return idleHeading end
function GetEntityCoords() return { x = 10 + rootShift + idleSway * 0.1, y = 20, z = 101 } end
function GetEntityLodDist(entity) return lod[entity] end
function SetEntityLodDist(entity, value) lod[entity] = value end
function SetFocusEntity(entity) focus = entity end
function SetFocusPosAndVel(x, y, z) focus = nil; focusPosition = { x = x, y = y, z = z } end
function IsEntityFocus(entity) return focus == entity end
function ClearFocus() focus = nil; focusPosition = nil; clearCount = clearCount + 1 end
function ForcePedAiAndAnimationUpdate() refreshes = refreshes + 1 end
function GetPedBoneCoords(_, bone)
    if brokenBone and bone == 0x796E then return { x = 5000, y = 5000, z = 5000 } end
    return { x = 10 + idleSway, y = 20, z = (bone == 0x796E and 101.7 or 100) + idleSway }
end
function SetCamCoord(cam, x, y, z) cameraWrites = cameraWrites + 1; cameraCoords[cam] = { x = x, y = y, z = z } end
function PointCamAtCoord(cam, x, y, z) targetCoords[cam] = { x = x, y = y, z = z } end
function SetCamFov() end
function SendNUIMessage() end
function CreateThread(fn) threads[#threads + 1] = coroutine.create(fn) end
function Wait() coroutine.yield() end
function GetCurrentResourceName() return 'cortex-admin' end
function AddEventHandler(_, fn) stopHandler = fn end
dofile(root .. '/client/character_studio.lua')
assert(EsAdmin.openCharacterStudio().ok and frozen[1])
assert(lod[1] == 512 and focus == 1 and refreshes == 1)
assert(math.abs(cameraCoords[rendering].z - 100.90) < 0.001, 'Body must frame skeletal bounds, not entity origin')
local firstThread = threads[#threads]
assert(coroutine.resume(firstThread))
assert(refreshes == 1, 'Camera tick must not repeat expensive animation refresh')
local steadyCamera, steadyTarget = cameraCoords[rendering], targetCoords[rendering]
local writesBeforeIdle = cameraWrites
for tick = 1, 12 do
    idleSway, idleHeading = math.sin(tick) * 0.08, math.cos(tick) * 3
    assert(coroutine.resume(firstThread))
    local cam, target = cameraCoords[rendering], targetCoords[rendering]
    assert(cam.x == steadyCamera.x and cam.y == steadyCamera.y and cam.z == steadyCamera.z
        and target.x == steadyTarget.x and target.y == steadyTarget.y and target.z == steadyTarget.z,
        'Idle bone, root and heading movement must not shake the studio camera')
end
idleSway, idleHeading = 0, 0
assert(cameraWrites == writesBeforeIdle, 'Idle checks must not repeatedly write camera transforms')
assert(EsAdmin.moveCharacterStudioCamera({ rotate = 1 }).ok)
assert(cameraCoords[rendering].x ~= steadyCamera.x, 'Manual orbit must still respond')
assert(EsAdmin.moveCharacterStudioCamera({ reset = true, zoom = -1 }).ok)
assert(cameraCoords[rendering].y == steadyCamera.y, 'Reset restores the stable original view')
assert(EsAdmin.moveCharacterStudioCamera({ zoom = -1 }).ok)
assert(cameraCoords[rendering].y < steadyCamera.y, 'Manual zoom must still respond')
assert(EsAdmin.moveCharacterStudioCamera({ reset = true }).ok)
rootShift = 10
assert(coroutine.resume(firstThread))
assert(cameraCoords[rendering].x == steadyCamera.x + 10, 'A real external relocation must carry the camera with the ped')
rootShift = 0
assert(coroutine.resume(firstThread))
brokenBone = true
assert(EsAdmin.moveCharacterStudioCamera({ frame = 'body' }).ok)
local displacedCamera = cameraCoords[rendering]
assert(math.abs(displacedCamera.x - 10) < 6 and math.abs(displacedCamera.y - 20) < 6
    and math.abs(displacedCamera.z - 101) < 6, 'Invalid streamed bone positions must never send the camera far from the player')
brokenBone = false
assert(EsAdmin.moveCharacterStudioCamera({ frame = 'bad', zoom = 100, rotate = {} }).ok)
commands.cortex_studio_debug(0, {})
assert(lastDiagnostic.playerMoved == 0 and lastDiagnostic.cameraMismatch == 0)
renderedOverride = { x = 5000, y = 5000, z = 5000 }
commands.cortex_studio_debug(0, {})
assert(lastDiagnostic.renderedDistance > 5000 and lastDiagnostic.cameraMismatch > 5000
    and lastDiagnostic.cameraWriteError == 0 and lastDiagnostic.playerMoved == 0,
    'Diagnostics must distinguish a displaced rendered camera from a player teleport or bad camera write')
renderedOverride = nil
local cameraBeforeProbe = cameraCoords[rendering]
commands.cortex_studio_debug(0, { 'camera' })
assert(focusPosition.x == cameraBeforeProbe.x and focusPosition.y == cameraBeforeProbe.y
    and focusPosition.z == cameraBeforeProbe.z, 'Camera-focus probe must target the existing nearby camera')
assert(cameraCoords[rendering].z == cameraBeforeProbe.z, 'Focus probe must not change camera framing')
EsAdmin.closeCharacterStudio()
assert(not frozen[1] and rendering == -1 and lod[1] == 80 and focus == nil and focusPosition == nil)
brokenBone = true
assert(EsAdmin.openCharacterStudio().ok)
commands.cortex_studio_debug(0, {})
assert(lastDiagnostic.boneFallback and lastDiagnostic.cameraDistance < 6,
    'Invalid bones at initial acquisition must still use bounded framing')
EsAdmin.closeCharacterStudio()
brokenBone = false
frozen[1] = true
assert(EsAdmin.openCharacterStudio().ok)
assert(coroutine.resume(firstThread) and coroutine.status(firstThread) == 'dead', 'Old loop must not take over a reopened studio')
assert(rendering ~= -1)
EsAdmin.closeCharacterStudio()
assert(frozen[1], 'Pre-existing freeze must survive studio exit')
frozen[1] = false
assert(EsAdmin.openCharacterStudio().ok)
ped = 2
assert(EsAdmin.moveCharacterStudioCamera({ frame = 'face' }).ok)
assert(not frozen[1] and frozen[2], 'Model replacement must release the old ped')
assert(lod[1] == 80 and lod[2] == 900 and focus == 2, 'Transfer focus and preserve higher prior detail distance')
assert(math.abs(targetCoords[rendering].z - 101.7428) < 0.001)
assert(EsAdmin.moveCharacterStudioCamera({ frame = 'legs' }).ok)
assert(math.abs(targetCoords[rendering].z - 100.4492) < 0.001)
stopHandler('cortex-admin')
assert(not frozen[2] and rendering == -1 and focus == nil and lod[2] == 900)
rendering = 99
assert(EsAdmin.openCharacterStudio().error == 'camera_busy')
rendering = -1
vehicle = true
assert(not EsAdmin.openCharacterStudio().ok and not frozen[2])
vehicle = false
assert(EsAdmin.openCharacterStudio().ok)
rendering = 99
focus = 99
lod[2] = 1000
local clearsBefore = clearCount
EsAdmin.closeCharacterStudio()
assert(rendering == 99, 'Cleanup must not disable another camera owner')
assert(focus == 99 and clearCount == clearsBefore, 'Cleanup must preserve another streaming focus owner')
assert(lod[2] == 1000, 'Cleanup must preserve a newer detail setting from another resource')
-- Reproduce the user's trace: script rendering has started, but the rendering
-- handle is still -1. Closing here must not leave GTA rendering without a cam.
rendering, deferRenderingHandle = -1, true
assert(EsAdmin.openCharacterStudio().ok)
EsAdmin.closeCharacterStudio()
assert(not scriptRendering, 'Closing before the rendering handle appears must disable script rendering before destroying its camera')
assert(EsAdmin.openCharacterStudio().ok)
local pendingThread = threads[#threads]
assert(coroutine.resume(pendingThread))
assert(coroutine.resume(pendingThread))
assert(EsAdmin.moveCharacterStudioCamera({ frame = 'body' }).ok,
    'A pending rendering handle is not a camera takeover and must not tear down the studio')
rendering, deferRenderingHandle = activeCamera, false
assert(coroutine.resume(pendingThread))
assert(EsAdmin.moveCharacterStudioCamera({ frame = 'face' }).ok)
EsAdmin.closeCharacterStudio()
assert(not scriptRendering)
-- Losing the camera object also requires releasing our script-render request.
assert(EsAdmin.openCharacterStudio().ok)
local lostThread = threads[#threads]
assert(coroutine.resume(lostThread))
cameras[activeCamera], rendering = false, -1
assert(coroutine.resume(lostThread))
assert(not scriptRendering and not frozen[ped])
-- A concrete foreign camera still wins, including during the first render tick.
assert(EsAdmin.openCharacterStudio().ok)
local takeoverThread = threads[#threads]
assert(coroutine.resume(takeoverThread))
rendering, focus = 99, 99
assert(coroutine.resume(takeoverThread))
assert(rendering == 99 and focus == 99 and scriptRendering)
print('character studio camera lifecycle and family tests passed (' .. total .. ' combinations)')

local callbacks, writes = {}, 0
Config = { ActionPermissions = { ['player.setAppearance'] = true, ['player.randomizeAppearance'] = true } }
EsAdmin.state.allowed['player.randomizeAppearance'] = true
function RegisterNUICallback(name, handler) callbacks[name] = handler end
function RegisterNetEvent() end
EsAdmin.setPedAppearance = function() writes = writes + 1 end
EsAdmin.getPedAppearance = function() return { maxComponents = { ['11'] = { textures = 7 } } } end
dofile(root .. '/client/nui.lua')
local function invoke(name, payload)
    local replies, result = 0, nil
    callbacks['cortex-admin:' .. name](payload, function(value) replies = replies + 1; result = value end)
    assert(replies == 1, name .. ' must reply exactly once')
    return result
end
local badPayloads = {
    {}, { type = 'component', id = 11, drawable = 0 / 0, texture = 0 },
    { type = 'component', id = 99, drawable = 0, texture = 0 },
    { type = 'component', id = 11, drawable = {}, texture = 0 },
    { type = 'blend', field = 'oops', value = 2 },
    { type = 'blend', field = 'shapeMix', value = math.huge },
    { type = 'overlay', id = 2, field = 'opacity', value = -1 },
    { type = 'color', colorType = 'eyes', value = 63 },
    { type = 'color', colorType = 'oops', id = 2, value = 0 },
}
for _, payload in ipairs(badPayloads) do assert(not invoke('setAppearance', payload).ok) end
assert(writes == 0, 'Malformed requests must never reach natives')
local result = invoke('setAppearance', { type = 'component', id = 11, drawable = 78, texture = 0 })
assert(result.ok and result.appearance.maxComponents['11'].textures == 7)
assert(writes == 1)
EsAdmin.state.allowed['player.setAppearance'] = false
assert(not invoke('setAppearance', { type = 'component', id = 11, drawable = 0, texture = 0 }).ok)
assert(not invoke('studio', { action = 'open' }).ok)
assert(writes == 1)
EsAdmin.state.allowed['player.setAppearance'] = true
EsAdmin.setPedAppearance = function() error('test exception') end
assert(not invoke('setAppearance', { type = 'component', id = 11, drawable = 0, texture = 0 }).ok)
assert(not invoke('studio', { action = 'unknown' }).ok)
print('studio NUI permissions, malformed input and callback completion tests passed')

local sourceFile = assert(io.open(root .. '/client/actions.lua', 'rb'))
local source = sourceFile:read('*a'); sourceFile:close()
local first = assert(source:find('local function generatedComponentIsValid', 1, true))
local last = assert(source:find('local function generatedAccessoryIsValid', first, true))
local validator = assert(load(source:sub(first, last - 1) .. '\nreturn generatedComponentIsValid'))()
local identity = AppearanceIndex.male[11][86]
local collection, localIndex, count, textures = identity.collection, identity.drawable, 500, 10
function joaat(value) return value == 'mp_f_freemode_01' and 2 or 1 end
function GetEntityModel() return 1 end
function GetNumberOfPedDrawableVariations() return count end
function GetNumberOfPedTextureVariations() return textures end
function GetPedCollectionNameFromDrawable() return collection end
function GetPedCollectionLocalIndexFromDrawable() return localIndex end
local item = { component = 11, globalDrawable = 86, texture = 0 }
assert(validator(1, item))
collection = 'custom_clothing_at_the_same_global_index'
assert(not validator(1, item), 'An old build addon index must not impersonate an unavailable official item')
collection = identity.collection
localIndex = identity.drawable + 1
assert(not validator(1, item), 'Collection local index must match the researched item')
localIndex = identity.drawable
count = 86
assert(not validator(1, item), 'Unavailable drawables must be excluded')
count = 500
item.texture = textures
assert(not validator(1, item), 'Unavailable textures must be excluded')
print('catalog collection identity, build availability and texture bounds tests passed')
