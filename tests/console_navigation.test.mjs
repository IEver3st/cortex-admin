import { test } from 'bun:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

const source = fs.readFileSync(new URL('../ui/app.js', import.meta.url), 'utf8');
const navigation = source.slice(source.indexOf('const SIDEBAR_SECTIONS ='), source.indexOf('\nfunction CoordHud('));
const setup = extra => {
    const context = vm.createContext({ React, useState: React.useState, useCallback: React.useCallback,
        Icon: () => null, createPortal: () => null, fetchNui: () => {}, ...extra });
    vm.runInContext(navigation, context);
    return context;
};

test('navigation exposes one active destination, studios, and permission-filtered tools', () => {
    const ctx = setup();
    const html = renderToStaticMarkup(React.createElement(ctx.Sidebar, {
        activeTab: 'weapons', allowed: { 'vehicle.customMods': true, 'vehicle.liveTuning': false },
        frameworkInfo: { hasInventory: false, hasGarage: false }, onViewChange() {}
    }));
    assert.match(html, /aria-controls="console-task-navigation"/);
    assert.match(html, /aria-current="page"><span>Player<\/span>/);
    assert.equal((html.match(/aria-current="page"/g) || []).length, 1);
    assert.match(html, /aria-label="Launch Vehicle Studio"/);
    assert.match(html, /aria-label="Launch Character Studio"/);
    const tabs = ctx.consoleWorkflowTabs('vehicle', { 'vehicle.liveTuning': false }, { hasGarage: false });
    assert.deepEqual(Array.from(tabs, item => item.id), ['vehicle']);
    const denied = renderToStaticMarkup(React.createElement(ctx.Sidebar, { activeTab: 'all', allowed: {}, frameworkInfo: {}, onViewChange() {} }));
    assert.doesNotMatch(denied, /Launch Vehicle Studio/);
});

test('index expansion closes on navigation and sends the original tab contract', () => {
    let cursor = 0;
    const slots = [];
    const calls = [];
    const ctx = setup({
        useState(initial) {
            const index = cursor++;
            if (!(index in slots)) slots[index] = initial;
            return [slots[index], next => { slots[index] = typeof next === 'function' ? next(slots[index]) : next; }];
        },
        useCallback: callback => callback,
    });
    const props = { activeTab: 'all', allowed: { 'vehicle.customMods': true }, frameworkInfo: {},
        onViewChange: (...args) => calls.push(args) };
    const render = () => { cursor = 0; return ctx.Sidebar(props); };
    const walk = element => !React.isValidElement(element) ? [] : [element, ...React.Children.toArray(element.props.children).flatMap(walk)];
    const toggle = tree => walk(tree).find(node => node.props.className === 'console-menu-toggle');
    toggle(render()).props.onClick();
    let tree = render();
    assert.equal(toggle(tree).props['aria-expanded'], true);
    walk(tree).find(node => node.props['aria-label'] === 'Launch Vehicle Studio').props.onClick();
    assert.deepEqual(calls, [['vehicle_custom', 'vehicle_custom']]);
    assert.equal(toggle(render()).props['aria-expanded'], false);
    toggle(render()).props.onClick();
    let focused = false;
    let stopped = false;
    walk(render()).find(node => node.props.id === 'console-task-navigation').props.onKeyDown({ key: 'Escape', preventDefault() {}, stopPropagation() { stopped = true; },
        currentTarget: { parentElement: { querySelector: () => ({ focus() { focused = true; } }) } } });
    assert.equal(toggle(render()).props['aria-expanded'], false);
    assert.equal(focused && stopped, true);
});

test('button Enter is not also dispatched to a selected admin action', () => {
    const start = source.indexOf('const keyHandler = (event) => {', source.indexOf('function App()'));
    const end = source.indexOf("window.addEventListener('keydown', keyHandler);", start);
    let runs = 0;
    let prevented = 0;
    const ctx = vm.createContext({
        document: { body: { classList: { contains: () => false } } },
        isDedicatedVmenuWorkspace: false,
        activateRef: { current: () => runs++ },
    });
    vm.runInContext(`${source.slice(start, end)}globalThis.handleKey = keyHandler;`, ctx);
    const event = target => ({ key: 'Enter', target, preventDefault: () => prevented++, stopPropagation() {} });
    ctx.handleKey(event({ tagName: 'BUTTON', closest: () => ({}) }));
    ctx.handleKey(event({ tagName: 'SPAN', closest: () => ({}) }));
    assert.equal(runs, 0);
    assert.equal(prevented, 0);
    ctx.handleKey(event({ tagName: 'DIV', closest: () => null }));
    assert.equal(runs, 1);
    assert.equal(prevented, 1);
});

test('console stylesheet loads before studio overrides and is packaged', () => {
    const html = fs.readFileSync(new URL('../ui/index.html', import.meta.url), 'utf8');
    const manifest = fs.readFileSync(new URL('../fxmanifest.lua', import.meta.url), 'utf8');
    assert.ok(html.indexOf('href="console.css?') > html.indexOf('href="style.css?'));
    assert.ok(html.indexOf('href="console.css?') < html.indexOf('href="character-studio.css?'));
    assert.match(manifest, /'ui\/console\.css'/);
    const css = fs.readFileSync(new URL('../ui/console.css', import.meta.url), 'utf8');
    assert.doesNotMatch(css, /(?:linear|radial|conic)-gradient\s*\(/);
});

function renderConsole(overrides = {}) {
    // Server-render the real app. This checks composition and escaping, not pixels.
    const appSource = source.slice(source.indexOf('function App()'));
    const states = Array.from(appSource.matchAll(/const \[(\w+),[^\]]+\] = useState\(/g), match => match[1]);
    const seed = { open: true, playerName: '<Admin>', favorites: ['vehicle.repair'],
        allowed: { 'vehicle.customMods': true }, actions: [
            { id: 'vehicle.repair', tab: 'vehicle', type: 'action', label: 'Repair vehicle', description: 'Restore the current vehicle', section: 'Vehicle' },
            { id: 'player.noclip', tab: 'player', type: 'toggle', label: 'Noclip', description: 'Move freely', section: 'Player' },
        ], ...overrides };
    let index = 0;
    const hooks = { ...React, useLayoutEffect: React.useEffect, useState(initial) {
        const key = states[index++];
        return React.useState(Object.hasOwn(seed, key) ? seed[key] : initial);
    } };
    const ctx = vm.createContext({ React: hooks, ReactDOM: { createPortal: () => null }, URLSearchParams,
        window: { location: { search: '' }, innerWidth: 1920, innerHeight: 1080, addEventListener() {},
            getComputedStyle: () => ({ getPropertyValue: () => '1' }) },
        document: { documentElement: { style: { setProperty() {} } }, getElementById: () => null },
    });
    vm.runInContext(source, ctx);
    return renderToStaticMarkup(React.createElement(ctx.App));
}

test('the complete workspace produces static markup with left favorites and persistent search', () => {
    const html = renderConsole();
    assert.match(html, /<main[^>]+aria-label="Workspace"/);
    assert.match(html, /Pinned commands/);
    assert.match(html, /Quick tools/);
    assert.match(html, /&lt;Admin&gt;/);
    assert.ok(html.indexOf('console-command-toolbar') < html.indexOf('class="admin-content"'));
    const row = html.slice(html.indexOf('class="admin-action-row"'));
    assert.ok(row.indexOf('admin-action-star') < row.indexOf('admin-action-info'));
});

test('studio launch requests run once and do not restart after ordinary rerenders or menu reopen', () => {
    const vehicle = fs.readFileSync(new URL('../ui/vehicle-studio.js', import.meta.url), 'utf8');
    for (const code of [source, vehicle]) {
        const start = code.indexOf('    const lastStudioLaunch =');
        const end = code.indexOf('    const exitStudio =', start);
        let opens = 0;
        const ref = { current: 0 };
        const hooks = { useRef: () => ref, useEffect: callback => callback() };
        const ctx = vm.createContext({ ...hooks, React: hooks, launchRequest: 1, menuOpen: true,
            openStudio: () => opens++, open: mode => { assert.equal(mode, 'current'); opens++; } });
        const run = () => vm.runInContext(`{${code.slice(start, end)}}`, ctx);
        run(); run();
        assert.equal(opens, 1);
        ctx.menuOpen = false; run(); ctx.menuOpen = true; run();
        assert.equal(opens, 1);
        ctx.launchRequest = 2; run();
        assert.equal(opens, 2);
    }
});


test('Self commands and Online Players have independent pages and searches', () => {
    const self = renderConsole({ activeTab: 'player' });
    assert.match(self, /Noclip/);
    assert.match(self, />Self<\/button>/);
    assert.doesNotMatch(self, /class="admin-player-workspace"/);
    const players = renderConsole({ activeTab: 'players' });
    assert.match(players, /class="admin-player-workspace"/);
    assert.match(players, /aria-label="Find online player"/);
    assert.doesNotMatch(players, /console-command-toolbar|admin-action-row/);
});
