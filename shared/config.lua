--[[
    Everest Admin - Shared Configuration
]]

Config = Config or {}

Config.Debug = false

Config.Command = 'esadmin'
Config.Keybind = 'F10'
Config.WardrobeShareRadius = 8.0
Config.VehiclePreviewCloseControl = 194

Config.DefaultSettings = {
    uiScale = 1,
    uiOpacity = 0.94,
    menuAccentColor = '#7170ff',
    showTargetInfo = true,
    menuPosition = 'right',
    doubleClickToRun = true,
    -- MP Ped / Appearance Settings
    autoLoadSavedPed = true,      -- Automatically load last saved MP Ped on initial spawn
    restorePedOnDeath = true,     -- Restore saved MP Ped appearance after respawning from death
    defaultToMpPed = true,        -- Default to MP Freemode ped if no saved ped exists
    replacePersonalVehicle = true, -- Delete vehicle you occupy before spawn (list, preview, personal, garage)
    disableAircraftTurbulence = false,
    quitSessionInRockstarEditor = false,
    speedHudUnits = 'mph',
    speedHudPosition = 'top-left',
}

Config.ClearRadiusOptions = {
    { label = '25m', value = 25 },
    { label = '50m', value = 50 },
    { label = '100m', value = 100 },
    { label = '200m', value = 200 },
    { label = '400m', value = 400 },
}

Config.WeaponList = {
    'weapon_knife',
    'weapon_nightstick',
    'weapon_hammer',
    'weapon_bat',
    'weapon_golfclub',
    'weapon_crowbar',
    'weapon_pistol',
    'weapon_pistol_mk2',
    'weapon_combatpistol',
    'weapon_appistol',
    'weapon_pistol50',
    'weapon_snspistol',
    'weapon_heavypistol',
    'weapon_vintagepistol',
    'weapon_microsmg',
    'weapon_smg',
    'weapon_smg_mk2',
    'weapon_assaultsmg',
    'weapon_combatpdw',
    'weapon_assaultshotgun',
    'weapon_pumpshotgun',
    'weapon_pumpshotgun_mk2',
    'weapon_sawnoffshotgun',
    'weapon_bullpupshotgun',
    'weapon_heavyshotgun',
    'weapon_assaultrifle',
    'weapon_carbinerifle',
    'weapon_carbinerifle_mk2',
    'weapon_advancedrifle',
    'weapon_specialcarbine',
    'weapon_specialcarbine_mk2',
    'weapon_bullpuprifle',
    'weapon_bullpuprifle_mk2',
    'weapon_compactrifle',
    'weapon_sniperrifle',
    'weapon_heavysniper',
    'weapon_heavysniper_mk2',
    'weapon_marksmanrifle',
    'weapon_marksmanrifle_mk2',
    'weapon_grenadelauncher',
    'weapon_rpg',
    'weapon_minigun',
    'weapon_firework',
    'weapon_hominglauncher',
    'weapon_grenade',
    'weapon_stickybomb',
    'weapon_smokegrenade',
    'weapon_molotov',
    'weapon_proxmine',
    'weapon_pipebomb',
    'weapon_ball',
    'weapon_flare',
    'weapon_petrolcan',
    'weapon_fireextinguisher'
}

Config.KvpKeys = {
    settings = 'cortex-admin_settings',
    favorites = 'cortex-admin_favorites',
    bans = 'cortex-admin_bans',
}

Config.Permissions = {
    all = 'cortex-admin.all',
    player = 'cortex-admin.player',
    vehicle = 'cortex-admin.vehicle',
    vehicle_custom = 'cortex-admin.vehicle',
    world = 'cortex-admin.world',
    weapons = 'cortex-admin.weapons',
    teleport = 'cortex-admin.teleport',
    dev = 'cortex-admin.dev',
    options = 'cortex-admin.options',
    server = 'cortex-admin.server',
    inventory = 'cortex-admin.inventory',
    garage = 'cortex-admin.garage',
}

Config.ActionPermissions = {
    ['player.kick'] = 'cortex-admin.server.kick',
    ['player.ban'] = 'cortex-admin.server.ban',
    ['player.unban'] = 'cortex-admin.server.ban',
    ['player.freeze'] = 'cortex-admin.server.freeze',
    ['player.bring'] = 'cortex-admin.server.teleport',
    ['player.goto'] = 'cortex-admin.server.teleport',
    ['player.kill'] = 'cortex-admin.player',
    ['player.reviveTarget'] = 'cortex-admin.player',
    ['player.sitInVehicle'] = 'cortex-admin.player',
    ['player.setJob'] = 'cortex-admin.player',
    ['player.setGang'] = 'cortex-admin.player',
    ['player.setCash'] = 'cortex-admin.player',
    ['player.setBank'] = 'cortex-admin.player',
    ['player.giveMoney'] = 'cortex-admin.player',
    ['player.setFood'] = 'cortex-admin.player',
    ['player.setThirst'] = 'cortex-admin.player',
    ['player.setStress'] = 'cortex-admin.player',
    ['player.openInventory'] = 'cortex-admin.inventory',
    ['player.setRoutingBucket'] = 'cortex-admin.server',
    ['vehicle.adminCar'] = 'cortex-admin.vehicle',
    ['vehicle.giveKeys'] = 'cortex-admin.vehicle',
    ['vehicle.liveTuning'] = 'cortex-admin.vehicle',
    ['world.weather'] = 'cortex-admin.world.weather',
    ['world.weatherEditor'] = 'cortex-admin.world.weather.editor',
    ['world.weatherReload'] = 'cortex-admin.world.weather.reload',
    ['world.weatherForce'] = 'cortex-admin.world.weather.force',
    ['world.weatherForceCurrent'] = 'cortex-admin.world.weather.force',
    ['world.time'] = 'cortex-admin.world.time',
    ['world.freezeTime'] = 'cortex-admin.world.time',
    ['world.blackout'] = 'cortex-admin.world.blackout',
    ['inventory.giveItem'] = 'cortex-admin.inventory',
    ['garage.spawnVehicle'] = 'cortex-admin.garage',
    ['server.pullStash'] = 'cortex-admin.server',
}

Config.BanIdentifierTypes = { 'license', 'license2', 'steam', 'discord', 'fivem', 'xbl', 'live' }

-- =============================================================================
-- QBX PERMISSION MAPPING
-- When QBX is detected, players in these ACE groups automatically receive
-- the listed cortex-admin permissions without needing separate cortex-admin.* ACEs.
-- Permissions are checked in order; first matching group wins.
--
-- 'all' grants full access (same as cortex-admin.all)
-- Tab names grant access to that tab (e.g. 'player', 'vehicle', 'world')
-- Action IDs grant access to specific actions (e.g. 'player.kick')
-- =============================================================================
Config.QBXPermissions = {
    -- god group: full access to everything
    -- Uses the 'admin' ACE permission which group.admin/group.god principals typically have
    ['god'] = {
        acePerms = { 'god' },        -- ACE permission strings to check (any match grants)
        grant = 'all',               -- 'all' = full admin
    },
    -- admin group: full access to everything
    ['admin'] = {
        acePerms = { 'admin' },
        grant = 'all',
    },
    -- mod group: limited access (no dev, server, ban)
    ['mod'] = {
        acePerms = { 'mod' },
        grant = {
            tabs = { 'player', 'vehicle', 'world', 'weapons', 'teleport', 'appearance', 'vehicle_custom', 'inventory', 'garage', 'options' },
            deny = { 'player.ban', 'player.unban', 'dev', 'server' },
        },
    },
}
