--[[
    Everest Admin - Shared Configuration
]]

Config = Config or {}

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
    settings = 'es_admin_settings',
    favorites = 'es_admin_favorites',
    bans = 'es_admin_bans',
}

Config.Permissions = {
    all = 'es_admin.all',
    player = 'es_admin.player',
    vehicle = 'es_admin.vehicle',
    vehicle_custom = 'es_admin.vehicle',
    world = 'es_admin.world',
    weapons = 'es_admin.weapons',
    teleport = 'es_admin.teleport',
    dev = 'es_admin.dev',
    options = 'es_admin.options',
    server = 'es_admin.server',
    inventory = 'es_admin.inventory',
    garage = 'es_admin.garage',
}

Config.ActionPermissions = {
    ['player.kick'] = 'es_admin.server.kick',
    ['player.ban'] = 'es_admin.server.ban',
    ['player.unban'] = 'es_admin.server.ban',
    ['player.freeze'] = 'es_admin.server.freeze',
    ['player.bring'] = 'es_admin.server.teleport',
    ['player.kill'] = 'es_admin.player',
    ['player.reviveTarget'] = 'es_admin.player',
    ['player.sitInVehicle'] = 'es_admin.player',
    ['player.setJob'] = 'es_admin.player',
    ['player.setGang'] = 'es_admin.player',
    ['player.setCash'] = 'es_admin.player',
    ['player.setBank'] = 'es_admin.player',
    ['player.giveMoney'] = 'es_admin.player',
    ['player.setFood'] = 'es_admin.player',
    ['player.setThirst'] = 'es_admin.player',
    ['player.setStress'] = 'es_admin.player',
    ['player.openInventory'] = 'es_admin.inventory',
    ['player.setRoutingBucket'] = 'es_admin.server',
    ['vehicle.adminCar'] = 'es_admin.vehicle',
    ['vehicle.giveKeys'] = 'es_admin.vehicle',
    ['world.weather'] = 'es_admin.world.weather',
    ['world.weatherEditor'] = 'es_admin.world.weather.editor',
    ['world.weatherReload'] = 'es_admin.world.weather.reload',
    ['world.weatherForce'] = 'es_admin.world.weather.force',
    ['world.time'] = 'es_admin.world.time',
    ['world.freezeTime'] = 'es_admin.world.time',
    ['world.blackout'] = 'es_admin.world.blackout',
    ['inventory.giveItem'] = 'es_admin.inventory',
    ['garage.spawnVehicle'] = 'es_admin.garage',
    ['server.pullStash'] = 'es_admin.server',
}

Config.BanIdentifierTypes = { 'license', 'license2', 'steam', 'discord', 'fivem', 'xbl', 'live' }

-- =============================================================================
-- QBX PERMISSION MAPPING
-- When QBX is detected, players in these ACE groups automatically receive
-- the listed es_admin permissions without needing separate es_admin.* ACEs.
-- Permissions are checked in order; first matching group wins.
--
-- 'all' grants full access (same as es_admin.all)
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
        acePerms = { 'admin', 'command' },
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
