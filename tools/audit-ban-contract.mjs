import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { LuaFactory } from 'wasmoon';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (...parts) => readFileSync(join(root, ...parts), 'utf8');
const fixture = JSON.parse(read('tests', 'fixtures', 'production-ban-record.json'));

function between(source, start, end) {
    const from = source.indexOf(start);
    const to = source.indexOf(end, from + start.length);
    assert.notEqual(from, -1, `Unable to find ${start}`);
    assert.notEqual(to, -1, `Unable to find ${end} after ${start}`);
    return source.slice(from, to);
}

function luaLiteral(value) {
    if (value === null || value === undefined) return 'nil';
    if (typeof value === 'string') return JSON.stringify(value);
    if (typeof value === 'boolean') return value ? 'true' : 'false';
    if (typeof value === 'number') {
        assert.ok(Number.isFinite(value), 'fixture numbers must be finite');
        return String(value);
    }
    if (Array.isArray(value)) return `{ ${value.map(luaLiteral).join(', ')} }`;
    assert.equal(typeof value, 'object', 'fixture values must be JSON-compatible');
    return `{ ${Object.entries(value).map(([key, entry]) => `[${luaLiteral(key)}] = ${luaLiteral(entry)}`).join(', ')} }`;
}

assert.equal(Object.hasOwn(fixture.storedRecord, 'admin'), true, 'fixture must use the persisted admin field');
assert.equal(Object.hasOwn(fixture.storedRecord, 'importedFrom'), true, 'fixture must use the persisted importedFrom field');
assert.equal(Object.hasOwn(fixture.storedRecord, 'adminName'), false, 'fixture must remain production-shaped');
assert.equal(Object.hasOwn(fixture.storedRecord, 'provenance'), false, 'fixture must remain production-shaped');

const factory = new LuaFactory();
const server = await factory.createEngine();
const client = await factory.createEngine();

try {
    const emittedServerEvents = [];
    const emittedClientEvents = [];
    const noOp = () => {};

    server.global.set('GetCurrentResourceName', () => 'cortex-admin');
    server.global.set('GetResourceKvpString', (key) => key === 'ban-store' ? '__BAN_FIXTURE__' : undefined);
    server.global.set('SetResourceKvp', noOp);
    server.global.set('GetConvar', (_name, fallback) => fallback);
    server.global.set('AddEventHandler', noOp);
    server.global.set('CreateThread', noOp);
    server.global.set('TriggerClientEvent', (name, target, ...args) => {
        const transportedArgs = args.map((value) => {
            if (value === null || typeof value !== 'object') return value;
            return JSON.parse(JSON.stringify(value));
        });
        emittedClientEvents.push({ name, target, args: transportedArgs });
    });

    const storedEnvelope = {
        version: 2,
        nextId: 2,
        records: [fixture.storedRecord],
    };
    await server.doString(`
        Config = {
            BanIdentifierTypes = { 'license' },
            KvpKeys = { bans = 'ban-store', vmenuConfig = 'vmenu-config' },
            VmenuCompatibility = { importConfigFiles = {} },
        }
        __serverEvents = {}
        RegisterNetEvent = function(name, handler) __serverEvents[name] = handler end
        json = {
            decode = function(raw)
                if raw == '__BAN_FIXTURE__' then return ${luaLiteral(storedEnvelope)} end
                return {}
            end,
            encode = function() return '{}' end,
        }
    `);
    await server.doString(read('server', 'actions.lua'));
    await server.doString(`
        EsAdminServer.hasPermission = function() return true end
        EsAdminServer.allowRequest = function() return true end
        EsAdminServer.worldState = {}
    `);
    await server.doString(read('server', 'vmenu_compat.lua'));

    assert.equal(
        await server.doString("return type(__serverEvents['cortex-admin:server:requestBanList'])"),
        'function',
        'real server ban-list event must register'
    );

    client.global.set('GetCurrentResourceName', () => 'cortex-admin');
    client.global.set('GetResourceKvpString', () => undefined);
    client.global.set('SetResourceKvp', noOp);
    client.global.set('GetGameTimer', () => 1234);
    client.global.set('AddEventHandler', noOp);
    client.global.set('CreateThread', noOp);
    client.global.set('SetTimeout', noOp);
    client.global.set('RegisterCommand', noOp);
    client.global.set('RegisterKeyMapping', noOp);
    client.global.set('SendNUIMessage', noOp);
    client.global.set('DoesBlipExist', () => false);
    client.global.set('RemoveBlip', noOp);
    client.global.set('TriggerServerEvent', (name, ...args) => {
        const transportedArgs = args.map((value) => {
            if (value === null || typeof value !== 'object') return value;
            return JSON.parse(JSON.stringify(value));
        });
        emittedServerEvents.push({ name, args: transportedArgs });
    });

    await client.doString(`
        Config = {
            Command = 'vmenu',
            VmenuCompatibility = {},
            ActionPermissions = { ['player.viewBans'] = 'cortex-admin.player.viewBans' },
            KvpKeys = {
                vmenuPreferences = 'vmenu-preferences',
                vmenuImport = 'vmenu-import',
                vmenuClientConfig = 'vmenu-client-config',
                vmenuCategories = 'vmenu-categories',
            },
        }
        __clientEvents = {}
        RegisterNetEvent = function(name, handler) __clientEvents[name] = handler end
        EsAdmin = {
            state = {
                toggles = {},
                settings = {},
                allowed = { ['player.viewBans'] = true },
                favorites = {},
            },
            notify = function() end,
            executeAction = function() end,
            toggleAction = function() end,
            selectAction = function() end,
        }
        promise = {
            new = function()
                local pending = {}
                function pending:resolve(value) self.value = value end
                return pending
            end,
        }
        Citizen = { Await = function(pending) return pending.value end }
        json = {
            decode = function() return {} end,
            encode = function() return '{}' end,
        }
        __nuiCallbacks = {}
        RegisterNUICallback = function(name, handler) __nuiCallbacks[name] = handler end
    `);
    await client.doString(read('client', 'vmenu_compat.lua'));

    assert.equal(
        await client.doString("return type(__clientEvents['cortex-admin:client:receiveBanList'])"),
        'function',
        'real client ban-list receiver must register'
    );
    assert.equal(await client.doString('return type(EsAdmin.getBanList)'), 'function', 'real client request bridge must load');

    await client.doString(`
        CreateThread = function(callback) callback() end
        Citizen.Await = function(pending)
            coroutine.yield()
            return pending.value
        end
    `);
    await client.doString(read('client', 'nui.lua'));
    assert.equal(
        await client.doString("return type(__nuiCallbacks['cortex-admin:getBanList'])"),
        'function',
        'real ban-list NUI callback must register'
    );

    await client.doString(`
        local function resumeOrFail(thread)
            local ok, err = coroutine.resume(thread)
            if not ok then error(err) end
            return coroutine.status(thread)
        end

        function __startBanNuiRequest()
            __browserResponse = nil
            __banNuiThread = coroutine.create(function()
                __nuiCallbacks['cortex-admin:getBanList'](
                    { query = ${luaLiteral(fixture.adminQuery)}, offset = 0, limit = 50 },
                    function(payload) __browserResponse = payload end
                )
            end)
            return resumeOrFail(__banNuiThread)
        end

        function __resumeBanNuiRequest()
            return resumeOrFail(__banNuiThread)
        end
    `);

    emittedServerEvents.length = 0;
    emittedClientEvents.length = 0;
    assert.equal(await client.doString('return __startBanNuiRequest()'), 'suspended', 'NUI request must await the server response');
    assert.equal(emittedServerEvents.length, 1, 'client bridge must emit one server request');

    const serverRequest = emittedServerEvents[0];
    assert.equal(serverRequest.name, 'cortex-admin:server:requestBanList');
    await server.doString(`
        source = 17
        __serverEvents[${luaLiteral(serverRequest.name)}](${serverRequest.args.map(luaLiteral).join(', ')})
    `);
    assert.equal(emittedClientEvents.length, 1, 'server must emit one ban-list response');

    const responseEvent = emittedClientEvents[0];
    assert.equal(responseEvent.name, 'cortex-admin:client:receiveBanList');
    assert.equal(responseEvent.target, 17);
    assert.equal(responseEvent.args.length, 2);
    await client.doString(
        `__clientEvents[${luaLiteral(responseEvent.name)}](${responseEvent.args.map(luaLiteral).join(', ')})`
    );

    assert.equal(await client.doString('return __resumeBanNuiRequest()'), 'dead', 'NUI request must finish after the client receiver resolves it');
    const response = await client.doString('return __browserResponse');

    assert.equal(response.ok, true);
    assert.equal(response.total, 1, 'administrator query must match the production-shaped record');
    assert.equal(response.offset, 0);
    assert.equal(response.limit, 50);
    assert.equal(response.hasMore, false);
    assert.equal(response.records.length, 1);
    assert.deepEqual(response.records[0], fixture.expectedDto, 'real NUI response must expose the canonical ban DTO');
    assert.equal(Object.hasOwn(response.records[0], 'admin'), false, 'NUI response must not leak the persisted admin alias');
    assert.equal(Object.hasOwn(response.records[0], 'importedFrom'), false, 'NUI response must not leak the persisted provenance alias');

    const ui = read('ui', 'app.js');
    const uiWorkspace = between(ui, 'function BannedPlayersWorkspace', 'function ImportedDataWorkspace');
    assert.match(uiWorkspace, /fetchNui\('cortex-admin:getBanList'/, 'browser must call the exercised NUI callback');
    assert.match(uiWorkspace, /record\.adminName/, 'browser must render the canonical administrator field');
    assert.match(uiWorkspace, /record\.provenance/, 'browser must render the canonical provenance field');

    const manifest = read('fxmanifest.lua');
    assert.ok(manifest.indexOf("'server/actions.lua'") < manifest.indexOf("'server/vmenu_compat.lua'"), 'server mapper must load before the server event');
    assert.ok(manifest.indexOf("'client/vmenu_compat.lua'") < manifest.indexOf("'client/nui.lua'"), 'client bridge must load before the NUI callback');
    assert.match(manifest, /'ui\/app\.js'/, 'the verified browser consumer must ship with the resource');

    console.log('Ban DTO integration passed: persisted record -> server event -> client bridge -> NUI response -> browser contract');
} finally {
    client.global.close();
    server.global.close();
}
