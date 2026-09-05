/**
 * Browser-only preview: open ui/index.html?preview=1 (via local static server).
 * Mocks FiveM NUI fetch + pushes initial state after es_admin:ready.
 */
(function () {
    const params = new URLSearchParams(window.location.search);
    if (params.get('preview') !== '1') {
        return;
    }

    window.__ES_ADMIN_PREVIEW__ = true;
    window.GetParentResourceName = function () {
        return 'es_admin';
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
            { name: 'es_admin', status: 'started' },
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
                console.warn('[es_admin preview] Using fallback state. Run: node tools/export-preview-state.mjs');
                return FALLBACK_PREVIEW_STATE;
            })
            .then(function (data) {
                const merged = mergeToggleDefaults(data);
                window.postMessage({ action: 'es_admin:setState', data: merged }, '*');
                window.postMessage({ action: 'es_admin:open' }, '*');
            });
    }

    const nuiJsonHandlers = {
        'es_admin:ready': function () {
            injectPreviewUiState();
            return jsonResponse({ ok: true });
        },
        'es_admin:getAppearance': function () {
            return jsonResponse(emptyAppearance());
        },
        'es_admin:getSavedPeds': function () {
            return jsonResponse([]);
        },
        'es_admin:getSavedTeleportLocations': function () {
            return jsonResponse([]);
        },
        'es_admin:getVehicleCustomization': function () {
            return jsonResponse(emptyVehicleCustomization());
        },
        'es_admin:getPreviewVehicleExtras': function () {
            return jsonResponse({ ok: true, extras: [] });
        },
        'es_admin:getWeaponAttachments': function () {
            return jsonResponse({ ok: true, weaponName: '', components: {} });
        },
        'es_admin:getVmenuMigrationSnapshot': function () {
            return jsonResponse({
                vmenuRunning: false,
                peds: { available: false, count: 0, source: 'preview', importedCount: 0 },
                vehicles: { available: false, count: 0, source: 'preview', importedCount: 0 },
                permissions: { mode: 'preview', note: 'Browser preview mode.' }
            });
        },
        'es_admin:getWardrobeShareTargets': function () {
            return jsonResponse({ ok: true, targets: [] });
        }
    };

    window.fetch = function (url, opts) {
        const u = String(url);
        if (!u.startsWith('https://es_admin/')) {
            return origFetch(url, opts);
        }

        const eventName = u.slice('https://es_admin/'.length);
        if (nuiJsonHandlers[eventName]) {
            return Promise.resolve(nuiJsonHandlers[eventName]());
        }

        if (window.__ES_ADMIN_PREVIEW_DEBUG__) {
            console.debug('[es_admin preview] NUI', eventName, opts && opts.body);
        }
        return Promise.resolve(jsonResponse({ ok: true }));
    };

    console.info('[es_admin] Preview mode. Serve the ui folder over HTTP, e.g. npx serve ui');
})();
