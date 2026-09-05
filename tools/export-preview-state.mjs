/**
 * Reads shared/actions.lua (EsAdminActions) and writes ui/preview-state.json
 * for browser preview (?preview=1). Run from repo root:
 *   node tools/export-preview-state.mjs
 */
import { readFileSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');
const luaPath = join(root, 'shared', 'actions.lua');
const outPath = join(root, 'ui', 'preview-state.json');

function tokenize(input) {
    const tokens = [];
    let i = 0;
    const len = input.length;

    const push = (type, value) => {
        tokens.push({ type, value, pos: i });
    };

    while (i < len) {
        const c = input[i];

        if (c === '\n' || c === '\r' || c === ' ' || c === '\t') {
            i += 1;
            continue;
        }

        if (c === '-' && input[i + 1] === '-') {
            while (i < len && input[i] !== '\n') i += 1;
            continue;
        }

        if (c === '\'' || c === '"') {
            const quote = c;
            let s = '';
            i += 1;
            while (i < len) {
                const ch = input[i];
                if (ch === '\\' && i + 1 < len) {
                    s += input[i + 1];
                    i += 2;
                    continue;
                }
                if (ch === quote) {
                    i += 1;
                    break;
                }
                s += ch;
                i += 1;
            }
            push('STRING', s);
            continue;
        }

        if (c >= '0' && c <= '9') {
            let start = i;
            while (i < len && /[0-9.eE+-]/.test(input[i])) i += 1;
            push('NUMBER', Number(input.slice(start, i)));
            continue;
        }

        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c === '_') {
            let start = i;
            i += 1;
            while (i < len && /[a-zA-Z0-9_]/.test(input[i])) i += 1;
            const word = input.slice(start, i);
            push('IDENT', word);
            continue;
        }

        if ('{},='.includes(c)) {
            push('PUNCT', c);
            i += 1;
            continue;
        }

        throw new Error(`Unexpected char "${c}" at ${i}`);
    }

    return tokens;
}

function parseTable(tokens, start) {
    let p = start;
    if (tokens[p].type !== 'PUNCT' || tokens[p].value !== '{') {
        throw new Error('Expected { at ' + p);
    }
    p += 1;

    const isArrayLike = () => {
        if (p >= tokens.length) return false;
        const t = tokens[p];
        return t.type === 'PUNCT' && t.value === '{';
    };

    const array = [];
    const obj = {};
    let useArray = null;

    while (p < tokens.length) {
        const t = tokens[p];
        if (t.type === 'PUNCT' && t.value === '}') {
            return [useArray === true ? array : obj, p + 1];
        }

        if (useArray === null) {
            useArray = isArrayLike();
        }

        if (useArray) {
            const [v, np] = parseValue(tokens, p);
            array.push(v);
            p = np;
        } else {
            if (t.type !== 'IDENT') {
                throw new Error('Expected IDENT for key at ' + p);
            }
            const key = t.value;
            p += 1;
            if (tokens[p].type !== 'PUNCT' || tokens[p].value !== '=') {
                throw new Error('Expected = after key at ' + p);
            }
            p += 1;
            const [v, np] = parseValue(tokens, p);
            obj[key] = v;
            p = np;
        }

        if (tokens[p].type === 'PUNCT' && tokens[p].value === ',') {
            p += 1;
        }
    }

    throw new Error('Unclosed table');
}

function parseValue(tokens, start) {
    const t = tokens[start];
    if (!t) throw new Error('Unexpected EOF');

    if (t.type === 'STRING' || t.type === 'NUMBER') {
        return [t.value, start + 1];
    }

    if (t.type === 'IDENT') {
        if (t.value === 'true') return [true, start + 1];
        if (t.value === 'false') return [false, start + 1];
        if (t.value === 'nil') return [null, start + 1];
    }

    if (t.type === 'PUNCT' && t.value === '{') {
        return parseTable(tokens, start);
    }

    throw new Error('Cannot parse value at ' + start + ': ' + JSON.stringify(t));
}

function extractBalancedBlock(text, openBraceIndex) {
    let i = openBraceIndex;
    let depth = 0;
    const len = text.length;

    while (i < len) {
        const c = text[i];

        if (c === '-' && text[i + 1] === '-') {
            while (i < len && text[i] !== '\n') i += 1;
            continue;
        }

        if (c === '\'' || c === '"') {
            const quote = c;
            i += 1;
            while (i < len) {
                const ch = text[i];
                if (ch === '\\' && i + 1 < len) {
                    i += 2;
                    continue;
                }
                if (ch === quote) {
                    i += 1;
                    break;
                }
                i += 1;
            }
            continue;
        }

        if (c === '{') {
            depth += 1;
            i += 1;
            continue;
        }

        if (c === '}') {
            depth -= 1;
            i += 1;
            if (depth === 0) {
                return text.slice(openBraceIndex, i);
            }
            continue;
        }

        i += 1;
    }

    throw new Error('Unbalanced braces in EsAdminActions block');
}

function parseEsAdminActions(luaText) {
    const marker = 'EsAdminActions =';
    const idx = luaText.indexOf(marker);
    if (idx < 0) throw new Error('EsAdminActions = not found');

    const braceStart = luaText.indexOf('{', idx + marker.length);
    if (braceStart < 0) throw new Error('{ not found after EsAdminActions');

    const slice = extractBalancedBlock(luaText, braceStart);
    const tokens = tokenize(slice);
    const [root] = parseTable(tokens, 0);
    return root;
}

const lua = readFileSync(luaPath, 'utf8');
const root = parseEsAdminActions(lua);
const tabs = root.tabs;
const actions = root.actions;

if (!Array.isArray(tabs) || !Array.isArray(actions)) {
    throw new Error('Parsed root missing tabs/actions arrays');
}

const payload = {
    open: true,
    actions,
    tabs,
    favorites: ['player.heal', 'vehicle.spawn'],
    settings: {
        menuPosition: 'right',
        menuAccentColor: '#7170ff',
        uiScale: 1.05,
        uiOpacity: 0.94,
        speedHudPosition: 'top-left',
        speedHudUnits: 'mph',
    },
    toggles: {
        'player.godmode': false,
        'dev.showSpeed': false,
    },
    allowed: {},
    players: [
        { id: 1, name: 'You (preview)', ping: 12, dead: false },
        { id: 2, name: 'Other Player', ping: 48, dead: false },
    ],
    wardrobeShareRequests: [],
    playerName: 'PreviewClient',
    gameHour: 14,
    gameMinute: 32,
    currentWeather: 'CLEAR',
    personalVehicles: [],
    addonVehicles: ['adder', 'zentorno', 'sanchez'],
    frameworkInfo: {
        framework: 'qbx',
        hasInventory: true,
        hasGarage: true,
        hasQBX: true,
    },
    vehiclePreview: {
        active: false,
        model: '',
        shared: false,
    },
    resources: [
        { name: 'es_admin', status: 'started' },
        { name: 'ox_lib', status: 'started' },
        { name: 'example_stopped', status: 'stopped' },
    ],
    inventoryItems: [
        { name: 'bread', label: 'Bread' },
        { name: 'water', label: 'Water' },
    ],
    garageVehicles: [
        { id: 101, model: 'adder', plate: 'PREVIEW1' },
    ],
};

for (let i = 0; i < actions.length; i += 1) {
    const a = actions[i];
    if (a && typeof a === 'object' && a.type === 'toggle' && typeof a.id === 'string') {
        if (payload.toggles[a.id] === undefined) {
            payload.toggles[a.id] = false;
        }
    }
}

writeFileSync(outPath, JSON.stringify(payload, null, 2), 'utf8');
console.log('Wrote', outPath, `(${actions.length} actions)`);
