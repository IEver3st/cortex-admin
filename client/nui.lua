local Admin = EsAdmin
local state = Admin.state
local mathFloor = math.floor
local tonumber = tonumber
local type = type

local function trimString(value, maxLength)
    if type(value) ~= 'string' then
        return nil
    end

    value = value:match('^%s*(.-)%s*$')
    if value == '' then
        return nil
    end

    if maxLength and #value > maxLength then
        value = value:sub(1, maxLength)
    end

    return value
end

local function toInteger(value, minValue, maxValue)
    local number = tonumber(value)
    if not number or number ~= number then
        return nil
    end

    number = mathFloor(number)

    if minValue and number < minValue then
        return nil
    end

    if maxValue and number > maxValue then
        return nil
    end

    return number
end

local function replyError(cb, message)
    cb({ ok = false, error = message or 'invalid_payload' })
end

local function buildEmptyAppearancePayload()
    return {
        components = {},
        props = {},
        maxComponents = {},
        maxProps = {},
        model = 0,
        isFreemode = false,
        features = {},
        headBlend = {
            shapeFirstID = 0,
            shapeSecondID = 0,
            shapeThirdID = 0,
            skinFirstID = 0,
            skinSecondID = 0,
            skinThirdID = 0,
            shapeMix = 0.5,
            skinMix = 0.5,
            thirdMix = 0.0,
        },
        hairColor = 0,
        hairHighlightColor = 0,
        eyeColor = 0,
        overlays = {},
    }
end

local jsonEncode = json.encode
local DEBUG_LOG_REL = '.cursor/debug-8d7dac.log'
local function agentDbg(hypothesisId, location, message, data)
    local res = GetCurrentResourceName()
    local payload = {
        sessionId = '8d7dac',
        hypothesisId = hypothesisId,
        location = location,
        message = message,
        data = data or {},
        timestamp = GetGameTimer(),
    }
    local line = jsonEncode(payload) .. '\n'
    local save = SaveResourceFile
    if type(save) ~= 'function' then
        return
    end
    local prev = LoadResourceFile(res, DEBUG_LOG_REL)
    if type(prev) == 'string' and prev ~= '' then
        line = prev .. line
    end
    save(res, DEBUG_LOG_REL, line, -1)
end

local function isFavorite(id)
    for i = 1, #state.favorites do
        if state.favorites[i] == id then
            return i
        end
    end
    return nil
end

local function toggleFavorite(id)
    if not id then
        return false
    end

    local index = isFavorite(id)
    if index then
        table.remove(state.favorites, index)
    else
        state.favorites[#state.favorites + 1] = id
    end

    Admin.saveFavorites()
    -- Send only favorites update, not entire state
    SendNUIMessage({
        action = 'es_admin:setState',
        data = { favorites = state.favorites }
    })

    return true
end

RegisterNUICallback('es_admin:ready', function(_, cb)
    Admin.sendUiState()
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:close', function(_, cb)
    Admin.setOpen(false)
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:action', function(data, cb)
    local actionId = trimString(data and data.id, 96)
    if not actionId then
        replyError(cb, 'invalid_action')
        return
    end

    local payload = data and data.data
    CreateThread(function()
        Admin.executeAction(actionId, payload)
        cb({ ok = true })
    end)
end)

RegisterNUICallback('es_admin:previewVehicle', function(data, cb)
    local model = data and data.model
    if (type(model) ~= 'string' and type(model) ~= 'number') or not Admin.previewVehicle then
        replyError(cb, 'invalid_model')
        return
    end

    if type(model) == 'string' then
        model = trimString(model, 64)
        if not model then
            replyError(cb, 'invalid_model')
            return
        end
    end

    local ok = Admin.previewVehicle(model)
    cb({ ok = ok == true })
end)

RegisterNUICallback('es_admin:clearVehiclePreview', function(_, cb)
    if Admin.clearVehiclePreview then
        Admin.clearVehiclePreview()
    end
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:getPreviewVehicleExtras', function(_, cb)
    local list = Admin.getPreviewVehicleExtras and Admin.getPreviewVehicleExtras() or {}
    cb({ ok = true, extras = list })
end)

RegisterNUICallback('es_admin:getWeaponAttachments', function(_, cb)
    local payload = Admin.getWeaponAttachmentList and Admin.getWeaponAttachmentList() or { weaponName = '', components = {} }
    cb({
        ok = true,
        weaponName = payload.weaponName or '',
        components = payload.components or {},
    })
end)

RegisterNUICallback('es_admin:toggleWeaponAttachment', function(data, cb)
    local h = trimString(data and data.componentHash, 192)
    if not h then
        replyError(cb, 'invalid_component')
        return
    end

    local ok = Admin.toggleWeaponAttachment and Admin.toggleWeaponAttachment(h)
    cb({ ok = ok == true })
end)

RegisterNUICallback('es_admin:togglePreviewVehicleExtra', function(data, cb)
    local id = toInteger(data and data.extraId, 1, 99)
    if not id then
        replyError(cb, 'invalid_extra')
        return
    end

    local ok = Admin.togglePreviewVehicleExtra and Admin.togglePreviewVehicleExtra(id)
    cb({ ok = ok == true })
end)

RegisterNUICallback('es_admin:setVehiclePreviewShared', function(data, cb)
    local ok = Admin.setPreviewShared and Admin.setPreviewShared(data and data.shared == true)
    cb({ ok = ok == true })
end)

RegisterNUICallback('es_admin:spawnPreviewVehicle', function(_, cb)
    CreateThread(function()
        local ok = Admin.spawnVehicleFromPreview and Admin.spawnVehicleFromPreview() or false
        cb({ ok = ok == true })
    end)
end)

RegisterNUICallback('es_admin:setTypingState', function(data, cb)
    if Admin.setTypingLock then
        Admin.setTypingLock(data and data.typing == true)
    end
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:toggle', function(data, cb)
    local actionId = trimString(data and data.id, 96)
    if not actionId then
        replyError(cb, 'invalid_action')
        return
    end

    Admin.toggleAction(actionId, data and data.enabled == true)
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:select', function(data, cb)
    local actionId = trimString(data and data.id, 96)
    if not actionId then
        replyError(cb, 'invalid_action')
        return
    end

    Admin.selectAction(actionId, data and data.value)
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:favorite', function(data, cb)
    local actionId = trimString(data and data.id, 96)
    if not actionId then
        replyError(cb, 'invalid_action')
        return
    end

    toggleFavorite(actionId)
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:updateSetting', function(data, cb)
    local key = trimString(data and data.key, 64)
    if not key then
        replyError(cb, 'invalid_setting')
        return
    end

    state.settings[key] = data.value
    Admin.saveSettings()
    -- Send only settings update
    SendNUIMessage({
        action = 'es_admin:setState',
        data = { settings = state.settings }
    })
    cb({ ok = true })
end)

local freezeState = {}

RegisterNUICallback('es_admin:playerAction', function(data, cb)
    local action = trimString(data and data.action, 16)
    local target = toInteger(data and data.target, 1)
    if not action or not target then
        replyError(cb, 'invalid_player_action')
        return
    end

    data.action = action
    data.target = target

    if action == 'goto' then
        local targetId = GetPlayerFromServerId(target)
        if targetId == -1 then
            replyError(cb, 'player_not_found')
            return
        end

        local ped = GetPlayerPed(targetId)
        if ped == 0 or not DoesEntityExist(ped) then
            replyError(cb, 'player_not_found')
            return
        end

        local coords = GetEntityCoords(ped)
        EsAdmin.state.lastCoords = GetEntityCoords(PlayerPedId())
        SetEntityCoordsNoOffset(PlayerPedId(), coords.x, coords.y, coords.z, false, false, false)
        cb({ ok = true })
        return
    end

    if action == 'bring' then
        local coords = GetEntityCoords(PlayerPedId())
        data.coords = { x = coords.x, y = coords.y, z = coords.z }
        data.heading = GetEntityHeading(PlayerPedId())
    end

    if action == 'freeze' then
        local current = freezeState[target] or false
        freezeState[target] = not current
        data.enabled = freezeState[target]
    end

    TriggerServerEvent('es_admin:server:playerAction', data)
    cb({ ok = true })
end)

-- Resources
RegisterNetEvent('es_admin:client:setResources', function(resources)
    state.resources = resources
    SendNUIMessage({
        action = 'es_admin:setState',
        data = { resources = resources }
    })
end)

RegisterNUICallback('es_admin:requestResources', function(_, cb)
    TriggerServerEvent('es_admin:server:requestResources')
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:requestAddonVehicles', function(_, cb)
    local requested = false
    if type(Admin.requestAddonVehiclesIfNeeded) == 'function' then
        requested = Admin.requestAddonVehiclesIfNeeded(false) == true
    else
        TriggerServerEvent('es_admin:server:requestAddonVehicles')
        requested = true
    end
    cb({ ok = true, requested = requested })
end)

RegisterNUICallback('es_admin:resourceAction', function(data, cb)
    local action = trimString(data and data.action, 16)
    local name = trimString(data and data.name, 64)
    if not action or not name then
        replyError(cb, 'invalid_resource_action')
        return
    end

    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    TriggerServerEvent('es_admin:server:resourceAction', {
        action = action,
        name = name,
    })
    cb({ ok = true })
end)

-- Appearance
RegisterNUICallback('es_admin:getAppearance', function(_, cb)
    agentDbg('H4', 'nui.lua:getAppearance', 'enter', {})
    local ok, data = pcall(Admin.getPedAppearance)
    if not ok or type(data) ~= 'table' then
        print(('[es_admin] WARNING: Failed to build appearance payload: %s'):format(tostring(data)))
        agentDbg('H4', 'nui.lua:getAppearance', 'error', { error = tostring(data) })
        cb(buildEmptyAppearancePayload())
        return
    end

    agentDbg('H4', 'nui.lua:getAppearance', 'exit', {})
    cb(data)
end)

RegisterNUICallback('es_admin:setAppearance', function(data, cb)
    if type(data) ~= 'table' then
        replyError(cb, 'invalid_appearance')
        return
    end

    Admin.setPedAppearance(data)
    cb({ ok = true })
end)

-- Vehicle Customization
RegisterNUICallback('es_admin:getVehicleCustomization', function(_, cb)
    cb(Admin.getVehicleCustomization())
end)

RegisterNUICallback('es_admin:setVehicleCustomization', function(data, cb)
    if type(data) ~= 'table' then
        replyError(cb, 'invalid_vehicle_customization')
        return
    end

    Admin.setVehicleCustomization(data)
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:getSavedPeds', function(_, cb)
    CreateThread(function()
        agentDbg('H3', 'nui.lua:getSavedPeds', 'enter', {})
        local ok, data = pcall(Admin.getSavedPeds)
        if not ok or type(data) ~= 'table' then
            print(('[es_admin] WARNING: Failed to build saved ped list: %s'):format(tostring(data)))
            agentDbg('H3', 'nui.lua:getSavedPeds', 'error', { error = tostring(data) })
            cb({})
            return
        end

        agentDbg('H3', 'nui.lua:getSavedPeds', 'exit', { count = #data })
        cb(data)
    end)
end)

RegisterNUICallback('es_admin:getWardrobeShareTargets', function(_, cb)
    if type(Admin.getNearbyWardrobeShareTargets) ~= 'function' then
        replyError(cb, 'wardrobe_share_unavailable')
        return
    end

    CreateThread(function()
        agentDbg('H1', 'nui.lua:getWardrobeShareTargets', 'enter', {})
        local targets = Admin.getNearbyWardrobeShareTargets()
        agentDbg('H1', 'nui.lua:getWardrobeShareTargets', 'exit', { n = type(targets) == 'table' and #targets or -1 })
        cb({
            ok = true,
            targets = targets,
        })
    end)
end)

RegisterNUICallback('es_admin:shareWardrobe', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then
        replyError(cb, 'invalid_target')
        return
    end

    CreateThread(function()
        local ok = type(Admin.shareCurrentWardrobe) == 'function' and Admin.shareCurrentWardrobe(target) == true
        cb({ ok = ok })
    end)
end)

RegisterNUICallback('es_admin:acceptWardrobeShare', function(data, cb)
    local shareId = trimString(data and data.shareId, 96)
    if not shareId or type(Admin.acceptWardrobeShare) ~= 'function' then
        replyError(cb, 'invalid_share')
        return
    end

    cb({ ok = Admin.acceptWardrobeShare(shareId) == true })
end)

RegisterNUICallback('es_admin:saveWardrobeShare', function(data, cb)
    local shareId = trimString(data and data.shareId, 96)
    if not shareId or type(Admin.saveWardrobeShare) ~= 'function' then
        replyError(cb, 'invalid_share')
        return
    end

    cb({ ok = Admin.saveWardrobeShare(shareId) == true })
end)

RegisterNUICallback('es_admin:dismissWardrobeShare', function(data, cb)
    local shareId = trimString(data and data.shareId, 96)
    if not shareId or type(Admin.dismissWardrobeShare) ~= 'function' then
        replyError(cb, 'invalid_share')
        return
    end

    cb({ ok = Admin.dismissWardrobeShare(shareId) == true })
end)

RegisterNUICallback('es_admin:getSavedTeleportLocations', function(_, cb)
    if type(Admin.getSavedTeleportLocations) ~= 'function' then
        replyError(cb, 'teleport_locations_unavailable')
        return
    end

    cb(Admin.getSavedTeleportLocations())
end)

RegisterNUICallback('es_admin:saveCurrentTeleportLocation', function(data, cb)
    if type(Admin.saveCurrentTeleportLocation) ~= 'function' then
        replyError(cb, 'teleport_locations_unavailable')
        return
    end

    local name = trimString(data and data.name, 64)
    local ok = Admin.saveCurrentTeleportLocation(name)
    cb({ ok = ok == true })
end)

RegisterNUICallback('es_admin:loadSavedTeleportLocation', function(data, cb)
    if type(Admin.loadSavedTeleportLocation) ~= 'function' then
        replyError(cb, 'teleport_locations_unavailable')
        return
    end

    local name = trimString(data and data.name, 64)
    local ok = Admin.loadSavedTeleportLocation(name)
    cb({ ok = ok == true })
end)

RegisterNUICallback('es_admin:deleteSavedTeleportLocation', function(data, cb)
    if type(Admin.deleteSavedTeleportLocation) ~= 'function' then
        replyError(cb, 'teleport_locations_unavailable')
        return
    end

    local name = trimString(data and data.name, 64)
    local ok = Admin.deleteSavedTeleportLocation(name)
    cb({ ok = ok == true })
end)

-- ============================================================================
-- INVENTORY (QBX / ox_inventory)
-- ============================================================================

RegisterNUICallback('es_admin:requestItems', function(_, cb)
    TriggerServerEvent('es_admin:server:getItems')
    cb({ ok = true })
end)

RegisterNetEvent('es_admin:client:setItems', function(items)
    SendNUIMessage({
        action = 'es_admin:setState',
        data = { inventoryItems = items or {} }
    })
end)

RegisterNUICallback('es_admin:giveItem', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local item = trimString(data and data.item, 64)
    local amount = toInteger(data and data.amount, 1, 10000) or 1
    if not target or not item then
        replyError(cb, 'invalid_item_request')
        return
    end

    TriggerServerEvent('es_admin:server:giveItem', {
        target = target,
        item = item,
        amount = amount,
    })
    cb({ ok = true })
end)

-- ============================================================================
-- GARAGE (QBX / qbx_vehicles)
-- ============================================================================

RegisterNUICallback('es_admin:requestGarage', function(_, cb)
    TriggerServerEvent('es_admin:server:getPlayerGarage')
    cb({ ok = true })
end)

RegisterNetEvent('es_admin:client:setGarageVehicles', function(vehicles)
    SendNUIMessage({
        action = 'es_admin:setState',
        data = { garageVehicles = vehicles or {} }
    })
end)

RegisterNUICallback('es_admin:spawnGarageVehicle', function(data, cb)
    local vehicleId = toInteger(data and data.vehicleId, 1)
    if not vehicleId then
        replyError(cb, 'invalid_vehicle')
        return
    end

    TriggerServerEvent('es_admin:server:spawnGarageVehicle', {
        vehicleId = vehicleId,
    })
    cb({ ok = true })
end)

-- ============================================================================
-- QBX PLAYER MANAGEMENT NUI CALLBACKS
-- ============================================================================

RegisterNUICallback('es_admin:killPlayer', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then replyError(cb, 'invalid_target') return end
    TriggerServerEvent('es_admin:server:killPlayer', { target = target })
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:revivePlayer', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then replyError(cb, 'invalid_target') return end
    TriggerServerEvent('es_admin:server:revivePlayer', { target = target })
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:sitInVehicle', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then replyError(cb, 'invalid_target') return end
    TriggerServerEvent('es_admin:server:sitInVehicle', { target = target })
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:setJob', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local job = trimString(data and data.job, 64)
    local grade = toInteger(data and data.grade, 0, 99) or 0
    if not target or not job then replyError(cb, 'invalid_job') return end

    TriggerServerEvent('es_admin:server:setJob', {
        target = target,
        job = job,
        grade = grade,
    })
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:setGang', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local gang = trimString(data and data.gang, 64)
    local grade = toInteger(data and data.grade, 0, 99) or 0
    if not target or not gang then replyError(cb, 'invalid_gang') return end

    TriggerServerEvent('es_admin:server:setGang', {
        target = target,
        gang = gang,
        grade = grade,
    })
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:setMoney', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local amount = toInteger(data and data.amount, 0, 1000000000)
    local moneyType = trimString(data and data.moneyType, 32) or 'cash'
    local actionId = trimString(data and data.actionId, 64) or 'player.setCash'
    if not target or amount == nil then replyError(cb, 'invalid_money') return end

    TriggerServerEvent('es_admin:server:setMoney', {
        target = target,
        moneyType = moneyType,
        amount = amount,
        actionId = actionId,
    })
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:giveMoney', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local amount = toInteger(data and data.amount, 1, 1000000000)
    local moneyType = trimString(data and data.moneyType, 32) or 'cash'
    if not target or not amount then replyError(cb, 'invalid_money') return end

    TriggerServerEvent('es_admin:server:giveMoney', {
        target = target,
        moneyType = moneyType,
        amount = amount,
    })
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:setMetadata', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local key = trimString(data and data.key, 64)
    local actionId = trimString(data and data.actionId, 64)
    if not target or not key then replyError(cb, 'invalid_metadata') return end

    TriggerServerEvent('es_admin:server:setMetadata', {
        target = target,
        key = key,
        value = data and data.value,
        actionId = actionId,
    })
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:openInventory', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then replyError(cb, 'invalid_target') return end
    TriggerServerEvent('es_admin:server:openInventory', { target = target })
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:setRoutingBucket', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local bucket = toInteger(data and data.bucket, 0, 65535) or 0
    if not target then replyError(cb, 'invalid_bucket') return end

    TriggerServerEvent('es_admin:server:setRoutingBucket', {
        target = target,
        bucket = bucket,
    })
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:adminCar', function(_, cb)
    TriggerServerEvent('es_admin:server:adminCar')
    cb({ ok = true })
end)

RegisterNUICallback('es_admin:pullStash', function(data, cb)
    local stash = trimString(data and data.stash, 80)
    if not stash then replyError(cb, 'invalid_stash') return end
    TriggerServerEvent('es_admin:server:pullStash', { stash = stash })
    cb({ ok = true })
end)

-- ============================================================================
-- QBX CLIENT-SIDE EVENT HANDLERS
-- ============================================================================

RegisterNetEvent('es_admin:client:killPed', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, 0)
end)

RegisterNetEvent('es_admin:client:revivePed', function()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    -- Try hospital/medical revive if available
    local revived = false

    -- Try qbx_medical
    local ok1 = pcall(function()
        exports.qbx_medical:revive()
        revived = true
    end)
    if revived then return end

    -- Try hospital resource
    local ok2 = pcall(function()
        TriggerEvent('hospital:client:Revive')
        revived = true
    end)
    if revived then return end

    -- Fallback: native revive
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPlayerInvincible(PlayerId(), false)
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
end)

RegisterNetEvent('es_admin:client:sitInVehicle', function(netId)
    if not netId then return end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(vehicle) then
        Admin.notify('error', 'Vehicle not found')
        return
    end

    -- Find first empty seat
    local maxSeats = GetVehicleMaxNumberOfPassengers(vehicle)
    for seat = -1, maxSeats - 1 do
        if IsVehicleSeatFree(vehicle, seat) then
            SetPedIntoVehicle(PlayerPedId(), vehicle, seat)
            return
        end
    end
    Admin.notify('error', 'No empty seats')
end)

RegisterNetEvent('es_admin:client:getVehicleProps', function()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        Admin.notify('error', 'You are not in a vehicle')
        return
    end

    local model = GetEntityModel(vehicle)

    -- Try to get full props via ox_lib
    local props = nil
    local ok = pcall(function()
        props = lib.getVehicleProperties(vehicle)
    end)

    if not ok or not props then
        -- Fallback: basic props
        props = {
            model = model,
            plate = GetVehicleNumberPlateText(vehicle),
        }
    end

    TriggerServerEvent('es_admin:server:adminCarSave', {
        model = model,
        props = props,
    })
end)

RegisterNUICallback('es_admin:deleteSavedPed', function(data, cb)
    if not data then
        replyError(cb, 'invalid_entry')
        return
    end

    local ref = (data and data.entry) or data
    CreateThread(function()
        Admin.deleteSavedPed(ref)
        cb({ ok = true })
    end)
end)

RegisterNUICallback('es_admin:renameSavedPed', function(data, cb)
    local newName = trimString(data and data.newName, 64)
    if not data or not newName then
        replyError(cb, 'invalid_name')
        return
    end

    local entry = (data and data.entry) or data
    CreateThread(function()
        Admin.renameSavedPed(entry, newName)
        cb({ ok = true })
    end)
end)

RegisterNUICallback('es_admin:cloneSavedPed', function(data, cb)
    local entry = (data and data.entry) or data
    local fallbackName = entry and entry.name and (entry.name .. '_clone') or nil
    local newName = trimString(data and data.newName, 64) or trimString(fallbackName, 64)
    if not entry or not newName then
        replyError(cb, 'invalid_name')
        return
    end

    CreateThread(function()
        Admin.cloneSavedPed(entry, newName)
        cb({ ok = true })
    end)
end)

RegisterNUICallback('es_admin:importVmenuSavedPeds', function(_, cb)
    if type(Admin.importVmenuSavedPeds) ~= 'function' then
        replyError(cb, 'import_unavailable')
        return
    end

    CreateThread(function()
        local okCall, ok, result = pcall(Admin.importVmenuSavedPeds)
        if not okCall then
            print(('[es_admin] WARNING: vMenu ped import crashed: %s'):format(tostring(ok)))
            cb({
                ok = false,
                result = { reason = 'exception', message = tostring(ok) },
            })
            return
        end

        cb({
            ok = ok == true,
            result = result or {},
        })
    end)
end)

RegisterNUICallback('es_admin:getVmenuMigrationSnapshot', function(_, cb)
    if type(Admin.getVmenuMigrationSnapshot) ~= 'function' then
        replyError(cb, 'migration_unavailable')
        return
    end

    CreateThread(function()
        agentDbg('H3', 'nui.lua:getVmenuMigrationSnapshot', 'enter', {})
        local ok, snap = pcall(Admin.getVmenuMigrationSnapshot)
        if not ok or type(snap) ~= 'table' then
            print(('[es_admin] WARNING: Failed to build vMenu migration snapshot: %s'):format(tostring(snap)))
            cb({
                vmenuRunning = GetResourceState('vMenu') == 'started',
                peds = {
                    available = false,
                    count = 0,
                    source = 'error',
                    importedCount = 0,
                },
                vehicles = {
                    available = false,
                    count = 0,
                    source = 'error',
                    importedCount = 0,
                },
                permissions = {
                    mode = 'error',
                    note = 'Failed to read vMenu migration snapshot.',
                },
            })
            return
        end

        agentDbg('H3', 'nui.lua:getVmenuMigrationSnapshot', 'exit', {})
        cb(snap)
    end)
end)

RegisterNUICallback('es_admin:importVmenuMigrationData', function(_, cb)
    if type(Admin.importVmenuMigrationData) ~= 'function' then
        replyError(cb, 'migration_unavailable')
        return
    end

    CreateThread(function()
        local okCall, ok, result = pcall(Admin.importVmenuMigrationData)
        if not okCall then
            print(('[es_admin] WARNING: vMenu migration import crashed: %s'):format(tostring(ok)))
            cb({
                ok = false,
                result = { reason = 'exception', message = tostring(ok) },
            })
            return
        end

        cb({
            ok = ok == true,
            result = result or {},
        })
    end)
end)
