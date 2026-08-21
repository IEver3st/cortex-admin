/**
 * Browser-only preview: open ui/index.html?preview=1 (via local static server).
 * Mocks FiveM NUI fetch + pushes initial state after cortex-admin:ready.
 */
(function () {
    const params = new URLSearchParams(window.location.search);
    if (params.get('preview') !== '1') {
        return;
    }

    window.__ES_ADMIN_PREVIEW__ = true;
    window.GetParentResourceName = function () {
        return 'cortex-admin';
    };

    const origFetch = window.fetch.bind(window);
    const previewScenario = params.get('state') || 'ready';
    const requestedTab = params.get('tab') || '';
    let previewGeneratorCanUndo = false;
    let previewBans = [
        { id: 'cortex-2026-00041', playerName: 'Rowan Cross', reason: 'Repeated combat logging after staff warning', adminName: 'PreviewAdmin', expiresAt: 0, provenance: 'cortex' },
        { id: 'vmenu-import-91a2', playerName: 'Taylor Knox', reason: 'Harassment', adminName: 'Legacy Staff', expiresAt: Math.floor(Date.now() / 1000) + 86400, provenance: 'vmenu' },
        { id: 'cortex-2026-00038', playerName: 'Jordan Vale', reason: 'Injected vehicle spawn events', adminName: 'Cortex Security', expiresAt: Math.floor(Date.now() / 1000) + 604800, provenance: 'cortex' },
    ];
    const previewLocations = [
        { name: 'Mission Row PD', x: 441.2, y: -981.9, z: 30.7, h: 90.0 },
        { name: 'Sandy Shores Airfield', x: 1742.5, y: 3271.3, z: 41.1, h: 193.0 },
        { name: 'Paleto Bay Sheriff', x: -447.1, y: 6013.4, z: 31.7, h: 314.0 },
    ];

    function requestBody(opts) {
        try {
            return JSON.parse((opts && opts.body) || '{}');
        } catch (err) {
            return {};
        }
    }

    function delayedResponse(factory) {
        return new Promise(function (resolve) {
            window.setTimeout(function () { resolve(factory()); }, 30000);
        });
    }

    function jsonResponse(obj) {
        return new Response(JSON.stringify(obj), {
            status: 200,
            headers: { 'Content-Type': 'application/json; charset=UTF-8' }
        });
    }

    function emptyAppearance() {
        return {
            components: {},
            maxComponents: {},
            props: {},
            maxProps: {},
            features: {},
            overlays: {},
            headBlend: {
                shapeFirstID: 0,
                shapeSecondID: 0,
                shapeThirdID: 0,
                skinFirstID: 0,
                skinSecondID: 0,
                skinThirdID: 0,
                shapeMix: 0.5,
                skinMix: 0.5,
                thirdMix: 0.0
            },
            model: 0,
            isFreemode: false,
            hairColor: 0,
            hairHighlightColor: 0,
            eyeColor: 0
        };
    }

    function previewAppearance() {
        const appearance = emptyAppearance();
        appearance.model = 1885233650;
        appearance.isFreemode = true;
        appearance.hairColor = 4;
        appearance.hairHighlightColor = 5;
        appearance.eyeColor = 5;
        for (let componentId = 0; componentId <= 11; componentId += 1) {
            appearance.components[String(componentId)] = { drawable: componentId === 2 ? 5 : 0, texture: 0 };
            appearance.maxComponents[String(componentId)] = { drawables: componentId === 2 ? 76 : 180, textures: 12 };
        }
        for (let propId = 0; propId <= 7; propId += 1) {
            appearance.props[String(propId)] = { drawable: -1, texture: 0 };
            appearance.maxProps[String(propId)] = { drawables: 80, textures: 10 };
        }
        for (let featureId = 0; featureId <= 19; featureId += 1) {
            appearance.features[String(featureId)] = 0;
        }
        return appearance;
    }

    function emptyVehicleCustomization() {
        const mods = {};
        [0, 1, 2, 3, 4, 6, 7, 10, 11, 12, 13, 14, 15, 16, 23, 24, 27, 28, 30, 32, 33, 38, 48].forEach(function (id) {
            mods[String(id)] = { current: id === 11 ? 2 : 0, max: id === 11 ? 4 : 6, names: {} };
        });
        mods['18'] = { isToggle: true, enabled: true };
        mods['20'] = { isToggle: true, enabled: false };
        mods['22'] = { isToggle: true, enabled: true };
        return {
            ok: true,
            vehicle: { model: 1663218586, label: 'Albany Police Cruiser', plate: 'CORTEX' },
            permissions: { mods: true, colors: true, liveries: true, extras: true, underglow: true, plate: true },
            mods,
            colors: {
                primary: 12,
                secondary: 0,
                pearlescent: 111,
                wheel: 156,
                dashboard: 0,
                trim: 0
            },
            paintFinish: { primary: 1, secondary: 0 },
            paintColor: { primary: 0, secondary: 0, pearlescent: 111 },
            customPrimary: { enabled: false, value: [36, 89, 156] },
            customSecondary: { enabled: true, value: [16, 18, 22] },
            extras: [
                { id: 1, label: 'Push bar', enabled: true },
                { id: 2, label: 'Roof lightbar', enabled: true },
                { id: 5, label: 'Spotlights', enabled: false },
                { id: 8, label: 'Rear antenna', enabled: false }
            ],
            liveries: [
                { value: 0, label: 'Los Santos Police' },
                { value: 1, label: 'Blaine County Sheriff' },
                { value: 2, label: 'Highway Patrol' }
            ],
            livery: 0,
            plate: 0,
            windowTint: 0,
            wheelType: 0,
            xenonColor: 0,
            enveffScale: 0.2,
            neonFront: false,
            neonBack: false,
            neonLeft: false,
            neonRight: false,
            neonColor: [255, 255, 255],
            tyreSmokeColor: [255, 255, 255]
        };
    }

    function previewVehicleTuning() {
        return {
            ok: true,
            vehicle: { label: 'Elegy Retro Custom', model: 'ELEGY', plate: 'CORTEX' },
            fields: [
                { id: 'fInitialDriveForce', label: 'Drive force', description: 'Acceleration delivered through the drivetrain', group: 'Powertrain', min: 0.01, max: 2, step: 0.01, precision: 2, value: 0.34, defaultValue: 0.29 },
                { id: 'fDriveInertia', label: 'Drive inertia', description: 'How quickly the engine builds and sheds revs', group: 'Powertrain', min: 0.1, max: 5, step: 0.05, precision: 2, value: 1.1, defaultValue: 1.0 },
                { id: 'fInitialDriveMaxFlatVel', label: 'Max flat velocity', description: 'Base transmission speed target from handling data', group: 'Powertrain', min: 10, max: 500, step: 1, precision: 0, value: 182, defaultValue: 168 },
                { id: 'fClutchChangeRateScaleUpShift', label: 'Upshift rate', description: 'Clutch speed while shifting into a higher gear', group: 'Powertrain', min: 0.1, max: 20, step: 0.1, precision: 1, value: 3.4, defaultValue: 3.4 },
                { id: 'fClutchChangeRateScaleDownShift', label: 'Downshift rate', description: 'Clutch speed while shifting into a lower gear', group: 'Powertrain', min: 0.1, max: 20, step: 0.1, precision: 1, value: 3.1, defaultValue: 3.1 },
                { id: 'fInitialDragCoeff', label: 'Drag coefficient', description: 'Aerodynamic resistance as speed increases', group: 'Powertrain', min: 0.1, max: 100, step: 0.1, precision: 1, value: 8.2, defaultValue: 8.2 },
                { id: 'fBrakeForce', label: 'Brake force', description: 'Overall service-brake strength', group: 'Control', min: 0.01, max: 5, step: 0.01, precision: 2, value: 1.1, defaultValue: 1.0 },
                { id: 'fSteeringLock', label: 'Steering lock', description: 'Maximum steering angle', group: 'Control', min: 5, max: 90, step: 0.5, precision: 1, unit: 'deg', value: 38, defaultValue: 38 },
                { id: 'fTractionCurveMax', label: 'Peak grip', description: 'Maximum tyre grip before slip begins', group: 'Grip', min: 0.1, max: 10, step: 0.01, precision: 2, value: 2.72, defaultValue: 2.55 },
                { id: 'fLowSpeedTractionLossMult', label: 'Launch slip', description: 'Low-speed wheelspin multiplier', group: 'Grip', min: 0, max: 5, step: 0.05, precision: 2, value: 0.9, defaultValue: 0.9 },
                { id: 'fMass', label: 'Mass', description: 'Vehicle mass used by handling calculations', group: 'Chassis', min: 100, max: 10000, step: 10, precision: 0, unit: 'kg', value: 1420, defaultValue: 1420 },
                { id: 'fSuspensionForce', label: 'Spring force', description: 'Overall suspension spring strength', group: 'Chassis', min: 0.1, max: 10, step: 0.05, precision: 2, value: 2.4, defaultValue: 2.3 }
            ],
            audio: {
                value: 'SULTANRS',
                defaultValue: 'ELEGY',
                presets: [
                    { label: 'Adder V8', value: 'ADDER' },
                    { label: 'Banshee', value: 'BANSHEE' },
                    { label: 'Sultan RS', value: 'SULTANRS' },
                    { label: 'Zentorno V12', value: 'ZENTORNO' }
                ]
            }
        };
    }

    const FALLBACK_PREVIEW_STATE = {
        open: true,
        tabs: [
            { id: 'all', label: 'All' },
            { id: 'player', label: 'Player' },
            { id: 'vehicle', label: 'Vehicle' },
            { id: 'world', label: 'World' },
            { id: 'weapons', label: 'Weapons' },
            { id: 'teleport', label: 'Teleport' },
            { id: 'appearance', label: 'Appearance' },
            { id: 'vehicle_custom', label: 'Customizer' },
            { id: 'inventory', label: 'Inventory', framework: 'qbx' },
            { id: 'garage', label: 'Garage', framework: 'qbx' },
            { id: 'dev', label: 'Dev' },
            { id: 'recording', label: 'Recording' },
            { id: 'options', label: 'Options' },
            { id: 'server', label: 'Server' },
            { id: 'voice', label: 'Voice' },
            { id: 'migration', label: 'vMenu Import' },
            { id: 'bans', label: 'Banned Players' },
            { id: 'imported', label: 'Imported Data' },
            { id: 'favorites', label: 'Favorites' }
        ],
        actions: [
            {
                id: 'player.godmode',
                label: 'God Mode',
                description: 'Prevent death and damage',
                tab: 'player',
                type: 'toggle'
            },
            {
                id: 'player.heal',
                label: 'Heal',
                description: 'Restore full health',
                tab: 'player',
                type: 'action'
            },
            {
                id: 'player.setWantedLevel',
                label: 'Set Wanted Level',
                description: 'Set your wanted level (0-5)',
                tab: 'player',
                type: 'select',
                values: [
                    { label: '0 Stars', value: 0 },
                    { label: '1 Star', value: 1 },
                    { label: '5 Stars', value: 5 }
                ]
            },
            {
                id: 'player.setModel',
                label: 'Set Ped Model',
                description: 'Change player model',
                tab: 'player',
                type: 'prompt',
                prompt: {
                    title: 'Set Ped Model',
                    fields: [{ name: 'model', label: 'Model', placeholder: 'mp_m_freemode_01' }]
                }
            },
            {
                id: 'vehicle.spawn',
                label: 'Spawn Vehicle',
                description: 'Preview and spawn a vehicle by model name',
                tab: 'vehicle',
                type: 'action'
            }
        ],
        favorites: ['player.heal'],
        settings: {
            menuPosition: 'right',
            menuAccentColor: '#e8a23f',
            uiScale: 1.05,
            uiOpacity: 0.94,
            speedHudPosition: 'top-left',
            speedHudUnits: 'mph'
        },
        toggles: {
            'player.godmode': false,
            'dev.showSpeed': false
        },
        allowed: {},
        players: [
            { id: 1, name: 'PreviewClient', ping: 12, bucket: 0, dead: false, isSelf: true },
            { id: 2, name: 'Avery Stone', ping: 48, bucket: 0, dead: false, isSelf: false },
            { id: 17, name: 'Morgan Reed', ping: 83, bucket: 2, dead: true, isSelf: false }
        ],
        wardrobeShareRequests: [],
        playerName: 'PreviewClient',
        gameHour: 14,
        gameMinute: 32,
        currentWeather: 'CLEAR',
        voiceState: {
            proximity: 20,
            channel: 42
        },
        personalVehicles: [],
        addonVehicles: ['adder', 'zentorno'],
        frameworkInfo: {
            framework: 'qbx',
            hasInventory: true,
            hasGarage: true,
            hasQBX: true
        },
        vehiclePreview: { active: false, model: '', shared: false },
        resources: [
            { name: 'cortex-admin', status: 'started' },
            { name: 'ox_lib', status: 'started' }
        ],
        inventoryItems: [
            { name: 'bread', label: 'Bread' },
            { name: 'water', label: 'Water' }
        ],
        garageVehicles: [{ id: 101, model: 'adder', plate: 'PREVIEW1' }]
    };

    function mergeToggleDefaults(state) {
        const out = { ...state };
        const toggles = { ...(out.toggles || {}) };
        const actions = Array.isArray(out.actions) ? out.actions : [];
        for (let i = 0; i < actions.length; i += 1) {
            const a = actions[i];
            if (a && a.type === 'toggle' && typeof a.id === 'string' && toggles[a.id] === undefined) {
                toggles[a.id] = false;
            }
        }
        out.toggles = toggles;
        return out;
    }

    function injectPreviewUiState() {
        const url = new URL('preview-state.json', window.location.href).toString();
        return origFetch(url, { cache: 'no-store' })
            .then(function (r) {
                if (!r.ok) {
                    throw new Error('preview-state.json not found');
                }
                return r.json();
            })
            .catch(function () {
                console.warn('[cortex-admin preview] Using fallback state. Run: bun run preview:state');
                return FALLBACK_PREVIEW_STATE;
            })
            .then(function (data) {
                const merged = mergeToggleDefaults(data);
                if (previewScenario === 'permission') {
                    merged.allowed = {
                        ...(merged.allowed || {}),
                        'migration.read': false,
                        'migration.import': false,
                        'player.viewBans': false,
                        'player.unban': false,
                    };
                }
                if (previewScenario === 'empty') {
                    merged.players = [];
                }
                window.postMessage({ action: 'cortex-admin:setState', data: merged }, '*');
                window.postMessage({ action: 'cortex-admin:open' }, '*');
                if (requestedTab) {
                    window.postMessage({ action: 'cortex-admin:setTab', data: { tab: requestedTab } }, '*');
                }
                if (params.get('huds') === '1') {
                    window.postMessage({ action: 'cortex-admin:setVehicleHealthHud', data: { visible: true, engine: 742, body: 915, tank: 624 } }, '*');
                    window.postMessage({ action: 'cortex-admin:setVoiceHud', data: { visible: true, talking: true, speakers: ['Avery Stone', 'Carmen Vega'] } }, '*');
                    window.postMessage({ action: 'cortex-admin:setTimeHud', data: { visible: true, hour: 14, minute: 32 } }, '*');
                }
            });
    }

    const nuiJsonHandlers = {
        'cortex-admin:ready': function () {
            injectPreviewUiState();
            return jsonResponse({ ok: true });
        },
        'cortex-admin:getAppearance': function () {
            return jsonResponse(previewScenario === 'empty' ? emptyAppearance() : previewAppearance());
        },
        'cortex-admin:randomizeAppearance': function (opts) {
            const body = requestBody(opts);
            const outfitNames = {
                polished: 'Night polo, black chinos, black Oxfords',
                casual: 'Charcoal T-shirt, black regular-fit jeans, black canvas shoes',
                street: 'Graphic T-shirt, black cargos, black skate shoes'
            };
            previewGeneratorCanUndo = true;
            return jsonResponse({ ok: true, mode: body.mode === 'character' ? 'character' : 'outfit', style: body.style || 'polished', outfitName: outfitNames[body.style] || outfitNames.polished, canUndo: true, modelChanged: body.mode === 'character' && body.gender !== 'keep' });
        },
        'cortex-admin:undoRandomizedAppearance': function () {
            const canUndo = previewGeneratorCanUndo;
            previewGeneratorCanUndo = false;
            return jsonResponse(canUndo ? { ok: true, canUndo: false } : { ok: false, error: 'nothing_to_undo', canUndo: false });
        },
        'cortex-admin:getSavedPeds': function () {
            return jsonResponse([]);
        },
        'cortex-admin:getSavedTeleportLocations': function () {
            return jsonResponse(previewScenario === 'empty' ? [] : previewLocations);
        },
        'cortex-admin:getVehicleCustomization': function () {
            return jsonResponse(emptyVehicleCustomization());
        },
        'cortex-admin:getVehicleTuning': function () {
            return jsonResponse(previewVehicleTuning());
        },
        'cortex-admin:resetVehicleTuning': function (opts) {
            const snapshot = previewVehicleTuning();
            let request = {};
            try {
                request = JSON.parse((opts && opts.body) || '{}');
            } catch (err) {
                request = {};
            }

            if (request.scope === 'audio' || request.scope === 'all') {
                snapshot.audio.value = '';
            }
            if (request.scope === 'handling' || request.scope === 'all') {
                snapshot.fields = snapshot.fields.map(function (field) {
                    return { ...field, value: field.defaultValue };
                });
            }
            return jsonResponse(snapshot);
        },
        'cortex-admin:resetVehicleTuningField': function (opts) {
            let request = {};
            try {
                request = JSON.parse((opts && opts.body) || '{}');
            } catch (err) {
                request = {};
            }
            const field = previewVehicleTuning().fields.find(function (entry) {
                return entry.id === request.field;
            });
            return jsonResponse(field
                ? { ok: true, field: field.id, value: field.defaultValue }
                : { ok: false, error: 'invalid_handling_field', message: 'That handling setting is not available.' });
        },
        'cortex-admin:getPreviewVehicleExtras': function () {
            return jsonResponse({ ok: true, extras: [] });
        },
        'cortex-admin:getWeaponAttachments': function () {
            return jsonResponse({ ok: true, weaponName: '', components: {} });
        },
        'cortex-admin:getVmenuMigrationSnapshot': function () {
            if (previewScenario === 'loading') {
                return delayedResponse(function () { return jsonResponse({ ok: false, error: 'preview_timeout' }); });
            }
            if (previewScenario === 'error') {
                return jsonResponse({ ok: false, error: 'The preview migration bridge is unavailable.' });
            }
            if (previewScenario === 'permission') {
                return jsonResponse({ ok: false, error: 'forbidden' });
            }
            if (previewScenario === 'empty') {
                return jsonResponse({
                    ok: true,
                    vmenuRunning: false,
                    peds: { available: false, count: 0, source: 'not detected', importedCount: 0 },
                    nonMpPeds: { available: false, count: 0, source: 'not detected' },
                    vehicles: { available: false, count: 0, source: 'not detected', importedCount: 0 },
                    weaponLoadouts: { available: false, count: 0, importedCount: 0 },
                    settings: { available: false, count: 0 },
                    categories: { peds: 0, vehicles: 0, importedPeds: 0, importedVehicles: 0 },
                    config: { available: false, resource: null, domains: {} },
                    permissions: { mode: 'ace-aliases', note: 'No recoverable vMenu data was detected.' },
                    fallback: { ok: false, reason: 'not_found', scope: 'host LevelDB', localHostOnly: true }
                });
            }
            return jsonResponse({
                ok: true,
                vmenuRunning: true,
                peds: { available: true, count: 4, source: 'vMenu client KVP', importedCount: 2 },
                nonMpPeds: { available: true, count: 2, source: 'host LevelDB' },
                vehicles: { available: true, count: 7, source: 'vMenu client KVP', importedCount: 3 },
                weaponLoadouts: { available: true, count: 3, importedCount: 1 },
                settings: { available: true, count: 58 },
                categories: { peds: 3, vehicles: 5, importedPeds: 1, importedVehicles: 2 },
                config: {
                    available: true,
                    resource: 'vMenu',
                    domains: {
                        addons: { available: true, count: 18, sourcePath: 'config/addons.json' },
                        extras: { available: true, count: 6, sourcePath: 'config/extras.json' },
                        locations: { available: true, count: 12, sourcePath: 'config/locations.json' },
                        modelWhitelists: { available: true, count: 9, sourcePath: 'config/model-whitelists.json' },
                        tattoos: { available: true, count: 41, sourcePath: 'config/tattoos.json' }
                    }
                },
                bans: { available: true, count: previewBans.length },
                permissions: { mode: 'ace-aliases', note: 'Existing vMenu.* grants are resolved as Cortex permission aliases.' },
                fallback: { ok: true, scope: 'FXServer host LevelDB', localHostOnly: true, parser: 'leveldb-log-v1' }
            });
        },
        'cortex-admin:importVmenuMigrationData': function () {
            if (previewScenario === 'error') return jsonResponse({ ok: false, error: 'preview_import_failed' });
            return jsonResponse({
                ok: true,
                result: {
                    ok: true,
                    peds: { imported: 2, skipped: 2 },
                    nonMpPeds: { imported: 2, skipped: 0 },
                    vehicles: { imported: 4, skipped: 3 },
                    weaponLoadouts: { imported: 2, skipped: 1 },
                    settings: { imported: 11, skipped: 47 },
                    locations: { imported: 3, skipped: 0 },
                    bans: { imported: 2, skipped: 1 }
                }
            });
        },
        'cortex-admin:getVmenuImportedConfiguration': function () {
            if (previewScenario === 'permission') return jsonResponse({ ok: false, error: 'forbidden' });
            if (previewScenario === 'error') return jsonResponse({ ok: false, error: 'Imported configuration could not be read.' });
            const empty = previewScenario === 'empty';
            return jsonResponse({
                ok: true,
                domains: {
                    addons: {
                        vehicles: { count: empty ? 0 : 12, sample: empty ? [] : ['cortexbuffalo', 'elegyr', 'police5'] },
                        peds: { count: empty ? 0 : 3, sample: empty ? [] : ['s_m_y_sheriff_02', 'a_m_m_business_01'] },
                        weapons: { count: empty ? 0 : 3, sample: empty ? [] : ['WEAPON_CARBINERIFLE', 'WEAPON_FLASHLIGHT'] }
                    },
                    extras: { count: empty ? 0 : 6, sample: empty ? [] : ['police5', 'ambulance'] },
                    locations: {
                        teleports: { count: empty ? 0 : 3, sample: empty ? [] : ['Mission Row PD', 'Sandy Shores Airfield'] },
                        blips: { count: empty ? 0 : 5, sample: empty ? [] : ['Police Stations', 'Hospitals'] }
                    },
                    modelWhitelists: {
                        vehicles: { count: empty ? 0 : 4, sample: empty ? [] : ['police5', 'ambulance'] },
                        peds: { count: empty ? 0 : 2, sample: empty ? [] : ['s_m_y_sheriff_02'] },
                        weapons: { count: empty ? 0 : 3, sample: empty ? [] : ['WEAPON_CARBINERIFLE'] }
                    },
                    tattoos: { count: empty ? 0 : 41, sample: empty ? [] : ['MP_Buis_M_Neck_000', 'MP_Buis_M_Head_000'] }
                },
                categories: {
                    peds: { count: empty ? 0 : 3, sample: empty ? [] : ['Emergency', 'Civilians'] },
                    vehicles: { count: empty ? 0 : 5, sample: empty ? [] : ['Emergency', 'Sports'] }
                }
            });
        },
        'cortex-admin:getBanList': function (opts) {
            if (previewScenario === 'loading') return delayedResponse(function () { return jsonResponse({ ok: false, error: 'preview_timeout', records: [] }); });
            if (previewScenario === 'permission') return jsonResponse({ ok: false, error: 'forbidden', records: [] });
            if (previewScenario === 'error') return jsonResponse({ ok: false, error: 'Ban storage is unavailable.', records: [] });
            const body = requestBody(opts);
            const query = String(body.query || '').trim().toLowerCase();
            const offset = Math.max(0, Number(body.offset) || 0);
            const limit = Math.min(100, Math.max(1, Number(body.limit) || 50));
            const source = previewScenario === 'empty' ? [] : previewBans;
            const matched = source.filter(function (record) {
                if (!query) return true;
                return [record.id, record.playerName, record.reason, record.adminName].some(function (value) {
                    return String(value || '').toLowerCase().includes(query);
                });
            });
            const records = matched.slice(offset, offset + limit);
            return jsonResponse({ ok: true, records, total: matched.length, offset, limit, hasMore: offset + records.length < matched.length });
        },
        'cortex-admin:unban': function (opts) {
            const body = requestBody(opts);
            const before = previewBans.length;
            previewBans = previewBans.filter(function (record) { return record.id !== body.id; });
            return jsonResponse({ ok: previewBans.length < before, id: body.id, error: previewBans.length < before ? undefined : 'not_found' });
        },
        'cortex-admin:playerAction': function (opts) {
            const body = requestBody(opts);
            if (body.action === 'identifiers') {
                window.postMessage({
                    action: 'cortex-admin:setPlayerIdentifiers',
                    data: {
                        target: body.target,
                        name: body.target === 17 ? 'Morgan Reed' : 'Avery Stone',
                        identifiers: ['license:preview7f3a12c9', 'discord:102938475610293847', 'fivem:812045']
                    }
                }, '*');
            }
            return jsonResponse({ ok: true });
        },
        'cortex-admin:favorite': function () {
            return jsonResponse({ ok: true });
        },
        'cortex-admin:close': function () {
            window.postMessage({ action: 'cortex-admin:close' }, '*');
            return jsonResponse({ ok: true });
        },
        'cortex-admin:getWardrobeShareTargets': function () {
            return jsonResponse({ ok: true, targets: [] });
        }
    };

    window.fetch = function (url, opts) {
        const u = String(url);
        if (!u.startsWith('https://cortex-admin/')) {
            return origFetch(url, opts);
        }

        const eventName = u.slice('https://cortex-admin/'.length);
        if (nuiJsonHandlers[eventName]) {
            return Promise.resolve(nuiJsonHandlers[eventName](opts));
        }

        if (window.__ES_ADMIN_PREVIEW_DEBUG__) {
            console.debug('[cortex-admin preview] NUI', eventName, opts && opts.body);
        }
        return Promise.resolve(jsonResponse({ ok: true }));
    };

    console.info('[cortex-admin] Preview mode. Run `bun run dev` and open the printed URL.');
})();
