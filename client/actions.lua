local Admin = EsAdmin
local state = Admin.state
local getHeadBlend
local applyHeadBlend
local applyPedOverlay

Admin.debugTrace = Admin.debugTrace or function() end

function getPed()
    return PlayerPedId()
end

function notify(type, message)
    Admin.notify(type, message)
end

local function currentUnixTime()
    local timestamp = GetCloudTimeAsInt()
    if type(timestamp) ~= 'number' or timestamp ~= timestamp or timestamp < 0 then
        return 0
    end
    return math.floor(timestamp)
end

local function modelAuthorizationError(reason)
    if reason == 'model_forbidden' then return 'Your ACE permissions do not allow that whitelisted model.' end
    if reason == 'forbidden' then return 'You do not have permission to use that model action.' end
    if reason == 'rate_limited' then return 'Model authorization is being requested too quickly. Try again in a moment.' end
    if reason == 'timeout' then return 'Model authorization timed out. Try again.' end
    return 'The server could not authorize that model.'
end

local function authorizeModel(kind, model, actionId, silent)
    if type(Admin.authorizeVmenuModel) ~= 'function' then
        if not silent then notify('error', 'Server model authorization is unavailable.') end
        return false, 'unavailable'
    end
    local allowed, reason, token = Admin.authorizeVmenuModel(kind, model, actionId)
    if not allowed and not silent then notify('error', modelAuthorizationError(reason)) end
    return allowed == true, reason, token
end

local function authorizeModelBatch(kind, models, actionId, silent)
    if type(Admin.authorizeVmenuModels) ~= 'function' then
        if not silent then notify('error', 'Server model authorization is unavailable.') end
        return nil, 'unavailable'
    end
    local result = Admin.authorizeVmenuModels(kind, models, actionId)
    if type(result) ~= 'table' or result.ok ~= true or type(result.allowed) ~= 'table' then
        local reason = type(result) == 'table' and result.error or 'unavailable'
        if not silent then notify('error', modelAuthorizationError(reason)) end
        return nil, reason
    end
    return result.allowed, result.error, result.token
end

function ensureVehicle()
    local ped = getPed()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        notify('error', 'You are not in a vehicle.')
        return nil
    end
    return vehicle
end

function parseNumber(value)
    local num = tonumber(value)
    if not num then
        return nil
    end
    return num
end

function trimString(value)
    if type(value) ~= 'string' then
        return nil
    end

    value = value:match('^%s*(.-)%s*$')
    if value == '' then
        return nil
    end

    return value
end

function normalizeWeatherCommandArg(value)
    local weatherType = trimString(value)
    if not weatherType or not weatherType:match('^[%w_]+$') then
        return nil
    end

    return string.upper(weatherType)
end

function copyToClipboard(text)
    Admin.copyToClipboard(text)
end

function buildCoordClipboardText(format)
    local coords = GetEntityCoords(getPed())
    local heading = GetEntityHeading(getPed())

    if format == 'vector3' then
        return ('vector3(%.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z), 'vector3'
    end

    return ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(coords.x, coords.y, coords.z, heading), 'vector4'
end

local MIN_RECORDING_DURATION_MS = 3000

local recordingState = {
    startedAt = 0,
}

function clearRecordingState()
    recordingState.startedAt = 0
end

function closeMenuForDevCapture()
    if not state.open or not Admin.setOpen then
        return
    end

    Admin.setOpen(false)
    Wait(75)
end

function setToggle(id, enabled)
    state.toggles[id] = enabled
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { toggles = state.toggles }
    })
end

function kvpKey(prefix, name)
    return ('%s%s'):format(prefix, name)
end

function loadKvpJson(key, fallback)
    local raw = GetResourceKvpString(key)
    if not raw or raw == '' then
        return fallback
    end
    
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then
        return decoded
    end
    
    return fallback
end

function saveKvpJson(key, data)
    if not key or key == '' then
        print('[cortex-admin] ERROR: saveKvpJson called with empty key')
        return false
    end
    
    local ok, encoded = pcall(json.encode, data)
    if not ok then
        print('[cortex-admin] ERROR: Failed to encode data for key: ' .. key)
        return false
    end
    
    SetResourceKvp(key, encoded)
    print(('[cortex-admin] Saved KVP: %s (%d bytes)'):format(key, #encoded))
    return true
end

local C = {
    MP_PED_KEY_PREFIX = 'mp_ped_',
    MP_PED_SOURCE_ES_ADMIN = 'cortex-admin',
    MP_PED_SOURCE_VMENU = 'vmenu',
    MODEL_HASH_MP_M = joaat('mp_m_freemode_01'),
    MODEL_HASH_MP_F = joaat('mp_f_freemode_01'),
    LAST_PED_NAME_KEY = 'cortex-admin_last_ped',
    LAST_PED_SOURCE_KEY = 'cortex-admin_last_ped_source',
    LAST_PED_SOURCE_REF_KEY = 'cortex-admin_last_ped_source_key',
    DEFAULT_PED_SOURCE_KEY = 'cortex-admin_default_ped_source',
    DEFAULT_PED_SOURCE_REF_KEY = 'cortex-admin_default_ped_source_key',
    TELEPORT_LOCATIONS_KEY = 'cortex-admin_teleport_locations',
    WEAPON_LOADOUTS_KEY = 'cortex-admin_weapon_loadouts',
    PERSONAL_VEHICLES_KEY = 'cortex-admin_personal_vehicles_v2',
    PERSONAL_VEHICLES_LEGACY_KEY = 'cortex-admin_personal_vehicles',
    VMENU_VEHICLE_KEY_PREFIX = 'veh_',
    PERSONAL_VEHICLE_SOURCE_ES_ADMIN = 'cortex-admin',
    PERSONAL_VEHICLE_SOURCE_VMENU = 'vmenu',
}

local PED_OVERLAY_MAP = {
    { key = 'blemishes', id = 0, colorType = 0 },
    { key = 'beard', id = 1, colorType = 1 },
    { key = 'eyebrows', id = 2, colorType = 1 },
    { key = 'ageing', id = 3, colorType = 0 },
    { key = 'makeup', id = 4, colorType = 2 },
    { key = 'blush', id = 5, colorType = 2 },
    { key = 'complexion', id = 6, colorType = 0 },
    { key = 'sunDamage', id = 7, colorType = 0 },
    { key = 'lipstick', id = 8, colorType = 2 },
    { key = 'molesFreckles', id = 9, colorType = 0 },
    { key = 'chestHair', id = 10, colorType = 1 },
    { key = 'bodyBlemishes', id = 11, colorType = 0 },
}

local LEGACY_FACE_FEATURE_FIELDS = {
    [0] = { 'noseWidth' },
    [1] = { 'nosePeakHeight', 'nosePeakHight' },
    [2] = { 'nosePeakLength', 'nosePeakLenght' },
    [3] = { 'noseBoneHeight', 'noseBoneHigh' },
    [4] = { 'nosePeakLowering' },
    [5] = { 'noseBoneTwist' },
    [6] = { 'eyebrowHeight', 'eyeBrownHigh', 'eyebrowsHigh' },
    [7] = { 'eyebrowForward', 'eyeBrownForward', 'eyebrowsForward' },
    [8] = { 'cheekboneHeight', 'cheeksBoneHigh', 'cheekBonesHigh' },
    [9] = { 'cheekboneWidth', 'cheeksBoneWidth', 'cheekBonesWidth' },
    [10] = { 'cheekWidth', 'cheeksWidth' },
    [11] = { 'eyesOpening', 'eyeOpening' },
    [12] = { 'lipsThickness', 'lipThickness' },
    [13] = { 'jawBoneWidth' },
    [14] = { 'jawBoneBackLength' },
    [15] = { 'chinBoneLowering', 'chimpBoneLowering' },
    [16] = { 'chinBoneLength', 'chimpBoneLength', 'chimpBoneLenght' },
    [17] = { 'chinBoneWidth', 'chimpBoneWidth' },
    [18] = { 'chinHole', 'chimpHole' },
    [19] = { 'neckThickness' },
}

local WARDROBE_SHARE_COMPONENT_BLACKLIST = {
    [0] = true,
    [2] = true,
}

function isFreemodeModel(modelHash)
    return modelHash == C.MODEL_HASH_MP_M or modelHash == C.MODEL_HASH_MP_F
end

function isFreemodePed(ped)
    return isFreemodeModel(GetEntityModel(ped))
end

function sanitizeJsonValue(value, depth)
    if depth > 12 then
        return nil
    end

    local valueType = type(value)
    if valueType == 'nil' then
        return nil
    end

    if valueType == 'boolean' or valueType == 'string' then
        return value
    end

    if valueType == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then
            return 0
        end
        return value
    end

    if valueType ~= 'table' then
        return nil
    end

    local output = {}
    for key, nestedValue in pairs(value) do
        local keyType = type(key)
        if keyType == 'number' or keyType == 'string' then
            local sanitizedValue = sanitizeJsonValue(nestedValue, depth + 1)
            if sanitizedValue ~= nil then
                output[key] = sanitizedValue
            end
        end
    end

    return output
end

function cloneJsonTable(data)
    if type(data) ~= 'table' then
        return nil
    end

    local ok, encoded = pcall(json.encode, data)
    if ok and type(encoded) == 'string' and encoded ~= '' then
        ok, data = pcall(json.decode, encoded)
        if ok and type(data) == 'table' then
            return data
        end
    end

    local sanitized = sanitizeJsonValue(data, 0)
    if type(sanitized) == 'table' then
        return sanitized
    end

    return nil
end

function loadSavedTeleportLocationsRaw()
    local locations = loadKvpJson(C.TELEPORT_LOCATIONS_KEY, {})
    if type(locations) ~= 'table' then
        return {}
    end
    return locations
end

function buildSavedTeleportLocationList()
    local raw = loadSavedTeleportLocationsRaw()
    local list = {}

    for name, loc in pairs(raw) do
        if type(name) == 'string' and type(loc) == 'table' and tonumber(loc.x) and tonumber(loc.y) and tonumber(loc.z) then
            list[#list + 1] = {
                name = name,
                x = tonumber(loc.x),
                y = tonumber(loc.y),
                z = tonumber(loc.z),
                h = tonumber(loc.h) or 0.0,
            }
        end
    end

    table.sort(list, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    return list
end

function loadWeaponLoadoutsRaw()
    local loadouts = loadKvpJson(C.WEAPON_LOADOUTS_KEY, {})
    if type(loadouts) ~= 'table' then
        return {}
    end
    return loadouts
end

function isTableEmpty(data)
    return type(data) ~= 'table' or next(data) == nil
end

function normalizeSavedPedKey(keyOrName)
    if type(keyOrName) ~= 'string' or keyOrName == '' then
        return nil, nil
    end

    if keyOrName:sub(1, #C.MP_PED_KEY_PREFIX) == C.MP_PED_KEY_PREFIX then
        return keyOrName, keyOrName:sub(#C.MP_PED_KEY_PREFIX + 1)
    end

    if keyOrName:sub(1, #'mp_character_category_') == 'mp_character_category_' then
        local name = keyOrName:sub(#'mp_character_category_' + 1)
        if name == '' then return nil, nil end
        return kvpKey(C.MP_PED_KEY_PREFIX, name), name
    end

    return kvpKey(C.MP_PED_KEY_PREFIX, keyOrName), keyOrName
end

function callVmenuBridge(method, ...)
    if GetResourceState('vMenu') ~= 'started' then
        return false, 'vMenu is not running'
    end

    local okBridge, bridge = pcall(function()
        return exports['vMenu']
    end)
    if not okBridge or not bridge then
        return false, 'vMenu bridge unavailable'
    end

    local okExport, exportFn = pcall(function()
        return bridge[method]
    end)
    if not okExport then
        return false, exportFn
    end

    if type(exportFn) ~= 'function' then
        return false, ('vMenu bridge export missing: %s'):format(method)
    end

    local ok, result = pcall(exportFn, ...)
    if not ok then
        return false, result
    end

    return true, result
end

local vmenuFallbackSnapshotCache = {
    expiresAt = 0,
    data = nil,
}

local pendingVmenuFallbackRequests = {}
local pendingWardrobeShareTargetRequests = {}

RegisterNetEvent('cortex-admin:client:receiveVmenuKvpSnapshot', function(requestId, payload)
    local pending = pendingVmenuFallbackRequests[requestId]
    if not pending then
        return
    end

    pendingVmenuFallbackRequests[requestId] = nil
    pending:resolve(payload)
end)

RegisterNetEvent('cortex-admin:client:receiveWardrobeShareTargets', function(requestId, payload)
    local pending = pendingWardrobeShareTargetRequests[requestId]
    if not pending then
        return
    end

    pendingWardrobeShareTargetRequests[requestId] = nil
    pending:resolve(payload)
end)

function invalidateVmenuFallbackSnapshot()
    vmenuFallbackSnapshotCache.expiresAt = 0
    vmenuFallbackSnapshotCache.data = nil
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == 'vMenu' then
        invalidateVmenuFallbackSnapshot()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == 'vMenu' then
        invalidateVmenuFallbackSnapshot()
    end
end)

function getVmenuFallbackSnapshot(forceRefresh)
    if not Config.VmenuFallback or Config.VmenuFallback.enabled == false then
        return nil
    end

    local now = GetGameTimer()
    local cacheMs = tonumber(Config.VmenuFallback.cacheMs) or 5000
    if cacheMs < 0 then
        cacheMs = 5000
    end

    if not forceRefresh and vmenuFallbackSnapshotCache.data and now < vmenuFallbackSnapshotCache.expiresAt then
        return vmenuFallbackSnapshotCache.data
    end

    local requestId = ('%s:%d:%d'):format(GetCurrentResourceName(), now, math.random(1000, 9999))
    local pending = promise.new()
    pendingVmenuFallbackRequests[requestId] = pending

    TriggerServerEvent('cortex-admin:server:requestVmenuKvpSnapshot', requestId, forceRefresh == true)

    SetTimeout(tonumber(Config.VmenuFallback.requestTimeoutMs) or 2500, function()
        if pendingVmenuFallbackRequests[requestId] then
            pendingVmenuFallbackRequests[requestId] = nil
            pending:resolve(nil)
        end
    end)

    Admin.debugTrace('vmenu_snapshot', 'before_await', { requestId = requestId })
    local payload = Citizen.Await(pending)
    Admin.debugTrace('vmenu_snapshot', 'after_await', { ok = type(payload) == 'table' })
    if type(payload) ~= 'table' then
        return nil
    end

    vmenuFallbackSnapshotCache.data = payload
    vmenuFallbackSnapshotCache.expiresAt = now + cacheMs
    return payload
end

function ensureVmenuWriteBridge(actionLabel)
    if GetResourceState('vMenu') == 'started' then
        return true
    end

    notify('error', ('vMenu must be running to %s vMenu saves.'):format(actionLabel or 'modify'))
    return false
end

function getCurrentHairColors(ped)
    local hairColor, hairHighlightColor = 0, 0
    if GetPedHairColors then
        hairColor, hairHighlightColor = GetPedHairColors(ped)
    end
    return hairColor or 0, hairHighlightColor or 0
end

function getWardrobeShareTargetSnapshot()
    local requestId = ('%s:wardrobe:%d:%d'):format(GetCurrentResourceName(), GetGameTimer(), math.random(1000, 9999))
    local pending = promise.new()
    pendingWardrobeShareTargetRequests[requestId] = pending

    TriggerServerEvent('cortex-admin:server:requestWardrobeShareTargets', requestId)

    SetTimeout(2000, function()
        if pendingWardrobeShareTargetRequests[requestId] then
            pendingWardrobeShareTargetRequests[requestId] = nil
            pending:resolve(nil)
        end
    end)

    Admin.debugTrace('wardrobe_targets', 'before_await', { requestId = requestId })
    local payload = Citizen.Await(pending)
    Admin.debugTrace('wardrobe_targets', 'after_await', { ok = type(payload) == 'table' })
    return WardrobeSharePolicy.validateTargetSnapshot(payload)
end

function clampInteger(value, minValue, maxValue)
    local numeric = tonumber(value)
    if not numeric then
        numeric = minValue or 0
    end

    numeric = math.floor(numeric)

    if minValue ~= nil then
        numeric = math.max(minValue, numeric)
    end

    if maxValue ~= nil then
        numeric = math.min(maxValue, numeric)
    end

    return numeric
end

function resolveComponentVariation(ped, componentId, drawable, texture)
    local componentIndex = tonumber(componentId)
    if not componentIndex then
        return nil, nil, false
    end

    local drawableCount = GetNumberOfPedDrawableVariations(ped, componentIndex) or 0
    if drawableCount <= 0 then
        return nil, nil, true
    end

    local rawDrawable = tonumber(drawable)
    local rawTexture = tonumber(texture)
    local safeDrawable = clampInteger(drawable, 0, drawableCount - 1)
    local textureCount = GetNumberOfPedTextureVariations(ped, componentIndex, safeDrawable) or 0
    local safeTexture = textureCount > 0 and clampInteger(texture, 0, textureCount - 1) or 0
    local adjusted = safeDrawable ~= (rawDrawable or 0) or safeTexture ~= (rawTexture or 0)

    if IsPedComponentVariationValid then
        if not IsPedComponentVariationValid(ped, componentIndex, safeDrawable, safeTexture) then
            adjusted = true

            if safeTexture ~= 0 and IsPedComponentVariationValid(ped, componentIndex, safeDrawable, 0) then
                safeTexture = 0
            elseif IsPedComponentVariationValid(ped, componentIndex, 0, 0) then
                safeDrawable = 0
                safeTexture = 0
            else
                return nil, nil, true
            end
        end
    end

    return safeDrawable, safeTexture, adjusted
end

function resolvePropVariation(ped, propId, drawable, texture)
    local propIndex = tonumber(propId)
    if not propIndex then
        return nil, nil, false
    end

    local rawDrawable = tonumber(drawable)
    if rawDrawable == nil or rawDrawable < 0 then
        return -1, 0, false
    end

    local drawableCount = GetNumberOfPedPropDrawableVariations(ped, propIndex) or 0
    if drawableCount <= 0 then
        return -1, 0, true
    end

    local safeDrawable = clampInteger(rawDrawable, 0, drawableCount - 1)
    local textureCount = GetNumberOfPedPropTextureVariations(ped, propIndex, safeDrawable) or 0
    local safeTexture = textureCount > 0 and clampInteger(texture, 0, textureCount - 1) or 0
    local adjusted = safeDrawable ~= rawDrawable or safeTexture ~= (tonumber(texture) or 0)

    return safeDrawable, safeTexture, adjusted
end

function setPedComponent(ped, componentId, drawable, texture)
    local componentIndex = tonumber(componentId)
    local safeDrawable, safeTexture, adjusted = resolveComponentVariation(ped, componentId, drawable, texture)
    if safeDrawable == nil or componentIndex == nil then
        print(('[cortex-admin] Skipped invalid component variation component=%s drawable=%s texture=%s'):format(componentId, drawable, texture))
        return
    end

    if adjusted then
        print(('[cortex-admin] Adjusted component variation component=%s drawable=%s->%s texture=%s->%s'):format(
            componentId,
            tostring(drawable),
            tostring(safeDrawable),
            tostring(texture),
            tostring(safeTexture)
        ))
    end

    SetPedComponentVariation(ped, componentIndex, safeDrawable, safeTexture, 2)
end

function setPedProp(ped, propId, drawable, texture)
    local propIndex = tonumber(propId)
    local safeDrawable, safeTexture, adjusted = resolvePropVariation(ped, propId, drawable, texture)
    if safeDrawable == nil or propIndex == nil then
        print(('[cortex-admin] Skipped invalid prop variation prop=%s drawable=%s texture=%s'):format(propId, drawable, texture))
        return
    end

    if safeDrawable < 0 then
        ClearPedProp(ped, propIndex)
    else
        if adjusted then
            print(('[cortex-admin] Adjusted prop variation prop=%s drawable=%s->%s texture=%s->%s'):format(
                propId,
                tostring(drawable),
                tostring(safeDrawable),
                tostring(texture),
                tostring(safeTexture)
            ))
        end

        SetPedPropIndex(ped, propIndex, safeDrawable, safeTexture, true)
    end
end

function applySharedWardrobeData(ped, data)
    if type(data) ~= 'table' then
        return false
    end

    local drawableVariations = data.DrawableVariations
    local propVariations = data.PropVariations
    if type(drawableVariations) ~= 'table' or type(propVariations) ~= 'table' then
        return false
    end

    local clothes = drawableVariations.clothes
    if type(clothes) == 'table' then
        for componentId, values in pairs(clothes) do
            local id = tonumber(componentId)
            if id and not WARDROBE_SHARE_COMPONENT_BLACKLIST[id] and type(values) == 'table' then
                setPedComponent(ped, id, values[1], values[2])
            end
        end
    end

    local props = propVariations.props
    if type(props) == 'table' then
        for propId, values in pairs(props) do
            if type(values) == 'table' then
                setPedProp(ped, tonumber(propId), values[1], values[2])
            end
        end
    end

    return true
end

function buildDefaultHeadBlend()
    return {
        shapeFirstID = 0,
        shapeSecondID = 0,
        shapeThirdID = 0,
        skinFirstID = 0,
        skinSecondID = 0,
        skinThirdID = 0,
        shapeMix = 0.5,
        skinMix = 0.5,
        thirdMix = 0.0,
    }
end

function buildEmptyAppearanceData(modelHash)
    local resolvedModel = tonumber(modelHash) or 0
    return {
        components = {},
        props = {},
        maxComponents = {},
        maxProps = {},
        model = resolvedModel,
        isFreemode = isFreemodeModel(resolvedModel),
        features = {},
        headBlend = buildDefaultHeadBlend(),
        hairColor = 0,
        hairHighlightColor = 0,
        eyeColor = 0,
        overlays = {},
    }
end

function coerceWholeNumber(value, fallback)
    local number = tonumber(value)
    if not number or number ~= number then
        return fallback
    end

    return math.floor(number)
end

function coerceNumber(value, fallback)
    local number = tonumber(value)
    if not number or number ~= number then
        return fallback
    end

    return number
end

function safeNativeWholeNumber(fn, fallback, ...)
    local ok, value = pcall(fn, ...)
    if not ok then
        return fallback
    end

    return coerceWholeNumber(value, fallback)
end

function safeNativeNumber(fn, fallback, ...)
    local ok, value = pcall(fn, ...)
    if not ok then
        return fallback
    end

    return coerceNumber(value, fallback)
end

function readPedHairColorsSafely(ped)
    if type(GetPedHairColors) ~= 'function' then
        return 0, 0
    end

    local ok, hairColor, hairHighlightColor = pcall(GetPedHairColors, ped)
    if not ok then
        return 0, 0
    end

    return coerceWholeNumber(hairColor, 0), coerceWholeNumber(hairHighlightColor, 0)
end

function readPedHeadBlendSafely(ped)
    local fallback = buildDefaultHeadBlend()
    local ok, hasData, shapeFirst, shapeSecond, shapeThird, skinFirst, skinSecond, skinThird, shapeMix, skinMix, thirdMix = pcall(GetPedHeadBlendData, ped)
    if not ok or not hasData then
        return fallback, false
    end

    return {
        shapeFirstID = coerceWholeNumber(shapeFirst, 0),
        shapeSecondID = coerceWholeNumber(shapeSecond, 0),
        shapeThirdID = coerceWholeNumber(shapeThird, 0),
        skinFirstID = coerceWholeNumber(skinFirst, 0),
        skinSecondID = coerceWholeNumber(skinSecond, 0),
        skinThirdID = coerceWholeNumber(skinThird, 0),
        shapeMix = coerceNumber(shapeMix, 0.5),
        skinMix = coerceNumber(skinMix, 0.5),
        thirdMix = coerceNumber(thirdMix, 0.0),
    }, true
end

function readPedOverlaySafely(ped, overlayId)
    local ok, success, style, colourType, firstColour, secondColour, overlayOpacity = pcall(GetPedHeadOverlayData, ped, overlayId)
    if not ok or not success then
        return nil
    end

    local maxStyles = 0
    if type(GetNumHeadOverlayValues) == 'function' then
        local okMax, value = pcall(GetNumHeadOverlayValues, overlayId)
        if okMax then
            maxStyles = math.max(0, coerceWholeNumber(value, 0))
        end
    end

    return {
        value = coerceWholeNumber(style, 0),
        opacity = coerceNumber(overlayOpacity, 0.0),
        colorType = math.max(0, coerceWholeNumber(colourType, 0)),
        color = math.max(0, coerceWholeNumber(firstColour, 0)),
        highlight = math.max(0, coerceWholeNumber(secondColour, 0)),
        maxStyles = maxStyles,
    }
end

Admin.getPedAppearance = function()
    Admin.debugTrace('ped_appearance', 'enter', {})
    local ped = getPed()
    if ped == 0 or not DoesEntityExist(ped) then
        Admin.debugTrace('ped_appearance', 'invalid_ped', {})
        return buildEmptyAppearanceData()
    end

    local data = buildEmptyAppearanceData(safeNativeWholeNumber(GetEntityModel, 0, ped))

    for i = 0, 11 do
        local drawable = math.max(0, safeNativeWholeNumber(GetPedDrawableVariation, 0, ped, i))
        local texture = math.max(0, safeNativeWholeNumber(GetPedTextureVariation, 0, ped, i))
        data.components[tostring(i)] = {
            drawable = drawable,
            texture = texture
        }
        data.maxComponents[tostring(i)] = {
            drawables = math.max(0, safeNativeWholeNumber(GetNumberOfPedDrawableVariations, 0, ped, i)),
            textures = math.max(0, safeNativeWholeNumber(GetNumberOfPedTextureVariations, 0, ped, i, drawable))
        }
    end
    Admin.debugTrace('ped_appearance', 'after_component_loop', {})

    for i = 0, 7 do
        local currentPropDrawable = safeNativeWholeNumber(GetPedPropIndex, -1, ped, i)
        data.props[tostring(i)] = {
            drawable = currentPropDrawable,
            texture = currentPropDrawable >= 0 and math.max(0, safeNativeWholeNumber(GetPedPropTextureIndex, 0, ped, i)) or 0
        }
        data.maxProps[tostring(i)] = {
            drawables = math.max(0, safeNativeWholeNumber(GetNumberOfPedPropDrawableVariations, 0, ped, i)),
            textures = currentPropDrawable >= 0 and math.max(0, safeNativeWholeNumber(GetNumberOfPedPropTextureVariations, 0, ped, i, currentPropDrawable)) or 0
        }
    end
    Admin.debugTrace('ped_appearance', 'after_prop_loop', {})

    if data.isFreemode then
        for i = 0, 19 do
            data.features[tostring(i)] = safeNativeNumber(GetPedFaceFeature, 0.0, ped, i)
        end

        data.headBlend = readPedHeadBlendSafely(ped)
        data.hairColor, data.hairHighlightColor = readPedHairColorsSafely(ped)
        data.eyeColor = math.max(0, safeNativeWholeNumber(GetPedEyeColor, 0, ped))

        local overlaysToTrack = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }
        for _, id in ipairs(overlaysToTrack) do
            local overlayData = readPedOverlaySafely(ped, id)
            if overlayData then
                data.overlays[tostring(id)] = {
                    style = overlayData.value,
                    opacity = overlayData.opacity,
                    colorType = overlayData.colorType,
                    color = overlayData.color,
                    secondColor = overlayData.highlight,
                    maxStyles = overlayData.maxStyles,
                }
            end
        end
    end

    Admin.debugTrace('ped_appearance', 'exit', { isFreemode = data.isFreemode == true })
    return data
end

Admin.setPedAppearance = function(data)
    local ped = getPed()
    local freemodePed = isFreemodePed(ped)
    if not data then return end

    if data.type == 'component' then
        setPedComponent(ped, clampInteger(data.id, 0, 11), data.drawable, data.texture)
    elseif data.type == 'prop' then
        setPedProp(ped, clampInteger(data.id, 0, 7), data.drawable, data.texture)
    elseif not freemodePed then
        return
    elseif data.type == 'blend' then
        local current = getHeadBlend(ped)
        if data.field == 'shapeMix' or data.field == 'skinMix' or data.field == 'thirdMix' then
            current[data.field] = tonumber(data.value) or current[data.field] or 0.0
        else
            current[data.field] = clampInteger(data.value, 0, 45)
        end
        applyHeadBlend(ped, current)
    elseif data.type == 'overlay' then
        local overlayId = tonumber(data.id)
        if overlayId == nil then
            return
        end

        local overlayData = readPedOverlaySafely(ped, overlayId) or {
            value = 0,
            opacity = 0.0,
            colorType = 0,
            color = 0,
            highlight = 0,
            maxStyles = 0,
        }

        if data.field == 'style' then
            local maxStyles = overlayData.maxStyles or 0
            if maxStyles > 0 then
                overlayData.value = clampInteger(data.value, 0, maxStyles - 1)
            else
                overlayData.value = clampInteger(data.value, 0, 255)
            end
        elseif data.field == 'opacity' then
            overlayData.opacity = math.min(1.0, math.max(0.0, tonumber(data.value) or overlayData.opacity or 0.0))
        elseif data.field == 'color' then
            overlayData.color = clampInteger(data.value, 0, 63)
        elseif data.field == 'secondColor' then
            overlayData.highlight = clampInteger(data.value, 0, 63)
        end

        applyPedOverlay(ped, overlayId, overlayData)
    elseif data.type == 'color' then
        if data.colorType == 'hair' then
            local _, highlight = readPedHairColorsSafely(ped)
            SetPedHairColor(ped, data.value, highlight or data.value)
        elseif data.colorType == 'hairHighlight' then
            local primary, _ = readPedHairColorsSafely(ped)
            SetPedHairColor(ped, primary or 0, data.value)
        elseif data.colorType == 'eyes' then
            SetPedEyeColor(ped, data.value)
        elseif data.colorType == 'overlay' then
            local overlayData = readPedOverlaySafely(ped, data.id)
            if overlayData then
                SetPedHeadOverlayColor(ped, data.id, overlayData.colorType, data.value, overlayData.highlight)
            end
        end
    end
end

function normalizeMpPedData(data, sourceKey)
    local normalized = cloneJsonTable(data) or {}
    normalized.ModelHash = tonumber(normalized.ModelHash) or tonumber(normalized.modelHash) or tonumber(normalized.Model) or tonumber(normalized.model) or 0
    normalized.Version = tonumber(normalized.Version) or tonumber(normalized.version) or 2
    if normalized.IsMale == nil then
        normalized.IsMale = normalized.ModelHash == C.MODEL_HASH_MP_M
    end

    if type(normalized.PedAppearance) ~= 'table' then
        normalized.PedAppearance = {}
    end

    local pedAppearance = normalized.PedAppearance

    local function readLegacyAppearanceNumber(fieldNames)
        for i = 1, #fieldNames do
            local value = tonumber(pedAppearance[fieldNames[i]])
            if value ~= nil then
                return value
            end
        end
        return nil
    end

    if normalized.PedTatttoos and not normalized.PedTattoos then
        normalized.PedTattoos = normalized.PedTatttoos
    elseif normalized.PedTattoos and not normalized.PedTatttoos then
        normalized.PedTatttoos = normalized.PedTattoos
    end

    if type(normalized.DrawableVariations) ~= 'table' then
        normalized.DrawableVariations = { clothes = {} }
    end
    if type(normalized.DrawableVariations.clothes) ~= 'table' then
        normalized.DrawableVariations.clothes = {}
    end

    if type(normalized.PropVariations) ~= 'table' then
        normalized.PropVariations = { props = {} }
    end
    if type(normalized.PropVariations.props) ~= 'table' then
        normalized.PropVariations.props = {}
    end

    if type(normalized.FaceShapeFeatures) ~= 'table' then
        normalized.FaceShapeFeatures = { features = {} }
    elseif type(normalized.FaceShapeFeatures.features) ~= 'table' then
        normalized.FaceShapeFeatures.features = {}
    end

    if isTableEmpty(normalized.FaceShapeFeatures.features) then
        local legacyFeatures = {}
        local hasLegacyFeatures = false
        for featureId, fieldNames in pairs(LEGACY_FACE_FEATURE_FIELDS) do
            local value = readLegacyAppearanceNumber(fieldNames)
            if value ~= nil then
                legacyFeatures[featureId] = value
                hasLegacyFeatures = true
            end
        end

        if hasLegacyFeatures then
            normalized.FaceShapeFeatures.features = legacyFeatures
        end
    end

    if type(normalized.PedHeadBlendData) ~= 'table' then
        local shapeFirstID = tonumber(pedAppearance.shapeFirstID)
        local shapeSecondID = tonumber(pedAppearance.shapeSecondID)
        local shapeThirdID = tonumber(pedAppearance.shapeThirdID)
        local skinFirstID = tonumber(pedAppearance.skinFirstID)
        local skinSecondID = tonumber(pedAppearance.skinSecondID)
        local skinThirdID = tonumber(pedAppearance.skinThirdID)
        if shapeFirstID ~= nil or shapeSecondID ~= nil or skinFirstID ~= nil or skinSecondID ~= nil then
            normalized.PedHeadBlendData = {
                shapeFirstID = shapeFirstID or 0,
                shapeSecondID = shapeSecondID or 0,
                shapeThirdID = shapeThirdID or 0,
                skinFirstID = skinFirstID or 0,
                skinSecondID = skinSecondID or 0,
                skinThirdID = skinThirdID or 0,
                shapeMix = tonumber(pedAppearance.shapeMix) or 0.5,
                skinMix = tonumber(pedAppearance.skinMix) or 0.5,
                thirdMix = tonumber(pedAppearance.thirdMix) or 0.0,
            }
        end
    end

    if normalized.HairColor == nil and pedAppearance.hairColor ~= nil then
        normalized.HairColor = tonumber(pedAppearance.hairColor) or 0
    end

    if normalized.HairHighlightColor == nil and pedAppearance.hairHighlightColor ~= nil then
        normalized.HairHighlightColor = tonumber(pedAppearance.hairHighlightColor) or normalized.HairColor or 0
    end

    if normalized.EyeColor == nil and pedAppearance.eyeColor ~= nil then
        normalized.EyeColor = tonumber(pedAppearance.eyeColor) or 0
    end

    if normalized.DrawableVariations.clothes[2] == nil and pedAppearance.hairStyle ~= nil then
        normalized.DrawableVariations.clothes[2] = {
            tonumber(pedAppearance.hairStyle) or 0,
            0,
        }
    end

    if type(normalized.HeadOverlays) ~= 'table' or next(normalized.HeadOverlays) == nil then
        local headOverlays = {}
        for i = 1, #PED_OVERLAY_MAP do
            local overlay = PED_OVERLAY_MAP[i]
            local style = tonumber(pedAppearance[overlay.key .. 'Style'])
            local opacity = tonumber(pedAppearance[overlay.key .. 'Opacity'])
            local color = tonumber(pedAppearance[overlay.key .. 'Color'])
            local secondColor = tonumber(pedAppearance[overlay.key .. 'SecondColor'])
            local colorType = tonumber(pedAppearance[overlay.key .. 'ColorType'])

            if style ~= nil or opacity ~= nil or color ~= nil or secondColor ~= nil or colorType ~= nil then
                headOverlays[overlay.id] = {
                    style = style or 0,
                    opacity = opacity or 0.0,
                    color = color or 0,
                    colorType = colorType or overlay.colorType,
                    secondColor = secondColor or 0,
                }
            end
        end

        if next(headOverlays) ~= nil then
            normalized.HeadOverlays = headOverlays
        end
    end

    if (type(normalized.Tattoos) ~= 'table' or #normalized.Tattoos == 0) and type(normalized.PedTattoos) == 'table' then
        local tattoos = {}
        for _, tattooList in pairs(normalized.PedTattoos) do
            if type(tattooList) == 'table' then
                for i = 1, #tattooList do
                    local tattoo = tattooList[i]
                    if type(tattoo) == 'table' then
                        if tattoo.collection and tattoo.overlay then
                            tattoos[#tattoos + 1] = {
                                collection = tattoo.collection,
                                overlay = tattoo.overlay,
                            }
                        elseif tattoo[1] and tattoo[2] then
                            tattoos[#tattoos + 1] = {
                                collection = tattoo[1],
                                overlay = tattoo[2],
                            }
                        end
                    end
                end
            end
        end

        if #tattoos > 0 then
            normalized.Tattoos = tattoos
        end
    end

    if type(sourceKey) == 'string' and sourceKey ~= '' then
        normalized.SaveName = sourceKey
    end

    if type(normalized.PedHeadBlendData) == 'table' then
        pedAppearance.shapeFirstID = tonumber(pedAppearance.shapeFirstID) or tonumber(normalized.PedHeadBlendData.shapeFirstID) or 0
        pedAppearance.shapeSecondID = tonumber(pedAppearance.shapeSecondID) or tonumber(normalized.PedHeadBlendData.shapeSecondID) or 0
        pedAppearance.shapeThirdID = tonumber(pedAppearance.shapeThirdID) or tonumber(normalized.PedHeadBlendData.shapeThirdID) or 0
        pedAppearance.skinFirstID = tonumber(pedAppearance.skinFirstID) or tonumber(normalized.PedHeadBlendData.skinFirstID) or 0
        pedAppearance.skinSecondID = tonumber(pedAppearance.skinSecondID) or tonumber(normalized.PedHeadBlendData.skinSecondID) or 0
        pedAppearance.skinThirdID = tonumber(pedAppearance.skinThirdID) or tonumber(normalized.PedHeadBlendData.skinThirdID) or 0
        pedAppearance.shapeMix = tonumber(pedAppearance.shapeMix) or tonumber(normalized.PedHeadBlendData.shapeMix) or 0.5
        pedAppearance.skinMix = tonumber(pedAppearance.skinMix) or tonumber(normalized.PedHeadBlendData.skinMix) or 0.5
        pedAppearance.thirdMix = tonumber(pedAppearance.thirdMix) or tonumber(normalized.PedHeadBlendData.thirdMix) or 0.0
    end

    local hairComponent = normalized.DrawableVariations.clothes[2] or normalized.DrawableVariations.clothes['2']
    if type(hairComponent) == 'table' and pedAppearance.hairStyle == nil then
        pedAppearance.hairStyle = tonumber(hairComponent[1]) or 0
    end

    if normalized.HairColor ~= nil then
        pedAppearance.hairColor = tonumber(pedAppearance.hairColor) or tonumber(normalized.HairColor) or 0
    end

    if normalized.HairHighlightColor ~= nil then
        pedAppearance.hairHighlightColor = tonumber(pedAppearance.hairHighlightColor) or tonumber(normalized.HairHighlightColor) or tonumber(normalized.HairColor) or 0
    end

    if normalized.EyeColor ~= nil then
        pedAppearance.eyeColor = tonumber(pedAppearance.eyeColor) or tonumber(normalized.EyeColor) or 0
    end

    if type(normalized.FaceShapeFeatures) == 'table' and type(normalized.FaceShapeFeatures.features) == 'table' then
        for featureId, fieldNames in pairs(LEGACY_FACE_FEATURE_FIELDS) do
            local featureValue = normalized.FaceShapeFeatures.features[featureId]
            if featureValue == nil then
                featureValue = normalized.FaceShapeFeatures.features[tostring(featureId)]
            end

            if featureValue ~= nil and pedAppearance[fieldNames[1]] == nil then
                pedAppearance[fieldNames[1]] = tonumber(featureValue) or featureValue
            end
        end
    end

    if type(normalized.HeadOverlays) == 'table' then
        for i = 1, #PED_OVERLAY_MAP do
            local overlay = PED_OVERLAY_MAP[i]
            local overlayData = normalized.HeadOverlays[overlay.id] or normalized.HeadOverlays[tostring(overlay.id)]
            if type(overlayData) == 'table' then
                if pedAppearance[overlay.key .. 'Style'] == nil then
                    pedAppearance[overlay.key .. 'Style'] = tonumber(overlayData.style) or 0
                end
                if pedAppearance[overlay.key .. 'Opacity'] == nil then
                    pedAppearance[overlay.key .. 'Opacity'] = tonumber(overlayData.opacity) or 0.0
                end
                if pedAppearance[overlay.key .. 'Color'] == nil and overlayData.color ~= nil then
                    pedAppearance[overlay.key .. 'Color'] = tonumber(overlayData.color) or 0
                end
                if pedAppearance[overlay.key .. 'SecondColor'] == nil and overlayData.secondColor ~= nil then
                    pedAppearance[overlay.key .. 'SecondColor'] = tonumber(overlayData.secondColor) or 0
                end
                if pedAppearance[overlay.key .. 'ColorType'] == nil and overlayData.colorType ~= nil then
                    pedAppearance[overlay.key .. 'ColorType'] = tonumber(overlayData.colorType) or overlay.colorType
                end
            end
        end
    end

    return normalized
end

Admin.normalizeMpPedData = normalizeMpPedData

function isSavedMpPedData(data)
    return type(data) == 'table'
        and (tonumber(data.ModelHash) ~= nil or tonumber(data.modelHash) ~= nil or tonumber(data.Model) ~= nil or tonumber(data.model) ~= nil)
        and (
            tonumber(data.Version) ~= nil
            or tonumber(data.version) ~= nil
            or type(data.DrawableVariations) == 'table'
            or type(data.PropVariations) == 'table'
            or type(data.FaceShapeFeatures) == 'table'
            or type(data.PedAppearance) == 'table'
            or type(data.PedHeadBlendData) == 'table'
            or type(data.HeadOverlays) == 'table'
            or type(data.Tattoos) == 'table'
            or type(data.PedTattoos) == 'table'
            or type(data.PedTatttoos) == 'table'
        )
end

function buildSavedPedEntry(source, sourceKey, data, isDefault)
    if not sourceKey or not isSavedMpPedData(data) then
        return nil
    end

    local _, name = normalizeSavedPedKey(sourceKey)
    if not name or name == '' then
        return nil
    end

    local normalizedData = normalizeMpPedData(data, source == C.MP_PED_SOURCE_VMENU and sourceKey or nil)
    local safeSourceKey = sourceKey:lower()

    return {
        id = ('%s:%s'):format(source, safeSourceKey),
        name = name,
        source = source,
        sourceKey = sourceKey,
        isDefault = isDefault == true,
        category = type(normalizedData.Category) == 'string' and normalizedData.Category or '',
        data = normalizedData,
    }
end

function sortSavedPeds(list)
    table.sort(list, function(a, b)
        if a.isDefault ~= b.isDefault then
            return a.isDefault
        end

        local sourceA = a.source or ''
        local sourceB = b.source or ''
        if sourceA ~= sourceB then
            return sourceA < sourceB
        end

        local categoryA = (a.category or ''):lower()
        local categoryB = (b.category or ''):lower()
        if categoryA ~= categoryB then
            return categoryA < categoryB
        end

        local nameA = (a.name or ''):lower()
        local nameB = (b.name or ''):lower()
        return nameA < nameB
    end)
end

function getEsAdminDefaultSavedPed()
    local source = GetResourceKvpString(C.DEFAULT_PED_SOURCE_KEY) or C.MP_PED_SOURCE_ES_ADMIN
    local sourceKey = GetResourceKvpString(C.DEFAULT_PED_SOURCE_REF_KEY)
    if not sourceKey or sourceKey == '' then
        return nil, nil
    end

    return source, sourceKey
end

function getEsAdminSavedPeds()
    local peds = {}
    local defaultSource, defaultSourceKey = getEsAdminDefaultSavedPed()
    local handle = StartFindKvp(C.MP_PED_KEY_PREFIX)
    if handle == -1 then
        return peds
    end

    while true do
        local key = FindKvp(handle)
        if not key or key == '' then
            break
        end

        local data = loadKvpJson(key)
        local entry = buildSavedPedEntry(C.MP_PED_SOURCE_ES_ADMIN, key, data, defaultSource == C.MP_PED_SOURCE_ES_ADMIN and defaultSourceKey == key)
        if entry then
            peds[#peds + 1] = entry
        end
    end

    EndFindKvp(handle)
    return peds
end

function getVmenuDefaultSavedPedKey()
    local ok, defaultKey = callVmenuBridge('GetDefaultSavedMpCharacterKeyForEsAdmin')
    if ok and type(defaultKey) == 'string' and defaultKey ~= '' then
        return defaultKey
    end

    local snapshot = getVmenuFallbackSnapshot()
    if snapshot and type(snapshot.defaultKey) == 'string' and snapshot.defaultKey ~= '' then
        return snapshot.defaultKey
    end

    return nil
end

function getVmenuSavedPeds()
    local peds = {}
    local ok, rawPeds = callVmenuBridge('GetSavedMpCharactersForEsAdmin')
    local defaultKey = nil

    if ok and type(rawPeds) == 'table' then
        defaultKey = getVmenuDefaultSavedPedKey()
    else
        local snapshot = getVmenuFallbackSnapshot()
        rawPeds = snapshot and snapshot.peds or nil
        defaultKey = snapshot and snapshot.defaultKey or nil
        if type(rawPeds) ~= 'table' then
            return peds
        end
    end

    for i = 1, #rawPeds do
        local item = rawPeds[i]
        local key = item and item.key
        local data = item and item.data
        local entry = buildSavedPedEntry(C.MP_PED_SOURCE_VMENU, key, data, item and (item.isDefault == true or key == defaultKey))
        if entry then
            peds[#peds + 1] = entry
        end
    end

    return peds
end

function getVmenuSavedPedPayload()
    local ok, rawPeds = callVmenuBridge('GetSavedMpCharactersForEsAdmin')
    if ok and type(rawPeds) == 'table' then
        return rawPeds, getVmenuDefaultSavedPedKey(), 'bridge'
    end

    local snapshot = getVmenuFallbackSnapshot()
    local fallbackPeds = snapshot and snapshot.peds or nil
    if type(fallbackPeds) == 'table' then
        return fallbackPeds, snapshot and snapshot.defaultKey or nil, 'fallback'
    end

    return nil, nil, nil
end

function getMergedSavedPeds()
    local peds = {}
    local seen = {}

    local localPeds = getEsAdminSavedPeds()
    for i = 1, #localPeds do
        local entry = localPeds[i]
        seen[entry.id] = true
        peds[#peds + 1] = entry
    end

    local vmenuPeds = getVmenuSavedPeds()
    for i = 1, #vmenuPeds do
        local entry = vmenuPeds[i]
        if not seen[entry.id] then
            seen[entry.id] = true
            peds[#peds + 1] = entry
        end
    end

    sortSavedPeds(peds)
    return peds
end

function getVmenuVehiclePayload()
    local ok, rawVehicles = callVmenuBridge('GetSavedVehiclesForEsAdmin')
    if ok and type(rawVehicles) == 'table' then
        return rawVehicles, 'bridge'
    end

    local snapshot = getVmenuFallbackSnapshot()
    local fallbackVehicles = snapshot and snapshot.vehicles or nil
    if type(fallbackVehicles) == 'table' then
        return fallbackVehicles, 'fallback'
    end

    return nil, nil
end

function countTableEntries(data)
    local count = 0
    if type(data) ~= 'table' then
        return count
    end

    for _ in pairs(data) do
        count = count + 1
    end

    return count
end

function getPermissionMigrationSummary()
    return {
        mode = 'ace_passthrough',
        usesVmenuAce = true,
        tabPermissionCount = countTableEntries(Config.Permissions),
        actionPermissionCount = countTableEntries(Config.ActionPermissions),
        qbxPermissionProfiles = countTableEntries(Config.QBXPermissions),
        note = 'ACE permissions stay live and vMenu-compatible; they are not copied into local storage.',
    }
end

function resolveSavedPedEntry(target)
    if type(target) ~= 'table' then
        local sourceKey, name = normalizeSavedPedKey(target)
        if not sourceKey then
            return nil
        end
        target = {
            source = C.MP_PED_SOURCE_ES_ADMIN,
            sourceKey = sourceKey,
            name = name,
        }
    elseif type(target.entry) == 'table' then
        target = target.entry
    end

    if target.id and target.source and target.sourceKey then
        return target
    end

    local wantedSource = target.source
    local wantedKey = target.sourceKey
    local wantedName = target.name and target.name:lower() or nil
    if wantedKey then
        wantedKey = normalizeSavedPedKey(wantedKey)
        wantedKey = wantedKey and wantedKey
    end

    local entries = getMergedSavedPeds()
    for i = 1, #entries do
        local entry = entries[i]
        if target.id and entry.id == target.id then
            return entry
        end
        if wantedSource and wantedKey and entry.source == wantedSource and entry.sourceKey == wantedKey then
            return entry
        end
        if not wantedSource and wantedName and entry.name and entry.name:lower() == wantedName then
            return entry
        end
    end

    return nil
end

function clearLastSavedPedReference()
    DeleteResourceKvp(C.LAST_PED_NAME_KEY)
    DeleteResourceKvp(C.LAST_PED_SOURCE_KEY)
    DeleteResourceKvp(C.LAST_PED_SOURCE_REF_KEY)
end

function setLastSavedPedReference(entry)
    if not entry or not entry.name then
        clearLastSavedPedReference()
        return
    end

    SetResourceKvp(C.LAST_PED_NAME_KEY, entry.name)
    SetResourceKvp(C.LAST_PED_SOURCE_KEY, entry.source or C.MP_PED_SOURCE_ES_ADMIN)
    if entry.sourceKey then
        SetResourceKvp(C.LAST_PED_SOURCE_REF_KEY, entry.sourceKey)
    else
        DeleteResourceKvp(C.LAST_PED_SOURCE_REF_KEY)
    end
end

function clearLastSavedPedIfMatches(entry)
    if not entry then
        return
    end

    local lastSource = GetResourceKvpString(C.LAST_PED_SOURCE_KEY) or C.MP_PED_SOURCE_ES_ADMIN
    local lastSourceKey = GetResourceKvpString(C.LAST_PED_SOURCE_REF_KEY)
    local lastName = GetResourceKvpString(C.LAST_PED_NAME_KEY)

    if entry.source ~= lastSource then
        return
    end

    if lastSourceKey and lastSourceKey ~= '' then
        if entry.sourceKey == lastSourceKey then
            clearLastSavedPedReference()
        end
        return
    end

    if entry.name and entry.name == lastName then
        clearLastSavedPedReference()
    end
end

function clearDefaultSavedPedIfMatches(entry)
    if not entry then
        return
    end

    local defaultSource = GetResourceKvpString(C.DEFAULT_PED_SOURCE_KEY) or C.MP_PED_SOURCE_ES_ADMIN
    local defaultSourceKey = GetResourceKvpString(C.DEFAULT_PED_SOURCE_REF_KEY)
    if defaultSource == entry.source and defaultSourceKey and defaultSourceKey == entry.sourceKey then
        DeleteResourceKvp(C.DEFAULT_PED_SOURCE_KEY)
        DeleteResourceKvp(C.DEFAULT_PED_SOURCE_REF_KEY)
    end
end

function setDefaultSavedPedReference(entry)
    if not entry or not entry.name then
        DeleteResourceKvp(C.DEFAULT_PED_SOURCE_KEY)
        DeleteResourceKvp(C.DEFAULT_PED_SOURCE_REF_KEY)
        return
    end

    SetResourceKvp(C.DEFAULT_PED_SOURCE_KEY, entry.source or C.MP_PED_SOURCE_ES_ADMIN)
    if entry.sourceKey and entry.sourceKey ~= '' then
        SetResourceKvp(C.DEFAULT_PED_SOURCE_REF_KEY, entry.sourceKey)
    else
        DeleteResourceKvp(C.DEFAULT_PED_SOURCE_REF_KEY)
    end
end

function loadSavedPedData(entry)
    if not entry then
        return nil
    end

    if isSavedMpPedData(entry.data) then
        return normalizeMpPedData(entry.data, entry.source == C.MP_PED_SOURCE_VMENU and entry.sourceKey or nil)
    end

    if entry.source == C.MP_PED_SOURCE_ES_ADMIN then
        local data = loadKvpJson(entry.sourceKey)
        if data then
            return normalizeMpPedData(data)
        end
        return nil
    end

    if entry.source == C.MP_PED_SOURCE_VMENU then
        local ok, rawPeds = callVmenuBridge('GetSavedMpCharactersForEsAdmin')
        if not ok or type(rawPeds) ~= 'table' then
            local snapshot = getVmenuFallbackSnapshot()
            rawPeds = snapshot and snapshot.peds or nil
        end

        if type(rawPeds) == 'table' then
            for i = 1, #rawPeds do
                local item = rawPeds[i]
                if item and item.key == entry.sourceKey and isSavedMpPedData(item.data) then
                    return normalizeMpPedData(item.data, entry.sourceKey)
                end
            end
        end
    end

    return nil
end

function buildOverwriteSavedPedData(existingEntry, capturedData)
    if not existingEntry or not capturedData then
        return capturedData
    end

    local merged = normalizeMpPedData(capturedData, existingEntry.source == C.MP_PED_SOURCE_VMENU and existingEntry.sourceKey or nil)
    local existingData = loadSavedPedData(existingEntry) or {}

    merged.Category = existingData.Category or merged.Category or ''
    merged.WalkingStyle = existingData.WalkingStyle or merged.WalkingStyle or ''
    merged.FacialExpression = existingData.FacialExpression or merged.FacialExpression or ''

    if isTableEmpty(merged.PedFacePaints) and type(existingData.PedFacePaints) == 'table' then
        merged.PedFacePaints = existingData.PedFacePaints
    end

    if isTableEmpty(merged.Tattoos) and type(existingData.Tattoos) == 'table' and next(existingData.Tattoos) ~= nil then
        merged.Tattoos = existingData.Tattoos
    end

    if isTableEmpty(merged.PedTattoos) and type(existingData.PedTattoos) == 'table' and next(existingData.PedTattoos) ~= nil then
        merged.PedTattoos = existingData.PedTattoos
    end

    if isTableEmpty(merged.PedTatttoos) and type(existingData.PedTatttoos) == 'table' and next(existingData.PedTatttoos) ~= nil then
        merged.PedTatttoos = existingData.PedTatttoos
    elseif type(merged.PedTattoos) == 'table' and not isTableEmpty(merged.PedTattoos) then
        merged.PedTatttoos = merged.PedTattoos
    end

    if type(existingData.PedAppearance) == 'table' then
        merged.PedAppearance = merged.PedAppearance or {}
        for key, value in pairs(existingData.PedAppearance) do
            if merged.PedAppearance[key] == nil then
                merged.PedAppearance[key] = value
            end
        end
    end

    return merged
end

function formatSavedPedImportSummary(result)
    if type(result) ~= 'table' then
        return 'Import finished.'
    end

    local segments = {}
    segments[#segments + 1] = ('imported %d'):format(tonumber(result.imported) or 0)

    local skipped = tonumber(result.skipped) or 0
    if skipped > 0 then
        segments[#segments + 1] = ('skipped %d existing'):format(skipped)
    end

    local invalid = tonumber(result.invalid) or 0
    if invalid > 0 then
        segments[#segments + 1] = ('ignored %d invalid'):format(invalid)
    end

    local failed = tonumber(result.failed) or 0
    if failed > 0 then
        segments[#segments + 1] = ('failed %d'):format(failed)
    end

    local promoted = result.promotedDefault == true
    local summary = ('vMenu import complete: %s.'):format(table.concat(segments, ', '))
    if promoted then
        summary = summary .. ' Default outfit promoted for spawn restore.'
    end

    return summary
end

function buildSavedPedUiEntry(entry)
    if type(entry) ~= 'table' then
        return nil
    end

    return {
        id = entry.id,
        name = entry.name,
        source = entry.source,
        sourceKey = entry.sourceKey,
        isDefault = entry.isDefault == true,
        category = entry.category or '',
    }
end

Admin.getSavedPeds = function()
    local entries = getMergedSavedPeds()
    local list = {}

    for i = 1, #entries do
        local uiEntry = buildSavedPedUiEntry(entries[i])
        if uiEntry then
            list[#list + 1] = uiEntry
        end
    end

    return list
end

function syncWardrobeShareRequests()
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { wardrobeShareRequests = state.wardrobeShareRequests or {} }
    })
end

function findWardrobeShareRequest(shareId)
    local requests = state.wardrobeShareRequests or {}
    for index = 1, #requests do
        local request = requests[index]
        if request and request.shareId == shareId then
            return index, request
        end
    end

    return nil, nil
end

function removeWardrobeShareRequest(shareId)
    local index = findWardrobeShareRequest(shareId)
    if not index then
        return false
    end

    table.remove(state.wardrobeShareRequests, index)
    syncWardrobeShareRequests()
    return true
end

RegisterNetEvent('cortex-admin:client:receiveWardrobeShare', function(payload)
    if type(payload) ~= 'table' or type(payload.shareId) ~= 'string' or type(payload.outfit) ~= 'table' then
        return
    end

    state.wardrobeShareRequests = state.wardrobeShareRequests or {}
    state.wardrobeShareRequests[#state.wardrobeShareRequests + 1] = {
        shareId = payload.shareId,
        senderId = payload.senderId,
        senderName = payload.senderName or 'Unknown',
        title = payload.title or 'Current Outfit',
        outfit = payload.outfit,
    }

    syncWardrobeShareRequests()
end)

Admin.getNearbyWardrobeShareTargets = function()
    Admin.debugTrace('wardrobe_targets', 'enter', {})
    local targetSnapshot = getWardrobeShareTargetSnapshot()
    if not targetSnapshot then
        Admin.debugTrace('wardrobe_targets', 'exit', { n = 0 })
        return {}
    end

    local openTargetIds = targetSnapshot.targets
    local openLookup = {}
    for i = 1, #openTargetIds do
        local id = tonumber(openTargetIds[i])
        if id then
            openLookup[id] = true
        end
    end

    local nearby = {}
    local radius = targetSnapshot.radius
    local myCoords = GetEntityCoords(getPed())
    local players = GetActivePlayers()

    for i = 1, #players do
        local player = players[i]
        if player ~= PlayerId() then
            local serverId = GetPlayerServerId(player)
            if openLookup[serverId] then
                local ped = GetPlayerPed(player)
                if ped ~= 0 and DoesEntityExist(ped) then
                    local coords = GetEntityCoords(ped)
                    local dx = coords.x - myCoords.x
                    local dy = coords.y - myCoords.y
                    local dz = coords.z - myCoords.z
                    local distanceSq = (dx * dx) + (dy * dy) + (dz * dz)
                    if WardrobeSharePolicy.isDistanceSquaredWithinRadius(distanceSq, radius) then
                        nearby[#nearby + 1] = {
                            id = serverId,
                            name = GetPlayerName(player) or ('Player %d'):format(serverId),
                            distance = math.sqrt(distanceSq),
                        }
                    end
                end
            end
        end
    end

    table.sort(nearby, function(a, b)
        return (a.distance or 0.0) < (b.distance or 0.0)
    end)

    Admin.debugTrace('wardrobe_targets', 'exit', { n = #nearby })
    return nearby
end

Admin.shareCurrentWardrobe = function(targetServerId)
    local target = tonumber(targetServerId)
    if not target or target <= 0 then
        notify('error', 'Valid target required.')
        return false
    end

    local nearbyTargets = Admin.getNearbyWardrobeShareTargets()
    local isAllowedTarget = false
    for i = 1, #nearbyTargets do
        if tonumber(nearbyTargets[i].id) == target then
            isAllowedTarget = true
            break
        end
    end

    if not isAllowedTarget then
        notify('error', 'Target player must be nearby and have the menu open.')
        return false
    end

    TriggerServerEvent('cortex-admin:server:shareWardrobe', {
        target = target,
        title = 'Current Outfit',
        outfit = buildSharedWardrobeData(getPed()),
    })

    return true
end

Admin.acceptWardrobeShare = function(shareId)
    local _, request = findWardrobeShareRequest(shareId)
    if not request then
        notify('error', 'Shared outfit not found.')
        return false
    end

    if not applySharedWardrobeData(getPed(), request.outfit) then
        notify('error', 'Failed to apply shared outfit.')
        return false
    end

    removeWardrobeShareRequest(shareId)
    notify('success', ('Applied shared outfit from %s.'):format(request.senderName or 'Unknown'))
    return true
end

Admin.saveWardrobeShare = function(shareId)
    local _, request = findWardrobeShareRequest(shareId)
    if not request then
        notify('error', 'Shared outfit not found.')
        return false
    end

    local ped = getPed()
    local model = GetEntityModel(ped)
    if model ~= joaat('mp_m_freemode_01') and model ~= joaat('mp_f_freemode_01') then
        notify('error', 'Switch to an MP freemode ped before saving shared outfits.')
        return false
    end

    local baseName = ('Shared_%s'):format((request.senderName or 'Outfit'):gsub('%s+', '_'))
    local key, name = normalizeSavedPedKey(baseName)
    local suffix = 1
    while key and loadKvpJson(key) do
        suffix = suffix + 1
        key, name = normalizeSavedPedKey(('%s_%d'):format(baseName, suffix))
    end

    if not key or not name then
        notify('error', 'Failed to generate a save name for the shared outfit.')
        return false
    end

    local mpData = captureMpPedData(ped, name)
    mpData.DrawableVariations = cloneJsonTable(request.outfit.DrawableVariations) or mpData.DrawableVariations
    mpData.PropVariations = cloneJsonTable(request.outfit.PropVariations) or mpData.PropVariations
    mpData.Category = 'shared'
    mpData.SaveName = name
    mpData.ImportedFrom = 'wardrobe_share'

    if not saveKvpJson(key, mpData) then
        notify('error', 'Failed to save shared outfit.')
        return false
    end

    removeWardrobeShareRequest(shareId)
    notify('success', ('Saved shared outfit as %s.'):format(name))
    return true
end

Admin.dismissWardrobeShare = function(shareId)
    if not removeWardrobeShareRequest(shareId) then
        notify('error', 'Shared outfit not found.')
        return false
    end

    return true
end

Admin.importVmenuSavedPeds = function(options)
    local silent = type(options) == 'table' and options.silent == true
    local rawPeds, defaultKey = getVmenuSavedPedPayload()
    if type(rawPeds) ~= 'table' then
        if not silent then
            notify('error', 'Failed to read saved vMenu outfits.')
        end
        return false, { reason = 'read_failed' }
    end

    local existingEntries = getEsAdminSavedPeds()
    local existingByKey = {}
    for i = 1, #existingEntries do
        local entry = existingEntries[i]
        if entry and entry.sourceKey then
            existingByKey[entry.sourceKey] = entry
        end
    end

    local result = {
        imported = 0,
        skipped = 0,
        invalid = 0,
        failed = 0,
        promotedDefault = false,
        total = #rawPeds,
    }

    for i = 1, #rawPeds do
        local item = rawPeds[i]
        local sourceKey = item and item.key
        local rawData = item and item.data
        local targetKey, name = normalizeSavedPedKey(sourceKey)

        if not targetKey or not name or not isSavedMpPedData(rawData) then
            result.invalid = result.invalid + 1
        elseif existingByKey[targetKey] then
            result.skipped = result.skipped + 1
        else
            local importedData = normalizeMpPedData(rawData)
            importedData.SaveName = name
            importedData.ImportedFrom = C.MP_PED_SOURCE_VMENU
            importedData.ImportedSourceKey = sourceKey

            if saveKvpJson(targetKey, importedData) then
                result.imported = result.imported + 1
                existingByKey[targetKey] = {
                    name = name,
                    source = C.MP_PED_SOURCE_ES_ADMIN,
                    sourceKey = targetKey,
                }
            else
                result.failed = result.failed + 1
            end
        end
    end

    local defaultEntry = defaultKey and existingByKey[defaultKey] or nil
    if defaultEntry then
        setLastSavedPedReference({
            name = defaultEntry.name,
            source = C.MP_PED_SOURCE_ES_ADMIN,
            sourceKey = defaultKey,
        })
        setDefaultSavedPedReference({
            name = defaultEntry.name,
            source = C.MP_PED_SOURCE_ES_ADMIN,
            sourceKey = defaultKey,
        })
        result.promotedDefault = true
    end

    if result.total == 0 then
        if not silent then
            notify('error', 'No saved vMenu outfits were found to import.')
        end
        return true, result
    end

    if not silent then
        local notifyType = (result.imported > 0 or result.promotedDefault) and 'success' or 'error'
        notify(notifyType, formatSavedPedImportSummary(result))
    end
    return true, result
end

function formatSavedVehicleImportSummary(result)
    if type(result) ~= 'table' then
        return 'Vehicle import finished.'
    end

    local segments = {}
    segments[#segments + 1] = ('imported %d'):format(tonumber(result.imported) or 0)

    local skipped = tonumber(result.skipped) or 0
    if skipped > 0 then
        segments[#segments + 1] = ('skipped %d existing'):format(skipped)
    end

    local invalid = tonumber(result.invalid) or 0
    if invalid > 0 then
        segments[#segments + 1] = ('ignored %d invalid'):format(invalid)
    end

    return ('vMenu vehicle import complete: %s.'):format(table.concat(segments, ', '))
end

Admin.deleteSavedPed = function(target)
    local entry = resolveSavedPedEntry(target)
    if not entry then
        notify('error', 'Saved outfit not found.')
        return
    end

    if entry.source == C.MP_PED_SOURCE_VMENU then
        if not ensureVmenuWriteBridge('delete') then
            return
        end

        local deleted, result = callVmenuBridge('DeleteSavedMpCharacterForEsAdmin', entry.sourceKey)
        if not deleted then
            print(('[cortex-admin] vMenu outfit delete failed: %s'):format(tostring(result)))
            notify('error', 'Failed to delete vMenu outfit.')
            return
        end
    else
        DeleteResourceKvp(entry.sourceKey)
    end

    clearLastSavedPedIfMatches(entry)
    clearDefaultSavedPedIfMatches(entry)
    notify('success', 'Deleted saved outfit: ' .. entry.name)
end

Admin.renameSavedPed = function(target, newName)
    local entry = resolveSavedPedEntry(target)
    if not entry or not newName or newName == '' or entry.name == newName then
        return
    end

    local newKey = normalizeSavedPedKey(newName)
    newKey = newKey and newKey
    if not newKey then
        notify('error', 'Invalid outfit name.')
        return
    end

    if entry.source == C.MP_PED_SOURCE_VMENU then
        if not ensureVmenuWriteBridge('rename') then
            return
        end

        local renamed, result = callVmenuBridge('RenameSavedMpCharacterForEsAdmin', entry.sourceKey, newKey)
        if not renamed then
            print(('[cortex-admin] vMenu outfit rename failed: %s'):format(tostring(result)))
            notify('error', 'Failed to rename vMenu outfit.')
            return
        end
    else
        local data = loadKvpJson(entry.sourceKey)
        if not data then
            notify('error', 'Saved outfit not found: ' .. entry.name)
            return
        end

        data.SaveName = newName
        if not saveKvpJson(newKey, data) then
            notify('error', 'Failed to rename outfit.')
            return
        end

        DeleteResourceKvp(entry.sourceKey)
    end

    local lastSource = GetResourceKvpString(C.LAST_PED_SOURCE_KEY) or C.MP_PED_SOURCE_ES_ADMIN
    local lastSourceKey = GetResourceKvpString(C.LAST_PED_SOURCE_REF_KEY)
    if lastSource == entry.source and ((lastSourceKey and lastSourceKey == entry.sourceKey) or (not lastSourceKey and GetResourceKvpString(C.LAST_PED_NAME_KEY) == entry.name)) then
        setLastSavedPedReference({
            name = newName,
            source = entry.source,
            sourceKey = newKey,
        })
    end

    local defaultSource = GetResourceKvpString(C.DEFAULT_PED_SOURCE_KEY) or C.MP_PED_SOURCE_ES_ADMIN
    local defaultSourceKey = GetResourceKvpString(C.DEFAULT_PED_SOURCE_REF_KEY)
    if defaultSource == entry.source and defaultSourceKey == entry.sourceKey then
        setDefaultSavedPedReference({
            name = newName,
            source = entry.source,
            sourceKey = newKey,
        })
    end

    notify('success', ('Renamed outfit from %s to %s'):format(entry.name, newName))
end

Admin.cloneSavedPed = function(target, newName)
    local entry = resolveSavedPedEntry(target)
    if not entry or not newName or newName == '' then
        return
    end

    local sourceData = loadSavedPedData(entry)
    if not sourceData then
        notify('error', 'Saved outfit not found: ' .. (entry.name or 'unknown'))
        return
    end

    local newKey = normalizeSavedPedKey(newName)
    newKey = newKey and newKey
    if not newKey then
        notify('error', 'Invalid outfit name.')
        return
    end

    local clonedData = normalizeMpPedData(sourceData, entry.source == C.MP_PED_SOURCE_VMENU and newKey or nil)
    clonedData.SaveName = entry.source == C.MP_PED_SOURCE_VMENU and newKey or newName

    if entry.source == C.MP_PED_SOURCE_VMENU then
        if not ensureVmenuWriteBridge('clone') then
            return
        end

        local saved, result = callVmenuBridge('UpsertSavedMpCharacterForEsAdmin', newKey, clonedData, false)
        if not saved then
            print(('[cortex-admin] vMenu outfit clone failed: %s'):format(tostring(result)))
            notify('error', 'Failed to clone vMenu outfit.')
            return
        end
    else
        if not saveKvpJson(newKey, clonedData) then
            notify('error', 'Failed to clone outfit.')
            return
        end
    end

    notify('success', ('Cloned outfit from %s to %s'):format(entry.name, newName))
end

Admin.setDefaultSavedPed = function(target)
    local entry = resolveSavedPedEntry(target)
    if not entry then
        notify('error', 'Saved outfit not found.')
        return false
    end

    setDefaultSavedPedReference({
        name = entry.name,
        source = entry.source,
        sourceKey = entry.sourceKey,
    })

    notify('success', 'Default outfit set: ' .. entry.name)
    return true
end

function fetchPedComponent(ped, componentId)
    return {
        GetPedDrawableVariation(ped, componentId),
        GetPedTextureVariation(ped, componentId)
    }
end

function fetchPedProp(ped, propId)
    return {
        GetPedPropIndex(ped, propId),
        GetPedPropTextureIndex(ped, propId)
    }
end

function getPedOverlay(ped, overlayId)
    if not isFreemodePed(ped) then
        return nil
    end

    local overlayData = readPedOverlaySafely(ped, overlayId)
    if overlayData then
        return {
            value = overlayData.value,
            opacity = overlayData.opacity,
            colorType = overlayData.colorType,
            color = overlayData.color,
            highlight = overlayData.highlight,
        }
    end
    return nil
end

applyPedOverlay = function(ped, overlayId, data)
    if not data or not isFreemodePed(ped) then return end
    SetPedHeadOverlay(ped, overlayId, data.value or 0, data.opacity or 0.0)
    if data.colorType ~= nil then
        SetPedHeadOverlayColor(ped, overlayId, data.colorType, data.color or 0, data.highlight or 0)
    end
end

getHeadBlend = function(ped)
    local blend = buildDefaultHeadBlend()

    if not isFreemodePed(ped) then
        return blend
    end

    local hasData = false
    blend, hasData = readPedHeadBlendSafely(ped)

    if hasData then
        print(('[cortex-admin] Head blend captured - Mother: %d, Father: %d, ShapeMix: %.2f, SkinMix: %.2f'):format(
            blend.shapeFirstID or 0, blend.shapeSecondID or 0, blend.shapeMix or 0, blend.skinMix or 0
        ))
    else
        print('[cortex-admin] WARNING: No head blend data found on ped')
    end

    return blend
end


applyHeadBlend = function(ped, data)
    if not data or not isFreemodePed(ped) then return end
    SetPedHeadBlendData(
        ped,
        data.shapeFirstID or 0,
        data.shapeSecondID or 0,
        data.shapeThirdID or 0,
        data.skinFirstID or 0,
        data.skinSecondID or 0,
        data.skinThirdID or 0,
        data.shapeMix or 0.0,
        data.skinMix or 0.0,
        data.thirdMix or 0.0,
        false
    )
end

function captureMpPedData(ped, saveName)
    print('[cortex-admin] Capturing MP Ped data...')
    
    local headBlend = getHeadBlend(ped)
    
    local drawableVariations = { clothes = {} }
    for componentId = 0, 11 do
        drawableVariations.clothes[componentId] = fetchPedComponent(ped, componentId)
    end

    local propVariations = { props = {} }
    for propId = 0, 7 do
        propVariations.props[propId] = fetchPedProp(ped, propId)
    end

    local faceFeatures = { features = {} }
    local hasNonZeroFeatures = false
    for featureId = 0, 19 do
        local value = GetPedFaceFeature(ped, featureId)
        faceFeatures.features[featureId] = value
        if value ~= 0 then hasNonZeroFeatures = true end
    end
    
    if hasNonZeroFeatures then
        print('[cortex-admin] Face features captured (has custom values)')
    else
        print('[cortex-admin] Face features captured (all default/zero)')
    end

    local hairColor, hairHighlightColor = getCurrentHairColors(ped)

    local eyeColor = GetPedEyeColor(ped)

    local headOverlays = {}
    for i = 1, #PED_OVERLAY_MAP do
        local overlay = PED_OVERLAY_MAP[i]
        local overlayData = getPedOverlay(ped, overlay.id)
        if overlayData then
            headOverlays[overlay.id] = {
                style = overlayData.value,
                opacity = overlayData.opacity,
                color = overlayData.color,
                colorType = overlayData.colorType,
                secondColor = overlayData.highlight or 0
            }
        end
    end

    local tattoos = {}

    return {
        ModelHash = GetEntityModel(ped),
        IsMale = GetEntityModel(ped) == joaat('mp_m_freemode_01'),
        SaveName = saveName,
        Version = 2,
        
        PedHeadBlendData = headBlend,
        
        FaceShapeFeatures = faceFeatures,
        
        DrawableVariations = drawableVariations,
        
        PropVariations = propVariations,
        
        HeadOverlays = headOverlays,
        
        HairColor = hairColor or 0,
        HairHighlightColor = hairHighlightColor or 0,
        
        EyeColor = eyeColor or 0,
        
        Tattoos = tattoos,
        
        PedAppearance = {
            hairStyle = GetPedDrawableVariation(ped, 2),
            hairColor = hairColor or 0,
            hairHighlightColor = hairHighlightColor or 0,
            eyeColor = eyeColor or 0,
        },
        PedTattoos = tattoos,
        PedFacePaints = {},
        WalkingStyle = '',
        FacialExpression = '',
        Category = '',
    }
end

function buildSharedWardrobeData(ped)
    local drawableVariations = { clothes = {} }
    for componentId = 1, 11 do
        if not WARDROBE_SHARE_COMPONENT_BLACKLIST[componentId] then
            drawableVariations.clothes[componentId] = fetchPedComponent(ped, componentId)
        end
    end

    local propVariations = { props = {} }
    for propId = 0, 7 do
        propVariations.props[propId] = fetchPedProp(ped, propId)
    end

    return {
        Version = 1,
        DrawableVariations = drawableVariations,
        PropVariations = propVariations,
    }
end

function applyMpPedData(ped, data, options)
    if not data then return false end
    if data.ModelHash and data.ModelHash ~= 0
        and not authorizeModel('ped', data.ModelHash, 'player.loadMpPed') then return false end
    
    print('[cortex-admin] Applying MP Ped data...')

    if data.ModelHash and data.ModelHash ~= 0 then
        local currentModel = GetEntityModel(ped)
        if currentModel ~= data.ModelHash then
            if exports['cortex-lib']:requestModel(data.ModelHash, 5000) then
                SetPlayerModel(PlayerId(), data.ModelHash)
                SetModelAsNoLongerNeeded(data.ModelHash)
            ped = getPed()
            Wait(100)
        end
        end
    end

    local freemodePed = isFreemodePed(ped)

    if freemodePed and data.PedHeadBlendData then
        applyHeadBlend(ped, data.PedHeadBlendData)
        print('[cortex-admin] Applied head blend data')
    elseif freemodePed then
        SetPedHeadBlendData(ped, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.0, false)
    end

    if freemodePed and data.FaceShapeFeatures and data.FaceShapeFeatures.features then
        for featureId, value in pairs(data.FaceShapeFeatures.features) do
            SetPedFaceFeature(ped, tonumber(featureId), value)
        end
        print('[cortex-admin] Applied face features')
    end

    if data.DrawableVariations and data.DrawableVariations.clothes then
        for componentId, values in pairs(data.DrawableVariations.clothes) do
            setPedComponent(ped, tonumber(componentId), values[1], values[2])
        end
        print('[cortex-admin] Applied clothing')
    end

    if data.PropVariations and data.PropVariations.props then
        for propId, values in pairs(data.PropVariations.props) do
            setPedProp(ped, tonumber(propId), values[1], values[2])
        end
        print('[cortex-admin] Applied props')
    end

    if freemodePed and data.HairColor ~= nil then
        SetPedHairColor(ped, data.HairColor, data.HairHighlightColor or data.HairColor)
    elseif freemodePed and data.PedAppearance and data.PedAppearance.hairColor then
        SetPedHairColor(ped, data.PedAppearance.hairColor, data.PedAppearance.hairHighlightColor or data.PedAppearance.hairColor)
    end

    if freemodePed and data.EyeColor ~= nil then
        SetPedEyeColor(ped, data.EyeColor)
    elseif freemodePed and data.PedAppearance and data.PedAppearance.eyeColor then
        SetPedEyeColor(ped, data.PedAppearance.eyeColor)
    end

    if freemodePed and data.HeadOverlays then
        for overlayId, overlayData in pairs(data.HeadOverlays) do
            local id = tonumber(overlayId)
            if id and overlayData then
                SetPedHeadOverlay(ped, id, overlayData.style or 0, overlayData.opacity or 0.0)
                if overlayData.colorType and overlayData.color then
                    SetPedHeadOverlayColor(ped, id, overlayData.colorType, overlayData.color, overlayData.secondColor or 0)
                end
            end
        end
        print('[cortex-admin] Applied head overlays (new format)')
    elseif freemodePed and data.PedAppearance then
        local appearance = data.PedAppearance

        for i = 1, #PED_OVERLAY_MAP do
            local overlay = PED_OVERLAY_MAP[i]
            local styleKey = overlay.key .. 'Style'
            local opacityKey = overlay.key .. 'Opacity'
            local colorKey = overlay.key .. 'Color'
            local overlayData = {
                value = appearance[styleKey] or 0,
                opacity = appearance[opacityKey] or 0.0,
                color = appearance[colorKey] or 0,
                highlight = 0,
                colorType = appearance[overlay.key .. 'ColorType'] or overlay.colorType,
            }
            applyPedOverlay(ped, overlay.id, overlayData)
        end
        print('[cortex-admin] Applied head overlays (legacy format)')
    end

    if not (options and options.preserveDecorations == true) then
        ClearPedDecorations(ped)

        if data.Tattoos and type(data.Tattoos) == 'table' and #data.Tattoos > 0 then
            for i, tattoo in ipairs(data.Tattoos) do
                if tattoo.collection and tattoo.overlay then
                    AddPedDecorationFromHashes(ped, tattoo.collection, tattoo.overlay)
                end
            end
            print(('[cortex-admin] Applied %d tattoos'):format(#data.Tattoos))
        else
            local legacyPedTattoos = data.PedTattoos or data.PedTatttoos
            if type(legacyPedTattoos) == 'table' then
                local count = 0
                for _, tattooList in pairs(legacyPedTattoos) do
                    if type(tattooList) == 'table' then
                        for _, tattoo in ipairs(tattooList) do
                            if tattoo.collection and tattoo.overlay then
                                AddPedDecorationFromHashes(ped, tattoo.collection, tattoo.overlay)
                                count = count + 1
                            elseif tattoo[1] and tattoo[2] then
                                AddPedDecorationFromHashes(ped, tattoo[1], tattoo[2])
                                count = count + 1
                            end
                        end
                    end
                end
                if count > 0 then
                    print(('[cortex-admin] Applied %d tattoos (legacy format)'):format(count))
                end
            end
        end
    end
    
    print('[cortex-admin] MP Ped data applied successfully')
    return true
end

-- Register early so startup restore in main.lua can use this even if later init code fails.
Admin.loadMpPedData = function(data)
    if not data then return false end
    return applyMpPedData(getPed(), data)
end

local VEHICLE_CLASS_CATEGORY_MAP = {
    [0] = 'compacts',
    [1] = 'sedans',
    [2] = 'suvs',
    [3] = 'coupes',
    [4] = 'muscle',
    [5] = 'sportsclassics',
    [6] = 'sports',
    [7] = 'super',
    [8] = 'motorcycles',
    [9] = 'offroad',
    [10] = 'industrial',
    [11] = 'utility',
    [12] = 'vans',
    [13] = 'cycles',
    [14] = 'boats',
    [15] = 'helicopters',
    [16] = 'planes',
    [17] = 'service',
    [18] = 'emergency',
    [19] = 'military',
    [20] = 'commercial',
    [21] = 'trains',
    [22] = 'openwheel',
}

function getVehicleCategoryFromClass(class)
    return VEHICLE_CLASS_CATEGORY_MAP[class] or 'other'
end

function getVehicleCategory(vehicle)
    return getVehicleCategoryFromClass(GetVehicleClass(vehicle))
end

function getVehicleCategoryFromModel(model)
    return getVehicleCategoryFromClass(GetVehicleClassFromName(model))
end

function captureVehicleData(vehicle, saveName)
    local props = {
        model = GetEntityModel(vehicle),
        name = saveName,
        category = getVehicleCategory(vehicle),
        colors = {},
        mods = {},
        modColors = {},
        extras = {},
        livery = GetVehicleLivery(vehicle),
        plateStyle = GetVehicleNumberPlateTextIndex(vehicle),
        plateText = GetVehicleNumberPlateText(vehicle),
        wheelType = GetVehicleWheelType(vehicle),
        windowTint = GetVehicleWindowTint(vehicle),
        neonFront = false,
        neonBack = false,
        neonLeft = false,
        neonRight = false,
        neonColor = nil,
        tyreSmokeColor = nil,
        xenonColor = nil,
        customPrimaryColor = nil,
        customSecondaryColor = nil,
        turbo = IsToggleModOn(vehicle, 18),
        tyreSmoke = IsToggleModOn(vehicle, 20),
        xenonHeadlights = IsToggleModOn(vehicle, 22),
        customWheels = GetVehicleModVariation(vehicle, 23),
        customWheelsRear = GetVehicleModVariation(vehicle, 24),
        tyresCanBurst = GetVehicleTyresCanBurst(vehicle),
        enveffScale = GetVehicleEnveffScale(vehicle),
        version = 1,
    }

    local primary, secondary = GetVehicleColours(vehicle)

    local pearlescent, wheelColor = GetVehicleExtraColours(vehicle)
    local dashColor = GetVehicleDashboardColour(vehicle)
    local trimColor = GetVehicleInteriorColour(vehicle)
    props.colors = {
        primary = primary,
        secondary = secondary,
        pearlescent = pearlescent,
        wheel = wheelColor,
        dashboard = dashColor,
        trim = trimColor,
    }

    if GetIsVehiclePrimaryColourCustom(vehicle) then
        local r, g, b = GetVehicleCustomPrimaryColour(vehicle)
        props.customPrimaryColor = { r, g, b }
    end

    if GetIsVehicleSecondaryColourCustom(vehicle) then
        local r, g, b = GetVehicleCustomSecondaryColour(vehicle)
        props.customSecondaryColor = { r, g, b }
    end

    local modColorType, modColor, pearlescentColor = GetVehicleModColor_1(vehicle)
    props.modColors.primary = {
        type = modColorType,
        color = modColor,
        pearlescent = pearlescentColor,
    }
    local modColorType2, modColor2 = GetVehicleModColor_2(vehicle)
    props.modColors.secondary = {
        type = modColorType2,
        color = modColor2,
    }

    for modType = 0, 49 do
        local modValue = GetVehicleMod(vehicle, modType)
        if modValue ~= nil then
            props.mods[modType] = modValue
        end
    end

    for extraId = 0, 20 do
        if DoesExtraExist(vehicle, extraId) then
            props.extras[extraId] = IsVehicleExtraTurnedOn(vehicle, extraId) and true or false
        end
    end

    local neon = { false, false, false }
    neon[1], neon[2], neon[3] = GetVehicleNeonLightsColour(vehicle)
    props.neonColor = { neon[1], neon[2], neon[3] }
    props.neonFront = IsVehicleNeonLightEnabled(vehicle, 0)
    props.neonBack = IsVehicleNeonLightEnabled(vehicle, 1)
    props.neonLeft = IsVehicleNeonLightEnabled(vehicle, 2)
    props.neonRight = IsVehicleNeonLightEnabled(vehicle, 3)

    local smokeR, smokeG, smokeB = GetVehicleTyreSmokeColor(vehicle)
    props.tyreSmokeColor = { smokeR, smokeG, smokeB }

    props.xenonColor = GetVehicleXenonLightsColour(vehicle)

    return props
end

function applyVehicleData(vehicle, props)
    if not props then return end

    SetVehicleModKit(vehicle, 0)
    if props.colors then
        SetVehicleColours(vehicle, props.colors.primary or 0, props.colors.secondary or 0)
        SetVehicleExtraColours(vehicle, props.colors.pearlescent or 0, props.colors.wheel or 0)
        SetVehicleDashboardColour(vehicle, props.colors.dashboard or 0)
        SetVehicleInteriorColour(vehicle, props.colors.trim or 0)
    end

    if props.customPrimaryColor then
        SetVehicleCustomPrimaryColour(vehicle, props.customPrimaryColor[1] or 0, props.customPrimaryColor[2] or 0, props.customPrimaryColor[3] or 0)
    else
        ClearVehicleCustomPrimaryColour(vehicle)
    end

    if props.customSecondaryColor then
        SetVehicleCustomSecondaryColour(vehicle, props.customSecondaryColor[1] or 0, props.customSecondaryColor[2] or 0, props.customSecondaryColor[3] or 0)
    else
        ClearVehicleCustomSecondaryColour(vehicle)
    end

    if props.modColors and props.modColors.primary then
        SetVehicleModColor_1(vehicle, props.modColors.primary.type or 0, props.modColors.primary.color or 0, props.modColors.primary.pearlescent or 0)
    end

    if props.modColors and props.modColors.secondary then
        SetVehicleModColor_2(vehicle, props.modColors.secondary.type or 0, props.modColors.secondary.color or 0)
    end

    if props.mods then
        for modType, modValue in pairs(props.mods) do
            local modIndex = tonumber(modType)
            local value = tonumber(modValue)
            if modIndex then
                if modIndex == 23 or modIndex == 24 then
                    SetVehicleMod(vehicle, modIndex, value or -1, props.customWheels == true)
                else
                    SetVehicleMod(vehicle, modIndex, value or -1, false)
                end
            end
        end
    end

    if props.extras then
        for extraId, enabled in pairs(props.extras) do
            SetVehicleExtra(vehicle, tonumber(extraId), enabled and 0 or 1)
        end
    end

    if props.windowTint ~= nil then
        SetVehicleWindowTint(vehicle, props.windowTint)
    end

    if props.plateText then
        SetVehicleNumberPlateText(vehicle, props.plateText)
    end

    if props.plateStyle ~= nil then
        SetVehicleNumberPlateTextIndex(vehicle, props.plateStyle)
    end

    if props.wheelType ~= nil then
        SetVehicleWheelType(vehicle, props.wheelType)
    end

    if props.livery ~= nil then
        SetVehicleLivery(vehicle, props.livery)
    end

    ToggleVehicleMod(vehicle, 18, props.turbo == true)
    ToggleVehicleMod(vehicle, 20, props.tyreSmoke == true)
    ToggleVehicleMod(vehicle, 22, props.xenonHeadlights == true)

    if props.xenonColor ~= nil and props.xenonColor ~= -1 then
        SetVehicleXenonLightsColour(vehicle, props.xenonColor)
    end

    if props.neonFront ~= nil then
        SetVehicleNeonLightEnabled(vehicle, 0, props.neonFront)
    end
    if props.neonBack ~= nil then
        SetVehicleNeonLightEnabled(vehicle, 1, props.neonBack)
    end
    if props.neonLeft ~= nil then
        SetVehicleNeonLightEnabled(vehicle, 2, props.neonLeft)
    end
    if props.neonRight ~= nil then
        SetVehicleNeonLightEnabled(vehicle, 3, props.neonRight)
    end

    if props.neonColor then
        SetVehicleNeonLightsColour(vehicle, props.neonColor[1] or 255, props.neonColor[2] or 255, props.neonColor[3] or 255)
    end

    if props.tyreSmokeColor then
        SetVehicleTyreSmokeColor(vehicle, props.tyreSmokeColor[1] or 255, props.tyreSmokeColor[2] or 255, props.tyreSmokeColor[3] or 255)
    end

    if props.customWheels ~= nil then
        SetVehicleMod(vehicle, 23, GetVehicleMod(vehicle, 23), props.customWheels == true)
    end

    if props.customWheelsRear ~= nil then
        SetVehicleMod(vehicle, 24, GetVehicleMod(vehicle, 24), props.customWheelsRear == true)
    end

    if props.tyresCanBurst ~= nil then
        SetVehicleTyresCanBurst(vehicle, props.tyresCanBurst == true)
    end

    local enveffScale = tonumber(props.enveffScale)
    if enveffScale and enveffScale == enveffScale and enveffScale >= 0.0 and enveffScale <= 1.0 then
        SetVehicleEnveffScale(vehicle, enveffScale)
    end
end

Admin.giveKeysForVehicle = function(vehicle, silent, authorizationToken, authorizationActionId)
    if not vehicle or vehicle == 0 then return end
    if GetResourceState('qbx_vehiclekeys') ~= 'started' then return end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    if netId == 0 then
        local timeoutAt = GetGameTimer() + 2000
        while netId == 0 and GetGameTimer() < timeoutAt do
            Wait(10)
            netId = NetworkGetNetworkIdFromEntity(vehicle)
        end
    end

    TriggerServerEvent('cortex-admin:server:giveVehicleKeys', {
        netId = netId ~= 0 and netId or nil,
        silent = silent == true,
        authorizationToken = authorizationToken,
        authorizationActionId = authorizationActionId,
    })
end

local previousCortexSpawnedVehicle = 0

function deleteOccupiedVehicleIfReplaceSpawnEnabled()
    if state.settings.replacePersonalVehicle == false then
        return
    end
    if previousCortexSpawnedVehicle ~= 0 and DoesEntityExist(previousCortexSpawnedVehicle) then
        SetEntityAsMissionEntity(previousCortexSpawnedVehicle, true, true)
        DeleteEntity(previousCortexSpawnedVehicle)
    end
    previousCortexSpawnedVehicle = 0
end

function registerCortexSpawnedVehicle(vehicle)
    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        previousCortexSpawnedVehicle = vehicle
    end
end

function seatPedInSpawnedVehicle(ped, vehicle)
    if state.settings.spawnInsideVehicle ~= false then
        SetPedIntoVehicle(ped, vehicle, -1)
    end
end

function spawnVehicleWithProps(props, authorizationActionId)
    if not props or not props.model then
        notify('error', 'Invalid vehicle data.')
        return
    end

    local modelActionId = authorizationActionId or 'vehicle.personal'
    local modelAuthorized, _, modelToken = authorizeModel('vehicle', props.model, modelActionId)
    if not modelAuthorized then return end

    deleteOccupiedVehicleIfReplaceSpawnEnabled()

    if not exports['cortex-lib']:requestModel(props.model, 5000) then
        notify('error', 'Unable to load vehicle model.')
        return
    end

    local ped = getPed()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local vehicle = CreateVehicle(props.model, coords.x, coords.y, coords.z, heading, true, false)

    if vehicle == 0 then
        notify('error', 'Failed to spawn vehicle.')
        return
    end

    registerCortexSpawnedVehicle(vehicle)
    seatPedInSpawnedVehicle(ped, vehicle)
    Wait(0)
    applyVehicleData(vehicle, props)
    Admin.giveKeysForVehicle(vehicle, true, modelToken, modelActionId)
    SetModelAsNoLongerNeeded(props.model)
    notify('success', 'Vehicle spawned.')
end

function normalizeModelHash(model)
    local hash = tonumber(model)
    if not hash then
        return nil
    end
    if hash > 2147483647 then
        hash = hash - 4294967296
    end
    return math.floor(hash)
end

function toUnsignedModelHash(model)
    local hash = normalizeModelHash(model)
    if not hash then
        return nil
    end
    if hash < 0 then
        hash = hash + 4294967296
    end
    return hash
end

function getVehicleLabel(model)
    local modelHash = normalizeModelHash(model) or model
    local displayName = GetDisplayNameFromVehicleModel(modelHash)
    local label = displayName and GetLabelText(displayName)
    if not label or label == '' or label == 'NULL' then
        label = displayName
    end
    if not label or label == '' or label == 'NULL' then
        label = tostring(model)
    end
    return label
end

function normalizePersonalVehicleData(data)
    if type(data) ~= 'table' then
        return { version = 2, vehicles = {} }
    end
    if data.version == 2 and type(data.vehicles) == 'table' then
        for i = 1, #data.vehicles do
            local entry = data.vehicles[i]
            if type(entry) == 'table' then
                entry.source = entry.source or C.PERSONAL_VEHICLE_SOURCE_ES_ADMIN
            end
        end
        return data
    end
    return { version = 2, vehicles = {} }
end

function migrateLegacyPersonalVehicles()
    local legacy = loadKvpJson(C.PERSONAL_VEHICLES_LEGACY_KEY, nil)
    if type(legacy) ~= 'table' then
        return { version = 2, vehicles = {} }
    end

    local list = { version = 2, vehicles = {} }
    for name, props in pairs(legacy) do
        if type(props) == 'table' and props.model then
            list.vehicles[#list.vehicles + 1] = {
                id = tostring(name),
                name = name,
                model = props.model,
                modelLabel = getVehicleLabel(props.model),
                category = props.category or 'other',
                source = C.PERSONAL_VEHICLE_SOURCE_ES_ADMIN,
                props = props,
            }
        end
    end

    return list
end

function loadStoredPersonalVehicles()
    local data = loadKvpJson(C.PERSONAL_VEHICLES_KEY, nil)
    if data and type(data) == 'table' and data.version == 2 then
        return normalizePersonalVehicleData(data)
    end

    local migrated = migrateLegacyPersonalVehicles()
    if #migrated.vehicles > 0 then
        saveKvpJson(C.PERSONAL_VEHICLES_KEY, migrated)
    end
    return migrated
end

function sortPersonalVehicles(list)
    table.sort(list, function(a, b)
        local catA = (a.category or ''):lower()
        local catB = (b.category or ''):lower()
        if catA ~= catB then
            return catA < catB
        end
        local nameA = (a.name or ''):lower()
        local nameB = (b.name or ''):lower()
        return nameA < nameB
    end)
end

function findPersonalVehicleIndex(list, id, name)
    local nameLower = name and name:lower() or nil
    for i = 1, #list do
        local entry = list[i]
        if (id and entry.id == id) or (nameLower and entry.name and entry.name:lower() == nameLower) then
            return i, entry
        end
    end
    return nil, nil
end

function normalizeNumberKeyMap(data, valueHandler)
    local out = {}
    if type(data) ~= 'table' then
        return out
    end

    for key, value in pairs(data) do
        local numericKey = tonumber(key)
        if numericKey then
            out[numericKey] = valueHandler and valueHandler(value) or value
        end
    end

    return out
end

function isVmenuVehicleData(data)
    return type(data) == 'table'
        and type(data.colors) == 'table'
        and type(data.mods) == 'table'
        and type(data.extras) == 'table'
        and data.Category ~= nil
        and data.plateText ~= nil
        and data.customWheels ~= nil
        and data.version ~= nil
        and tonumber(data.model) ~= nil
end

function convertVmenuDataToProps(saveName, data)
    local colors = data.colors or {}
    local model = normalizeModelHash(data.model)
    if not model then
        return nil
    end

    local props = {
        model = model,
        name = saveName,
        category = getVehicleCategoryFromModel(model),
        colors = {
            primary = tonumber(colors.primary) or 0,
            secondary = tonumber(colors.secondary) or 0,
            pearlescent = tonumber(colors.pearlescent) or 0,
            wheel = tonumber(colors.wheels) or tonumber(colors.wheel) or 0,
            dashboard = tonumber(colors.dash) or tonumber(colors.dashboard) or 0,
            trim = tonumber(colors.trim) or 0,
        },
        mods = normalizeNumberKeyMap(data.mods, function(value)
            return tonumber(value) or -1
        end),
        modColors = {
            primary = {
                type = math.max(0, math.min(math.floor(tonumber(colors.PrimaryPaintFinish) or 0), 5)),
                color = 0,
                pearlescent = tonumber(colors.pearlescent) or 0,
            },
            secondary = {
                type = math.max(0, math.min(math.floor(tonumber(colors.SecondaryPaintFinish) or 0), 5)),
                color = 0,
            },
        },
        extras = normalizeNumberKeyMap(data.extras, function(value)
            return value == true
        end),
        livery = tonumber(data.livery) or -1,
        plateStyle = tonumber(data.plateStyle) or 0,
        plateText = data.plateText or '',
        wheelType = tonumber(data.wheelType) or 0,
        windowTint = tonumber(data.windowTint) or 0,
        neonFront = data.neonFront == true,
        neonBack = data.neonBack == true,
        neonLeft = data.neonLeft == true,
        neonRight = data.neonRight == true,
        neonColor = {
            tonumber(colors.neonR) or 255,
            tonumber(colors.neonG) or 255,
            tonumber(colors.neonB) or 255,
        },
        tyreSmokeColor = {
            tonumber(colors.tyresmokeR) or 0,
            tonumber(colors.tyresmokeG) or 0,
            tonumber(colors.tyresmokeB) or 0,
        },
        xenonColor = tonumber(data.headlightColor) or -1,
        customPrimaryColor = nil,
        customSecondaryColor = nil,
        turbo = data.turbo == true,
        tyreSmoke = data.tyreSmoke == true,
        xenonHeadlights = data.xenonHeadlights == true,
        customWheels = data.customWheels == true,
        customWheelsRear = data.customWheels == true,
        tyresCanBurst = data.bulletProofTires ~= true,
        enveffScale = math.max(0.0, math.min(tonumber(data.enveffScale) or 0.0, 1.0)),
        version = tonumber(data.version) or 1,
    }

    local customPrimaryR = tonumber(colors.customPrimaryR)
    local customPrimaryG = tonumber(colors.customPrimaryG)
    local customPrimaryB = tonumber(colors.customPrimaryB)
    if customPrimaryR and customPrimaryG and customPrimaryB and customPrimaryR >= 0 and customPrimaryG >= 0 and customPrimaryB >= 0 then
        props.customPrimaryColor = { customPrimaryR, customPrimaryG, customPrimaryB }
    end

    local customSecondaryR = tonumber(colors.customSecondaryR)
    local customSecondaryG = tonumber(colors.customSecondaryG)
    local customSecondaryB = tonumber(colors.customSecondaryB)
    if customSecondaryR and customSecondaryG and customSecondaryB and customSecondaryR >= 0 and customSecondaryG >= 0 and customSecondaryB >= 0 then
        props.customSecondaryColor = { customSecondaryR, customSecondaryG, customSecondaryB }
    end

    return props
end

function buildVmenuVehicleDataFromProps(saveName, category, props)
    local colors = props.colors or {}
    local neonColor = props.neonColor or {}
    local smokeColor = props.tyreSmokeColor or {}
    local customPrimary = props.customPrimaryColor or {}
    local customSecondary = props.customSecondaryColor or {}
    local safeModel = normalizeModelHash(props.model) or 0
    local modelForVmenu = toUnsignedModelHash(safeModel) or 0

    return {
        colors = {
            primary = tonumber(colors.primary) or 0,
            secondary = tonumber(colors.secondary) or 0,
            pearlescent = tonumber(colors.pearlescent) or 0,
            wheels = tonumber(colors.wheel) or 0,
            dash = tonumber(colors.dashboard) or 0,
            trim = tonumber(colors.trim) or 0,
            neonR = tonumber(neonColor[1]) or 255,
            neonG = tonumber(neonColor[2]) or 255,
            neonB = tonumber(neonColor[3]) or 255,
            tyresmokeR = tonumber(smokeColor[1]) or 0,
            tyresmokeG = tonumber(smokeColor[2]) or 0,
            tyresmokeB = tonumber(smokeColor[3]) or 0,
            customPrimaryR = tonumber(customPrimary[1]) or -1,
            customPrimaryG = tonumber(customPrimary[2]) or -1,
            customPrimaryB = tonumber(customPrimary[3]) or -1,
            customSecondaryR = tonumber(customSecondary[1]) or -1,
            customSecondaryG = tonumber(customSecondary[2]) or -1,
            customSecondaryB = tonumber(customSecondary[3]) or -1,
            PrimaryPaintFinish = props.modColors and props.modColors.primary and tonumber(props.modColors.primary.type) or nil,
            SecondaryPaintFinish = props.modColors and props.modColors.secondary and tonumber(props.modColors.secondary.type) or nil,
        },
        customWheels = props.customWheels == true,
        extras = normalizeNumberKeyMap(props.extras, function(value)
            return value == true
        end),
        livery = tonumber(props.livery) or -1,
        model = modelForVmenu,
        mods = normalizeNumberKeyMap(props.mods, function(value)
            return tonumber(value) or -1
        end),
        name = saveName or getVehicleLabel(safeModel),
        neonBack = props.neonBack == true,
        neonFront = props.neonFront == true,
        neonLeft = props.neonLeft == true,
        neonRight = props.neonRight == true,
        plateText = props.plateText or '',
        plateStyle = tonumber(props.plateStyle) or 0,
        turbo = props.turbo == true,
        tyreSmoke = props.tyreSmoke == true,
        version = 1,
        wheelType = tonumber(props.wheelType) or 0,
        windowTint = tonumber(props.windowTint) or 0,
        xenonHeadlights = props.xenonHeadlights == true,
        bulletProofTires = props.tyresCanBurst == false,
        headlightColor = tonumber(props.xenonColor) or -1,
        enveffScale = math.max(0.0, math.min(tonumber(props.enveffScale) or 0.0, 1.0)),
        Category = category or 'Uncategorized',
    }
end

function buildVmenuVehicleEntry(key, decoded)
    local saveName = key:sub(#C.VMENU_VEHICLE_KEY_PREFIX + 1)
    if saveName == '' then
        saveName = decoded.name or key
    end

    local props = convertVmenuDataToProps(saveName, decoded)
    if not props then
        return nil
    end

    return {
        id = ('vmenu:%s'):format(key:lower()),
        name = saveName,
        model = props.model,
        modelLabel = getVehicleLabel(props.model),
        category = props.category or 'other',
        source = C.PERSONAL_VEHICLE_SOURCE_VMENU,
        sourceKey = key,
        vmenuCategory = type(decoded.Category) == 'string' and decoded.Category or 'Uncategorized',
        props = props,
    }
end

function mergeVmenuVehicles(personalData)
    local vehicles = personalData.vehicles or {}
    local ok, rawVehicles = callVmenuBridge('GetSavedVehiclesForEsAdmin')
    if not ok or type(rawVehicles) ~= 'table' then
        local snapshot = getVmenuFallbackSnapshot()
        rawVehicles = snapshot and snapshot.vehicles or nil
        if type(rawVehicles) ~= 'table' then
            personalData.vehicles = vehicles
            return personalData
        end
    end

    for i = 1, #rawVehicles do
        local item = rawVehicles[i]
        local key = item and item.key
        local decoded = item and item.data
        if type(key) == 'string' and isVmenuVehicleData(decoded) then
            local vmenuEntry = buildVmenuVehicleEntry(key, decoded)
            if vmenuEntry then
                local index, existing = findPersonalVehicleIndex(vehicles, vmenuEntry.id, vmenuEntry.name)
                if index then
                    if existing.source ~= C.PERSONAL_VEHICLE_SOURCE_ES_ADMIN then
                        vehicles[index] = vmenuEntry
                    end
                else
                    vehicles[#vehicles + 1] = vmenuEntry
                end
            end
        end
    end

    sortPersonalVehicles(vehicles)
    personalData.vehicles = vehicles
    return personalData
end

function loadPersonalVehicles()
    local stored = loadStoredPersonalVehicles()
    return mergeVmenuVehicles(stored)
end

function savePersonalVehicles(data)
    local normalized = normalizePersonalVehicleData(data)
    local persist = { version = 2, vehicles = {} }

    for i = 1, #normalized.vehicles do
        local entry = normalized.vehicles[i]
        if type(entry) == 'table' and entry.source ~= C.PERSONAL_VEHICLE_SOURCE_VMENU then
            persist.vehicles[#persist.vehicles + 1] = entry
        end
    end

    saveKvpJson(C.PERSONAL_VEHICLES_KEY, persist)
end

local function emptyDomainResult(total)
    return { imported = 0, skipped = 0, invalid = 0, failed = 0, total = total or 0 }
end

local function safeImportedKey(value, requiredPrefix)
    if type(value) ~= 'string' or value == '' or #value > 128 or value:find('[%z\1-\31\127]') then return nil end
    if requiredPrefix and value:sub(1, #requiredPrefix) ~= requiredPrefix then return nil end
    return value
end

local function importVmenuNonMpPeds(snapshot)
    local source = type(snapshot) == 'table' and snapshot.nonMpPeds or nil
    local result = emptyDomainResult(type(source) == 'table' and #source or 0)
    if type(source) ~= 'table' then result.reason = 'unavailable'; return result end
    for index = 1, #source do
        local item = source[index]
        local key = item and safeImportedKey(item.key, 'ped_')
        local data = item and cloneJsonTable(item.data)
        local model = data and tonumber(data.ModelHash or data.model)
        if not key or not data or not model or model ~= math.floor(model) then
            result.invalid = result.invalid + 1
        elseif GetResourceKvpString(key) then
            result.skipped = result.skipped + 1
        else
            data.ModelHash = model
            data.model = model
            data.SaveName = type(data.SaveName) == 'string' and data.SaveName or key:sub(5)
            data.ImportedFrom = C.MP_PED_SOURCE_VMENU
            data.ImportedSourceKey = key
            if saveKvpJson(key, data) then result.imported = result.imported + 1 else result.failed = result.failed + 1 end
        end
    end
    return result
end

local function normalizeImportedWeapon(raw)
    if type(raw) ~= 'table' then return nil end
    local name = raw.SpawnName or raw.spawnName or raw.name
    if type(name) ~= 'string' or #name > 64 or not name:lower():match('^weapon_[%w_]+$') then return nil end
    local components = {}
    if type(raw.Components or raw.components) == 'table' then
        for key, value in pairs(raw.Components or raw.components) do
            local component = tonumber(value) or (type(key) == 'string' and key:match('^component_') and key:lower() or nil)
            if component and #components < 64 then components[#components + 1] = component end
        end
    end
    return {
        name = name:lower(),
        ammo = math.max(0, math.min(math.floor(tonumber(raw.CurrentAmmo or raw.ammo) or 250), 9999)),
        components = components,
        tint = math.max(0, math.min(math.floor(tonumber(raw.CurrentTint or raw.tint) or 0), 31)),
    }
end

local function convertVmenuLoadout(raw)
    if type(raw) ~= 'table' then return nil end
    local weapons = {}
    for index = 1, math.min(#raw, 256) do
        local weapon = normalizeImportedWeapon(raw[index])
        if weapon then weapons[#weapons + 1] = weapon end
    end
    if #weapons == 0 and #raw > 0 then return nil end
    return { weapons = weapons, savedAt = currentUnixTime(), importedFrom = 'vmenu' }
end

local function importVmenuWeaponLoadouts(snapshot)
    local source = type(snapshot) == 'table' and snapshot.weaponLoadouts or nil
    local total = type(source) == 'table' and #source or 0
    if type(snapshot) == 'table' and type(snapshot.temporaryLoadout) == 'table' then total = total + 1 end
    local result = emptyDomainResult(total)
    if type(source) ~= 'table' then result.reason = 'unavailable'; return result end
    local existing = loadWeaponLoadoutsRaw()
    local sourceToName = {}
    local function importOne(sourceKey, raw, fallbackName)
        local key = safeImportedKey(sourceKey)
        local name = key and key:match('^vmenu_string_saved_weapon_loadout_(.+)$') or fallbackName
        if not name or name == '' or #name > 64 then result.invalid = result.invalid + 1; return end
        sourceToName[key or sourceKey] = name
        if existing[name] then result.skipped = result.skipped + 1; return end
        local converted = convertVmenuLoadout(raw)
        if not converted then result.invalid = result.invalid + 1; return end
        converted.importedSourceKey = sourceKey
        existing[name] = converted
        result.imported = result.imported + 1
    end
    for index = 1, #source do
        local item = source[index]
        importOne(item and item.key, item and item.data)
    end
    if type(snapshot.temporaryLoadout) == 'table' then
        importOne('vmenu_temp_weapons_loadout_before_respawn', snapshot.temporaryLoadout, 'Recovered pre-respawn')
    end
    if result.imported > 0 and not saveKvpJson(C.WEAPON_LOADOUTS_KEY, existing) then
        result.failed = result.failed + result.imported
        result.imported = 0
    end
    local defaultKey = type(snapshot.defaultLoadout) == 'string' and snapshot.defaultLoadout or nil
    local defaultName = defaultKey and (sourceToName[defaultKey] or defaultKey:match('^vmenu_string_saved_weapon_loadout_(.+)$')) or nil
    if defaultName and existing[defaultName] then result.defaultName = defaultName end
    return result
end

local vmenuSettingToggles = {
    autoEquipParachuteWhenInPlane = 'weapons.autoEquipParachute', everyoneIgnorePlayer = 'player.everyoneIgnores',
    fastRun = 'player.fastRun', fastSwim = 'player.fastSwim', neverWanted = 'player.neverWanted', noRagdoll = 'player.noRagdoll',
    playerGodMode = 'player.godmode', playerStayInVehicle = 'player.stayInVehicle', superJump = 'player.superjump',
    unlimitedStamina = 'player.infiniteStamina', vehicleAnchorBoat = 'vehicle.anchorBoat', vehicleBikeSeatbelt = 'vehicle.bikeSeatbelt',
    vehicleEngineAlwaysOn = 'vehicle.engineAlwaysOn', vehicleGodAutoRepair = 'vehicle.autoRepair', vehicleGodEngine = 'vehicle.preventEngineDamage',
    vehicleGodInvincible = 'vehicle.invincible', vehicleGodStrongWheels = 'vehicle.strongWheels', vehicleGodVisual = 'vehicle.preventVisualDamage',
    vehicleHighbeamsOnHonk = 'vehicle.flashHighbeams', vehicleNeverDirty = 'vehicle.keepClean', vehicleNoBikeHelmet = 'vehicle.noHelmet',
    vehicleNoSiren = 'vehicle.noSiren', voiceChatEnabled = 'voice.enabled', voiceChatShowSpeaker = 'voice.showSpeaker',
    voiceChatShowVoiceStatus = 'voice.showStatus', weaponLoadoutsSetLoadoutOnRespawn = 'weapons.restoreLoadoutOnRespawn',
    weaponsNoReload = 'weapons.noReload', weaponsUnlimitedAmmo = 'weapons.infiniteAmmo', weaponsUnlimitedParachutes = 'weapons.unlimitedParachutes',
    miscDeathNotifications = 'dev.deathNotifications', miscJoinQuitNotifications = 'dev.joinQuitNotifications', miscLocationBlips = 'dev.locationBlips',
    miscShowOverheadNames = 'dev.overheadNames', miscShowPlayerBlips = 'dev.playerBlips', miscShowTime = 'dev.showTime',
    miscShowLocation = 'dev.showCoords', miscRestorePlayerWeapons = 'weapons.restoreLoadoutOnRespawn',
    kbDriftMode = 'dev.driftMode', kbTpToWaypoint = 'options.teleportWaypointKey', vehicleSpawnerReplacePrevious = 'options.replacePersonalVehicle',
}

local function importVmenuSettings(snapshot)
    local settings = type(snapshot) == 'table' and snapshot.settings or nil
    local result = emptyDomainResult(countTableEntries(settings))
    if type(settings) ~= 'table' then result.reason = 'unavailable'; return result end
    for sourceKey, actionId in pairs(vmenuSettingToggles) do
        local value = settings[sourceKey]
        if type(value) == 'boolean' then
            if type(Admin.toggleAction) == 'function' then
                Admin.toggleAction(actionId, value)
                result.imported = result.imported + 1
            else
                result.failed = result.failed + 1
            end
        end
    end
    if type(settings.miscRightAlignMenu) == 'boolean' then
        state.settings.menuPosition = settings.miscRightAlignMenu and 'right' or 'left'
        result.imported = result.imported + 1
    end
    if type(settings.miscSpeedoKmh) == 'boolean' and settings.miscSpeedoKmh then
        state.settings.speedHudUnits = 'kph'; result.imported = result.imported + 1
        if type(Admin.toggleAction) == 'function' then Admin.toggleAction('dev.showSpeed', true) end
    elseif type(settings.miscSpeedoMph) == 'boolean' and settings.miscSpeedoMph then
        state.settings.speedHudUnits = 'mph'; result.imported = result.imported + 1
        if type(Admin.toggleAction) == 'function' then Admin.toggleAction('dev.showSpeed', true) end
    end
    if type(settings.miscRestorePlayerAppearance) == 'boolean' then
        state.settings.restorePedOnDeath = settings.miscRestorePlayerAppearance; result.imported = result.imported + 1
    end
    if type(settings.vehicleDisableHelicopterTurbulence) == 'boolean' or type(settings.vehicleDisablePlaneTurbulence) == 'boolean' then
        state.settings.disableAircraftTurbulence = settings.vehicleDisableHelicopterTurbulence == true or settings.vehicleDisablePlaneTurbulence == true
        result.imported = result.imported + 1
    end
    if EsAdmin.saveSettings then EsAdmin.saveSettings() end
    return result
end

local VMENU_CONFIG_DOMAIN_NAMES = { 'addons', 'extras', 'locations', 'modelWhitelists', 'tattoos' }

local function fetchVmenuConfigDomains(serverState)
    local domains = {}
    local failures = {}
    local metadata = type(serverState) == 'table' and serverState.config and serverState.config.domains or {}
    for index = 1, #VMENU_CONFIG_DOMAIN_NAMES do
        local domain = VMENU_CONFIG_DOMAIN_NAMES[index]
        local entry = type(metadata) == 'table' and metadata[domain] or nil
        if type(entry) == 'table' and entry.available == true and type(Admin.getVmenuConfigDomain) == 'function' then
            local data, reason = Admin.getVmenuConfigDomain(domain)
            if type(data) == 'table' then
                domains[domain] = data
            else
                failures[domain] = reason or 'unavailable'
            end
        end
    end
    return domains, failures
end

local function importVmenuCategories(snapshot)
    local output = { peds = {}, vehicles = {} }
    local summary = { peds = 0, vehicles = 0, invalid = 0 }
    local sources = {
        { name = 'peds', entries = type(snapshot) == 'table' and snapshot.pedCategories or nil },
        { name = 'vehicles', entries = type(snapshot) == 'table' and snapshot.vehicleCategories or nil },
    }

    for sourceIndex = 1, #sources do
        local source = sources[sourceIndex]
        local entries = type(source.entries) == 'table' and source.entries or {}
        for index = 1, math.min(#entries, 1024) do
            local entry = entries[index]
            local key = entry and safeImportedKey(entry.key)
            local data = entry and cloneJsonTable(entry.data)
            if key and data then
                output[source.name][#output[source.name] + 1] = { key = key, data = data }
                summary[source.name] = summary[source.name] + 1
            else
                summary.invalid = summary.invalid + 1
            end
        end
    end

    local saved = type(Admin.setVmenuImportedCategories) == 'function' and Admin.setVmenuImportedCategories(output) == true
    summary.saved = saved
    if not saved and (summary.peds > 0 or summary.vehicles > 0) then summary.failed = 1 else summary.failed = 0 end
    return summary
end

local function importVmenuLocations(configDomains)
    local locations = type(configDomains) == 'table' and configDomains.locations or nil
    local teleports = type(locations) == 'table' and locations.teleports or nil
    local result = emptyDomainResult(type(teleports) == 'table' and #teleports or 0)
    if type(teleports) ~= 'table' then result.reason = 'unavailable'; return result end
    local existing = loadSavedTeleportLocationsRaw()
    for index = 1, math.min(#teleports, 1024) do
        local entry = teleports[index]
        local coords = type(entry) == 'table' and entry.coordinates or nil
        local name = type(entry) == 'table' and entry.name or nil
        local x, y, z = coords and tonumber(coords.x), coords and tonumber(coords.y), coords and tonumber(coords.z)
        if type(name) ~= 'string' or name == '' or #name > 96 or not x or not y or not z
            or x ~= x or y ~= y or z ~= z or math.abs(x) > 20000 or math.abs(y) > 20000 or math.abs(z) > 20000 then
            result.invalid = result.invalid + 1
        elseif existing[name] then
            result.skipped = result.skipped + 1
        else
            existing[name] = { x = x, y = y, z = z, h = tonumber(entry.heading) or 0.0, importedFrom = 'vmenu' }
            result.imported = result.imported + 1
        end
    end
    if result.imported > 0 and not saveKvpJson(C.TELEPORT_LOCATIONS_KEY, existing) then
        result.failed = result.failed + result.imported; result.imported = 0
    end
    return result
end

Admin.getVmenuMigrationSnapshot = function()
    local pedPayload, defaultPedKey, pedSource = getVmenuSavedPedPayload()
    local vehiclePayload, vehicleSource = getVmenuVehiclePayload()
    local fallback = getVmenuFallbackSnapshot()
    local serverState = type(Admin.getVmenuServerState) == 'function' and Admin.getVmenuServerState(false) or nil
    local storedVehicles = loadStoredPersonalVehicles()
    local storedVehicleCount = storedVehicles and storedVehicles.vehicles and #storedVehicles.vehicles or 0
    local configDomains = {}
    if type(serverState) == 'table' and type(serverState.config) == 'table' and type(serverState.config.domains) == 'table' then
        for domain, entry in pairs(serverState.config.domains) do
            configDomains[domain] = {
                available = type(entry) == 'table' and entry.available == true,
                count = type(entry) == 'table' and tonumber(entry.count) or 0,
                sourceResource = type(entry) == 'table' and entry.sourceResource or nil,
                importedAt = type(entry) == 'table' and entry.importedAt or nil,
            }
        end
    end
    local ledger = loadKvpJson(Config.KvpKeys.vmenuImport, {})
    local storedCategories = loadKvpJson(Config.KvpKeys.vmenuCategories, {})

    return {
        vmenuRunning = GetResourceState('vMenu') == 'started',
        generatedAt = currentUnixTime(),
        peds = {
            available = type(pedPayload) == 'table',
            count = type(pedPayload) == 'table' and #pedPayload or 0,
            source = pedSource or 'unavailable',
            defaultKey = defaultPedKey,
            importedCount = #getEsAdminSavedPeds(),
        },
        vehicles = {
            available = type(vehiclePayload) == 'table',
            count = type(vehiclePayload) == 'table' and #vehiclePayload or 0,
            source = vehicleSource or 'unavailable',
            importedCount = storedVehicleCount,
        },
        nonMpPeds = {
            available = type(fallback) == 'table' and type(fallback.nonMpPeds) == 'table',
            count = type(fallback) == 'table' and type(fallback.nonMpPeds) == 'table' and #fallback.nonMpPeds or 0,
            source = type(fallback) == 'table' and fallback.scope or 'unavailable',
        },
        weaponLoadouts = {
            available = type(fallback) == 'table' and type(fallback.weaponLoadouts) == 'table',
            count = type(fallback) == 'table' and type(fallback.weaponLoadouts) == 'table' and #fallback.weaponLoadouts or 0,
            hasTemporary = type(fallback) == 'table' and type(fallback.temporaryLoadout) == 'table',
            defaultKey = type(fallback) == 'table' and fallback.defaultLoadout or nil,
            importedCount = countTableEntries(loadWeaponLoadoutsRaw()),
        },
        settings = {
            available = type(fallback) == 'table' and type(fallback.settings) == 'table',
            count = type(fallback) == 'table' and countTableEntries(fallback.settings) or 0,
        },
        categories = {
            peds = type(fallback) == 'table' and type(fallback.pedCategories) == 'table' and #fallback.pedCategories or 0,
            vehicles = type(fallback) == 'table' and type(fallback.vehicleCategories) == 'table' and #fallback.vehicleCategories or 0,
            importedPeds = type(storedCategories.peds) == 'table' and #storedCategories.peds or 0,
            importedVehicles = type(storedCategories.vehicles) == 'table' and #storedCategories.vehicles or 0,
        },
        config = {
            available = type(serverState) == 'table' and serverState.ok == true,
            resource = type(serverState) == 'table' and serverState.resource or nil,
            domains = configDomains,
        },
        bans = {
            available = type(serverState) == 'table' and serverState.ok == true,
            count = type(serverState) == 'table' and serverState.bans and tonumber(serverState.bans.count) or 0,
        },
        fallback = type(fallback) == 'table' and {
            ok = fallback.ok == true,
            reason = fallback.reason,
            scope = fallback.scope,
            localHostOnly = fallback.localHostOnly == true,
            parser = fallback.parser,
        } or { ok = false, reason = 'unavailable' },
        previousImport = type(ledger) == 'table' and ledger or {},
        permissions = getPermissionMigrationSummary(),
    }
end

Admin.importVmenuSavedVehicles = function(options)
    local silent = type(options) == 'table' and options.silent == true
    local rawVehicles = getVmenuVehiclePayload()
    if type(rawVehicles) ~= 'table' then
        if not silent then
            notify('error', 'Failed to read saved vMenu vehicles.')
        end
        return false, { reason = 'read_failed' }
    end

    local personalData = loadStoredPersonalVehicles()
    local vehicles = personalData.vehicles or {}
    local result = {
        imported = 0,
        skipped = 0,
        invalid = 0,
        total = #rawVehicles,
    }

    for i = 1, #rawVehicles do
        local item = rawVehicles[i]
        local key = item and item.key
        local decoded = item and item.data
        if type(key) == 'string' and isVmenuVehicleData(decoded) then
            local vmenuEntry = buildVmenuVehicleEntry(key, decoded)
            if vmenuEntry and vmenuEntry.props and vmenuEntry.props.model then
                local importedId = key
                local index, existing = findPersonalVehicleIndex(vehicles, importedId, vmenuEntry.name)
                if index and existing and existing.source == C.PERSONAL_VEHICLE_SOURCE_ES_ADMIN then
                    result.skipped = result.skipped + 1
                else
                    local importedEntry = {
                        id = importedId,
                        name = vmenuEntry.name,
                        model = vmenuEntry.model,
                        modelLabel = vmenuEntry.modelLabel,
                        category = vmenuEntry.category or 'other',
                        source = C.PERSONAL_VEHICLE_SOURCE_ES_ADMIN,
                        importedFrom = C.PERSONAL_VEHICLE_SOURCE_VMENU,
                        importedSourceKey = key,
                        vmenuCategory = vmenuEntry.vmenuCategory,
                        props = cloneJsonTable(vmenuEntry.props),
                    }

                    if index then
                        vehicles[index] = importedEntry
                    else
                        vehicles[#vehicles + 1] = importedEntry
                    end
                    result.imported = result.imported + 1
                end
            else
                result.invalid = result.invalid + 1
            end
        else
            result.invalid = result.invalid + 1
        end
    end

    sortPersonalVehicles(vehicles)
    personalData.vehicles = vehicles
    savePersonalVehicles(personalData)

    if Admin.refreshPersonalVehiclesCache then
        Admin.refreshPersonalVehiclesCache()
    end

    if Admin.getPersonalVehiclesCache then
        SendNUIMessage({
            action = 'cortex-admin:setState',
            data = { personalVehicles = Admin.getPersonalVehiclesCache() }
        })
    end

    if not silent then
        local notifyType = result.imported > 0 and 'success' or 'error'
        notify(notifyType, formatSavedVehicleImportSummary(result))
    end

    return true, result
end

Admin.importVmenuMigrationData = function()
    local fallback = getVmenuFallbackSnapshot(true) or {}
    local serverState = type(Admin.getVmenuServerState) == 'function' and Admin.getVmenuServerState(true) or nil
    local configDomains, configFailures = fetchVmenuConfigDomains(serverState)
    local pedOk, pedResult = Admin.importVmenuSavedPeds({ silent = true })
    local vehicleOk, vehicleResult = Admin.importVmenuSavedVehicles({ silent = true })
    local nonMpPedResult = importVmenuNonMpPeds(fallback)
    local loadoutResult = importVmenuWeaponLoadouts(fallback)
    local settingResult = importVmenuSettings(fallback)
    local locationResult = importVmenuLocations(configDomains)
    local categoryResult = importVmenuCategories(fallback)
    local configSaved = type(Admin.setVmenuImportedConfig) == 'function' and Admin.setVmenuImportedConfig(configDomains) == true

    if loadoutResult.defaultName and type(Admin.executeAction) == 'function' then
        Admin.executeAction('weapons.defaultLoadout', { name = loadoutResult.defaultName })
    end

    local summary = {
        ok = false,
        peds = pedResult or { reason = 'not_attempted' },
        nonMpPeds = nonMpPedResult,
        vehicles = vehicleResult or { reason = 'not_attempted' },
        weaponLoadouts = loadoutResult,
        settings = settingResult,
        locations = locationResult,
        categories = categoryResult,
        config = {
            saved = configSaved,
            failures = configFailures,
            domains = type(serverState) == 'table' and serverState.config and serverState.config.domains or {},
            importResult = type(serverState) == 'table' and serverState.config and serverState.config.importResult or nil,
        },
        bans = type(serverState) == 'table' and serverState.bans or { reason = 'unavailable' },
        permissions = getPermissionMigrationSummary(),
        completedAt = currentUnixTime(),
    }

    local domains = { summary.peds, summary.nonMpPeds, summary.vehicles, summary.weaponLoadouts, summary.settings, summary.locations }
    for index = 1, #domains do
        local domain = domains[index]
        if type(domain) == 'table' and ((tonumber(domain.total) or 0) > 0 or (tonumber(domain.imported) or 0) > 0) then
            summary.ok = true
            break
        end
    end
    if type(serverState) == 'table' and serverState.config and serverState.config.importResult
        and (tonumber(serverState.config.importResult.imported) or 0) > 0 then summary.ok = true end
    if configSaved and next(configDomains) ~= nil then summary.ok = true end
    if categoryResult.saved and ((categoryResult.peds or 0) > 0 or (categoryResult.vehicles or 0) > 0) then summary.ok = true end

    local persisted = {
        version = 2,
        importedAt = summary.completedAt,
        domains = {
            peds = summary.peds, nonMpPeds = summary.nonMpPeds, vehicles = summary.vehicles,
            weaponLoadouts = summary.weaponLoadouts, settings = summary.settings, locations = summary.locations,
            categories = summary.categories,
        },
        server = type(serverState) == 'table' and {
            config = {
                domains = serverState.config and serverState.config.domains or {},
                importResult = serverState.config and serverState.config.importResult or nil,
                savedLocally = configSaved,
            },
            bans = { count = serverState.bans and serverState.bans.count or 0 },
            resource = serverState.resource,
        } or nil,
    }
    if type(Admin.setVmenuImportedData) == 'function' then
        Admin.setVmenuImportedData(persisted)
    else
        saveKvpJson(Config.KvpKeys.vmenuImport, persisted)
    end

    if not summary.ok then
        notify('error', 'vMenu migration failed. No importable data was found.')
        return false, summary
    end

    local segments = {}
    segments[#segments + 1] = ('outfits imported %d'):format(tonumber(summary.peds.imported) or 0)
    segments[#segments + 1] = ('peds imported %d'):format(tonumber(summary.nonMpPeds.imported) or 0)
    segments[#segments + 1] = ('vehicles imported %d'):format(tonumber(summary.vehicles.imported) or 0)
    segments[#segments + 1] = ('loadouts imported %d'):format(tonumber(summary.weaponLoadouts.imported) or 0)
    segments[#segments + 1] = ('locations imported %d'):format(tonumber(summary.locations.imported) or 0)
    notify('success', ('vMenu migration complete: %s. ACE permissions remain active.'):format(table.concat(segments, ', ')))
    return true, summary
end

Admin.loadPersonalVehicles = loadPersonalVehicles
if Admin.refreshPersonalVehiclesCache then
    local ok, err = pcall(Admin.refreshPersonalVehiclesCache)
    if not ok then
        print(('[cortex-admin] WARNING: Failed to refresh personal vehicle cache during actions init: %s'):format(tostring(err)))
    end
end

function buildPersonalVehiclesSummary(list)
    local summary = {}
    for i = 1, #list do
        local entry = list[i]
        summary[#summary + 1] = {
            id = entry.id,
            name = entry.name,
            model = entry.model,
            modelLabel = entry.modelLabel,
            category = entry.category,
        }
    end
    return summary
end

function actionSpawnVehicleList(data)
    local model = data and data.value
    if not model or model == '' then
        notify('error', 'Vehicle model required.')
        return
    end

    actionSpawnVehicle({ model = model })
end

function actionSaveVehicle(data)
    local name = data and data.name
    if not name or name == '' then
        notify('error', 'Vehicle name required.')
        return
    end

    local vehicle = ensureVehicle()
    if not vehicle then return end

    local props = captureVehicleData(vehicle, name)
    saveKvpJson(kvpKey('veh_', name), props)
    notify('success', 'Vehicle saved.')
end

function actionSaveVehicleLegacy()
    local vehicle = ensureVehicle()
    if not vehicle then return end

    local props = captureVehicleData(vehicle, 'saved')
    state.savedVehicle = props
    notify('success', 'Vehicle properties saved.')
end

function actionLoadVehicle(data)
    local name = data and data.name
    if not name or name == '' then
        notify('error', 'Vehicle name required.')
        return
    end

    local props = loadKvpJson(kvpKey('veh_', name))
    if not props then
        notify('error', 'Saved vehicle not found.')
        return
    end

    spawnVehicleWithProps(props, 'vehicle.load')
end

function actionSavePersonalVehicle(data)
    local name = data and data.name
    local id = data and data.id

    local vehicle = ensureVehicle()
    if not vehicle then return end

    local personalData = loadPersonalVehicles()
    local vehicles = personalData.vehicles or {}
    local index, existing = findPersonalVehicleIndex(vehicles, id, name)

    if (not name or name == '') and existing then
        name = existing.name
    end

    if not name or name == '' then
        notify('error', 'Vehicle name required.')
        return
    end

    local props = captureVehicleData(vehicle, name)
    if existing and existing.source == C.PERSONAL_VEHICLE_SOURCE_VMENU and existing.sourceKey then
        if not ensureVmenuWriteBridge('update') then
            return
        end

        local vmenuData = buildVmenuVehicleDataFromProps(name, existing.vmenuCategory, props)
        local updated, result = callVmenuBridge('UpdateSavedVehicleForEsAdmin', existing.sourceKey, vmenuData)
        if updated and result == true then
            notify('success', 'vMenu vehicle updated.')
        else
            print(('[cortex-admin] vMenu update failed: %s'):format(tostring(result)))
            notify('error', 'Failed to update vMenu vehicle.')
        end

        Admin.refreshPersonalVehiclesCache()
        SendNUIMessage({
            action = 'cortex-admin:setState',
            data = { personalVehicles = Admin.getPersonalVehiclesCache() }
        })
        return
    end

    local entry = {
        id = (existing and existing.id) or id or ('veh_' .. tostring(GetGameTimer()) .. '_' .. tostring(math.random(1000, 9999))),
        name = name,
        model = props.model,
        modelLabel = getVehicleLabel(props.model),
        category = props.category or 'other',
        source = C.PERSONAL_VEHICLE_SOURCE_ES_ADMIN,
        props = props,
    }

    if index then
        vehicles[index] = entry
    else
        vehicles[#vehicles + 1] = entry
    end

    sortPersonalVehicles(vehicles)
    personalData.vehicles = vehicles
    savePersonalVehicles(personalData)
    notify('success', index and 'Personal vehicle updated.' or 'Personal vehicle saved.')

    Admin.refreshPersonalVehiclesCache()
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { personalVehicles = Admin.getPersonalVehiclesCache() }
    })
end

function actionRemovePersonalVehicle(data)
    local name = data and data.name
    local id = data and data.id
    if (not id or id == '') and (not name or name == '') then
        notify('error', 'Vehicle id or name required.')
        return
    end

    local personalData = loadPersonalVehicles()
    local vehicles = personalData.vehicles or {}
    local index, entry = findPersonalVehicleIndex(vehicles, id, name)
    if not index then
        notify('error', 'Vehicle not found in personal list.')
        return
    end

    if entry and entry.source == C.PERSONAL_VEHICLE_SOURCE_VMENU then
        if not ensureVmenuWriteBridge('remove') then
            return
        end

        local sourceKey = entry.sourceKey or (C.VMENU_VEHICLE_KEY_PREFIX .. (entry.name or ''))
        if sourceKey == C.VMENU_VEHICLE_KEY_PREFIX then
            notify('error', 'Unable to resolve vMenu key for this vehicle.')
            return
        end

        local deleted, result = callVmenuBridge('DeleteSavedVehicleForEsAdmin', sourceKey)
        if deleted and result == true then
            notify('success', 'Removed vMenu saved vehicle.')
        else
            print(('[cortex-admin] vMenu delete failed: %s'):format(tostring(result)))
            notify('error', 'Failed to remove vMenu saved vehicle.')
            return
        end

        Admin.refreshPersonalVehiclesCache()
        SendNUIMessage({
            action = 'cortex-admin:setState',
            data = { personalVehicles = Admin.getPersonalVehiclesCache() }
        })
        return
    end

    table.remove(vehicles, index)
    personalData.vehicles = vehicles
    savePersonalVehicles(personalData)
    notify('success', 'Personal vehicle removed.')

    Admin.refreshPersonalVehiclesCache()
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { personalVehicles = Admin.getPersonalVehiclesCache() }
    })
end

function actionSpawnPersonalVehicle(data)
    local name = data and (data.name or data.value)
    local id = data and data.id
    if (not id or id == '') and (not name or name == '') then
        notify('error', 'Vehicle id or name required.')
        return
    end

    local personalData = loadPersonalVehicles()
    local vehicles = personalData.vehicles or {}
    local _, entry = findPersonalVehicleIndex(vehicles, id, name)
    local props = entry and entry.props
    if not props then
        notify('error', 'Personal vehicle not found.')
        return
    end

    spawnVehicleWithProps(props, 'vehicle.personal')
end

function actionSaveMpPed(data)
    local entry = nil
    if type(data) == 'table' and (type(data.entry) == 'table' or data.id or data.source or data.sourceKey) then
        entry = resolveSavedPedEntry(data.entry or data)
    end

    local name = data and data.name
    if entry and (not name or name == '') then
        name = entry.name
    end

    if not name or name == '' then
        notify('error', 'Name required.')
        return
    end

    local ped = getPed()
    local model = GetEntityModel(ped)
    if model ~= joaat('mp_m_freemode_01') and model ~= joaat('mp_f_freemode_01') then
        notify('error', 'Not a freemode ped.')
        return
    end

    local mpData = captureMpPedData(ped, name)
    if entry and entry.source == C.MP_PED_SOURCE_VMENU then
        if not ensureVmenuWriteBridge('overwrite') then
            return
        end

        local merged = buildOverwriteSavedPedData(entry, mpData)
        merged.SaveName = entry.sourceKey

        local saved, result = callVmenuBridge('UpsertSavedMpCharacterForEsAdmin', entry.sourceKey, merged, true)
        if not saved then
            print(('[cortex-admin] vMenu outfit overwrite failed: %s'):format(tostring(result)))
            notify('error', 'Failed to overwrite vMenu outfit.')
            return
        end

        setLastSavedPedReference({
            name = entry.name,
            source = C.MP_PED_SOURCE_VMENU,
            sourceKey = entry.sourceKey,
        })
        notify('success', 'vMenu outfit updated: ' .. entry.name)
        return
    end

    local key = (entry and entry.sourceKey) or kvpKey(C.MP_PED_KEY_PREFIX, name)
    mpData.SaveName = name

    print(('[cortex-admin] Saving MP Ped: %s to key: %s'):format(name, key))

    if not saveKvpJson(key, mpData) then
        notify('error', 'Failed to save MP ped.')
        return
    end

    setLastSavedPedReference({
        name = name,
        source = C.MP_PED_SOURCE_ES_ADMIN,
        sourceKey = key,
    })

    notify('success', (entry and 'MP ped updated: ' or 'MP ped saved: ') .. name)
end

function actionLoadMpPed(data)
    local entry = resolveSavedPedEntry(data)
    if not entry then
        notify('error', 'Saved MP ped not found.')
        return
    end

    local mpData = loadSavedPedData(entry)
    if not mpData then
        notify('error', 'Saved MP ped not found.')
        return
    end

    if not applyMpPedData(getPed(), mpData) then return end

    setLastSavedPedReference({
        name = entry.name,
        source = entry.source,
        sourceKey = entry.sourceKey,
    })

    notify('success', 'MP ped loaded.')
end

function actionSavePed(data)
    local name = data and data.name
    if not name or name == '' then
        notify('error', 'Name required.')
        return
    end

    local ped = getPed()
    local model = GetEntityModel(ped)
    local payload = {
        model = model,
        ModelHash = model,
        IsMale = model == joaat('mp_m_freemode_01'),
        SaveName = name,
        Version = 1,
    }

    saveKvpJson(kvpKey('ped_', name), payload)
    notify('success', 'Ped saved.')
end

function actionLoadPed(data)
    local name = data and data.name
    if not name or name == '' then
        notify('error', 'Name required.')
        return
    end

    local payload = loadKvpJson(kvpKey('ped_', name))
    if not payload or not payload.ModelHash then
        notify('error', 'Saved ped not found.')
        return
    end

    if not authorizeModel('ped', payload.ModelHash, 'player.loadPed') then return end

    if not exports['cortex-lib']:requestModel(payload.ModelHash, 5000) then
        notify('error', 'Failed to load model.')
        return
    end

    SetPlayerModel(PlayerId(), payload.ModelHash)
    SetModelAsNoLongerNeeded(payload.ModelHash)
    notify('success', 'Ped loaded.')
end

local function configuredWeaponModels()
    local output = {}
    local seen = {}
    local function append(value)
        if type(value) ~= 'string' then return end
        local name = value:match('^%s*(.-)%s*$'):lower()
        if name == '' or not name:match('^[%w_%-]+$') then return end
        if name ~= 'gadget_parachute' and name:sub(1, 7) ~= 'weapon_' then name = 'weapon_' .. name end
        if not seen[name] then
            seen[name] = true
            output[#output + 1] = name
        end
    end

    for index = 1, #(Config.WeaponList or {}) do append(Config.WeaponList[index]) end
    local imported = type(Admin.getVmenuImportedConfig) == 'function' and Admin.getVmenuImportedConfig() or {}
    local addons = type(imported.addons) == 'table' and imported.addons or {}
    local weapons = type(addons.weapons) == 'table' and addons.weapons or {}
    for index = 1, math.min(#weapons, 512) do append(weapons[index]) end
    return output
end

function actionGiveAllWeapons()
    local ped = getPed()
    local weaponList = configuredWeaponModels()
    if #weaponList == 0 then
        notify('error', 'No weapon models are configured.')
        return
    end
    local authorized, reason = authorizeModelBatch('weapon', weaponList, 'weapons.giveAll')
    if not authorized then return end
    CreateThread(function()
        local granted = 0
        local denied = 0
        for i = 1, #weaponList do
            if authorized[i] == true then
                local weaponHash = joaat(weaponList[i])
                if not HasPedGotWeapon(ped, weaponHash, false) then
                    GiveWeaponToPed(ped, weaponHash, 250, false, false)
                    granted = granted + 1
                end
            else
                denied = denied + 1
            end

            if i % 8 == 0 then
                Wait(0)
            end
        end

        if granted > 0 then
            notify('success', ('Granted %d weapons%s.'):format(granted, denied > 0 and (', skipped ' .. denied .. ' restricted') or ''))
        elseif denied > 0 then
            notify('error', modelAuthorizationError(reason or 'model_forbidden'))
        else
            notify('success', 'All listed weapons already owned.')
        end
    end)
end

local WEAPON_UNARMED = joaat('weapon_unarmed')

function prettifyWeaponComponentLabel(hashStr)
    if type(hashStr) ~= 'string' then
        return ''
    end
    return (hashStr:gsub('^COMPONENT_', ''):gsub('_', ' '))
end

function weaponNameFromHash(weaponHash)
    local list = configuredWeaponModels()
    for i = 1, #list do
        if joaat(list[i]) == weaponHash then
            return list[i]
        end
    end
    return nil
end

function collectApplicableWeaponComponents(ped, weaponHash)
    local hashes = Config.WeaponComponentHashes or {}
    local rows = {}
    for i = 1, #hashes do
        local name = hashes[i]
        local ch = joaat(name)
        if DoesWeaponTakeWeaponComponent(weaponHash, ch) then
            rows[#rows + 1] = {
                hash = name,
                label = prettifyWeaponComponentLabel(name),
                on = HasPedGotWeaponComponent(ped, weaponHash, ch),
            }
        end
    end
    table.sort(rows, function(a, b)
        return (a.label or '') < (b.label or '')
    end)
    return rows
end

function collectEquippedWeaponComponentNames(ped, weaponHash)
    local hashes = Config.WeaponComponentHashes or {}
    local out = {}
    for i = 1, #hashes do
        local name = hashes[i]
        local ch = joaat(name)
        if DoesWeaponTakeWeaponComponent(weaponHash, ch) and HasPedGotWeaponComponent(ped, weaponHash, ch) then
            out[#out + 1] = name
        end
    end
    return out
end

Admin.getWeaponAttachmentList = function()
    local ped = getPed()
    local weapon = GetSelectedPedWeapon(ped)
    if not weapon or weapon == 0 or weapon == WEAPON_UNARMED then
        return {
            weaponName = '',
            components = {},
        }
    end
    return {
        weaponName = weaponNameFromHash(weapon) or ('0x%X'):format(weapon),
        components = collectApplicableWeaponComponents(ped, weapon),
    }
end

Admin.toggleWeaponAttachment = function(componentName)
    if type(componentName) ~= 'string' or componentName == '' then
        return false
    end
    local ped = getPed()
    local weapon = GetSelectedPedWeapon(ped)
    if not weapon or weapon == 0 or weapon == WEAPON_UNARMED then
        notify('error', 'Equip a weapon first.')
        return false
    end
    local ch = joaat(componentName)
    if not DoesWeaponTakeWeaponComponent(weapon, ch) then
        notify('error', 'That attachment does not apply to this weapon.')
        return false
    end
    if HasPedGotWeaponComponent(ped, weapon, ch) then
        RemoveWeaponComponentFromPed(ped, weapon, ch)
        notify('success', 'Attachment removed.')
    else
        GiveWeaponComponentToPed(ped, weapon, ch)
        notify('success', 'Attachment installed.')
    end
    return true
end

Admin.saveWeaponLoadout = function(name)
    if not name or name == '' then
        notify('error', 'Name required.')
        return false
    end

    local ped = getPed()
    local loadouts = loadWeaponLoadoutsRaw()
    local weapons = {}
    local weaponList = configuredWeaponModels()

    for i = 1, #weaponList do
        local weaponName = weaponList[i]
        local weaponHash = joaat(weaponName)
        if HasPedGotWeapon(ped, weaponHash, false) then
            weapons[#weapons + 1] = {
                name = weaponName,
                ammo = GetAmmoInPedWeapon(ped, weaponHash) or 0,
                components = collectEquippedWeaponComponentNames(ped, weaponHash),
            }
        end
    end

    loadouts[name] = {
        weapons = weapons,
        savedAt = currentUnixTime(),
    }
    saveKvpJson(C.WEAPON_LOADOUTS_KEY, loadouts)
    notify('success', ('Weapon loadout saved: %s'):format(name))
    return true
end

Admin.loadWeaponLoadout = function(name)
    if not name or name == '' then
        notify('error', 'Name required.')
        return false
    end

    local loadouts = loadWeaponLoadoutsRaw()
    local loadout = loadouts[name]
    if type(loadout) ~= 'table' or type(loadout.weapons) ~= 'table' then
        notify('error', ('Weapon loadout not found: %s'):format(name))
        return false
    end

    if #loadout.weapons > 256 then
        notify('error', 'Weapon loadout is too large to authorize safely.')
        return false
    end
    local models = {}
    for index = 1, #loadout.weapons do
        local weapon = loadout.weapons[index]
        if type(weapon) ~= 'table' or type(weapon.name) ~= 'string' then
            notify('error', 'Weapon loadout contains an invalid model.')
            return false
        end
        models[index] = weapon.name
    end
    if #models > 0 then
        local authorized, reason = authorizeModelBatch('weapon', models, 'weapons.loadLoadout')
        if not authorized then return false end
        for index = 1, #authorized do
            if authorized[index] ~= true then
                notify('error', modelAuthorizationError(reason or 'model_forbidden'))
                return false
            end
        end
    end

    local ped = getPed()
    RemoveAllPedWeapons(ped, true)
    for i = 1, #loadout.weapons do
        local weapon = loadout.weapons[i]
        if weapon and weapon.name then
            local wHash = joaat(weapon.name)
            GiveWeaponToPed(ped, wHash, tonumber(weapon.ammo) or 250, false, false)
            local comps = weapon.components
            if type(comps) == 'table' then
                for c = 1, #comps do
                    local cname = comps[c]
                    if type(cname) == 'string' or type(cname) == 'number' then
                        local cHash = type(cname) == 'number' and cname or joaat(cname)
                        if DoesWeaponTakeWeaponComponent(wHash, cHash) then
                            GiveWeaponComponentToPed(ped, wHash, cHash)
                        end
                    end
                end
            end
            local tint = tonumber(weapon.tint)
            if tint and tint >= 0 and tint <= 31 then SetPedWeaponTintIndex(ped, wHash, math.floor(tint)) end
        end
    end

    notify('success', ('Weapon loadout loaded: %s'):format(name))
    return true
end

Admin.deleteWeaponLoadout = function(name)
    if not name or name == '' then
        notify('error', 'Name required.')
        return false
    end

    local loadouts = loadWeaponLoadoutsRaw()
    if not loadouts[name] then
        notify('error', ('Weapon loadout not found: %s'):format(name))
        return false
    end

    loadouts[name] = nil
    saveKvpJson(C.WEAPON_LOADOUTS_KEY, loadouts)
    notify('success', ('Weapon loadout deleted: %s'):format(name))
    return true
end

function applyVehicleMods(vehicle)
    SetVehicleModKit(vehicle, 0)

    for modType = 0, 16 do
        local modCount = GetNumVehicleMods(vehicle, modType)
        if modCount and modCount > 0 then
            SetVehicleMod(vehicle, modType, modCount - 1, false)
        end
    end

    ToggleVehicleMod(vehicle, 18, true)
    ToggleVehicleMod(vehicle, 22, true)
    SetVehicleMod(vehicle, 16, GetNumVehicleMods(vehicle, 16) - 1, false)
    SetVehicleWindowTint(vehicle, 1)
    SetVehicleTyresCanBurst(vehicle, false)
end

local freecam = {
    enabled = false,
    cam = nil,
    ped = nil,
    controlledEntity = nil,
    entities = {},
    speed = 2.5,
    pitch = 0.0,
    yaw = 0.0,
}

local noclip = {
    enabled = false,
    speed = 2.5,
}

local function restoreFreecamEntities()
    for index = 1, #freecam.entities do
        local record = freecam.entities[index]
        local entity = record.entity
        if entity and entity ~= 0 and DoesEntityExist(entity) then
            if record.freezeChanged and IsEntityPositionFrozen(entity) then
                FreezeEntityPosition(entity, record.wasFrozen)
            end
            if record.visibilityChanged and not IsEntityVisible(entity) then
                SetEntityVisible(entity, record.wasVisible, false)
            end
        end
    end

    freecam.entities = {}
    freecam.ped = nil
    freecam.controlledEntity = nil
end

local function captureFreecamEntity(entity, shouldFreeze, shouldHide)
    local record = {
        entity = entity,
        wasFrozen = IsEntityPositionFrozen(entity),
        wasVisible = IsEntityVisible(entity),
        freezeChanged = false,
        visibilityChanged = false,
        shouldFreeze = shouldFreeze == true,
        shouldHide = shouldHide == true,
    }

    if record.shouldFreeze then
        record.freezeChanged = record.wasFrozen ~= true
        FreezeEntityPosition(entity, true)
    end
    if record.shouldHide then
        record.visibilityChanged = record.wasVisible ~= false
        SetEntityVisible(entity, false, false)
    end

    freecam.entities[#freecam.entities + 1] = record
end

local function captureFreecamState(ped)
    freecam.ped = ped
    freecam.controlledEntity = GetVehiclePedIsIn(ped, false)
    if not freecam.controlledEntity or freecam.controlledEntity == 0 then
        freecam.controlledEntity = ped
    end

    captureFreecamEntity(ped, true, true)
    if freecam.controlledEntity ~= ped then
        captureFreecamEntity(freecam.controlledEntity, true, false)
    end
end

local function reassertFreecamEntities()
    for index = 1, #freecam.entities do
        local record = freecam.entities[index]
        if record.entity and record.entity ~= 0 and DoesEntityExist(record.entity) then
            if record.shouldFreeze then
                FreezeEntityPosition(record.entity, true)
            end
            if record.shouldHide then
                SetEntityVisible(record.entity, false, false)
            end
        end
    end
end

function destroyFreecamCam()
    if freecam.cam and DoesCamExist(freecam.cam) then
        SetCamActive(freecam.cam, false)
        DestroyCam(freecam.cam, false)
    end
    RenderScriptCams(false, true, 250, true, false)
    freecam.cam = nil
end

function setFreecam(enabled, silent)
    if enabled and noclip.enabled then
        setToggle('dev.freecam', false)
        if not silent then
            notify('error', 'Disable noclip before freecam.')
        end
        return
    end

    if not enabled then
        if not freecam.enabled and not freecam.cam and #freecam.entities == 0 then
            return
        end
        freecam.enabled = false
        destroyFreecamCam()
        restoreFreecamEntities()
        ClearFocus()
        exports['cortex-lib']:hideHelp()
        if not silent then
            notify('info', 'Freecam off.')
        end
        return
    end

    if freecam.enabled then
        return
    end

    local ped = getPed()
    if not ped or ped == 0 or not DoesEntityExist(ped) or IsEntityDead(ped) then
        setToggle('dev.freecam', false)
        return
    end

    freecam.enabled = true
    captureFreecamState(ped)

    local c = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    freecam.pitch = rot.x
    freecam.yaw = rot.z
    local fov = GetGameplayCamFov()

    destroyFreecamCam()
    freecam.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', c.x, c.y, c.z, freecam.pitch, 0.0, freecam.yaw, fov, false, 2)
    if not freecam.cam or not DoesCamExist(freecam.cam) then
        setFreecam(false, true)
        return
    end
    SetCamActive(freecam.cam, true)
    RenderScriptCams(true, true, 400, true, false)

    exports['cortex-lib']:showHelp({
        { label = 'Move', value = 'W S A D' },
        { label = 'Up / Down', value = 'Space Q' },
        { label = 'Look', value = 'Mouse' },
        { label = 'Faster', value = 'Shift' },
        { label = 'Slower', value = 'Ctrl' },
        { label = 'Exit', value = 'Esc · Backspace' },
        { label = 'Off', value = 'Recording tab' },
    })

    CreateThread(function()
        while freecam.enabled do
            local cam = freecam.cam
            local currentPed = getPed()
            local currentEntity = currentPed
            if currentPed and currentPed ~= 0 and DoesEntityExist(currentPed) then
                local vehicle = GetVehiclePedIsIn(currentPed, false)
                if vehicle and vehicle ~= 0 then
                    currentEntity = vehicle
                end
            end
            if not cam or not DoesCamExist(cam) or not currentPed or currentPed == 0
                or not DoesEntityExist(currentPed) or currentPed ~= freecam.ped
                or currentEntity ~= freecam.controlledEntity or not DoesEntityExist(currentEntity)
                or IsEntityDead(currentPed) then
                setToggle('dev.freecam', false)
                setFreecam(false, true)
                break
            end

            reassertFreecamEntities()

            DisableControlAction(0, 30, true)
            DisableControlAction(0, 31, true)
            DisableControlAction(0, 32, true)
            DisableControlAction(0, 33, true)
            DisableControlAction(0, 34, true)
            DisableControlAction(0, 35, true)
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 36, true)
            DisableControlAction(0, 19, true)
            DisableControlAction(0, 22, true)
            DisableControlAction(0, 44, true)
            DisableControlAction(0, 200, true)
            DisableControlAction(0, 322, true)
            DisableControlAction(0, 177, true)

            if IsDisabledControlJustPressed(0, 322)
                or IsDisabledControlJustPressed(0, 200)
                or IsDisabledControlJustPressed(0, 177)
            then
                setToggle('dev.freecam', false)
                setFreecam(false, false)
                break
            end

            local mouseX = GetDisabledControlNormal(0, 1)
            local mouseY = GetDisabledControlNormal(0, 2)
            freecam.yaw = freecam.yaw - mouseX * 6.0
            freecam.pitch = freecam.pitch - mouseY * 6.0
            freecam.pitch = math.max(-89.0, math.min(89.0, freecam.pitch))
            SetCamRot(cam, freecam.pitch, 0.0, freecam.yaw, 2)

            local pitchRad = math.rad(freecam.pitch)
            local yawRad = math.rad(freecam.yaw)
            local cosPitch = math.cos(pitchRad)
            local fwdX = -math.sin(yawRad) * cosPitch
            local fwdY = math.cos(yawRad) * cosPitch
            local fwdZ = math.sin(pitchRad)
            local rightX = math.cos(yawRad)
            local rightY = math.sin(yawRad)

            local speed = freecam.speed
            if IsDisabledControlPressed(0, 21) then
                speed = speed * 4.0
            end
            if IsDisabledControlPressed(0, 36) or IsDisabledControlPressed(0, 19) then
                speed = speed * 0.15
            end

            local pos = GetCamCoord(cam)
            local step = speed * GetFrameTime() * 3.0

            if IsDisabledControlPressed(0, 32) then
                pos = vector3(pos.x + fwdX * step, pos.y + fwdY * step, pos.z + fwdZ * step)
            end
            if IsDisabledControlPressed(0, 33) then
                pos = vector3(pos.x - fwdX * step, pos.y - fwdY * step, pos.z - fwdZ * step)
            end
            if IsDisabledControlPressed(0, 34) then
                pos = vector3(pos.x - rightX * step, pos.y - rightY * step, pos.z)
            end
            if IsDisabledControlPressed(0, 35) then
                pos = vector3(pos.x + rightX * step, pos.y + rightY * step, pos.z)
            end
            if IsDisabledControlPressed(0, 22) then
                pos = vector3(pos.x, pos.y, pos.z + step)
            end
            if IsDisabledControlPressed(0, 44) then
                pos = vector3(pos.x, pos.y, pos.z - step)
            end

            SetCamCoord(cam, pos.x, pos.y, pos.z)
            SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0)
            Wait(0)
        end
    end)

    if not silent then
        notify('success', 'Freecam on.')
    end
end

function playNoclipFx(entity, enabled)
    local soundName = enabled and "Power_On" or "Power_Down"
    PlaySoundFrontend(-1, soundName, "DLC_HEIST_BIOLAB_PREP_TRACKING_SOUNDS", 1)
    
    if not HasNamedPtfxAssetLoaded("core") then
        RequestNamedPtfxAsset("core")
        local timeout = GetGameTimer() + 1000
        while not HasNamedPtfxAssetLoaded("core") and GetGameTimer() < timeout do
            Wait(10)
        end
    end
    
    if HasNamedPtfxAssetLoaded("core") then
        UseParticleFxAssetNextCall("core")
        StartParticleFxNonLoopedOnEntity("ent_dst_elec_fire_sp", entity, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 4.0, false, false, false)
    end
end

function setNoclip(enabled)
    if enabled and freecam.enabled then
        setToggle('player.noclip', false)
        notify('error', 'Disable freecam before noclip.')
        return
    end
    noclip.enabled = enabled
    local ped = getPed()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local entity = (vehicle ~= 0) and vehicle or ped

    playNoclipFx(entity, enabled)

    SetEntityCollision(entity, not enabled, not enabled)
    SetEntityInvincible(entity, enabled)
    SetEntityVisible(entity, not enabled, false)
    if vehicle ~= 0 then
        SetEntityCollision(ped, not enabled, not enabled)
        SetEntityInvincible(ped, enabled)
        SetEntityVisible(ped, not enabled, false)
        FreezeEntityPosition(vehicle, enabled)
    end

    if enabled then
        notify('info', 'Noclip enabled')

        exports['cortex-lib']:showHelp({
            { label = 'Fwd/Back', value = 'W S' },
            { label = 'Left/Right', value = 'A D' },
            { label = 'Up', value = 'Space' },
            { label = 'Down', value = 'Q' },
            { label = 'Faster', value = 'Shift' },
            { label = 'Slower', value = 'Ctrl' }
        })

        CreateThread(function()
            local currentSpeed = noclip.speed

            while noclip.enabled do
                local pedHandle = getPed()
                local veh = GetVehiclePedIsIn(pedHandle, false)
                local moveEntity = (veh ~= 0) and veh or pedHandle
                local coords = GetEntityCoords(moveEntity)
                local camRot = GetGameplayCamRot(2)

                local rotZ = math.rad(camRot.z)
                local rotX = math.rad(camRot.x)
                local cosX = math.abs(math.cos(rotX))

                local fwdX = -math.sin(rotZ) * cosX
                local fwdY = math.cos(rotZ) * cosX
                local fwdZ = math.sin(rotX)

                local rightX = math.cos(rotZ)
                local rightY = math.sin(rotZ)

                local targetSpeed = noclip.speed
                if IsControlPressed(0, 21) then
                    targetSpeed = noclip.speed * 5.0
                elseif IsControlPressed(0, 36) or IsControlPressed(0, 19) then
                    targetSpeed = noclip.speed * 0.1
                end

                currentSpeed = currentSpeed + (targetSpeed - currentSpeed) * 0.1

                local moveX, moveY, moveZ = 0.0, 0.0, 0.0

                if IsControlPressed(0, 32) then
                    moveX = moveX + fwdX
                    moveY = moveY + fwdY
                    moveZ = moveZ + fwdZ
                elseif IsControlPressed(0, 33) then
                    moveX = moveX - fwdX
                    moveY = moveY - fwdY
                    moveZ = moveZ - fwdZ
                end

                if IsControlPressed(0, 34) then
                    moveX = moveX - rightX
                    moveY = moveY - rightY
                elseif IsControlPressed(0, 35) then
                    moveX = moveX + rightX
                    moveY = moveY + rightY
                end

                if IsControlPressed(0, 22) then
                    moveZ = moveZ + 1.0
                elseif IsControlPressed(0, 44) then
                    moveZ = moveZ - 1.0
                end

                if moveX ~= 0.0 or moveY ~= 0.0 or moveZ ~= 0.0 then
                    local len = math.sqrt((moveX * moveX) + (moveY * moveY) + (moveZ * moveZ))
                    if len > 0 then
                        local invLen = 1.0 / len
                        moveX = moveX * invLen
                        moveY = moveY * invLen
                        moveZ = moveZ * invLen
                    end

                    SetEntityCoordsNoOffset(
                        moveEntity,
                        coords.x + (moveX * currentSpeed),
                        coords.y + (moveY * currentSpeed),
                        coords.z + (moveZ * currentSpeed),
                        true,
                        true,
                        true
                    )
                end

                SetEntityHeading(moveEntity, camRot.z)
                SetEntityVelocity(moveEntity, 0.0, 0.0, 0.0)

                Wait(0)
            end
        end)
    else
        exports['cortex-lib']:hideHelp()

        if vehicle ~= 0 then
            FreezeEntityPosition(vehicle, false)
            SetEntityCollision(vehicle, true, true)
            SetEntityInvincible(vehicle, false)
            SetEntityVisible(vehicle, true, false)
            SetEntityCollision(ped, true, true)
            SetEntityInvincible(ped, false)
            SetEntityVisible(ped, true, false)
            SetEntityVelocity(vehicle, 0.0, 0.0, 0.0)
        else
            FreezeEntityPosition(ped, false)
            SetEntityVelocity(ped, 0.0, 0.0, 0.0)
        end
    end
end

function requestEntityControl(entity, timeoutMs)
    if entity == 0 or not DoesEntityExist(entity) then
        return false
    end

    if not NetworkGetEntityIsNetworked(entity) then
        return true
    end

    if NetworkHasControlOfEntity(entity) then
        return true
    end

    NetworkRequestControlOfEntity(entity)
    if NetworkHasControlOfEntity(entity) then
        return true
    end

    local timeout = tonumber(timeoutMs) or 0
    if timeout > 0 then
        local deadline = GetGameTimer() + timeout
        while GetGameTimer() < deadline do
            if NetworkHasControlOfEntity(entity) then
                return true
            end
            Wait(0)
        end
    end

    return NetworkHasControlOfEntity(entity)
end

function tryDeleteEntity(entity)
    if entity == 0 or not DoesEntityExist(entity) then
        return false
    end

    if IsEntityAPed(entity) and IsPedAPlayer(entity) then
        return false
    end

    requestEntityControl(entity, 0)
    SetEntityAsMissionEntity(entity, true, true)
    DeleteEntity(entity)

    if DoesEntityExist(entity) then
        requestEntityControl(entity, 0)
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
    end

    return not DoesEntityExist(entity)
end

function vehicleHasPlayerOccupant(vehicle)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false
    end

    local maxPassengers = GetVehicleMaxNumberOfPassengers(vehicle)
    for seat = -1, maxPassengers - 1 do
        local occupant = GetPedInVehicleSeat(vehicle, seat)
        if occupant ~= 0 and IsPedAPlayer(occupant) then
            return true
        end
    end

    return false
end

function clearPoolEntities(poolName, radius, excludeEntity)
    local ped = getPed()
    local coords = GetEntityCoords(ped)
    local cx, cy, cz = coords.x, coords.y, coords.z
    local radiusSq = radius * radius
    local pool = GetGamePool(poolName)
    local removed = 0
    local exclude = excludeEntity or ped

    for i = 1, #pool do
        local entity = pool[i]
        if entity ~= exclude and DoesEntityExist(entity) then
            local shouldSkip = false
            if poolName == 'CPed' and IsPedAPlayer(entity) then
                shouldSkip = true
            elseif poolName == 'CVehicle' and vehicleHasPlayerOccupant(entity) then
                shouldSkip = true
            end

            if not shouldSkip then
                local eCoords = GetEntityCoords(entity)
                local dx = eCoords.x - cx
                local dy = eCoords.y - cy
                local dz = eCoords.z - cz
                local distSq = (dx * dx) + (dy * dy) + (dz * dz)

                if distSq <= radiusSq and tryDeleteEntity(entity) then
                    removed = removed + 1
                end
            end
        end
    end

    return removed
end

function setAmbientSuppressionState(enabled)
    local allowAmbient = not enabled
    SetRandomBoats(allowAmbient)
    SetGarbageTrucks(allowAmbient)
    SetCreateRandomCops(allowAmbient)
    SetCreateRandomCopsOnScenarios(allowAmbient)
    SetCreateRandomCopsNotOnScenarios(allowAmbient)

    if SetPedPopulationBudget then
        SetPedPopulationBudget(enabled and 0 or 3)
    end

    if SetVehiclePopulationBudget then
        SetVehiclePopulationBudget(enabled and 0 or 3)
    end
end

function applyAmbientSuppressionFrame()
    SetPedDensityMultiplierThisFrame(0.0)
    SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
    SetRandomVehicleDensityMultiplierThisFrame(0.0)
    SetParkedVehicleDensityMultiplierThisFrame(0.0)
    SetVehicleDensityMultiplierThisFrame(0.0)

    if SuppressShockingEventsNextFrame then
        SuppressShockingEventsNextFrame()
    end
end

function actionPlayerHeal()
    local ped = getPed()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    notify('success', 'Health restored.')
end

function actionPlayerArmor()
    SetPedArmour(getPed(), 100)
    notify('success', 'Armor restored.')
end

function actionPlayerRevive()
    local ped = getPed()
    local coords = GetEntityCoords(ped)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, true)
    ClearPedTasksImmediately(ped)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    notify('success', 'Player revived.')
end

function actionClearWanted()
    ClearPlayerWantedLevel(PlayerId())
    notify('success', 'Wanted level cleared.')
end

function actionSetFaceFeature(data)
    if type(data) ~= 'table' or data.id == nil then return end
    local featureId = tonumber(data.id)
    if featureId == nil then return end
    local v = tonumber(data.value) or 0.0
    if v < -1.0 then v = -1.0 elseif v > 1.0 then v = 1.0 end
    local ped = getPed()
    if not isFreemodePed(ped) then return end
    SetPedFaceFeature(ped, featureId, v)
end

local lastAppearanceRandomization = nil
local lastGeneratedOutfitId = nil

local NATURAL_EYE_COLORS = { 0, 1, 2, 3, 4, 5, 6, 7 }
local GENERATED_PROP_IDS = { 0, 1, 2, 6, 7 }
local GENERATED_CLEAR_COMPONENT_IDS = { 1, 5, 7, 9, 10 }

local function randomChoice(values)
    if type(values) ~= 'table' or #values == 0 then return nil end
    return values[math.random(1, #values)]
end

local function randomUnit(minimum, maximum)
    return minimum + ((maximum - minimum) * (math.random(0, 1000) / 1000))
end

local function randomReviewedFaceFeature(gender, profileName, featureId)
    local minimum, maximum = -0.12, 0.12
    if AppearanceRandomizer and AppearanceRandomizer.getFaceFeatureRange then
        minimum, maximum = AppearanceRandomizer.getFaceFeatureRange(gender, profileName, featureId)
    end
    -- Two rolls keep the result near the center while respecting the reviewed
    -- per-feature band for jaw, chin, eyes, lips and neck.
    return (randomUnit(minimum, maximum) + randomUnit(minimum, maximum)) / 2
end

local function collectNaturalHairColors(tone)
    local colors = {}
    local count = type(GetNumHairColors) == 'function' and tonumber(GetNumHairColors()) or 0
    count = math.min(256, math.max(0, math.floor(count or 0)))

    if type(GetPedHairRgbColor) == 'function' then
        for index = 0, count - 1 do
            local ok, red, green, blue = pcall(GetPedHairRgbColor, index)
            if ok then
                colors[#colors + 1] = {
                    index = index,
                    r = tonumber(red),
                    g = tonumber(green),
                    b = tonumber(blue),
                }
            end
        end
    end

    if AppearanceRandomizer and AppearanceRandomizer.filterNaturalHairColors then
        return AppearanceRandomizer.filterNaturalHairColors(colors, tone)
    end
    return { { index = 0, r = 0, g = 0, b = 0 } }
end

local function generatedComponentIsValid(ped, component)
    if type(component) ~= 'table' then return false end
    local drawable = component.globalDrawable or component.drawable
    if type(drawable) ~= 'number' then return false end
    if component.globalDrawable == nil and component.collection ~= '' then return false end
    -- Official DLC entries are stored by their catalog global index, then
    -- resolved to their collection-local index immediately before applying.
    -- Runtime global counts let older game builds discard unavailable pieces.
    local drawableCount = tonumber(GetNumberOfPedDrawableVariations(ped, component.component)) or 0
    if drawable < 0 or drawable >= drawableCount then return false end
    local textureCount = tonumber(GetNumberOfPedTextureVariations(ped, component.component, drawable)) or 0
    if textureCount <= 0 then return component.texture == 0 end
    return component.texture >= 0 and component.texture < textureCount
end

local function generatedAccessoryIsValid(ped, accessory)
    if type(accessory) ~= 'table' or accessory.collection ~= '' then return false end
    local drawableCount = tonumber(GetNumberOfPedPropDrawableVariations(ped, accessory.prop)) or 0
    if accessory.drawable < 0 or accessory.drawable >= drawableCount then return false end
    local textureCount = tonumber(GetNumberOfPedPropTextureVariations(ped, accessory.prop, accessory.drawable)) or 0
    if textureCount <= 0 then return accessory.texture == 0 end
    return accessory.texture >= 0 and accessory.texture < textureCount
end

local function generatedClothingPieceIsValid(ped, piece)
    if type(piece) ~= 'table' or type(piece.components) ~= 'table' or #piece.components == 0 then return false end
    for _, component in ipairs(piece.components) do
        if not generatedComponentIsValid(ped, component) then return false end
    end
    return true
end

local function selectGeneratedOutfit(ped, options)
    local gender = GetEntityModel(ped) == joaat('mp_f_freemode_01') and 'female' or 'male'
    local pools = AppearanceRandomizer and AppearanceRandomizer.getPiecePools
        and AppearanceRandomizer.getPiecePools(gender, options.style, options.palette) or nil
    if not pools or not AppearanceRandomizer.filterPiecePools or not AppearanceRandomizer.assembleOutfit then return nil end

    pools = AppearanceRandomizer.filterPiecePools(
        pools,
        function(piece) return generatedClothingPieceIsValid(ped, piece) end,
        function(accessory) return generatedAccessoryIsValid(ped, accessory) end
    )

    if #pools.tops == 0 or #pools.bottoms == 0 or #pools.shoes == 0 then
        print(('[cortex-admin] No compatible generated pieces model=%s gender=%s style=%s tops=%d bottoms=%d shoes=%d'):format(
            tostring(GetEntityModel(ped)), gender, options.style, #pools.tops, #pools.bottoms, #pools.shoes
        ))
        return nil
    end

    local fallback = nil
    for _ = 1, 12 do
        local outfit = AppearanceRandomizer.assembleOutfit(pools, options.accessories, function(count)
            return math.random(1, count)
        end)
        if outfit then
            fallback = outfit
            if outfit.id ~= lastGeneratedOutfitId then return outfit end
        end
    end
    return fallback
end

local function applyGeneratedCollectionComponent(ped, component)
    if component.globalDrawable ~= nil then
        local getCollectionName = type(GetPedCollectionNameFromDrawable) == 'function'
            and GetPedCollectionNameFromDrawable or GetPedDrawableCollectionName
        local getLocalIndex = type(GetPedCollectionLocalIndexFromDrawable) == 'function'
            and GetPedCollectionLocalIndexFromDrawable or GetPedDrawableCollectionLocalIndex
        if type(getCollectionName) == 'function' and type(getLocalIndex) == 'function'
            and type(SetPedCollectionComponentVariation) == 'function' then
            local nameOk, collection = pcall(getCollectionName, ped, component.component, component.globalDrawable)
            local indexOk, localIndex = pcall(getLocalIndex, ped, component.component, component.globalDrawable)
            if nameOk and indexOk and type(collection) == 'string' and type(localIndex) == 'number' and localIndex >= 0 then
                SetPedCollectionComponentVariation(
                    ped, component.component, collection,
                    localIndex, component.texture, 0
                )
                return
            end
        end
        setPedComponent(ped, component.component, component.globalDrawable, component.texture)
        return
    end
    if type(SetPedCollectionComponentVariation) == 'function' then
        SetPedCollectionComponentVariation(
            ped, component.component, component.collection,
            component.drawable, component.texture, 0
        )
        return
    end
    setPedComponent(ped, component.component, component.drawable, component.texture)
end

local function applyGeneratedCollectionProp(ped, accessory)
    if type(SetPedCollectionPropIndex) == 'function' then
        SetPedCollectionPropIndex(
            ped, accessory.prop, accessory.collection,
            accessory.drawable, accessory.texture, true
        )
        return
    end
    setPedProp(ped, accessory.prop, accessory.drawable, accessory.texture)
end

local function applyGeneratedOutfit(ped, preset, includeAccessories)
    for _, componentId in ipairs(GENERATED_CLEAR_COMPONENT_IDS) do
        setPedComponent(ped, componentId, 0, 0)
    end
    for _, propId in ipairs(GENERATED_PROP_IDS) do ClearPedProp(ped, propId) end
    for _, component in ipairs(preset.components) do
        applyGeneratedCollectionComponent(ped, component)
    end
    if includeAccessories then
        for _, accessory in ipairs(preset.accessories) do
            applyGeneratedCollectionProp(ped, accessory)
        end
    end
    lastGeneratedOutfitId = preset.id
end

local function setGeneratedOverlay(ped, overlayId, chance, minimumOpacity, maximumOpacity, colorType, firstColor, secondColor)
    local maxStyles = type(GetNumHeadOverlayValues) == 'function'
        and tonumber(GetNumHeadOverlayValues(overlayId)) or 0
    if maxStyles <= 0 or math.random(1, 100) > chance then
        SetPedHeadOverlay(ped, overlayId, 0, 0.0)
        return
    end

    local style = math.random(0, math.max(0, maxStyles - 1))
    SetPedHeadOverlay(ped, overlayId, style, randomUnit(minimumOpacity, maximumOpacity))
    if colorType then
        SetPedHeadOverlayColor(ped, overlayId, colorType, firstColor or 0, secondColor or firstColor or 0)
    end
end

local function applyGeneratedCharacter(ped, options)
    local isMale = GetEntityModel(ped) == joaat('mp_m_freemode_01')
    local gender = isMale and 'male' or 'female'
    local identity = AppearanceRandomizer.assembleIdentity(gender, options, function(count)
        return math.random(1, count)
    end)
    SetPedHeadBlendData(
        ped,
        identity.shapeFirst,
        identity.shapeSecond,
        0,
        identity.skinFirst,
        identity.skinSecond,
        0,
        randomUnit(identity.shapeMixMin, identity.shapeMixMax),
        randomUnit(identity.skinMixMin, identity.skinMixMax),
        0.0,
        false
    )

    for featureId = 0, 19 do
        SetPedFaceFeature(ped, featureId, randomReviewedFaceFeature(gender, identity.profile, featureId))
    end

    local hairComponent = {
        component = 2,
        collection = identity.hair.collection,
        drawable = identity.hair.drawable,
        texture = identity.hair.texture,
    }
    if generatedComponentIsValid(ped, hairComponent) then
        applyGeneratedCollectionComponent(ped, hairComponent)
    else
        setPedComponent(ped, 2, 0, 0)
    end

    local naturalColors = collectNaturalHairColors(options.hairTone)
    local primary = randomChoice(naturalColors) or { index = 0 }
    local highlight = math.random(1, 100) <= 68 and primary or (randomChoice(naturalColors) or primary)
    SetPedHairColor(ped, primary.index, highlight.index)
    SetPedEyeColor(ped, randomChoice(NATURAL_EYE_COLORS) or 0)

    local overlayPlan = AppearanceRandomizer.getOverlayPlan(gender, options)
    for overlayId = 0, 11 do
        local rule = overlayPlan[overlayId]
        local colorType, firstColor, secondColor = nil, nil, nil
        if rule.color == 'hair' then
            colorType, firstColor, secondColor = 1, primary.index, highlight.index
        elseif rule.color == 'cosmetic' then
            colorType, firstColor, secondColor = 2, 0, 0
        end
        setGeneratedOverlay(
            ped,
            overlayId,
            rule.chance,
            rule.minimumOpacity,
            rule.maximumOpacity,
            colorType,
            firstColor,
            secondColor
        )
    end
end

local function resolveGeneratedModel(options, currentModel)
    if options.mode ~= 'character' or options.gender == 'keep' then return currentModel end
    if options.gender == 'random' then
        return math.random(0, 1) == 0 and joaat('mp_m_freemode_01') or joaat('mp_f_freemode_01')
    end
    return options.gender == 'female' and joaat('mp_f_freemode_01') or joaat('mp_m_freemode_01')
end

Admin.randomizeAppearance = function(rawOptions)
    local options = AppearanceRandomizer and AppearanceRandomizer.sanitizeOptions
        and AppearanceRandomizer.sanitizeOptions(rawOptions) or { mode = 'outfit', style = 'polished', gender = 'keep', hairTone = 'any', palette = 'neutral', accessories = false }
    local ped = getPed()
    if ped == 0 or not DoesEntityExist(ped) then
        notify('error', 'Player ped is unavailable.')
        return { ok = false, error = 'ped_unavailable', canUndo = lastAppearanceRandomization ~= nil }
    end

    local currentModel = GetEntityModel(ped)
    local targetModel = resolveGeneratedModel(options, currentModel)
    if options.mode == 'outfit' and not isFreemodePed(ped) then
        notify('error', 'Outfit generation requires an MP freemode ped.')
        return { ok = false, error = 'freemode_required', canUndo = lastAppearanceRandomization ~= nil }
    end
    if options.mode == 'character' and options.gender == 'keep' and not isFreemodePed(ped) then
        targetModel = math.random(0, 1) == 0 and joaat('mp_m_freemode_01') or joaat('mp_f_freemode_01')
    end

    local undoSnapshot = isFreemodePed(ped) and captureMpPedData(ped, 'Before generated appearance') or nil

    if targetModel ~= currentModel then
        local modelName = targetModel == joaat('mp_f_freemode_01') and 'mp_f_freemode_01' or 'mp_m_freemode_01'
        if not authorizeModel('ped', modelName, 'player.randomizeAppearance') then
            return { ok = false, error = 'model_forbidden', canUndo = lastAppearanceRandomization ~= nil }
        end
        if not exports['cortex-lib']:requestModel(targetModel, 5000) then
            notify('error', 'Failed to load the selected freemode model.')
            return { ok = false, error = 'model_load_failed', canUndo = lastAppearanceRandomization ~= nil }
        end

        SetPlayerModel(PlayerId(), targetModel)
        SetModelAsNoLongerNeeded(targetModel)
        Wait(100)
        ped = getPed()
        SetPedDefaultComponentVariation(ped)
    end

    local outfit = selectGeneratedOutfit(ped, options)
    if not outfit then
        notify('error', 'No compatible clothing pieces were available for this freemode model.')
        return { ok = false, error = 'no_compatible_outfit', canUndo = lastAppearanceRandomization ~= nil }
    end

    lastAppearanceRandomization = undoSnapshot
    applyGeneratedOutfit(ped, outfit, options.accessories)
    if options.mode == 'character' then applyGeneratedCharacter(ped, options) end

    local label = options.mode == 'character' and 'character' or 'outfit'
    notify('success', ('Applied %s (%s %s).'):format(outfit.name, options.style, label))
    return {
        ok = true,
        mode = options.mode,
        style = options.style,
        outfitId = outfit.id,
        outfitName = outfit.name,
        canUndo = lastAppearanceRandomization ~= nil,
        modelChanged = targetModel ~= currentModel,
    }
end

Admin.undoRandomizedAppearance = function()
    if not lastAppearanceRandomization then
        notify('error', 'There is no generated appearance to undo.')
        return { ok = false, error = 'nothing_to_undo', canUndo = false }
    end

    local snapshot = lastAppearanceRandomization
    lastAppearanceRandomization = nil
    local restored = applyMpPedData(getPed(), snapshot, { preserveDecorations = true })
    if not restored then
        lastAppearanceRandomization = snapshot
        notify('error', 'Could not restore the previous appearance.')
        return { ok = false, error = 'restore_failed', canUndo = true }
    end

    notify('success', 'Restored the appearance from before the last roll.')
    return { ok = true, canUndo = false }
end

function actionRandomizeMpPedFace()
    local ped = getPed()
    local pedModel = GetEntityModel(ped)
    local isFreemode = pedModel == joaat('mp_m_freemode_01') or pedModel == joaat('mp_f_freemode_01')
    if not isFreemode then
        notify('error', 'Switch to an MP freemode ped first.')
        return
    end

    applyGeneratedCharacter(ped, { hairTone = 'any' })
    notify('success', 'Randomized MP face, hair and overlays.')
end

function actionClearPedTattoos()
    ClearPedDecorations(getPed())
    notify('success', 'Cleared ped tattoos and decorations.')
end

function actionSetModel(data)
    local model = data and data.model
    if not model or model == '' then
        notify('error', 'Model name required.')
        return
    end

    if not authorizeModel('ped', model, 'player.setModel') then return end

    if not exports['cortex-lib']:requestModel(model, 5000) then
        notify('error', 'Failed to load model.')
        return
    end

    local modelHash = joaat(model)
    SetPlayerModel(PlayerId(), modelHash)
    SetModelAsNoLongerNeeded(modelHash)
    
    local isFreemode = modelHash == joaat('mp_m_freemode_01') or modelHash == joaat('mp_f_freemode_01')
    if isFreemode then
        local ped = getPed()
        SetPedHeadBlendData(ped, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.0, false)
        
        SetPedComponentVariation(ped, 0, 0, 0, 2)
        SetPedComponentVariation(ped, 2, 0, 0, 2)
        SetPedComponentVariation(ped, 3, 0, 0, 2)
        SetPedComponentVariation(ped, 4, 0, 0, 2)
        SetPedComponentVariation(ped, 6, 0, 0, 2)
        SetPedComponentVariation(ped, 8, 0, 0, 2)
        SetPedComponentVariation(ped, 11, 0, 0, 2)
    end
    
    notify('success', 'Model updated.')
end

function actionCopyCoords(data)
    local text, format = buildCoordClipboardText(data and data.format)
    copyToClipboard(text)
    notify('success', ('%s copied.'):format(format))
end

function actionCopyHeading()
    local heading = GetEntityHeading(getPed())
    copyToClipboard(('%0.2f'):format(heading))
    notify('success', 'Heading copied.')
end

local previewVehicle = 0
local previewModel = nil
local previewWatcherActive = false
local previewShared = false
local clearVehiclePreview

function collectPreviewExtraStates()
    local list = {}
    if previewVehicle == 0 or not DoesEntityExist(previewVehicle) then
        return list
    end

    for i = 1, 20 do
        if DoesExtraExist(previewVehicle, i) then
            list[#list + 1] = {
                id = i,
                on = IsVehicleExtraTurnedOn(previewVehicle, i) and true or false,
            }
        end
    end

    return list
end

function applyVehicleExtraStates(vehicle, states)
    if vehicle == 0 or type(states) ~= 'table' then
        return
    end

    for idx = 1, #states do
        local entry = states[idx]
        local id = entry and tonumber(entry.id)
        if id and DoesExtraExist(vehicle, id) then
            local wantOn = entry.on == true
            SetVehicleExtra(vehicle, id, not wantOn)
        end
    end
end

function syncPreviewExtrasStatebag()
    if previewShared ~= true then
        return
    end
    if previewVehicle == 0 or not DoesEntityExist(previewVehicle) then
        return
    end
    if not NetworkGetEntityIsNetworked(previewVehicle) then
        return
    end
    local ent = Entity(previewVehicle)
    if ent and ent.state then
        ent.state:set('cortex-admin_pv_ex', collectPreviewExtraStates(), true)
    end
end

function destroyPreviewEntityOnly()
    if previewVehicle ~= 0 and DoesEntityExist(previewVehicle) then
        SetEntityAsMissionEntity(previewVehicle, true, true)
        DeleteEntity(previewVehicle)
    end
    previewVehicle = 0
end

function computePedPreviewSpawn()
    local ped = getPed()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local headingRad = math.rad(heading)
    local spawnDistance = 6.0
    local spawnX = coords.x + (-math.sin(headingRad) * spawnDistance)
    local spawnY = coords.y + (math.cos(headingRad) * spawnDistance)
    local spawnZ = coords.z + 0.25
    local spawnHeading = (heading + 180.0) % 360.0
    RequestCollisionAtCoord(spawnX, spawnY, spawnZ)
    local foundGround, groundZ = GetGroundZFor_3dCoord(spawnX, spawnY, spawnZ + 2.0, false)
    if foundGround then
        spawnZ = groundZ + 0.15
    end
    return spawnX, spawnY, spawnZ, spawnHeading
end

function configurePreviewVehicleEntity(vehicle, networkShared)
    SetEntityAsMissionEntity(vehicle, true, true)
    FreezeEntityPosition(vehicle, true)
    SetEntityInvincible(vehicle, true)
    SetEntityCollision(vehicle, false, false)
    SetEntityAlpha(vehicle, 220, false)
    SetVehicleEngineOn(vehicle, false, true, true)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehicleOnGroundProperly(vehicle)
    if NetworkGetEntityIsNetworked(vehicle) then
        local netId = NetworkGetNetworkIdFromEntity(vehicle)
        if netId and netId ~= 0 then
            if networkShared == true then
                SetNetworkIdExistsOnAllMachines(netId, true)
            else
                SetNetworkIdExistsOnAllMachines(netId, false)
            end
            SetNetworkIdCanMigrate(netId, false)
        end
    end
end

function spawnPreviewVehicleEntity(model, networkShared, transform)
    if not model or model == '' then
        return false
    end
    if not exports['cortex-lib']:requestModel(model, 5000) then
        notify('error', 'Unable to load vehicle model.')
        return false
    end
    local modelHash = joaat(model)
    local spawnX, spawnY, spawnZ, spawnHeading
    if transform and transform.x and transform.y and transform.z then
        spawnX = transform.x
        spawnY = transform.y
        spawnZ = transform.z
        spawnHeading = transform.heading or 0.0
    else
        spawnX, spawnY, spawnZ, spawnHeading = computePedPreviewSpawn()
    end
    local useNet = networkShared == true
    local vehicle = CreateVehicle(modelHash, spawnX, spawnY, spawnZ, spawnHeading, useNet, useNet)
    if vehicle == 0 then
        SetModelAsNoLongerNeeded(modelHash)
        notify('error', 'Failed to create preview vehicle.')
        return false
    end
    configurePreviewVehicleEntity(vehicle, networkShared)
    previewVehicle = vehicle
    SetModelAsNoLongerNeeded(modelHash)
    return true
end

function spawnVehicleAtPedWithExtras(model, extraStates, authorizationActionId)
    if not model or model == '' then
        notify('error', 'Vehicle model required.')
        return false
    end

    local modelActionId = authorizationActionId or 'vehicle.spawn'
    local modelAuthorized, _, modelToken = authorizeModel('vehicle', model, modelActionId)
    if not modelAuthorized then return false end

    if not exports['cortex-lib']:requestModel(model, 5000) then
        notify('error', 'Unable to load vehicle model.')
        return false
    end

    local ped = getPed()

    deleteOccupiedVehicleIfReplaceSpawnEnabled()

    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local vehicle = CreateVehicle(joaat(model), coords.x, coords.y, coords.z, heading, true, false)

    if vehicle == 0 then
        SetModelAsNoLongerNeeded(joaat(model))
        notify('error', 'Failed to spawn vehicle.')
        return false
    end

    if type(extraStates) == 'table' and #extraStates > 0 then
        applyVehicleExtraStates(vehicle, extraStates)
    end

    registerCortexSpawnedVehicle(vehicle)
    seatPedInSpawnedVehicle(ped, vehicle)
    Wait(0)
    Admin.giveKeysForVehicle(vehicle, true, modelToken, modelActionId)
    SetModelAsNoLongerNeeded(joaat(model))
    notify('success', 'Vehicle spawned.')
    return true
end

function startPreviewWatcher()
    if previewWatcherActive then
        return
    end

    previewWatcherActive = true
    CreateThread(function()
        local closeControl = tonumber(Config.VehiclePreviewCloseControl) or 194
        while previewVehicle ~= 0 do
            if IsControlJustPressed(0, closeControl) then
                clearVehiclePreview()
                notify('info', 'Vehicle preview closed.')
                break
            end

            Wait(0)
        end

        previewWatcherActive = false
    end)
end

clearVehiclePreview = function()
    destroyPreviewEntityOnly()
    previewModel = nil
    previewShared = false
end

function startVehiclePreview(model)
    if not model or model == '' then
        notify('error', 'Vehicle model required.')
        return false
    end

    if not authorizeModel('vehicle', model, 'vehicle.spawn') then return false end
    clearVehiclePreview()
    if not spawnPreviewVehicleEntity(model, false, nil) then
        return false
    end
    previewModel = model
    startPreviewWatcher()
    return true
end

Admin.clearVehiclePreview = clearVehiclePreview
Admin.previewVehicle = startVehiclePreview
Admin.getPreviewVehicleModel = function()
    return previewModel
end

Admin.getPreviewShared = function()
    return previewShared == true
end

Admin.setPreviewShared = function(shared)
    shared = shared == true
    if not previewModel or previewModel == '' then
        previewShared = false
        return not shared
    end
    if shared == previewShared and previewVehicle ~= 0 and DoesEntityExist(previewVehicle) then
        if previewShared then
            syncPreviewExtrasStatebag()
        end
        Admin.sendUiState()
        return true
    end
    local transform
    local states = {}
    if previewVehicle ~= 0 and DoesEntityExist(previewVehicle) then
        local c = GetEntityCoords(previewVehicle)
        transform = {
            x = c.x,
            y = c.y,
            z = c.z,
            heading = GetEntityHeading(previewVehicle),
        }
        states = collectPreviewExtraStates()
    end
    destroyPreviewEntityOnly()
    previewShared = shared
    if not spawnPreviewVehicleEntity(previewModel, previewShared, transform) then
        previewShared = false
        notify('error', 'Failed to update preview vehicle.')
        Admin.sendUiState()
        return false
    end
    if #states > 0 then
        applyVehicleExtraStates(previewVehicle, states)
    end
    if previewShared then
        syncPreviewExtrasStatebag()
    end
    startPreviewWatcher()
    Admin.sendUiState()
    return true
end

Admin.getPreviewVehicleExtras = collectPreviewExtraStates

Admin.togglePreviewVehicleExtra = function(extraId)
    extraId = tonumber(extraId)
    if not extraId then
        return false
    end

    if previewVehicle == 0 or not DoesEntityExist(previewVehicle) then
        return false
    end

    if not DoesExtraExist(previewVehicle, extraId) then
        return false
    end

    local curOn = IsVehicleExtraTurnedOn(previewVehicle, extraId) and true or false
    SetVehicleExtra(previewVehicle, extraId, curOn)
    syncPreviewExtrasStatebag()
    return true
end

Admin.spawnVehicleFromPreview = function()
    local model = previewModel
    if not model or model == '' then
        notify('error', 'No preview vehicle active.')
        return false
    end

    if previewVehicle == 0 or not DoesEntityExist(previewVehicle) then
        notify('error', 'No preview vehicle active.')
        return false
    end

    local extrasSnapshot = collectPreviewExtraStates()
    clearVehiclePreview()
    return spawnVehicleAtPedWithExtras(model, extrasSnapshot, 'vehicle.spawn') == true
end

function actionSpawnVehicle(data)
    local model = data and data.model
    if not model or model == '' then
        notify('error', 'Vehicle model required.')
        return
    end

    clearVehiclePreview()
    spawnVehicleAtPedWithExtras(model, nil, 'vehicle.spawn')
end

function actionRepairVehicle()
    local vehicle = ensureVehicle()
    if not vehicle then return end

    SetVehicleFixed(vehicle)
    SetVehicleDeformationFixed(vehicle)
    SetVehicleDirtLevel(vehicle, 0.0)
    notify('success', 'Vehicle repaired.')
end

function actionCleanVehicle()
    local vehicle = ensureVehicle()
    if not vehicle then return end

    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehicleEnveffScale(vehicle, 0.0)
    notify('success', 'Vehicle cleaned.')
end

function actionDeleteVehicle()
    local vehicle = ensureVehicle()
    if not vehicle then return end

    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteEntity(vehicle)
    notify('success', 'Vehicle deleted.')
end

function actionFlipVehicle()
    local vehicle = ensureVehicle()
    if not vehicle then return end

    local coords = GetEntityCoords(vehicle)
    SetEntityCoordsNoOffset(vehicle, coords.x, coords.y, coords.z + 0.5, true, true, true)
    SetEntityRotation(vehicle, 0.0, 0.0, GetEntityHeading(vehicle), 2, true)
    notify('success', 'Vehicle flipped.')
end

function actionMaxMods()
    local vehicle = ensureVehicle()
    if not vehicle then return end

    applyVehicleMods(vehicle)
    notify('success', 'Max mods applied.')
end

Admin.vehicleTuning = Admin.vehicleTuning or {
    sessions = {},
    fields = {
        { id = 'fInitialDriveForce', label = 'Drive force', description = 'Acceleration delivered through the drivetrain', group = 'Powertrain', min = 0.01, max = 2.0, step = 0.01, precision = 2 },
        { id = 'fDriveInertia', label = 'Drive inertia', description = 'How quickly the engine builds and sheds revs', group = 'Powertrain', min = 0.1, max = 5.0, step = 0.05, precision = 2 },
        { id = 'fInitialDriveMaxFlatVel', label = 'Max flat velocity', description = 'Base transmission speed target from handling data', group = 'Powertrain', min = 10.0, max = 500.0, step = 1.0, precision = 0 },
        { id = 'fClutchChangeRateScaleUpShift', label = 'Upshift rate', description = 'Clutch speed while shifting into a higher gear', group = 'Powertrain', min = 0.1, max = 20.0, step = 0.1, precision = 1 },
        { id = 'fClutchChangeRateScaleDownShift', label = 'Downshift rate', description = 'Clutch speed while shifting into a lower gear', group = 'Powertrain', min = 0.1, max = 20.0, step = 0.1, precision = 1 },
        { id = 'fInitialDragCoeff', label = 'Drag coefficient', description = 'Aerodynamic resistance as speed increases', group = 'Powertrain', min = 0.1, max = 100.0, step = 0.1, precision = 1 },

        { id = 'fBrakeForce', label = 'Brake force', description = 'Overall service-brake strength', group = 'Control', min = 0.01, max = 5.0, step = 0.01, precision = 2 },
        { id = 'fBrakeBiasFront', label = 'Front brake bias', description = '0 sends braking rearward; 1 sends it forward', group = 'Control', min = 0.0, max = 1.0, step = 0.01, precision = 2 },
        { id = 'fHandBrakeForce', label = 'Handbrake force', description = 'Rear-wheel lock strength for the handbrake', group = 'Control', min = 0.0, max = 5.0, step = 0.05, precision = 2 },
        { id = 'fSteeringLock', label = 'Steering lock', description = 'Maximum steering angle', group = 'Control', min = 5.0, max = 90.0, step = 0.5, precision = 1, unit = 'deg' },
        { id = 'fDriveBiasFront', label = 'Front drive bias', description = '0 is rear-wheel drive, 1 is front-wheel drive', group = 'Control', min = 0.0, max = 1.0, step = 0.01, precision = 2 },

        { id = 'fTractionCurveMax', label = 'Peak grip', description = 'Maximum tyre grip before slip begins', group = 'Grip', min = 0.1, max = 10.0, step = 0.01, precision = 2 },
        { id = 'fTractionCurveMin', label = 'Sliding grip', description = 'Tyre grip retained while the vehicle is sliding', group = 'Grip', min = 0.1, max = 10.0, step = 0.01, precision = 2 },
        { id = 'fTractionCurveLateral', label = 'Lateral curve', description = 'Slip angle where the tyre reaches peak grip', group = 'Grip', min = 1.0, max = 45.0, step = 0.1, precision = 1 },
        { id = 'fLowSpeedTractionLossMult', label = 'Launch slip', description = 'Low-speed wheelspin multiplier', group = 'Grip', min = 0.0, max = 5.0, step = 0.05, precision = 2 },
        { id = 'fTractionBiasFront', label = 'Front traction bias', description = 'How available grip is distributed front to rear', group = 'Grip', min = 0.0, max = 1.0, step = 0.01, precision = 2 },

        { id = 'fMass', label = 'Mass', description = 'Vehicle mass used by handling calculations', group = 'Chassis', min = 100.0, max = 10000.0, step = 10.0, precision = 0, unit = 'kg' },
        { id = 'fSuspensionForce', label = 'Spring force', description = 'Overall suspension spring strength', group = 'Chassis', min = 0.1, max = 10.0, step = 0.05, precision = 2 },
        { id = 'fSuspensionCompDamp', label = 'Compression damping', description = 'Resistance while the suspension compresses', group = 'Chassis', min = 0.1, max = 10.0, step = 0.05, precision = 2 },
        { id = 'fSuspensionReboundDamp', label = 'Rebound damping', description = 'Resistance while the suspension extends', group = 'Chassis', min = 0.1, max = 10.0, step = 0.05, precision = 2 },
        { id = 'fSuspensionUpperLimit', label = 'Upper travel', description = 'Maximum upward suspension movement', group = 'Chassis', min = -1.0, max = 1.0, step = 0.01, precision = 2 },
        { id = 'fSuspensionLowerLimit', label = 'Lower travel', description = 'Maximum downward suspension movement', group = 'Chassis', min = -1.0, max = 1.0, step = 0.01, precision = 2 },
        { id = 'fSuspensionRaise', label = 'Ride height', description = 'Raises or lowers the chassis at rest', group = 'Chassis', min = -1.0, max = 1.0, step = 0.01, precision = 2 },
        { id = 'fAntiRollBarForce', label = 'Anti-roll force', description = 'Resistance to chassis roll in corners', group = 'Chassis', min = 0.0, max = 10.0, step = 0.05, precision = 2 },
        { id = 'fAntiRollBarBiasFront', label = 'Front anti-roll bias', description = 'Anti-roll stiffness distribution front to rear', group = 'Chassis', min = 0.0, max = 1.0, step = 0.01, precision = 2 },
        { id = 'fRollCentreHeightFront', label = 'Front roll centre', description = 'Front roll-centre height relative to the chassis', group = 'Chassis', min = -1.0, max = 1.0, step = 0.01, precision = 2 },
        { id = 'fRollCentreHeightRear', label = 'Rear roll centre', description = 'Rear roll-centre height relative to the chassis', group = 'Chassis', min = -1.0, max = 1.0, step = 0.01, precision = 2 },
    },
    audioPresets = {
        { label = 'Adder V8', value = 'ADDER' },
        { label = 'Banshee', value = 'BANSHEE' },
        { label = 'Carbonizzare', value = 'CARBONIZARE' },
        { label = 'Comet', value = 'COMET2' },
        { label = 'Dominator V8', value = 'DOMINATOR' },
        { label = 'Elegy', value = 'ELEGY' },
        { label = 'Sultan RS', value = 'SULTANRS' },
        { label = 'Zentorno V12', value = 'ZENTORNO' },
    },
}

function Admin.canUseVehicleTuning()
    return state.allowed['vehicle.liveTuning'] ~= false
end

function Admin.findVehicleTuningField(fieldId)
    if type(fieldId) ~= 'string' then return nil end

    for i = 1, #Admin.vehicleTuning.fields do
        local field = Admin.vehicleTuning.fields[i]
        if field.id == fieldId then
            return field
        end
    end

    return nil
end

function Admin.getVehicleTuningVehicle()
    local ped = getPed()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil, 'Enter a vehicle to start a live tuning session.'
    end

    if GetPedInVehicleSeat(vehicle, -1) ~= ped then
        return nil, 'Move to the driver seat before changing handling.'
    end

    return vehicle
end

function Admin.getVehicleTuningSession()
    if not Admin.canUseVehicleTuning() then
        return nil, 'You do not have permission to use live vehicle tuning.'
    end

    local vehicle, vehicleError = Admin.getVehicleTuningVehicle()
    if not vehicle then
        return nil, vehicleError
    end

    for handle, saved in pairs(Admin.vehicleTuning.sessions) do
        if not DoesEntityExist(handle) or GetEntityModel(handle) ~= saved.model then
            Admin.vehicleTuning.sessions[handle] = nil
        end
    end

    local model = GetEntityModel(vehicle)
    local session = Admin.vehicleTuning.sessions[vehicle]
    if session and session.model == model then
        return session
    end

    local defaults = {}
    for i = 1, #Admin.vehicleTuning.fields do
        local field = Admin.vehicleTuning.fields[i]
        local value = GetVehicleHandlingFloat(vehicle, 'CHandlingData', field.id)
        defaults[field.id] = value
    end

    local displayName = GetDisplayNameFromVehicleModel(model)
    if type(displayName) ~= 'string' or displayName == '' or displayName == 'NULL' then
        displayName = ('0x%08X'):format(model)
    end

    local label = GetLabelText(displayName)
    if type(label) ~= 'string' or label == '' or label == 'NULL' then
        label = displayName
    end

    session = {
        vehicle = vehicle,
        model = model,
        modelName = displayName,
        label = label,
        plate = GetVehicleNumberPlateText(vehicle) or '',
        defaults = defaults,
        defaultAudio = displayName,
        audioName = nil,
    }
    Admin.vehicleTuning.sessions[vehicle] = session
    return session
end

function Admin.buildVehicleTuningSnapshot()
    local session, sessionError = Admin.getVehicleTuningSession()
    if not session then
        return { ok = false, error = 'vehicle_unavailable', message = sessionError }
    end

    local fields = {}
    for i = 1, #Admin.vehicleTuning.fields do
        local definition = Admin.vehicleTuning.fields[i]
        fields[i] = {
            id = definition.id,
            label = definition.label,
            description = definition.description,
            group = definition.group,
            min = definition.min,
            max = definition.max,
            step = definition.step,
            precision = definition.precision,
            unit = definition.unit,
            value = GetVehicleHandlingFloat(session.vehicle, 'CHandlingData', definition.id),
            defaultValue = session.defaults[definition.id],
        }
    end

    return {
        ok = true,
        vehicle = {
            label = session.label,
            model = session.modelName,
            plate = session.plate,
        },
        fields = fields,
        audio = {
            value = session.audioName or '',
            defaultValue = session.defaultAudio,
            presets = Admin.vehicleTuning.audioPresets,
        },
    }
end

function Admin.setVehicleTuningValue(fieldId, rawValue)
    local definition = Admin.findVehicleTuningField(fieldId)
    local value = tonumber(rawValue)
    if not definition or not value or value ~= value or value < definition.min or value > definition.max then
        return { ok = false, error = 'invalid_handling_value', message = 'That handling value is outside the supported range.' }
    end

    local session, sessionError = Admin.getVehicleTuningSession()
    if not session then
        return { ok = false, error = 'vehicle_unavailable', message = sessionError }
    end

    SetVehicleHandlingFloat(session.vehicle, 'CHandlingData', definition.id, value + 0.0)
    if definition.id == 'fInitialDriveForce' or definition.id == 'fInitialDriveMaxFlatVel' then
        ModifyVehicleTopSpeed(session.vehicle, 0.0)
    end

    return {
        ok = true,
        field = definition.id,
        value = GetVehicleHandlingFloat(session.vehicle, 'CHandlingData', definition.id),
    }
end

function Admin.resetVehicleTuningField(fieldId)
    local definition = Admin.findVehicleTuningField(fieldId)
    if not definition then
        return { ok = false, error = 'invalid_handling_field', message = 'That handling setting is not available.' }
    end

    local session, sessionError = Admin.getVehicleTuningSession()
    if not session then
        return { ok = false, error = 'vehicle_unavailable', message = sessionError }
    end

    local defaultValue = session.defaults[definition.id]
    if type(defaultValue) ~= 'number' then
        return { ok = false, error = 'missing_handling_default', message = 'That setting has no captured default.' }
    end

    SetVehicleHandlingFloat(session.vehicle, 'CHandlingData', definition.id, defaultValue + 0.0)
    if definition.id == 'fInitialDriveForce' or definition.id == 'fInitialDriveMaxFlatVel' then
        ModifyVehicleTopSpeed(session.vehicle, 0.0)
    end

    return {
        ok = true,
        field = definition.id,
        value = GetVehicleHandlingFloat(session.vehicle, 'CHandlingData', definition.id),
    }
end

function Admin.forceVehicleTuningAudio(vehicle, soundName)
    if type(ForceVehicleEngineAudio) == 'function' then
        ForceVehicleEngineAudio(vehicle, soundName)
        return true
    end

    if type(ForceUseAudioGameObject) == 'function' then
        ForceUseAudioGameObject(vehicle, soundName)
        return true
    end

    return false
end

function Admin.setVehicleTuningAudio(rawSoundName)
    local soundName = trimString(rawSoundName)
    if not soundName or #soundName > 64 or not soundName:match('^[%w_%-]+$') then
        return { ok = false, error = 'invalid_audio_name', message = 'Use a valid engine audio name (letters, numbers, _ or -).' }
    end

    local session, sessionError = Admin.getVehicleTuningSession()
    if not session then
        return { ok = false, error = 'vehicle_unavailable', message = sessionError }
    end

    if not Admin.forceVehicleTuningAudio(session.vehicle, soundName) then
        return { ok = false, error = 'audio_native_unavailable', message = 'Engine audio switching is unavailable in this client build.' }
    end

    session.audioName = soundName
    return { ok = true, value = soundName }
end

function Admin.resetVehicleTuning(scope)
    local session, sessionError = Admin.getVehicleTuningSession()
    if not session then
        return { ok = false, error = 'vehicle_unavailable', message = sessionError }
    end

    if scope == 'audio' then
        Admin.forceVehicleTuningAudio(session.vehicle, session.defaultAudio)
        session.audioName = nil
        return { ok = true, value = '' }
    end

    for i = 1, #Admin.vehicleTuning.fields do
        local definition = Admin.vehicleTuning.fields[i]
        local defaultValue = session.defaults[definition.id]
        if type(defaultValue) == 'number' then
            SetVehicleHandlingFloat(session.vehicle, 'CHandlingData', definition.id, defaultValue + 0.0)
        end
    end
    ModifyVehicleTopSpeed(session.vehicle, 0.0)

    if scope == 'all' then
        Admin.forceVehicleTuningAudio(session.vehicle, session.defaultAudio)
        session.audioName = nil
    end

    return Admin.buildVehicleTuningSnapshot()
end

function Admin.restoreVehicleTuningSessions()
    for vehicle, session in pairs(Admin.vehicleTuning.sessions) do
        if DoesEntityExist(vehicle) and GetEntityModel(vehicle) == session.model then
            for i = 1, #Admin.vehicleTuning.fields do
                local definition = Admin.vehicleTuning.fields[i]
                local defaultValue = session.defaults[definition.id]
                if type(defaultValue) == 'number' then
                    SetVehicleHandlingFloat(vehicle, 'CHandlingData', definition.id, defaultValue + 0.0)
                end
            end
            ModifyVehicleTopSpeed(vehicle, 0.0)
            Admin.forceVehicleTuningAudio(vehicle, session.defaultAudio)
        end
    end
    Admin.vehicleTuning.sessions = {}
end


function actionSetWeather(value)
    TriggerServerEvent('cortex-admin:server:setWorldState', { weather = value })
end

function getCurrentDynamicWeatherZone()
    if GetResourceState('Dynamic_weather') ~= 'started' then
        notify('error', 'Dynamic_weather is not started.')
        return nil
    end

    local coords = GetEntityCoords(getPed())
    local ok, zone = pcall(function()
        return exports['Dynamic_weather']:getZoneAt(coords.x, coords.y)
    end)

    if not ok then
        notify('error', 'Could not detect current weather zone.')
        return nil
    end

    if type(zone) ~= 'table' or type(zone.id) ~= 'string' or zone.id == '' then
        notify('error', 'You are not inside a Dynamic_weather zone.')
        return nil
    end

    return zone
end

function actionForceCurrentZoneWeather(data)
    local weatherType = normalizeWeatherCommandArg(data and (data.weatherType or data.value))
    if not weatherType then
        notify('error', 'Weather type is required.')
        return
    end

    local zone = getCurrentDynamicWeatherZone()
    if not zone then return end

    ExecuteCommand(('weather force %s %s'):format(zone.id, weatherType))
end

function actionSetTime(value)
    local hour = tonumber(value)
    if not hour then
        notify('error', 'Invalid hour.')
        return
    end
    TriggerServerEvent('cortex-admin:server:setWorldState', { hour = hour, minute = 0 })
end

function actionTeleportWaypoint()
    local blip = GetFirstBlipInfoId(8)
    if blip == 0 then
        notify('error', 'No waypoint set.')
        return
    end

    local coords = GetBlipInfoIdCoord(blip)
    state.lastCoords = GetEntityCoords(getPed())
    SetEntityCoordsNoOffset(getPed(), coords.x, coords.y, coords.z, false, false, false)
    notify('success', 'Teleported to waypoint.')
end

function actionTeleportCoords(data)
    local x = parseNumber(data and data.x)
    local y = parseNumber(data and data.y)
    local z = parseNumber(data and data.z)

    if not x or not y or not z then
        notify('error', 'Invalid coordinates.')
        return
    end

    state.lastCoords = GetEntityCoords(getPed())
    SetEntityCoordsNoOffset(getPed(), x + 0.0, y + 0.0, z + 0.0, false, false, false)
    notify('success', 'Teleported to coordinates.')
end

function actionTeleportBack()
    if not state.lastCoords then
        notify('error', 'No previous location stored.')
        return
    end

    SetEntityCoordsNoOffset(getPed(), state.lastCoords.x, state.lastCoords.y, state.lastCoords.z, false, false, false)
    notify('success', 'Returned to last location.')
end

Admin.getSavedTeleportLocations = function()
    return buildSavedTeleportLocationList()
end

Admin.saveCurrentTeleportLocation = function(name)
    if not name or name == '' then
        notify('error', 'Please enter a location name.')
        return false
    end

    local ped = getPed()
    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local locations = loadSavedTeleportLocationsRaw()
    locations[name] = {
        x = coords.x,
        y = coords.y,
        z = coords.z,
        h = heading,
    }
    saveKvpJson(C.TELEPORT_LOCATIONS_KEY, locations)
    notify('success', ('Location saved: %s'):format(name))
    return true
end

Admin.loadSavedTeleportLocation = function(name)
    if not name or name == '' then
        notify('error', 'Please enter a location name.')
        return false
    end

    local locations = loadSavedTeleportLocationsRaw()
    local loc = locations[name]
    if not loc then
        notify('error', ('Location not found: %s'):format(name))
        return false
    end

    local ped = getPed()
    SetEntityCoordsNoOffset(ped, loc.x, loc.y, loc.z, false, false, false)
    if loc.h then
        SetEntityHeading(ped, loc.h)
    end
    notify('success', ('Teleported to: %s'):format(name))
    return true
end

Admin.deleteSavedTeleportLocation = function(name)
    if not name or name == '' then
        notify('error', 'Please enter a location name.')
        return false
    end

    local locations = loadSavedTeleportLocationsRaw()
    if not locations[name] then
        notify('error', ('Location not found: %s'):format(name))
        return false
    end

    locations[name] = nil
    saveKvpJson(C.TELEPORT_LOCATIONS_KEY, locations)
    notify('success', ('Deleted location: %s'):format(name))
    return true
end

function teleportToCoords(x, y, showNotification)
    if not x or not y then return false end

    local ped = getPed()
    state.lastCoords = GetEntityCoords(ped)

    local foundZ = 0.0
    
    RequestCollisionAtCoord(x, y, 500.0)
    Wait(100)

    for testZ = 800, 0, -25 do
        NewLoadSceneStart(x, y, testZ, x, y, testZ, 100.0, 0)
        local timeout = GetGameTimer() + 1000
        while IsNetworkLoadingScene() and GetGameTimer() < timeout do
            Wait(10)
        end
        
        local hit, groundZ = GetGroundZFor_3dCoord(x, y, testZ + 0.0, false)
        if hit then
            foundZ = groundZ + 1.0
            break
        end
    end

    if foundZ < 1.0 then
        foundZ = 100.0
    end

    SetEntityCoordsNoOffset(ped, x + 0.0, y + 0.0, foundZ, false, false, false)
    
    if showNotification then
        notify('success', ('Teleported to %.1f, %.1f'):format(x, y))
    end
    
    return true
end

exports('teleportToCoords', teleportToCoords)

function actionGiveWeapon(data)
    local weapon = data and (data.weapon or data.value)
    if type(weapon) ~= 'string' then
        notify('error', 'Weapon name required.')
        return
    end
    weapon = weapon:match('^%s*(.-)%s*$'):lower()
    if weapon == '' or #weapon > 64 or not weapon:match('^[%w_%-]+$') then
        notify('error', 'Enter a valid weapon model name.')
        return
    end
    if weapon ~= 'gadget_parachute' and weapon:sub(1, 7) ~= 'weapon_' then weapon = 'weapon_' .. weapon end

    local authorizationAction = data and data.authorizationAction == 'weapons.giveCustom'
        and 'weapons.giveCustom' or 'weapons.give'
    if not authorizeModel('weapon', weapon, authorizationAction) then return end

    GiveWeaponToPed(getPed(), joaat(weapon), 250, false, true)
    notify('success', ('Weapon given: %s'):format(weapon))
end

--- GTA parachute gadget hash (see vespura parachute tints doc)
local PARACHUTE_WEAPON_HASH = joaat('gadget_parachute')

function actionGiveParachute(value)
    local tint = tonumber(value)
    if tint == nil then
        tint = 0
    end
    tint = math.floor(tint)
    if tint < 0 then
        tint = 0
    elseif tint > 13 then
        tint = 13
    end

    local ped = getPed()
    local playerId = PlayerId()
    if not authorizeModel('weapon', 'gadget_parachute', 'weapons.parachute') then return end
    if not HasPedGotWeapon(ped, PARACHUTE_WEAPON_HASH, false) then
        GiveWeaponToPed(ped, PARACHUTE_WEAPON_HASH, 1, false, true)
    end
    SetPlayerHasReserveParachute(playerId, true)
    SetPlayerParachutePackTintIndex(playerId, tint)
    SetPlayerReserveParachuteTintIndex(playerId, tint)
    notify('success', ('Parachute given (tint %d).'):format(tint))
end

function actionRemoveWeapons()
    RemoveAllPedWeapons(getPed(), true)
    notify('success', 'Weapons removed.')
end

function actionSetAmmo(data)
    local ammo = parseNumber(data and data.ammo)
    if not ammo then
        notify('error', 'Ammo amount required.')
        return
    end

    local weapon = GetSelectedPedWeapon(getPed())
    if weapon == 0 then
        notify('error', 'No weapon selected.')
        return
    end

    SetPedAmmo(getPed(), weapon, ammo)
    notify('success', 'Ammo updated.')
end

function actionClearArea(data)
    local radius = parseNumber(data and (data.radius or data.value)) or 50
    local pedsCleared = clearPoolEntities('CPed', radius)
    local vehiclesCleared = clearPoolEntities('CVehicle', radius)
    local objectsCleared = clearPoolEntities('CObject', radius)
    local total = pedsCleared + vehiclesCleared + objectsCleared
    notify('success', ('Cleared %d entities (%d peds, %d vehicles, %d objects).'):format(total, pedsCleared, vehiclesCleared, objectsCleared))
end

function actionClearVehicles(data)
    local radius = parseNumber(data and (data.radius or data.value)) or 100
    local cleared = clearPoolEntities('CVehicle', radius)
    notify('success', ('Cleared %d vehicle(s).'):format(cleared))
end

function actionClearPeds(data)
    local radius = parseNumber(data and (data.radius or data.value)) or 100
    local cleared = clearPoolEntities('CPed', radius)
    notify('success', ('Cleared %d ped(s).'):format(cleared))
end

function actionClearObjects(data)
    local radius = parseNumber(data and (data.radius or data.value)) or 100
    local cleared = clearPoolEntities('CObject', radius)
    notify('success', ('Cleared %d object(s).'):format(cleared))
end

function actionTakePhoto()
    if GetResourceState('screenshot-basic') ~= 'started' then
        notify('error', 'screenshot-basic must be started before taking a photo.')
        return
    end

    closeMenuForDevCapture()
    notify('info', 'Capturing photo...')
    TriggerServerEvent('cortex-admin:server:takePhoto')
end

function actionOpenGallery()
    Admin.setOpen(false)
    Wait(75)
    ActivateFrontendMenu(joaat('FE_MENU_VERSION_MP_PAUSE'), true, 3)
end

function actionStartRecording()
    if IsRecording() then
        notify('error', 'Already recording. Stop your current recording first.')
        return
    end

    closeMenuForDevCapture()
    StartRecording(1)
    Wait(0)

    if not IsRecording() then
        clearRecordingState()
        notify('error', 'Failed to start recording.')
        return
    end

    recordingState.startedAt = GetGameTimer()
    local keyLabel = (Config and Config.Keybind) and tostring(Config.Keybind) or 'menu key'
    local cmdLabel = (Config and Config.Command) and tostring(Config.Command) or 'esadmin'
    notify('success', ('Recording started. Press %s or /%s to reopen admin, then Stop or Discard.'):format(keyLabel, cmdLabel))
end

function actionStopRecording()
    if not IsRecording() then
        clearRecordingState()
        notify('error', 'You are not currently recording.')
        return
    end

    local startedAt = recordingState.startedAt
    if startedAt > 0 then
        local elapsed = GetGameTimer() - startedAt
        if elapsed < MIN_RECORDING_DURATION_MS then
            local remaining = (MIN_RECORDING_DURATION_MS - elapsed) / 1000.0
            notify('error', ('Keep recording for %.1fs more before saving the clip.'):format(remaining))
            return
        end
    end

    StopRecordingAndSaveClip()
    clearRecordingState()
    notify('success', 'Recording stopped. Saving clip...')
end

function actionDiscardRecording()
    if not IsRecording() then
        clearRecordingState()
        notify('error', 'You are not currently recording.')
        return
    end

    StopRecordingAndDiscardClip()
    clearRecordingState()
    notify('success', 'Recording discarded.')
end

function actionOpenRockstarEditor()
    if IsRecording() then
        notify('error', 'Stop or discard the active recording before opening Rockstar Editor.')
        return
    end

    local quitSessionFirst = state.settings and state.settings.quitSessionInRockstarEditor == true
    Admin.setOpen(false)
    Wait(75)

    if quitSessionFirst then
        NetworkSessionEnd(true, true)
        Wait(250)
    end

    ActivateRockstarEditor()

    if quitSessionFirst then
        notify('info', 'Session ended before opening Rockstar Editor. Restart GTA V to rejoin the server session.')
    end
end

function toggleHud(enabled)
    state.toggles['dev.noHud'] = enabled
end

Admin.executeAction = function(actionId, data)
    if type(Admin.dispatchVmenuAction) == 'function' then
        local handled, result = Admin.dispatchVmenuAction('execute', actionId, data)
        if handled then return result end
    end
    if actionId == 'player.heal' then
        return actionPlayerHeal()
    elseif actionId == 'player.armor' then
        return actionPlayerArmor()
    elseif actionId == 'player.revive' then
        return actionPlayerRevive()
    elseif actionId == 'player.clearWanted' then
        return actionClearWanted()
    elseif actionId == 'player.cleanPlayer' then
        local ped = getPed()
        ClearPedBloodDamage(ped)
        ResetPedVisibleDamage(ped)
        notify('success', 'Player cleaned.')
        return
    elseif actionId == 'player.dryPlayer' then
        local ped = getPed()
        ClearPedWetness(ped)
        notify('success', 'Player dried.')
        return
    elseif actionId == 'player.wetPlayer' then
        local ped = getPed()
        SetPedWetnessHeight(ped, 2.0)
        notify('success', 'Player is now wet.')
        return
    elseif actionId == 'player.setModel' then
        return actionSetModel(data)
    elseif actionId == 'player.saveMpPed' then
        return actionSaveMpPed(data)
    elseif actionId == 'player.loadMpPed' then
        return actionLoadMpPed(data)
    elseif actionId == 'player.setFaceFeature' then
        return actionSetFaceFeature(data)
    elseif actionId == 'player.randomizeMpFace' then
        return actionRandomizeMpPedFace()
    elseif actionId == 'player.randomizeAppearance' then
        return Admin.randomizeAppearance(data)
    elseif actionId == 'player.undoRandomizedAppearance' then
        return Admin.undoRandomizedAppearance()
    elseif actionId == 'player.clearPedTattoos' then
        return actionClearPedTattoos()
    elseif actionId == 'player.setDefaultSavedPed' then
        return Admin.setDefaultSavedPed(data and (data.entry or data))
    elseif actionId == 'player.savePed' then
        return actionSavePed(data)
    elseif actionId == 'player.loadPed' then
        return actionLoadPed(data)
    elseif actionId == 'player.copyCoords' then
        return actionCopyCoords(data)
    elseif actionId == 'player.copyHeading' then
        return actionCopyHeading()
    elseif actionId == 'vehicle.spawn' then
        return actionSpawnVehicle(data)
    elseif actionId == 'vehicle.save' then
        return actionSaveVehicle(data)
    elseif actionId == 'vehicle.saveLegacy' then
        return actionSaveVehicleLegacy()
    elseif actionId == 'vehicle.load' then
        return actionLoadVehicle(data)
    elseif actionId == 'vehicle.personal' then
        return actionSpawnPersonalVehicle(data)
    elseif actionId == 'vehicle.savePersonal' then
        return actionSavePersonalVehicle(data)
    elseif actionId == 'vehicle.removePersonal' then
        return actionRemovePersonalVehicle(data)
    elseif actionId == 'vehicle.repair' then
        return actionRepairVehicle()
    elseif actionId == 'vehicle.clean' then
        return actionCleanVehicle()
    elseif actionId == 'vehicle.delete' then
        return actionDeleteVehicle()
    elseif actionId == 'vehicle.destroyEngine' then
        local vehicle = ensureVehicle()
        if vehicle then
            SetVehicleEngineHealth(vehicle, -4000.0)
            SetVehicleUndriveable(vehicle, true)
            notify('success', 'Engine destroyed.')
        end
        return
    elseif actionId == 'vehicle.flip' then
        return actionFlipVehicle()
    elseif actionId == 'vehicle.maxMods' then
        return actionMaxMods()
    elseif actionId == 'vehicle.speedLimiter' then
        local speed = parseNumber(data and data.speed)
        if not speed or speed <= 0 then
            notify('error', 'Invalid speed value.')
            return
        end
        local vehicle = ensureVehicle()
        if vehicle then
            local speedMs = speed / 3.6
            SetEntityMaxSpeed(vehicle, speedMs)
            state.vehicleSpeedLimit = speedMs
            notify('success', ('Speed limit set to %d km/h'):format(speed))
        end
        return
    elseif actionId == 'vehicle.clearSpeedLimit' then
        local vehicle = ensureVehicle()
        if vehicle then
            SetEntityMaxSpeed(vehicle, 0.0)
            state.vehicleSpeedLimit = nil
            notify('success', 'Speed limit cleared.')
        end
        return
    elseif actionId == 'vehicle.changePlate' then
        local plate = data and data.plate
        if not plate or plate == '' then
            notify('error', 'Please enter plate text.')
            return
        end
        local vehicle = ensureVehicle()
        if vehicle then
            SetVehicleNumberPlateText(vehicle, plate:sub(1, 8))
            notify('success', ('Plate set to: %s'):format(plate:sub(1, 8)))
        end
        return
    elseif actionId == 'world.weather' then
        return actionSetWeather(data and data.value)
    elseif actionId == 'world.weatherEditor' then
        ExecuteCommand('weathereditor')
        return
    elseif actionId == 'world.weatherReload' then
        ExecuteCommand('weather reload')
        return
    elseif actionId == 'world.weatherForce' then
        local zoneId = trimString(data and data.zoneId)
        local weatherType = normalizeWeatherCommandArg(data and data.weatherType)
        if not zoneId or zoneId == '' or not weatherType or weatherType == '' then
            notify('error', 'Zone ID and weather type are required.')
            return
        end

        ExecuteCommand(('weather force %s %s'):format(zoneId, weatherType))
        return
    elseif actionId == 'world.weatherForceCurrent' then
        actionForceCurrentZoneWeather(data)
        return
    elseif actionId == 'world.time' then
        return actionSetTime(data and data.value)
    elseif actionId == 'world.clearArea' then
        return actionClearArea(data)
    elseif actionId == 'world.clearVehicles' then
        return actionClearVehicles(data)
    elseif actionId == 'world.clearPeds' then
        return actionClearPeds(data)
    elseif actionId == 'world.clearObjects' then
        return actionClearObjects(data)
    elseif actionId == 'teleport.waypoint' or actionId == 'teleport.marker' then
        return actionTeleportWaypoint()
    elseif actionId == 'teleport.coords' then
        return actionTeleportCoords(data)
    elseif actionId == 'teleport.back' then
        return actionTeleportBack()
    elseif actionId == 'teleport.saveLocation' then
        local name = data and data.name
        return Admin.saveCurrentTeleportLocation(name)
    elseif actionId == 'teleport.loadLocation' then
        local name = data and data.name
        return Admin.loadSavedTeleportLocation(name)
    elseif actionId == 'teleport.deleteLocation' then
        local name = data and data.name
        return Admin.deleteSavedTeleportLocation(name)
    elseif actionId == 'weapons.give' then
        return actionGiveWeapon(data)
    elseif actionId == 'weapons.giveCustom' then
        return actionGiveWeapon({
            weapon = data and (data.weapon or data.value),
            authorizationAction = 'weapons.giveCustom',
        })
    elseif actionId == 'weapons.giveAll' then
        return actionGiveAllWeapons()
    elseif actionId == 'weapons.removeAll' then
        return actionRemoveWeapons()
    elseif actionId == 'weapons.saveLoadout' then
        return Admin.saveWeaponLoadout(data and data.name)
    elseif actionId == 'weapons.loadLoadout' then
        return Admin.loadWeaponLoadout(data and data.name)
    elseif actionId == 'weapons.deleteLoadout' then
        return Admin.deleteWeaponLoadout(data and data.name)
    elseif actionId == 'weapons.setAmmo' then
        return actionSetAmmo(data)
    elseif actionId == 'weapons.attachments' then
        return
    elseif actionId == 'dev.resetAllSettings' then
        state.settings = {}
        for key, value in pairs(Config.DefaultSettings) do
            state.settings[key] = value
        end

        Admin.saveSettings()
        SendNUIMessage({
            action = 'cortex-admin:setState',
            data = { settings = state.settings }
        })
        SendNUIMessage({ action = 'cortex-admin:reload' })
        notify('success', 'Settings reset and UI reload requested.')
        return
    elseif actionId == 'dev.noHud' then
        return toggleHud(data and data.enabled)
    elseif actionId == 'dev.takePhoto' then
        return actionTakePhoto()
    elseif actionId == 'dev.openGallery' then
        return actionOpenGallery()
    elseif actionId == 'dev.startRecording' then
        return actionStartRecording()
    elseif actionId == 'dev.stopRecording' then
        return actionStopRecording()
    elseif actionId == 'dev.discardRecording' then
        return actionDiscardRecording()
    elseif actionId == 'dev.openRockstarEditor' then
        return actionOpenRockstarEditor()
    elseif actionId == 'dev.setStress' then
        local value = parseNumber(data and data.value)
        if not value then
            notify('error', 'Stress value required.')
            return
        end

        value = math.floor(value)
        if value < 0 then
            value = 0
        elseif value > 100 then
            value = 100
        end

        TriggerServerEvent('cortex-admin:server:setMetadata', {
            target = GetPlayerServerId(PlayerId()),
            key = 'stress',
            value = value,
            actionId = actionId,
        })
        return
    -- QBX player management actions - these are triggered via NUI prompts
    elseif actionId == 'player.kill' or actionId == 'player.reviveTarget'
        or actionId == 'player.sitInVehicle' or actionId == 'player.setJob'
        or actionId == 'player.setGang' or actionId == 'player.setCash'
        or actionId == 'player.setBank' or actionId == 'player.giveMoney'
        or actionId == 'player.setFood' or actionId == 'player.setThirst'
        or actionId == 'player.setStress' or actionId == 'player.openInventory'
        or actionId == 'player.setRoutingBucket' then
        -- These are handled via inline prompts in the NUI
        return
    elseif actionId == 'vehicle.adminCar' then
        -- Save current vehicle to QBX garage via server
        TriggerServerEvent('cortex-admin:server:adminCar')
        return
    elseif actionId == 'vehicle.giveKeys' then
        local vehicle = ensureVehicle()
        if not vehicle then return end
        local model = GetEntityModel(vehicle)
        local authorized, _, token = authorizeModel('vehicle', model, 'vehicle.giveKeys')
        if authorized then Admin.giveKeysForVehicle(vehicle, false, token, 'vehicle.giveKeys') end
        return
    elseif actionId == 'server.pullStash' then
        -- Handled via inline prompt in the NUI
        return
    elseif actionId == 'inventory.giveItem' then
        -- Handled inline via NUI - just switch to inventory tab
        SendNUIMessage({ action = 'cortex-admin:setTab', data = { tab = 'inventory' } })
        return
    elseif actionId == 'garage.spawnVehicle' then
        -- Handled inline via NUI - just switch to garage tab
        SendNUIMessage({ action = 'cortex-admin:setTab', data = { tab = 'garage' } })
        return
    elseif actionId == 'server.resources' then
        SendNUIMessage({ action = 'cortex-admin:setTab', data = { tab = 'server' } })
        return
    elseif actionId == 'server.refresh' then
        TriggerServerEvent('cortex-admin:server:resourceAction', { action = 'refresh', name = 'all' })
        return
    end

    notify('error', ('Action not implemented: %s'):format(tostring(actionId)))
    return false
end

-- Blip map on state.devPlayerBlips. These are Admin.* (not `local function`) so they do not use main-chunk local slots (Lua limit 200).
function Admin.updatePlayerBlips()
    state.devPlayerBlips = state.devPlayerBlips or {}
    local playerBlips = state.devPlayerBlips
    local players = GetActivePlayers()
    local existingIds = {}
    local selfId = PlayerId()

    for i = 1, #players do
        local playerId = players[i]
        existingIds[playerId] = true
        local ped = GetPlayerPed(playerId)

        if ped and DoesEntityExist(ped) and playerId ~= selfId then
            if not playerBlips[playerId] then
                local blip = AddBlipForEntity(ped)
                SetBlipSprite(blip, 1)
                SetBlipColour(blip, 0)
                SetBlipScale(blip, 0.8)
                SetBlipAsShortRange(blip, false)
                BeginTextCommandSetBlipName("STRING")
                AddTextComponentString(GetPlayerName(playerId) or ("Player " .. playerId))
                EndTextCommandSetBlipName(blip)
                playerBlips[playerId] = blip
            end
        end
    end

    for playerId, blip in pairs(playerBlips) do
        if not existingIds[playerId] then
            if DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
            playerBlips[playerId] = nil
        end
    end
end

function Admin.clearPlayerBlips()
    local playerBlips = state.devPlayerBlips
    if playerBlips then
        for playerId, blip in pairs(playerBlips) do
            if DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
        end
    end
    state.devPlayerBlips = {}
end

Admin.toggleAction = function(actionId, enabled)
    if type(Admin.dispatchVmenuAction) == 'function' then
        local handled, result = Admin.dispatchVmenuAction('toggle', actionId, enabled)
        if handled then return result end
    end
    setToggle(actionId, enabled)

    if actionId == 'player.godmode' then
        SetEntityInvincible(getPed(), enabled)
        SetPlayerInvincible(PlayerId(), enabled)
    elseif actionId == 'player.invisible' then
        SetEntityVisible(getPed(), not enabled, false)
    elseif actionId == 'player.noclip' then
        setNoclip(enabled)
    elseif actionId == 'player.superjump' then
    elseif actionId == 'player.infiniteStamina' then
    elseif actionId == 'player.noRagdoll' then
        SetPedCanRagdoll(getPed(), not enabled)
    elseif actionId == 'player.fastRun' then
        SetRunSprintMultiplierForPlayer(PlayerId(), enabled and 1.2 or 1.0)
    elseif actionId == 'player.fastSwim' then
        SetSwimMultiplierForPlayer(PlayerId(), enabled and 1.2 or 1.0)
    elseif actionId == 'player.neverWanted' then
        if enabled then
            SetMaxWantedLevel(0)
            SetPlayerWantedLevel(PlayerId(), 0, false)
            SetPlayerWantedLevelNow(PlayerId(), false)
        else
            SetMaxWantedLevel(5)
        end
    elseif actionId == 'player.freeze' then
        FreezeEntityPosition(getPed(), enabled)
    elseif actionId == 'player.everyoneIgnores' then
        local ped = getPed()
        SetEveryoneIgnorePlayer(PlayerId(), enabled)
        SetPoliceIgnorePlayer(PlayerId(), enabled)
    elseif actionId == 'vehicle.engine' then
        local vehicle = ensureVehicle()
        if vehicle then
            SetVehicleEngineOn(vehicle, enabled, true, true)
        end
    elseif actionId == 'vehicle.invincible' then
        local vehicle = ensureVehicle()
        if vehicle then
            SetEntityInvincible(vehicle, enabled)
            SetVehicleCanBeVisiblyDamaged(vehicle, not enabled)
        end
    elseif actionId == 'vehicle.keepClean' then
    elseif actionId == 'vehicle.bikeSeatbelt' then
        local ped = getPed()
        if enabled then
            SetPedCanBeKnockedOffVehicle(ped, 1)
            SetPedConfigFlag(ped, 32, true)
        else
            SetPedCanBeKnockedOffVehicle(ped, 0)
            SetPedConfigFlag(ped, 32, false)
        end
    elseif actionId == 'weapons.infiniteAmmo' then
        SetPedInfiniteAmmo(getPed(), enabled, 0)
        SetPedInfiniteAmmoClip(getPed(), enabled)
    elseif actionId == 'world.freezeTime' then
        TriggerServerEvent('cortex-admin:server:setWorldState', { freezeTime = enabled })
    elseif actionId == 'world.blackout' then
        TriggerServerEvent('cortex-admin:server:setWorldState', { blackout = enabled })
    elseif actionId == 'dev.noHud' then
        DisplayHud(not enabled)
        DisplayRadar(not enabled)
    elseif actionId == 'dev.nightVision' then
        SetNightvision(enabled)
    elseif actionId == 'dev.thermalVision' then
        SetSeethrough(enabled)
    elseif actionId == 'dev.playerBlips' then
        if enabled then
            Admin.updatePlayerBlips()
        else
            Admin.clearPlayerBlips()
        end
    elseif actionId == 'dev.freecam' then
        setFreecam(enabled, false)
    elseif actionId == 'world.disableNpcs' then
        setAmbientSuppressionState(enabled == true)
        if enabled then
            clearPoolEntities('CPed', 250.0)
            clearPoolEntities('CVehicle', 350.0)
        else
            SetPedDensityMultiplierThisFrame(1.0)
            SetScenarioPedDensityMultiplierThisFrame(1.0, 1.0)
            SetRandomVehicleDensityMultiplierThisFrame(1.0)
            SetParkedVehicleDensityMultiplierThisFrame(1.0)
            SetVehicleDensityMultiplierThisFrame(1.0)
        end
    elseif actionId == 'dev.showCoords' then
        state.coordHudDirty = enabled == true
        SendNUIMessage({
            action = 'cortex-admin:setCoordHud',
            data = {
                visible = enabled == true or state.toggles['dev.locationDisplay'] == true,
                showCoordinates = enabled == true,
                showLocation = state.toggles['dev.locationDisplay'] == true,
            }
        })
    elseif actionId == 'dev.showSpeed' then
        state.speedHudDirty = enabled == true
        SendNUIMessage({
            action = 'cortex-admin:setSpeedHud',
            data = {
                visible = enabled == true,
                position = state.settings.speedHudPosition or 'top-left',
                units = state.settings.speedHudUnits or 'mph',
            }
        })
    elseif actionId == 'options.compactMode' or actionId == 'options.showTargetInfo' or actionId == 'options.doubleClickToRun' or actionId == 'options.autoLoadSavedPed' or actionId == 'options.restorePedOnDeath' or actionId == 'options.defaultToMpPed' or actionId == 'options.replacePersonalVehicle' or actionId == 'options.spawnInsideVehicle' or actionId == 'options.disableAircraftTurbulence' or actionId == 'options.disablePlaneTurbulence' or actionId == 'options.disableHelicopterTurbulence' or actionId == 'options.disablePrivateMessages' or actionId == 'options.disableControllerSupport' or actionId == 'options.recordingControls' or actionId == 'options.minimapControls' or actionId == 'options.fingerPointControls' or actionId == 'options.quitSessionInRockstarEditor' then
        local settingKey = actionId:gsub('options%.', '')
        if settingKey == 'compactMode' then
            state.settings.compactMode = nil
        end
        state.settings[settingKey] = enabled
        print(('[cortex-admin] Toggle setting: %s = %s'):format(settingKey, tostring(enabled)))
        Admin.saveSettings()
        SendNUIMessage({
            action = 'cortex-admin:setState',
            data = { settings = state.settings }
        })
    end
end

Admin.selectAction = function(actionId, value)
    if type(Admin.dispatchVmenuAction) == 'function' then
        local handled, result = Admin.dispatchVmenuAction('select', actionId, value)
        if handled then return result end
    end
    if actionId == 'player.setWantedLevel' then
        local level = tonumber(value) or 0
        if level < 0 then level = 0 end
        if level > 5 then level = 5 end
        SetPlayerWantedLevel(PlayerId(), level, false)
        SetPlayerWantedLevelNow(PlayerId(), false)
        notify('success', ('Wanted level set to %d'):format(level))
        return
    elseif actionId == 'vehicle.torqueMultiplier' then
        local vehicle = ensureVehicle()
        if vehicle then
            local multiplier = tonumber(value) or 1.0
            SetVehicleEngineTorqueMultiplier(vehicle, multiplier + 0.0)
            state.vehicleTorqueMultiplier = multiplier
            notify('success', ('Torque multiplier set to %.1fx'):format(multiplier))
        end
        return
    elseif actionId == 'vehicle.powerMultiplier' then
        local vehicle = ensureVehicle()
        if vehicle then
            local multiplier = tonumber(value) or 1.0
            SetVehicleEnginePowerMultiplier(vehicle, multiplier + 0.0)
            state.vehiclePowerMultiplier = multiplier
            notify('success', ('Power multiplier set to %.1fx'):format(multiplier))
        end
        return
    elseif actionId == 'world.weather' then
        return actionSetWeather(value)
    elseif actionId == 'world.weatherForceCurrent' then
        return actionForceCurrentZoneWeather({ value = value })
    elseif actionId == 'world.time' then
        return actionSetTime(value)
    elseif actionId == 'world.clearArea' then
        return actionClearArea({ value = value })
    elseif actionId == 'world.clearVehicles' then
        return actionClearVehicles({ value = value })
    elseif actionId == 'world.clearPeds' then
        return actionClearPeds({ value = value })
    elseif actionId == 'world.clearObjects' then
        return actionClearObjects({ value = value })
    elseif actionId == 'vehicle.spawn' then
        return actionSpawnVehicleList({ value = value })
    elseif actionId == 'vehicle.personal' then
        return actionSpawnPersonalVehicle({ value = value })
    elseif actionId == 'weapons.give' then
        return actionGiveWeapon({ value = value })
    elseif actionId == 'weapons.parachute' then
        return actionGiveParachute(value)
    elseif actionId == 'weapons.setTint' then
        local tint = tonumber(value)
        if tint == nil then
            tint = 0
        end
        tint = math.floor(tint)
        if tint < 0 then
            tint = 0
        elseif tint > 7 then
            tint = 7
        end
        local ped = getPed()
        local w = GetSelectedPedWeapon(ped)
        if not w or w == 0 or w == WEAPON_UNARMED then
            notify('error', 'Equip a weapon first.')
            return
        end
        SetPedWeaponTintIndex(ped, w, tint)
        notify('success', ('Weapon tint set to %d.'):format(tint))
        return
    elseif actionId == 'options.uiScale' then
        local nextScale = tonumber(value) or 1.0
        if nextScale < 1.0 then nextScale = 1.0 end
        if nextScale > 1.6 then nextScale = 1.6 end
        state.settings.uiScale = nextScale
    elseif actionId == 'options.uiOpacity' then
        local o = tonumber(value)
        if o == nil then
            o = 0.94
        end
        if o < 0.35 then
            o = 0.35
        elseif o > 1.0 then
            o = 1.0
        end
        state.settings.uiOpacity = o
    elseif actionId == 'options.menuAccentColor' then
        local s = type(value) == 'string' and value:gsub('%s+', '') or ''
        if s:sub(1, 1) ~= '#' then
            s = '#' .. s
        end
        local hex = s:match('^#([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])$') or s:match('^#([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])$')
        if not hex then
            notify('error', 'Invalid accent color.')
            return
        end
        if #hex == 3 then
            hex = hex:sub(1, 1) .. hex:sub(1, 1) .. hex:sub(2, 2) .. hex:sub(2, 2) .. hex:sub(3, 3) .. hex:sub(3, 3)
        end
        state.settings.menuAccentColor = ('#%s'):format(hex:lower())
    elseif actionId == 'options.menuPosition' then
        local v = type(value) == 'string' and value:lower() or 'right'
        if v == 'left' or v == 'right' then
            state.settings.menuPosition = v
        else
            state.settings.menuPosition = 'right'
        end
    elseif actionId == 'options.speedHudUnits' then
        local v = type(value) == 'string' and value:lower() or 'mph'
        if v == 'kph' then
            state.settings.speedHudUnits = 'kph'
        else
            state.settings.speedHudUnits = 'mph'
        end
        state.speedHudDirty = true
        SendNUIMessage({
            action = 'cortex-admin:setSpeedHud',
            data = {
                visible = state.toggles['dev.showSpeed'] == true,
                position = state.settings.speedHudPosition or 'top-left',
                units = state.settings.speedHudUnits or 'mph',
            }
        })
    elseif actionId == 'options.speedHudPosition' then
        local v = type(value) == 'string' and value:lower() or 'top-left'
        local ok = v == 'top-left' or v == 'top-right' or v == 'top-center'
            or v == 'bottom-left' or v == 'bottom-right' or v == 'bottom-center'
        if ok then
            state.settings.speedHudPosition = v
        else
            state.settings.speedHudPosition = 'top-left'
        end
        state.speedHudDirty = true
        SendNUIMessage({
            action = 'cortex-admin:setSpeedHud',
            data = {
                visible = state.toggles['dev.showSpeed'] == true,
                position = state.settings.speedHudPosition or 'top-left',
                units = state.settings.speedHudUnits or 'mph',
            }
        })
    end

    Admin.saveSettings()
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = { settings = state.settings }
    })
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    setFreecam(false, true)
    if noclip.enabled then
        setNoclip(false)
    end
    clearVehiclePreview()
    Admin.restoreVehicleTuningSessions()
    setAmbientSuppressionState(false)
end)

CreateThread(function()
    local nextStaminaTick = 0
    local nextNoRagdollTick = 0
    local nextNeverWantedTick = 0
    local nextHudTick = 0
    local nextBlipsTick = 0
    local nextCoordTick = 0
    local nextSpeedTick = 0
    local lastSpeedDisplay = nil
    local nextVehicleCleanTick = 0
    local nextBikeSeatbeltTick = 0
    local nextInfiniteAmmoTick = 0
    local lastCoordX, lastCoordY, lastCoordZ, lastCoordHeading = nil, nil, nil, nil
    local lastStreetHash, lastCrossingHash = nil, nil
    local lastStreetName, lastCrossingName = '', nil

    while true do
        local toggles = state.toggles or {}
        local runPerFrame = toggles['player.superjump'] or toggles['world.disableNpcs']
        local runFast = toggles['player.infiniteStamina']
            or toggles['player.noRagdoll']
            or toggles['dev.noHud']
        local runSlow = toggles['player.neverWanted']
            or toggles['dev.playerBlips']
            or toggles['dev.showCoords']
            or toggles['dev.showSpeed']
            or toggles['vehicle.keepClean']
            or toggles['vehicle.bikeSeatbelt']
            or toggles['weapons.infiniteAmmo']

        if runPerFrame or runFast or runSlow then
            local now = GetGameTimer()
            local ped = PlayerPedId()
            local playerId = PlayerId()

            if recordingState.startedAt > 0 and not IsRecording() then
                clearRecordingState()
            end

            if toggles['player.superjump'] then
                SetSuperJumpThisFrame(playerId)
            end

            if toggles['player.infiniteStamina'] and now >= nextStaminaTick then
                RestorePlayerStamina(playerId, 1.0)
                nextStaminaTick = now + 250
            end

            if toggles['player.noRagdoll'] and now >= nextNoRagdollTick then
                SetPedCanRagdoll(ped, false)
                nextNoRagdollTick = now + 500
            end

            if toggles['player.neverWanted'] and now >= nextNeverWantedTick then
                SetPlayerWantedLevel(playerId, 0, false)
                SetPlayerWantedLevelNow(playerId, false)
                nextNeverWantedTick = now + 250
            end

            if toggles['weapons.infiniteAmmo'] and now >= nextInfiniteAmmoTick then
                SetPedInfiniteAmmoClip(ped, true)
                nextInfiniteAmmoTick = now + 1000
            end

            if toggles['dev.noHud'] and now >= nextHudTick then
                DisplayHud(false)
                DisplayRadar(false)
                nextHudTick = now + 200
            end

            if toggles['dev.playerBlips'] and now >= nextBlipsTick then
                Admin.updatePlayerBlips()
                nextBlipsTick = now + 1000
            end

            if toggles['vehicle.keepClean'] and now >= nextVehicleCleanTick then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle ~= 0 then
                    SetVehicleDirtLevel(vehicle, 0.0)
                end
                nextVehicleCleanTick = now + 750
            end

            if toggles['vehicle.bikeSeatbelt'] and now >= nextBikeSeatbeltTick then
                SetPedCanBeKnockedOffVehicle(ped, 1)
                SetPedConfigFlag(ped, 32, true)
                nextBikeSeatbeltTick = now + 500
            end

            if toggles['world.disableNpcs'] then
                applyAmbientSuppressionFrame()
            end

            if toggles['dev.showCoords'] and now >= nextCoordTick then
                local coords = GetEntityCoords(ped)
                local heading = GetEntityHeading(ped)
                local street, crossing = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
                local streetChanged = false
                local crossingChanged = false

                if street ~= lastStreetHash then
                    lastStreetHash = street
                    lastStreetName = street ~= 0 and GetStreetNameFromHashKey(street) or ''
                    streetChanged = true
                end

                if crossing ~= lastCrossingHash then
                    lastCrossingHash = crossing
                    lastCrossingName = crossing ~= 0 and GetStreetNameFromHashKey(crossing) or nil
                    crossingChanged = true
                end

                local x = coords.x
                local y = coords.y
                local z = coords.z
                local h = heading

                if x >= 0 then
                    x = math.floor((x * 1000.0) + 0.5) / 1000.0
                else
                    x = math.floor((x * 1000.0) - 0.5) / 1000.0
                end

                if y >= 0 then
                    y = math.floor((y * 1000.0) + 0.5) / 1000.0
                else
                    y = math.floor((y * 1000.0) - 0.5) / 1000.0
                end

                if z >= 0 then
                    z = math.floor((z * 1000.0) + 0.5) / 1000.0
                else
                    z = math.floor((z * 1000.0) - 0.5) / 1000.0
                end

                if h >= 0 then
                    h = math.floor((h * 10.0) + 0.5) / 10.0
                else
                    h = math.floor((h * 10.0) - 0.5) / 10.0
                end

                if state.coordHudDirty
                    or x ~= lastCoordX
                    or y ~= lastCoordY
                    or z ~= lastCoordZ
                    or h ~= lastCoordHeading
                    or streetChanged
                    or crossingChanged then
                    lastCoordX = x
                    lastCoordY = y
                    lastCoordZ = z
                    lastCoordHeading = h
                    state.coordHudDirty = false

                    SendNUIMessage({
                        action = 'cortex-admin:updateCoordHud',
                        data = {
                            x = x,
                            y = y,
                            z = z,
                            heading = h,
                            street = lastStreetName,
                            crossing = lastCrossingName
                        }
                    })
                end

                nextCoordTick = now + 150
            end

            if toggles['dev.showSpeed'] and now >= nextSpeedTick then
                local speedMs = GetEntitySpeed(ped)
                local units = state.settings.speedHudUnits or 'mph'
                local display
                if units == 'kph' then
                    display = speedMs * 3.6
                else
                    display = speedMs * 2.236936
                end
                if display >= 0 then
                    display = math.floor((display * 10.0) + 0.5) / 10.0
                else
                    display = math.floor((display * 10.0) - 0.5) / 10.0
                end

                if state.speedHudDirty or display ~= lastSpeedDisplay then
                    lastSpeedDisplay = display
                    state.speedHudDirty = false
                    SendNUIMessage({
                        action = 'cortex-admin:updateSpeedHud',
                        data = { speed = display }
                    })
                end

                nextSpeedTick = now + 120
            end

            if runPerFrame then
                Wait(0)
            elseif runFast then
                Wait(50)
            else
                Wait(150)
            end
        else
            Wait(4000)
        end
    end
end)

CreateThread(function()
    while true do
        local waitMs = 500
        local settings = state.settings
        if settings and (settings.disableAircraftTurbulence == true or settings.disablePlaneTurbulence == true or settings.disableHelicopterTurbulence == true) then
            local ped = PlayerPedId()
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 then
                local model = GetEntityModel(vehicle)
                if IsThisModelAPlane(model) and (settings.disableAircraftTurbulence == true or settings.disablePlaneTurbulence == true) then
                    SetPlaneTurbulenceMultiplier(vehicle, 0.0)
                    waitMs = 0
                elseif IsThisModelAHeli(model) and (settings.disableAircraftTurbulence == true or settings.disableHelicopterTurbulence == true) and SetHeliTurbulenceScalar then
                    SetHeliTurbulenceScalar(vehicle, 0.0)
                    waitMs = 0
                end
            end
        end
        Wait(waitMs)
    end
end)

local function getDrivenCustomizationVehicle()
    local ped = getPed()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil, 'no_vehicle' end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return nil, 'driver_required' end
    if IsEntityDead(vehicle) then return nil, 'vehicle_destroyed' end
    return vehicle
end

local function customizationInteger(value, minimum, maximum)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge
        or number ~= math.floor(number) or number < minimum or number > maximum then
        return nil
    end
    return number
end

local function customizationNumber(value, minimum, maximum)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge
        or number < minimum or number > maximum then
        return nil
    end
    return number
end

local function customizationRgb(value)
    if type(value) ~= 'table' then return nil end
    local red = customizationInteger(value[1], 0, 255)
    local green = customizationInteger(value[2], 0, 255)
    local blue = customizationInteger(value[3], 0, 255)
    if red == nil or green == nil or blue == nil then return nil end
    return { red, green, blue }
end

local function importedExtraLabelsForVehicle(modelHash)
    local labels = {}
    local config = type(Admin.getVmenuImportedConfig) == 'function' and Admin.getVmenuImportedConfig() or {}
    local extras = type(config.extras) == 'table' and config.extras or {}
    local targetHash = toUnsignedModelHash(modelHash)
    local visited = 0

    for rawModel, rawLabels in pairs(extras) do
        visited = visited + 1
        if visited > 4096 then break end
        local candidateHash = type(rawModel) == 'string' and toUnsignedModelHash(joaat(rawModel))
            or toUnsignedModelHash(rawModel)
        if candidateHash == targetHash and type(rawLabels) == 'table' then
            for rawId, rawLabel in pairs(rawLabels) do
                local id = customizationInteger(rawId, 0, 20)
                if id ~= nil and type(rawLabel) == 'string' then
                    local label = trimString(rawLabel)
                    if label then labels[id] = label:sub(1, 80) end
                end
            end
            break
        end
    end
    return labels
end

Admin.getVehicleCustomization = function()
    local vehicle, errorReason = getDrivenCustomizationVehicle()
    if not vehicle then return nil, errorReason end

    SetVehicleModKit(vehicle, 0)

    local neonR, neonG, neonB = GetVehicleNeonLightsColour(vehicle)
    local smokeR, smokeG, smokeB = GetVehicleTyreSmokeColor(vehicle)
    local primaryPaintType, primaryPaintColor, primaryPearlescent = GetVehicleModColor_1(vehicle)
    local secondaryPaintType, secondaryPaintColor = GetVehicleModColor_2(vehicle)
    local primaryCustom = GetIsVehiclePrimaryColourCustom(vehicle) == true
    local secondaryCustom = GetIsVehicleSecondaryColourCustom(vehicle) == true
    local primaryCustomColor = { 0, 0, 0 }
    local secondaryCustomColor = { 0, 0, 0 }
    if primaryCustom then
        local red, green, blue = GetVehicleCustomPrimaryColour(vehicle)
        primaryCustomColor = { red, green, blue }
    end
    if secondaryCustom then
        local red, green, blue = GetVehicleCustomSecondaryColour(vehicle)
        secondaryCustomColor = { red, green, blue }
    end

    local data = {
        vehicle = {
            model = GetEntityModel(vehicle),
            label = getVehicleLabel(GetEntityModel(vehicle)),
            plate = GetVehicleNumberPlateText(vehicle),
        },
        mods = {},
        colors = {},
        paintFinish = {
            primary = customizationInteger(primaryPaintType, 0, 5) or 0,
            secondary = customizationInteger(secondaryPaintType, 0, 5) or 0,
        },
        paintColor = {
            primary = customizationInteger(primaryPaintColor, 0, 255) or 0,
            secondary = customizationInteger(secondaryPaintColor, 0, 255) or 0,
            pearlescent = customizationInteger(primaryPearlescent, 0, 255) or 0,
        },
        customPrimary = { enabled = primaryCustom, value = primaryCustomColor },
        customSecondary = { enabled = secondaryCustom, value = secondaryCustomColor },
        extras = {},
        liveries = {},
        livery = GetVehicleLivery(vehicle),
        plate = GetVehicleNumberPlateTextIndex(vehicle),
        windowTint = GetVehicleWindowTint(vehicle),
        wheelType = GetVehicleWheelType(vehicle),
        xenonColor = GetVehicleXenonLightsColour(vehicle),
        enveffScale = GetVehicleEnveffScale(vehicle),
        neonFront = IsVehicleNeonLightEnabled(vehicle, 0),
        neonBack = IsVehicleNeonLightEnabled(vehicle, 1),
        neonLeft = IsVehicleNeonLightEnabled(vehicle, 2),
        neonRight = IsVehicleNeonLightEnabled(vehicle, 3),
        neonColor = { neonR, neonG, neonB },
        tyreSmokeColor = { smokeR, smokeG, smokeB },
    }

    for i = 0, 49 do
        local max = math.max(0, math.min(GetNumVehicleMods(vehicle, i) or 0, 4096))
        local current = GetVehicleMod(vehicle, i)
        local names = {}

        for m = 0, max - 1 do
            local label = GetModTextLabel(vehicle, i, m)
            local name = label and GetLabelText(label)
            if name == 'NULL' or name == '' then name = nil end
            names[tostring(m)] = name
        end

        data.mods[tostring(i)] = {
            current = current,
            max = max,
            names = names,
            isToggle = i == 18 or i == 20 or i == 22,
        }
    end

    data.mods['18'] = { isToggle = true, enabled = IsToggleModOn(vehicle, 18) }
    data.mods['20'] = { isToggle = true, enabled = IsToggleModOn(vehicle, 20) }
    data.mods['22'] = { isToggle = true, enabled = IsToggleModOn(vehicle, 22) }

    local primary, secondary = GetVehicleColours(vehicle)
    local pearlescent, wheelColor = GetVehicleExtraColours(vehicle)
    data.colors = {
        primary = primary,
        secondary = secondary,
        pearlescent = pearlescent,
        wheel = wheelColor,
        dashboard = GetVehicleDashboardColour(vehicle),
        trim = GetVehicleInteriorColour(vehicle),
    }

    local extraLabels = importedExtraLabelsForVehicle(GetEntityModel(vehicle))
    for extraId = 0, 20 do
        if DoesExtraExist(vehicle, extraId) then
            data.extras[#data.extras + 1] = {
                id = extraId,
                label = extraLabels[extraId] or ('Extra #%d'):format(extraId),
                enabled = IsVehicleExtraTurnedOn(vehicle, extraId) == true,
            }
        end
    end

    local liveryCount = customizationInteger(GetVehicleLiveryCount(vehicle), 0, 255) or 0
    for index = 0, liveryCount - 1 do
        local labelKey = GetLiveryName(vehicle, index)
        local label = type(labelKey) == 'string' and labelKey ~= '' and GetLabelText(labelKey) or nil
        if label == 'NULL' or label == '' then label = nil end
        data.liveries[#data.liveries + 1] = { value = index, label = label or ('Livery #%d'):format(index + 1) }
    end

    return data
end

Admin.setVehicleCustomization = function(data)
    if type(data) ~= 'table' or type(data.type) ~= 'string' then return false, 'invalid_payload' end
    local vehicle, errorReason = getDrivenCustomizationVehicle()
    if not vehicle then return false, errorReason end

    SetVehicleModKit(vehicle, 0)

    if data.type == 'mod' then
        local id = customizationInteger(data.id, 0, 49)
        if id == nil then return false, 'invalid_mod' end
        if data.isToggle == true then
            if (id ~= 18 and id ~= 20 and id ~= 22) or type(data.enabled) ~= 'boolean' then
                return false, 'invalid_mod_toggle'
            end
            ToggleVehicleMod(vehicle, id, data.enabled)
        else
            local value = customizationInteger(data.value, -1, 4096)
            local count = GetNumVehicleMods(vehicle, id) or 0
            if value == nil or count <= 0 or value >= count then return false, 'invalid_mod_value' end
            SetVehicleMod(vehicle, id, value, GetVehicleModVariation(vehicle, id) == true)
        end
    elseif data.type == 'color' then
        local value = customizationInteger(data.value, 0, 255)
        if value == nil then return false, 'invalid_color' end
        local primary, secondary = GetVehicleColours(vehicle)
        local pearlescent, wheelColor = GetVehicleExtraColours(vehicle)
        if data.id == 'primary' and (value <= 160 or (value >= 223 and value <= 238)) then
            ClearVehicleCustomPrimaryColour(vehicle)
            SetVehicleColours(vehicle, value, secondary)
        elseif data.id == 'secondary' and (value <= 160 or (value >= 223 and value <= 238)) then
            ClearVehicleCustomSecondaryColour(vehicle)
            SetVehicleColours(vehicle, primary, value)
        elseif data.id == 'pearlescent' and value <= 160 then
            SetVehicleExtraColours(vehicle, value, wheelColor)
        elseif data.id == 'wheel' and value <= 160 then
            SetVehicleExtraColours(vehicle, pearlescent, value)
        elseif data.id == 'dashboard' and value <= 160 then
            SetVehicleDashboardColour(vehicle, value)
        elseif data.id == 'trim' and value <= 160 then
            SetVehicleInteriorColour(vehicle, value)
        else
            return false, 'invalid_color'
        end
    elseif data.type == 'paintFinish' then
        local value = customizationInteger(data.value, 0, 5)
        if value == nil then return false, 'invalid_paint_finish' end
        local pearlescent, wheelColor = GetVehicleExtraColours(vehicle)
        if data.id == 'primary' then
            SetVehicleModColor_1(vehicle, value, 0, 0)
        elseif data.id == 'secondary' then
            SetVehicleModColor_2(vehicle, value, 0)
        else
            return false, 'invalid_paint_finish'
        end
        SetVehicleExtraColours(vehicle, pearlescent, wheelColor)
    elseif data.type == 'customColor' then
        if (data.id ~= 'primary' and data.id ~= 'secondary') or type(data.enabled) ~= 'boolean' then
            return false, 'invalid_custom_color'
        end
        if not data.enabled then
            if data.id == 'primary' then ClearVehicleCustomPrimaryColour(vehicle) else ClearVehicleCustomSecondaryColour(vehicle) end
        else
            local color = customizationRgb(data.value)
            if not color then return false, 'invalid_custom_color' end
            if data.id == 'primary' then
                SetVehicleCustomPrimaryColour(vehicle, color[1], color[2], color[3])
            else
                SetVehicleCustomSecondaryColour(vehicle, color[1], color[2], color[3])
            end
        end
    elseif data.type == 'plate' then
        local value = customizationInteger(data.value, 0, 12)
        if value == nil then return false, 'invalid_plate' end
        SetVehicleNumberPlateTextIndex(vehicle, value)
    elseif data.type == 'window' then
        local value = customizationInteger(data.value, 0, 6)
        if value == nil then return false, 'invalid_window_tint' end
        SetVehicleWindowTint(vehicle, value)
    elseif data.type == 'wheelType' then
        local value = customizationInteger(data.value, 0, 20)
        if value == nil then return false, 'invalid_wheel_type' end
        SetVehicleWheelType(vehicle, value)
    elseif data.type == 'xenonColor' then
        local value = customizationInteger(data.value, -1, 255)
        if value == nil or (value > 12 and value ~= 255) then return false, 'invalid_xenon_color' end
        SetVehicleXenonLightsColour(vehicle, value)
    elseif data.type == 'neon' then
        if type(data.value) ~= 'boolean' then return false, 'invalid_neon' end
        local neonIds = { front = 0, back = 1, left = 2, right = 3 }
        if data.id == 'all' then
            for index = 0, 3 do SetVehicleNeonLightEnabled(vehicle, index, data.value) end
        elseif neonIds[data.id] ~= nil then
            SetVehicleNeonLightEnabled(vehicle, neonIds[data.id], data.value)
        else
            return false, 'invalid_neon'
        end
    elseif data.type == 'neonColor' or data.type == 'tyreSmokeColor' then
        local color = customizationRgb(data.value)
        if not color then return false, 'invalid_rgb' end
        if data.type == 'neonColor' then
            SetVehicleNeonLightsColour(vehicle, color[1], color[2], color[3])
        else
            SetVehicleTyreSmokeColor(vehicle, color[1], color[2], color[3])
        end
    elseif data.type == 'livery' then
        local value = customizationInteger(data.value, -1, 255)
        local count = GetVehicleLiveryCount(vehicle) or -1
        if value == nil or count <= 0 or value >= count then return false, 'invalid_livery' end
        SetVehicleLivery(vehicle, value)
    elseif data.type == 'extra' then
        local id = customizationInteger(data.id, 0, 20)
        if id == nil or type(data.enabled) ~= 'boolean' or not DoesExtraExist(vehicle, id) then
            return false, 'invalid_extra'
        end
        SetVehicleExtra(vehicle, id, data.enabled and 0 or 1)
    elseif data.type == 'enveff' then
        local value = customizationNumber(data.value, 0.0, 1.0)
        if value == nil then return false, 'invalid_enveff' end
        SetVehicleEnveffScale(vehicle, value)
    else
        return false, 'invalid_customization_type'
    end

    return true
end

-- ============================================================================
-- GARAGE VEHICLE SPAWN (QBX)
-- ============================================================================

RegisterNetEvent('cortex-admin:client:spawnGarageVehicle', function(data)
    if not data or not data.model then
        notify('error', 'Invalid vehicle data')
        return
    end

    local modelAuthorized, _, modelToken = authorizeModel('vehicle', data.model, 'garage.spawnVehicle')
    if not modelAuthorized then return end

    local modelHash = type(data.model) == 'number' and data.model or joaat(data.model)

    if not exports['cortex-lib']:requestModel(modelHash, 5000) then
        notify('error', 'Failed to load vehicle model: ' .. tostring(data.model))
        return
    end

    local ped = getPed()

    deleteOccupiedVehicleIfReplaceSpawnEnabled()

    local coords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local vehicle = CreateVehicle(modelHash, coords.x, coords.y, coords.z, heading, true, false)

    if vehicle == 0 then
        notify('error', 'Failed to spawn vehicle')
        SetModelAsNoLongerNeeded(modelHash)
        return
    end

    registerCortexSpawnedVehicle(vehicle)
    seatPedInSpawnedVehicle(ped, vehicle)
    SetModelAsNoLongerNeeded(modelHash)

    if data.props and type(data.props) == 'table' then
        -- Try to use ox_lib setVehicleProperties if available
        local oxLibOk = pcall(function()
            lib.setVehicleProperties(vehicle, data.props)
        end)

        if not oxLibOk then
            -- Fallback: apply basic properties manually
            if data.props.plate then
                SetVehicleNumberPlateText(vehicle, data.props.plate)
            end
            applyVehicleData(vehicle, data.props)
        end
    elseif data.plate then
        SetVehicleNumberPlateText(vehicle, data.plate)
    end

    Wait(0)
    Admin.giveKeysForVehicle(vehicle, true, modelToken, 'garage.spawnVehicle')
    notify('success', ('Spawned: %s'):format(data.label or data.model))
end)

RegisterCommand('fix', function()
    if not state.allowed['vehicle.repair'] then
        notify('error', 'You do not have permission to fix vehicles.')
        return
    end
    actionRepairVehicle()
end, false)

RegisterCommand('clean', function()
    if not state.allowed['vehicle.clean'] then
        notify('error', 'You do not have permission to clean vehicles.')
        return
    end
    actionCleanVehicle()
end, false)

AddStateBagChangeHandler('cortex-admin_pv_ex', nil, function(bagName, _, value)
    if type(value) ~= 'table' then
        return
    end
    local entity = GetEntityFromStateBagName(bagName)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return
    end
    applyVehicleExtraStates(entity, value)
end)
