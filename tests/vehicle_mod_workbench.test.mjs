import { test } from 'bun:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

const source = readFileSync(new URL('../ui/vehicle-studio.js', import.meta.url), 'utf8');
const config = [
    { id: 11, label: 'Engine', cat: 'Performance' },
    { id: 18, label: 'Turbo', cat: 'Performance', isToggle: true },
    { id: 0, label: 'Spoilers', cat: 'Exterior' },
    { id: 32, label: 'Seats', cat: 'Interior' },
    { id: 23, label: 'Front wheels', cat: 'Wheels' },
];
const fixture = () => ({
    11: { current: -1, max: 4, names: { 0: 'EMS upgrade' } },
    18: { isToggle: true, enabled: true },
    0: { current: -1, max: 14, names: {} },
    32: { current: -1, max: 0, names: {} },
    23: { current: -1, max: 5, names: {} },
});

// Exercise component callbacks without starting a browser, NUI or game runtime.
function harness(name, props, extra = {}) {
    const slots = [], cleanups = [];
    let cursor = 0;
    const hooks = {
        createElement: (type, props, ...children) => ({ type, props: props || {}, children: children.flat(Infinity) }),
        useState(initial) {
            const index = cursor++;
            if (!(index in slots)) slots[index] = typeof initial === 'function' ? initial() : initial;
            return [slots[index], value => { slots[index] = typeof value === 'function' ? value(slots[index]) : value; }];
        },
        useRef(initial) { const index = cursor++; return slots[index] ||= { current: initial }; },
        useEffect(effect) { const index = cursor++; if (!(index in slots)) { slots[index] = true; cleanups.push(effect()); } },
        useId: () => 'fixture',
        useMemo: derive => derive(),
        useCallback: callback => callback,
        useLayoutEffect() {},
    };
    const context = vm.createContext({ React: hooks, ...hooks, Icon: () => null, ...extra.globals });
    vm.runInContext(source, context);
    if (extra.source) vm.runInContext(extra.source, context);
    return {
        render() { cursor = 0; return context[name](props); },
        unmount() { cleanups.forEach(cleanup => cleanup?.()); },
    };
}
function nodes(tree) {
    return !tree || typeof tree !== 'object' ? [] : [tree, ...tree.children.flatMap(nodes)];
}
function by(tree, prop, value) {
    return nodes(tree).find(node => node.props[prop] === value);
}
function button(tree, text) {
    return nodes(tree).find(node => node.type === 'button' && node.children.includes(text));
}

test('static markup exposes stock, native names and turbo semantics without numeric sliders', () => {
    const context = vm.createContext({ React, Icon: () => null });
    vm.runInContext(source, context);
    const markup = renderToStaticMarkup(React.createElement(context.VehicleModWorkbench, { mods: fixture(), config, onUpdate() {} }));
    assert.match(markup, /aria-label="Engine: Stock"[^>]*aria-pressed="true"/);
    assert.match(markup, /Engine: EMS upgrade/);
    assert.match(markup, /role="switch" aria-label="Turbo" aria-checked="true"/);
    assert.doesNotMatch(markup, /type="range"|−1|\-1\/|Spoilers|Seats|Front wheels/);
});

test('rapid selections send one request and preserve confirmed state until acknowledgement', async () => {
    const mods = fixture(), calls = [];
    let finish;
    const ui = harness('VehicleModWorkbench', { mods, config, onUpdate: (...args) => {
        calls.push(args); return new Promise(resolve => { finish = resolve; });
    } });
    let tree = ui.render();
    const target = by(tree, 'aria-label', 'Engine: EMS upgrade');
    const pending = target.props.onClick();
    await target.props.onClick();
    tree = ui.render();
    assert.equal(calls.length, 1);
    assert.deepEqual(calls[0], ['mod', 11, 0, false, undefined]);
    assert.equal(by(tree, 'aria-label', 'Engine: Stock').props['aria-pressed'], true);
    assert.equal(by(tree, 'aria-label', 'Engine: EMS upgrade').props['aria-disabled'], true);
    mods[11] = { ...mods[11], current: 0 }; // Parent publishes the accepted change.
    finish(true); await pending;
    tree = ui.render();
    assert.equal(by(tree, 'aria-label', 'Engine: EMS upgrade').props['aria-pressed'], true);
    assert.equal(tree.props['aria-busy'], false);
    const stock = by(tree, 'aria-label', 'Engine: Stock').props.onClick();
    assert.equal(calls[1][2], -1, 'Stock must retain the native -1 payload');
    finish(true); await stock;
});

test('turbo off sends false, rejected and thrown requests release the lock for retry', async () => {
    const calls = [];
    const ui = harness('VehicleModWorkbench', { mods: fixture(), config, onUpdate: async (...args) => {
        calls.push(args);
        if (calls.length === 2) throw new Error('transport failed');
        return false;
    } });
    await by(ui.render(), 'role', 'switch').props.onClick();
    assert.deepEqual(calls[0], ['mod', 18, null, true, false]);
    let tree = ui.render();
    assert.equal(by(tree, 'role', 'switch').props['aria-checked'], true);
    assert.equal(tree.props['aria-busy'], false);
    assert.ok(by(tree, 'className', 'vehicle-mod-feedback is-error'));
    await by(tree, 'role', 'switch').props.onClick();
    await by(ui.render(), 'role', 'switch').props.onClick();
    assert.equal(calls.length, 3);
    ui.unmount();
});

test('bodywork filters unsupported groups and opens only one part', () => {
    const mods = fixture();
    const ui = harness('VehicleModWorkbench', { mods, config, onUpdate() {} });
    button(ui.render(), 'Bodywork').props.onClick();
    let tree = ui.render();
    assert.equal(button(tree, 'Cabin'), undefined);
    assert.equal(nodes(tree).filter(node => node.props.className === 'vehicle-mod-part-trigger').length, 1);
    const trigger = by(tree, 'className', 'vehicle-mod-part-trigger');
    trigger.props.onClick();
    tree = ui.render();
    assert.equal(by(tree, 'className', 'vehicle-mod-part-trigger').props['aria-expanded'], true);
    assert.equal(nodes(tree).filter(node => node.props.className === 'vehicle-mod-part is-expanded').length, 1);
    mods[0] = { ...mods[0], max: 0 };
    assert.ok(by(ui.render(), 'className', 'vehicle-mod-empty'));
});

test('all parts share one list without pagination and keep exact last/stock values', () => {
    const chosen = [];
    const ui = harness('VehicleModChoices', { item: config[2], state: { current: 4095, max: 4096, names: {} }, pending: false, onSelect: value => chosen.push(value) });
    let tree = ui.render();
    const choices = nodes(tree).filter(node => node.props.className === 'vehicle-mod-choice');
    assert.equal(choices.length, 4097);
    assert.equal(by(tree, 'className', 'vehicle-mod-pagination'), undefined);
    by(tree, 'aria-pressed', true).props.onClick();
    assert.equal(chosen[0], 4095);
    choices[0].props.onClick();
    assert.equal(chosen[1], -1);
});

test('native labels render as text and unusual performance counts use bounded choices', () => {
    const context = vm.createContext({ React, Icon: () => null });
    vm.runInContext(source, context);
    const markup = renderToStaticMarkup(React.createElement(context.VehicleModChoices, {
        item: config[2], state: { current: 0, max: 1, names: { 0: '<img src=x onerror=alert(1)>' } }, onSelect() {}, pending: false,
    }));
    assert.match(markup, /&lt;img/);
    assert.doesNotMatch(markup, /<img/);
    const mods = fixture(); mods[11].max = 4096;
    const ui = harness('VehicleModWorkbench', { mods, config, onUpdate() {} });
    assert.equal(by(ui.render(), 'className', 'vehicle-mod-stages'), undefined);
    assert.ok(by(ui.render(), 'className', 'vehicle-mod-part-trigger'));
});

test('VehicleView integration keeps discrete mods confirmed while using the shared request queue', async () => {
    const app = readFileSync(new URL('../ui/app.js', import.meta.url), 'utf8');
    const start = app.indexOf('function VehicleView(');
    const end = app.indexOf('\nconst MemoVehicleView', start);
    assert.ok(start > 0 && end > start);
    const controls = readFileSync(new URL('../ui/vehicle-controls.js', import.meta.url), 'utf8');
    let finish;
    const sent = [];
    const ui = harness('VehicleView', { studioSession: 'session-test', studioSection: 'mods' }, {
        source: controls + '\n' + app.slice(start, end),
        globals: {
            VehicleConfig: { mods: config },
            WorkspaceHeader() {}, AppearanceCollapsible() {}, scheduleLucideIcons() {},
            fetchNui: async (event, payload) => {
                sent.push({ event, payload });
                if (event.endsWith('getVehicleCustomization')) return { ok: true, data: { mods: fixture(), permissions: { mods: true } } };
                return new Promise(resolve => { finish = resolve; });
            },
        },
    });
    ui.render();
    await new Promise(resolve => setTimeout(resolve, 0));
    const workbench = () => nodes(ui.render()).find(node => node.type?.name === 'VehicleModWorkbench');
    assert.equal(workbench().props.mods[11].current, -1);
    const changing = workbench().props.onUpdate('mod', 11, 0, false);
    assert.equal(workbench().props.mods[11].current, -1, 'Parent must not publish an optimistic selection');
    assert.equal(sent.at(-1).payload.studioSession, 'session-test');
    finish({ ok: true, data: { ok: true } });
    assert.equal(await changing, true);
    assert.equal(workbench().props.mods[11].current, 0);
    ui.unmount();
});
