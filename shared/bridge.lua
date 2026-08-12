--[[
    Everest Admin - Shared Framework Bridge
    Auto-detects QBX, ox_inventory, qbx_vehicles at resource start.
    All QBX features are gated behind runtime detection.
]]

Config = Config or {}

-- Framework detection (runs on both client and server)
local function detectFramework()
    local qbxState = GetResourceState('qbx_core')
    local oxInvState = GetResourceState('ox_inventory')
    local qbxVehState = GetResourceState('qbx_vehicles')

    Config.Framework = (qbxState == 'started' or qbxState == 'starting') and 'qbx' or 'standalone'
    Config.Inventory = (oxInvState == 'started' or oxInvState == 'starting') and 'ox_inventory' or 'none'

    Config.HasQBX = Config.Framework == 'qbx'
    Config.HasOxInventory = Config.Inventory == 'ox_inventory'
    Config.HasQBXVehicles = (qbxVehState == 'started' or qbxVehState == 'starting') and true or false

    print(('[cortex-admin] Framework: %s | Inventory: %s | Vehicles: %s'):format(
        Config.Framework,
        Config.Inventory,
        Config.HasQBXVehicles and 'qbx_vehicles' or 'none'
    ))
end

-- Run detection immediately (shared script runs on both sides)
detectFramework()

-- Re-detect if relevant resources start later
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == 'qbx_core' or resourceName == 'ox_inventory' or resourceName == 'qbx_vehicles' then
        detectFramework()
    end
end)

return Config
