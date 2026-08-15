--[[
    Everest Admin - Client-Side Framework Bridge
    Provides client-side helpers for framework detection and data access.
]]

EsAdminBridge = EsAdminBridge or {}

--- Check if QBX framework is active
---@return boolean
function EsAdminBridge.isQBX()
    return Config.HasQBX == true
end

--- Check if ox_inventory is available to the QBX-backed admin flow
---@return boolean
function EsAdminBridge.hasInventory()
    return Config.HasQBX == true and Config.HasOxInventory == true
end

--- Check if qbx_vehicles is available to the QBX-backed admin flow
---@return boolean
function EsAdminBridge.hasGarage()
    return Config.HasQBX == true and Config.HasQBXVehicles == true
end

--- Get framework info table for sending to NUI
---@return table
function EsAdminBridge.getFrameworkInfo()
    local hasQBX = Config.HasQBX == true
    return {
        framework = Config.Framework or 'standalone',
        hasInventory = hasQBX and Config.HasOxInventory == true,
        hasGarage = hasQBX and Config.HasQBXVehicles == true,
        hasQBX = hasQBX,
    }
end

local frameworkGeneration = 0
local lastFrameworkInfo = EsAdminBridge.getFrameworkInfo()

--- Return the client-owned dependency lifecycle generation for request correlation.
---@return number
function EsAdminBridge.getFrameworkGeneration()
    return frameworkGeneration
end

--- Reject replies issued before the most recent dependency transition.
---@param generation number
---@return boolean
function EsAdminBridge.isFrameworkGenerationCurrent(generation)
    return type(generation) == 'number' and generation == frameworkGeneration
end

-- Keep the browser snapshot synchronized while the menu is open or closed.
-- Disabled integrations also clear their data so a later view cannot render
-- entries fetched before the dependency stopped.
AddEventHandler('cortex-admin:frameworkChanged', function()
    local frameworkInfo = EsAdminBridge.getFrameworkInfo()
    local lostCapability = (lastFrameworkInfo.hasQBX and not frameworkInfo.hasQBX)
        or (lastFrameworkInfo.hasInventory and not frameworkInfo.hasInventory)
        or (lastFrameworkInfo.hasGarage and not frameworkInfo.hasGarage)
    local data = { frameworkInfo = frameworkInfo }

    frameworkGeneration = frameworkGeneration + 1
    lastFrameworkInfo = frameworkInfo

    if not frameworkInfo.hasInventory then
        data.inventoryItems = {}
    end
    if not frameworkInfo.hasGarage then
        data.garageVehicles = {}
    end

    if lostCapability then
        SendNUIMessage({
            action = 'cortex-admin:setTab',
            data = { tab = 'all' },
        })
    end

    SendNUIMessage({
        action = 'cortex-admin:setState',
        data = data,
    })
end)

print('[cortex-admin] Client bridge loaded')
