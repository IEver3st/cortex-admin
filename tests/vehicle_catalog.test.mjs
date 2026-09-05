import { test } from 'bun:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import vm from 'node:vm';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

const source = readFileSync(new URL('../ui/vehicle-controls.js', import.meta.url), 'utf8');
const catalogSource = readFileSync(new URL('../ui/vehicle-catalog/catalog.js', import.meta.url), 'utf8');
function context(overrides = {}) {
    const value = vm.createContext({ React, window: {}, ...overrides });
    vm.runInContext(catalogSource + '\n' + source, value);
    return value;
}
const tick = () => new Promise(resolve => setImmediate(resolve));

test('slow NUI coalesces a 100-event drag to first and latest, preserving exact final value', async () => {
    const api = context(), sent = [], finish = [];
    const queue = api.createVehicleUpdateQueue(payload => {
        sent.push(payload.value); return new Promise(resolve => finish.push(resolve));
    });
    const jobs = Array.from({ length: 100 }, (_, value) => queue.push({ value }, 'paint:primary'));
    assert.deepEqual(sent, [0]);
    finish.shift()({ ok: true }); await tick();
    assert.deepEqual(sent, [0, 99]);
    finish.shift()({ ok: true });
    const results = await Promise.all(jobs);
    assert.equal(results.filter(result => result.superseded).length, 98);
    assert.equal(results.at(-1).ok, true);
});

test('wheel category barriers retain ordering; errors release the queue; closing discards unsent work', async () => {
    const api = context(), sent = [], release = [];
    const queue = api.createVehicleUpdateQueue(payload => {
        sent.push(payload); return new Promise((resolve, reject) => release.push({ resolve, reject }));
    });
    const a = queue.push('sport', 'type');
    const b = queue.push('sport-wheel-3', 'mod:23');
    const c = queue.push('track', 'type');
    const d = queue.push('track-wheel-2', 'mod:23');
    release.shift().resolve({ ok: true }); await tick();
    assert.deepEqual(sent, ['sport', 'sport-wheel-3']);
    release.shift().reject(new Error('native rejected')); await tick();
    assert.deepEqual(sent, ['sport', 'sport-wheel-3', 'track']);
    queue.close();
    release.shift().resolve({ ok: true });
    assert.equal((await b).ok, false);
    assert.equal((await d).cancelled, true);
    assert.equal((await queue.push('late', 'type')).cancelled, true);
    await Promise.all([a, c]);
    assert.equal(sent.length, 3);
});

test('draft updates preserve independent channels, disable custom paint, and never mutate native snapshots', () => {
    const api = context();
    const original = { mods: { 18: { enabled: false } }, colors: { primary: 0, secondary: 5 },
        customPrimary: { enabled: true, value: [40, 50, 60] }, windowTint: 0 };
    const enabled = api.applyVehicleDraft(original, { type: 'mod', id: 18, isToggle: true, enabled: true });
    assert.equal(original.mods[18].enabled, false);
    assert.equal(enabled.mods[18].enabled, true);
    const painted = api.applyVehicleDraft(enabled, { type: 'color', id: 'primary', value: 27 });
    assert.equal(painted.colors.secondary, 5);
    assert.equal(painted.customPrimary.enabled, false);
    assert.equal(api.applyVehicleDraft(painted, { type: 'window', value: 3 }).windowTint, 3);
});

test('all factual paints and wheel thumbnails are packaged locally with matching provenance hashes', () => {
    const api = context(), data = api.window.VehicleCatalogData;
    assert.equal(data.colors.length, 161);
    data.colors.forEach((color, id) => { assert.equal(color.id, id); assert.match(color.hex, /^#[\dA-F]{6}$/); assert.ok(color.name); });
    assert.equal(data.colors[0].hex, '#080808');
    assert.equal(Object.keys(data.wheels).length, 13);
    const sources = JSON.parse(readFileSync(new URL('../ui/vehicle-catalog/sources.json', import.meta.url)));
    assert.equal(sources.wheels.images.length, 491);
    for (const item of sources.wheels.images) {
        const bytes = readFileSync(new URL(`../ui/vehicle-catalog/${item.file}`, import.meta.url));
        assert.equal(bytes.toString('ascii', 0, 4), 'RIFF');
        assert.equal(bytes.toString('ascii', 8, 12), 'WEBP');
        assert.equal(createHash('sha256').update(bytes).digest('hex'), item.sha256);
    }
    for (const category of Object.values(data.wheels)) for (const item of Object.values(category)) {
        assert.ok(existsSync(new URL(`../ui/${item.image}`, import.meta.url)));
    }
});

test('wheel photos match type and native name, never guessed indices or unknown addon names', () => {
    const api = context();
    assert.equal(api.vehicleWheelImage(0, 'Inferno'), 'vehicle-catalog/wheels/0-inferno.webp');
    assert.equal(api.vehicleWheelImage(0, 'Inferno Chrome'), 'vehicle-catalog/wheels/0-chromeinferno.webp');
    assert.equal(api.vehicleWheelImage(1, 'Inferno'), undefined);
    assert.equal(api.vehicleWheelImage(0, 'My addon wheel'), undefined);
    const markup = renderToStaticMarkup(React.createElement(api.VehicleWheelPicker, {
        type: 0, slot: 23, label: 'Front wheels', mod: { current: 0, max: 2, names: { 0: 'Inferno', 1: 'My addon wheel' } }, onChange() {}
    }));
    assert.match(markup, /0-inferno.webp/);
    assert.match(markup, /My addon wheel/);
    assert.doesNotMatch(markup, /0-chromeinferno.webp/);
    assert.equal((markup.match(/<img /g) || []).length, 1);
});

test('large wheel catalogs mount nine options; paint mounts 64 accurate samples; switches expose checked state', () => {
    const api = context();
    const wheels = renderToStaticMarkup(React.createElement(api.VehicleWheelPicker, {
        type: 0, slot: 23, label: 'Front wheels', mod: { current: -1, max: 4096, names: {} }, disabled: true, onChange() {}
    }));
    assert.equal((wheels.match(/aria-pressed=/g) || []).length, 9);
    assert.match(wheels, /disabled=""/);
    const paint = renderToStaticMarkup(React.createElement(api.VehiclePaintPicker, {
        channels: [{ id: 'primary', label: 'Primary' }], colors: { primary: 0 }, onChange() {}
    }));
    assert.equal((paint.match(/title="[^"]+ · #/g) || []).length, 64);
    assert.match(paint, /background-color:#080808/);
    const toggle = renderToStaticMarkup(React.createElement(api.StudioSwitch, { label: 'Neon', checked: true, onChange() {} }));
    assert.match(toggle, /role="switch" aria-checked="true"/);
    assert.match(toggle, /studio-switch-state/);
});

test('plate examples use corrected native IDs, real local textures and game-build availability', () => {
    const api = context();
    const app = readFileSync(new URL('../ui/app.js', import.meta.url), 'utf8');
    const start = app.indexOf('const VehicleConfig ='), end = app.indexOf('\nconst AppearanceConfig', start);
    vm.runInContext(app.slice(start, end) + '\nwindow.plates = VehicleConfig.plates;', api);
    const plates = api.window.plates;
    assert.equal(plates.find(item => item.value === 1).label, 'Yellow on Black');
    assert.equal(plates.find(item => item.value === 2).label, 'Yellow on Blue');
    assert.equal(plates.find(item => item.value === 3).label, 'Blue on White 2');
    assert.equal(plates.find(item => item.value === 10).label, 'LS Panic');
    assert.equal(api.vehiclePlateChoices(plates, 2944).length, 6);
    assert.equal(api.vehiclePlateChoices(plates, 3095).length, 13);
    assert.equal(api.vehiclePlateChoices(plates, undefined).length, 6);
    const markup = renderToStaticMarkup(React.createElement(api.VehiclePlatePicker, {
        options: plates, value: 1, text: 'ABC123', gameBuild: 3095, onChange() {}
    }));
    assert.equal((markup.match(/<img /g) || []).length, 13);
    assert.match(markup, /plates\/1.webp/);
    assert.match(markup, /ABC123/);
    assert.match(markup, /aria-label="Yellow on Black" aria-pressed="true"/);
    const sources = JSON.parse(readFileSync(new URL('../ui/vehicle-catalog/sources.json', import.meta.url)));
    assert.equal(sources.plates.images.length, 13);
    for (const item of sources.plates.images) {
        const bytes = readFileSync(new URL(`../ui/vehicle-catalog/${item.file}`, import.meta.url));
        assert.equal(createHash('sha256').update(bytes).digest('hex'), item.sha256);
    }
});

test('tint illustrations retain native IDs, distinguish model-dependent examples, and convert ARGB correctly', () => {
    const api = context();
    assert.equal(api.window.VehicleCatalogData.tints[0], '#FFFFFF04');
    assert.equal(api.window.VehicleCatalogData.tints[1], '#000000D1');
    const options = ['None', 'Pure Black', 'Dark Smoke', 'Light Smoke', 'Stock', 'Limo', 'Green'].map((label, value) => ({ label, value }));
    const markup = renderToStaticMarkup(React.createElement(api.VehicleTintPicker, { options, value: 3, onChange() {} }));
    assert.equal((markup.match(/<svg /g) || []).length, 7);
    assert.match(markup, /aria-pressed="true" aria-label="Light Smoke"/);
    assert.match(markup, /Illustrated tint samples/);
    assert.match(markup, /Model dependent/);
    assert.doesNotMatch(markup, /[0-9]+%/);
});

test('new assets load once in dependency order and are included in the resource manifest', () => {
    const html = readFileSync(new URL('../ui/index.html', import.meta.url), 'utf8');
    const manifest = readFileSync(new URL('../fxmanifest.lua', import.meta.url), 'utf8');
    const order = ['vehicle-catalog/catalog.js', 'vehicle-controls.js', 'vehicle-studio.js', 'app.js'];
    let previous = -1;
    for (const file of order) {
        const token = `src="${file}?`;
        assert.equal(html.split(token).length - 1, 1, file);
        assert.ok(html.indexOf(token) > previous);
        previous = html.indexOf(token);
        assert.ok(manifest.includes(`'ui/${file}'`));
    }
    assert.ok(manifest.includes("'ui/vehicle-catalog/wheels/*.webp'"));
    assert.ok(manifest.includes("'ui/studio-controls.css'"));
});

// Invoke real component callbacks with deterministic hooks and a delayed NUI
// transport. This is source-level interaction proof, not a browser/game test.
function customizer(section, readNative, sendNative) {
    const slots = [], cleanups = [];
    let cursor = 0;
    const hooks = {
        createElement: (type, props, ...children) => ({ type, props: props || {}, children: children.flat(Infinity) }),
        Fragment: 'fragment',
        useState(initial) {
            const index = cursor++;
            if (!(index in slots)) slots[index] = typeof initial === 'function' ? initial() : initial;
            return [slots[index], value => { slots[index] = typeof value === 'function' ? value(slots[index]) : value; }];
        },
        useRef(initial) { const index = cursor++; return slots[index] ||= { current: initial }; },
        useEffect(effect) { const index = cursor++; if (!(index in slots)) { slots[index] = true; cleanups.push(effect()); } },
        useLayoutEffect() { cursor++; }, useMemo: fn => fn(), useCallback: fn => fn,
    };
    const app = readFileSync(new URL('../ui/app.js', import.meta.url), 'utf8');
    const start = app.indexOf('function VehicleView('), end = app.indexOf('\nconst MemoVehicleView', start);
    const api = context({ React: hooks, ...hooks,
        Icon() {}, WorkspaceHeader() {}, AppearanceCollapsible() {}, CustomSelect() {},
        clamp: (value, min, max) => Math.min(max, Math.max(min, value)),
        VehicleConfig: { mods: [{ id: 23, cat: 'Wheels', label: 'Front wheels' }], colors: [{ id: 'primary', label: 'Primary' }, { id: 'secondary', label: 'Secondary' }],
            wheelTypes: [{ value: 0 }, { value: 12 }], plates: [], windows: [], paintFinishes: [], chameleonColors: [] },
        fetchNui: (event, payload) => event.endsWith('getVehicleCustomization') ? readNative() : sendNative(payload),
    });
    vm.runInContext(app.slice(start, end), api);
    const flatten = tree => !tree || typeof tree !== 'object' ? [] : [tree, ...tree.children.flatMap(flatten)];
    return {
        render() { cursor = 0; return flatten(api.VehicleView({ studioSection: section, studioSession: 'catalog-test' })); },
        close() { cleanups.forEach(fn => fn?.()); }
    };
}

test('wheel type change locks old choices until a fresh native list arrives', async () => {
    let native = { mods: { 23: { current: 0, max: 2, names: { 0: 'Inferno', 1: 'Deep Five' } } }, wheelType: 0, permissions: { mods: true } };
    let finish;
    const ui = customizer('wheels', async () => ({ ok: true, data: native }), payload => {
        assert.equal(payload.studioSession, 'catalog-test');
        return new Promise(resolve => { finish = resolve; });
    });
    ui.render(); await tick();
    const wheel = () => ui.render().find(node => node.type?.name === 'VehicleWheelPicker');
    const selector = ui.render().find(node => node.type?.name === 'CustomSelect' && node.props.options.length === 2);
    const changed = selector.props.onChange(12);
    assert.equal(wheel().props.disabled, true);
    native = { ...native, wheelType: 12, mods: { 23: { current: -1, max: 1, names: { 0: 'Rally Throwback' } } } };
    finish({ ok: true, data: { ok: true } });
    await changed;
    assert.equal(wheel().props.mod.max, 1);
    assert.equal(wheel().props.mod.names[0], 'Rally Throwback');
    assert.equal(wheel().props.disabled, false);
    ui.close();
});

test('rejected optimistic paint reconciles even when another color was edited before rejection', async () => {
    let native = { mods: {}, colors: { primary: 0, secondary: 0 }, permissions: { colors: true } };
    const pending = [];
    const ui = customizer('colors', async () => ({ ok: true, data: native }), payload =>
        new Promise(resolve => pending.push({ payload, resolve })));
    ui.render(); await tick();
    const paint = () => ui.render().find(node => node.type?.name === 'VehiclePaintPicker');
    const primary = paint().props.onChange('primary', 27);
    assert.equal(paint().props.colors.primary, 27, 'Range/swatches respond before NUI acknowledgement');
    const secondary = paint().props.onChange('secondary', 5);
    pending.shift().resolve({ ok: true, data: { ok: false, error: 'forbidden' } }); await tick();
    native = { ...native, colors: { primary: 0, secondary: 5 } };
    pending.shift().resolve({ ok: true, data: { ok: true } });
    await Promise.all([primary, secondary]);
    assert.equal(paint().props.colors.primary, 0, 'Rejected field must not remain selected');
    assert.equal(paint().props.colors.secondary, 5, 'Accepted independent edit is retained');
    ui.close();
});
