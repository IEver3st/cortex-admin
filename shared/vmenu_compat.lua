--[[
    Cortex Admin vMenu compatibility catalog.

    This file deliberately contains only declarative actions, permission aliases,
    and migration configuration. Runtime behavior lives in client/server modules.
    Existing cortex-admin ACEs remain authoritative, while a server can keep its
    vMenu ACE file during migration without granting a second set of permissions.
]]

Config = Config or {}
EsAdminActions = EsAdminActions or { tabs = {}, actions = {} }

Config.VmenuCompatibility = Config.VmenuCompatibility or {
    enabled = true,
    commandAlias = 'vmenu',
    keybind = 'M',
    waypointKeybind = 'F7',
    importResourceNames = { 'vMenu', 'vmenu' },
    importConfigFiles = {
        addons = 'config/addons.json',
        extras = 'config/extras.json',
        locations = 'config/locations.json',
        modelWhitelists = 'config/model-whitelists.json',
        tattoos = 'config/tattoos.json',
    },
}

Config.VmenuFallback = Config.VmenuFallback or {
    enabled = true,
    kvsPath = '',
    cacheMs = 5000,
    requestTimeoutMs = 3500,
}

Config.KvpKeys = Config.KvpKeys or {}
Config.KvpKeys.vmenuImport = Config.KvpKeys.vmenuImport or 'cortex-admin_vmenu_import_v2'
Config.KvpKeys.vmenuPreferences = Config.KvpKeys.vmenuPreferences or 'cortex-admin_vmenu_preferences_v1'
Config.KvpKeys.vmenuServerImport = Config.KvpKeys.vmenuServerImport or 'cortex-admin_vmenu_server_import_v1'
Config.KvpKeys.vmenuClientConfig = Config.KvpKeys.vmenuClientConfig or 'cortex-admin_vmenu_client_config_v1'
Config.KvpKeys.vmenuCategories = Config.KvpKeys.vmenuCategories or 'cortex-admin_vmenu_categories_v1'

local function values(list)
    local output = {}
    for index = 1, #list do
        output[#output + 1] = { label = list[index][1], value = list[index][2] }
    end
    return output
end

local drivingStyles = values({
    { 'Normal', 786603 },
    { 'Cautious', 786468 },
    { 'Avoid traffic', 2883621 },
    { 'Rushed', 1074528293 },
    { 'Very aggressive', 1076 },
})

local doorValues = values({
    { 'Open all', 'open_all' }, { 'Close all', 'close_all' },
    { 'Front left', 'toggle_0' }, { 'Front right', 'toggle_1' },
    { 'Rear left', 'toggle_2' }, { 'Rear right', 'toggle_3' },
    { 'Hood', 'toggle_4' }, { 'Trunk', 'toggle_5' },
    { 'Extra door 1', 'toggle_6' }, { 'Extra door 2', 'toggle_7' },
    { 'Bomb bay', 'bomb_bay' },
    { 'Remove front left', 'remove_0' }, { 'Remove front right', 'remove_1' },
    { 'Remove rear left', 'remove_2' }, { 'Remove rear right', 'remove_3' },
    { 'Remove hood', 'remove_4' }, { 'Remove trunk', 'remove_5' },
    { 'Remove extra door 1', 'remove_6' }, { 'Remove extra door 2', 'remove_7' },
    { 'Restore removed doors', 'restore' },
})

local windowValues = values({
    { 'Front windows up', 'front_up' }, { 'Front windows down', 'front_down' },
    { 'Rear windows up', 'rear_up' }, { 'Rear windows down', 'rear_down' },
    { 'All windows up', 'all_up' }, { 'All windows down', 'all_down' },
})

local lightValues = values({
    { 'Automatic', 0 }, { 'Force off', 1 }, { 'Force on', 2 }, { 'High beams', 3 },
})

local parachuteStyles = values({
    { 'Rainbow', 0 }, { 'Red', 1 }, { 'Seaside', 2 }, { 'Widowmaker', 3 },
    { 'Patriot', 4 }, { 'Blue', 5 }, { 'Black', 6 }, { 'Hornet', 7 },
    { 'Air Force', 8 }, { 'Desert', 9 }, { 'Shadow', 10 }, { 'High altitude', 11 },
    { 'Airborne', 12 }, { 'Sunrise', 13 },
})

local radioStations = values({
    { 'Radio Off', 'OFF' }, { 'Los Santos Rock Radio', 'RADIO_01_CLASS_ROCK' },
    { 'Non-Stop-Pop FM', 'RADIO_02_POP' }, { 'Radio Los Santos', 'RADIO_03_HIPHOP_NEW' },
    { 'Channel X', 'RADIO_04_PUNK' }, { 'West Coast Talk Radio', 'RADIO_05_TALK_01' },
    { 'Rebel Radio', 'RADIO_06_COUNTRY' }, { 'Soulwax FM', 'RADIO_07_DANCE_01' },
    { 'East Los FM', 'RADIO_08_MEXICAN' }, { 'West Coast Classics', 'RADIO_09_HIPHOP_OLD' },
    { 'Blaine County Radio', 'RADIO_11_TALK_02' }, { 'Blue Ark', 'RADIO_12_REGGAE' },
    { 'Worldwide FM', 'RADIO_13_JAZZ' }, { 'FlyLo FM', 'RADIO_14_DANCE_02' },
    { 'The Lowdown 91.1', 'RADIO_15_MOTOWN' }, { 'Radio Mirror Park', 'RADIO_16_SILVERLAKE' },
    { 'Space 103.2', 'RADIO_17_FUNK' }, { 'Vinewood Boulevard Radio', 'RADIO_18_90S_ROCK' },
    { 'Self Radio', 'RADIO_19_USER' }, { 'The Lab', 'RADIO_20_THELAB' },
})

local actions = {
    -- Player Options parity.
    { id = 'player.stayInVehicle', label = 'Stay In Vehicle', description = 'Prevent being dragged or jacked out of a vehicle', tab = 'player', type = 'toggle' },
    { id = 'player.armorType', label = 'Set Armor Type', description = 'Set armor from none through super-heavy armor', tab = 'player', type = 'select', values = values({ { 'No armor', 0 }, { 'Super light', 20 }, { 'Light', 40 }, { 'Standard', 60 }, { 'Heavy', 80 }, { 'Super heavy', 100 } }) },
    { id = 'player.clearBlood', label = 'Clear Blood', description = 'Remove blood and visible damage without changing clothes', tab = 'player', type = 'action' },
    { id = 'player.setBloodLevel', label = 'Set Blood Level', description = 'Apply a visible injury and blood level', tab = 'player', type = 'select', values = values({ { 'Clear', 0 }, { 'Light', 1 }, { 'Medium', 2 }, { 'Heavy', 3 }, { 'Critical', 4 } }) },
    { id = 'player.suicide', label = 'Commit Suicide', description = 'Kill your current player ped', tab = 'player', type = 'action', requiresConfirm = true },
    { id = 'player.drivingStyle', label = 'Autopilot Driving Style', description = 'Choose how the AI driver handles traffic', tab = 'player', type = 'select', values = drivingStyles },
    { id = 'player.drivingSpeed', label = 'Autopilot Speed', description = 'Choose the autopilot cruise speed', tab = 'player', type = 'select', values = values({ { '30 km/h', 8.33 }, { '50 km/h', 13.89 }, { '80 km/h', 22.22 }, { '120 km/h', 33.33 }, { '160 km/h', 44.44 } }) },
    { id = 'player.autopilotWaypoint', label = 'Drive To Waypoint', description = 'Let the current vehicle drive to your waypoint', tab = 'player', type = 'action' },
    { id = 'player.autopilotWander', label = 'Drive Around Randomly', description = 'Let the current vehicle wander using the selected style', tab = 'player', type = 'action' },
    { id = 'player.autopilotStop', label = 'Stop Autopilot', description = 'Stop the active AI driving task', tab = 'player', type = 'action' },
    { id = 'player.scenario', label = 'Start Scenario', description = 'Run any valid GTA scenario by name', tab = 'player', type = 'prompt', prompt = { title = 'Start Player Scenario', fields = { { name = 'scenario', label = 'Scenario', placeholder = 'WORLD_HUMAN_COP_IDLES' } } } },
    { id = 'player.stopScenario', label = 'Stop Scenario', description = 'Stop the current scenario or scripted task', tab = 'player', type = 'action' },
    { id = 'player.walkingStyle', label = 'Walking Style', description = 'Apply a vMenu-compatible movement style', tab = 'player', type = 'select', values = values({ { 'Normal', 'normal' }, { 'Injured', 'injured' }, { 'Tough Guy', 'tough' }, { 'Femme', 'femme' }, { 'Gangster', 'gangster' }, { 'Posh', 'posh' }, { 'Sexy', 'sexy' }, { 'Business', 'business' }, { 'Drunk', 'drunk' }, { 'Hipster', 'hipster' } }) },
    { id = 'player.facialExpression', label = 'Facial Expression', description = 'Set the idle facial expression for the current ped', tab = 'player', type = 'select', values = values({ { 'Normal', 'mood_Normal_1' }, { 'Happy', 'mood_Happy_1' }, { 'Angry', 'mood_Angry_1' }, { 'Aiming', 'mood_Aiming_1' }, { 'Injured', 'mood_Injured_1' }, { 'Stressed', 'mood_stressed_1' }, { 'Smug', 'mood_smug_1' }, { 'Sulk', 'mood_sulk_1' } }) },
    { id = 'player.illuminatedClothing', label = 'Illuminated Clothing Style', description = 'Set illuminated clothing to on, off, fade or flash', tab = 'player', type = 'select', values = values({ { 'On', 0 }, { 'Off', 1 }, { 'Fade', 2 }, { 'Flash', 3 } }) },
    { id = 'player.applyTattoo', label = 'Apply Tattoo / Badge', description = 'Apply a streamed or base-game decoration by collection and overlay', tab = 'player', type = 'prompt', prompt = { title = 'Apply Tattoo or Badge', fields = { { name = 'collection', label = 'Collection', placeholder = 'mpbusiness_overlays' }, { name = 'overlay', label = 'Overlay', placeholder = 'MP_Buis_M_Neck_000' } } } },

    -- Vehicle Options and Personal Vehicle parity.
    { id = 'vehicle.freeze', label = 'Freeze Vehicle', description = 'Lock the current vehicle in place', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.invisible', label = 'Vehicle Visibility', description = 'Hide the current vehicle while keeping collision', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.engineAlwaysOn', label = 'Engine Always On', description = 'Keep the last vehicle engine running after you exit', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.noSiren', label = 'Disable Siren', description = 'Silence the current emergency vehicle siren', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.noHelmet', label = 'No Bike Helmet', description = 'Prevent automatic helmets and remove the current helmet', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.anchorBoat', label = 'Anchor Boat', description = 'Anchor the current boat when the location permits it', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.flashHighbeams', label = 'Flash Highbeams On Honk', description = 'Flash high beams while the horn control is held', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.infiniteFuel', label = 'Infinite Fuel', description = 'Continuously refill the current vehicle fuel level', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.showHealth', label = 'Show Vehicle Health', description = 'Show engine, body and tank health while driving', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.autoRepair', label = 'Auto Repair', description = 'Automatically repair catastrophic vehicle damage', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.strongWheels', label = 'Strong Wheels', description = 'Prevent vehicle tyres from bursting', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.preventEngineDamage', label = 'Prevent Engine Damage', description = 'Keep the engine from taking damage', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.preventVisualDamage', label = 'Prevent Visual Damage', description = 'Prevent visible deformation and body damage', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.preventRampDamage', label = 'Prevent Ramp Damage', description = 'Protect ramp vehicles from ramp-use damage', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.bulletproofTyres', label = 'Bulletproof Tyres', description = 'Prevent tyres from being burst by gunfire', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.lowGripTyres', label = 'Low Grip Tyres', description = 'Enable low-grip tyre handling on the current vehicle', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.torqueEnabled', label = 'Enable Torque Multiplier', description = 'Continuously apply the selected engine torque multiplier', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.powerEnabled', label = 'Enable Power Multiplier', description = 'Continuously apply the selected engine power multiplier', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.defaultRadioEnabled', label = 'Enable Default Radio Station', description = 'Apply the selected station whenever you enter a vehicle', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.defaultRadioStation', label = 'Set Default Radio Station', description = 'Choose the station used for newly entered vehicles', tab = 'vehicle', type = 'select', values = radioStations },
    { id = 'vehicle.plateType', label = 'License Plate Type', description = 'Apply a GTA license plate style to the current vehicle', tab = 'vehicle', type = 'select', values = values({ { 'Blue on white 1', 0 }, { 'Blue on white 2', 1 }, { 'Blue on white 3', 2 }, { 'Yellow on blue', 3 }, { 'Yellow on black', 4 }, { 'North Yankton', 5 }, { 'E-Cola', 6 }, { 'Las Venturas', 7 }, { 'Liberty City', 8 }, { 'LS Car Meet', 9 }, { 'LSPD', 10 }, { 'Pounders', 11 }, { 'Sprunk', 12 } }) },
    { id = 'vehicle.enveffScale', label = 'Vehicle Environment Effect', description = 'Set the vehicle environment reflection effect', tab = 'vehicle', type = 'slider', min = 0, max = 1, step = 0.05 },
    { id = 'vehicle.alarm', label = 'Toggle Vehicle Alarm', description = 'Start or stop the current vehicle alarm', tab = 'vehicle', type = 'action' },
    { id = 'vehicle.cycleSeat', label = 'Cycle Vehicle Seat', description = 'Move to the next free seat in the current vehicle', tab = 'vehicle', type = 'action' },
    { id = 'vehicle.lights', label = 'Vehicle Lights', description = 'Set automatic, off, on or high-beam lighting', tab = 'vehicle', type = 'select', values = lightValues },
    { id = 'vehicle.doors', label = 'Vehicle Doors', description = 'Open, close, remove or restore vehicle doors', tab = 'vehicle', type = 'select', values = doorValues },
    { id = 'vehicle.deleteRemovedDoors', label = 'Delete Removed Doors', description = 'Delete detached doors instead of dropping them into the world', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.windows', label = 'Vehicle Windows', description = 'Raise or lower front, rear or all windows', tab = 'vehicle', type = 'select', values = windowValues },
    { id = 'vehicle.extras', label = 'Toggle Vehicle Extra', description = 'Toggle an extra by ID (0-20)', tab = 'vehicle', type = 'prompt', prompt = { title = 'Toggle Vehicle Extra', fields = { { name = 'extra', label = 'Extra ID', placeholder = '1' } } } },
    { id = 'vehicle.tyres', label = 'Fix / Destroy Tyres', description = 'Repair or burst one tyre or all tyres', tab = 'vehicle', type = 'select', values = values({ { 'Fix all', 'fix_all' }, { 'Burst all', 'burst_all' }, { 'Fix front left', 'fix_0' }, { 'Fix front right', 'fix_1' }, { 'Burst front left', 'burst_0' }, { 'Burst front right', 'burst_1' }, { 'Fix rear left', 'fix_4' }, { 'Fix rear right', 'fix_5' }, { 'Burst rear left', 'burst_4' }, { 'Burst rear right', 'burst_5' } }) },
    { id = 'vehicle.dirtLevel', label = 'Set Dirt Level', description = 'Set current vehicle dirt from clean to filthy', tab = 'vehicle', type = 'slider', min = 0, max = 15, step = 0.5 },
    { id = 'vehicle.personalSet', label = 'Set Personal Vehicle', description = 'Use the current vehicle for remote personal controls', tab = 'vehicle', type = 'action' },
    { id = 'vehicle.personalEngine', label = 'Personal Vehicle Engine', description = 'Toggle the personal vehicle engine remotely', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.personalLights', label = 'Personal Vehicle Lights', description = 'Control personal vehicle lights remotely', tab = 'vehicle', type = 'select', values = lightValues },
    { id = 'vehicle.personalStance', label = 'Personal Vehicle Stance', description = 'Use the normal or reduced-drift suspension stance', tab = 'vehicle', type = 'select', values = values({ { 'Normal', false }, { 'Lowered', true } }) },
    { id = 'vehicle.personalKickPassengers', label = 'Kick Personal Vehicle Passengers', description = 'Ask every passenger to leave the personal vehicle', tab = 'vehicle', type = 'action' },
    { id = 'vehicle.personalLock', label = 'Lock Personal Vehicle', description = 'Lock all personal vehicle doors', tab = 'vehicle', type = 'action' },
    { id = 'vehicle.personalUnlock', label = 'Unlock Personal Vehicle', description = 'Unlock all personal vehicle doors', tab = 'vehicle', type = 'action' },
    { id = 'vehicle.personalDoors', label = 'Personal Vehicle Doors', description = 'Control personal vehicle doors remotely', tab = 'vehicle', type = 'select', values = doorValues },
    { id = 'vehicle.personalHorn', label = 'Sound Personal Vehicle Horn', description = 'Sound the personal vehicle horn for one second', tab = 'vehicle', type = 'action' },
    { id = 'vehicle.personalAlarm', label = 'Personal Vehicle Alarm', description = 'Toggle the personal vehicle alarm remotely', tab = 'vehicle', type = 'action' },
    { id = 'vehicle.personalBlip', label = 'Personal Vehicle Blip', description = 'Show the personal vehicle on the map', tab = 'vehicle', type = 'toggle' },
    { id = 'vehicle.personalExclusive', label = 'Exclusive Personal Vehicle Driver', description = 'Only you may occupy the personal vehicle driver seat', tab = 'vehicle', type = 'toggle' },
    -- Hidden capability records protect the dedicated customizer while preserving
    -- vMenu's separate Mod/Colors/Liveries/Components/Underglow ACE controls.
    { id = 'vehicle.customMods', label = 'Vehicle Modifications', description = 'Modify visual and performance vehicle parts', tab = 'vehicle_custom', type = 'action', hidden = true, capability = true },
    { id = 'vehicle.customColors', label = 'Vehicle Colors', description = 'Change indexed, custom and paint-finish vehicle colors', tab = 'vehicle_custom', type = 'action', hidden = true, capability = true },
    { id = 'vehicle.customLiveries', label = 'Vehicle Liveries', description = 'Change native vehicle liveries', tab = 'vehicle_custom', type = 'action', hidden = true, capability = true },
    { id = 'vehicle.customExtras', label = 'Vehicle Extras', description = 'Toggle model-specific vehicle extras', tab = 'vehicle_custom', type = 'action', hidden = true, capability = true },
    { id = 'vehicle.customUnderglow', label = 'Vehicle Underglow', description = 'Change vehicle neon lights and colors', tab = 'vehicle_custom', type = 'action', hidden = true, capability = true },

    -- Time and weather parity.
    { id = 'world.exactTime', label = 'Set Exact Time', description = 'Set global hour and minute', tab = 'world', type = 'prompt', prompt = { title = 'Set Exact Time', fields = { { name = 'hour', label = 'Hour (0-23)', placeholder = '12' }, { name = 'minute', label = 'Minute (0-59)', placeholder = '0' } } } },
    { id = 'world.dynamicWeather', label = 'Dynamic Weather', description = 'Cycle global weather automatically', tab = 'world', type = 'toggle' },
    { id = 'world.vehicleBlackout', label = 'Vehicle Lights Blackout', description = 'Disable vehicle lights during blackout', tab = 'world', type = 'toggle' },
    { id = 'world.snowEffects', label = 'Snow Effects', description = 'Force snow footsteps, trails and ground effects', tab = 'world', type = 'toggle' },
    { id = 'world.randomClouds', label = 'Randomize Clouds', description = 'Apply a random cloud hat to the sky', tab = 'world', type = 'action' },
    { id = 'world.removeClouds', label = 'Remove All Clouds', description = 'Clear the active cloud hat', tab = 'world', type = 'action' },

    -- Weapon Options, parachute and loadout parity.
    { id = 'weapons.noReload', label = 'No Reload', description = 'Keep the active weapon magazine full', tab = 'weapons', type = 'toggle' },
    { id = 'weapons.setAllAmmo', label = 'Set All Ammo Count', description = 'Set ammunition for every carried weapon', tab = 'weapons', type = 'prompt', prompt = { title = 'Set All Ammo', fields = { { name = 'ammo', label = 'Ammo', placeholder = '250' } } } },
    { id = 'weapons.refillAllAmmo', label = 'Refill All Ammo', description = 'Refill every carried weapon to maximum ammunition', tab = 'weapons', type = 'action' },
    { id = 'weapons.removeWeapon', label = 'Remove Weapon By Name', description = 'Remove one carried weapon without clearing the loadout', tab = 'weapons', type = 'prompt', prompt = { title = 'Remove Weapon', fields = { { name = 'weapon', label = 'Weapon model', placeholder = 'weapon_pistol' } } } },
    { id = 'weapons.primaryParachute', label = 'Toggle Primary Parachute', description = 'Equip or remove the primary parachute', tab = 'weapons', type = 'action' },
    { id = 'weapons.primaryChuteStyle', label = 'Primary Chute Style', description = 'Choose the primary parachute canopy style', tab = 'weapons', type = 'select', values = parachuteStyles },
    { id = 'weapons.reserveParachute', label = 'Add Reserve Parachute', description = 'Add a reserve parachute to the current player', tab = 'weapons', type = 'action' },
    { id = 'weapons.unlimitedParachutes', label = 'Unlimited Parachutes', description = 'Automatically replace used parachutes', tab = 'weapons', type = 'toggle' },
    { id = 'weapons.autoEquipParachute', label = 'Auto Equip Parachutes', description = 'Equip parachutes when entering aircraft', tab = 'weapons', type = 'toggle' },
    { id = 'weapons.reserveChuteStyle', label = 'Reserve Chute Style', description = 'Choose the reserve parachute canopy style', tab = 'weapons', type = 'select', values = parachuteStyles },
    { id = 'weapons.parachuteSmoke', label = 'Parachute Smoke Color', description = 'Choose a parachute smoke trail color or turn the trail off', tab = 'weapons', type = 'select', values = values({ { 'No smoke', 'off' }, { 'White', '255,255,255' }, { 'Red', '255,40,40' }, { 'Orange', '255,120,20' }, { 'Yellow', '255,220,20' }, { 'Green', '40,220,80' }, { 'Blue', '40,120,255' }, { 'Purple', '150,60,255' }, { 'Pink', '255,70,170' }, { 'Black', '15,15,15' } }) },
    { id = 'weapons.renameLoadout', label = 'Rename Weapon Loadout', description = 'Rename a saved Cortex or imported vMenu loadout', tab = 'weapons', type = 'prompt', prompt = { title = 'Rename Loadout', fields = { { name = 'from', label = 'Current name', placeholder = 'Patrol' }, { name = 'to', label = 'New name', placeholder = 'Supervisor' } } } },
    { id = 'weapons.cloneLoadout', label = 'Clone Weapon Loadout', description = 'Copy a saved loadout into a new slot', tab = 'weapons', type = 'prompt', prompt = { title = 'Clone Loadout', fields = { { name = 'from', label = 'Source name', placeholder = 'Patrol' }, { name = 'to', label = 'Clone name', placeholder = 'Patrol Copy' } } } },
    { id = 'weapons.defaultLoadout', label = 'Set Default Loadout', description = 'Choose the loadout restored on respawn', tab = 'weapons', type = 'prompt', prompt = { title = 'Set Default Loadout', fields = { { name = 'name', label = 'Loadout name', placeholder = 'Patrol' } } } },
    { id = 'weapons.replaceLoadout', label = 'Replace Weapon Loadout', description = 'Replace a saved loadout with the weapons currently carried', tab = 'weapons', type = 'prompt', requiresConfirm = true, prompt = { title = 'Replace Loadout', fields = { { name = 'name', label = 'Loadout name', placeholder = 'Patrol' } } } },
    { id = 'weapons.restoreLoadoutOnRespawn', label = 'Restore Default Loadout On Respawn', description = 'Equip the default loadout after respawn', tab = 'weapons', type = 'toggle' },

    -- Misc, developer and connection options.
    { id = 'dev.showTime', label = 'Show Time On Screen', description = 'Display the current synchronized game time', tab = 'dev', type = 'toggle' },
    { id = 'dev.hideRadar', label = 'Hide Radar', description = 'Hide only the minimap while leaving the rest of the HUD visible', tab = 'dev', type = 'toggle' },
    { id = 'dev.locationDisplay', label = 'Location Display', description = 'Show street, cross street and heading without coordinate values', tab = 'dev', type = 'toggle' },
    { id = 'dev.overheadNames', label = 'Show Player Names', description = 'Draw nearby player names and server IDs overhead', tab = 'dev', type = 'toggle' },
    { id = 'dev.joinQuitNotifications', label = 'Join / Quit Notifications', description = 'Show player connection and disconnect notices', tab = 'dev', type = 'toggle' },
    { id = 'dev.deathNotifications', label = 'Death Notifications', description = 'Show server-wide player death notices', tab = 'dev', type = 'toggle' },
    { id = 'dev.driftMode', label = 'Drift Mode', description = 'Reduce rear grip while the drift key is held', tab = 'dev', type = 'toggle' },
    { id = 'dev.locationBlips', label = 'Location Blips', description = 'Show imported vMenu teleport locations on the map', tab = 'dev', type = 'toggle' },
    { id = 'dev.entityInspector', label = 'Entity Inspector', description = 'Outline the aimed entity and show model, handle and owner', tab = 'dev', type = 'toggle' },
    { id = 'dev.vehicleDimensions', label = 'Show Vehicle Dimensions', description = 'Outline nearby vehicles and draw their model bounds', tab = 'dev', type = 'toggle' },
    { id = 'dev.propDimensions', label = 'Show Prop Dimensions', description = 'Outline nearby objects and draw their model bounds', tab = 'dev', type = 'toggle' },
    { id = 'dev.pedDimensions', label = 'Show Ped Dimensions', description = 'Outline nearby peds and draw their model bounds', tab = 'dev', type = 'toggle' },
    { id = 'dev.entityHandles', label = 'Show Entity Handles', description = 'Add entity handles to dimension labels', tab = 'dev', type = 'toggle' },
    { id = 'dev.entityModels', label = 'Show Entity Models', description = 'Add model hashes to dimension labels', tab = 'dev', type = 'toggle' },
    { id = 'dev.entityOwners', label = 'Show Network Owners', description = 'Add authoritative network-owner IDs to dimension labels', tab = 'dev', type = 'toggle' },
    { id = 'dev.dimensionRadius', label = 'Show Dimensions Radius', description = 'Set the nearby entity inspection radius', tab = 'dev', type = 'slider', min = 10, max = 200, step = 5 },
    { id = 'dev.lockCameraHorizontal', label = 'Lock Camera Horizontal Rotation', description = 'Hold the gameplay camera at its current heading', tab = 'dev', type = 'toggle' },
    { id = 'dev.lockCameraVertical', label = 'Lock Camera Vertical Rotation', description = 'Hold the gameplay camera at its current pitch', tab = 'dev', type = 'toggle' },
    { id = 'dev.spawnEntity', label = 'Spawn New Entity', description = 'Spawn a vehicle, ped or object and place it in front of you', tab = 'dev', type = 'prompt', prompt = { title = 'Spawn Entity', fields = { { name = 'type', label = 'Type', placeholder = 'object | ped | vehicle' }, { name = 'model', label = 'Model', placeholder = 'prop_barrel_02a' } } } },
    { id = 'dev.clearSpawnedEntities', label = 'Clear Spawned Entities', description = 'Delete entities created by the Cortex entity spawner', tab = 'dev', type = 'action', requiresConfirm = true },
    { id = 'dev.confirmEntityPlacement', label = 'Confirm Entity Position', description = 'Finish positioning the entity currently being placed', tab = 'dev', type = 'action' },
    { id = 'dev.cancelEntityPlacement', label = 'Cancel Entity Placement', description = 'Delete the entity currently being positioned', tab = 'dev', type = 'action' },
    { id = 'dev.duplicateEntityPlacement', label = 'Confirm Position And Duplicate', description = 'Finish the current entity and start placing a duplicate', tab = 'dev', type = 'action' },
    { id = 'dev.timecycle', label = 'Timecycle Modifier', description = 'Apply a timecycle modifier and strength', tab = 'dev', type = 'prompt', prompt = { title = 'Timecycle Modifier', fields = { { name = 'name', label = 'Modifier', placeholder = 'scanline_cam_cheap' }, { name = 'strength', label = 'Strength (0-1)', placeholder = '1.0' } } } },
    { id = 'dev.clearTimecycle', label = 'Clear Timecycle Modifier', description = 'Remove the active timecycle modifier', tab = 'dev', type = 'action' },
    { id = 'options.teleportWaypointKey', label = 'Teleport Waypoint Keybind', description = 'Enable the configurable F7 waypoint shortcut', tab = 'options', type = 'toggle' },
    { id = 'options.spawnInsideVehicle', label = 'Spawn Inside Vehicle', description = 'Seat yourself in newly spawned vehicles', tab = 'options', type = 'toggle' },
    { id = 'options.disablePlaneTurbulence', label = 'Disable Plane Turbulence', description = 'Remove turbulence from planes you occupy', tab = 'options', type = 'toggle' },
    { id = 'options.disableHelicopterTurbulence', label = 'Disable Helicopter Turbulence', description = 'Remove turbulence from helicopters you occupy', tab = 'options', type = 'toggle' },
    { id = 'options.disablePrivateMessages', label = 'Disable Private Messages', description = 'Refuse vMenu-compatible private admin messages', tab = 'options', type = 'toggle' },
    { id = 'options.disableControllerSupport', label = 'Disable Controller Support', description = 'Keep Cortex navigation on keyboard and mouse only', tab = 'options', type = 'toggle' },
    { id = 'options.recordingControls', label = 'Recording Controls', description = 'Enable the configured Rockstar recording hotkeys', tab = 'options', type = 'toggle' },
    { id = 'options.minimapControls', label = 'Minimap Controls', description = 'Toggle expanded radar with the multiplayer-info control', tab = 'options', type = 'toggle' },
    { id = 'options.fingerPointControls', label = 'Finger Point Controls', description = 'Enable the configurable finger-point shortcut', tab = 'options', type = 'toggle' },
    { id = 'options.quitSession', label = 'Quit Session', description = 'Leave the network session while remaining connected', tab = 'options', type = 'action', requiresConfirm = true },
    { id = 'options.rejoinSession', label = 'Re-join Session', description = 'Attempt to rejoin after leaving the network session', tab = 'options', type = 'action' },
    { id = 'options.quitGame', label = 'Quit Game', description = 'Exit GTA V after a short warning', tab = 'options', type = 'action', requiresConfirm = true },
    { id = 'options.disconnect', label = 'Disconnect From Server', description = 'Leave the current server session', tab = 'options', type = 'action', requiresConfirm = true },

    -- Legacy vMenu voice surface. Modern voice resources may override these natives.
    { id = 'voice.enabled', label = 'Enable Voice Chat', description = 'Enable or disable the native FiveM voice channel', tab = 'voice', type = 'toggle' },
    { id = 'voice.showSpeaker', label = 'Show Current Speaker', description = 'Show the names of nearby players who are speaking', tab = 'voice', type = 'toggle' },
    { id = 'voice.showStatus', label = 'Show Microphone Status', description = 'Show whether your local voice is transmitting', tab = 'voice', type = 'toggle' },
    { id = 'voice.proximity', label = 'Voice Chat Proximity', description = 'Set the native talker proximity', tab = 'voice', type = 'select', values = values({ { 'Whisper (2m)', 2.0 }, { 'Normal (8m)', 8.0 }, { 'Shout (20m)', 20.0 }, { 'Global', 9999.0 } }) },
    { id = 'voice.channel', label = 'Voice Chat Channel', description = 'Join a numbered native voice channel, or 0 to leave', tab = 'voice', type = 'prompt', prompt = { title = 'Voice Channel', fields = { { name = 'channel', label = 'Channel (0-65535)', placeholder = '0' } } } },
}

EsAdminVmenuActions = { actions = actions }

local known = {}
for _, action in ipairs(EsAdminActions.actions) do
    known[action.id] = true
end
for _, action in ipairs(actions) do
    if not known[action.id] then
        EsAdminActions.actions[#EsAdminActions.actions + 1] = action
        known[action.id] = true
    end
end

local tabKnown = {}
for _, tab in ipairs(EsAdminActions.tabs) do
    tabKnown[tab.id] = true
end
if not tabKnown.voice then
    EsAdminActions.tabs[#EsAdminActions.tabs + 1] = { id = 'voice', label = 'Voice' }
end
if not tabKnown.migration then
    EsAdminActions.tabs[#EsAdminActions.tabs + 1] = { id = 'migration', label = 'vMenu Import' }
end
if not tabKnown.bans then
    EsAdminActions.tabs[#EsAdminActions.tabs + 1] = { id = 'bans', label = 'Banned Players' }
end
if not tabKnown.imported then
    EsAdminActions.tabs[#EsAdminActions.tabs + 1] = { id = 'imported', label = 'Imported Data' }
end

Config.Permissions.voice = Config.Permissions.voice or 'cortex-admin.voice'
Config.Permissions.migration = Config.Permissions.migration or 'cortex-admin.server'
Config.Permissions.bans = Config.Permissions.bans or 'cortex-admin.server'

for actionId, permission in pairs({
    ['player.waypoint'] = 'cortex-admin.server.teleport',
    ['player.spectate'] = 'cortex-admin.server.spectate',
    ['player.message'] = 'cortex-admin.server.message',
    ['player.identifiers'] = 'cortex-admin.server.identifiers',
    ['player.viewBans'] = 'cortex-admin.server.ban',
    ['player.unban'] = 'cortex-admin.server.ban',
    ['migration.read'] = 'cortex-admin.server',
    ['migration.import'] = 'cortex-admin.server',
}) do
    Config.ActionPermissions[actionId] = Config.ActionPermissions[actionId] or permission
end

local actionPermissionDefaults = {
    player = 'cortex-admin.player',
    vehicle = 'cortex-admin.vehicle',
    world = 'cortex-admin.world',
    weapons = 'cortex-admin.weapons',
    dev = 'cortex-admin.dev',
    options = 'cortex-admin.options',
    voice = 'cortex-admin.voice',
    vehicle_custom = 'cortex-admin.vehicle',
}
for _, action in ipairs(actions) do
    local tab = action.tab
    Config.ActionPermissions[action.id] = Config.ActionPermissions[action.id] or actionPermissionDefaults[tab]
end

-- Each entry is checked as an alias in addition to Cortex/QBX permissions.
-- Menu/All aliases intentionally mirror vMenu's own fallback hierarchy.
Config.VmenuAcePermissions = Config.VmenuAcePermissions or {}

local function ace(actionId, ...)
    Config.VmenuAcePermissions[actionId] = { ... }
end

local playerMenu = { 'vMenu.PlayerOptions.All', 'vMenu.Everything' }
local vehicleMenu = { 'vMenu.VehicleOptions.All', 'vMenu.Everything' }
local weaponMenu = { 'vMenu.WeaponOptions.All', 'vMenu.Everything' }
local miscMenu = { 'vMenu.MiscSettings.All', 'vMenu.Everything' }
local voiceMenu = { 'vMenu.VoiceChat.All', 'vMenu.Everything' }

local function withFallback(permission, fallback)
    local out = { permission }
    for index = 1, #fallback do out[#out + 1] = fallback[index] end
    return out
end

local aliasById = {
    ['player.godmode'] = 'vMenu.PlayerOptions.God', ['player.invisible'] = 'vMenu.PlayerOptions.Invisible',
    ['player.infiniteStamina'] = 'vMenu.PlayerOptions.UnlimitedStamina', ['player.fastRun'] = 'vMenu.PlayerOptions.FastRun',
    ['player.fastSwim'] = 'vMenu.PlayerOptions.FastSwim', ['player.superjump'] = 'vMenu.PlayerOptions.Superjump',
    ['player.noRagdoll'] = 'vMenu.PlayerOptions.NoRagdoll', ['player.neverWanted'] = 'vMenu.PlayerOptions.NeverWanted',
    ['player.setWantedLevel'] = 'vMenu.PlayerOptions.SetWanted', ['player.clearWanted'] = 'vMenu.PlayerOptions.SetWanted',
    ['player.everyoneIgnores'] = 'vMenu.PlayerOptions.Ignored', ['player.stayInVehicle'] = 'vMenu.PlayerOptions.StayInVehicle',
    ['player.freeze'] = 'vMenu.PlayerOptions.Freeze', ['player.cleanPlayer'] = 'vMenu.PlayerOptions.CleanPlayer',
    ['player.dryPlayer'] = 'vMenu.PlayerOptions.DryPlayer', ['player.wetPlayer'] = 'vMenu.PlayerOptions.WetPlayer',
    ['player.setBloodLevel'] = 'vMenu.PlayerOptions.SetBlood', ['player.heal'] = 'vMenu.PlayerOptions.MaxHealth',
    ['player.armor'] = 'vMenu.PlayerOptions.MaxArmor', ['player.scenario'] = 'vMenu.PlayerOptions.Scenarios',
    ['player.stopScenario'] = 'vMenu.PlayerOptions.Scenarios', ['player.autopilotWaypoint'] = 'vMenu.PlayerOptions.VehicleAutoPilotMenu',
    ['player.autopilotWander'] = 'vMenu.PlayerOptions.VehicleAutoPilotMenu', ['player.autopilotStop'] = 'vMenu.PlayerOptions.VehicleAutoPilotMenu',
    ['player.drivingStyle'] = 'vMenu.PlayerOptions.VehicleAutoPilotMenu', ['player.drivingSpeed'] = 'vMenu.PlayerOptions.VehicleAutoPilotMenu',
    ['vehicle.invincible'] = 'vMenu.VehicleOptions.God', ['vehicle.keepClean'] = 'vMenu.VehicleOptions.KeepClean',
    ['vehicle.repair'] = 'vMenu.VehicleOptions.Repair', ['vehicle.clean'] = 'vMenu.VehicleOptions.Wash',
    ['vehicle.engine'] = 'vMenu.VehicleOptions.Engine', ['vehicle.destroyEngine'] = 'vMenu.VehicleOptions.DestroyEngine',
    ['vehicle.bikeSeatbelt'] = 'vMenu.VehicleOptions.BikeSeatbelt', ['vehicle.speedLimiter'] = 'vMenu.VehicleOptions.SpeedLimiter',
    ['vehicle.changePlate'] = 'vMenu.VehicleOptions.ChangePlate', ['vehicle.flip'] = 'vMenu.VehicleOptions.Flip',
    ['vehicle.delete'] = 'vMenu.VehicleOptions.Delete', ['vehicle.freeze'] = 'vMenu.VehicleOptions.Freeze',
    ['vehicle.invisible'] = 'vMenu.VehicleOptions.Invisible', ['vehicle.engineAlwaysOn'] = 'vMenu.VehicleOptions.EngineAlwaysOn',
    ['vehicle.noSiren'] = 'vMenu.VehicleOptions.NoSiren', ['vehicle.noHelmet'] = 'vMenu.VehicleOptions.NoHelmet',
    ['vehicle.anchorBoat'] = 'vMenu.VehicleOptions.AnchorBoat', ['vehicle.flashHighbeams'] = 'vMenu.VehicleOptions.FlashHighbeamsOnHonk',
    ['vehicle.infiniteFuel'] = 'vMenu.VehicleOptions.InfiniteFuel', ['vehicle.alarm'] = 'vMenu.VehicleOptions.Alarm',
    ['vehicle.cycleSeat'] = 'vMenu.VehicleOptions.CycleSeats', ['vehicle.lights'] = 'vMenu.VehicleOptions.Lights',
    ['vehicle.doors'] = 'vMenu.VehicleOptions.Doors', ['vehicle.windows'] = 'vMenu.VehicleOptions.Windows',
    ['vehicle.extras'] = 'vMenu.VehicleOptions.Components', ['vehicle.tyres'] = 'vMenu.VehicleOptions.FixOrDestroyTires',
    ['vehicle.torqueMultiplier'] = 'vMenu.VehicleOptions.TorqueMultiplier', ['vehicle.powerMultiplier'] = 'vMenu.VehicleOptions.PowerMultiplier',
    ['weapons.giveAll'] = 'vMenu.WeaponOptions.GetAll', ['weapons.removeAll'] = 'vMenu.WeaponOptions.RemoveAll',
    ['weapons.infiniteAmmo'] = 'vMenu.WeaponOptions.UnlimitedAmmo', ['weapons.noReload'] = 'vMenu.WeaponOptions.NoReload',
    ['weapons.setAllAmmo'] = 'vMenu.WeaponOptions.SetAllAmmo', ['weapons.parachute'] = 'vMenu.WeaponOptions.Parachute',
    ['teleport.waypoint'] = 'vMenu.MiscSettings.TeleportToWp', ['teleport.coords'] = 'vMenu.MiscSettings.TeleportToCoord',
    ['teleport.saveLocation'] = 'vMenu.MiscSettings.TeleportSaveLocation', ['dev.showCoords'] = 'vMenu.MiscSettings.ShowCoordinates',
    ['dev.nightVision'] = 'vMenu.MiscSettings.NightVision', ['dev.thermalVision'] = 'vMenu.MiscSettings.ThermalVision',
    ['dev.playerBlips'] = 'vMenu.MiscSettings.PlayerBlips', ['dev.overheadNames'] = 'vMenu.MiscSettings.OverheadNames',
    ['dev.locationBlips'] = 'vMenu.MiscSettings.LocationBlips', ['dev.entityInspector'] = 'vMenu.MiscSettings.DevTools',
    ['dev.spawnEntity'] = 'vMenu.MiscSettings.EntitySpawner', ['world.time'] = 'vMenu.TimeOptions.SetTime',
    ['world.exactTime'] = 'vMenu.TimeOptions.SetTime', ['world.freezeTime'] = 'vMenu.TimeOptions.FreezeTime',
    ['world.weather'] = 'vMenu.WeatherOptions.SetWeather', ['world.dynamicWeather'] = 'vMenu.WeatherOptions.Dynamic',
    ['world.blackout'] = 'vMenu.WeatherOptions.Blackout', ['world.vehicleBlackout'] = 'vMenu.WeatherOptions.VehBlackout',
}

for actionId, permission in pairs(aliasById) do
    local fallback = actionId:sub(1, 7) == 'vehicle' and vehicleMenu
        or actionId:sub(1, 7) == 'weapons' and weaponMenu
        or actionId:sub(1, 5) == 'world' and { 'vMenu.TimeOptions.All', 'vMenu.WeatherOptions.All', 'vMenu.Everything' }
        or actionId:sub(1, 3) == 'dev' and miscMenu
        or actionId:sub(1, 8) == 'teleport' and miscMenu
        or playerMenu
    Config.VmenuAcePermissions[actionId] = withFallback(permission, fallback)
end

for _, action in ipairs(actions) do
    if not Config.VmenuAcePermissions[action.id] then
        local fallback = action.tab == 'vehicle' and vehicleMenu
            or action.tab == 'weapons' and weaponMenu
            or action.tab == 'voice' and voiceMenu
            or action.tab == 'dev' and miscMenu
            or action.tab == 'options' and miscMenu
            or action.tab == 'world' and { 'vMenu.TimeOptions.All', 'vMenu.WeatherOptions.All', 'vMenu.Everything' }
            or playerMenu
        Config.VmenuAcePermissions[action.id] = fallback
    end
end

ace('player.goto', 'vMenu.OnlinePlayers.Teleport', 'vMenu.OnlinePlayers.All', 'vMenu.Everything')
ace('player.bring', 'vMenu.OnlinePlayers.Summon', 'vMenu.OnlinePlayers.All', 'vMenu.Everything')
ace('player.waypoint', 'vMenu.OnlinePlayers.Waypoint', 'vMenu.OnlinePlayers.All', 'vMenu.Everything')
ace('player.spectate', 'vMenu.OnlinePlayers.Spectate', 'vMenu.OnlinePlayers.All', 'vMenu.Everything')
ace('player.message', 'vMenu.OnlinePlayers.SendMessage', 'vMenu.OnlinePlayers.All', 'vMenu.Everything')
ace('player.identifiers', 'vMenu.OnlinePlayers.Identifiers', 'vMenu.OnlinePlayers.All', 'vMenu.Everything')
ace('player.kill', 'vMenu.OnlinePlayers.Kill', 'vMenu.OnlinePlayers.All', 'vMenu.Everything')
ace('player.kick', 'vMenu.OnlinePlayers.Kick', 'vMenu.OnlinePlayers.All', 'vMenu.Everything')
ace('player.ban', 'vMenu.OnlinePlayers.TempBan', 'vMenu.OnlinePlayers.PermBan', 'vMenu.OnlinePlayers.All', 'vMenu.Everything')
ace('player.unban', 'vMenu.OnlinePlayers.Unban', 'vMenu.OnlinePlayers.All', 'vMenu.Everything')
ace('player.viewBans', 'vMenu.OnlinePlayers.ViewBannedPlayers', 'vMenu.OnlinePlayers.All', 'vMenu.Everything')
ace('player.sitInVehicle', 'vMenu.OnlinePlayers.Teleport', 'vMenu.OnlinePlayers.All', 'vMenu.Everything')
ace('player.noclip', 'vMenu.NoClip', 'vMenu.Everything')

local vehicleSpawnerMenu = { 'vMenu.VehicleSpawner.All', 'vMenu.VehicleSpawner.SpawnByName', 'vMenu.VehicleSpawner.Addon', 'vMenu.Everything' }
local savedVehicleMenu = { 'vMenu.SavedVehicles.All', 'vMenu.SavedVehicles.Menu', 'vMenu.Everything' }
local appearanceMenu = { 'vMenu.PlayerAppearance.All', 'vMenu.Everything' }
local loadoutMenu = { 'vMenu.WeaponLoadouts.All', 'vMenu.WeaponLoadouts.Menu', 'vMenu.Everything' }
local personalVehiclePermissions = {
    ['vehicle.personalSet'] = 'vMenu.PersonalVehicle.Menu',
    ['vehicle.personalEngine'] = 'vMenu.PersonalVehicle.ToggleEngine',
    ['vehicle.personalLights'] = 'vMenu.PersonalVehicle.ToggleLights',
    ['vehicle.personalStance'] = 'vMenu.PersonalVehicle.ToggleStance',
    ['vehicle.personalKickPassengers'] = 'vMenu.PersonalVehicle.KickPassengers',
    ['vehicle.personalLock'] = 'vMenu.PersonalVehicle.LockDoors',
    ['vehicle.personalUnlock'] = 'vMenu.PersonalVehicle.LockDoors',
    ['vehicle.personalDoors'] = 'vMenu.PersonalVehicle.Doors',
    ['vehicle.personalHorn'] = 'vMenu.PersonalVehicle.SoundHorn',
    ['vehicle.personalAlarm'] = 'vMenu.PersonalVehicle.ToggleAlarm',
    ['vehicle.personalBlip'] = 'vMenu.PersonalVehicle.AddBlip',
    ['vehicle.personalExclusive'] = 'vMenu.PersonalVehicle.ExclusiveDriver',
}
for actionId, permission in pairs(personalVehiclePermissions) do
    if actionId == 'vehicle.personalSet' then
        ace(actionId, permission, 'vMenu.PersonalVehicle.All', 'vMenu.Everything')
    else
        ace(actionId, permission, 'vMenu.PersonalVehicle.All', 'vMenu.Everything')
    end
end

for _, actionId in ipairs({ 'vehicle.spawn', 'vehicle.preview' }) do
    Config.VmenuAcePermissions[actionId] = vehicleSpawnerMenu
end
ace('vehicle.personal', 'vMenu.SavedVehicles.Spawn', 'vMenu.SavedVehicles.All', 'vMenu.SavedVehicles.Menu', 'vMenu.Everything')
ace('vehicle.savePersonal', 'vMenu.SavedVehicles.Menu', 'vMenu.SavedVehicles.All', 'vMenu.Everything')
ace('vehicle.customMods', 'vMenu.VehicleOptions.Mod', 'vMenu.VehicleOptions.All', 'vMenu.Everything')
ace('vehicle.customColors', 'vMenu.VehicleOptions.Colors', 'vMenu.VehicleOptions.All', 'vMenu.Everything')
ace('vehicle.customLiveries', 'vMenu.VehicleOptions.Liveries', 'vMenu.VehicleOptions.All', 'vMenu.Everything')
ace('vehicle.customExtras', 'vMenu.VehicleOptions.Components', 'vMenu.VehicleOptions.All', 'vMenu.Everything')
ace('vehicle.customUnderglow', 'vMenu.VehicleOptions.Underglow', 'vMenu.VehicleOptions.All', 'vMenu.Everything')

for _, actionId in ipairs({
    'player.setModel', 'player.randomizeMpFace', 'player.clearPedTattoos', 'player.applyTattoo',
}) do
    ace(actionId, 'vMenu.PlayerAppearance.Customize', table.unpack(appearanceMenu))
end
for _, actionId in ipairs({ 'player.loadMpPed', 'player.loadPed', 'player.setDefaultSavedPed' }) do
    ace(actionId, 'vMenu.PlayerAppearance.SpawnSaved', table.unpack(appearanceMenu))
end
for _, actionId in ipairs({ 'player.saveMpPed', 'player.savePed' }) do
    Config.VmenuAcePermissions[actionId] = appearanceMenu
end

for _, actionId in ipairs({ 'weapons.saveLoadout', 'weapons.deleteLoadout', 'weapons.renameLoadout', 'weapons.cloneLoadout', 'weapons.defaultLoadout' }) do
    Config.VmenuAcePermissions[actionId] = loadoutMenu
end
for _, actionId in ipairs({ 'weapons.loadLoadout', 'weapons.restoreLoadoutOnRespawn' }) do
    ace(actionId, 'vMenu.WeaponLoadouts.Equip', 'vMenu.WeaponLoadouts.EquipOnRespawn', 'vMenu.WeaponLoadouts.All', 'vMenu.Everything')
end

local miscAliases = {
    ['world.clearArea'] = 'vMenu.MiscSettings.ClearArea', ['world.clearVehicles'] = 'vMenu.MiscSettings.ClearArea',
    ['world.clearPeds'] = 'vMenu.MiscSettings.ClearArea', ['world.clearObjects'] = 'vMenu.MiscSettings.ClearArea',
    ['dev.joinQuitNotifications'] = 'vMenu.MiscSettings.JoinQuitNotifs',
    ['dev.deathNotifications'] = 'vMenu.MiscSettings.DeathNotifs',
    ['dev.driftMode'] = 'vMenu.MiscSettings.DriftMode',
    ['options.disconnect'] = 'vMenu.MiscSettings.ConnectionMenu',
    ['options.restorePedOnDeath'] = 'vMenu.MiscSettings.RestoreAppearance',
    ['weapons.restoreLoadoutOnRespawn'] = 'vMenu.MiscSettings.RestoreWeapons',
    ['teleport.loadLocation'] = 'vMenu.MiscSettings.TeleportLocations',
    ['teleport.deleteLocation'] = 'vMenu.MiscSettings.TeleportLocations',
}
for actionId, permission in pairs(miscAliases) do
    ace(actionId, permission, 'vMenu.MiscSettings.All', 'vMenu.Everything')
end

ace('world.randomClouds', 'vMenu.WeatherOptions.RandomizeClouds', 'vMenu.WeatherOptions.All', 'vMenu.Everything')
ace('world.removeClouds', 'vMenu.WeatherOptions.RemoveClouds', 'vMenu.WeatherOptions.All', 'vMenu.Everything')
ace('migration.read', 'vMenu.Everything', 'vMenu.OnlinePlayers.ViewBannedPlayers')
ace('migration.import', 'vMenu.Everything', 'vMenu.OnlinePlayers.ViewBannedPlayers')

local sectionByPrefix = {
    ['player.auto'] = 'Autopilot', ['player.driving'] = 'Autopilot', ['player.scenario'] = 'Scenarios',
    ['vehicle.personal'] = 'Personal Vehicle', ['world.weather'] = 'Weather', ['world.dynamic'] = 'Weather',
    ['world.random'] = 'Weather', ['world.remove'] = 'Weather', ['world.snow'] = 'Weather',
    ['weapons.reserve'] = 'Parachutes', ['weapons.parachute'] = 'Parachutes',
    ['weapons.autoEquip'] = 'Parachutes', ['weapons.unlimitedParachutes'] = 'Parachutes',
    ['weapons.rename'] = 'Weapon Loadouts', ['weapons.clone'] = 'Weapon Loadouts', ['weapons.default'] = 'Weapon Loadouts',
    ['dev.entity'] = 'Developer Tools', ['dev.spawn'] = 'Developer Tools', ['dev.clearSpawned'] = 'Developer Tools',
    ['voice.'] = 'Voice Chat',
}
local defaultSections = {
    player = 'Player Options', vehicle = 'Vehicle Options', world = 'Time & Weather', weapons = 'Weapon Options',
    teleport = 'Teleport', appearance = 'Appearance', vehicle_custom = 'Vehicle Customization', dev = 'Miscellaneous',
    recording = 'Recording', options = 'Preferences', server = 'Server Tools', inventory = 'Inventory', garage = 'Garage',
}
for _, action in ipairs(EsAdminActions.actions) do
    if not action.section then
        for prefix, section in pairs(sectionByPrefix) do
            if action.id:sub(1, #prefix) == prefix then action.section = section; break end
        end
        action.section = action.section or defaultSections[action.tab] or 'General'
    end
end

for _, actionId in ipairs({ 'voice.enabled', 'voice.showSpeaker', 'voice.showStatus', 'voice.proximity', 'voice.channel' }) do
    local specific = actionId == 'voice.enabled' and 'vMenu.VoiceChat.Enable'
        or actionId == 'voice.showSpeaker' and 'vMenu.VoiceChat.ShowSpeaker'
        or actionId == 'voice.channel' and 'vMenu.VoiceChat.StaffChannel'
        or nil
    Config.VmenuAcePermissions[actionId] = specific and withFallback(specific, voiceMenu) or voiceMenu
end
