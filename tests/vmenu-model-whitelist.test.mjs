import { afterAll, beforeAll, describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LuaFactory } from 'wasmoon';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const serverSource = readFileSync(join(root, 'server', 'vmenu_compat.lua'), 'utf8');
const unitEnd = serverSource.indexOf('local function buildAuthorizedModelSet');

if (unitEnd < 0) throw new Error('Unable to isolate the model authorization unit');

const harnessSource = `
local grantedAces = {}
local hashes = {}
local nextHash = 1000

Config = { Permissions = { all = 'cortex.admin' } }
EsAdminServer = {
    hasPermission = function() return true end,
}

function GetCurrentResourceName()
    return 'cortex-admin'
end

function joaat(name)
    if hashes[name] == nil then
        nextHash = nextHash + 1
        hashes[name] = nextHash
    end
    return hashes[name]
end

function IsPlayerAceAllowed(_, ace)
    return grantedAces[ace] == true
end

${serverSource.slice(0, unitEnd)}

function runAuthorizationCase(whitelistData, kind, model, actionId, aces)
    grantedAces = {}
    for index = 1, #aces do grantedAces[aces[index]] = true end

    configStore = { version = 1, domains = {} }
    if whitelistData ~= nil then
        configStore.domains.modelWhitelists = { data = whitelistData }
    end
    refreshModelWhitelistIndex()

    local modelAllowed, reason = authorizeModel(7, kind, model, actionId)
    return (modelAllowed == true and 'allowed' or 'denied') .. ':' .. (reason or '')
end
`;

let lua;

beforeAll(async () => {
    lua = await new LuaFactory().createEngine();
    await lua.doString(harnessSource);
});

afterAll(() => {
    lua?.global.close();
});

async function authorize(whitelistData, kind, model, actionId, aces = '{}') {
    return lua.doString(
        `return runAuthorizationCase(${whitelistData}, ${JSON.stringify(kind)}, ${JSON.stringify(model)}, ${JSON.stringify(actionId)}, ${aces})`,
    );
}

describe('imported vMenu model whitelist authorization', () => {
    test.each([
        ['vehicle', "{ whitelistedvehicles = { 'adder' } }", 'ADDER', 'vehicle.spawn', "{ 'vMenu.VehicleSpawner.WhitelistedModels.adder' }"],
        ['ped', "{ whitelistedpeds = { 's_m_y_cop_01' } }", 's_m_y_cop_01', 'player.setModel', "{ 'vMenu.PlayerAppearance.WhitelistedModels.s_m_y_cop_01' }"],
        ['weapon', "{ whitelistedweapons = { 'pistol' } }", 'pistol', 'weapons.give', "{ 'vMenu.WeaponOptions.WhitelistedModels.pistol' }"],
    ])('allows a listed %s model when its model ACE is granted', async (kind, data, model, actionId, aces) => {
        expect(await authorize(data, kind, model, actionId, aces)).toBe('allowed:');
    });

    test.each([
        ['vehicle', "{ whitelistedvehicles = { 'adder' } }", 'zentorno', 'vehicle.spawn', "{ 'vMenu.VehicleSpawner.WhitelistedModels.zentorno', 'vMenu.VehicleSpawner.WhitelistedModels.All', 'vMenu.Everything', 'cortex.admin' }"],
        ['ped', "{ whitelistedpeds = { 's_m_y_cop_01' } }", 'mp_m_freemode_01', 'player.setModel', "{ 'vMenu.PlayerAppearance.WhitelistedModels.mp_m_freemode_01', 'vMenu.PlayerAppearance.WhitelistedModels.All', 'vMenu.Everything', 'cortex.admin' }"],
        ['weapon', "{ whitelistedweapons = { 'pistol' } }", 'smg', 'weapons.give', "{ 'vMenu.WeaponOptions.WhitelistedModels.smg', 'vMenu.WeaponOptions.WhitelistedModels.All', 'vMenu.Everything', 'cortex.admin' }"],
    ])('denies an unlisted %s model when that kind has a non-empty whitelist', async (kind, data, model, actionId, aces) => {
        expect(await authorize(data, kind, model, actionId, aces)).toBe('denied:model_forbidden');
    });

    test.each([
        ['vehicle', 'nil', 'zentorno', 'vehicle.spawn'],
        ['ped', 'nil', 'mp_m_freemode_01', 'player.setModel'],
        ['weapon', 'nil', 'smg', 'weapons.give'],
        ['ped', "{ whitelistedvehicles = { 'adder' } }", 'mp_m_freemode_01', 'player.setModel'],
    ])('keeps %s models unrestricted when that kind has no configured whitelist', async (kind, data, model, actionId) => {
        expect(await authorize(data, kind, model, actionId)).toBe('allowed:');
    });

    test('treats a non-empty imported whitelist as configured even when every entry is invalid', async () => {
        expect(await authorize("{ whitelistedvehicles = { 'not a model!' } }", 'vehicle', 'adder', 'vehicle.spawn')).toBe(
            'denied:model_forbidden',
        );
    });

    test('keeps an explicitly empty imported whitelist unrestricted', async () => {
        expect(await authorize('{ whitelistedvehicles = {} }', 'vehicle', 'adder', 'vehicle.spawn')).toBe('allowed:');
    });

    test('denies a listed model when its model ACE is not granted', async () => {
        expect(await authorize("{ whitelistedvehicles = { 'adder' } }", 'vehicle', 'adder', 'vehicle.spawn')).toBe(
            'denied:model_forbidden',
        );
    });
});
