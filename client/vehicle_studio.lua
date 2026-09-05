-- Edit the current/last vehicle or explicitly create a disposable model preview.
-- The admin menu remains the NUI focus owner.
local Admin = EsAdmin
local state = { generation = 0, active = false, loading = false }
local function allowed()
    return Admin.state.open and Admin.state.allowed['vehicle.spawn'] == true
end
local function finite(n) return type(n) == 'number' and n == n and math.abs(n) < math.huge end
local function integer(n, low, high) return finite(n) and n % 1 == 0 and n >= low and n <= high end
local function foreignCamera()
    local cam = GetRenderingCam()
    return cam and cam ~= -1 and cam ~= 0 and cam ~= state.cam
end

local function liveVehicleError(vehicle, ped)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 'no_source_vehicle' end
    if IsEntityDead(vehicle) then return 'vehicle_destroyed' end
    local current = GetVehiclePedIsIn(ped, false)
    if current ~= 0 and current ~= vehicle then return 'studio_session_expired' end
    local driver = GetPedInVehicleSeat(vehicle, -1)
    if driver ~= 0 and driver ~= ped then return 'driver_required' end
    local p, v = GetEntityCoords(ped), GetEntityCoords(vehicle)
    if (p.x-v.x)^2 + (p.y-v.y)^2 + (p.z-v.z)^2 > 225 then return 'source_too_far' end
end

Admin.getVehicleStudioVehicle = function(session)
    if not state.active or session ~= state.session or not allowed() or not state.vehicle
        or not DoesEntityExist(state.vehicle) then
        return nil, 'studio_session_expired'
    end
    if state.preview then
        if NetworkGetEntityIsNetworked(state.vehicle) then return nil, 'studio_session_expired' end
    else
        local err = liveVehicleError(state.vehicle, PlayerPedId())
        if err then return nil, err end
        if NetworkGetEntityIsNetworked(state.vehicle) and not NetworkHasControlOfEntity(state.vehicle) then
            return nil, 'no_control'
        end
    end
    return state.vehicle
end

Admin.closeVehicleStudio = function(session)
    if session and session ~= state.session then return { ok = false, error = 'studio_session_expired' } end
    local wasOpen = state.active or state.loading
    state.generation = state.generation + 1
    state.active, state.loading = false, false
    if state.renderRequested and not foreignCamera() then RenderScriptCams(false, false, 0, true, false) end
    state.renderRequested = false
    if state.cam and DoesCamExist(state.cam) then SetCamActive(state.cam, false); DestroyCam(state.cam, false) end
    state.cam = nil
    if state.vehicle and DoesEntityExist(state.vehicle) then
        if state.preview then DeleteEntity(state.vehicle)
        elseif state.vehicleWasFrozen == false then FreezeEntityPosition(state.vehicle, false) end
    end
    state.vehicle = nil
    state.preview, state.vehicleWasFrozen = nil, nil
    if state.ped and DoesEntityExist(state.ped) and not state.wasFrozen then FreezeEntityPosition(state.ped, false) end
    state.ped = nil
    if state.clockOwned then
        NetworkClearClockTimeOverride()
        if Admin.restoreWorldClock then Admin.restoreWorldClock() end
    end
    state.clockOwned, Admin.vehicleStudioClockActive = false, false
    if wasOpen then SendNUIMessage({ action = 'cortex-admin:vehicleStudioClosed', session = state.session }) end
    state.session = nil
    return { ok = true }
end

local function positionCamera()
    local a = math.rad(state.baseHeading + state.orbit)
    local radius = state.radius * state.zoom
    local center = state.center
    SetCamCoord(state.cam, center.x + math.sin(a) * radius, center.y - math.cos(a) * radius,
        center.z + radius * state.elevation)
    PointCamAtCoord(state.cam, center.x, center.y, center.z)
end

local function clockMinutes()
    return (state.minutes + (state.cycle and (GetGameTimer() - state.clockStarted) * 1440 / 120000 or 0)) % 1440
end

Admin.openVehicleStudio = function(data)
    if type(data) ~= 'table' then return { ok = false, error = 'invalid_payload' } end
    if not allowed() then return { ok = false, error = 'forbidden' } end
    if state.active or state.loading then return { ok = false, error = 'studio_busy' } end
    if foreignCamera() then return { ok = false, error = 'camera_busy' } end
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return { ok = false, error = 'player_unavailable' } end
    local source, model
    local preview = data.source == 'model' or (data.source == nil and data.model ~= nil)
    if data.source ~= nil and data.source ~= 'current' and data.source ~= 'model' then
        return { ok = false, error = 'invalid_source' }
    end
    if not preview then
        source = GetVehiclePedIsIn(ped, false)
        if source == 0 then source = GetVehiclePedIsIn(ped, true) end
        local err = liveVehicleError(source, ped)
        if err then return { ok = false, error = err } end
        model = GetEntityModel(source)
    else
        if IsPedInAnyVehicle(ped, false) then return { ok = false, error = 'stand_on_foot' } end
        if type(data.model) ~= 'string' or #data.model < 1 or #data.model > 64
            or not data.model:match('^[%w_%-]+$') then return { ok = false, error = 'invalid_model' } end
        model = joaat(data.model)
    end
    if not IsModelInCdimage(model) or not IsModelAVehicle(model) then return { ok = false, error = 'invalid_model' } end
    state.generation = state.generation + 1
    local generation = state.generation
    state.session = ('vs:%d:%d'):format(GetGameTimer(), generation)
    state.loading = true
    if preview then
        RequestModel(model)
        local deadline = GetGameTimer() + 8000
        while not HasModelLoaded(model) do
            if generation ~= state.generation then SetModelAsNoLongerNeeded(model); return { ok = false, error = 'cancelled' } end
            if not allowed() or GetGameTimer() > deadline then
                SetModelAsNoLongerNeeded(model); Admin.closeVehicleStudio()
                return { ok = false, error = 'model_load_failed' }
            end
            Wait(0)
        end
        if generation ~= state.generation or not allowed() or PlayerPedId() ~= ped
            or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) or foreignCamera() then
            SetModelAsNoLongerNeeded(model)
            if generation == state.generation then Admin.closeVehicleStudio() end
            return { ok = false, error = 'cancelled' }
        end
    end
    local minimum, maximum = GetModelDimensions(model)
    local size = math.max(maximum.x-minimum.x, maximum.y-minimum.y, maximum.z-minimum.z)
    if not finite(size) or size < 0.2 or size > 22 then
        if preview then SetModelAsNoLongerNeeded(model) end
        Admin.closeVehicleStudio(); return { ok = false, error = 'model_too_large' }
    end
    state.preview = preview
    if not preview then
        local deadline = GetGameTimer() + 1500
        while NetworkGetEntityIsNetworked(source) and not NetworkHasControlOfEntity(source) do
            if generation ~= state.generation then return { ok = false, error = 'cancelled' } end
            local err = liveVehicleError(source, ped)
            if err or not allowed() or PlayerPedId() ~= ped or GetGameTimer() > deadline then
                Admin.closeVehicleStudio(); return { ok = false, error = err or 'no_control' }
            end
            NetworkRequestControlOfEntity(source)
            Wait(0)
        end
        if generation ~= state.generation then return { ok = false, error = 'cancelled' } end
        local err = liveVehicleError(source, ped)
        if err or not allowed() or PlayerPedId() ~= ped or IsEntityDead(ped) or foreignCamera() then
            Admin.closeVehicleStudio(); return { ok = false, error = err or 'cancelled' }
        end
        state.vehicle, state.vehicleWasFrozen = source, IsEntityPositionFrozen(source)
        FreezeEntityPosition(source, true)
        state.baseHeading = GetEntityHeading(source)
        local center = GetOffsetFromEntityInWorldCoords(source, (minimum.x+maximum.x)*0.5,
            (minimum.y+maximum.y)*0.5, (minimum.z+maximum.z)*0.5)
        state.center = { x = center.x, y = center.y, z = center.z }
    else
        local spawn = GetOffsetFromEntityInWorldCoords(ped, 0.0, math.max(7.0, size + 3.0), 0.0)
        local found, ground = GetGroundZFor_3dCoord(spawn.x, spawn.y, spawn.z + 5.0, false)
        if not found then SetModelAsNoLongerNeeded(model); Admin.closeVehicleStudio(); return { ok = false, error = 'ground_unavailable' } end
        state.baseHeading = GetEntityHeading(ped)
        state.vehicle = CreateVehicle(model, spawn.x, spawn.y, ground - minimum.z + 0.05, state.baseHeading, false, false)
        SetModelAsNoLongerNeeded(model)
        if not state.vehicle or state.vehicle == 0 or not DoesEntityExist(state.vehicle) then
            Admin.closeVehicleStudio(); return { ok = false, error = 'spawn_failed' }
        end
        SetEntityAsMissionEntity(state.vehicle, true, false)
        FreezeEntityPosition(state.vehicle, true)
        SetEntityCollision(state.vehicle, false, false)
        SetEntityInvincible(state.vehicle, true)
        SetVehicleDoorsLocked(state.vehicle, 2)
        SetVehicleEngineOn(state.vehicle, false, true, true)
        SetVehicleDirtLevel(state.vehicle, 0.0)
        SetVehicleModKit(state.vehicle, 0)
        state.center = { x = spawn.x, y = spawn.y, z = ground + (maximum.z-minimum.z) * 0.5 }
    end
    state.ped, state.wasFrozen = ped, IsEntityPositionFrozen(ped)
    FreezeEntityPosition(ped, true)
    state.radius = math.max(4.0, size * 1.65)
    state.orbit, state.zoom, state.rotation, state.elevation = 35.0, 1.0, state.baseHeading, 0.28
    state.cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', false)
    if not state.cam or state.cam == 0 or not DoesCamExist(state.cam) then
        Admin.closeVehicleStudio(); return { ok = false, error = 'camera_unavailable' }
    end
    SetCamFov(state.cam, 42.0)
    positionCamera()
    SetCamActive(state.cam, true)
    state.renderRequested = true
    RenderScriptCams(true, false, 0, true, false)
    state.minutes, state.cycle, state.clockStarted = 12 * 60, false, GetGameTimer()
    state.active, state.loading, state.clockOwned, Admin.vehicleStudioClockActive = true, false, true, true
    CreateThread(function()
        Wait(0)
        while state.active and generation == state.generation do
            if not allowed() or PlayerPedId() ~= state.ped or IsEntityDead(state.ped)
                or not DoesEntityExist(state.vehicle) or not DoesCamExist(state.cam)
                or not IsCamActive(state.cam) or foreignCamera() then Admin.closeVehicleStudio(); break end
            if not Admin.getVehicleStudioVehicle(state.session) then Admin.closeVehicleStudio(); break end
            local p = GetEntityCoords(state.ped)
            if (p.x-state.center.x)^2 + (p.y-state.center.y)^2 + (p.z-state.center.z)^2 > 10000 then
                Admin.closeVehicleStudio(); break
            end
            local minute = clockMinutes()
            NetworkOverrideClockTime(math.floor(minute / 60), math.floor(minute % 60), math.floor((minute % 1) * 60))
            -- Only the local clock needs a frame-bound override. Camera framing
            -- and vehicle transforms change exclusively on explicit controls.
            Wait(0)
        end
    end)
    return { ok = true, session = state.session, label = getVehicleLabel(model), model = model, preview = preview,
        canSave = Admin.state.allowed['vehicle.savePersonal'] == true }
end

Admin.controlVehicleStudio = function(data)
    local vehicle, err = Admin.getVehicleStudioVehicle(data.session)
    if not vehicle then return { ok = false, error = err } end
    if foreignCamera() then return { ok = false, error = 'camera_busy' } end
    if data.action == 'camera' then
        if data.control == 'rotate' and (data.value == 1 or data.value == -1) then
            if not state.preview then return { ok = false, error = 'preview_only' } end
            state.rotation = (state.rotation + data.value * 15) % 360
            SetEntityHeading(vehicle, state.rotation)
        elseif data.control == 'orbit' and (data.value == 1 or data.value == -1) then state.orbit = (state.orbit + data.value * 15) % 360
        elseif data.control == 'zoom' and (data.value == 1 or data.value == -1) then state.zoom = math.max(0.65, math.min(1.6, state.zoom + data.value * 0.1))
        elseif data.control == 'view' and (data.value == 'low' or data.value == 'high') then state.elevation = data.value == 'low' and 0.1 or 0.55
        elseif data.control == 'reset' then
            state.orbit, state.zoom, state.elevation, state.rotation = 35.0, 1.0, 0.28, state.baseHeading
            if state.preview then SetEntityHeading(vehicle, state.rotation) end
        else return { ok = false, error = 'invalid_camera_control' } end
        positionCamera()
    elseif data.action == 'lighting' then
        if not integer(data.minutes, 0, 1439) or type(data.cycle) ~= 'boolean' then return { ok = false, error = 'invalid_lighting' } end
        state.minutes, state.cycle, state.clockStarted = data.minutes, data.cycle, GetGameTimer()
    elseif data.action == 'save' then
        if Admin.state.allowed['vehicle.savePersonal'] ~= true then return { ok = false, error = 'forbidden' } end
        return Admin.saveVehicleStudioPreset(data.session, data.name)
    else return { ok = false, error = 'invalid_action' } end
    return { ok = true }
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Admin.closeVehicleStudio() end
end)
