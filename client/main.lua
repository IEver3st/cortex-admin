local PlayerPedId = PlayerPedId
local PlayerId = PlayerId
local GetPlayerServerId = GetPlayerServerId
local GetPlayerName = GetPlayerName
local GetActivePlayers = GetActivePlayers
local GetEntityCoords = GetEntityCoords
local GetEntityHeading = GetEntityHeading
local IsEntityDead = IsEntityDead
local GetClockHours = GetClockHours
local GetClockMinutes = GetClockMinutes
local IsNextWeatherType = IsNextWeatherType
local GetDisplayNameFromVehicleModel = GetDisplayNameFromVehicleModel
local GetLabelText = GetLabelText
local GetCurrentResourceName = GetCurrentResourceName
local SetEntityCoordsNoOffset = SetEntityCoordsNoOffset
local SendNUIMessage = SendNUIMessage
local SetNuiFocus = SetNuiFocus
local SetNuiFocusKeepInput = SetNuiFocusKeepInput
local DisableAllControlActions = DisableAllControlActions
local EnableControlAction = EnableControlAction
local HudWeaponWheelIgnoreSelection = HudWeaponWheelIgnoreSelection
local BlockWeaponWheelThisFrame = BlockWeaponWheelThisFrame
local SetPauseMenuActive = SetPauseMenuActive
local InvalidateIdleCam = InvalidateIdleCam
local InvalidateVehicleIdleCam = InvalidateVehicleIdleCam
local NetworkOverrideClockTime = NetworkOverrideClockTime
local SetWeatherTypeNowPersist = SetWeatherTypeNowPersist
local SetWeatherTypeNow = SetWeatherTypeNow
local SetOverrideWeather = SetOverrideWeather
local SetBlackout = SetBlackout
local PauseClock = PauseClock
local FreezeEntityPosition = FreezeEntityPosition
local PlaySoundFrontend = PlaySoundFrontend
local GetVehiclePedIsIn = GetVehiclePedIsIn
local TaskLeaveVehicle = TaskLeaveVehicle
local SetEntityAsMissionEntity = SetEntityAsMissionEntity
local DeleteEntity = DeleteEntity
local DoesEntityExist = DoesEntityExist
local GetGamePool = GetGamePool
local GetGameTimer = GetGameTimer
local Wait = Wait
local CreateThread = CreateThread
local RegisterCommand = RegisterCommand
local RegisterKeyMapping = RegisterKeyMapping
local RegisterNetEvent = RegisterNetEvent
local TriggerServerEvent = TriggerServerEvent
local GetResourceKvpString = GetResourceKvpString
local SetResourceKvp = SetResourceKvp
local GetResourceState = GetResourceState

-- Cached math/table functions
local pairs = pairs
local ipairs = ipairs
local type = type
local pcall = pcall
local tonumber = tonumber
local tableSort = table.sort
local tableConcat = table.concat
local tableInsert = table.insert

-- ============================================================================
-- MODULE STATE
-- ============================================================================

EsAdmin = EsAdmin or {}

local Actions = EsAdminActions

local state = {
    open = false,
    favorites = {},
    settings = {},
    toggles = {},
    allowed = {},
    playerList = {},
    wardrobeShareRequests = {},
    lastCoords = nil,
    coordHudDirty = false,
    speedHudDirty = false,
}

local worldState = {
    freezeTime = false,
}

local currentResourceName = GetCurrentResourceName()
local trackedWeatherTypes = {
    'EXTRASUNNY',
    'CLEAR',
    'CLOUDS',
    'SMOG',
    'FOGGY',
    'OVERCAST',
    'RAIN',
    'THUNDER',
    'CLEARING',
    'NEUTRAL',
    'SNOW',
    'BLIZZARD',
    'SNOWLIGHT',
    'XMAS',
    'HALLOWEEN',
}

local enabledControls = {
    71, 72, 59, 60, 76, 77, 79, 80, 63, 64, 75,
    -- Keep GTA's text-chat controls usable while the menu owns gameplay input.
    245, 246, 247, 248, 249,
    30, 31, 32, 33, 34, 35, 21, 22, 36
}
local enabledControlsCount = #enabledControls
local menuControlThreadActive = false
local menuFocusApplied = false
local menuIdleCamTick = 0
local menuFocusTick = 0
local menuTypingLock = false
local chatResourceName = 'cortex-chat'

EsAdmin.state = state

-- ============================================================================
-- UTILITY FUNCTIONS (Use cortex-lib where possible)
-- ============================================================================

local function notify(notifyType, message)
    local position = 'top-right'
    if state.settings.menuPosition == 'right' then
        position = 'top-left'
    end
    -- Use exports['cortex-lib']:notify from cortex-lib
    exports['cortex-lib']:notify({ type = notifyType or 'info', description = message, position = position })
end

EsAdmin.notify = notify

local function getCurrentWeather()
    for i = 1, #trackedWeatherTypes do
        local weatherType = trackedWeatherTypes[i]
        if IsNextWeatherType(weatherType) then
            return weatherType
        end
    end

    return worldState.weather or 'UNKNOWN'
end

local function getLiveWorldSnapshot()
    return {
        gameHour = GetClockHours(),
        gameMinute = GetClockMinutes(),
        currentWeather = getCurrentWeather(),
    }
end

-- Direct native KVP functions for reliability
local function loadKvp(key, fallback)
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

local function saveKvp(key, data)
    if not key or key == '' then
        print('[cortex-admin] ERROR: saveKvp called with empty key')
        return false
    end
    
    local ok, encoded = pcall(json.encode, data)
    if not ok then
        print('[cortex-admin] ERROR: Failed to encode settings for key: ' .. key)
        return false
    end
    
    SetResourceKvp(key, encoded)
    return true
end

local MP_PED_KEY_PREFIX = 'mp_ped_'
local MP_PED_SOURCE_ES_ADMIN = 'cortex-admin'
local MP_PED_SOURCE_VMENU = 'vmenu'
local LAST_PED_NAME_KEY = 'cortex-admin_last_ped'
local LAST_PED_SOURCE_KEY = 'cortex-admin_last_ped_source'
local LAST_PED_SOURCE_REF_KEY = 'cortex-admin_last_ped_source_key'
local DEFAULT_PED_SOURCE_KEY = 'cortex-admin_default_ped_source'
local DEFAULT_PED_SOURCE_REF_KEY = 'cortex-admin_default_ped_source_key'

local function cloneJsonTable(data)
    if type(data) ~= 'table' then
        return nil
    end

    local ok, encoded = pcall(json.encode, data)
    if not ok or type(encoded) ~= 'string' or encoded == '' then
        return nil
    end

    ok, data = pcall(json.decode, encoded)
    if ok and type(data) == 'table' then
        return data
    end

    return nil
end

local function normalizeSavedPedKey(keyOrName)
    if type(keyOrName) ~= 'string' or keyOrName == '' then
        return nil, nil
    end

    if keyOrName:sub(1, #MP_PED_KEY_PREFIX) == MP_PED_KEY_PREFIX then
        return keyOrName, keyOrName:sub(#MP_PED_KEY_PREFIX + 1)
    end

    return MP_PED_KEY_PREFIX .. keyOrName, keyOrName
end

local function normalizeMpPedData(data, sourceKey)
    if type(EsAdmin.normalizeMpPedData) == 'function' then
        local normalized = EsAdmin.normalizeMpPedData(data, sourceKey)
        if type(normalized) == 'table' then
            return normalized
        end
    end

    local normalized = cloneJsonTable(data) or {}
    if normalized.PedTatttoos and not normalized.PedTattoos then
        normalized.PedTattoos = normalized.PedTatttoos
    elseif normalized.PedTattoos and not normalized.PedTatttoos then
        normalized.PedTatttoos = normalized.PedTattoos
    end

    if type(sourceKey) == 'string' and sourceKey ~= '' then
        normalized.SaveName = sourceKey
    end

    return normalized
end

local function callVmenuBridge(method, ...)
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

local function getVmenuSavedPedByKey(sourceKey)
    local ok, rawPeds = callVmenuBridge('GetSavedMpCharactersForEsAdmin')
    if not ok or type(rawPeds) ~= 'table' then
        return nil
    end

    for i = 1, #rawPeds do
        local item = rawPeds[i]
        if item and item.key == sourceKey and type(item.data) == 'table' then
            return normalizeMpPedData(item.data, sourceKey)
        end
    end

    return nil
end

local function applyDefaultSettings(settings)
    -- Merge defaults with saved settings
    local merged = {}
    for key, value in pairs(Config.DefaultSettings) do
        merged[key] = value
    end
    if settings then
        for key, value in pairs(settings) do
            merged[key] = value
        end
    end
    return merged
end

-- ============================================================================
-- PLAYER LIST (Optimized with indexed loops)
-- ============================================================================

local function refreshPlayerList()
    local players = {}
    local activePlayers = GetActivePlayers()
    local myPlayerId = PlayerId()
    local count = 0
    
    for i = 1, #activePlayers do
        local player = activePlayers[i]
        local serverId = GetPlayerServerId(player)
        local name = GetPlayerName(player) or ('Player %s'):format(serverId)
        count = count + 1
        players[count] = {
            id = serverId,
            name = name,
            isSelf = player == myPlayerId,
        }
    end

    tableSort(players, function(a, b)
        return a.id < b.id
    end)

    state.playerList = players
end

-- ============================================================================
-- CACHED DATA (Avoid rebuilding every update)
-- ============================================================================

local cachedData = {
    personalVehicles = nil,
    addonVehicles = {},
    playerName = nil,
    actions = nil,
    tabs = nil,
    frameworkInfo = nil,
}

local runtimeUiCache = {
    gameHour = nil,
    gameMinute = nil,
    currentWeather = nil,
    playerListSignature = nil,
}

local menuDataCache = {
    permissionsRequestedAt = 0,
    addonVehiclesRequestedAt = 0,
    addonVehiclesLoaded = false,
}

local PERMISSIONS_REFRESH_MS = 10000
local ADDON_VEHICLES_REFRESH_MS = 300000

local function buildPersonalVehiclesSummary(vehicles)
    local summary = {}
    for i = 1, #vehicles do
        local entry = vehicles[i]
        summary[#summary + 1] = {
            id = entry.id,
            name = entry.name,
            model = entry.model,
            modelLabel = entry.modelLabel,
            category = entry.category,
        }
    end

    tableSort(summary, function(a, b)
        local catA = (a.category or ''):lower()
        local catB = (b.category or ''):lower()
        if catA ~= catB then
            return catA < catB
        end
        local nameA = (a.name or ''):lower()
        local nameB = (b.name or ''):lower()
        return nameA < nameB
    end)

    return summary
end

local function buildPlayerListSignature(players)
    if type(players) ~= 'table' or #players == 0 then
        return ''
    end

    local signature = {}

    for i = 1, #players do
        local player = players[i]
        signature[i] = ('%s:%s:%s'):format(
            tostring(player.id or ''),
            tostring(player.name or ''),
            player.isSelf and '1' or '0'
        )
    end

    return tableConcat(signature, '|')
end

local function trimString(value)
    if type(value) ~= 'string' then
        return ''
    end
    return (value:gsub('^%s+', ''):gsub('%s+$', ''))
end

local function prettifyModelName(model)
    local normalized = trimString(model):gsub('_', ' ')
    return normalized:gsub('(%a)([%w]*)', function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

local function resolveLabelText(labelKey)
    local key = trimString(labelKey)
    if key == '' then
        return nil
    end

    local text = GetLabelText(key)
    if text and text ~= '' and text ~= 'NULL' then
        return text
    end

    return nil
end

local function resolveAddonVehicleName(model, gameName, fallbackName)
    local gameLabel = resolveLabelText(gameName)
    if gameLabel then
        return gameLabel
    end

    local normalizedModel = trimString(model):lower()
    if normalizedModel ~= '' then
        local displayKey = trimString(GetDisplayNameFromVehicleModel(joaat(normalizedModel)))
        if displayKey ~= '' and displayKey ~= 'NULL' and displayKey ~= 'CARNOTFOUND' then
            local displayLabel = resolveLabelText(displayKey)
            if displayLabel then
                return displayLabel
            end
        end
    end

    local fallback = trimString(fallbackName)
    if fallback ~= '' and fallback ~= trimString(gameName) then
        return fallback
    end

    return prettifyModelName(normalizedModel)
end

local function normalizeAddonVehicles(list)
    if type(list) ~= 'table' then
        return {}
    end

    local normalized = {}
    local seenModels = {}
    for i = 1, #list do
        local entry = list[i]
        if type(entry) == 'table' then
            local model = trimString(entry.model):lower()
            if model ~= '' and not seenModels[model] then
                seenModels[model] = true

                local gameName = trimString(entry.gameName)
                local makeName = trimString(entry.makeName)

                normalized[#normalized + 1] = {
                    model = model,
                    name = resolveAddonVehicleName(model, gameName, entry.name),
                    gameName = gameName ~= '' and gameName or nil,
                    makeName = makeName ~= '' and makeName or nil,
                    resource = entry.resource,
                    metaPath = entry.metaPath,
                    sourceType = entry.sourceType,
                    ownerResource = entry.ownerResource,
                    dataResource = entry.dataResource,
                }
            end
        end
    end

    tableSort(normalized, function(a, b)
        local nameA = (a.name or a.model or ''):lower()
        local nameB = (b.name or b.model or ''):lower()
        if nameA ~= nameB then
            return nameA < nameB
        end
        return (a.model or ''):lower() < (b.model or ''):lower()
    end)

    return normalized
end

local function refreshPersonalVehiclesCache()
    local loader = EsAdmin.loadPersonalVehicles
    if type(loader) == 'function' then
        local merged = loader()
        if merged and type(merged) == 'table' and type(merged.vehicles) == 'table' then
            cachedData.personalVehicles = buildPersonalVehiclesSummary(merged.vehicles)
            return
        end
    end

    local data = loadKvp('cortex-admin_personal_vehicles_v2', nil)
    if data and type(data) == 'table' and data.version == 2 and type(data.vehicles) == 'table' then
        cachedData.personalVehicles = buildPersonalVehiclesSummary(data.vehicles)
        return
    end

    local legacy = loadKvp('cortex-admin_personal_vehicles', {}) or {}
    local summary = {}
    for name, props in pairs(legacy) do
        if type(props) == 'table' then
            summary[#summary + 1] = {
                id = tostring(name),
                name = name,
                model = props.model,
                modelLabel = props.modelLabel,
                category = props.category or 'other',
            }
        end
    end

    cachedData.personalVehicles = buildPersonalVehiclesSummary(summary)
end

EsAdmin.refreshPersonalVehiclesCache = refreshPersonalVehiclesCache

EsAdmin.getPersonalVehiclesCache = function()
    return cachedData.personalVehicles
end

-- ============================================================================
-- UI STATE BUILDING (Optimized)
-- ============================================================================

local function buildUiState()
    -- Cache player name (rarely changes)
    if not cachedData.playerName then
        cachedData.playerName = GetPlayerName(PlayerId()) or 'Admin'
    end
    
    -- Cache actions/tabs (static)
    if not cachedData.actions then
        cachedData.actions = Actions.actions
        cachedData.tabs = Actions.tabs
        cachedData.frameworkInfo = EsAdminBridge.getFrameworkInfo()
    end
    
    -- Cache personal vehicles (only refresh on demand)
    if not cachedData.personalVehicles then
        refreshPersonalVehiclesCache()
    end

    local pvModel = EsAdmin.getPreviewVehicleModel and EsAdmin.getPreviewVehicleModel() or nil
    local pvShared = EsAdmin.getPreviewShared and EsAdmin.getPreviewShared() == true

    return {
        open = state.open,
        actions = cachedData.actions,
        tabs = cachedData.tabs,
        favorites = state.favorites,
        settings = state.settings,
        toggles = state.toggles,
        allowed = state.allowed,
        players = state.playerList,
        wardrobeShareRequests = state.wardrobeShareRequests,
        playerName = cachedData.playerName,
        gameHour = GetClockHours(),
        gameMinute = GetClockMinutes(),
        currentWeather = getCurrentWeather(),
        personalVehicles = cachedData.personalVehicles,
        addonVehicles = cachedData.addonVehicles or {},
        frameworkInfo = cachedData.frameworkInfo,
        vehiclePreview = {
            active = type(pvModel) == 'string' and pvModel ~= '',
            model = pvModel,
            shared = pvShared,
        },
    }
end

local function sendUiState()
    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = buildUiState()
    })
    if state.toggles['dev.showSpeed'] == true then
        SendNUIMessage({
            action = 'cortex-admin:setSpeedHud',
            data = {
                visible = true,
                position = state.settings.speedHudPosition or 'top-left',
                units = state.settings.speedHudUnits or 'mph',
            }
        })
    end
end

local function sendRuntimeUiState(includePlayers, force)
    local snapshot = getLiveWorldSnapshot()
    local data = {}
    local changed = force == true

    if force or runtimeUiCache.gameHour ~= snapshot.gameHour then
        runtimeUiCache.gameHour = snapshot.gameHour
        data.gameHour = snapshot.gameHour
        changed = true
    end

    if force or runtimeUiCache.gameMinute ~= snapshot.gameMinute then
        runtimeUiCache.gameMinute = snapshot.gameMinute
        data.gameMinute = snapshot.gameMinute
        changed = true
    end

    if force or runtimeUiCache.currentWeather ~= snapshot.currentWeather then
        runtimeUiCache.currentWeather = snapshot.currentWeather
        data.currentWeather = snapshot.currentWeather
        changed = true
    end

    if includePlayers then
        local signature = buildPlayerListSignature(state.playerList)
        if force or runtimeUiCache.playerListSignature ~= signature then
            runtimeUiCache.playerListSignature = signature
            data.players = state.playerList
            changed = true
        end
    end

    if not changed then
        return false
    end

    SendNUIMessage({
        action = 'cortex-admin:updateRuntimeState',
        data = data
    })

    return true
end

EsAdmin.sendUiState = sendUiState

local function requestMenuPermissions(force)
    local now = GetGameTimer()
    if force or now - menuDataCache.permissionsRequestedAt > PERMISSIONS_REFRESH_MS then
        menuDataCache.permissionsRequestedAt = now
        TriggerServerEvent('cortex-admin:server:requestPermissions')
    end
end

local function requestAddonVehiclesIfNeeded(force)
    local now = GetGameTimer()
    local hasAddonVehicles = type(cachedData.addonVehicles) == 'table' and #cachedData.addonVehicles > 0
    if force or not menuDataCache.addonVehiclesLoaded or not hasAddonVehicles or now - menuDataCache.addonVehiclesRequestedAt > ADDON_VEHICLES_REFRESH_MS then
        menuDataCache.addonVehiclesRequestedAt = now
        TriggerServerEvent('cortex-admin:server:requestAddonVehicles')
        return true
    end
    return false
end

EsAdmin.requestAddonVehiclesIfNeeded = requestAddonVehiclesIfNeeded

-- ============================================================================
-- MENU OPEN/CLOSE
-- ============================================================================

local function isChatOpen()
    if GetResourceState(chatResourceName) ~= 'started' then
        return false
    end

    -- cortex-chat is optional; treat a missing/outdated export as closed so the
    -- admin menu keeps its normal focus behavior on servers without that chat.
    local ok, open = pcall(function()
        return exports[chatResourceName]:isOpen()
    end)

    return ok and open == true
end

local function startMenuControlThread()
    if menuControlThreadActive then return end
    menuControlThreadActive = true

    CreateThread(function()
        local chatOpen = false
        local wasChatOpen = false
        local chatStateTick = 0

        while state.open do
            DisableAllControlActions(0)
            for i = 1, enabledControlsCount do
                EnableControlAction(0, enabledControls[i], true)
            end

            HudWeaponWheelIgnoreSelection()
            BlockWeaponWheelThisFrame()
            SetPauseMenuActive(false)

            local now = GetGameTimer()
            if now - chatStateTick >= 100 then
                chatOpen = isChatOpen()
                chatStateTick = now
            end

            if chatOpen then
                -- cortex-chat owns NUI focus while its input is open.
                menuFocusTick = now
            elseif wasChatOpen then
                -- Chat just released focus; hand it back to the admin menu now.
                SetNuiFocus(true, true)
                SetNuiFocusKeepInput(not menuTypingLock)
                menuFocusApplied = true
                menuFocusTick = now
            elseif now - menuFocusTick >= 500 then
                SetNuiFocus(true, true)
                SetNuiFocusKeepInput(not menuTypingLock)
                menuFocusApplied = true
                menuFocusTick = now
            end

            wasChatOpen = chatOpen

            if now - menuIdleCamTick >= 1000 then
                InvalidateIdleCam()
                InvalidateVehicleIdleCam()
                menuIdleCamTick = now
            end

            Wait(0)
        end

        menuControlThreadActive = false
    end)
end

local function applyMenuFocus()
    if menuFocusApplied then return end
    if isChatOpen() then return end
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(not menuTypingLock)
    menuFocusApplied = true
end

local function clearMenuFocus()
    if not menuFocusApplied then return end
    menuTypingLock = false
    if not isChatOpen() then
        SetNuiFocusKeepInput(false)
        SetNuiFocus(false, false)
    end
    menuFocusApplied = false
end

function EsAdmin.setTypingLock(enabled)
    local shouldLock = enabled == true
    if menuTypingLock == shouldLock then
        return
    end

    menuTypingLock = shouldLock

    if state.open then
        SetNuiFocus(true, true)
        SetNuiFocusKeepInput(not menuTypingLock)
        menuFocusTick = GetGameTimer()
    end
end

local function setOpen(open)
    if state.open == open then return end
    state.open = open
    TriggerServerEvent('cortex-admin:server:setUiPresence', { open = open == true })

    if open then
        menuTypingLock = false
        applyMenuFocus()
        menuIdleCamTick = 0
        menuFocusTick = 0
        refreshPlayerList()
        sendUiState()
        SendNUIMessage({ action = 'cortex-admin:open' })
        startMenuControlThread()
        requestMenuPermissions(false)
        requestAddonVehiclesIfNeeded(false)
        local m = EsAdmin.getPreviewVehicleModel and EsAdmin.getPreviewVehicleModel() or nil
        if type(m) == 'string' and m ~= '' then
            SendNUIMessage({
                action = 'cortex-admin:vehiclePreviewResume',
                data = {
                    model = m,
                    shared = EsAdmin.getPreviewShared and EsAdmin.getPreviewShared() == true,
                    resumeOnly = true,
                }
            })
        end
    else
        menuTypingLock = false
        SendNUIMessage({ action = 'cortex-admin:close' })
        clearMenuFocus()
    end
end

EsAdmin.setOpen = setOpen

local function openVehiclePreviewPage(model)
    if not state.open then
        setOpen(true)
    end
    requestAddonVehiclesIfNeeded(false)

    SendNUIMessage({
        action = 'cortex-admin:vehiclePreviewPage',
        data = {
            model = type(model) == 'string' and model ~= '' and model or nil,
        }
    })
end

EsAdmin.openVehiclePreviewPage = openVehiclePreviewPage

local function toggleMenu()
    local opening = not state.open
    setOpen(opening)
end

RegisterCommand(Config.Command, function()
    toggleMenu()
end, false)

RegisterKeyMapping(Config.Command, 'Open admin menu', 'keyboard', Config.Keybind)

local COMMAND_PERMISSION_WAIT_MS = 750

local function hasCommandPermission(actionId, label)
    if state.allowed[actionId] == true then
        return true
    end

    if state.allowed[actionId] == nil then
        requestMenuPermissions(true)
        local deadline = GetGameTimer() + COMMAND_PERMISSION_WAIT_MS
        while state.allowed[actionId] == nil and GetGameTimer() < deadline do
            Wait(25)
        end

        if state.allowed[actionId] == true then
            return true
        end
    end

    notify('error', ('No permission for %s.'):format(label or actionId))
    return false
end

local function runCommandAction(actionId, data, label)
    if not hasCommandPermission(actionId, label) then
        return
    end

    if EsAdmin.executeAction then
        EsAdmin.executeAction(actionId, data or {})
    end
end

local function runCommandToggle(actionId, label)
    if not hasCommandPermission(actionId, label) then
        return
    end

    if EsAdmin.toggleAction then
        EsAdmin.toggleAction(actionId, not EsAdmin.state.toggles[actionId])
    end
end

local function runCommandSelect(actionId, value, label)
    if not hasCommandPermission(actionId, label) then
        return
    end

    if EsAdmin.selectAction then
        EsAdmin.selectAction(actionId, value)
    end
end

-- ============================================================================
-- TELEPORT COMMAND (Smart parsing)
-- ============================================================================

RegisterCommand('tp', function(_, args)
    if not hasCommandPermission('teleport.coords', 'teleport') then
        return
    end

    if #args == 0 then
        notify('error', 'Usage: /tp X Y [Z] or /tp X=-513.2, Y=-1943.2')
        return
    end

    -- Join all args into one string for parsing
    local input = tableConcat(args, ' ')
    
    -- Remove common prefixes/wrappers
    input = input:gsub('vector3', ''):gsub('vector4', '')
    input = input:gsub('[%(%)%[%]]', '')  -- Remove brackets
    
    local coords = { x = nil, y = nil, z = nil }
    
    -- Try to parse labeled format: X=-513.2, Y=-1943.2, Z=30
    local labeledX = input:match('[Xx]%s*[=:]%s*([%-]?[%d%.]+)')
    local labeledY = input:match('[Yy]%s*[=:]%s*([%-]?[%d%.]+)')
    local labeledZ = input:match('[Zz]%s*[=:]%s*([%-]?[%d%.]+)')
    
    if labeledX and labeledY then
        coords.x = tonumber(labeledX)
        coords.y = tonumber(labeledY)
        coords.z = labeledZ and tonumber(labeledZ) or nil
    else
        -- Try to parse unlabeled format: extract all numbers
        local numbers = {}
        local count = 0
        for num in input:gmatch('[%-]?[%d]+%.?[%d]*') do
            local n = tonumber(num)
            if n then
                count = count + 1
                numbers[count] = n
            end
        end
        
        if count >= 2 then
            coords.x = numbers[1]
            coords.y = numbers[2]
            coords.z = numbers[3] -- May be nil
        end
    end
    
    -- Validate coordinates
    if not coords.x or not coords.y then
        notify('error', 'Could not parse coordinates. Try: /tp -513.2 -1943.2')
        return
    end
    
    -- Save last coords for teleport back
    local ped = PlayerPedId()
    state.lastCoords = GetEntityCoords(ped)
    
    -- If Z is provided, teleport directly
    if coords.z then
        SetEntityCoordsNoOffset(ped, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, false, false, false)
        notify('success', ('Teleported to %.1f, %.1f, %.1f'):format(coords.x, coords.y, coords.z))
    else
        -- Use smart teleport to find ground
        exports['cortex-admin']:teleportToCoords(coords.x, coords.y, true)
    end
end, false)

RegisterCommand('tpm', function()
    runCommandAction('teleport.waypoint', nil, 'waypoint teleport')
end, false)

RegisterCommand('tpmarker', function()
    runCommandAction('teleport.marker', nil, 'marker teleport')
end, false)

RegisterCommand('tpback', function()
    runCommandAction('teleport.back', nil, 'teleport back')
end, false)

-- /parachute [0-13] — give parachute + canopy tint (matches Weapons → Parachute menu)
RegisterCommand('parachute', function(_, args)
    local tint = 0
    if args and args[1] then
        tint = tonumber(args[1]) or 0
    end
    runCommandSelect('weapons.parachute', tint, 'parachute')
end, false)

-- ============================================================================
-- OTHER COMMANDS
-- ============================================================================

-- Noclip command
RegisterCommand('noclip', function()
    runCommandToggle('player.noclip', 'noclip')
end, false)

RegisterKeyMapping('noclip', 'Toggle Noclip', 'keyboard', 'F2')

RegisterCommand('god', function()
    runCommandToggle('player.godmode', 'god mode')
end, false)

RegisterCommand('vanish', function()
    runCommandToggle('player.invisible', 'invisibility')
end, false)

RegisterCommand('heal', function()
    runCommandAction('player.heal', nil, 'heal')
end, false)

RegisterCommand('armor', function()
    runCommandAction('player.armor', nil, 'armor')
end, false)

RegisterCommand('revive', function()
    runCommandAction('player.revive', nil, 'revive')
end, false)

RegisterCommand('coords', function()
    runCommandAction('player.copyCoords', nil, 'copy coords')
end, false)

RegisterCommand('copycoords', function()
    runCommandAction('player.copyCoords', nil, 'copy coords')
end, false)

RegisterCommand('heading', function()
    runCommandAction('player.copyHeading', nil, 'copy heading')
end, false)

RegisterCommand('copyheading', function()
    runCommandAction('player.copyHeading', nil, 'copy heading')
end, false)

-- Delete vehicle command (Optimized with cortex-lib)
RegisterCommand('dv', function()
    if not hasCommandPermission('vehicle.delete', 'delete vehicle') then
        return
    end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    
    -- If in a vehicle, delete it
    if vehicle ~= 0 then
        TaskLeaveVehicle(ped, vehicle, 16) -- 16 = leave immediately
        Wait(100)
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteEntity(vehicle)
        notify('success', 'Vehicle deleted.')
        return
    end
    
    -- Otherwise, find nearest vehicle using exports['cortex-lib']:getClosestVehicle
    local coords = GetEntityCoords(ped)
    local nearestVehicle = exports['cortex-lib']:getClosestVehicle(coords, 10.0)
    
    if nearestVehicle then
        SetEntityAsMissionEntity(nearestVehicle, true, true)
        DeleteEntity(nearestVehicle)
        notify('success', 'Deleted nearby vehicle.')
    else
        notify('error', 'No vehicle found within 10m.')
    end
end, false)

RegisterCommand('delveh', function()
    ExecuteCommand('dv')
end, false)

RegisterCommand('deleteveh', function()
    ExecuteCommand('dv')
end, false)

local function spawnVehicleCommand(args)
    local model = tableConcat(args or {}, ' ')
    if type(model) == 'string' then
        model = model:match('^%s*(.-)%s*$')
    end

    if not model or model == '' then
        notify('error', 'Usage: /car [vehiclename]')
        return
    end

    runCommandAction('vehicle.spawn', { model = model }, 'spawn vehicle')
end

RegisterCommand('car', function(_, args)
    spawnVehicleCommand(args)
end, false)

RegisterCommand('veh', function(_, args)
    spawnVehicleCommand(args)
end, false)

RegisterCommand('spawnveh', function(_, args)
    spawnVehicleCommand(args)
end, false)

RegisterCommand('fix', function()
    runCommandAction('vehicle.repair', nil, 'repair vehicle')
end, false)

RegisterCommand('fixveh', function()
    runCommandAction('vehicle.repair', nil, 'repair vehicle')
end, false)

RegisterCommand('repair', function()
    runCommandAction('vehicle.repair', nil, 'repair vehicle')
end, false)

RegisterCommand('repairveh', function()
    runCommandAction('vehicle.repair', nil, 'repair vehicle')
end, false)

RegisterCommand('clean', function()
    runCommandAction('vehicle.clean', nil, 'clean vehicle')
end, false)

RegisterCommand('cleanveh', function()
    runCommandAction('vehicle.clean', nil, 'clean vehicle')
end, false)

RegisterCommand('flip', function()
    runCommandAction('vehicle.flip', nil, 'flip vehicle')
end, false)

RegisterCommand('maxmods', function()
    runCommandAction('vehicle.maxMods', nil, 'max vehicle mods')
end, false)

local function giveWeaponCommand(args)
    local weapon = tableConcat(args or {}, ' ')
    if type(weapon) == 'string' then
        weapon = weapon:match('^%s*(.-)%s*$')
    end

    if not weapon or weapon == '' then
        notify('error', 'Usage: /weapon [weapon_name]')
        return
    end

    runCommandAction('weapons.giveCustom', { weapon = weapon }, 'give weapon')
end

RegisterCommand('weapon', function(_, args)
    giveWeaponCommand(args)
end, false)

RegisterCommand('giveweapon', function(_, args)
    giveWeaponCommand(args)
end, false)

RegisterCommand('ammo', function(_, args)
    local ammo = args and args[1]
    if not ammo or ammo == '' then
        notify('error', 'Usage: /ammo [amount]')
        return
    end

    runCommandAction('weapons.setAmmo', { ammo = ammo }, 'set ammo')
end, false)

RegisterCommand('clearweapons', function()
    runCommandAction('weapons.removeAll', nil, 'remove weapons')
end, false)

RegisterCommand('preview', function(_, args)
    if not hasCommandPermission('vehicle.preview', 'vehicle preview') then
        return
    end

    local model = tableConcat(args, ' ')
    if type(model) == 'string' then
        model = model:match('^%s*(.-)%s*$')
    end

    if not model or model == '' then
        if EsAdmin.getPreviewVehicleModel and EsAdmin.getPreviewVehicleModel() and EsAdmin.clearVehiclePreview then
            EsAdmin.clearVehiclePreview()
            notify('info', 'Vehicle preview cleared.')
            return
        end

        notify('error', 'Usage: /preview [vehiclename]')
        return
    end

    if model == 'off' or model == 'clear' then
        if EsAdmin.clearVehiclePreview then
            EsAdmin.clearVehiclePreview()
            notify('info', 'Vehicle preview cleared.')
        end
        return
    end

    if EsAdmin.previewVehicle and EsAdmin.previewVehicle(model) then
        notify('success', ('Previewing vehicle: %s'):format(model))
    end
    openVehiclePreviewPage(model)
end, false)

-- Reset admin menu settings command
RegisterCommand('esadmin_reset', function()
    state.settings = {}
    for k, v in pairs(Config.DefaultSettings) do
        state.settings[k] = v
    end
    
    EsAdmin.saveSettings()
    EsAdmin.sendUiState()
    
    notify('success', 'Admin menu visual settings have been reset to defaults.')
    print('[cortex-admin] Visual settings reset to defaults via command.')
end, false)

-- ============================================================================
-- STATE LOADING
-- ============================================================================

local function loadState()
    state.settings = applyDefaultSettings(loadKvp(Config.KvpKeys.settings, {}))
    state.favorites = loadKvp(Config.KvpKeys.favorites, {}) or {}
    state.toggles = state.toggles or {}

    if state.settings and state.settings.menuPosition and type(state.settings.menuPosition) == 'string' then
        state.settings.menuPosition = state.settings.menuPosition:lower()
    end

    if state.settings.menuPosition == 'floating' or (state.settings.menuPosition ~= 'left' and state.settings.menuPosition ~= 'right') then
        state.settings.menuPosition = 'right'
    end

    local speedUnits = state.settings.speedHudUnits
    if type(speedUnits) == 'string' then
        speedUnits = speedUnits:lower()
    end
    if speedUnits ~= 'mph' and speedUnits ~= 'kph' then
        state.settings.speedHudUnits = Config.DefaultSettings.speedHudUnits
    else
        state.settings.speedHudUnits = speedUnits
    end

    local speedPos = state.settings.speedHudPosition
    if type(speedPos) == 'string' then
        speedPos = speedPos:lower()
    end
    local speedPosOk = speedPos == 'top-left' or speedPos == 'top-right' or speedPos == 'top-center'
        or speedPos == 'bottom-left' or speedPos == 'bottom-right' or speedPos == 'bottom-center'
    if not speedPosOk then
        state.settings.speedHudPosition = Config.DefaultSettings.speedHudPosition
    else
        state.settings.speedHudPosition = speedPos
    end

    if state.favorites and type(state.favorites) == 'table' then
        for index, actionId in ipairs(state.favorites) do
            if actionId == 'dev.reloadUi' then
                state.favorites[index] = 'dev.resetAllSettings'
            end
        end
    end
    
    local scale = tonumber(state.settings.uiScale) or 1.0
    if scale < 1.0 then scale = 1.0 end
    if scale > 1.6 then scale = 1.6 end
    state.settings.uiScale = scale

    local opacity = tonumber(state.settings.uiOpacity) or 0.94
    if opacity < 0.8 then opacity = 0.8 end
    if opacity > 1.0 then opacity = 1.0 end
    state.settings.uiOpacity = opacity
end

loadState()

-- ============================================================================
-- MP PED MANAGEMENT (persistent behavior)
-- ============================================================================

local mpPedState = {
    hasLoadedInitial = false,
    lastDeathTime = 0,
}

-- Try to find and load a saved ped
local function findSavedPedData()
    local lastPedName = GetResourceKvpString(LAST_PED_NAME_KEY)
    local lastPedSource = GetResourceKvpString(LAST_PED_SOURCE_KEY) or MP_PED_SOURCE_ES_ADMIN
    local lastSourceKey = GetResourceKvpString(LAST_PED_SOURCE_REF_KEY)

    if (lastPedName and lastPedName ~= '') or (lastSourceKey and lastSourceKey ~= '') then
        local sourceKey = lastSourceKey
        if not sourceKey or sourceKey == '' then
            sourceKey = normalizeSavedPedKey(lastPedName)
        end

        local _, resolvedName = normalizeSavedPedKey(sourceKey)
        resolvedName = resolvedName or lastPedName or sourceKey

        if lastPedSource == MP_PED_SOURCE_VMENU then
            local mpData = getVmenuSavedPedByKey(sourceKey)
            if mpData then
                return mpData, resolvedName, MP_PED_SOURCE_VMENU
            end
        else
            local mpData = loadKvp(sourceKey)
            if mpData then
                return normalizeMpPedData(mpData), resolvedName, MP_PED_SOURCE_ES_ADMIN
            end
        end
    end

    local defaultSource = GetResourceKvpString(DEFAULT_PED_SOURCE_KEY) or MP_PED_SOURCE_ES_ADMIN
    local defaultSourceKey = GetResourceKvpString(DEFAULT_PED_SOURCE_REF_KEY)
    if defaultSourceKey and defaultSourceKey ~= '' then
        local _, defaultName = normalizeSavedPedKey(defaultSourceKey)
        if defaultSource == MP_PED_SOURCE_VMENU then
            local mpData = getVmenuSavedPedByKey(defaultSourceKey)
            if mpData then
                return mpData, defaultName or defaultSourceKey, MP_PED_SOURCE_VMENU
            end
        else
            local mpData = loadKvp(defaultSourceKey)
            if mpData then
                return normalizeMpPedData(mpData), defaultName or defaultSourceKey, MP_PED_SOURCE_ES_ADMIN
            end
        end
    end

    local ok, defaultKey = callVmenuBridge('GetDefaultSavedMpCharacterKeyForEsAdmin')
    if ok and type(defaultKey) == 'string' and defaultKey ~= '' then
        local mpData = getVmenuSavedPedByKey(defaultKey)
        if mpData then
            local _, defaultName = normalizeSavedPedKey(defaultKey)
            return mpData, defaultName or defaultKey, MP_PED_SOURCE_VMENU
        end
    end

    return nil, nil, nil
end

-- Set default MP Ped model (male or female based on random or preference)
local function setDefaultMpPed()
    local model = joaat('mp_m_freemode_01')
    if exports['cortex-lib']:requestModel(model, 5000) then
        SetPlayerModel(PlayerId(), model)
        SetModelAsNoLongerNeeded(model)
        
        -- IMPORTANT: Freemode peds require head blend data to be visible
        local ped = PlayerPedId()
        SetPedHeadBlendData(ped, 0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.0, false)
        
        -- Set default components so ped isn't naked
        SetPedComponentVariation(ped, 0, 0, 0, 2)  -- Face
        SetPedComponentVariation(ped, 2, 0, 0, 2)  -- Hair
        SetPedComponentVariation(ped, 3, 0, 0, 2)  -- Arms
        SetPedComponentVariation(ped, 4, 0, 0, 2)  -- Legs
        SetPedComponentVariation(ped, 6, 0, 0, 2)  -- Shoes
        SetPedComponentVariation(ped, 8, 0, 0, 2)  -- Undershirt
        SetPedComponentVariation(ped, 11, 0, 0, 2) -- Torso
        
        print('[cortex-admin] Set default MP Freemode ped')
    end
end

-- Main function to load or restore MP ped
local function loadOrRestoreMpPed(isRespawn)
    local settings = state.settings
    
    -- Find saved ped data
    local pedData, pedName, source = findSavedPedData()
    
    if pedData then
        print(('[cortex-admin] Loading saved MP Ped: %s (source: %s)'):format(pedName, source))
        if type(EsAdmin.loadMpPedData) == 'function' then
            EsAdmin.loadMpPedData(pedData)
            return true
        end
        print('[cortex-admin] WARNING: loadMpPedData is unavailable during startup restore.')
    end
    
    -- No saved ped found, check if we should default to MP ped
    if settings.defaultToMpPed then
        setDefaultMpPed()
        return true
    end
    
    return false
end

-- Initial spawn handler
local function handleInitialSpawn()
    if mpPedState.hasLoadedInitial then return end
    mpPedState.hasLoadedInitial = true
    
    if not state.settings.autoLoadSavedPed then return end
    
    Wait(2000) -- Wait for player to fully spawn
    loadOrRestoreMpPed(false)
end

-- Death/respawn handler
local function handleRespawn()
    if not state.settings.restorePedOnDeath then return end
    
    Wait(1000) -- Wait for respawn to complete
    loadOrRestoreMpPed(true)
end

-- Monitor for death and respawn
CreateThread(function()
    local wasDead = false
    
    while true do
        if state.settings.restorePedOnDeath then
            Wait(1000)

            local ped = PlayerPedId()
            local isDead = IsEntityDead(ped)

            if wasDead and not isDead then
                CreateThread(handleRespawn)
            end

            wasDead = isDead
        else
            wasDead = false
            Wait(3000)
        end
    end
end)

-- Initial spawn trigger
CreateThread(function()
    Wait(5000)
    handleInitialSpawn()
end)

EsAdmin.saveSettings = function()
    saveKvp(Config.KvpKeys.settings, state.settings)
end

EsAdmin.saveFavorites = function()
    saveKvp(Config.KvpKeys.favorites, state.favorites)
end

-- ============================================================================
-- NET EVENTS
-- ============================================================================

RegisterNetEvent('cortex-admin:client:permissions', function(allowed)
    state.allowed = allowed or {}
    if state.open then
        SendNUIMessage({
            action = 'cortex-admin:setState',
            data = { allowed = state.allowed }
        })
    end
end)

RegisterNetEvent('cortex-admin:client:setAddonVehicles', function(vehicles)
    cachedData.addonVehicles = normalizeAddonVehicles(vehicles)
    menuDataCache.addonVehiclesLoaded = true
    if state.open then
        SendNUIMessage({
            action = 'cortex-admin:setState',
            data = { addonVehicles = cachedData.addonVehicles }
        })
    end
end)

RegisterNetEvent('cortex-admin:client:updateWorldState', function(payload)
    if not payload then return end

    local shouldRefreshUi = false
    local shouldOverrideClock = false

    if payload.weather ~= nil then
        worldState.weather = payload.weather
        SetWeatherTypeNowPersist(payload.weather)
        SetWeatherTypeNow(payload.weather)
        SetOverrideWeather(payload.weather)
        shouldRefreshUi = true
    end

    if payload.blackout ~= nil then
        SetBlackout(payload.blackout)
        shouldRefreshUi = true
    end

    if payload.hour ~= nil then
        worldState.hour = tonumber(payload.hour) or worldState.hour
        worldState.minute = tonumber(payload.minute) or 0
        shouldOverrideClock = true
        shouldRefreshUi = true
    end

    if payload.freezeTime ~= nil then
        worldState.freezeTime = payload.freezeTime and true or false
        if worldState.freezeTime and (worldState.hour == nil or worldState.minute == nil) then
            worldState.hour = GetClockHours()
            worldState.minute = GetClockMinutes()
        end
        PauseClock(worldState.freezeTime)
        shouldOverrideClock = worldState.freezeTime or shouldOverrideClock
        shouldRefreshUi = true
    end

    if shouldOverrideClock and worldState.hour ~= nil and worldState.minute ~= nil then
        NetworkOverrideClockTime(worldState.hour, worldState.minute, 0)
    end

    if shouldRefreshUi and state.open then
        sendRuntimeUiState(false, true)
    end
end)

RegisterNetEvent('cortex-admin:client:teleport', function(coords, heading)
    if not coords then return end
    local ped = PlayerPedId()
    SetEntityCoordsNoOffset(ped, coords.x, coords.y, coords.z, false, false, false)
    if heading then
        SetEntityHeading(ped, heading)
    end
end)

RegisterNetEvent('cortex-admin:client:freeze', function(enabled)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, enabled)
end)

RegisterNetEvent('cortex-admin:client:notify', function(notifyType, message)
    local position = 'top-right'
    if state.settings.menuPosition == 'right' then
        position = 'top-left'
    end
    
    exports['cortex-lib']:notify({
        type = notifyType or 'info',
        description = message or '',
        position = position
    })
    
    if notifyType == 'success' then
        PlaySoundFrontend(-1, "Event_Message_Purple", "GTAO_FM_Events_Soundset", true)
    elseif notifyType == 'error' then
        PlaySoundFrontend(-1, "ERROR", "HUD_AMMO_SHOP_SOUNDSET", true)
    elseif notifyType == 'info' then
        PlaySoundFrontend(-1, "Toggle_On", "HUD_FRONTEND_DEFAULT_SOUNDSET", true)
    end
end)

RegisterNetEvent('cortex-admin:client:copyText', function(text)
    SendNUIMessage({
        action = 'cortex-admin:copyText',
        data = { text = text }
    })
end)

-- ============================================================================
-- SINGLE UNIFIED TICK (ONLY thread in main.lua - minimal overhead)
-- ============================================================================

local lastPlayerListUpdate = 0
local lastWorldUiUpdate = 0

CreateThread(function()
    while true do
        local now = GetGameTimer()
        local menuOpen = state.open
        local timeFrozen = worldState.freezeTime
        
        if menuOpen then
            -- Player list update every 10 seconds while open
            if now - lastPlayerListUpdate > 10000 then
                lastPlayerListUpdate = now
                refreshPlayerList()
                sendRuntimeUiState(true, false)
            elseif now - lastWorldUiUpdate > 1000 then
                sendRuntimeUiState(false, false)
            end

            if now - lastWorldUiUpdate > 1000 then
                lastWorldUiUpdate = now
            end

            Wait(250)
        elseif timeFrozen then
            -- Time frozen: keep sync at low frequency while closed
            NetworkOverrideClockTime(worldState.hour, worldState.minute, 0)
            Wait(500)
        else
            -- Completely idle: sleep 5 seconds
            Wait(5000)
        end
    end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= currentResourceName then return end
    TriggerServerEvent('cortex-admin:server:requestWorldState')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= currentResourceName then
        return
    end

    TriggerServerEvent('cortex-admin:server:setUiPresence', { open = false })
    state.open = false
    menuTypingLock = false
    menuFocusApplied = false
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
end)
