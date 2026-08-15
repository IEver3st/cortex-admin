--[[
    vMenu-compatible client behavior for Cortex Admin.

    The declarative action catalog is shared/vmenu_compat.lua. This module wraps
    the existing action dispatcher so established Cortex actions are untouched.
]]

local Admin = EsAdmin
local state = Admin.state
local vmenuCompatibilityEnabled = not Config.VmenuCompatibility
    or Config.VmenuCompatibility.enabled ~= false

if not vmenuCompatibilityEnabled then
    -- Core model actions use this API for the optional imported vMenu
    -- allowlists. With compatibility disabled there is no imported allowlist,
    -- so preserve the core action flow without registering any compat events.
    Admin.authorizeVmenuModels = function(kind, models, actionId)
        if type(kind) ~= 'string' or type(models) ~= 'table' or #models < 1 or #models > 256
            or type(actionId) ~= 'string' then
            return { ok = false, error = 'invalid_request', allowed = {} }
        end
        local allowed = {}
        for index = 1, #models do allowed[index] = true end
        return { ok = true, allowed = allowed }
    end
    Admin.authorizeVmenuModel = function(kind, model, actionId)
        local result = Admin.authorizeVmenuModels(kind, { model }, actionId)
        return result.ok == true and result.allowed[1] == true, result.error, nil
    end
    return
end

local resourceName = GetCurrentResourceName()

local compat = {
    personalVehicle = 0,
    personalBlip = 0,
    spawnedEntities = {},
    locationBlips = {},
    spectatingServerId = nil,
    spectatingPed = 0,
    autopilotStyle = 786603,
    autopilotSpeed = 22.22,
    lastDoor = 0,
    lastVehicle = 0,
    lastRadioVehicle = 0,
    lastDeathReported = false,
    placement = nil,
    dimensionEntities = {},
    dimensionLabels = {},
    cameraHeading = nil,
    cameraPitch = nil,
    pointing = false,
    radarExpanded = false,
    radarBaselineVisible = nil,
    vehicleBaselines = {},
    currentEffectVehicle = 0,
    inspectorEntity = 0,
    lastPed = 0,
    deathCleanupApplied = false,
    clothingGlowTouched = false,
    parachuteBaseline = nil,
    parachuteSmokeTouched = false,
    autoParachutePeds = {},
    parachuteAuthorization = {},
    imported = {},
}

local pendingCompatibilityRequests = {}
local pendingConfigDomainRequests = {}
local pendingBanListRequests = {}
local pendingUnbanRequests = {}
local pendingModelAuthorizationRequests = {}
local pendingEntitySpawnRequests = {}
local pendingVmenuBanToken = nil

local persistentToggleIds = {
    ['player.stayInVehicle'] = true,
    ['vehicle.engineAlwaysOn'] = true,
    ['vehicle.noSiren'] = true,
    ['vehicle.noHelmet'] = true,
    ['vehicle.anchorBoat'] = true,
    ['vehicle.flashHighbeams'] = true,
    ['vehicle.infiniteFuel'] = true,
    ['vehicle.showHealth'] = true,
    ['vehicle.autoRepair'] = true,
    ['vehicle.strongWheels'] = true,
    ['vehicle.preventEngineDamage'] = true,
    ['vehicle.preventVisualDamage'] = true,
    ['vehicle.preventRampDamage'] = true,
    ['vehicle.bulletproofTyres'] = true,
    ['vehicle.lowGripTyres'] = true,
    ['vehicle.torqueEnabled'] = true,
    ['vehicle.powerEnabled'] = true,
    ['vehicle.defaultRadioEnabled'] = true,
    ['vehicle.deleteRemovedDoors'] = true,
    ['weapons.noReload'] = true,
    ['weapons.unlimitedParachutes'] = true,
    ['weapons.autoEquipParachute'] = true,
    ['weapons.restoreLoadoutOnRespawn'] = true,
    ['dev.showTime'] = true,
    ['dev.overheadNames'] = true,
    ['dev.joinQuitNotifications'] = true,
    ['dev.deathNotifications'] = true,
    ['dev.driftMode'] = true,
    ['dev.locationBlips'] = true,
    ['dev.hideRadar'] = true,
    ['dev.locationDisplay'] = true,
    ['dev.vehicleDimensions'] = true,
    ['dev.propDimensions'] = true,
    ['dev.pedDimensions'] = true,
    ['dev.entityHandles'] = true,
    ['dev.entityModels'] = true,
    ['dev.entityOwners'] = true,
    ['dev.lockCameraHorizontal'] = true,
    ['dev.lockCameraVertical'] = true,
    ['voice.enabled'] = true,
    ['voice.showSpeaker'] = true,
    ['voice.showStatus'] = true,
    ['options.teleportWaypointKey'] = true,
}

local function notify(kind, message)
    if Admin.notify then
        Admin.notify(kind, message)
    end
end

local function trim(value, maxLength)
    if type(value) ~= 'string' then return nil end
    value = value:match('^%s*(.-)%s*$')
    if value == '' then return nil end
    if maxLength and #value > maxLength then value = value:sub(1, maxLength) end
    return value
end

local function finite(value, minValue, maxValue)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    if minValue and number < minValue then return nil end
    if maxValue and number > maxValue then return nil end
    return number
end

local function integer(value, minValue, maxValue)
    local number = finite(value, minValue, maxValue)
    if not number or number ~= math.floor(number) then return nil end
    return number
end

local function clone(value)
    local ok, encoded = pcall(json.encode, value)
    if not ok then return nil end
    local decodedOk, decoded = pcall(json.decode, encoded)
    return decodedOk and decoded or nil
end

local function loadJsonKvp(key, fallback)
    local raw = GetResourceKvpString(key)
    if type(raw) ~= 'string' or raw == '' then return fallback end
    local ok, decoded = pcall(json.decode, raw)
    return ok and type(decoded) == 'table' and decoded or fallback
end

local function saveJsonKvp(key, value, maxBytes)
    local ok, encoded = pcall(json.encode, value)
    local limit = tonumber(maxBytes) or 4 * 1024 * 1024
    if not ok or type(encoded) ~= 'string' or #encoded > limit then return false end
    SetResourceKvp(key, encoded)
    return true
end

local preferences = loadJsonKvp(Config.KvpKeys.vmenuPreferences, {
    toggles = {},
    drivingStyle = 786603,
    drivingSpeed = 22.22,
    voiceProximity = 8.0,
    voiceChannel = 0,
    defaultLoadout = '',
    defaultRadioStation = 'OFF',
    primaryChuteStyle = 0,
    clothingGlowStyle = 0,
    dimensionRadius = 50.0,
    torqueMultiplier = 1.0,
    powerMultiplier = 1.0,
})

compat.imported = loadJsonKvp(Config.KvpKeys.vmenuImport, {})
compat.importedConfig = loadJsonKvp(Config.KvpKeys.vmenuClientConfig, {})
compat.importedCategories = loadJsonKvp(Config.KvpKeys.vmenuCategories, {})

preferences.toggles = type(preferences.toggles) == 'table' and preferences.toggles or {}
compat.autopilotStyle = integer(preferences.drivingStyle, 0, 2147483647) or 786603
compat.autopilotSpeed = finite(preferences.drivingSpeed, 1.0, 100.0) or 22.22
preferences.defaultRadioStation = trim(preferences.defaultRadioStation, 64) or 'OFF'
preferences.primaryChuteStyle = integer(preferences.primaryChuteStyle, 0, 13) or 0
preferences.clothingGlowStyle = integer(preferences.clothingGlowStyle, 0, 3) or 0
preferences.dimensionRadius = finite(preferences.dimensionRadius, 10.0, 200.0) or 50.0
preferences.torqueMultiplier = finite(preferences.torqueMultiplier, 1.0, 1024.0) or 1.0
preferences.powerMultiplier = finite(preferences.powerMultiplier, 1.0, 1024.0) or 1.0

for actionId, enabled in pairs(preferences.toggles) do
    if persistentToggleIds[actionId] and type(enabled) == 'boolean' then
        state.toggles[actionId] = enabled
    end
end

local function savePreferences()
    preferences.drivingStyle = compat.autopilotStyle
    preferences.drivingSpeed = compat.autopilotSpeed
    saveJsonKvp(Config.KvpKeys.vmenuPreferences, preferences)
end

local function setCompatToggle(actionId, enabled)
    enabled = enabled == true
    state.toggles[actionId] = enabled
    if persistentToggleIds[actionId] then
        preferences.toggles[actionId] = enabled
        savePreferences()
    end
    SendNUIMessage({ action = 'cortex-admin:setState', data = { toggles = state.toggles } })
end

local function playerPed()
    return PlayerPedId()
end

local function currentVehicle(requireDriver)
    local ped = playerPed()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        notify('error', 'Enter a vehicle first.')
        return nil
    end
    if requireDriver and GetPedInVehicleSeat(vehicle, -1) ~= ped then
        notify('error', 'You must be the driver.')
        return nil
    end
    compat.lastVehicle = vehicle
    return vehicle
end

local function personalVehicle()
    local vehicle = compat.personalVehicle
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        compat.personalVehicle = 0
        notify('error', 'Set a personal vehicle first.')
        return nil
    end
    return vehicle
end

local function requestControl(entity, timeoutMs)
    if entity == 0 or not DoesEntityExist(entity) then return false end
    if not NetworkGetEntityIsNetworked(entity) or NetworkHasControlOfEntity(entity) then return true end
    local deadline = GetGameTimer() + (timeoutMs or 750)
    repeat
        NetworkRequestControlOfEntity(entity)
        Wait(0)
    until NetworkHasControlOfEntity(entity) or GetGameTimer() >= deadline
    return NetworkHasControlOfEntity(entity)
end

local function tableIsEmpty(value)
    return type(value) ~= 'table' or next(value) == nil
end

local function vehicleMatchesBaseline(record)
    local vehicle = type(record) == 'table' and record.entity or 0
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    if record.model and GetEntityModel(vehicle) ~= record.model then return false end
    if record.networkId and NetworkGetEntityIsNetworked(vehicle)
        and NetworkGetNetworkIdFromEntity(vehicle) ~= record.networkId then return false end
    return true
end

local function captureVehicleBaseline(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local current = compat.vehicleBaselines[vehicle]
    if current and vehicleMatchesBaseline(current) then return current end

    local networked = NetworkGetEntityIsNetworked(vehicle)
    local record = {
        entity = vehicle,
        model = GetEntityModel(vehicle),
        networkId = networked and NetworkGetNetworkIdFromEntity(vehicle) or nil,
        features = {},
        visible = IsEntityVisible(vehicle),
        tyresCanBurst = GetVehicleTyresCanBurst and GetVehicleTyresCanBurst(vehicle) or true,
    }
    compat.vehicleBaselines[vehicle] = record
    return record
end

local function markVehicleFeature(vehicle, feature)
    local record = captureVehicleBaseline(vehicle)
    if not record then return nil end
    if feature == 'defaultRadio' and record.features.defaultRadio ~= true then
        record.radioStation = GetPlayerRadioStationName and GetPlayerRadioStationName() or 'OFF'
        record.radioEnabled = IsVehicleRadioOn and IsVehicleRadioOn(vehicle)
            or IsPlayerVehRadioEnable and IsPlayerVehRadioEnable()
            or false
    elseif feature == 'engineAlwaysOn' and record.features.engineAlwaysOn ~= true then
        record.engineRunning = GetIsVehicleEngineRunning(vehicle)
    end
    record.features[feature] = true
    return record
end

local function restoreVehicleFeatureRecord(record, feature)
    if type(record) ~= 'table' or type(record.features) ~= 'table' or record.features[feature] ~= true then return end
    local vehicle = record.entity
    record.features[feature] = nil

    if not vehicleMatchesBaseline(record) then
        compat.vehicleBaselines[vehicle] = nil
        return
    end

    if feature == 'freeze' then
        FreezeEntityPosition(vehicle, false)
    elseif feature == 'invisible' then
        SetEntityVisible(vehicle, record.visible ~= false, false)
    elseif feature == 'noSiren' then
        SetVehicleHasMutedSirens(vehicle, false)
    elseif feature == 'engineAlwaysOn' then
        SetVehicleEngineOn(vehicle, record.engineRunning == true, true, true)
    elseif feature == 'anchorBoat' then
        if IsThisModelABoat(GetEntityModel(vehicle)) then
            SetBoatAnchor(vehicle, false)
            SetBoatFrozenWhenAnchored(vehicle, false)
            SetForcedBoatLocationWhenAnchored(vehicle, false)
        end
    elseif feature == 'strongWheels' then
        SetVehicleWheelsCanBreak(vehicle, true)
    elseif feature == 'bulletproofTyres' then
        SetVehicleTyresCanBurst(vehicle, record.tyresCanBurst ~= false)
    elseif feature == 'lowGrip' or feature == 'drift' then
        SetVehicleReduceGrip(vehicle, record.features.lowGrip == true or record.features.drift == true)
    elseif feature == 'preventEngineDamage' then
        if SetVehicleEngineCanDegrade then SetVehicleEngineCanDegrade(vehicle, true) end
    elseif feature == 'preventVisualDamage' then
        SetVehicleCanBeVisiblyDamaged(vehicle, true)
    elseif feature == 'preventRampDamage' then
        if SetRampVehicleReceivesRampDamage then SetRampVehicleReceivesRampDamage(vehicle, true) end
    elseif feature == 'torque' then
        SetVehicleEngineTorqueMultiplier(vehicle, 1.0)
    elseif feature == 'power' then
        SetVehicleEnginePowerMultiplier(vehicle, 1.0)
    elseif feature == 'defaultRadio' then
        local station = trim(record.radioStation, 64) or 'OFF'
        SetVehRadioStation(vehicle, station)
        SetVehicleRadioEnabled(vehicle, record.radioEnabled == true)
    elseif feature == 'fullbeam' then
        SetVehicleFullbeam(vehicle, false)
    elseif feature == 'exclusiveDriver' then
        if SetVehicleExclusiveDriver_2 then SetVehicleExclusiveDriver_2(vehicle, 0, 1) end
    end

    if tableIsEmpty(record.features) then compat.vehicleBaselines[vehicle] = nil end
end

local function restoreTrackedVehicleFeature(feature)
    local records = {}
    for _, record in pairs(compat.vehicleBaselines) do records[#records + 1] = record end
    for index = 1, #records do restoreVehicleFeatureRecord(records[index], feature) end
end

local currentVehicleFeatures = {
    'freeze', 'invisible', 'noSiren', 'anchorBoat', 'strongWheels', 'bulletproofTyres',
    'lowGrip', 'drift', 'preventEngineDamage', 'preventVisualDamage', 'preventRampDamage',
    'torque', 'power', 'defaultRadio', 'fullbeam',
}

local function restoreVehicleContext(vehicle)
    local record = compat.vehicleBaselines[vehicle]
    if not record then return end
    for index = 1, #currentVehicleFeatures do
        restoreVehicleFeatureRecord(record, currentVehicleFeatures[index])
    end
end

local function setCurrentEffectVehicle(vehicle)
    vehicle = vehicle and vehicle ~= 0 and vehicle or 0
    if compat.currentEffectVehicle == vehicle then return end
    if compat.currentEffectVehicle ~= 0 then restoreVehicleContext(compat.currentEffectVehicle) end
    compat.currentEffectVehicle = vehicle
    compat.lastRadioVehicle = 0
end

local function restoreAllVehicleEffects()
    local records = {}
    for _, record in pairs(compat.vehicleBaselines) do records[#records + 1] = record end
    for index = 1, #records do
        local record = records[index]
        local features = {}
        for feature in pairs(record.features or {}) do features[#features + 1] = feature end
        for featureIndex = 1, #features do restoreVehicleFeatureRecord(record, features[featureIndex]) end
    end
    compat.vehicleBaselines = {}
    compat.currentEffectVehicle = 0
    compat.lastRadioVehicle = 0
end

local function captureRadarBaseline()
    if compat.radarBaselineVisible == nil then
        compat.radarBaselineVisible = not (IsRadarHidden and IsRadarHidden() or false)
    end
end

local function restoreRadarBaseline()
    SetRadarBigmapEnabled(false, false)
    compat.radarExpanded = false
    if compat.radarBaselineVisible ~= nil and state.toggles['dev.noHud'] ~= true then
        DisplayRadar(compat.radarBaselineVisible == true)
    end
    compat.radarBaselineVisible = nil
end

local function captureParachuteBaseline()
    if compat.parachuteBaseline then return compat.parachuteBaseline end
    local player = PlayerId()
    local ped = playerPed()
    local smokeR, smokeG, smokeB = GetPlayerParachuteSmokeTrailColor(player)
    compat.parachuteBaseline = {
        ped = ped,
        hadPrimary = HasPedGotWeapon(ped, joaat('gadget_parachute'), false),
        primaryTint = GetPlayerParachuteTintIndex(player),
        reserveTint = GetPlayerReserveParachuteTintIndex(player),
        smokeR = smokeR,
        smokeG = smokeG,
        smokeB = smokeB,
    }
    return compat.parachuteBaseline
end

local function restoreParachuteBaseline()
    local baseline = compat.parachuteBaseline
    if type(baseline) == 'table' then
        local player = PlayerId()
        local ped = baseline.ped
        if ped and DoesEntityExist(ped) then
            local chute = joaat('gadget_parachute')
            local hasPrimary = HasPedGotWeapon(ped, chute, false)
            if baseline.hadPrimary and not hasPrimary then
                GiveWeaponToPed(ped, chute, 1, false, false)
            elseif not baseline.hadPrimary and hasPrimary then
                RemoveWeaponFromPed(ped, chute)
            end
        end
        if integer(baseline.primaryTint, 0, 13) then SetPlayerParachuteTintIndex(player, baseline.primaryTint) end
        if integer(baseline.reserveTint, 0, 13) then SetPlayerReserveParachuteTintIndex(player, baseline.reserveTint) end
        if integer(baseline.smokeR, 0, 255) and integer(baseline.smokeG, 0, 255) and integer(baseline.smokeB, 0, 255) then
            SetPlayerParachuteSmokeTrailColor(player, baseline.smokeR, baseline.smokeG, baseline.smokeB)
        end
    end
    if compat.parachuteSmokeTouched then SetPlayerCanLeaveParachuteSmokeTrail(PlayerId(), false) end
    compat.parachuteBaseline = nil
    compat.parachuteSmokeTouched = false
    compat.autoParachutePeds = {}
end

local function clearDimensionOutlines()
    for entity in pairs(compat.dimensionEntities) do
        if DoesEntityExist(entity) then SetEntityDrawOutline(entity, false) end
    end
    compat.dimensionEntities = {}
    compat.dimensionLabels = {}
end

local function drawText3d(coords, text)
    local visible, sx, sy = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not visible then return end
    SetTextScale(0.25, 0.25)
    SetTextFont(0)
    SetTextProportional(1)
    SetTextCentre(true)
    SetTextColour(247, 248, 248, 220)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(sx, sy)
end

local function inspectNearbyEntities(origin, radius, toggles)
    local seen = {}
    local pools = {
        toggles['dev.vehicleDimensions'] and 'CVehicle' or nil,
        toggles['dev.propDimensions'] and 'CObject' or nil,
        toggles['dev.pedDimensions'] and 'CPed' or nil,
    }
    for index = 1, #pools do
        local poolName = pools[index]
        if poolName then
            local pool = GetGamePool(poolName)
            for entityIndex = 1, math.min(#pool, 256) do
                local entity = pool[entityIndex]
                if entity ~= playerPed() and DoesEntityExist(entity) then
                    local coords = GetEntityCoords(entity)
                    local distance = #(origin - coords)
                    if distance <= radius then
                        seen[entity] = true
                        compat.dimensionEntities[entity] = true
                        SetEntityDrawOutlineColor(113, 112, 255, 190)
                        SetEntityDrawOutline(entity, true)
                        local minBounds, maxBounds = GetModelDimensions(GetEntityModel(entity))
                        local width = math.abs((maxBounds and maxBounds.x or 0) - (minBounds and minBounds.x or 0))
                        local length = math.abs((maxBounds and maxBounds.y or 0) - (minBounds and minBounds.y or 0))
                        local height = math.abs((maxBounds and maxBounds.z or 0) - (minBounds and minBounds.z or 0))
                        local parts = { ('%.1fx%.1fx%.1f'):format(width, length, height) }
                        if toggles['dev.entityHandles'] then parts[#parts + 1] = ('handle %d'):format(entity) end
                        if toggles['dev.entityModels'] then parts[#parts + 1] = ('model %u'):format(GetEntityModel(entity)) end
                        if toggles['dev.entityOwners'] then
                            local owner = NetworkGetEntityOwner(entity)
                            parts[#parts + 1] = owner and owner >= 0 and ('owner %d'):format(GetPlayerServerId(owner)) or 'owner none'
                        end
                        drawText3d(vector3(coords.x, coords.y, coords.z + height + 0.35), table.concat(parts, ' | '))
                        compat.dimensionLabels[entity] = { text = table.concat(parts, ' | '), height = height }
                    end
                end
            end
        end
    end
    for entity in pairs(compat.dimensionEntities) do
        if not seen[entity] then
            if DoesEntityExist(entity) then SetEntityDrawOutline(entity, false) end
            compat.dimensionEntities[entity] = nil
            compat.dimensionLabels[entity] = nil
        end
    end
end

local function drawDimensionLabels()
    for entity, label in pairs(compat.dimensionLabels) do
        if DoesEntityExist(entity) then
            local coords = GetEntityCoords(entity)
            drawText3d(vector3(coords.x, coords.y, coords.z + (label.height or 0.0) + 0.35), label.text or '')
        end
    end
end

local function clearLocationBlips()
    for index = #compat.locationBlips, 1, -1 do
        local blip = compat.locationBlips[index]
        if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
        table.remove(compat.locationBlips, index)
    end
end

local function importedLocations()
    local config = type(compat.importedConfig) == 'table' and compat.importedConfig or {}
    return type(config.locations) == 'table' and config.locations or {}
end

local function importedDomain(name)
    local config = type(compat.importedConfig) == 'table' and compat.importedConfig or {}
    return type(config[name]) == 'table' and config[name] or {}
end

local function refreshLocationBlips()
    clearLocationBlips()
    if state.toggles['dev.locationBlips'] ~= true then return end
    local locations = importedLocations()
    local blips = type(locations.blips) == 'table' and locations.blips or {}
    for index = 1, math.min(#blips, 512) do
        local entry = blips[index]
        local coords = type(entry) == 'table' and entry.coordinates or nil
        local x = coords and finite(coords.x, -20000, 20000)
        local y = coords and finite(coords.y, -20000, 20000)
        local z = coords and finite(coords.z, -20000, 20000)
        if x and y and z then
            local blip = AddBlipForCoord(x, y, z)
            SetBlipSprite(blip, integer(entry.spriteID, 0, 1000) or 1)
            SetBlipColour(blip, integer(entry.color, 0, 85) or 0)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(trim(entry.name, 96) or 'Imported location')
            EndTextCommandSetBlipName(blip)
            compat.locationBlips[#compat.locationBlips + 1] = blip
        end
    end
end

local function setVehicleLights(vehicle, mode)
    mode = integer(mode, 0, 3) or 0
    if mode == 3 then
        SetVehicleLights(vehicle, 2)
        SetVehicleFullbeam(vehicle, true)
    else
        SetVehicleFullbeam(vehicle, false)
        SetVehicleLights(vehicle, mode)
    end
end

local function applyDoors(vehicle, command)
    if type(command) ~= 'string' then return end
    if command == 'open_all' then
        for door = 0, 7 do SetVehicleDoorOpen(vehicle, door, false, false) end
        if OpenBombBayDoors then OpenBombBayDoors(vehicle) end
        return
    end
    if command == 'close_all' then
        for door = 0, 7 do SetVehicleDoorShut(vehicle, door, false) end
        if CloseBombBayDoors then CloseBombBayDoors(vehicle) end
        return
    end
    if command == 'restore' then
        SetVehicleFixed(vehicle)
        return
    end
    if command == 'bomb_bay' then
        if AreBombBayDoorsOpen and AreBombBayDoorsOpen(vehicle) then
            if CloseBombBayDoors then CloseBombBayDoors(vehicle) end
        elseif OpenBombBayDoors then
            OpenBombBayDoors(vehicle)
        end
        return
    end
    local removedDoor = integer(command:match('^remove_(%d+)$'), 0, 7)
    if removedDoor then
        compat.lastDoor = removedDoor
        SetVehicleDoorBroken(vehicle, removedDoor, state.toggles['vehicle.deleteRemovedDoors'] == true)
        return
    end
    local door = integer(command:match('^toggle_(%d+)$'), 0, 7)
    if door then
        compat.lastDoor = door
        if GetVehicleDoorAngleRatio(vehicle, door) > 0.1 then
            SetVehicleDoorShut(vehicle, door, false)
        else
            SetVehicleDoorOpen(vehicle, door, false, false)
        end
    end
end

local function applyWindows(vehicle, command)
    local groups = {
        front_up = { 0, 1 }, front_down = { 0, 1 },
        rear_up = { 2, 3 }, rear_down = { 2, 3 },
        all_up = { 0, 1, 2, 3 }, all_down = { 0, 1, 2, 3 },
    }
    local indexes = groups[command]
    if not indexes then return end
    local shouldRaise = command:sub(-3) == '_up'
    for index = 1, #indexes do
        if shouldRaise then RollUpWindow(vehicle, indexes[index]) else RollDownWindow(vehicle, indexes[index]) end
    end
end

local function applyTyres(vehicle, command)
    if type(command) ~= 'string' then return end
    local tyreIndexes = { 0, 1, 2, 3, 4, 5, 45, 47 }
    if command == 'fix_all' or command == 'burst_all' then
        for index = 1, #tyreIndexes do
            local tyre = tyreIndexes[index]
            if command == 'fix_all' then SetVehicleTyreFixed(vehicle, tyre) else SetVehicleTyreBurst(vehicle, tyre, false, 1000.0) end
        end
        return
    end
    local verb, rawTyre = command:match('^(fix)_([%d]+)$')
    if not verb then verb, rawTyre = command:match('^(burst)_([%d]+)$') end
    local tyre = integer(rawTyre, 0, 47)
    if not tyre then return end
    if verb == 'fix' then SetVehicleTyreFixed(vehicle, tyre) else SetVehicleTyreBurst(vehicle, tyre, false, 1000.0) end
end

local walkingStyles = {
    injured = { male = 'move_m@injured', female = 'move_f@injured' },
    tough = { male = 'move_m@tough_guy@', female = 'move_f@tough_guy@' },
    femme = { male = 'move_m@femme@', female = 'move_f@femme@' },
    gangster = { male = 'move_m@gangster@a', female = 'move_f@gangster@ng' },
    posh = { male = 'move_m@posh@', female = 'move_f@posh@' },
    sexy = { female = 'move_f@sexy@a' },
    business = { female = 'move_f@business@a' },
    drunk = { male = 'move_m@drunk@a', female = 'move_f@drunk@a' },
    hipster = { male = 'move_m@hipster@a' },
}

local function applyWalkingStyle(style)
    local ped = playerPed()
    ResetPedMovementClipset(ped, 0.25)
    if style == 'normal' then
        notify('success', 'Walking style reset.')
        return
    end
    local model = GetEntityModel(ped)
    local gender = model == joaat('mp_f_freemode_01') and 'female' or model == joaat('mp_m_freemode_01') and 'male' or nil
    if not gender then
        notify('error', 'Walking styles require a freemode ped.')
        return
    end
    local entry = walkingStyles[style]
    local clipset = entry and entry[gender]
    if not clipset then
        notify('error', 'That walking style is unavailable for this ped.')
        return
    end
    RequestAnimSet(clipset)
    local deadline = GetGameTimer() + 3000
    while not HasAnimSetLoaded(clipset) and GetGameTimer() < deadline do Wait(0) end
    if not HasAnimSetLoaded(clipset) then
        notify('error', 'Walking style failed to load.')
        return
    end
    SetPedMovementClipset(ped, clipset, 0.25)
    RemoveAnimSet(clipset)
    notify('success', 'Walking style applied.')
end

local function setSpectate(targetServerId)
    if not targetServerId then
        if compat.spectatingServerId then
            NetworkSetInSpectatorMode(false, compat.spectatingPed)
            compat.spectatingServerId = nil
            compat.spectatingPed = 0
            notify('info', 'Spectating stopped.')
        end
        return
    end
    if compat.spectatingServerId then
        NetworkSetInSpectatorMode(false, compat.spectatingPed)
        compat.spectatingServerId = nil
        compat.spectatingPed = 0
        notify('info', 'Spectating stopped.')
        if not targetServerId then return end
    end
    local player = GetPlayerFromServerId(targetServerId)
    if player == -1 then
        notify('error', 'Target player is outside your network scope.')
        return
    end
    local ped = GetPlayerPed(player)
    if ped == 0 or not DoesEntityExist(ped) then
        notify('error', 'Target player is unavailable.')
        return
    end
    NetworkSetInSpectatorMode(true, ped)
    compat.spectatingServerId = targetServerId
    compat.spectatingPed = ped
    notify('success', ('Spectating player #%d. Run spectate again to stop.'):format(targetServerId))
end

RegisterNetEvent('cortex-admin:client:setPlayerWaypoint', function(coords)
    if type(coords) ~= 'table' then return end
    local x = finite(coords.x, -20000, 20000)
    local y = finite(coords.y, -20000, 20000)
    if not x or not y then return end
    SetNewWaypoint(x, y)
    notify('success', 'Player waypoint set.')
end)

RegisterNetEvent('cortex-admin:client:setSpectateTarget', function(targetServerId)
    local target = integer(targetServerId, 1, 65535)
    setSpectate(target)
end)

RegisterNetEvent('cortex-admin:client:vmenuIdentifiers', function(payload)
    if type(payload) ~= 'table' or type(payload.identifiers) ~= 'table' then return end
    local identifiers = {}
    for index = 1, math.min(#payload.identifiers, 16) do
        local identifier = trim(payload.identifiers[index], 160)
        if identifier then identifiers[#identifiers + 1] = identifier end
    end
    SendNUIMessage({
        action = 'cortex-admin:setPlayerIdentifiers',
        data = {
            target = integer(payload.target, 1, 65535),
            name = trim(payload.name, 96) or 'Unknown',
            identifiers = identifiers,
        },
    })
    notify('info', (#identifiers > 0 and table.concat(identifiers, ' | ') or 'No durable identifiers found.'))
end)

RegisterNetEvent('cortex-admin:client:receiveVmenuCompatibilityState', function(requestId, payload)
    local pending = pendingCompatibilityRequests[requestId]
    if not pending then return end
    pendingCompatibilityRequests[requestId] = nil
    pending:resolve(payload)
end)

RegisterNetEvent('cortex-admin:client:receiveVmenuConfigDomain', function(requestId, domain, encoded, errorReason)
    local pending = pendingConfigDomainRequests[requestId]
    if not pending then return end
    pendingConfigDomainRequests[requestId] = nil

    domain = trim(domain, 48)
    if pending.domain ~= domain or type(encoded) ~= 'string' or encoded == '' or #encoded > 2 * 1024 * 1024 then
        pending.promise:resolve({ ok = false, error = trim(errorReason, 64) or 'invalid_payload' })
        return
    end

    local ok, decoded = pcall(json.decode, encoded)
    if not ok or type(decoded) ~= 'table' then
        pending.promise:resolve({ ok = false, error = 'invalid_json' })
        return
    end
    pending.promise:resolve({ ok = true, data = decoded })
end)

RegisterNetEvent('cortex-admin:client:receiveBanList', function(requestId, records)
    local pending = pendingBanListRequests[requestId]
    if not pending then return end
    pendingBanListRequests[requestId] = nil
    pending:resolve(type(records) == 'table' and records or {})
end)

RegisterNetEvent('cortex-admin:client:receiveUnbanResult', function(requestId, result)
    local pending = pendingUnbanRequests[requestId]
    if not pending then return end
    pendingUnbanRequests[requestId] = nil
    pending:resolve(type(result) == 'table' and result or { ok = false })
end)

RegisterNetEvent('cortex-admin:client:receiveModelAuthorization', function(requestId, result)
    local pending = pendingModelAuthorizationRequests[requestId]
    if not pending then return end
    pendingModelAuthorizationRequests[requestId] = nil
    pending:resolve(type(result) == 'table' and result or { ok = false, error = 'invalid_response', allowed = {} })
end)

RegisterNetEvent('cortex-admin:client:requestVmenuBanList', function(token)
    token = trim(token, 96)
    if not token or GetResourceState('vMenu') ~= 'started' then return end
    pendingVmenuBanToken = { token = token, expiresAt = GetGameTimer() + 9000 }
    -- Match vMenu's own call shape; the server injects the source Player and
    -- current releases also send the local player handle as the first payload.
    TriggerServerEvent('vMenu:RequestBanList', PlayerId())
end)

RegisterNetEvent('vMenu:SetBanList', function(encoded)
    local pending = pendingVmenuBanToken
    pendingVmenuBanToken = nil
    if not pending or GetGameTimer() > pending.expiresAt then return end
    if type(encoded) ~= 'string' or encoded == '' or #encoded > 2 * 1024 * 1024 then return end
    TriggerServerEvent('cortex-admin:server:importVmenuBanList', pending.token, encoded)
end)

RegisterNetEvent('cortex-admin:client:vmenuBanImportResult', function(result)
    SendNUIMessage({ action = 'cortex-admin:setVmenuBanImportResult', data = type(result) == 'table' and result or {} })
end)

RegisterNetEvent('cortex-admin:client:vmenuNotice', function(kind, message)
    message = trim(message, 320)
    if message then
        if message:sub(1, 21) == 'Private message from ' and state.settings.disablePrivateMessages == true then return end
        notify(kind == 'error' and 'error' or kind == 'success' and 'success' or 'info', message)
    end
end)

RegisterNetEvent('cortex-admin:client:vmenuJoinQuit', function(message)
    if state.toggles['dev.joinQuitNotifications'] == true and type(message) == 'string' then notify('info', message:sub(1, 256)) end
end)

RegisterNetEvent('cortex-admin:client:vmenuDeath', function(message)
    if state.toggles['dev.deathNotifications'] == true and type(message) == 'string' then notify('info', message:sub(1, 256)) end
end)

RegisterNetEvent('cortex-admin:client:applyVmenuWorldState', function(payload)
    if type(payload) ~= 'table' then return end
    if payload.vehicleBlackout ~= nil and SetArtificialLightsStateAffectsVehicles then
        SetArtificialLightsStateAffectsVehicles(payload.vehicleBlackout == true)
    end
    if payload.snowEffects ~= nil then
        local enabled = payload.snowEffects == true
        SetForcePedFootstepsTracks(enabled)
        SetForceVehicleTrails(enabled)
        if SetForceSnowPass then SetForceSnowPass(enabled) end
    end
    if payload.cloudAction == 'remove' then
        ClearCloudHat()
    elseif payload.cloudAction == 'random' then
        local cloudHats = { 'Cirrus', 'Cloudy 01', 'Contrails', 'Horizon', 'Nimbus', 'Puffs', 'Rain', 'Snowy 01', 'Stormy 01', 'Wispy' }
        local hat = cloudHats[math.random(1, #cloudHats)]
        SetCloudHatTransition(hat, 2.5)
    end
end)

local function placementDirection(rotation)
    local pitch = math.rad(rotation.x)
    local yaw = math.rad(rotation.z)
    local horizontal = math.abs(math.cos(pitch))
    return vector3(-math.sin(yaw) * horizontal, math.cos(yaw) * horizontal, math.sin(pitch))
end

local function requestEntitySpawnAuthorization(entityType, modelName)
    local requestId = ('entity:%d:%d'):format(GetGameTimer(), math.random(1000, 9999))
    pendingEntitySpawnRequests[requestId] = {
        entityType = entityType,
        modelName = modelName,
        expiresAt = GetGameTimer() + 5000,
    }
    TriggerServerEvent('cortex-admin:server:requestEntitySpawn', {
        requestId = requestId,
        type = entityType,
        model = modelName,
    })
    SetTimeout(5000, function()
        if pendingEntitySpawnRequests[requestId] then
            pendingEntitySpawnRequests[requestId] = nil
            notify('error', 'Entity spawn authorization timed out.')
        end
    end)
end

local function finishEntityPlacement(duplicate)
    local placement = compat.placement
    if type(placement) ~= 'table' then
        notify('error', 'No entity is currently being positioned.')
        return false
    end
    local entity = placement.entity
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        compat.placement = nil
        notify('error', 'The placement entity no longer exists.')
        return false
    end
    FreezeEntityPosition(entity, false)
    compat.placement = nil
    notify('success', duplicate and 'Entity placed. Starting a duplicate.' or 'Entity position confirmed.')
    if duplicate then
        requestEntitySpawnAuthorization(placement.entityType, placement.modelName)
    end
    return true
end

local function cancelEntityPlacement(silent)
    local placement = compat.placement
    compat.placement = nil
    if type(placement) == 'table' and placement.entity and DoesEntityExist(placement.entity) then
        DeleteEntity(placement.entity)
        for index = #compat.spawnedEntities, 1, -1 do
            if compat.spawnedEntities[index] == placement.entity then table.remove(compat.spawnedEntities, index) end
        end
    end
    if not silent then notify('info', 'Entity placement cancelled.') end
end

local function setPointing(enabled)
    local ped = playerPed()
    enabled = enabled == true
    if enabled then
        RequestAnimDict('anim@mp_point')
        local timeoutAt = GetGameTimer() + 1500
        while not HasAnimDictLoaded('anim@mp_point') and GetGameTimer() < timeoutAt do Wait(0) end
        if not HasAnimDictLoaded('anim@mp_point') then
            notify('error', 'Pointing animation could not be loaded.')
            compat.pointing = false
            return
        end
        TaskMoveNetworkByName(ped, 'task_mp_pointing', 0.5, false, 'anim@mp_point', 24)
        compat.pointing = true
    else
        if IsTaskMoveNetworkActive(ped) then RequestTaskMoveNetworkStateTransition(ped, 'Stop') end
        compat.pointing = false
    end
end

local function beginEntityPlacement(entity, entityType, modelName)
    cancelEntityPlacement(true)
    compat.placement = {
        entity = entity,
        entityType = entityType,
        modelName = modelName,
        distance = 4.0,
        heading = GetEntityHeading(entity),
    }
    FreezeEntityPosition(entity, true)
    Admin.setOpen(false)
    notify('info', 'Move the camera to position. Scroll changes distance, left click confirms, right click cancels, Shift + left click duplicates.')
end

local function clearCompatibilityHuds()
    SendNUIMessage({ action = 'cortex-admin:setVehicleHealthHud', data = { visible = false } })
    SendNUIMessage({ action = 'cortex-admin:setVoiceHud', data = { visible = false } })
    SendNUIMessage({ action = 'cortex-admin:setTimeHud', data = { visible = false } })
    SendNUIMessage({
        action = 'cortex-admin:setCoordHud',
        data = {
            visible = state.toggles['dev.showCoords'] == true,
            showCoordinates = state.toggles['dev.showCoords'] == true,
            showLocation = false,
        },
    })
end

local function cleanupPedEffects(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    SetPedCanBeDraggedOut(ped, true)
    SetPedStayInVehicleWhenJacked(ped, false)
    SetPedHelmet(ped, true)
    SetPedInfiniteAmmoClip(ped, false)
    ClearPedSecondaryTask(ped)
    if SetPedIlluminatedClothingGlowIntensity then SetPedIlluminatedClothingGlowIntensity(ped, 1.0) end
end

local function cleanupTransientCompatibilityState(ped)
    cancelEntityPlacement(true)
    if compat.pointing then setPointing(false) end
    if compat.inspectorEntity ~= 0 and DoesEntityExist(compat.inspectorEntity) then
        SetEntityDrawOutline(compat.inspectorEntity, false)
    end
    compat.inspectorEntity = 0
    clearDimensionOutlines()
    restoreAllVehicleEffects()
    restoreRadarBaseline()
    compat.cameraHeading = nil
    compat.cameraPitch = nil
    cleanupPedEffects(ped)
    restoreParachuteBaseline()
    clearCompatibilityHuds()
end

local executeHandlers = {}
local toggleHandlers = {}
local selectHandlers = {}

local function authorizeParachute(actionId, cacheResult)
    local cached = cacheResult and compat.parachuteAuthorization[actionId] or nil
    if type(cached) == 'table' and GetGameTimer() < (cached.expiresAt or 0) then
        return cached.allowed == true
    end
    if type(Admin.authorizeVmenuModel) ~= 'function' then
        notify('error', 'Server model authorization is unavailable.')
        if cacheResult then compat.parachuteAuthorization[actionId] = { allowed = false, expiresAt = GetGameTimer() + 5000 } end
        return false
    end
    local authorized = Admin.authorizeVmenuModel('weapon', 'gadget_parachute', actionId)
    if cacheResult then
        compat.parachuteAuthorization[actionId] = { allowed = authorized == true, expiresAt = GetGameTimer() + 5000 }
    end
    if not authorized then notify('error', 'Your ACE permissions do not allow the parachute model.') end
    return authorized == true
end

executeHandlers['player.suicide'] = function()
    SetEntityHealth(playerPed(), 0)
end

executeHandlers['player.clearBlood'] = function()
    local ped = playerPed()
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    ClearPedLastDamageBone(ped)
    notify('success', 'Blood and visible damage cleared.')
end

executeHandlers['player.autopilotWaypoint'] = function()
    local vehicle = currentVehicle(true)
    if not vehicle then return end
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then notify('error', 'Set a waypoint first.'); return end
    local coords = GetBlipInfoIdCoord(blip)
    TaskVehicleDriveToCoordLongrange(playerPed(), vehicle, coords.x, coords.y, coords.z, compat.autopilotSpeed, compat.autopilotStyle, 18.0)
    notify('success', 'Autopilot is driving to the waypoint.')
end

executeHandlers['player.autopilotWander'] = function()
    local vehicle = currentVehicle(true)
    if not vehicle then return end
    TaskVehicleDriveWander(playerPed(), vehicle, compat.autopilotSpeed, compat.autopilotStyle)
    notify('success', 'Autopilot wander started.')
end

executeHandlers['player.autopilotStop'] = function()
    ClearPedTasks(playerPed())
    notify('info', 'Autopilot stopped.')
end

executeHandlers['player.scenario'] = function(data)
    local scenario = trim(data and data.scenario, 96)
    if not scenario or not scenario:match('^[%u%d_]+$') then notify('error', 'Enter a valid scenario name.'); return end
    TaskStartScenarioInPlace(playerPed(), scenario, 0, true)
end

executeHandlers['player.stopScenario'] = function()
    ClearPedTasksImmediately(playerPed())
end

executeHandlers['player.applyTattoo'] = function(data)
    local collection = trim(data and data.collection, 96)
    local overlay = trim(data and data.overlay, 96)
    if not collection or not overlay or not collection:match('^[%w_%-]+$') or not overlay:match('^[%w_%-]+$') then
        notify('error', 'Collection and overlay names are required.')
        return
    end
    AddPedDecorationFromHashes(playerPed(), joaat(collection), joaat(overlay))
    notify('success', 'Tattoo or badge applied.')
end

executeHandlers['vehicle.alarm'] = function()
    local vehicle = currentVehicle(false)
    if not vehicle then return end
    local running = IsVehicleAlarmActivated(vehicle)
    SetVehicleAlarm(vehicle, not running)
    if not running then StartVehicleAlarm(vehicle) end
end

executeHandlers['vehicle.cycleSeat'] = function()
    local vehicle = currentVehicle(false)
    if not vehicle then return end
    local ped = playerPed()
    local seats = GetVehicleModelNumberOfSeats(GetEntityModel(vehicle)) - 2
    local current = -2
    for seat = -1, seats do if GetPedInVehicleSeat(vehicle, seat) == ped then current = seat break end end
    for offset = 1, seats + 2 do
        local seat = -1 + ((current + 1 + offset) % (seats + 2))
        if IsVehicleSeatFree(vehicle, seat) then SetPedIntoVehicle(ped, vehicle, seat); return end
    end
    notify('error', 'No free vehicle seat was found.')
end

executeHandlers['vehicle.extras'] = function(data)
    local extra = integer(data and data.extra, 0, 20)
    local vehicle = currentVehicle(false)
    if not extra or not vehicle then notify('error', 'Enter an extra ID from 0 to 20.'); return end
    if not DoesExtraExist(vehicle, extra) then notify('error', 'That extra is unavailable on this vehicle.'); return end
    SetVehicleExtra(vehicle, extra, IsVehicleExtraTurnedOn(vehicle, extra) and 1 or 0)
end

executeHandlers['vehicle.personalSet'] = function()
    local vehicle = currentVehicle(false)
    if not vehicle then return end
    if compat.personalVehicle ~= 0 and compat.personalVehicle ~= vehicle then
        local previous = compat.vehicleBaselines[compat.personalVehicle]
        if previous then restoreVehicleFeatureRecord(previous, 'exclusiveDriver') end
        if compat.personalBlip ~= 0 and DoesBlipExist(compat.personalBlip) then RemoveBlip(compat.personalBlip) end
        compat.personalBlip = 0
    end
    compat.personalVehicle = vehicle
    SetEntityAsMissionEntity(vehicle, true, true)
    if state.toggles['vehicle.personalBlip'] == true and toggleHandlers['vehicle.personalBlip'] then
        toggleHandlers['vehicle.personalBlip'](true)
    end
    notify('success', 'Personal vehicle controls are now linked to this vehicle.')
end

executeHandlers['vehicle.personalKickPassengers'] = function()
    local vehicle = personalVehicle()
    if not vehicle or not requestControl(vehicle) then return end
    local maxPassengers = GetVehicleMaxNumberOfPassengers(vehicle)
    for seat = 0, maxPassengers - 1 do
        local ped = GetPedInVehicleSeat(vehicle, seat)
        if ped ~= 0 then TaskLeaveVehicle(ped, vehicle, 0) end
    end
end

executeHandlers['vehicle.personalLock'] = function()
    local vehicle = personalVehicle(); if not vehicle or not requestControl(vehicle) then return end
    SetVehicleDoorsLocked(vehicle, 2)
end

executeHandlers['vehicle.personalUnlock'] = function()
    local vehicle = personalVehicle(); if not vehicle or not requestControl(vehicle) then return end
    SetVehicleDoorsLocked(vehicle, 1)
end

executeHandlers['vehicle.personalHorn'] = function()
    local vehicle = personalVehicle(); if not vehicle or not requestControl(vehicle) then return end
    StartVehicleHorn(vehicle, 1000, joaat('NORMAL'), false)
end

executeHandlers['vehicle.personalAlarm'] = function()
    local vehicle = personalVehicle(); if not vehicle or not requestControl(vehicle) then return end
    local running = IsVehicleAlarmActivated(vehicle)
    SetVehicleAlarm(vehicle, not running)
    if not running then StartVehicleAlarm(vehicle) end
end

executeHandlers['world.exactTime'] = function(data)
    local hour = integer(data and data.hour, 0, 23)
    local minute = integer(data and data.minute, 0, 59)
    if not hour or not minute then notify('error', 'Hour must be 0-23 and minute 0-59.'); return end
    TriggerServerEvent('cortex-admin:server:setWorldState', { hour = hour, minute = minute })
end

executeHandlers['world.randomClouds'] = function()
    TriggerServerEvent('cortex-admin:server:setVmenuWorldState', { actionId = 'world.randomClouds', cloudAction = 'random' })
end

executeHandlers['world.removeClouds'] = function()
    TriggerServerEvent('cortex-admin:server:setVmenuWorldState', { actionId = 'world.removeClouds', cloudAction = 'remove' })
end

local function eachCarriedWeapon(callback)
    local ped = playerPed()
    for index = 1, #(Config.WeaponList or {}) do
        local name = Config.WeaponList[index]
        local hash = joaat(name)
        if HasPedGotWeapon(ped, hash, false) then callback(ped, hash, name) end
    end
    local importedWeapons = importedDomain('addons').weapons or {}
    for index = 1, #importedWeapons do
        local name = importedWeapons[index]
        if type(name) == 'string' then
            local hash = joaat(name)
            if HasPedGotWeapon(ped, hash, false) then callback(ped, hash, name) end
        end
    end
end

executeHandlers['weapons.setAllAmmo'] = function(data)
    local ammo = integer(data and data.ammo, 0, 9999)
    if not ammo then notify('error', 'Ammo must be between 0 and 9999.'); return end
    eachCarriedWeapon(function(ped, hash) SetPedAmmo(ped, hash, ammo) end)
    notify('success', ('All carried weapon ammo set to %d.'):format(ammo))
end

executeHandlers['weapons.refillAllAmmo'] = function()
    eachCarriedWeapon(function(ped, hash) SetPedAmmo(ped, hash, 9999) end)
    notify('success', 'All carried weapons refilled.')
end

executeHandlers['weapons.removeWeapon'] = function(data)
    local weapon = trim(data and data.weapon, 64)
    if not weapon or not weapon:match('^[%w_%-]+$') then notify('error', 'Enter a valid weapon model.'); return end
    weapon = weapon:lower()
    if weapon:sub(1, 7) ~= 'weapon_' and weapon ~= 'gadget_parachute' then weapon = 'weapon_' .. weapon end
    RemoveWeaponFromPed(playerPed(), joaat(weapon))
    notify('success', ('Removed %s.'):format(weapon))
end

executeHandlers['weapons.primaryParachute'] = function()
    if not authorizeParachute('weapons.primaryParachute', false) then return end
    captureParachuteBaseline()
    local ped = playerPed()
    local chute = joaat('gadget_parachute')
    if HasPedGotWeapon(ped, chute, false) then
        RemoveWeaponFromPed(ped, chute)
        notify('info', 'Primary parachute removed.')
    else
        GiveWeaponToPed(ped, chute, 1, false, false)
        SetPlayerParachuteTintIndex(PlayerId(), preferences.primaryChuteStyle or 0)
        notify('success', 'Primary parachute added.')
    end
end

executeHandlers['weapons.reserveParachute'] = function()
    SetPlayerHasReserveParachute(PlayerId())
    notify('success', 'Reserve parachute added.')
end

local LOADOUTS_KEY = 'cortex-admin_weapon_loadouts'

local function loadLoadouts()
    return loadJsonKvp(LOADOUTS_KEY, {})
end

local function writeLoadouts(loadouts)
    return saveJsonKvp(LOADOUTS_KEY, loadouts)
end

executeHandlers['weapons.renameLoadout'] = function(data)
    local from = trim(data and data.from, 64)
    local to = trim(data and data.to, 64)
    if not from or not to then notify('error', 'Current and new names are required.'); return end
    local loadouts = loadLoadouts()
    if type(loadouts[from]) ~= 'table' then notify('error', 'Source loadout was not found.'); return end
    if loadouts[to] then notify('error', 'A loadout already uses that name.'); return end
    loadouts[to] = loadouts[from]
    loadouts[from] = nil
    writeLoadouts(loadouts)
    if preferences.defaultLoadout == from then preferences.defaultLoadout = to; savePreferences() end
    notify('success', ('Loadout renamed to %s.'):format(to))
end

executeHandlers['weapons.cloneLoadout'] = function(data)
    local from = trim(data and data.from, 64)
    local to = trim(data and data.to, 64)
    if not from or not to then notify('error', 'Source and clone names are required.'); return end
    local loadouts = loadLoadouts()
    if type(loadouts[from]) ~= 'table' then notify('error', 'Source loadout was not found.'); return end
    if loadouts[to] then notify('error', 'A loadout already uses that name.'); return end
    loadouts[to] = clone(loadouts[from])
    writeLoadouts(loadouts)
    notify('success', ('Loadout cloned as %s.'):format(to))
end

executeHandlers['weapons.defaultLoadout'] = function(data)
    local name = trim(data and data.name, 64)
    local loadouts = loadLoadouts()
    if not name or type(loadouts[name]) ~= 'table' then notify('error', 'Loadout was not found.'); return end
    preferences.defaultLoadout = name
    savePreferences()
    notify('success', ('Default loadout set to %s.'):format(name))
end

executeHandlers['weapons.replaceLoadout'] = function(data)
    local name = trim(data and data.name, 64)
    local loadouts = loadLoadouts()
    if not name or type(loadouts[name]) ~= 'table' then notify('error', 'Loadout was not found.'); return end
    if type(Admin.saveWeaponLoadout) ~= 'function' then notify('error', 'Loadout capture is unavailable.'); return end
    Admin.saveWeaponLoadout(name)
end

executeHandlers['dev.spawnEntity'] = function(data)
    local entityType = trim(data and data.type, 16)
    local modelName = trim(data and data.model, 64)
    if not entityType or not modelName or not modelName:match('^[%w_%-]+$') then notify('error', 'Enter a valid type and model.'); return end
    entityType = entityType:lower()
    if entityType ~= 'vehicle' and entityType ~= 'ped' and entityType ~= 'object' then notify('error', 'Type must be object, ped or vehicle.'); return end
    requestEntitySpawnAuthorization(entityType, modelName)
end

RegisterNetEvent('cortex-admin:client:authorizedEntitySpawn', function(requestId, entityType, modelName)
    local pending = nil
    if type(requestId) == 'string' then
        pending = pendingEntitySpawnRequests[requestId]
        pendingEntitySpawnRequests[requestId] = nil
    end
    entityType = trim(entityType, 16)
    modelName = trim(modelName, 64)
    if not pending or GetGameTimer() > pending.expiresAt or pending.entityType ~= entityType
        or pending.modelName ~= modelName or not entityType or not modelName
        or not modelName:match('^[%w_%-]+$') then return end
    entityType = entityType:lower()
    if entityType ~= 'vehicle' and entityType ~= 'ped' and entityType ~= 'object' then return end
    local model = joaat(modelName)
    if not IsModelInCdimage(model) or not IsModelValid(model) then notify('error', 'Model is invalid.'); return end
    if entityType == 'vehicle' and not IsModelAVehicle(model) then notify('error', 'That model is not a vehicle.'); return end
    if entityType == 'ped' and not IsModelAPed(model) then notify('error', 'That model is not a ped.'); return end
    if not exports['cortex-lib']:requestModel(model, 5000) then notify('error', 'Model failed to load.'); return end
    local ped = playerPed()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 3.0, 0.0)
    local heading = GetEntityHeading(ped)
    local entity
    if entityType == 'vehicle' then entity = CreateVehicle(model, coords.x, coords.y, coords.z, heading, false, false)
    elseif entityType == 'ped' then entity = CreatePed(4, model, coords.x, coords.y, coords.z, heading, false, false)
    else entity = CreateObject(model, coords.x, coords.y, coords.z, false, false, false) end
    SetModelAsNoLongerNeeded(model)
    if not entity or entity == 0 then notify('error', 'Entity creation failed.'); return end
    SetEntityAsMissionEntity(entity, true, true)
    if entityType == 'object' then PlaceObjectOnGroundProperly(entity) end
    compat.spawnedEntities[#compat.spawnedEntities + 1] = entity
    beginEntityPlacement(entity, entityType, modelName)
end)

RegisterNetEvent('cortex-admin:client:entitySpawnRejected', function(requestId, reason)
    if type(requestId) ~= 'string' or not pendingEntitySpawnRequests[requestId] then return end
    pendingEntitySpawnRequests[requestId] = nil
    local messages = {
        rate_limited = 'Entity spawn requests are being sent too quickly.',
        forbidden = 'You do not have permission to spawn entities.',
        invalid_payload = 'The entity spawn request was malformed.',
        invalid_model = 'Entity type or model is invalid.',
        model_forbidden = 'Your ACE permissions do not allow that whitelisted model.',
    }
    notify('error', messages[reason] or 'The entity model was not authorized.')
end)

executeHandlers['dev.clearSpawnedEntities'] = function()
    compat.placement = nil
    local removed = 0
    for index = #compat.spawnedEntities, 1, -1 do
        local entity = compat.spawnedEntities[index]
        if entity and DoesEntityExist(entity) and requestControl(entity, 350) then DeleteEntity(entity); removed = removed + 1 end
        table.remove(compat.spawnedEntities, index)
    end
    notify('success', ('Removed %d spawned entities.'):format(removed))
end

executeHandlers['dev.confirmEntityPlacement'] = function()
    finishEntityPlacement(false)
end

executeHandlers['dev.cancelEntityPlacement'] = function()
    cancelEntityPlacement(false)
end

executeHandlers['dev.duplicateEntityPlacement'] = function()
    finishEntityPlacement(true)
end

executeHandlers['dev.timecycle'] = function(data)
    local name = trim(data and data.name, 96)
    local strength = finite(data and data.strength, 0.0, 1.0)
    if not name or not strength then notify('error', 'Modifier and strength from 0 to 1 are required.'); return end
    SetTimecycleModifier(name)
    SetTimecycleModifierStrength(strength)
end

executeHandlers['dev.clearTimecycle'] = function()
    ClearTimecycleModifier()
end

executeHandlers['options.disconnect'] = function()
    Admin.setOpen(false)
    ExecuteCommand('disconnect')
end

executeHandlers['options.quitSession'] = function()
    if not NetworkIsSessionActive() then notify('error', 'You are not currently in a network session.'); return end
    if NetworkIsHost() then notify('error', 'The network host cannot quit the session without disrupting other players.'); return end
    Admin.setOpen(false)
    NetworkSessionEnd(true, true)
end

executeHandlers['options.rejoinSession'] = function()
    if NetworkIsSessionActive() then notify('error', 'You are already connected to a network session.'); return end
    NetworkSessionHost(-1, 32, false)
    notify('info', 'Attempting to re-join the network session.')
end

executeHandlers['options.quitGame'] = function()
    Admin.setOpen(false)
    notify('info', 'The game will exit in 5 seconds.')
    SetTimeout(5000, function()
        ForceSocialClubUpdate()
    end)
end

executeHandlers['voice.channel'] = function(data)
    local channel = integer(data and data.channel, 0, 65535)
    if not channel then notify('error', 'Channel must be between 0 and 65535.'); return end
    preferences.voiceChannel = channel
    savePreferences()
    if channel == 0 then NetworkClearVoiceChannel() else NetworkSetVoiceChannel(channel) end
end

toggleHandlers['player.stayInVehicle'] = function(enabled)
    local ped = playerPed()
    SetPedCanBeDraggedOut(ped, not enabled)
    SetPedStayInVehicleWhenJacked(ped, enabled)
end

toggleHandlers['vehicle.freeze'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('freeze'); return end
    local vehicle = currentVehicle(false)
    if vehicle and markVehicleFeature(vehicle, 'freeze') then FreezeEntityPosition(vehicle, true) end
end

toggleHandlers['vehicle.invisible'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('invisible'); return end
    local vehicle = currentVehicle(false)
    if vehicle and markVehicleFeature(vehicle, 'invisible') then SetEntityVisible(vehicle, false, false) end
end

toggleHandlers['vehicle.engineAlwaysOn'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('engineAlwaysOn'); return end
    local vehicle = GetVehiclePedIsIn(playerPed(), false)
    if vehicle ~= 0 then markVehicleFeature(vehicle, 'engineAlwaysOn') end
end

toggleHandlers['vehicle.noSiren'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('noSiren'); return end
    local vehicle = currentVehicle(false)
    if vehicle and markVehicleFeature(vehicle, 'noSiren') then SetVehicleHasMutedSirens(vehicle, true) end
end

toggleHandlers['vehicle.noHelmet'] = function(enabled)
    SetPedHelmet(playerPed(), not enabled)
    if enabled then RemovePedHelmet(playerPed(), true) end
end

toggleHandlers['vehicle.anchorBoat'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('anchorBoat'); return end
    local vehicle = currentVehicle(false)
    if not vehicle or not IsThisModelABoat(GetEntityModel(vehicle))
        or CanAnchorBoatHere and not CanAnchorBoatHere(vehicle) then
        notify('error', 'This boat cannot be anchored here.')
        return
    end
    if markVehicleFeature(vehicle, 'anchorBoat') then
        SetBoatAnchor(vehicle, true)
        SetBoatFrozenWhenAnchored(vehicle, true)
        SetForcedBoatLocationWhenAnchored(vehicle, true)
    end
end

toggleHandlers['vehicle.strongWheels'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('strongWheels'); return end
    local vehicle = currentVehicle(false)
    if vehicle and markVehicleFeature(vehicle, 'strongWheels') then SetVehicleWheelsCanBreak(vehicle, false) end
end

toggleHandlers['vehicle.preventEngineDamage'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('preventEngineDamage'); return end
    local vehicle = currentVehicle(false)
    if vehicle and markVehicleFeature(vehicle, 'preventEngineDamage') and SetVehicleEngineCanDegrade then
        SetVehicleEngineCanDegrade(vehicle, false)
    end
end

toggleHandlers['vehicle.preventVisualDamage'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('preventVisualDamage'); return end
    local vehicle = currentVehicle(false)
    if vehicle and markVehicleFeature(vehicle, 'preventVisualDamage') then SetVehicleCanBeVisiblyDamaged(vehicle, false) end
end

toggleHandlers['vehicle.preventRampDamage'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('preventRampDamage'); return end
    local vehicle = currentVehicle(false)
    if vehicle and markVehicleFeature(vehicle, 'preventRampDamage') and SetRampVehicleReceivesRampDamage then
        SetRampVehicleReceivesRampDamage(vehicle, false)
    end
end

toggleHandlers['vehicle.bulletproofTyres'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('bulletproofTyres'); return end
    local vehicle = currentVehicle(false)
    if vehicle and markVehicleFeature(vehicle, 'bulletproofTyres') then SetVehicleTyresCanBurst(vehicle, false) end
end

toggleHandlers['vehicle.lowGripTyres'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('lowGrip'); return end
    local vehicle = currentVehicle(false)
    if vehicle and markVehicleFeature(vehicle, 'lowGrip') then SetVehicleReduceGrip(vehicle, true) end
end

toggleHandlers['vehicle.torqueEnabled'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('torque'); return end
    local vehicle = GetVehiclePedIsIn(playerPed(), false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == playerPed() and markVehicleFeature(vehicle, 'torque') then
        SetVehicleEngineTorqueMultiplier(vehicle, preferences.torqueMultiplier or 1.0)
    end
end

toggleHandlers['vehicle.powerEnabled'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('power'); return end
    local vehicle = GetVehiclePedIsIn(playerPed(), false)
    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == playerPed() and markVehicleFeature(vehicle, 'power') then
        SetVehicleEnginePowerMultiplier(vehicle, preferences.powerMultiplier or 1.0)
    end
end

toggleHandlers['vehicle.defaultRadioEnabled'] = function(enabled)
    compat.lastRadioVehicle = 0
    if not enabled then restoreTrackedVehicleFeature('defaultRadio') end
end

toggleHandlers['vehicle.deleteRemovedDoors'] = function() end

toggleHandlers['vehicle.flashHighbeams'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('fullbeam') end
end

toggleHandlers['weapons.noReload'] = function(enabled)
    SetPedInfiniteAmmoClip(playerPed(), enabled)
end

toggleHandlers['dev.driftMode'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('drift') end
end

toggleHandlers['vehicle.personalEngine'] = function(enabled)
    local vehicle = personalVehicle(); if vehicle and requestControl(vehicle) then SetVehicleEngineOn(vehicle, enabled, true, true) end
end

toggleHandlers['vehicle.personalBlip'] = function(enabled)
    local vehicle = personalVehicle(); if not vehicle then return end
    if enabled then
        if compat.personalBlip == 0 or not DoesBlipExist(compat.personalBlip) then
            compat.personalBlip = AddBlipForEntity(vehicle)
            SetBlipSprite(compat.personalBlip, 225)
            SetBlipColour(compat.personalBlip, 3)
            BeginTextCommandSetBlipName('STRING'); AddTextComponentString('Personal Vehicle'); EndTextCommandSetBlipName(compat.personalBlip)
        end
    elseif compat.personalBlip ~= 0 and DoesBlipExist(compat.personalBlip) then
        RemoveBlip(compat.personalBlip); compat.personalBlip = 0
    end
end

toggleHandlers['vehicle.personalExclusive'] = function(enabled)
    if not enabled then restoreTrackedVehicleFeature('exclusiveDriver'); return end
    local vehicle = personalVehicle()
    if not vehicle or not requestControl(vehicle) or not SetVehicleExclusiveDriver_2 then return end
    if markVehicleFeature(vehicle, 'exclusiveDriver') then SetVehicleExclusiveDriver_2(vehicle, playerPed(), 1) end
end

toggleHandlers['dev.locationBlips'] = function()
    refreshLocationBlips()
end

toggleHandlers['vehicle.showHealth'] = function(enabled)
    if not enabled then SendNUIMessage({ action = 'cortex-admin:setVehicleHealthHud', data = { visible = false } }) end
end

toggleHandlers['dev.showTime'] = function(enabled)
    if not enabled then SendNUIMessage({ action = 'cortex-admin:setTimeHud', data = { visible = false } }) end
end

toggleHandlers['voice.showSpeaker'] = function(enabled)
    if not enabled and state.toggles['voice.showStatus'] ~= true then
        SendNUIMessage({ action = 'cortex-admin:setVoiceHud', data = { visible = false } })
    end
end

toggleHandlers['voice.showStatus'] = function(enabled)
    if not enabled and state.toggles['voice.showSpeaker'] ~= true then
        SendNUIMessage({ action = 'cortex-admin:setVoiceHud', data = { visible = false } })
    end
end

toggleHandlers['world.dynamicWeather'] = function(enabled)
    TriggerServerEvent('cortex-admin:server:setVmenuWorldState', { actionId = 'world.dynamicWeather', dynamicWeather = enabled })
end

toggleHandlers['world.vehicleBlackout'] = function(enabled)
    TriggerServerEvent('cortex-admin:server:setVmenuWorldState', { actionId = 'world.vehicleBlackout', vehicleBlackout = enabled })
end

toggleHandlers['world.snowEffects'] = function(enabled)
    TriggerServerEvent('cortex-admin:server:setVmenuWorldState', { actionId = 'world.snowEffects', snowEffects = enabled })
end

toggleHandlers['dev.hideRadar'] = function(enabled)
    if enabled then
        captureRadarBaseline()
        DisplayRadar(false)
    else
        restoreRadarBaseline()
    end
end

toggleHandlers['dev.locationDisplay'] = function(enabled)
    state.coordHudDirty = true
    SendNUIMessage({
        action = 'cortex-admin:setCoordHud',
        data = {
            visible = enabled == true or state.toggles['dev.showCoords'] == true,
            showCoordinates = state.toggles['dev.showCoords'] == true,
            showLocation = enabled == true,
        },
    })
end

toggleHandlers['dev.lockCameraHorizontal'] = function(enabled)
    compat.cameraHeading = enabled and GetGameplayCamRelativeHeading() or nil
end

toggleHandlers['dev.lockCameraVertical'] = function(enabled)
    compat.cameraPitch = enabled and GetGameplayCamRelativePitch() or nil
end

for _, dimensionToggle in ipairs({
    'dev.vehicleDimensions', 'dev.propDimensions', 'dev.pedDimensions',
    'dev.entityHandles', 'dev.entityModels', 'dev.entityOwners',
}) do
    toggleHandlers[dimensionToggle] = function()
        if state.toggles['dev.vehicleDimensions'] ~= true
            and state.toggles['dev.propDimensions'] ~= true
            and state.toggles['dev.pedDimensions'] ~= true then
            clearDimensionOutlines()
        end
    end
end

toggleHandlers['voice.enabled'] = function(enabled)
    NetworkSetVoiceActive(enabled)
end

selectHandlers['player.setBloodLevel'] = function(value)
    local level = integer(value, 0, 4)
    if not level then return end
    local ped = playerPed()
    ClearPedBloodDamage(ped)
    ResetPedVisibleDamage(ped)
    if level > 0 then
        local packs = { 'BigHitByVehicle', 'SCR_Torture', 'Explosion_Med', 'BigRunOverByVehicle' }
        ApplyPedDamagePack(ped, packs[level], 0.0, level * 0.35)
    end
end

selectHandlers['player.armorType'] = function(value)
    local amount = integer(value, 0, 100)
    if amount == nil then return end
    SetPedArmour(playerPed(), amount)
    notify('success', ('Armor set to %d.'):format(amount))
end

selectHandlers['player.illuminatedClothing'] = function(value)
    local style = integer(value, 0, 3)
    if style == nil then return end
    preferences.clothingGlowStyle = style
    compat.clothingGlowTouched = true
    savePreferences()
end

selectHandlers['player.drivingStyle'] = function(value)
    compat.autopilotStyle = integer(value, 0, 2147483647) or compat.autopilotStyle
    savePreferences()
end

selectHandlers['player.drivingSpeed'] = function(value)
    compat.autopilotSpeed = finite(value, 1.0, 100.0) or compat.autopilotSpeed
    savePreferences()
end

selectHandlers['player.walkingStyle'] = function(value)
    if type(value) == 'string' then applyWalkingStyle(value) end
end

selectHandlers['player.facialExpression'] = function(value)
    local expression = trim(value, 64)
    if expression then SetFacialIdleAnimOverride(playerPed(), expression, nil) end
end

selectHandlers['vehicle.lights'] = function(value)
    local vehicle = currentVehicle(false); if vehicle then setVehicleLights(vehicle, value) end
end

selectHandlers['vehicle.doors'] = function(value)
    local vehicle = currentVehicle(false); if vehicle then applyDoors(vehicle, value) end
end

selectHandlers['vehicle.windows'] = function(value)
    local vehicle = currentVehicle(false); if vehicle then applyWindows(vehicle, value) end
end

selectHandlers['vehicle.tyres'] = function(value)
    local vehicle = currentVehicle(false); if vehicle then applyTyres(vehicle, value) end
end

selectHandlers['vehicle.torqueMultiplier'] = function(value)
    local multiplier = finite(value, 1.0, 10.0)
    if not multiplier then return end
    preferences.torqueMultiplier = multiplier
    state.vehicleTorqueMultiplier = multiplier
    savePreferences()
    local vehicle = GetVehiclePedIsIn(playerPed(), false)
    if state.toggles['vehicle.torqueEnabled'] == true and vehicle ~= 0
        and GetPedInVehicleSeat(vehicle, -1) == playerPed() and markVehicleFeature(vehicle, 'torque') then
        SetVehicleEngineTorqueMultiplier(vehicle, multiplier)
    end
    notify('success', ('Torque multiplier set to %.1fx.'):format(multiplier))
end

selectHandlers['vehicle.powerMultiplier'] = function(value)
    local multiplier = finite(value, 1.0, 10.0)
    if not multiplier then return end
    preferences.powerMultiplier = multiplier
    state.vehiclePowerMultiplier = multiplier
    savePreferences()
    local vehicle = GetVehiclePedIsIn(playerPed(), false)
    if state.toggles['vehicle.powerEnabled'] == true and vehicle ~= 0
        and GetPedInVehicleSeat(vehicle, -1) == playerPed() and markVehicleFeature(vehicle, 'power') then
        SetVehicleEnginePowerMultiplier(vehicle, multiplier)
    end
    notify('success', ('Power multiplier set to %.1fx.'):format(multiplier))
end

selectHandlers['vehicle.dirtLevel'] = function(value)
    local vehicle = currentVehicle(false); local level = finite(value, 0, 15)
    if vehicle and level then SetVehicleDirtLevel(vehicle, level) end
end

selectHandlers['vehicle.defaultRadioStation'] = function(value)
    local station = trim(value, 64)
    if not station or (station ~= 'OFF' and not station:match('^RADIO_[%w_]+$')) then return end
    preferences.defaultRadioStation = station
    savePreferences()
    local vehicle = GetVehiclePedIsIn(playerPed(), false)
    if vehicle ~= 0 and state.toggles['vehicle.defaultRadioEnabled'] then
        if markVehicleFeature(vehicle, 'defaultRadio') then
            SetVehRadioStation(vehicle, station)
            SetVehicleRadioEnabled(vehicle, station ~= 'OFF')
            compat.lastRadioVehicle = vehicle
        end
    end
end

selectHandlers['vehicle.plateType'] = function(value)
    local plate = integer(value, 0, 12)
    local vehicle = currentVehicle(false)
    if plate ~= nil and vehicle then SetVehicleNumberPlateTextIndex(vehicle, plate) end
end

selectHandlers['vehicle.enveffScale'] = function(value)
    local scale = finite(value, 0.0, 1.0)
    local vehicle = currentVehicle(false)
    if scale and vehicle then SetVehicleEnveffScale(vehicle, scale) end
end

selectHandlers['vehicle.personalLights'] = function(value)
    local vehicle = personalVehicle(); if vehicle and requestControl(vehicle) then setVehicleLights(vehicle, value) end
end

selectHandlers['vehicle.personalStance'] = function(value)
    local vehicle = personalVehicle(); if vehicle and requestControl(vehicle) then SetReduceDriftVehicleSuspension(vehicle, value == true) end
end

selectHandlers['vehicle.personalDoors'] = function(value)
    local vehicle = personalVehicle(); if vehicle and requestControl(vehicle) then applyDoors(vehicle, value) end
end

selectHandlers['weapons.reserveChuteStyle'] = function(value)
    local tint = integer(value, 0, 13)
    if tint == nil then return end
    captureParachuteBaseline()
    SetPlayerReserveParachuteTintIndex(PlayerId(), tint)
end

selectHandlers['weapons.primaryChuteStyle'] = function(value)
    local tint = integer(value, 0, 13)
    if tint == nil then return end
    captureParachuteBaseline()
    preferences.primaryChuteStyle = tint
    savePreferences()
    SetPlayerParachuteTintIndex(PlayerId(), tint)
end

selectHandlers['weapons.parachuteSmoke'] = function(value)
    if type(value) ~= 'string' then return end
    captureParachuteBaseline()
    compat.parachuteSmokeTouched = true
    if value == 'off' then
        SetPlayerCanLeaveParachuteSmokeTrail(PlayerId(), false)
        return
    end
    local r, g, b = value:match('^(%d+),(%d+),(%d+)$')
    r, g, b = integer(r, 0, 255), integer(g, 0, 255), integer(b, 0, 255)
    if r and g and b then
        SetPlayerParachuteSmokeTrailColor(PlayerId(), r, g, b)
        SetPlayerCanLeaveParachuteSmokeTrail(PlayerId(), true)
    end
end

selectHandlers['dev.dimensionRadius'] = function(value)
    local radius = finite(value, 10.0, 200.0)
    if not radius then return end
    preferences.dimensionRadius = radius
    savePreferences()
end

selectHandlers['voice.proximity'] = function(value)
    local proximity = finite(value, 0.5, 10000.0)
    if proximity then preferences.voiceProximity = proximity; savePreferences(); NetworkSetTalkerProximity(proximity) end
end

local baseExecute = Admin.executeAction
Admin.executeAction = function(actionId, data)
    local handler = executeHandlers[actionId]
    if handler then return handler(type(data) == 'table' and data or {}) end
    return baseExecute(actionId, data)
end

local baseToggle = Admin.toggleAction
Admin.toggleAction = function(actionId, enabled)
    local handler = toggleHandlers[actionId]
    if handler or persistentToggleIds[actionId] or actionId:sub(1, 6) == 'voice.' then
        setCompatToggle(actionId, enabled)
        if handler then handler(enabled == true) end
        return
    end
    return baseToggle(actionId, enabled)
end

local baseSelect = Admin.selectAction
Admin.selectAction = function(actionId, value)
    local handler = selectHandlers[actionId]
    if handler then return handler(value) end
    return baseSelect(actionId, value)
end

local compatCommand = Config.VmenuCompatibility and Config.VmenuCompatibility.commandAlias or 'vmenu'
if compatCommand ~= Config.Command then
    RegisterCommand(compatCommand, function()
        Admin.setOpen(not state.open)
    end, false)
    RegisterKeyMapping(compatCommand, 'Open Cortex Admin (vMenu compatible)', 'keyboard', Config.VmenuCompatibility.keybind or 'M')
end

RegisterCommand('cortex_admin_tp_waypoint', function()
    if state.toggles['options.teleportWaypointKey'] == true and state.allowed['teleport.waypoint'] == true then
        Admin.executeAction('teleport.waypoint', {})
    end
end, false)
RegisterKeyMapping('cortex_admin_tp_waypoint', 'Cortex Admin: Teleport to waypoint', 'keyboard', Config.VmenuCompatibility.waypointKeybind or 'F7')

RegisterCommand('cortex_admin_toggle_radar', function()
    if state.settings.minimapControls ~= true or state.allowed['options.minimapControls'] == false then return end
    compat.radarExpanded = not compat.radarExpanded
    SetRadarBigmapEnabled(compat.radarExpanded, false)
end, false)
RegisterKeyMapping('cortex_admin_toggle_radar', 'Cortex Admin: Toggle expanded radar', 'keyboard', 'Z')

RegisterCommand('cortex_admin_point', function()
    if state.settings.fingerPointControls ~= true or state.allowed['options.fingerPointControls'] == false then return end
    setPointing(not compat.pointing)
end, false)
RegisterKeyMapping('cortex_admin_point', 'Cortex Admin: Toggle finger point', 'keyboard', 'B')

RegisterCommand('cortex_admin_record', function()
    if state.settings.recordingControls ~= true then return end
    if IsRecording() then Admin.executeAction('dev.stopRecording', {}) else Admin.executeAction('dev.startRecording', {}) end
end, false)
RegisterKeyMapping('cortex_admin_record', 'Cortex Admin: Start or save recording', 'keyboard', 'F1')

RegisterCommand('cortex_admin_discard_recording', function()
    if state.settings.recordingControls == true and IsRecording() then Admin.executeAction('dev.discardRecording', {}) end
end, false)
RegisterKeyMapping('cortex_admin_discard_recording', 'Cortex Admin: Discard recording', 'keyboard', 'F3')

CreateThread(function()
    local nextSlow = 0
    local nextHud = 0
    local nextParachuteCheck = 0
    local nextLocationHud = 0
    local nextDimensionScan = 0
    local lastHealthPayload = ''
    local lastVoicePayload = ''

    while true do
        local toggles = state.toggles or {}
        local active = toggles['player.stayInVehicle'] or toggles['vehicle.freeze'] or toggles['vehicle.invisible']
            or toggles['vehicle.engineAlwaysOn'] or toggles['vehicle.noSiren']
            or toggles['vehicle.noHelmet'] or toggles['vehicle.anchorBoat'] or toggles['vehicle.flashHighbeams']
            or toggles['vehicle.infiniteFuel'] or toggles['vehicle.showHealth'] or toggles['vehicle.autoRepair']
            or toggles['vehicle.strongWheels'] or toggles['vehicle.preventEngineDamage'] or toggles['vehicle.preventVisualDamage']
            or toggles['vehicle.preventRampDamage'] or toggles['vehicle.bulletproofTyres'] or toggles['vehicle.lowGripTyres']
            or toggles['vehicle.torqueEnabled'] or toggles['vehicle.powerEnabled'] or toggles['vehicle.defaultRadioEnabled']
            or toggles['vehicle.personalExclusive'] or toggles['weapons.noReload'] or toggles['weapons.unlimitedParachutes']
            or toggles['weapons.autoEquipParachute'] or toggles['weapons.restoreLoadoutOnRespawn']
            or toggles['dev.showTime'] or toggles['dev.overheadNames'] or toggles['dev.deathNotifications']
            or toggles['dev.driftMode'] or toggles['dev.entityInspector'] or toggles['dev.hideRadar'] or toggles['dev.locationDisplay']
            or toggles['dev.vehicleDimensions'] or toggles['dev.propDimensions'] or toggles['dev.pedDimensions']
            or toggles['dev.lockCameraHorizontal'] or toggles['dev.lockCameraVertical']
            or toggles['voice.showSpeaker'] or toggles['voice.showStatus'] or compat.spectatingServerId ~= nil
            or compat.placement ~= nil or compat.pointing == true or compat.clothingGlowTouched == true

        if not active then
            Wait(1000)
        else
            local now = GetGameTimer()
            local ped = playerPed()
            local vehicle = GetVehiclePedIsIn(ped, false)

            if compat.lastPed ~= 0 and compat.lastPed ~= ped then
                cleanupPedEffects(compat.lastPed)
                compat.pointing = false
                restoreParachuteBaseline()
            end
            compat.lastPed = ped

            repeat
            local dead = IsEntityDead(ped)
            if dead then
                if not compat.deathCleanupApplied then
                    compat.deathCleanupApplied = true
                    compat.lastDeathReported = true
                    cleanupTransientCompatibilityState(ped)
                    if toggles['dev.deathNotifications'] then TriggerServerEvent('cortex-admin:server:reportDeath') end
                end
                Wait(250)
                break
            elseif compat.deathCleanupApplied then
                compat.deathCleanupApplied = false
                compat.lastDeathReported = false
                if toggles['weapons.restoreLoadoutOnRespawn'] and type(preferences.defaultLoadout) == 'string' and preferences.defaultLoadout ~= '' then
                    Admin.loadWeaponLoadout(preferences.defaultLoadout)
                end
            end

            setCurrentEffectVehicle(vehicle)

            if toggles['player.stayInVehicle'] then
                SetPedCanBeDraggedOut(ped, false)
                SetPedStayInVehicleWhenJacked(ped, true)
            end

            if vehicle ~= 0 then compat.lastVehicle = vehicle end

            if now >= nextSlow then
                if compat.spectatingServerId then
                    local targetPlayer = GetPlayerFromServerId(compat.spectatingServerId)
                    local targetPed = targetPlayer ~= -1 and GetPlayerPed(targetPlayer) or 0
                    if targetPlayer == -1 or targetPed == 0 or not DoesEntityExist(targetPed) then
                        setSpectate(nil)
                        notify('error', 'Spectate target is no longer available.')
                    elseif targetPed ~= compat.spectatingPed then
                        NetworkSetInSpectatorMode(false, compat.spectatingPed)
                        NetworkSetInSpectatorMode(true, targetPed)
                        compat.spectatingPed = targetPed
                    end
                end
                if toggles['vehicle.engineAlwaysOn'] and compat.lastVehicle ~= 0 and DoesEntityExist(compat.lastVehicle) and not IsPedInAnyVehicle(ped, false) then
                    SetVehicleEngineOn(compat.lastVehicle, true, true, true)
                end
                if vehicle ~= 0 then
                    if toggles['vehicle.engineAlwaysOn'] then markVehicleFeature(vehicle, 'engineAlwaysOn') end
                    if toggles['vehicle.freeze'] and markVehicleFeature(vehicle, 'freeze') then FreezeEntityPosition(vehicle, true) end
                    if toggles['vehicle.invisible'] and markVehicleFeature(vehicle, 'invisible') then SetEntityVisible(vehicle, false, false) end
                    if toggles['vehicle.noSiren'] and markVehicleFeature(vehicle, 'noSiren') then SetVehicleHasMutedSirens(vehicle, true) end
                    if toggles['vehicle.noHelmet'] then SetPedHelmet(ped, false); RemovePedHelmet(ped, true) end
                    if toggles['vehicle.anchorBoat'] and IsThisModelABoat(GetEntityModel(vehicle))
                        and (not CanAnchorBoatHere or CanAnchorBoatHere(vehicle)) and markVehicleFeature(vehicle, 'anchorBoat') then
                        SetBoatAnchor(vehicle, true)
                        SetBoatFrozenWhenAnchored(vehicle, true)
                        SetForcedBoatLocationWhenAnchored(vehicle, true)
                    end
                    if toggles['vehicle.infiniteFuel'] then
                        local maxFuel = GetVehicleHandlingFloat(vehicle, 'CHandlingData', 'fPetrolTankVolume')
                        SetVehicleFuelLevel(vehicle, math.max(maxFuel or 65.0, 5.0))
                    end
                    if toggles['vehicle.autoRepair'] and IsVehicleDamaged(vehicle) then SetVehicleFixed(vehicle) end
                    if toggles['vehicle.strongWheels'] and markVehicleFeature(vehicle, 'strongWheels') then SetVehicleWheelsCanBreak(vehicle, false) end
                    if toggles['vehicle.bulletproofTyres'] and markVehicleFeature(vehicle, 'bulletproofTyres') then SetVehicleTyresCanBurst(vehicle, false) end
                    if toggles['vehicle.lowGripTyres'] and markVehicleFeature(vehicle, 'lowGrip') then SetVehicleReduceGrip(vehicle, true) end
                    if toggles['vehicle.preventEngineDamage'] and markVehicleFeature(vehicle, 'preventEngineDamage') then
                        if SetVehicleEngineCanDegrade then SetVehicleEngineCanDegrade(vehicle, false) end
                        if GetVehicleEngineHealth(vehicle) < 1000.0 then SetVehicleEngineHealth(vehicle, 1000.0) end
                    end
                    if toggles['vehicle.preventVisualDamage'] and markVehicleFeature(vehicle, 'preventVisualDamage') then
                        SetVehicleCanBeVisiblyDamaged(vehicle, false)
                        RemoveDecalsFromVehicle(vehicle)
                    end
                    if toggles['vehicle.preventRampDamage'] and SetRampVehicleReceivesRampDamage
                        and markVehicleFeature(vehicle, 'preventRampDamage') then
                        SetRampVehicleReceivesRampDamage(vehicle, false)
                    end
                    if toggles['vehicle.powerEnabled'] and GetPedInVehicleSeat(vehicle, -1) == ped
                        and markVehicleFeature(vehicle, 'power') then
                        SetVehicleEnginePowerMultiplier(vehicle, preferences.powerMultiplier or 1.0)
                    end
                    if toggles['vehicle.defaultRadioEnabled'] and vehicle ~= compat.lastRadioVehicle then
                        if markVehicleFeature(vehicle, 'defaultRadio') then
                            SetVehRadioStation(vehicle, preferences.defaultRadioStation or 'OFF')
                            SetVehicleRadioEnabled(vehicle, preferences.defaultRadioStation ~= 'OFF')
                            compat.lastRadioVehicle = vehicle
                        end
                    end
                end
                if toggles['vehicle.personalExclusive'] and compat.personalVehicle ~= 0 and DoesEntityExist(compat.personalVehicle) and SetVehicleExclusiveDriver_2 then
                    if markVehicleFeature(compat.personalVehicle, 'exclusiveDriver') then
                        SetVehicleExclusiveDriver_2(compat.personalVehicle, ped, 1)
                    end
                end
                nextSlow = now + 350
            end

            if toggles['vehicle.torqueEnabled'] and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
                and markVehicleFeature(vehicle, 'torque') then
                SetVehicleEngineTorqueMultiplier(vehicle, preferences.torqueMultiplier or 1.0)
            end

            if toggles['vehicle.flashHighbeams'] and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
                and markVehicleFeature(vehicle, 'fullbeam') then
                SetVehicleFullbeam(vehicle, IsControlPressed(0, 86))
            end

            if toggles['dev.driftMode'] and vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                if IsControlPressed(0, 21) then
                    if markVehicleFeature(vehicle, 'drift') then SetVehicleReduceGrip(vehicle, true) end
                else
                    local record = compat.vehicleBaselines[vehicle]
                    if record and record.features.drift then restoreVehicleFeatureRecord(record, 'drift') end
                end
            end

            if toggles['dev.hideRadar'] then captureRadarBaseline(); DisplayRadar(false) end
            if toggles['dev.lockCameraHorizontal'] then
                compat.cameraHeading = compat.cameraHeading or GetGameplayCamRelativeHeading()
                SetGameplayCamRelativeHeading(compat.cameraHeading)
            end
            if toggles['dev.lockCameraVertical'] then
                compat.cameraPitch = compat.cameraPitch or GetGameplayCamRelativePitch()
                SetGameplayCamRelativePitch(compat.cameraPitch, 1.0)
            end

            if compat.pointing and not IsTaskMoveNetworkActive(ped) then compat.pointing = false end

            if compat.placement and DoesEntityExist(compat.placement.entity) then
                local cameraCoords = GetGameplayCamCoord()
                local direction = placementDirection(GetGameplayCamRot(2))
                if IsControlJustPressed(0, 14) then compat.placement.distance = math.min(25.0, compat.placement.distance + 0.5) end
                if IsControlJustPressed(0, 15) then compat.placement.distance = math.max(1.0, compat.placement.distance - 0.5) end
                if IsControlPressed(0, 174) then compat.placement.heading = compat.placement.heading + 1.5 end
                if IsControlPressed(0, 175) then compat.placement.heading = compat.placement.heading - 1.5 end
                local target = cameraCoords + direction * compat.placement.distance
                SetEntityCoordsNoOffset(compat.placement.entity, target.x, target.y, target.z, false, false, false)
                SetEntityHeading(compat.placement.entity, compat.placement.heading)
                if IsDisabledControlJustReleased(0, 24) or IsControlJustReleased(0, 24) then finishEntityPlacement(IsControlPressed(0, 21)) end
                if IsDisabledControlJustReleased(0, 25) or IsControlJustReleased(0, 25) then cancelEntityPlacement(false) end
            elseif compat.placement then
                compat.placement = nil
            end

            if toggles['weapons.noReload'] then SetPedInfiniteAmmoClip(ped, true) end

            if now >= nextParachuteCheck then
                if toggles['weapons.unlimitedParachutes'] and not HasPedGotWeapon(ped, joaat('gadget_parachute'), false) then
                    if authorizeParachute('weapons.unlimitedParachutes', true) then
                        captureParachuteBaseline()
                        GiveWeaponToPed(ped, joaat('gadget_parachute'), 1, false, false)
                        compat.autoParachutePeds[ped] = true
                    else
                        setCompatToggle('weapons.unlimitedParachutes', false)
                    end
                end
                if toggles['weapons.autoEquipParachute'] and vehicle ~= 0 then
                    local model = GetEntityModel(vehicle)
                    if (IsThisModelAPlane(model) or IsThisModelAHeli(model))
                        and not HasPedGotWeapon(ped, joaat('gadget_parachute'), false) then
                        if authorizeParachute('weapons.autoEquipParachute', true) then
                            captureParachuteBaseline()
                            GiveWeaponToPed(ped, joaat('gadget_parachute'), 1, false, false)
                            compat.autoParachutePeds[ped] = true
                        else
                            setCompatToggle('weapons.autoEquipParachute', false)
                        end
                    end
                end
                nextParachuteCheck = now + 1000
            end

            if now >= nextHud then
                local healthPayload = { visible = false }
                if toggles['vehicle.showHealth'] and vehicle ~= 0 then
                    healthPayload = {
                        visible = true,
                        engine = math.floor(GetVehicleEngineHealth(vehicle)),
                        body = math.floor(GetVehicleBodyHealth(vehicle)),
                        tank = math.floor(GetVehiclePetrolTankHealth(vehicle)),
                    }
                end

                local speakers = {}
                if toggles['voice.showSpeaker'] then
                    for _, player in ipairs(GetActivePlayers()) do
                        if NetworkIsPlayerTalking(player) then speakers[#speakers + 1] = GetPlayerName(player) or ('Player ' .. player) end
                        if #speakers >= 6 then break end
                    end
                end
                local voicePayload = {
                    visible = toggles['voice.showSpeaker'] == true or toggles['voice.showStatus'] == true,
                    talking = NetworkIsPlayerTalking(PlayerId()),
                    speakers = speakers,
                }
                local encodedHealth = json.encode(healthPayload)
                local encodedVoice = json.encode(voicePayload)
                if encodedHealth ~= lastHealthPayload then SendNUIMessage({ action = 'cortex-admin:setVehicleHealthHud', data = healthPayload }); lastHealthPayload = encodedHealth end
                if encodedVoice ~= lastVoicePayload then SendNUIMessage({ action = 'cortex-admin:setVoiceHud', data = voicePayload }); lastVoicePayload = encodedVoice end
                if toggles['dev.showTime'] then
                    SendNUIMessage({ action = 'cortex-admin:setTimeHud', data = { visible = true, hour = GetClockHours(), minute = GetClockMinutes() } })
                end
                nextHud = now + 250
            end

            if toggles['dev.overheadNames'] then
                local myCoords = GetEntityCoords(ped)
                for _, player in ipairs(GetActivePlayers()) do
                    if player ~= PlayerId() then
                        local targetPed = GetPlayerPed(player)
                        local targetCoords = GetEntityCoords(targetPed)
                        local distance = #(myCoords - targetCoords)
                        if distance <= 80.0 and HasEntityClearLosToEntity(ped, targetPed, 17) then
                            local onScreen, sx, sy = World3dToScreen2d(targetCoords.x, targetCoords.y, targetCoords.z + 1.05)
                            if onScreen then
                                SetTextScale(0.28, 0.28); SetTextFont(0); SetTextProportional(1); SetTextCentre(true); SetTextColour(247, 248, 248, 220)
                                SetTextOutline(); BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(('[%d] %s'):format(GetPlayerServerId(player), GetPlayerName(player) or 'Player')); EndTextCommandDisplayText(sx, sy)
                            end
                        end
                    end
                end
            end

            if toggles['dev.entityInspector'] then
                local found, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())
                if found and entity and entity ~= 0 and DoesEntityExist(entity) then
                    if compat.inspectorEntity ~= 0 and compat.inspectorEntity ~= entity and DoesEntityExist(compat.inspectorEntity) then
                        SetEntityDrawOutline(compat.inspectorEntity, false)
                    end
                    compat.inspectorEntity = entity
                    SetEntityDrawOutlineColor(113, 112, 255, 220)
                    SetEntityDrawOutline(entity, true)
                    local coords = GetEntityCoords(entity)
                    local onScreen, sx, sy = World3dToScreen2d(coords.x, coords.y, coords.z + 1.0)
                    if onScreen then
                        local owner = NetworkGetEntityOwner(entity)
                        SetTextScale(0.27, 0.27); SetTextFont(0); SetTextCentre(true); SetTextColour(247, 248, 248, 230); SetTextOutline()
                        BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(('Handle %d | Model %u | Owner %s'):format(entity, GetEntityModel(entity), owner and GetPlayerServerId(owner) or 'none')); EndTextCommandDisplayText(sx, sy)
                    end
                elseif compat.inspectorEntity ~= 0 then
                    if DoesEntityExist(compat.inspectorEntity) then SetEntityDrawOutline(compat.inspectorEntity, false) end
                    compat.inspectorEntity = 0
                end
            elseif compat.inspectorEntity ~= 0 then
                if DoesEntityExist(compat.inspectorEntity) then SetEntityDrawOutline(compat.inspectorEntity, false) end
                compat.inspectorEntity = 0
            end

            if toggles['dev.vehicleDimensions'] or toggles['dev.propDimensions'] or toggles['dev.pedDimensions'] then
                if now >= nextDimensionScan then
                    inspectNearbyEntities(GetEntityCoords(ped), preferences.dimensionRadius or 50.0, toggles)
                    nextDimensionScan = now + 350
                end
                drawDimensionLabels()
            elseif next(compat.dimensionEntities) then
                clearDimensionOutlines()
            end

            if toggles['dev.locationDisplay'] and now >= nextLocationHud then
                local coords = GetEntityCoords(ped)
                local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
                SendNUIMessage({
                    action = 'cortex-admin:setCoordHud',
                    data = {
                        visible = true,
                        showCoordinates = toggles['dev.showCoords'] == true,
                        showLocation = true,
                    },
                })
                SendNUIMessage({
                    action = 'cortex-admin:updateCoordHud',
                    data = {
                        x = coords.x, y = coords.y, z = coords.z, heading = GetEntityHeading(ped),
                        street = streetHash ~= 0 and GetStreetNameFromHashKey(streetHash) or '',
                        crossing = crossingHash ~= 0 and GetStreetNameFromHashKey(crossingHash) or nil,
                    },
                })
                nextLocationHud = now + 250
            end

            if compat.clothingGlowTouched and SetPedIlluminatedClothingGlowIntensity then
                local glowStyle = preferences.clothingGlowStyle or 0
                local intensity = 1.0
                if glowStyle == 1 then intensity = 0.0
                elseif glowStyle == 2 then intensity = (math.sin(now / 500.0) + 1.0) * 0.5
                elseif glowStyle == 3 then intensity = math.floor(now / 250) % 2 == 0 and 1.0 or 0.0 end
                SetPedIlluminatedClothingGlowIntensity(ped, intensity)
            end

            Wait(0)
            until true
        end
    end
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource ~= resourceName then return end
    if compat.spectatingServerId then NetworkSetInSpectatorMode(false, compat.spectatingPed) end
    if compat.personalBlip ~= 0 and DoesBlipExist(compat.personalBlip) then RemoveBlip(compat.personalBlip) end
    clearLocationBlips()
    cleanupTransientCompatibilityState(playerPed())
    for index = 1, #compat.spawnedEntities do
        local entity = compat.spawnedEntities[index]
        if entity and DoesEntityExist(entity) and requestControl(entity, 150) then DeleteEntity(entity) end
    end
    NetworkSetVoiceActive(true)
    NetworkClearVoiceChannel()
    compat.clothingGlowTouched = false
end)

Admin.setVmenuImportedData = function(payload)
    compat.imported = type(payload) == 'table' and (clone(payload) or {}) or {}
    saveJsonKvp(Config.KvpKeys.vmenuImport, compat.imported)
end

Admin.setVmenuImportedConfig = function(payload)
    compat.importedConfig = type(payload) == 'table' and (clone(payload) or {}) or {}
    local saved = saveJsonKvp(Config.KvpKeys.vmenuClientConfig, compat.importedConfig)
    refreshLocationBlips()
    if type(Admin.setImportedAddonVehicles) == 'function' then
        local addons = type(compat.importedConfig.addons) == 'table' and compat.importedConfig.addons or {}
        Admin.setImportedAddonVehicles(type(addons.vehicles) == 'table' and addons.vehicles or {})
    end
    return saved
end

Admin.setVmenuImportedCategories = function(payload)
    compat.importedCategories = type(payload) == 'table' and (clone(payload) or {}) or {}
    return saveJsonKvp(Config.KvpKeys.vmenuCategories, compat.importedCategories)
end

Admin.getVmenuImportedConfig = function()
    return clone(compat.importedConfig) or {}
end


Admin.getVmenuImportedCategories = function()
    return clone(compat.importedCategories) or {}
end

local function nextRequestId(prefix)
    return ('%s:%s:%d:%d'):format(resourceName, prefix, GetGameTimer(), math.random(1000, 9999))
end

Admin.authorizeVmenuModels = function(kind, models, actionId)
    if type(kind) ~= 'string' or type(models) ~= 'table' or #models < 1 or #models > 256
        or type(actionId) ~= 'string' then
        return { ok = false, error = 'invalid_request', allowed = {} }
    end
    local requestId = nextRequestId('model-auth')
    local pending = promise.new()
    pendingModelAuthorizationRequests[requestId] = pending
    TriggerServerEvent('cortex-admin:server:requestModelAuthorization', requestId, {
        kind = kind,
        models = models,
        actionId = actionId,
    })
    SetTimeout(4500, function()
        if pendingModelAuthorizationRequests[requestId] then
            pendingModelAuthorizationRequests[requestId] = nil
            pending:resolve({ ok = false, error = 'timeout', allowed = {} })
        end
    end)
    return Citizen.Await(pending)
end

Admin.authorizeVmenuModel = function(kind, model, actionId)
    local result = Admin.authorizeVmenuModels(kind, { model }, actionId)
    local authorized = type(result) == 'table' and result.ok == true
        and type(result.allowed) == 'table' and result.allowed[1] == true
    return authorized, type(result) == 'table' and result.error or 'unavailable',
        type(result) == 'table' and result.token or nil
end

Admin.getVmenuServerState = function(importNow)
    local requestId = nextRequestId('vmenu-state')
    local pending = promise.new()
    pendingCompatibilityRequests[requestId] = pending
    TriggerServerEvent('cortex-admin:server:requestVmenuCompatibilityState', requestId, importNow == true)
    SetTimeout(5000, function()
        if pendingCompatibilityRequests[requestId] then
            pendingCompatibilityRequests[requestId] = nil
            pending:resolve(nil)
        end
    end)
    return Citizen.Await(pending)
end

Admin.getVmenuConfigDomain = function(domain)
    domain = trim(domain, 48)
    if not domain then return nil, 'invalid_domain' end
    local requestId = nextRequestId('vmenu-config')
    local pending = promise.new()
    pendingConfigDomainRequests[requestId] = { domain = domain, promise = pending }
    TriggerServerEvent('cortex-admin:server:requestVmenuConfigDomain', requestId, domain)
    SetTimeout(15000, function()
        local request = pendingConfigDomainRequests[requestId]
        if request then
            pendingConfigDomainRequests[requestId] = nil
            request.promise:resolve({ ok = false, error = 'timeout' })
        end
    end)
    local result = Citizen.Await(pending)
    if type(result) ~= 'table' or result.ok ~= true or type(result.data) ~= 'table' then
        return nil, type(result) == 'table' and result.error or 'unavailable'
    end
    return result.data
end

Admin.getBanList = function(options)
    local requestId = nextRequestId('bans')
    local pending = promise.new()
    pendingBanListRequests[requestId] = pending
    TriggerServerEvent('cortex-admin:server:requestBanList', requestId, type(options) == 'table' and options or {})
    SetTimeout(4000, function()
        if pendingBanListRequests[requestId] then
            pendingBanListRequests[requestId] = nil
            pending:resolve(nil)
        end
    end)
    local page = Citizen.Await(pending)
    return type(page) == 'table' and page or nil
end

Admin.unbanPlayer = function(banId)
    banId = trim(banId, 96)
    if not banId then return { ok = false, error = 'invalid_ban_id' } end
    local requestId = nextRequestId('unban')
    local pending = promise.new()
    pendingUnbanRequests[requestId] = pending
    TriggerServerEvent('cortex-admin:server:unban', requestId, banId)
    SetTimeout(4000, function()
        if pendingUnbanRequests[requestId] then
            pendingUnbanRequests[requestId] = nil
            pending:resolve(nil)
        end
    end)
    return Citizen.Await(pending) or { ok = false, error = 'timeout' }
end

if type(Admin.setImportedAddonVehicles) == 'function' then
    local addons = type(compat.importedConfig.addons) == 'table' and compat.importedConfig.addons or {}
    Admin.setImportedAddonVehicles(type(addons.vehicles) == 'table' and addons.vehicles or {})
end

refreshLocationBlips()
