import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (...parts) => readFileSync(join(root, ...parts), 'utf8');
const sharedCompat = read('shared', 'vmenu_compat.lua');
const clientCompat = read('client', 'vmenu_compat.lua');
const serverCompat = read('server', 'vmenu_compat.lua');
const clientMain = read('client', 'main.lua');
const clientNui = read('client', 'nui.lua');
const serverMain = read('server', 'main.lua');
const serverFallback = read('server', 'vmenu_fallback.lua');

function position(source, marker, label = marker) {
    const index = source.indexOf(marker);
    assert.notEqual(index, -1, `missing ${label}`);
    return index;
}

function section(source, startMarker, endMarker) {
    const start = position(source, startMarker);
    const end = position(source.slice(start + startMarker.length), endMarker) + start + startMarker.length;
    return source.slice(start, end);
}

test('enabled=false stops shared catalog and ACE augmentation after fallback configuration', () => {
    const fallbackConfig = position(sharedCompat, 'Config.VmenuFallback = Config.VmenuFallback or {');
    const fallbackKeys = position(sharedCompat, "Config.KvpKeys.vmenuCategories =");
    const disabledGuard = position(sharedCompat, 'if Config.VmenuCompatibility.enabled == false then');
    const catalog = position(sharedCompat, 'local function values(list)');

    assert.ok(fallbackConfig < disabledGuard, 'fallback configuration must survive the compatibility guard');
    assert.ok(fallbackKeys < disabledGuard, 'fallback/migration KVP keys must survive the compatibility guard');
    assert.ok(disabledGuard < catalog, 'disabled compatibility must return before catalog construction');
});

test('enabled=false exits client and server compatibility chunks before runtime registration', () => {
    for (const [name, source, requiredBypass] of [
        ['client', clientCompat, 'Admin.authorizeVmenuModel ='],
        ['server', serverCompat, 'Server.consumeModelAuthorization ='],
    ]) {
        const guard = position(source, 'if not vmenuCompatibilityEnabled then', `${name} disabled guard`);
        const bypass = position(source, requiredBypass, `${name} core model authorization bypass`);
        const returnMatch = /\r?\n    return\r?\nend/.exec(source.slice(guard));
        assert.ok(returnMatch, `missing ${name} disabled return`);
        const earlyReturn = guard + returnMatch.index;
        const registrations = [
            'RegisterNetEvent(',
            'RegisterCommand(',
            'RegisterKeyMapping(',
            'AddEventHandler(',
            'CreateThread(',
        ]
            .map((marker) => source.indexOf(marker))
            .filter((index) => index >= 0);
        const firstRegistration = Math.min(...registrations);

        assert.ok(guard < bypass && bypass < earlyReturn, `${name} must install only the core bypass before returning`);
        assert.ok(earlyReturn < firstRegistration, `${name} must return before registering compatibility runtime surface`);
    }
});

test('enabled=false retains core server model authorization before exiting', () => {
    const authorizer = position(serverCompat, 'Server.authorizeModel = authorizeModel');
    const guard = position(serverCompat, 'if not vmenuCompatibilityEnabled then');
    assert.ok(authorizer < guard, 'core server model authorization must be installed before the disabled return');
});

test('vMenu ACE grants and protections are ignored when compatibility is disabled', () => {
    const canOpen = section(serverMain, 'local function canOpenMenu', 'local function sanitizeVariationPair');
    const hasPermission = section(serverMain, 'local function hasPermission', 'EsAdminServer.hasPermission');

    assert.match(canOpen, /if vmenuCompatibilityEnabled then[\s\S]*command\.vmenu[\s\S]*vMenu\.Everything/);
    assert.match(hasPermission, /if vmenuCompatibilityEnabled then[\s\S]*vMenu\.Everything[\s\S]*Config\.VmenuAcePermissions/);
    assert.match(serverMain, /vmenuCompatibilityEnabled and IsPlayerAceAllowed\(target, 'vMenu\.DontKickMe'\)/);
    assert.match(serverMain, /vmenuCompatibilityEnabled and IsPlayerAceAllowed\(target, 'vMenu\.DontBanMe'\)/);
});

test('non-compatibility client paths do not call disabled server endpoints', () => {
    const startup = section(clientMain, "AddEventHandler('onClientResourceStart'", "AddEventHandler('onResourceStop'");
    const playerAction = section(clientNui, "RegisterNUICallback('cortex-admin:playerAction'", '-- Resources');

    assert.match(startup, /if vmenuCompatibilityEnabled then[\s\S]*requestVmenuWorldState/);
    assert.match(playerAction, /vmenuCompatibilityEnabled and compatibilityPlayerActions\[action\]/);
    assert.match(playerAction, /elseif action == 'kill' then[\s\S]*cortex-admin:server:killPlayer/);
});

test('VmenuFallback remains independently controlled', () => {
    assert.doesNotMatch(serverFallback, /VmenuCompatibility/);
    assert.match(serverFallback, /Config\.VmenuFallback\.enabled == false/);
    assert.match(serverFallback, /RegisterNetEvent\('cortex-admin:server:requestVmenuKvpSnapshot'/);
});
