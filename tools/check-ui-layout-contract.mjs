import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const css = fs.readFileSync(path.join(root, 'ui', 'style.css'), 'utf8');
const app = fs.readFileSync(path.join(root, 'ui', 'app.js'), 'utf8');
const cssWithoutComments = css.replace(/\/\*[\s\S]*?\*\//g, '');

const failures = [];

function ruleBody(selector) {
    const rulePattern = /([^{}]+)\{([^{}]*)\}/g;
    let body = '';
    let match;

    while ((match = rulePattern.exec(cssWithoutComments)) !== null) {
        const selectors = match[1].split(',').map((entry) => entry.trim());
        if (selectors.includes(selector)) body += `\n${match[2]}`;
    }

    return body;
}

function requireDeclarations(selector, declarations) {
    const body = ruleBody(selector);
    if (!body) {
        failures.push(`Missing CSS rule: ${selector}`);
        return;
    }

    for (const declaration of declarations) {
        if (!body.includes(declaration)) {
            failures.push(`${selector} must include "${declaration}"`);
        }
    }
}

function requireSource(fragment, description) {
    if (!app.includes(fragment)) failures.push(description);
}

const actionStart = app.indexOf('const ActionItem = React.memo');
const actionEnd = app.indexOf('\nfunction Modal(', actionStart);
const actionSource = actionStart >= 0 && actionEnd > actionStart ? app.slice(actionStart, actionEnd) : '';
const infoIndex = actionSource.indexOf("className: 'admin-action-info'");
const favoriteIndex = actionSource.indexOf('className: `admin-action-star');

if (!actionSource) {
    failures.push('Could not isolate ActionItem source');
} else if (infoIndex < 0 || favoriteIndex < 0 || infoIndex >= favoriteIndex) {
    failures.push('ActionItem must render command copy before the favorite control so labels start at the left content edge');
}

requireDeclarations('.admin-action-info', ['flex: 1;', 'min-width: 0;']);
requireDeclarations('.admin-action-enabled-dot', ['position: absolute;']);
requireDeclarations('.admin-select-trigger', ['min-height: calc(32px * var(--es-ui-scale));', 'font-size: calc(12px * var(--es-ui-scale));']);
requireDeclarations('.admin-select-option', ['flex: 0 0 auto;', 'min-height: calc(32px * var(--es-ui-scale));', 'line-height: 1.25;']);
requireDeclarations('.appearance-header--wardrobe', ['display: grid;', 'grid-template-columns:']);
requireDeclarations('.appearance-row--wardrobe', ['display: grid;', 'grid-template-columns:']);
requireDeclarations('.appearance-h-col-steppers', ['display: grid;', 'grid-template-columns:']);
requireDeclarations('.appearance-stepper-row--wardrobe', ['display: grid;', 'grid-template-columns:', 'min-width: 0;']);
requireDeclarations('.appearance-stepper-row--wardrobe .appearance-stepper-group', ['display: grid;', 'grid-template-columns:', 'min-width: 0;']);
requireDeclarations('.admin-shell.is-cramped .appearance-stepper-row--wardrobe', ['grid-template-columns: minmax(0, 1fr);']);
requireDeclarations('.admin-shell.docked-right .appearance-stepper-row--wardrobe', ['grid-template-columns: minmax(0, 1fr);']);
requireDeclarations('.admin-shell.is-cramped .appearance-header--wardrobe', ['display: none;']);
requireDeclarations('.appearance-stepper-unit', ['min-width: 0;']);
requireDeclarations('.appearance-stepper-input', ['min-width: 0;']);
requireDeclarations('.appearance-section-stack--wardrobe-scroll', ['overflow-y: auto;', 'overflow-x: hidden;']);
requireDeclarations('.appearance-section-stack--wardrobe-scroll > .appearance-row', ['flex-shrink: 0;']);
requireDeclarations('.admin-main', ['min-width: 0;', 'min-height: 0;', 'overflow: hidden;']);
requireDeclarations('.admin-column', ['overflow-y: auto;', 'overflow-x: hidden;', 'min-height: 0;']);
requireDeclarations('.admin-column > *', ['min-width: 0;', 'max-width: 100%;']);
requireDeclarations('.admin-workspace-heading', ['flex: 1 1 0;', 'min-width: 0;']);
requireDeclarations('.admin-shell.docked-right .admin-workspace-header', ['align-items: stretch;', 'flex-direction: column;']);
requireDeclarations('.admin-shell.docked-right .admin-workspace-header-actions', ['width: 100%;', 'justify-content: flex-end;', 'flex-wrap: wrap;']);
requireDeclarations('.admin-shell.is-cramped .admin-workspace-header', ['align-items: stretch;', 'flex-direction: column;']);
requireDeclarations('.admin-shell.is-cramped .admin-workspace-header-actions', ['width: 100%;', 'justify-content: flex-end;', 'flex-wrap: wrap;']);
requireDeclarations('.admin-config-domain', ['display: flex;', 'align-items: center;', 'justify-content: space-between;', 'min-width: 0;']);
requireDeclarations('.admin-config-domain > div', ['display: flex;', 'flex-direction: column;', 'min-width: 0;']);
requireDeclarations('.admin-config-domain small', ['overflow: hidden;', 'text-overflow: ellipsis;', 'white-space: nowrap;']);
requireDeclarations('.admin-config-domain > span', ['flex: 0 0 auto;', 'font-family: var(--font-mono);']);
requireDeclarations('.admin-column:has(> .admin-appearance)', ['display: flex;', 'overflow: hidden;']);
requireDeclarations('.admin-appearance', ['flex: 1 1 0;', 'min-height: 0;']);
requireDeclarations('.admin-appearance > :not(.appearance-content-area)', ['flex-shrink: 0;']);
requireDeclarations('.appearance-content-area--scroll', ['flex: 1;', 'min-height: 0;', 'overflow-y: auto;', 'overflow-x: hidden;']);
requireDeclarations('.appearance-content-area--scroll > .appearance-collapsible', ['flex-shrink: 0;']);
requireDeclarations('.appearance-slider', ['min-width: 0;']);
requireDeclarations('.appearance-btn', ['flex-shrink: 0;']);
requireDeclarations('.admin-shell.is-cramped .appearance-row:not(.appearance-row--wardrobe)', ['flex-direction: column;', 'align-items: stretch;']);
requireDeclarations('.admin-shell.is-cramped .appearance-row:not(.appearance-row--wardrobe) .appearance-label', ['min-width: 0;']);
requireDeclarations('.admin-shell.is-cramped .appearance-row:not(.appearance-row--wardrobe) > .appearance-control', ['width: 100%;', 'min-width: 0;']);
requireDeclarations('.admin-shell.is-cramped .appearance-row:not(.appearance-row--wardrobe) > .admin-select', ['width: 100%;', 'min-width: 0;']);
requireDeclarations('.admin-shell.is-cramped .appearance-row:not(.appearance-row--wardrobe) .appearance-slider', ['min-width: 0;', 'max-width: none;']);
requireDeclarations('.admin-shell.is-cramped .appearance-heritage-layout', ['grid-template-columns: minmax(0, 1fr);']);
requireDeclarations('.admin-shell.docked-right .vehicle-custom-extra-grid', ['grid-template-columns: minmax(0, 1fr);']);
requireDeclarations('.vehicle-custom-rgb-head', ['flex-wrap: wrap;', 'min-width: 0;']);
requireDeclarations('.vehicle-custom-rgb-head > div', ['flex: 1;', 'min-width: 0;']);
requireDeclarations('.appearance-collapsible-panel', ['min-width: 0;', 'width: 100%;']);
requireDeclarations('.feature-discovery-dot', ['border-radius: 50%;', 'background: #2ea8ff;']);
requireDeclarations('.appearance-generator', ['min-width: 0;']);
requireDeclarations('.appearance-generator-grid', ['grid-template-columns: repeat(2, minmax(0, 1fr));', 'min-width: 0;']);
requireDeclarations('.appearance-generator-choice', ['min-width: 0;']);
requireDeclarations('.appearance-generator-select .admin-select', ['width: 100%;', 'min-width: 0;']);
requireDeclarations('.appearance-generator-switch.is-on .appearance-generator-switch-track', ['border-color: var(--accent);', 'background: var(--accent);']);
requireDeclarations('.appearance-generator-actions', ['display: grid;', 'grid-template-columns: minmax(0, 1fr) calc(36px * var(--es-ui-scale));', 'min-width: 0;']);
requireDeclarations('.appearance-generator-status:not(.is-error)', ['position: absolute;', 'width: 1px;', 'overflow: hidden;']);
requireDeclarations('.appearance-saved-outfit-row', ['display: grid;', 'grid-template-columns: minmax(0, 1fr) auto;', 'min-width: 0;']);
requireDeclarations('.appearance-workspace-utility', ['display: flex;', 'justify-content: space-between;', 'min-width: 0;']);
requireDeclarations('.admin-shell.docked-left .appearance-saved-outfit-row', ['grid-template-columns: minmax(0, 1fr);']);
requireDeclarations('.admin-shell.is-cramped .appearance-generator-grid', ['grid-template-columns: minmax(0, 1fr);']);
requireSource("className: 'appearance-stepper-unit-label'", 'Wardrobe steppers must render per-control labels for constrained layouts');
requireSource("querySelector('.appearance-content-area--scroll')", 'Admin-column wheel routing must target the nested appearance/vehicle page scroll owner');
requireSource("role: 'switch'", 'Appearance generator accessory control must expose switch semantics');
requireSource("'aria-live': 'polite'", 'Appearance generator progress and result messages must be announced');
requireSource("generatorSelect('faceProfile', 'Face profile'", 'Appearance generator face profile must use the custom dropdown');
requireSource("className: 'admin-button appearance-generator-undo appearance-icon-btn'", 'Appearance generator undo must stay in the compact icon slot');
requireSource('normalizeSavedOutfitEntry', 'Saved outfit payloads must retain a visible player-facing name');
requireSource("appearance-workspace-utility--empty-share", 'No-nearby-player state must use the compact utility row');
requireSource("migrationAvailable && React.createElement", 'Unavailable vMenu import must stay out of the outfit workspace');
requireSource('FEATURE_DISCOVERY_STORAGE_KEY', 'New feature discovery must persist per player');
requireSource("markFeatureDiscovered('appearanceGenerator')", 'Opening the appearance generator must clear its new feature dot');

if (failures.length > 0) {
    console.error('UI layout contract failed:');
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
}

console.log('UI layout contract passed.');
