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

    function emptyVehicleCustomization() {
        return {
            mods: {},
            colors: {
                primary: 0,
                secondary: 0,
                pearlescent: 0,
                wheel: 0,
                dashboard: 0,
                trim: 0
            },
            plate: 0,
            windowTint: 0,
            wheelType: 0,
            xenonColor: 0,
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
            menuAccentColor: '#7170ff',
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
            { id: 1, name: 'You (preview)', ping: 12, dead: false },
            { id: 2, name: 'Other Player', ping: 48, dead: false }
        ],
        wardrobeShareRequests: [],
        playerName: 'PreviewClient',
        gameHour: 14,
        gameMinute: 32,
        currentWeather: 'CLEAR',
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
                window.postMessage({ action: 'cortex-admin:setState', data: merged }, '*');
                window.postMessage({ action: 'cortex-admin:open' }, '*');
            });
    }

    const nuiJsonHandlers = {
        'cortex-admin:ready': function () {
            injectPreviewUiState();
            return jsonResponse({ ok: true });
        },
        'cortex-admin:getAppearance': function () {
            return jsonResponse(emptyAppearance());
        },
        'cortex-admin:getSavedPeds': function () {
            return jsonResponse([]);
        },
        'cortex-admin:getSavedTeleportLocations': function () {
            return jsonResponse([]);
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
            return jsonResponse({
                vmenuRunning: false,
                peds: { available: false, count: 0, source: 'preview', importedCount: 0 },
                vehicles: { available: false, count: 0, source: 'preview', importedCount: 0 },
                permissions: { mode: 'preview', note: 'Browser preview mode.' }
            });
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
