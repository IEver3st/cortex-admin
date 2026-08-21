import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (...parts) => readFileSync(join(root, ...parts), 'utf8');
const state = JSON.parse(read('ui', 'preview-state.json'));
const clientActions = read('client', 'actions.lua');
const compat = read('client', 'vmenu_compat.lua');
const config = read('shared', 'config.lua');
const ui = read('ui', 'app.js');

function between(source, start, end) {
    const from = source.indexOf(start);
    const to = source.indexOf(end, from + start.length);
    if (from < 0 || to < 0) throw new Error(`Unable to isolate ${start}`);
    return source.slice(from, to);
}

function literalIds(source, patterns) {
    const ids = new Set();
    for (const pattern of patterns) {
        for (const match of source.matchAll(pattern)) ids.add(match[1]);
    }
    return ids;
}

const executeSource = between(clientActions, 'Admin.executeAction = function', 'Admin.toggleAction = function');
const toggleSource = between(clientActions, 'Admin.toggleAction = function', 'Admin.selectAction = function');
const selectSource = between(clientActions, 'Admin.selectAction = function', "AddEventHandler('onResourceStop'");
const executeIds = literalIds(executeSource, [/actionId\s*==\s*['"]([^'"]+)['"]/g]);
const toggleIds = literalIds(toggleSource, [/actionId\s*==\s*['"]([^'"]+)['"]/g]);
const selectIds = literalIds(selectSource, [/actionId\s*==\s*['"]([^'"]+)['"]/g]);

for (const id of literalIds(compat, [/executeHandlers\[['"]([^'"]+)['"]\]/g])) executeIds.add(id);
for (const id of literalIds(compat, [/toggleHandlers\[['"]([^'"]+)['"]\]/g])) toggleIds.add(id);
for (const id of literalIds(compat, [/selectHandlers\[['"]([^'"]+)['"]\]/g])) selectIds.add(id);
for (const id of literalIds(ui, [/const\s+is\w+\s*=\s*action\.id\s*===\s*['"]([^'"]+)['"]/g])) executeIds.add(id);
for (const id of literalIds(compat, [/toggles\[['"]([^'"]+)['"]\]/g])) toggleIds.add(id);

const persistentSource = between(compat, 'local persistentToggleIds = {', '}\n\nlocal function notify');
for (const id of literalIds(persistentSource, [/\[['"]([^'"]+)['"]\]\s*=\s*true/g])) toggleIds.add(id);

const supportedTypes = new Set(['action', 'prompt', 'toggle', 'select', 'slider', 'color', 'dock', 'workspace']);
const seen = new Set();
const failures = [];
const coverage = { execute: 0, toggle: 0, select: 0, workspace: 0, capability: 0 };

for (const action of state.actions || []) {
    if (!action || typeof action.id !== 'string' || !action.id) {
        failures.push('Action without a valid id');
        continue;
    }
    if (seen.has(action.id)) failures.push(`${action.id}: duplicate declaration`);
    seen.add(action.id);
    if (!supportedTypes.has(action.type)) {
        failures.push(`${action.id}: unsupported type ${String(action.type)}`);
        continue;
    }
    if (action.type === 'select' && (!Array.isArray(action.values) || action.values.length === 0)) {
        failures.push(`${action.id}: select has no values`);
    }
    if (action.type === 'prompt' && (!action.prompt || !Array.isArray(action.prompt.fields))) {
        failures.push(`${action.id}: prompt has no fields`);
    }

    if (action.capability === true) {
        if (action.hidden !== true) failures.push(`${action.id}: capability records must be hidden`);
        else coverage.capability += 1;
        continue;
    }

    if (action.type === 'action' || action.type === 'prompt') {
        if (!executeIds.has(action.id)) failures.push(`${action.id}: ${action.type} has no execute handler`);
        else coverage.execute += 1;
    } else if (action.type === 'toggle') {
        if (!toggleIds.has(action.id)) failures.push(`${action.id}: toggle has no toggle or persistent-loop handler`);
        else coverage.toggle += 1;
    } else if (action.type === 'select' || action.type === 'slider' || action.type === 'color' || action.type === 'dock') {
        if (!selectIds.has(action.id)) failures.push(`${action.id}: ${action.type} has no select handler`);
        else coverage.select += 1;
    } else if (action.type === 'workspace') {
        if (typeof action.workspaceTab !== 'string' || !action.workspaceTab || !ui.includes(`id: '${action.workspaceTab}'`)) {
            failures.push(`${action.id}: workspace has no reachable sidebar destination`);
        } else coverage.workspace += 1;
    }
}

const permissionSource = between(config, 'Config.ActionPermissions = {', 'Config.BanIdentifierTypes');
const permissionIds = literalIds(permissionSource, [/\[['"]([^'"]+)['"]\]\s*=/g]);
const uiExecuteIds = literalIds(ui, [
    /fetchNui\(\s*['"]cortex-admin:action['"]\s*,\s*\{\s*id:\s*['"]([^'"]+)['"]/g,
]);
for (const id of uiExecuteIds) {
    if (!seen.has(id) && !permissionIds.has(id)) failures.push(`${id}: UI emits an action absent from catalog and action permissions`);
    if (!executeIds.has(id)) failures.push(`${id}: UI-emitted action has no execute handler`);
}

const activationSource = between(ui, 'const activateAction = React.useCallback', 'const activateSelectedItem = React.useCallback');
if (!activationSource.includes("action.type === 'select'")) {
    failures.push('keyboard activation does not exclude select actions from execute dispatch');
}
if (!activationSource.includes("action.type === 'workspace'") || !activationSource.includes('setActiveTab(action.workspaceTab)')) {
    failures.push('keyboard activation does not route workspace actions to their tab');
}
if (!compat.includes('Admin.dispatchVmenuAction = function')
    || !clientActions.includes("Admin.dispatchVmenuAction('execute'")
    || !clientActions.includes("Admin.dispatchVmenuAction('toggle'")
    || !clientActions.includes("Admin.dispatchVmenuAction('select'")) {
    failures.push('compatibility dispatch is not registered with the base action router');
}

if (failures.length) {
    console.error(`Action parity audit failed (${failures.length} issue${failures.length === 1 ? '' : 's'}):`);
    for (const failure of failures) console.error(`- ${failure}`);
    process.exitCode = 1;
} else {
    console.log(`Action parity audit passed: ${seen.size} unique actions`);
    console.log(`execute=${coverage.execute} toggle=${coverage.toggle} select=${coverage.select} workspace=${coverage.workspace} capability=${coverage.capability}`);
}
