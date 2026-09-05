fx_version 'cerulean'
game 'gta5'

name 'es_admin'
author 'Everest Studios'
version '1.1.0'
description 'Admin/dev menu with QBX framework support'

shared_scripts {
    '@es_lib/init.lua',
    'shared/config.lua',
    'shared/weapon_component_hashes.lua',
    'shared/bridge.lua',
    'shared/actions.lua',
}

client_scripts {
    'client/bridge.lua',
    'client/main.lua',
    'client/actions.lua',
    'client/nui.lua',
}

server_scripts {
    'server/bridge.lua',
    'server/actions.lua',
    'server/vmenu_fallback.lua',
    'server/main.lua',
}

dependency 'es_lib'

-- Exports for external resources
exports {
    'teleportToCoords'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/preview-shim.js',
}

lua54 'yes'
