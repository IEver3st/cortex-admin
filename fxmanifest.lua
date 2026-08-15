fx_version 'cerulean'
game 'gta5'

name 'cortex-admin'
author 'Cortex'
version '1.1.0'
description 'Admin/dev menu with QBX framework support'

shared_scripts {
    '@cortex-lib/init.lua',
    'shared/config.lua',
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
    'client/vmenu_compat.lua',
    'client/nui.lua',
}

server_scripts {
    'server/bridge.lua',
    'server/actions.lua',
    'server/leveldb_reader.lua',
    'server/vmenu_fallback.lua',
    'server/main.lua',
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
    'ui/app.js',
    'ui/preview-shim.js',
    'ui/vendor/*.js',
}

lua54 'yes'
