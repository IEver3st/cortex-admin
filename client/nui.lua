local Admin = EsAdmin
local state = Admin.state
local mathFloor = math.floor
local tonumber = tonumber
local type = type
local nativeRegisterNUICallback = RegisterNUICallback

local function RegisterNUICallback(name, handler)
    nativeRegisterNUICallback(name, function(data, cb)
        local replied = false
        local function reply(payload)
            if replied then return end
            replied = true
            cb(payload)
        end

        local ok, err = pcall(handler, data, reply)
        if not ok then
            print(('[cortex-admin] NUI callback %s failed: %s'):format(name, tostring(err)))
            reply({ ok = false, error = 'internal_error' })
        end
    end)
end

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
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end

    if number ~= mathFloor(number) then
        return nil
    end

    if minValue and number < minValue then
        return nil
    end

    if maxValue and number > maxValue then
        return nil
    end

    return number
end

local function toFiniteNumber(value, minValue, maxValue)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then
        return nil
    end
    if minValue and number < minValue then return nil end
    if maxValue and number > maxValue then return nil end
    return number
end

local function sanitizeRgb(value)
    if type(value) ~= 'table' then return nil end
    local count = 0
    for key in pairs(value) do
        if key ~= 1 and key ~= 2 and key ~= 3 then return nil end
        count = count + 1
    end
    if count ~= 3 then return nil end

    local red = toInteger(value[1], 0, 255)
    local green = toInteger(value[2], 0, 255)
    local blue = toInteger(value[3], 0, 255)
    if red == nil or green == nil or blue == nil then return nil end
    return { red, green, blue }
end

local function replyError(cb, message)
    cb({ ok = false, error = message or 'invalid_payload' })
end

local actionIndex = {}
for _, action in ipairs((EsAdminActions and EsAdminActions.actions) or {}) do
    actionIndex[action.id] = true
end

local function canInvokeAction(actionId)
    local known = actionIndex[actionId] == true
        or (Config.ActionPermissions and Config.ActionPermissions[actionId] ~= nil)
    return known and state.allowed[actionId] == true
end

local function sanitizeSetting(key, value)
    local booleanSettings = {
        showTargetInfo = true,
        doubleClickToRun = true,
        autoLoadSavedPed = true,
        restorePedOnDeath = true,
        defaultToMpPed = true,
        replacePersonalVehicle = true,
        spawnInsideVehicle = true,
        disableAircraftTurbulence = true,
        disablePlaneTurbulence = true,
        disableHelicopterTurbulence = true,
        disablePrivateMessages = true,
        disableControllerSupport = true,
        recordingControls = true,
        minimapControls = true,
        fingerPointControls = true,
        quitSessionInRockstarEditor = true,
    }
    if booleanSettings[key] then
        if type(value) == 'boolean' then return value end
        return nil
    end
    if key == 'uiScale' then
        local number = tonumber(value)
        return number and number == number and number >= 1.0 and number <= 1.6 and number or nil
    end
    if key == 'uiOpacity' then
        local number = tonumber(value)
        return number and number == number and number >= 0.35 and number <= 1.0 and number or nil
    end
    if key == 'menuAccentColor' then
        return type(value) == 'string' and value:match('^#[%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F][%da-fA-F]$') and value:lower() or nil
    end
    if key == 'menuPosition' then
        if value == 'left' or value == 'right' then return value end
        return nil
    end
    if key == 'speedHudUnits' then
        if value == 'mph' or value == 'kph' then return value end
        return nil
    end
    if key == 'speedHudPosition' then
        local allowed = { ['top-left'] = true, ['top-right'] = true, ['bottom-left'] = true, ['bottom-right'] = true }
        return allowed[value] and value or nil
    end
    return nil
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

local function agentDbg() end

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
        action = 'cortex-admin:setState',
        data = { favorites = state.favorites }
    })

    return true
end

RegisterNUICallback('cortex-admin:ready', function(_, cb)
    Admin.sendUiState()
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:close', function(_, cb)
    Admin.setOpen(false)
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:action', function(data, cb)
    local actionId = trimString(data and data.id, 96)
    if not actionId or not canInvokeAction(actionId) then
        replyError(cb, 'invalid_action')
        return
    end

    local payload = data and data.data
    CreateThread(function()
        local ok, err = pcall(Admin.executeAction, actionId, payload)
        if not ok then
            print(('[cortex-admin] action %s failed: %s'):format(actionId, tostring(err)))
            replyError(cb, 'action_failed')
            return
        end
        cb({ ok = true })
    end)
end)

RegisterNUICallback('cortex-admin:previewVehicle', function(data, cb)
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

RegisterNUICallback('cortex-admin:clearVehiclePreview', function(_, cb)
    if Admin.clearVehiclePreview then
        Admin.clearVehiclePreview()
    end
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:getPreviewVehicleExtras', function(_, cb)
    local list = Admin.getPreviewVehicleExtras and Admin.getPreviewVehicleExtras() or {}
    cb({ ok = true, extras = list })
end)

RegisterNUICallback('cortex-admin:getVehicleTuning', function(_, cb)
    local payload = Admin.buildVehicleTuningSnapshot and Admin.buildVehicleTuningSnapshot()
        or { ok = false, error = 'tuning_unavailable', message = 'Live vehicle tuning is unavailable.' }
    cb(payload)
end)

RegisterNUICallback('cortex-admin:setVehicleHandling', function(data, cb)
    local fieldId = trimString(data and data.field, 64)
    if not fieldId or not data or data.value == nil then
        replyError(cb, 'invalid_handling_value')
        return
    end

    local payload = Admin.setVehicleTuningValue and Admin.setVehicleTuningValue(fieldId, data.value)
        or { ok = false, error = 'tuning_unavailable', message = 'Live vehicle tuning is unavailable.' }
    cb(payload)
end)

RegisterNUICallback('cortex-admin:resetVehicleTuningField', function(data, cb)
    local fieldId = trimString(data and data.field, 64)
    if not fieldId then
        replyError(cb, 'invalid_handling_field')
        return
    end

    local payload = Admin.resetVehicleTuningField and Admin.resetVehicleTuningField(fieldId)
        or { ok = false, error = 'tuning_unavailable', message = 'Live vehicle tuning is unavailable.' }
    cb(payload)
end)

RegisterNUICallback('cortex-admin:setVehicleEngineAudio', function(data, cb)
    local rawSoundName = data and data.soundName
    if type(rawSoundName) ~= 'string' or #rawSoundName > 64 then
        replyError(cb, 'invalid_audio_name')
        return
    end

    local soundName = trimString(rawSoundName, 64)
    if not soundName then
        replyError(cb, 'invalid_audio_name')
        return
    end

    local payload = Admin.setVehicleTuningAudio and Admin.setVehicleTuningAudio(soundName)
        or { ok = false, error = 'tuning_unavailable', message = 'Engine audio switching is unavailable.' }
    cb(payload)
end)

RegisterNUICallback('cortex-admin:resetVehicleTuning', function(data, cb)
    local scope = trimString(data and data.scope, 16) or 'handling'
    if scope ~= 'handling' and scope ~= 'audio' and scope ~= 'all' then
        replyError(cb, 'invalid_reset_scope')
        return
    end

    local payload = Admin.resetVehicleTuning and Admin.resetVehicleTuning(scope)
        or { ok = false, error = 'tuning_unavailable', message = 'Live vehicle tuning is unavailable.' }
    cb(payload)
end)

RegisterNUICallback('cortex-admin:getWeaponAttachments', function(_, cb)
    local payload = Admin.getWeaponAttachmentList and Admin.getWeaponAttachmentList() or { weaponName = '', components = {} }
    cb({
        ok = true,
        weaponName = payload.weaponName or '',
        components = payload.components or {},
    })
end)

RegisterNUICallback('cortex-admin:toggleWeaponAttachment', function(data, cb)
    local h = trimString(data and data.componentHash, 192)
    if not h then
        replyError(cb, 'invalid_component')
        return
    end

    local ok = Admin.toggleWeaponAttachment and Admin.toggleWeaponAttachment(h)
    cb({ ok = ok == true })
end)

RegisterNUICallback('cortex-admin:togglePreviewVehicleExtra', function(data, cb)
    local id = toInteger(data and data.extraId, 1, 99)
    if not id then
        replyError(cb, 'invalid_extra')
        return
    end

    local ok = Admin.togglePreviewVehicleExtra and Admin.togglePreviewVehicleExtra(id)
    cb({ ok = ok == true })
end)

RegisterNUICallback('cortex-admin:setVehiclePreviewShared', function(data, cb)
    local ok = Admin.setPreviewShared and Admin.setPreviewShared(data and data.shared == true)
    cb({ ok = ok == true })
end)

RegisterNUICallback('cortex-admin:spawnPreviewVehicle', function(_, cb)
    CreateThread(function()
        local okCall, ok = pcall(function()
            return Admin.spawnVehicleFromPreview and Admin.spawnVehicleFromPreview() or false
        end)
        if not okCall then
            replyError(cb, 'spawn_failed')
            return
        end
        cb({ ok = ok == true })
    end)
end)

RegisterNUICallback('cortex-admin:setTypingState', function(data, cb)
    if Admin.setTypingLock then
        Admin.setTypingLock(data and data.typing == true)
    end
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:toggle', function(data, cb)
    local actionId = trimString(data and data.id, 96)
    if not actionId or not canInvokeAction(actionId) then
        replyError(cb, 'invalid_action')
        return
    end

    Admin.toggleAction(actionId, data and data.enabled == true)
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:select', function(data, cb)
    local actionId = trimString(data and data.id, 96)
    if not actionId or not canInvokeAction(actionId) then
        replyError(cb, 'invalid_action')
        return
    end

    Admin.selectAction(actionId, data and data.value)
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:favorite', function(data, cb)
    local actionId = trimString(data and data.id, 96)
    if not actionId or not canInvokeAction(actionId) then
        replyError(cb, 'invalid_action')
        return
    end

    toggleFavorite(actionId)
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:updateSetting', function(data, cb)
    local key = trimString(data and data.key, 64)
    if not key then
        replyError(cb, 'invalid_setting')
        return
    end

    local value = sanitizeSetting(key, data and data.value)
    if value == nil then
        replyError(cb, 'invalid_setting_value')
        return
    end

    state.settings[key] = value
    Admin.saveSettings()
    -- Send only settings update
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { settings = state.settings }
    })
    cb({ ok = true })
end)

local freezeState = {}

RegisterNUICallback('cortex-admin:playerAction', function(data, cb)
    local action = trimString(data and data.action, 16)
    local target = toInteger(data and data.target, 1)
    local actionPermissions = {
        ['goto'] = 'player.goto',
        waypoint = 'player.waypoint',
        spectate = 'player.spectate',
        message = 'player.message',
        identifiers = 'player.identifiers',
        kill = 'player.kill',
        kick = 'player.kick',
        ban = 'player.ban',
        freeze = 'player.freeze',
        bring = 'player.bring',
    }
    local actionId = action and actionPermissions[action]
    if not action or not target or not actionId or not canInvokeAction(actionId) then
        replyError(cb, 'invalid_player_action')
        return
    end

    data.action = action
    data.target = target

    if action == 'ban' then
        local rawDuration = data.duration
        local duration = 0
        if rawDuration ~= nil and rawDuration ~= '' then
            duration = toInteger(rawDuration, 0, 525600)
            if duration == nil then
                replyError(cb, 'invalid_ban_duration')
                return
            end
        end
        data.duration = duration
    end

    if action == 'freeze' then
        local current = freezeState[target] or false
        freezeState[target] = not current
        data.enabled = freezeState[target]
    end

    if action == 'waypoint' or action == 'spectate' or action == 'message' or action == 'identifiers' or action == 'kill' then
        TriggerServerEvent('cortex-admin:server:vmenuPlayerAction', data)
    else
        TriggerServerEvent('cortex-admin:server:playerAction', data)
    end
    cb({ ok = true })
end)

-- Resources
RegisterNetEvent('cortex-admin:client:setResources', function(resources)
    state.resources = resources
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { resources = resources }
    })
end)

RegisterNUICallback('cortex-admin:requestResources', function(_, cb)
    TriggerServerEvent('cortex-admin:server:requestResources')
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:requestAddonVehicles', function(_, cb)
    local requested = false
    if type(Admin.requestAddonVehiclesIfNeeded) == 'function' then
        requested = Admin.requestAddonVehiclesIfNeeded(false) == true
    else
        TriggerServerEvent('cortex-admin:server:requestAddonVehicles')
        requested = true
    end
    cb({ ok = true, requested = requested })
end)

RegisterNUICallback('cortex-admin:resourceAction', function(data, cb)
    local action = trimString(data and data.action, 16)
    local name = trimString(data and data.name, 64)
    if not action or not name then
        replyError(cb, 'invalid_resource_action')
        return
    end

    PlaySoundFrontend(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    TriggerServerEvent('cortex-admin:server:resourceAction', {
        action = action,
        name = name,
    })
    cb({ ok = true })
end)

-- Appearance
RegisterNUICallback('cortex-admin:getAppearance', function(_, cb)
    agentDbg('H4', 'nui.lua:getAppearance', 'enter', {})
    local ok, data = pcall(Admin.getPedAppearance)
    if not ok or type(data) ~= 'table' then
        print(('[cortex-admin] WARNING: Failed to build appearance payload: %s'):format(tostring(data)))
        agentDbg('H4', 'nui.lua:getAppearance', 'error', { error = tostring(data) })
        cb(buildEmptyAppearancePayload())
        return
    end

    agentDbg('H4', 'nui.lua:getAppearance', 'exit', {})
    cb(data)
end)

RegisterNUICallback('cortex-admin:setAppearance', function(data, cb)
    if type(data) ~= 'table' then
        replyError(cb, 'invalid_appearance')
        return
    end

    Admin.setPedAppearance(data)
    cb({ ok = true })
end)

-- Vehicle Customization
RegisterNUICallback('cortex-admin:getVehicleCustomization', function(_, cb)
    local permissions = {
        mods = canInvokeAction('vehicle.customMods'),
        colors = canInvokeAction('vehicle.customColors'),
        liveries = canInvokeAction('vehicle.customLiveries'),
        extras = canInvokeAction('vehicle.customExtras'),
        underglow = canInvokeAction('vehicle.customUnderglow'),
        plate = canInvokeAction('vehicle.plateType'),
    }
    if not permissions.mods and not permissions.colors and not permissions.liveries
        and not permissions.extras and not permissions.underglow and not permissions.plate then
        replyError(cb, 'forbidden')
        return
    end

    local data, errorReason = Admin.getVehicleCustomization()
    if type(data) ~= 'table' then
        replyError(cb, errorReason or 'no_vehicle')
        return
    end
    data.ok = true
    data.permissions = permissions
    cb(data)
end)

RegisterNUICallback('cortex-admin:setVehicleCustomization', function(data, cb)
    if type(data) ~= 'table' then
        replyError(cb, 'invalid_vehicle_customization')
        return
    end

    local kind = trimString(data.type, 32)
    local permissionByType = {
        mod = 'vehicle.customMods',
        wheelType = 'vehicle.customMods',
        window = 'vehicle.customMods',
        xenonColor = 'vehicle.customMods',
        color = 'vehicle.customColors',
        paintFinish = 'vehicle.customColors',
        customColor = 'vehicle.customColors',
        tyreSmokeColor = 'vehicle.customColors',
        enveff = 'vehicle.customColors',
        livery = 'vehicle.customLiveries',
        extra = 'vehicle.customExtras',
        neon = 'vehicle.customUnderglow',
        neonColor = 'vehicle.customUnderglow',
        plate = 'vehicle.plateType',
    }
    local actionId = kind and permissionByType[kind] or nil
    if not actionId then
        replyError(cb, 'invalid_customization_type')
        return
    end
    if not canInvokeAction(actionId) then
        replyError(cb, 'forbidden')
        return
    end

    local sanitized = { type = kind }
    if kind == 'mod' then
        sanitized.id = toInteger(data.id, 0, 49)
        if sanitized.id == nil or (data.isToggle ~= nil and type(data.isToggle) ~= 'boolean') then
            replyError(cb, 'invalid_mod')
            return
        end
        sanitized.isToggle = data.isToggle == true
        if sanitized.isToggle then
            if sanitized.id ~= 18 and sanitized.id ~= 20 and sanitized.id ~= 22
                or type(data.enabled) ~= 'boolean' then
                replyError(cb, 'invalid_mod_toggle')
                return
            end
            sanitized.enabled = data.enabled
        else
            sanitized.value = toInteger(data.value, -1, 4096)
            if sanitized.value == nil then
                replyError(cb, 'invalid_mod_value')
                return
            end
        end
    elseif kind == 'color' then
        local colorIds = { primary = true, secondary = true, pearlescent = true, wheel = true, dashboard = true, trim = true }
        sanitized.id = trimString(data.id, 24)
        sanitized.value = toInteger(data.value, 0, 255)
        local allowsChameleon = sanitized.id == 'primary' or sanitized.id == 'secondary'
        local validColor = sanitized.value ~= nil and (sanitized.value <= 160
            or (allowsChameleon and sanitized.value >= 223 and sanitized.value <= 238))
        if not sanitized.id or not colorIds[sanitized.id] or not validColor then
            replyError(cb, 'invalid_color')
            return
        end
    elseif kind == 'paintFinish' then
        sanitized.id = trimString(data.id, 16)
        sanitized.value = toInteger(data.value, 0, 5)
        if (sanitized.id ~= 'primary' and sanitized.id ~= 'secondary') or sanitized.value == nil then
            replyError(cb, 'invalid_paint_finish')
            return
        end
    elseif kind == 'customColor' then
        sanitized.id = trimString(data.id, 16)
        sanitized.enabled = type(data.enabled) == 'boolean' and data.enabled or nil
        if (sanitized.id ~= 'primary' and sanitized.id ~= 'secondary') or sanitized.enabled == nil then
            replyError(cb, 'invalid_custom_color')
            return
        end
        if sanitized.enabled then
            sanitized.value = sanitizeRgb(data.value)
            if not sanitized.value then
                replyError(cb, 'invalid_custom_color')
                return
            end
        end
    elseif kind == 'neonColor' or kind == 'tyreSmokeColor' then
        sanitized.value = sanitizeRgb(data.value)
        if not sanitized.value then
            replyError(cb, 'invalid_rgb')
            return
        end
    elseif kind == 'neon' then
        local neonIds = { front = true, back = true, left = true, right = true, all = true }
        sanitized.id = trimString(data.id, 16)
        if not sanitized.id or not neonIds[sanitized.id] or type(data.value) ~= 'boolean' then
            replyError(cb, 'invalid_neon')
            return
        end
        sanitized.value = data.value
    elseif kind == 'plate' then
        sanitized.value = toInteger(data.value, 0, 12)
        if sanitized.value == nil then replyError(cb, 'invalid_plate'); return end
    elseif kind == 'window' then
        sanitized.value = toInteger(data.value, 0, 6)
        if sanitized.value == nil then replyError(cb, 'invalid_window_tint'); return end
    elseif kind == 'wheelType' then
        sanitized.value = toInteger(data.value, 0, 20)
        if sanitized.value == nil then replyError(cb, 'invalid_wheel_type'); return end
    elseif kind == 'xenonColor' then
        sanitized.value = toInteger(data.value, -1, 255)
        if sanitized.value == nil or (sanitized.value > 12 and sanitized.value ~= 255) then
            replyError(cb, 'invalid_xenon_color')
            return
        end
    elseif kind == 'livery' then
        sanitized.value = toInteger(data.value, -1, 255)
        if sanitized.value == nil then replyError(cb, 'invalid_livery'); return end
    elseif kind == 'extra' then
        sanitized.id = toInteger(data.id, 0, 20)
        sanitized.enabled = type(data.enabled) == 'boolean' and data.enabled or nil
        if sanitized.id == nil or sanitized.enabled == nil then replyError(cb, 'invalid_extra'); return end
    elseif kind == 'enveff' then
        sanitized.value = toFiniteNumber(data.value, 0.0, 1.0)
        if sanitized.value == nil then replyError(cb, 'invalid_enveff'); return end
    end

    local ok, errorReason = Admin.setVehicleCustomization(sanitized)
    if ok ~= true then
        replyError(cb, errorReason or 'customization_failed')
        return
    end
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:getSavedPeds', function(_, cb)
    CreateThread(function()
        agentDbg('H3', 'nui.lua:getSavedPeds', 'enter', {})
        local ok, data = pcall(Admin.getSavedPeds)
        if not ok or type(data) ~= 'table' then
            print(('[cortex-admin] WARNING: Failed to build saved ped list: %s'):format(tostring(data)))
            agentDbg('H3', 'nui.lua:getSavedPeds', 'error', { error = tostring(data) })
            cb({})
            return
        end

        agentDbg('H3', 'nui.lua:getSavedPeds', 'exit', { count = #data })
        cb(data)
    end)
end)

RegisterNUICallback('cortex-admin:getWardrobeShareTargets', function(_, cb)
    if type(Admin.getNearbyWardrobeShareTargets) ~= 'function' then
        replyError(cb, 'wardrobe_share_unavailable')
        return
    end

    CreateThread(function()
        agentDbg('H1', 'nui.lua:getWardrobeShareTargets', 'enter', {})
        local ok, targets = pcall(Admin.getNearbyWardrobeShareTargets)
        if not ok or type(targets) ~= 'table' then
            replyError(cb, 'wardrobe_share_unavailable')
            return
        end
        agentDbg('H1', 'nui.lua:getWardrobeShareTargets', 'exit', { n = type(targets) == 'table' and #targets or -1 })
        cb({
            ok = true,
            targets = targets,
        })
    end)
end)

RegisterNUICallback('cortex-admin:shareWardrobe', function(data, cb)
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

RegisterNUICallback('cortex-admin:acceptWardrobeShare', function(data, cb)
    local shareId = trimString(data and data.shareId, 96)
    if not shareId or type(Admin.acceptWardrobeShare) ~= 'function' then
        replyError(cb, 'invalid_share')
        return
    end

    cb({ ok = Admin.acceptWardrobeShare(shareId) == true })
end)

RegisterNUICallback('cortex-admin:saveWardrobeShare', function(data, cb)
    local shareId = trimString(data and data.shareId, 96)
    if not shareId or type(Admin.saveWardrobeShare) ~= 'function' then
        replyError(cb, 'invalid_share')
        return
    end

    cb({ ok = Admin.saveWardrobeShare(shareId) == true })
end)

RegisterNUICallback('cortex-admin:dismissWardrobeShare', function(data, cb)
    local shareId = trimString(data and data.shareId, 96)
    if not shareId or type(Admin.dismissWardrobeShare) ~= 'function' then
        replyError(cb, 'invalid_share')
        return
    end

    cb({ ok = Admin.dismissWardrobeShare(shareId) == true })
end)

RegisterNUICallback('cortex-admin:getSavedTeleportLocations', function(_, cb)
    if type(Admin.getSavedTeleportLocations) ~= 'function' then
        replyError(cb, 'teleport_locations_unavailable')
        return
    end

    cb(Admin.getSavedTeleportLocations())
end)

RegisterNUICallback('cortex-admin:saveCurrentTeleportLocation', function(data, cb)
    if type(Admin.saveCurrentTeleportLocation) ~= 'function' then
        replyError(cb, 'teleport_locations_unavailable')
        return
    end

    local name = trimString(data and data.name, 64)
    local ok = Admin.saveCurrentTeleportLocation(name)
    cb({ ok = ok == true })
end)

RegisterNUICallback('cortex-admin:loadSavedTeleportLocation', function(data, cb)
    if type(Admin.loadSavedTeleportLocation) ~= 'function' then
        replyError(cb, 'teleport_locations_unavailable')
        return
    end

    local name = trimString(data and data.name, 64)
    local ok = Admin.loadSavedTeleportLocation(name)
    cb({ ok = ok == true })
end)

RegisterNUICallback('cortex-admin:deleteSavedTeleportLocation', function(data, cb)
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

RegisterNUICallback('cortex-admin:requestItems', function(_, cb)
    TriggerServerEvent('cortex-admin:server:getItems')
    cb({ ok = true })
end)

RegisterNetEvent('cortex-admin:client:setItems', function(items)
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { inventoryItems = items or {} }
    })
end)

RegisterNUICallback('cortex-admin:giveItem', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local item = trimString(data and data.item, 64)
    local amount = toInteger(data and data.amount, 1, 10000)
    if not target or not item or not amount then
        replyError(cb, 'invalid_item_request')
        return
    end

    TriggerServerEvent('cortex-admin:server:giveItem', {
        target = target,
        item = item,
        amount = amount,
    })
    cb({ ok = true })
end)

-- ============================================================================
-- GARAGE (QBX / qbx_vehicles)
-- ============================================================================

RegisterNUICallback('cortex-admin:requestGarage', function(_, cb)
    TriggerServerEvent('cortex-admin:server:getPlayerGarage')
    cb({ ok = true })
end)

RegisterNetEvent('cortex-admin:client:setGarageVehicles', function(vehicles)
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { garageVehicles = vehicles or {} }
    })
end)

RegisterNUICallback('cortex-admin:spawnGarageVehicle', function(data, cb)
    local vehicleId = toInteger(data and data.vehicleId, 1)
    if not vehicleId then
        replyError(cb, 'invalid_vehicle')
        return
    end

    TriggerServerEvent('cortex-admin:server:spawnGarageVehicle', {
        vehicleId = vehicleId,
    })
    cb({ ok = true })
end)

-- ============================================================================
-- QBX PLAYER MANAGEMENT NUI CALLBACKS
-- ============================================================================

RegisterNUICallback('cortex-admin:killPlayer', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then replyError(cb, 'invalid_target') return end
    TriggerServerEvent('cortex-admin:server:killPlayer', { target = target })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:revivePlayer', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then replyError(cb, 'invalid_target') return end
    TriggerServerEvent('cortex-admin:server:revivePlayer', { target = target })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:sitInVehicle', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then replyError(cb, 'invalid_target') return end
    TriggerServerEvent('cortex-admin:server:sitInVehicle', { target = target })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:setJob', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local job = trimString(data and data.job, 64)
    local rawGrade = data and data.grade
    local grade = (rawGrade == nil or rawGrade == '') and 0 or toInteger(rawGrade, 0, 99)
    if not target or not job or grade == nil then replyError(cb, 'invalid_job') return end

    TriggerServerEvent('cortex-admin:server:setJob', {
        target = target,
        job = job,
        grade = grade,
    })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:setGang', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local gang = trimString(data and data.gang, 64)
    local rawGrade = data and data.grade
    local grade = (rawGrade == nil or rawGrade == '') and 0 or toInteger(rawGrade, 0, 99)
    if not target or not gang or grade == nil then replyError(cb, 'invalid_gang') return end

    TriggerServerEvent('cortex-admin:server:setGang', {
        target = target,
        gang = gang,
        grade = grade,
    })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:setMoney', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local amount = toInteger(data and data.amount, 0, 1000000000)
    local moneyType = trimString(data and data.moneyType, 32) or 'cash'
    local actionId = trimString(data and data.actionId, 64) or 'player.setCash'
    if not target or amount == nil then replyError(cb, 'invalid_money') return end

    TriggerServerEvent('cortex-admin:server:setMoney', {
        target = target,
        moneyType = moneyType,
        amount = amount,
        actionId = actionId,
    })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:giveMoney', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local amount = toInteger(data and data.amount, 1, 1000000000)
    local moneyType = trimString(data and data.moneyType, 32) or 'cash'
    if not target or not amount then replyError(cb, 'invalid_money') return end

    TriggerServerEvent('cortex-admin:server:giveMoney', {
        target = target,
        moneyType = moneyType,
        amount = amount,
    })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:setMetadata', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local key = trimString(data and data.key, 64)
    local actionId = trimString(data and data.actionId, 64)
    if not target or not key then replyError(cb, 'invalid_metadata') return end

    TriggerServerEvent('cortex-admin:server:setMetadata', {
        target = target,
        key = key,
        value = data and data.value,
        actionId = actionId,
    })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:openInventory', function(data, cb)
    local target = toInteger(data and data.target, 1)
    if not target then replyError(cb, 'invalid_target') return end
    TriggerServerEvent('cortex-admin:server:openInventory', { target = target })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:setRoutingBucket', function(data, cb)
    local target = toInteger(data and data.target, 1)
    local bucket = toInteger(data and data.bucket, 0, 65535)
    if not target or bucket == nil then replyError(cb, 'invalid_bucket') return end

    TriggerServerEvent('cortex-admin:server:setRoutingBucket', {
        target = target,
        bucket = bucket,
    })
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:adminCar', function(_, cb)
    TriggerServerEvent('cortex-admin:server:adminCar')
    cb({ ok = true })
end)

RegisterNUICallback('cortex-admin:pullStash', function(data, cb)
    local stash = trimString(data and data.stash, 80)
    if not stash then replyError(cb, 'invalid_stash') return end
    TriggerServerEvent('cortex-admin:server:pullStash', { stash = stash })
    cb({ ok = true })
end)

-- ============================================================================
-- QBX CLIENT-SIDE EVENT HANDLERS
-- ============================================================================

RegisterNetEvent('cortex-admin:client:killPed', function()
    if not EsAdminClientSecurity.isServerOrigin(source) then return end
    local ped = PlayerPedId()
    SetEntityHealth(ped, 0)
end)

RegisterNetEvent('cortex-admin:client:revivePed', function()
    if not EsAdminClientSecurity.isServerOrigin(source) then return end
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

RegisterNetEvent('cortex-admin:client:sitInVehicle', function(netId)
    if not EsAdminClientSecurity.isServerOrigin(source) then return end
    netId = toInteger(netId, 1, 65535)
    if not netId then return end
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
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

RegisterNetEvent('cortex-admin:client:getVehicleProps', function()
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

    TriggerServerEvent('cortex-admin:server:adminCarSave', {
        model = model,
        props = props,
    })
end)

RegisterNUICallback('cortex-admin:deleteSavedPed', function(data, cb)
    if not data then
        replyError(cb, 'invalid_entry')
        return
    end

    local ref = (data and data.entry) or data
    CreateThread(function()
        local ok = pcall(Admin.deleteSavedPed, ref)
        cb({ ok = ok == true })
    end)
end)

RegisterNUICallback('cortex-admin:renameSavedPed', function(data, cb)
    local newName = trimString(data and data.newName, 64)
    if not data or not newName then
        replyError(cb, 'invalid_name')
        return
    end

    local entry = (data and data.entry) or data
    CreateThread(function()
        local ok = pcall(Admin.renameSavedPed, entry, newName)
        cb({ ok = ok == true })
    end)
end)

RegisterNUICallback('cortex-admin:cloneSavedPed', function(data, cb)
    local entry = (data and data.entry) or data
    local fallbackName = entry and entry.name and (entry.name .. '_clone') or nil
    local newName = trimString(data and data.newName, 64) or trimString(fallbackName, 64)
    if not entry or not newName then
        replyError(cb, 'invalid_name')
        return
    end

    CreateThread(function()
        local ok = pcall(Admin.cloneSavedPed, entry, newName)
        cb({ ok = ok == true })
    end)
end)

RegisterNUICallback('cortex-admin:importVmenuSavedPeds', function(_, cb)
    if type(Admin.importVmenuSavedPeds) ~= 'function' then
        replyError(cb, 'import_unavailable')
        return
    end

    CreateThread(function()
        local okCall, ok, result = pcall(Admin.importVmenuSavedPeds)
        if not okCall then
            print(('[cortex-admin] WARNING: vMenu ped import crashed: %s'):format(tostring(ok)))
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

RegisterNUICallback('cortex-admin:getVmenuMigrationSnapshot', function(_, cb)
    if not canInvokeAction('migration.read') then
        replyError(cb, 'forbidden')
        return
    end
    if type(Admin.getVmenuMigrationSnapshot) ~= 'function' then
        replyError(cb, 'migration_unavailable')
        return
    end

    CreateThread(function()
        agentDbg('H3', 'nui.lua:getVmenuMigrationSnapshot', 'enter', {})
        local ok, snap = pcall(Admin.getVmenuMigrationSnapshot)
        if not ok or type(snap) ~= 'table' then
            print(('[cortex-admin] WARNING: Failed to build vMenu migration snapshot: %s'):format(tostring(snap)))
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

RegisterNUICallback('cortex-admin:getVmenuImportedConfiguration', function(_, cb)
    if type(Admin.getVmenuImportedConfig) ~= 'function' or not canInvokeAction('migration.read') then
        replyError(cb, 'forbidden')
        return
    end

    local config = Admin.getVmenuImportedConfig()
    local categories = type(Admin.getVmenuImportedCategories) == 'function' and Admin.getVmenuImportedCategories() or {}
    local function sampleList(entries)
        local sample = {}
        if type(entries) ~= 'table' then return sample end
        for index = 1, math.min(#entries, 8) do
            local entry = entries[index]
            local value = type(entry) == 'string' and entry
                or type(entry) == 'table' and (entry.name or entry.label or entry.model or entry.key)
                or nil
            value = trimString(value, 96)
            if value then sample[#sample + 1] = value end
        end
        return sample
    end
    local function groupSummary(entries)
        return {
            count = type(entries) == 'table' and #entries or 0,
            sample = sampleList(entries),
        }
    end
    local function mapSummary(entries)
        local keys = {}
        local count = 0
        if type(entries) == 'table' then
            for key in pairs(entries) do
                count = count + 1
                local clean = trimString(type(key) == 'string' and key or tostring(key), 96)
                if clean and #keys < 8 then keys[#keys + 1] = clean end
            end
        end
        table.sort(keys)
        return { count = count, sample = keys }
    end

    local addons = type(config.addons) == 'table' and config.addons or {}
    local whitelists = type(config.modelWhitelists) == 'table' and config.modelWhitelists or {}
    local locations = type(config.locations) == 'table' and config.locations or {}
    local tattooList = type(config.tattoos) == 'table' and config.tattoos or {}
    local domainPayload = {
        addons = {
            vehicles = groupSummary(addons.vehicles),
            peds = groupSummary(addons.peds),
            weapons = groupSummary(addons.weapons),
            components = groupSummary(addons.weapon_components),
        },
        extras = mapSummary(config.extras),
        locations = {
            teleports = groupSummary(locations.teleports),
            blips = groupSummary(locations.blips),
        },
        modelWhitelists = {
            vehicles = groupSummary(whitelists.whitelistedvehicle),
            peds = groupSummary(whitelists.whitelistedpeds),
            weapons = groupSummary(whitelists.whitelistedweapons),
        },
        tattoos = groupSummary(tattooList),
    }

    cb({
        ok = true,
        domains = domainPayload,
        categories = {
            peds = groupSummary(type(categories.peds) == 'table' and categories.peds or {}),
            vehicles = groupSummary(type(categories.vehicles) == 'table' and categories.vehicles or {}),
        },
    })
end)

RegisterNUICallback('cortex-admin:getBanList', function(data, cb)
    if type(Admin.getBanList) ~= 'function' or not canInvokeAction('player.viewBans') then
        replyError(cb, 'forbidden')
        return
    end
    local query = trimString(data and data.query, 64) or ''
    local offset = toInteger(data and data.offset, 0, 100000) or 0
    local limit = toInteger(data and data.limit, 1, 100) or 50
    CreateThread(function()
        local ok, page = pcall(Admin.getBanList, { query = query, offset = offset, limit = limit })
        if not ok or type(page) ~= 'table' then
            cb({ ok = false, error = ok and 'timeout' or 'exception', records = {} })
            return
        end
        cb(page)
    end)
end)

RegisterNUICallback('cortex-admin:unban', function(data, cb)
    local banId = trimString(data and data.id, 96)
    if not banId or type(Admin.unbanPlayer) ~= 'function' or not canInvokeAction('player.unban') then
        replyError(cb, 'forbidden')
        return
    end
    CreateThread(function()
        local ok, result = pcall(Admin.unbanPlayer, banId)
        if not ok or type(result) ~= 'table' then
            cb({ ok = false, error = ok and 'timeout' or 'exception' })
            return
        end
        cb(result)
    end)
end)

RegisterNUICallback('cortex-admin:importVmenuMigrationData', function(_, cb)
    if not canInvokeAction('migration.import') then
        replyError(cb, 'forbidden')
        return
    end
    if type(Admin.importVmenuMigrationData) ~= 'function' then
        replyError(cb, 'migration_unavailable')
        return
    end

    CreateThread(function()
        local okCall, ok, result = pcall(Admin.importVmenuMigrationData)
        if not okCall then
            print(('[cortex-admin] WARNING: vMenu migration import crashed: %s'):format(tostring(ok)))
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
