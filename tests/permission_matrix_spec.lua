local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

Config = nil
EsAdminActions = nil
EsAdminVmenuActions = nil
EsAdminPermissions = nil

dofile(resourceRoot .. '/shared/config.lua')
dofile(resourceRoot .. '/shared/actions.lua')
Config.VmenuAceExcludedTabs = { player = true }
dofile(resourceRoot .. '/shared/vmenu_compat.lua')
dofile(resourceRoot .. '/server/permissions.lua')

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(('%s: expected %s, got %s'):format(message, tostring(expected), tostring(actual)), 2)
    end
end

local manifestFile = assert(io.open(resourceRoot .. '/fxmanifest.lua', 'r'))
local manifest = manifestFile:read('*a')
manifestFile:close()
local resolverPosition = assert(manifest:find("'server/permissions.lua'", 1, true), 'permissions module missing from manifest')
local mainPosition = assert(manifest:find("'server/main.lua'", 1, true), 'server main missing from manifest')
assert(resolverPosition < mainPosition, 'permissions module must load before server/main.lua')

local actionIndex = {}
local protected = { appearance = {}, recording = {} }
for _, action in ipairs(EsAdminActions.actions) do
    actionIndex[action.id] = action
    if protected[action.tab] then
        protected[action.tab][#protected[action.tab] + 1] = action
    end
end
assert(#protected.appearance > 0, 'appearance catalog is empty')
assert(#protected.recording > 0, 'recording catalog is empty')

local grants = {}
local qbxResult = nil
local function isAceAllowed(_, permission)
    return grants[permission] == true
end
local function checkQBXPermission()
    return qbxResult
end
local hasPermission = EsAdminPermissions.build(Config, actionIndex, isAceAllowed, checkQBXPermission)

local expectedAce = {
    appearance = 'cortex-admin.appearance',
    recording = 'cortex-admin.recording',
}
assertEqual(Config.Permissions.appearance, expectedAce.appearance, 'appearance tab ACE')
assertEqual(Config.Permissions.recording, expectedAce.recording, 'recording tab ACE')
for tab, actions in pairs(protected) do
    for _, action in ipairs(actions) do
        assertEqual(Config.ActionPermissions[action.id], expectedAce[tab], action.id .. ' action ACE')
    end
end

Config.HasQBX = false
local coreMatrix = {
    { grants = { ['cortex-admin.appearance'] = true }, appearance = true, recording = false },
    { grants = { ['cortex-admin.recording'] = true }, appearance = false, recording = true },
    { grants = { ['cortex-admin.player'] = true }, appearance = false, recording = false },
    { grants = { ['cortex-admin.dev'] = true }, appearance = false, recording = false },
    { grants = { ['cortex-admin.all'] = true }, appearance = true, recording = true },
}
for rowIndex, row in ipairs(coreMatrix) do
    grants = row.grants
    for tab, actions in pairs(protected) do
        for _, action in ipairs(actions) do
            assertEqual(
                hasPermission(1, action.id),
                row[tab],
                ('core matrix row %d for %s'):format(rowIndex, action.id)
            )
        end
    end
end

local recordingAction = protected.recording[1].id
Config.HasQBX = true
grants = {}
qbxResult = true
assertEqual(hasPermission(1, recordingAction), true, 'QBX grant')
grants = { ['cortex-admin.recording'] = true }
qbxResult = false
assertEqual(hasPermission(1, recordingAction), false, 'QBX explicit deny precedence')
qbxResult = nil
assertEqual(hasPermission(1, recordingAction), true, 'QBX fallthrough to Recording ACE')
Config.HasQBX = false

assertEqual(Config.VmenuAceExcludedTabs.player, true, 'existing vMenu exclusion preserved')
assertEqual(Config.VmenuAceExcludedTabs.recording, true, 'recording vMenu alias exclusion')
local unrelatedAliases = {
    'vMenu.PlayerOptions.All',
    'vMenu.MiscSettings.All',
    'vMenu.PlayerAppearance.All',
}
for _, action in ipairs(protected.recording) do
    -- Inject broad aliases to prove the production resolver enforces the tab
    -- exclusion even if the alias catalog is broadened later.
    Config.VmenuAcePermissions[action.id] = unrelatedAliases
    for _, permission in ipairs(unrelatedAliases) do
        grants = { [permission] = true }
        assertEqual(hasPermission(1, action.id), false, permission .. ' must not grant ' .. action.id)
    end

    grants = { ['vMenu.Everything'] = true }
    assertEqual(hasPermission(1, action.id), true, 'vMenu.Everything must remain global')
end

-- The exclusion is scoped to Recording; legitimate Appearance aliases still work.
grants = { ['vMenu.PlayerAppearance.All'] = true }
assertEqual(hasPermission(1, 'player.randomizeMpFace'), true, 'appearance vMenu alias')
assertEqual(hasPermission(1, nil), false, 'invalid action id')

print('appearance and recording permission matrix tests passed')
