local sourcePath = debug.getinfo(1, 'S').source:sub(2):gsub('\\', '/')
local resourceRoot = assert(sourcePath:match('^(.*)/tests/[^/]+$'), 'could not locate resource root')

dofile(resourceRoot .. '/shared/config.lua')

local weaponList = assert(Config.WeaponList, 'Config.WeaponList must exist')
local weaponIndex = {}
for index = 1, #weaponList do
    local weapon = weaponList[index]
    assert(type(weapon) == 'string', ('weapon %d must be a string'):format(index))
    assert(weapon:match('^weapon_[a-z0-9_]+$'), ('invalid weapon model: %s'):format(weapon))
    assert(not weaponIndex[weapon], ('duplicate weapon model: %s'):format(weapon))
    weaponIndex[weapon] = true
end

-- The Cfx weapon-model catalog through the enforced GTA build 3095 contains
-- 111 grantable entries (everything except weapon_unarmed and post-3095 models).
-- These samples span the categories and DLC generations that the previous
-- partial list omitted.
local requiredWeapons = {
    'weapon_battleaxe',
    'weapon_bottle',
    'weapon_combatmg',
    'weapon_compactlauncher',
    'weapon_grenadelauncher_smoke',
    'weapon_dbshotgun',
    'weapon_doubleaction',
    'weapon_flaregun',
    'weapon_gusenberg',
    'weapon_hatchet',
    'weapon_knuckle',
    'weapon_machinepistol',
    'weapon_mg',
    'weapon_metaldetector',
    'weapon_minismg',
    'weapon_musket',
    'weapon_poolcue',
    'weapon_railgun',
    'weapon_revolver_mk2',
    'weapon_snspistol_mk2',
    'weapon_stungun',
    'weapon_switchblade',
    'weapon_raypistol',
    'weapon_ceramicpistol',
    'weapon_gadgetpistol',
    'weapon_militaryrifle',
    'weapon_emplauncher',
    'weapon_tacticalrifle',
    'weapon_pistolxm3',
    'weapon_railgunxm3',
    'weapon_tecpistol',
    'weapon_battlerifle',
    'weapon_snowlauncher',
}

assert(#weaponList >= 111, ('Give All catalog is partial: expected at least 111 weapons, got %d'):format(#weaponList))
for index = 1, #requiredWeapons do
    local weapon = requiredWeapons[index]
    assert(weaponIndex[weapon], ('Give All catalog is missing %s'):format(weapon))
end

local file = assert(io.open(resourceRoot .. '/client/actions.lua', 'rb'))
local clientSource = file:read('*a')
file:close()

local giveAllStart = assert(clientSource:find('function actionGiveAllWeapons()', 1, true), 'Give All action must exist')
local giveAllEnd = assert(clientSource:find('local WEAPON_UNARMED', giveAllStart, true), 'could not isolate Give All action')
local giveAllSource = clientSource:sub(giveAllStart, giveAllEnd - 1)

assert(giveAllSource:find('configuredWeaponModels()', 1, true), 'Give All must use the complete configured catalog')
assert(giveAllSource:find("authorizeModelBatch('weapon', weaponList, 'weapons.giveAll')", 1, true), 'Give All must authorize the complete catalog')
assert(giveAllSource:find('for i = 1, #weaponList do', 1, true), 'Give All must iterate the complete catalog')
assert(giveAllSource:find('GiveWeaponToPed(ped, weaponHash', 1, true), 'Give All must grant each authorized weapon')

print(('give all weapons contract tests passed (%d configured weapons)'):format(#weaponList))
