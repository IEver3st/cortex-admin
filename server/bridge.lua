--[[
    Everest Admin - Server-Side Framework Bridge
    Provides abstracted functions for QBX player lookups, inventory management,
    and vehicle garage queries. Falls back gracefully when frameworks aren't present.
]]

EsAdminBridge = EsAdminBridge or {}

local cachedItems = nil
local cachedItemsTime = 0
local ITEM_CACHE_TTL = 60 -- seconds

-- ============================================================================
-- PLAYER FUNCTIONS
-- ============================================================================

--- Get QBX player object by server source
---@param src number
---@return table|nil
function EsAdminBridge.getPlayer(src)
    if not Config.HasQBX then return nil end

    local ok, player = pcall(function()
        return exports.qbx_core:GetPlayer(src)
    end)

    if ok and player then
        return player
    end
    return nil
end

--- Get citizenid for a player source
---@param src number
---@return string|nil
function EsAdminBridge.getPlayerCitizenId(src)
    if not Config.HasQBX then return nil end

    local player = EsAdminBridge.getPlayer(src)
    if player and player.PlayerData and player.PlayerData.citizenid then
        return player.PlayerData.citizenid
    end
    return nil
end

--- Get player name with framework awareness
---@param src number
---@return string
function EsAdminBridge.getPlayerName(src)
    if Config.HasQBX then
        local player = EsAdminBridge.getPlayer(src)
        if player and player.PlayerData and player.PlayerData.charinfo then
            local ci = player.PlayerData.charinfo
            local first = ci.firstname or ''
            local last = ci.lastname or ''
            if first ~= '' or last ~= '' then
                return ('%s %s'):format(first, last):gsub('^%s+', ''):gsub('%s+$', '')
            end
        end
    end
    return GetPlayerName(src) or ('Player %d'):format(src)
end

-- ============================================================================
-- INVENTORY FUNCTIONS (ox_inventory)
-- ============================================================================

--- Get all registered items from ox_inventory
---@return table[] items - array of {name, label, weight}
function EsAdminBridge.getAllItems()
    if not Config.HasOxInventory then return {} end

    -- Use cache if fresh
    local now = os.time()
    if cachedItems and (now - cachedItemsTime) < ITEM_CACHE_TTL then
        return cachedItems
    end

    local ok, rawItems = pcall(function()
        return exports.ox_inventory:Items()
    end)

    if not ok or not rawItems then
        print('[es_admin] Failed to fetch items from ox_inventory')
        return cachedItems or {}
    end

    local items = {}
    for itemName, itemData in pairs(rawItems) do
        if type(itemData) == 'table' then
            items[#items + 1] = {
                name = itemName,
                label = itemData.label or itemName,
                weight = itemData.weight or 0,
            }
        end
    end

    -- Sort alphabetically by label
    table.sort(items, function(a, b)
        return (a.label or ''):lower() < (b.label or ''):lower()
    end)

    cachedItems = items
    cachedItemsTime = now
    print(('[es_admin] Cached %d items from ox_inventory'):format(#items))
    return items
end

--- Give an item to a player via ox_inventory
---@param targetSrc number server source of the target player
---@param itemName string item name
---@param amount number quantity to give
---@return boolean success
---@return string|nil errorMessage
function EsAdminBridge.giveItem(targetSrc, itemName, amount)
    if not Config.HasOxInventory then
        return false, 'No inventory system detected'
    end

    if not itemName or itemName == '' then
        return false, 'Item name required'
    end

    amount = tonumber(amount) or 1
    if amount < 1 then
        return false, 'Amount must be at least 1'
    end

    -- Verify the item exists
    local ok, itemData = pcall(function()
        return exports.ox_inventory:Items(itemName)
    end)

    if not ok or not itemData then
        return false, 'Item not found: ' .. tostring(itemName)
    end

    -- Check if target can carry the item
    local canCarry, carryErr = pcall(function()
        return exports.ox_inventory:CanCarryItem(targetSrc, itemName, amount)
    end)

    if canCarry == true and carryErr == false then
        return false, 'Player cannot carry that many items'
    end

    -- Add the item
    local addOk, success, response = pcall(function()
        return exports.ox_inventory:AddItem(targetSrc, itemName, amount)
    end)

    if not addOk then
        return false, 'Failed to add item (error)'
    end

    if success then
        return true, nil
    else
        return false, response or 'Failed to add item'
    end
end

-- ============================================================================
-- VEHICLE / GARAGE FUNCTIONS (qbx_vehicles)
-- ============================================================================

--- Get all vehicles owned by a citizenid from qbx_vehicles
---@param citizenid string
---@return table[] vehicles
function EsAdminBridge.getPlayerVehicles(citizenid)
    if not Config.HasQBXVehicles or not citizenid then return {} end

    local ok, vehicles = pcall(function()
        return exports.qbx_vehicles:GetPlayerVehicles({ citizenid = citizenid })
    end)

    if not ok or not vehicles then
        print('[es_admin] Failed to fetch player vehicles from qbx_vehicles')
        return {}
    end

    -- Get the shared vehicle data for labels
    local sharedVehicles = EsAdminBridge.getSharedVehicleList()

    local result = {}
    for i = 1, #vehicles do
        local veh = vehicles[i]
        local modelName = veh.modelName or 'unknown'
        local sharedData = sharedVehicles[modelName]
        local plate = ''
        if veh.props and veh.props.plate then
            plate = veh.props.plate
        end

        result[#result + 1] = {
            id = veh.id,
            citizenid = veh.citizenid,
            model = modelName,
            label = sharedData and sharedData.name or modelName,
            brand = sharedData and sharedData.brand or '',
            category = sharedData and sharedData.category or 'other',
            garage = veh.garage or 'unknown',
            state = veh.state, -- 0=OUT, 1=GARAGED, 2=IMPOUNDED
            plate = plate,
            props = veh.props,
        }
    end

    -- Sort by garage then label
    table.sort(result, function(a, b)
        if a.garage ~= b.garage then
            return (a.garage or ''):lower() < (b.garage or ''):lower()
        end
        return (a.label or ''):lower() < (b.label or ''):lower()
    end)

    return result
end

--- Get the shared vehicle list from qbx_core
---@return table<string, table> vehiclesByModel
function EsAdminBridge.getSharedVehicleList()
    if not Config.HasQBX then return {} end

    local ok, vehicles = pcall(function()
        return exports.qbx_core:GetVehiclesByName()
    end)

    if ok and vehicles then
        return vehicles
    end

    -- Fallback: try to access the shared data directly
    ok, vehicles = pcall(function()
        if QBX and QBX.Shared and QBX.Shared.Vehicles then
            return QBX.Shared.Vehicles
        end
        return nil
    end)

    if ok and vehicles then
        return vehicles
    end

    return {}
end

-- ============================================================================
-- QBX PERMISSION INTEGRATION
-- ============================================================================

--- Cache of resolved QBX permission groups per player source
--- Cleared when a player drops
local qbxPermCache = {}

--- Determine which QBX permission group a player belongs to (if any)
--- Returns the first matching group config from Config.QBXPermissions
---@param src number
---@return table|nil groupConfig  The matching group from Config.QBXPermissions
---@return string|nil groupName   The name of the matching group
--- Check if a player matches any of the ACE permission strings for a group
---@param src number
---@param groupConfig table
---@return boolean
local function matchesGroupPerms(src, groupConfig)
    local perms = groupConfig.acePerms
    if not perms then return false end
    for _, perm in ipairs(perms) do
        if IsPlayerAceAllowed(src, perm) then
            return true
        end
    end
    return false
end

function EsAdminBridge.getQBXPermissionGroup(src)
    if not Config.HasQBX then return nil, nil end
    if not Config.QBXPermissions then return nil, nil end

    -- Check cache first
    if qbxPermCache[src] ~= nil then
        if qbxPermCache[src] == false then return nil, nil end
        return qbxPermCache[src].config, qbxPermCache[src].name
    end

    -- Check groups in priority order: god > admin > mod
    local priorityOrder = { 'god', 'admin', 'mod' }

    local checked = {}
    for _, groupName in ipairs(priorityOrder) do
        local groupConfig = Config.QBXPermissions[groupName]
        if groupConfig then
            checked[groupName] = true
            if matchesGroupPerms(src, groupConfig) then
                qbxPermCache[src] = { config = groupConfig, name = groupName }
                return groupConfig, groupName
            end
        end
    end

    -- Check any custom groups not in the priority list
    for groupName, groupConfig in pairs(Config.QBXPermissions) do
        if not checked[groupName] then
            if matchesGroupPerms(src, groupConfig) then
                qbxPermCache[src] = { config = groupConfig, name = groupName }
                return groupConfig, groupName
            end
        end
    end

    -- No matching group
    qbxPermCache[src] = false
    return nil, nil
end

--- Check if a QBX player has permission for a specific action based on their group mapping
---@param src number
---@param actionId string  e.g. 'player.kick', 'inventory.giveItem'
---@param actionTab string|nil  The tab the action belongs to
---@return boolean|nil  true=allowed, false=denied, nil=no QBX group (fall through to normal ACE checks)
function EsAdminBridge.checkQBXPermission(src, actionId, actionTab)
    local groupConfig, groupName = EsAdminBridge.getQBXPermissionGroup(src)
    if not groupConfig then return nil end -- No QBX group, fall through

    local grant = groupConfig.grant

    -- Simple 'all' grant = full access
    if grant == 'all' then
        return true
    end

    -- Complex grant table: { tabs = {...}, deny = {...} }
    if type(grant) == 'table' then
        -- Check explicit denies first
        if grant.deny then
            for _, denied in ipairs(grant.deny) do
                -- Deny can be an action ID or a tab name
                if actionId == denied then return false end
                if actionTab and actionTab == denied then return false end
            end
        end

        -- Check tab grants
        if grant.tabs and actionTab then
            for _, allowedTab in ipairs(grant.tabs) do
                if actionTab == allowedTab then return true end
            end
        end

        -- Check specific action grants (if defined)
        if grant.actions then
            for _, allowedAction in ipairs(grant.actions) do
                if actionId == allowedAction then return true end
            end
        end

        -- If tabs are defined but the action's tab isn't in the list, deny
        if grant.tabs then
            return false
        end
    end

    return nil -- Fall through to normal ACE checks
end

--- Clear permission cache for a player (call on disconnect)
---@param src number
function EsAdminBridge.clearPermCache(src)
    qbxPermCache[src] = nil
end

--- Check if a player has any QBX admin group at all (for menu access gating)
---@param src number
---@return boolean
function EsAdminBridge.isQBXAdmin(src)
    local groupConfig = EsAdminBridge.getQBXPermissionGroup(src)
    return groupConfig ~= nil
end

-- Clear cache when player drops
AddEventHandler('playerDropped', function()
    local src = source
    if src then
        EsAdminBridge.clearPermCache(src)
    end
end)

print('[es_admin] Server bridge loaded')
