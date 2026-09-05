local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local root = assert(sourcePath:match('^(.*)/tests/[^/]+$'))
local timer, ped, rendering, nextHandle = 0, 1, -1, 10
local entities = { [1] = { x = 100, y = 200, z = 10 }, [2] = { x = 102, y = 200, z = 10 } }
local frozen, cams, camCoords, threads, handlers = {}, {}, {}, {}, {}
local modelLoaded, inVehicle, failCam, deferCam = true, false, false, false
local activeCam, renderRequested, clockOverride, clockClears, appliedTo = nil, false, nil, 0, nil
local currentVehicle, lastVehicle, driver, controlled, networked = 2, 2, 1, true, false
EsAdmin = { state = { open = true, allowed = { ['vehicle.spawn'] = true, ['vehicle.customColors'] = true,
    ['vehicle.customExtras'] = true, ['vehicle.savePersonal'] = true } } }
function PlayerPedId() return ped end
function IsEntityDead() return false end
function IsPedInAnyVehicle() return inVehicle end
function GetEntityCoords(entity) return assert(entities[entity]) end
function GetEntityHeading() return 0 end
function GetOffsetFromEntityInWorldCoords(entity, x, y, z) local p=entities[entity]; return { x=p.x+x,y=p.y+y,z=p.z+z } end
function GetEntityModel() return 123 end
function GetVehiclePedIsIn(_, last) return last and lastVehicle or currentVehicle end
function GetPedInVehicleSeat() return driver end
function DoesEntityExist(entity) return entities[entity] ~= nil end
function IsEntityPositionFrozen(entity) return frozen[entity] == true end
function FreezeEntityPosition(entity, value) frozen[entity] = value end
function joaat(value) return value == 'invalid' and 0 or 123 end
function IsModelInCdimage(model) return model ~= 0 end
function IsModelAVehicle(model) return model ~= 0 end
function RequestModel() end
function HasModelLoaded() return modelLoaded end
function SetModelAsNoLongerNeeded() end
function GetGameTimer() return timer end
function Wait() coroutine.yield() end
function CreateThread(fn) threads[#threads+1] = coroutine.create(fn) end
function GetModelDimensions() return { x=-1,y=-2,z=-0.5 }, { x=1,y=2,z=1 } end
function GetGroundZFor_3dCoord() return true, 9 end
function CreateVehicle(_, x,y,z,_, networked, mission)
    assert(networked == false and mission == false, 'Preview must never be networked')
    nextHandle=nextHandle+1; entities[nextHandle]={x=x,y=y,z=z}; return nextHandle
end
function NetworkGetEntityIsNetworked(entity) return entity == 2 and networked end
function NetworkHasControlOfEntity() return controlled end
function NetworkRequestControlOfEntity() end
function SetEntityAsMissionEntity() end
function SetEntityCollision(_, collision) assert(collision == false) end
function SetEntityInvincible() end
function SetVehicleDoorsLocked(_, mode) assert(mode == 2) end
function SetVehicleEngineOn() end
function SetVehicleDirtLevel() end
function SetVehicleModKit() end
function captureVehicleData(entity, name) assert(entities[entity]); return { model=123,name=name,colors={primary=27} } end
function applyVehicleData(entity, props) assert(entity ~= 2 and props.colors.primary == 27); appliedTo=entity end
function getVehicleLabel() return 'Sultan' end
function DeleteEntity(entity) assert(entity ~= 1 and entity ~= 2, 'Must never delete player or source'); entities[entity]=nil end
function SetEntityHeading(entity, heading) assert(entity ~= ped and entity ~= 2); entities[entity].heading=heading end
function CreateCam(_, active)
    assert(not active); if failCam then return 0 end
    nextHandle=nextHandle+1; cams[nextHandle]=true; return nextHandle
end
function DoesCamExist(cam) return cams[cam] == true end
function SetCamCoord(cam,x,y,z) camCoords[cam]={x=x,y=y,z=z} end
function PointCamAtCoord() end
function SetCamFov() end
function SetCamActive(cam, active)
    if active then assert(camCoords[cam]); activeCam=cam elseif activeCam==cam then activeCam=nil end
end
function IsCamActive(cam) return activeCam==cam end
function DestroyCam(cam) cams[cam]=nil end
function GetRenderingCam() return rendering end
function RenderScriptCams(active) renderRequested=active; rendering=active and not deferCam and activeCam or -1 end
function NetworkOverrideClockTime(hour,minute,second)
    assert(hour>=0 and hour<=23 and minute>=0 and minute<=59 and second>=0 and second<=59)
    clockOverride={hour,minute,second}
end
function NetworkClearClockTimeOverride() clockOverride=nil; clockClears=clockClears+1 end
function SendNUIMessage() end
function AddEventHandler(name, fn) handlers[name]=fn end
function GetCurrentResourceName() return 'cortex-admin' end
function EsAdmin.restoreWorldClock() end
dofile(root .. '/client/vehicle_studio.lua')
-- The default entry must edit the existing entity, including while seated.
inVehicle=true
local liveOpened=EsAdmin.openVehicleStudio({source='current'})
assert(liveOpened.ok, 'Studio must open on the vehicle the player is in')
assert(EsAdmin.getVehicleStudioVehicle(liveOpened.session)==2, 'Studio must target the real vehicle, not spawn a copy')
EsAdmin.closeVehicleStudio()
assert(entities[2] and not frozen[2], 'Closing must preserve and release the real vehicle')
inVehicle=false
-- On foot, resolve the nearby last vehicle without cloning or resetting it.
currentVehicle, driver, networked = 0, 0, true
liveOpened=EsAdmin.openVehicleStudio({})
assert(liveOpened.ok and liveOpened.preview==false and frozen[2])
assert(EsAdmin.getVehicleStudioVehicle(liveOpened.session)==2)
assert(EsAdmin.controlVehicleStudio({session=liveOpened.session,action='camera',control='reset'}).ok)
assert(not EsAdmin.controlVehicleStudio({session=liveOpened.session,action='camera',control='rotate',value=1}).ok)
handlers.onResourceStop('cortex-admin')
assert(entities[2] and not frozen[2] and not frozen[1])
frozen[2]=true
liveOpened=EsAdmin.openVehicleStudio({source='current'}); assert(liveOpened.ok)
EsAdmin.closeVehicleStudio(); assert(frozen[2], 'Preserve inherited vehicle freeze')
frozen[2]=false
failCam=true
assert(not EsAdmin.openVehicleStudio({source='current'}).ok)
assert(entities[2] and not frozen[2], 'Failed setup must release, never delete, the real vehicle')
failCam=false
lastVehicle=0; assert(EsAdmin.openVehicleStudio({source='current'}).error=='no_source_vehicle'); lastVehicle=2
entities[2].x=200; assert(EsAdmin.openVehicleStudio({source='current'}).error=='source_too_far'); entities[2].x=102
driver=3; assert(EsAdmin.openVehicleStudio({source='current'}).error=='driver_required'); driver=0
liveOpened=EsAdmin.openVehicleStudio({source='current'}); assert(liveOpened.ok)
local liveThread=threads[#threads]; assert(coroutine.resume(liveThread))
controlled=false
assert(not EsAdmin.getVehicleStudioVehicle(liveOpened.session), 'Reject writes after ownership loss')
assert(coroutine.resume(liveThread)); assert(not frozen[2] and entities[2])
local controlPending=coroutine.create(function()
    assert(EsAdmin.openVehicleStudio({source='current'}).error=='cancelled')
end)
assert(coroutine.resume(controlPending)); EsAdmin.closeVehicleStudio(); controlled=true
assert(coroutine.resume(controlPending)); assert(not frozen[2])
controlled=false
controlPending=coroutine.create(function()
    assert(EsAdmin.openVehicleStudio({source='current'}).error=='no_control')
end)
assert(coroutine.resume(controlPending)); timer=timer+1600; assert(coroutine.resume(controlPending))
assert(not frozen[2] and entities[2])
controlled, networked, currentVehicle, driver = true, false, 2, ped
timer=0
assert(not EsAdmin.openVehicleStudio({model='invalid'}).ok)
inVehicle=true; assert(EsAdmin.openVehicleStudio({model='sultan'}).error=='stand_on_foot'); inVehicle=false
local opened=EsAdmin.openVehicleStudio({model='sultan'})
assert(opened.ok and frozen[1])
local preview=assert(EsAdmin.getVehicleStudioVehicle(opened.session))
assert(preview~=2)
assert(not EsAdmin.getVehicleStudioVehicle('stale'))
local thread=threads[#threads]; assert(coroutine.resume(thread)); assert(coroutine.resume(thread))
assert(clockOverride[1]==12 and EsAdmin.vehicleStudioClockActive)
assert(not EsAdmin.controlVehicleStudio({session=opened.session,action='lighting',minutes=1440,cycle=false}).ok)
assert(not EsAdmin.controlVehicleStudio({session=opened.session,action='lighting',minutes=0/0,cycle=false}).ok)
assert(EsAdmin.controlVehicleStudio({session=opened.session,action='lighting',minutes=1380,cycle=true}).ok)
timer=60000; assert(coroutine.resume(thread)); assert(clockOverride[1]==11, 'Cycle must wrap within valid local hours')
local before=camCoords[activeCam]
assert(EsAdmin.controlVehicleStudio({session=opened.session,action='camera',control='rotate',value=1}).ok)
assert(entities[preview].heading==15 and camCoords[activeCam].x==before.x, 'Vehicle rotation must not orbit the camera')
assert(not EsAdmin.closeVehicleStudio('stale').ok and entities[preview])
assert(EsAdmin.closeVehicleStudio(opened.session).ok)
assert(not entities[preview] and entities[2] and not frozen[1] and not clockOverride and not renderRequested)
assert(not EsAdmin.getVehicleStudioVehicle(opened.session))
-- Lost/early rendering handles, inherited freeze, and real camera takeover.
frozen[1],deferCam=true,true
opened=EsAdmin.openVehicleStudio({model='sultan'}); assert(opened.ok)
EsAdmin.closeVehicleStudio(); assert(not renderRequested and frozen[1]); frozen[1]=false
deferCam=false; opened=EsAdmin.openVehicleStudio({model='sultan'}); assert(opened.ok)
rendering=999; EsAdmin.closeVehicleStudio(); assert(rendering==999 and renderRequested); rendering=-1
-- Cancellation while streaming must not spawn a late entity.
modelLoaded=false
local pending=coroutine.create(function() local result=EsAdmin.openVehicleStudio({model='sultan'}); assert(result.error=='cancelled') end)
assert(coroutine.resume(pending)); EsAdmin.closeVehicleStudio(); modelLoaded=true; assert(coroutine.resume(pending))
assert(not frozen[1])
failCam=true; assert(not EsAdmin.openVehicleStudio({model='sultan'}).ok); failCam=false
assert(not frozen[1] and not EsAdmin.vehicleStudioClockActive)
opened=EsAdmin.openVehicleStudio({model='sultan'}); assert(opened.ok)
thread=threads[#threads]; assert(coroutine.resume(thread)); EsAdmin.state.allowed['vehicle.spawn']=false
assert(coroutine.resume(thread)); assert(not renderRequested and not frozen[1]); EsAdmin.state.allowed['vehicle.spawn']=true
-- Exercise the actual target resolver, then NUI sanitization/session forwarding.
local f=assert(io.open(root .. '/client/actions.lua','rb')); local actions=f:read('*a'); f:close()
local first=assert(actions:find('local function getDrivenCustomizationVehicle',1,true))
local last=assert(actions:find('local function customizationInteger',first,true))
local resolver=assert(load('local Admin=EsAdmin; local getPed=PlayerPedId\n' .. actions:sub(first,last-1) .. '\nreturn getDrivenCustomizationVehicle'))()
opened=EsAdmin.openVehicleStudio({model='sultan'}); preview=assert(resolver(opened.session))
assert(resolver()==2 and not resolver('old-session') and preview~=2)
EsAdmin.closeVehicleStudio()
opened=EsAdmin.openVehicleStudio({source='current'}); assert(opened.ok)
assert(resolver(opened.session)==2, 'Customization must resolve to the actual current vehicle')
EsAdmin.closeVehicleStudio()
opened=EsAdmin.openVehicleStudio({model='sultan'}); preview=assert(resolver(opened.session))
local callbacks, writes={},{}
function RegisterNUICallback(name,fn) callbacks[name]=fn end
function RegisterNetEvent() end
Config={ActionPermissions={['vehicle.spawn']=true,['vehicle.customColors']=true,['vehicle.customExtras']=true}}
EsAdmin.getVehicleCustomization=function(session) local v,e=resolver(session); if not v then return nil,e end; return {mods={},vehicle={model=123}} end
EsAdmin.setVehicleCustomization=function(data,session) local v,e=resolver(session); if not v then return false,e end; writes[#writes+1]={vehicle=v,data=data}; return true end
dofile(root .. '/client/nui.lua')
local function invoke(name,payload)
    local result,count=nil,0
    callbacks['cortex-admin:'..name](payload,function(v) result=v; count=count+1 end)
    assert(count==1,'Callback must complete exactly once'); return result
end
assert(not invoke('getVehicleCustomization',{studioSession=false}).ok)
assert(not invoke('setVehicleCustomization',{type='color',id='primary',value=27,studioSession='stale'}).ok)
assert(invoke('setVehicleCustomization',{type='customColor',id='primary',enabled=false,studioSession=opened.session}).ok)
assert(writes[#writes].vehicle==preview and writes[#writes].data.enabled==false)
assert(invoke('setVehicleCustomization',{type='extra',id=1,enabled=false,studioSession=opened.session}).ok)
assert(not invoke('setVehicleCustomization',{type='extra',id=1,enabled=0,studioSession=opened.session}).ok)
assert(not invoke('vehicleStudio',{action='camera',session='stale',control='rotate',value=1}).ok)
-- Saving uses the existing personal-garage record shape and never overwrites.
first=assert(actions:find('Admin.saveVehicleStudioPreset = function',1,true))
last=assert(actions:find('Admin.getVehicleCustomization = function',first,true))
assert(load("local Admin=EsAdmin; local C={PERSONAL_VEHICLE_SOURCE_ES_ADMIN='cortex-admin'}\n" .. actions:sub(first,last-1)))()
local savedRecords={}
function loadPersonalVehicles() return {vehicles=savedRecords} end
function sortPersonalVehicles() end
function savePersonalVehicles(data) savedRecords=data.vehicles; return true end
function EsAdmin.refreshPersonalVehiclesCache() end
function EsAdmin.getPersonalVehiclesCache() return savedRecords end
assert(EsAdmin.controlVehicleStudio({action='save',session=opened.session,name='  Midnight Sultan  '}).ok)
assert(#savedRecords==1 and savedRecords[1].name=='Midnight Sultan' and savedRecords[1].source=='cortex-admin'
    and savedRecords[1].props.model==123 and savedRecords[1].props.colors.primary==27)
assert(EsAdmin.controlVehicleStudio({action='save',session=opened.session,name='midnight sultan'}).error=='name_exists')
assert(not EsAdmin.controlVehicleStudio({action='save',session=opened.session,name=string.rep('x',65)}).ok)
EsAdmin.state.allowed['vehicle.savePersonal']=false
assert(EsAdmin.controlVehicleStudio({action='save',session=opened.session,name='Denied'}).error=='forbidden')
assert(#savedRecords==1)
handlers.onResourceStop('cortex-admin'); assert(not entities[preview] and not EsAdmin.vehicleStudioClockActive)
-- Drive the actual customization setter all the way to the native write.
first=assert(actions:find('local function getDrivenCustomizationVehicle',1,true))
last=assert(actions:find('-- GARAGE VEHICLE SPAWN (QBX)',first,true))
assert(load('local Admin=EsAdmin; local getPed=PlayerPedId\n' .. actions:sub(first,last-1)))()
local painted
function GetVehicleColours() return 0,1 end
function GetVehicleExtraColours() return 0,0 end
function ClearVehicleCustomPrimaryColour(vehicle) assert(vehicle==2) end
function SetVehicleColours(vehicle,primary,secondary) painted={vehicle,primary,secondary} end
opened=EsAdmin.openVehicleStudio({source='current'}); assert(opened.ok)
assert(EsAdmin.setVehicleCustomization({type='color',id='primary',value=27},opened.session))
assert(painted[1]==2 and painted[2]==27 and painted[3]==1, 'Paint must reach the original vehicle')
EsAdmin.closeVehicleStudio()
assert(entities[2] and painted[2]==27 and not frozen[2])
assert(not EsAdmin.setVehicleCustomization({type='color',id='primary',value=0},opened.session))
print('vehicle studio local isolation, clock, camera, cancellation and NUI session tests passed')
