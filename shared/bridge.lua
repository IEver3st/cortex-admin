--[[
    Everest Admin - Shared Framework Bridge
    Tracks QBX, ox_inventory, and qbx_vehicles across their full resource lifecycle.
    Capabilities are available only after a dependency is fully started.
]]

Config = Config or {}

local trackedResources = {
    qbx_core = true,
    ox_inventory = true,
    qbx_vehicles = true,
}

local lastSnapshot = nil

local function isStarted(resourceName, stoppedResource)
    if resourceName == stoppedResource then
        return false
    end
    return GetResourceState(resourceName) == 'started'
end

local function buildSnapshot(stoppedResource)
    local hasQBX = isStarted('qbx_core', stoppedResource)
    local hasOxInventory = isStarted('ox_inventory', stoppedResource)
    local hasQBXVehicles = isStarted('qbx_vehicles', stoppedResource)

    return {
        framework = hasQBX and 'qbx' or 'standalone',
        inventory = hasOxInventory and 'ox_inventory' or 'none',
        hasQBX = hasQBX,
        hasOxInventory = hasOxInventory,
        hasQBXVehicles = hasQBXVehicles,
    }
end

local function snapshotsEqual(first, second)
    return first
        and second
        and first.framework == second.framework
        and first.inventory == second.inventory
        and first.hasQBX == second.hasQBX
        and first.hasOxInventory == second.hasOxInventory
        and first.hasQBXVehicles == second.hasQBXVehicles
end

local function copySnapshot(snapshot)
    return {
        framework = snapshot.framework,
        inventory = snapshot.inventory,
        hasQBX = snapshot.hasQBX,
        hasOxInventory = snapshot.hasOxInventory,
        hasQBXVehicles = snapshot.hasQBXVehicles,
    }
end

-- Framework detection runs in both runtimes. A stop event passes the stopped
-- resource explicitly because its state can still be reported as "started"
-- while lifecycle callbacks are being dispatched.
local function detectFramework(stoppedResource, changedResource)
    local snapshot = buildSnapshot(stoppedResource)
    local changed = not snapshotsEqual(lastSnapshot, snapshot)

    Config.Framework = snapshot.framework
    Config.Inventory = snapshot.inventory
    Config.HasQBX = snapshot.hasQBX
    Config.HasOxInventory = snapshot.hasOxInventory
    Config.HasQBXVehicles = snapshot.hasQBXVehicles

    if not changed then
        return snapshot
    end

    local hadPreviousSnapshot = lastSnapshot ~= nil
    lastSnapshot = copySnapshot(snapshot)

    print(('[cortex-admin] Framework: %s | Inventory: %s | Vehicles: %s'):format(
        Config.Framework,
        Config.Inventory,
        Config.HasQBXVehicles and 'qbx_vehicles' or 'none'
    ))

    if hadPreviousSnapshot then
        TriggerEvent('cortex-admin:frameworkChanged', snapshot, changedResource)
    end

    return snapshot
end

-- Run detection immediately (shared script runs on both sides).
detectFramework()

local startEvent = IsDuplicityVersion() and 'onResourceStart' or 'onClientResourceStart'
local stopEvent = IsDuplicityVersion() and 'onResourceStop' or 'onClientResourceStop'
local startCheckTokens = {}

local function cancelStartCheck(resourceName)
    startCheckTokens[resourceName] = (startCheckTokens[resourceName] or 0) + 1
end

local function detectAfterStart(resourceName)
    cancelStartCheck(resourceName)
    local token = startCheckTokens[resourceName]

    detectFramework(nil, resourceName)
    if GetResourceState(resourceName) ~= 'starting' then
        return
    end

    -- onResourceStart/onClientResourceStart can run before the state leaves
    -- "starting". Wait until the dependency is actually export-ready instead
    -- of advertising it early or relying on a second start event.
    CreateThread(function()
        while startCheckTokens[resourceName] == token do
            Wait(100)
            if startCheckTokens[resourceName] ~= token then
                return
            end

            local state = GetResourceState(resourceName)
            if state == 'started' then
                detectFramework(nil, resourceName)
                return
            end
            if state ~= 'starting' then
                detectFramework(nil, resourceName)
                return
            end
        end
    end)
end

AddEventHandler(startEvent, function(resourceName)
    if trackedResources[resourceName] then
        detectAfterStart(resourceName)
    end
end)

AddEventHandler(stopEvent, function(resourceName)
    if trackedResources[resourceName] then
        cancelStartCheck(resourceName)
        detectFramework(resourceName, resourceName)
    end
end)

return Config
