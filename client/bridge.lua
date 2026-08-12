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

--- Check if ox_inventory is available
---@return boolean
function EsAdminBridge.hasInventory()
    return Config.HasOxInventory == true
end

--- Check if qbx_vehicles is available
---@return boolean
function EsAdminBridge.hasGarage()
    return Config.HasQBXVehicles == true
end

--- Get framework info table for sending to NUI
---@return table
function EsAdminBridge.getFrameworkInfo()
    return {
        framework = Config.Framework or 'standalone',
        hasInventory = Config.HasOxInventory == true,
        hasGarage = Config.HasQBXVehicles == true,
        hasQBX = Config.HasQBX == true,
    }
end

print('[cortex-admin] Client bridge loaded')
