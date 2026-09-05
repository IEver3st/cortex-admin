fx_version 'cerulean'
game 'gta5'

name 'cortex-admin'
author 'Cortex'
version '1.1.0'
description 'Admin/dev menu with QBX framework support'

shared_scripts {
    '@cortex-lib/init.lua',
    'shared/config.lua',
    'shared/appearance_catalog.lua',
    'shared/appearance_index.lua',
    'shared/wardrobe_catalog.lua',
    'shared/appearance_randomizer.lua',
    'shared/wardrobe_share.lua',
    'shared/weapon_component_hashes.lua',
    'shared/bridge.lua',
    'shared/actions.lua',
    'shared/vmenu_compat.lua',
}

client_scripts {
    'client/bridge.lua',
    'client/main.lua',
    'client/actions.lua',
    'client/character_studio.lua',
    'client/wardrobe_catalog.lua',
    'client/vehicle_studio.lua',
    'client/vmenu_compat.lua',
    'client/nui.lua',
}

server_scripts {
    'server/bridge.lua',
    'server/actions.lua',
    'server/leveldb_reader.lua',
    'server/vmenu_fallback.lua',
    'server/main.lua',
    'server/wardrobe_catalog.lua',
    'server/vmenu_compat.lua',
}

dependency 'cortex-lib'

-- Exports for external resources
exports {
    'teleportToCoords'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/console.css',
    'ui/character-studio.css',
    'ui/vehicle-studio.css',
    'ui/studio-controls.css',
    'ui/vehicle-controls.js',
    'ui/vehicle-catalog/catalog.js',
    'ui/vehicle-catalog/wheels/*.webp',
    'ui/vehicle-catalog/plates/*.webp',
    'ui/vehicle-studio.js',
    'ui/app.js',
    'ui/wardrobe-capture.js',
    'ui/wardrobe-matte.js',
    'ui/wardrobe/*.webp',
    'ui/preview-shim.js',
    'ui/vendor/*.js',
}

lua54 'yes'
