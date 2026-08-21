const { useState, useEffect, useMemo, useCallback, useLayoutEffect } = React;
const { createPortal } = ReactDOM;
const h = React.createElement;

const UI_VERSION_LABEL = 'v1.1.0';
const MODEL_HASH_MP_M = 0x705e61f2 >>> 0;
const MODEL_HASH_MP_F = 0x9c9effd8 >>> 0;
const FEATURE_DISCOVERY_STORAGE_KEY = 'cortex-admin.discovered-features.v1';
const FEATURE_RELEASES = Object.freeze({
    appearanceGenerator: 'custom-character-generator-2026-08-19'
});

function readDiscoveredFeatureReleases() {
    try {
        const raw = window.localStorage.getItem(FEATURE_DISCOVERY_STORAGE_KEY);
        const parsed = raw ? JSON.parse(raw) : {};
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return {};

        return Object.fromEntries(Object.entries(parsed)
            .filter(([key, value]) => typeof key === 'string' && typeof value === 'string')
            .slice(-100));
    } catch (_) {
        return {};
    }
}

function writeDiscoveredFeatureReleases(releases) {
    try {
        window.localStorage.setItem(FEATURE_DISCOVERY_STORAGE_KEY, JSON.stringify(releases));
    } catch (_) {
        // Discovery hints are optional; a blocked storage API must not break NUI.
    }
}

function modelHashU32(model) {
    const n = Number(model);
    if (!Number.isFinite(n)) return 0;
    return n >>> 0;
}

const LUCIDE_ATTR_MAP = {
    class: 'className',
    'stroke-width': 'strokeWidth',
    'stroke-linecap': 'strokeLinecap',
    'stroke-linejoin': 'strokeLinejoin',
    'fill-rule': 'fillRule',
    'clip-rule': 'clipRule',
    'stroke-miterlimit': 'strokeMiterlimit',
    'stroke-dasharray': 'strokeDasharray',
    'stroke-dashoffset': 'strokeDashoffset',
    'xmlns:xlink': 'xmlnsXlink',
    'xlink:href': 'xlinkHref'
};

function toLucideExportName(name) {
    return String(name || '')
        .split(/[^a-zA-Z0-9]+/)
        .filter(Boolean)
        .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
        .join('');
}

function getLucideIconNode(name) {
    if (!name || typeof window.lucide === 'undefined') {
        return null;
    }

    const exportName = toLucideExportName(name);
    if (!exportName) {
        return null;
    }

    return window.lucide[exportName]
        || (window.lucide.icons && (window.lucide.icons[exportName] || window.lucide.icons[name]))
        || null;
}

function buildLucideProps(attrs, extraProps) {
    const normalized = {};
    const attrEntries = Object.entries(attrs || {});

    for (let index = 0; index < attrEntries.length; index += 1) {
        const [key, value] = attrEntries[index];
        normalized[LUCIDE_ATTR_MAP[key] || key] = value;
    }

    const extras = { ...(extraProps || {}) };
    const mergedClassName = [normalized.className, extras.className].filter(Boolean).join(' ');
    const mergedStyle = normalized.style || extras.style
        ? { ...(normalized.style || {}), ...(extras.style || {}) }
        : undefined;

    delete extras.className;
    delete extras.style;

    if (mergedClassName) {
        normalized.className = mergedClassName;
    }

    if (mergedStyle) {
        normalized.style = mergedStyle;
    }

    return {
        ...normalized,
        ...extras
    };
}

function renderLucideNode(node, extraProps, keyPrefix = 'icon') {
    if (!Array.isArray(node) || node.length < 2) {
        return null;
    }

    const [tagName, attrs, children] = node;
    const renderedChildren = Array.isArray(children)
        ? children.map((child, index) => renderLucideNode(child, { key: `${keyPrefix}-${index}` }, `${keyPrefix}-${index}`))
        : [];

    return React.createElement(tagName, buildLucideProps(attrs, extraProps), ...renderedChildren);
}

function Icon({ name, size = 16, className = '' }) {
    if (name === 'star-filled') {
        const dimensionStyle = {
            width: `calc(${size}px * var(--es-ui-scale))`,
            height: `calc(${size}px * var(--es-ui-scale))`
        };
        return React.createElement('svg', {
            className: ['lucide-inline', className].filter(Boolean).join(' '),
            style: dimensionStyle,
            viewBox: '0 0 24 24',
            'aria-hidden': 'true',
            focusable: 'false'
        }, React.createElement('path', {
            d: 'M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z',
            fill: 'currentColor',
            stroke: 'none'
        }));
    }
    const iconNode = getLucideIconNode(name) || getLucideIconNode('circle');
    const dimensionStyle = {
        width: `calc(${size}px * var(--es-ui-scale))`,
        height: `calc(${size}px * var(--es-ui-scale))`
    };

    if (!iconNode) {
        return React.createElement('span', {
            className: ['lucide-inline', className].filter(Boolean).join(' '),
            style: dimensionStyle,
            'aria-hidden': 'true'
        });
    }

    return renderLucideNode(iconNode, {
        className: ['lucide-inline', className].filter(Boolean).join(' '),
        style: dimensionStyle,
        'aria-hidden': 'true',
        focusable: 'false'
    });
}

const resourceName = window.GetParentResourceName ? window.GetParentResourceName() : 'cortex-admin';
const isDebugMode = new URLSearchParams(window.location.search).get('debug') === '1';
const NUI_REQUEST_TIMEOUT_MS = 8000;

function createEmptyAppearancePayload() {
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

function debugLog(...args) {
    if (isDebugMode && window.console && typeof window.console.debug === 'function') {
        window.console.debug(...args);
    }
}

function scheduleLucideIcons() {
    // No-op. Mutating React-managed DOM with lucide.createIcons causes
    // removeChild DOMExceptions during rerenders and tab switches.
}

function normalizeAppearancePayload(raw) {
    const base = createEmptyAppearancePayload();
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
        return base;
    }
    const asRecord = (value) => (value && typeof value === 'object' && !Array.isArray(value) ? value : {});
    const toFiniteNumber = (value, fallback = 0) => {
        const normalized = Number(value);
        return Number.isFinite(normalized) ? normalized : fallback;
    };

    return {
        ...base,
        ...raw,
        components: asRecord(raw.components),
        maxComponents: asRecord(raw.maxComponents),
        props: asRecord(raw.props),
        maxProps: asRecord(raw.maxProps),
        features: asRecord(raw.features),
        overlays: asRecord(raw.overlays),
        headBlend: {
            ...base.headBlend,
            ...asRecord(raw.headBlend)
        },
        model: toFiniteNumber(raw.model, 0),
        isFreemode: raw.isFreemode === true,
        hairColor: toFiniteNumber(raw.hairColor, 0),
        hairHighlightColor: toFiniteNumber(raw.hairHighlightColor, 0),
        eyeColor: toFiniteNumber(raw.eyeColor, 0)
    };
}

function normalizeSavedOutfitEntry(raw, index) {
    if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
    const cleanName = (value) => String(value == null ? '' : value)
        .trim()
        .replace(/^mp_(?:ped_|character_category_)/i, '')
        .trim()
        .slice(0, 64);
    const sourceKey = String(raw.sourceKey == null ? '' : raw.sourceKey).slice(0, 160);
    const name = cleanName(raw.name)
        || cleanName(raw.SaveName)
        || cleanName(raw.saveName)
        || cleanName(sourceKey)
        || `Saved outfit ${index + 1}`;
    const source = String(raw.source == null ? 'cortex-admin' : raw.source).slice(0, 32);
    const id = String(raw.id == null || raw.id === '' ? `${source}:${sourceKey || index}` : raw.id).slice(0, 192);
    return { ...raw, id, name, source, sourceKey };
}

function normalizeSavedOutfitList(raw) {
    if (!Array.isArray(raw)) return [];
    return raw.map(normalizeSavedOutfitEntry).filter(Boolean);
}

class AppearanceErrorBoundary extends React.Component {
    constructor(props) {
        super(props);
        this.state = {
            error: null,
            resetKey: 0
        };
        this.handleRetry = this.handleRetry.bind(this);
    }

    static getDerivedStateFromError(error) {
        return { error };
    }

    componentDidCatch(error) {
        debugLog('[cortex-admin] Appearance view crashed:', error);
    }

    handleRetry() {
        this.setState((prev) => ({
            error: null,
            resetKey: prev.resetKey + 1
        }));
    }

    render() {
        if (this.state.error) {
            return React.createElement('div', { className: 'admin-no-results' },
                React.createElement('div', null, 'Appearance view hit a render error.'),
                React.createElement('button', {
                    type: 'button',
                    className: 'admin-button',
                    onClick: this.handleRetry
                }, 'Reload appearance panel')
            );
        }

        return React.createElement(React.Fragment, { key: this.state.resetKey }, this.props.children);
    }
}

function isPlainObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function asArray(value) {
    return Array.isArray(value) ? value : [];
}

function asObject(value) {
    return isPlainObject(value) ? value : {};
}

function asString(value, fallback = '') {
    return typeof value === 'string' ? value : fallback;
}

function normalizeMenuDock(value) {
    const raw = typeof value === 'string' ? value.toLowerCase().trim() : '';
    if (raw === 'left') return 'left';
    return 'right';
}

function asFiniteNumber(value, fallback = 0) {
    const normalized = Number(value);
    return Number.isFinite(normalized) ? normalized : fallback;
}

async function fetchNui(eventName, data) {
    const controller = typeof AbortController === 'function' ? new AbortController() : null;
    const timeoutId = controller ? window.setTimeout(() => controller.abort(), NUI_REQUEST_TIMEOUT_MS) : null;
    let parsed = null;

    try {
        const response = await fetch(`https://${resourceName}/${eventName}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
            signal: controller ? controller.signal : undefined
        });

        const contentType = response.headers.get('content-type') || '';
        if (contentType.includes('application/json')) {
            try {
                parsed = await response.json();
            } catch (err) {
                debugLog('[cortex-admin] Failed to parse NUI response JSON:', eventName, err);
            }
        } else {
            try {
                const text = await response.text();
                parsed = text ? { text } : null;
            } catch (err) {
                debugLog('[cortex-admin] Failed to read NUI response text:', eventName, err);
            }
        }

        return {
            ok: response.ok,
            status: response.status,
            data: parsed,
            json: async () => parsed
        };
    } catch (err) {
        debugLog('[cortex-admin] NUI callback error:', eventName, err);
        return {
            ok: false,
            status: 0,
            error: err && err.name === 'AbortError' ? 'timeout' : 'network_error',
            data: null,
            json: async () => null
        };
    } finally {
        if (timeoutId) {
            window.clearTimeout(timeoutId);
        }
    }
}

async function copyTextToClipboard(text) {
    if (!text) return false;

    try {
        if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
            await navigator.clipboard.writeText(text);
            return true;
        }
    } catch (err) {
        debugLog('[cortex-admin] navigator.clipboard failed:', err);
    }

    try {
        const ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.left = '-9999px';
        document.body.appendChild(ta);
        ta.focus();
        ta.select();
        const copied = document.execCommand('copy');
        document.body.removeChild(ta);
        return copied;
    } catch (err) {
        debugLog('[cortex-admin] execCommand copy failed:', err);
        return false;
    }
}

function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

const ACCENT_ALPHA_STOPS = [
    ['04', 0.04], ['05', 0.05], ['07', 0.07], ['08', 0.08], ['09', 0.09],
    ['10', 0.1], ['12', 0.12], ['14', 0.14], ['16', 0.16], ['18', 0.18],
    ['20', 0.2], ['22', 0.22], ['34', 0.34], ['92', 0.92],
];

function normalizeHex6(hex) {
    if (typeof hex !== 'string') return null;
    let h = hex.trim();
    if (!h.startsWith('#')) h = `#${h}`;
    const m = h.match(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/);
    if (!m) return null;
    let body = m[1];
    if (body.length === 3) {
        body = body.split('').map((c) => c + c).join('');
    }
    return `#${body.toLowerCase()}`;
}

function hexToRgb(hex6) {
    const h = normalizeHex6(hex6);
    if (!h) return null;
    const n = parseInt(h.slice(1), 16);
    if (Number.isNaN(n)) return null;
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

function mixTowardWhite(r, g, b, t) {
    return {
        r: Math.min(255, Math.round(r + (255 - r) * t)),
        g: Math.min(255, Math.round(g + (255 - g) * t)),
        b: Math.min(255, Math.round(b + (255 - b) * t)),
    };
}

function applyMenuAccentCss(hexInput) {
    const root = document.documentElement;
    const fallback = '#e8a23f';
    const hex = normalizeHex6(hexInput) || fallback;
    const rgb = hexToRgb(hex);
    if (!rgb) {
        applyMenuAccentCss(fallback);
        return;
    }
    const { r, g, b } = rgb;
    const hi = mixTowardWhite(r, g, b, 0.14);
    root.style.setProperty('--es-accent-violet', `rgb(${r},${g},${b})`);
    root.style.setProperty('--es-accent-hover', `rgb(${hi.r},${hi.g},${hi.b})`);
    root.style.setProperty('--es-sidebar-nav-active-icon', `rgb(${r},${g},${b})`);
    for (let i = 0; i < ACCENT_ALPHA_STOPS.length; i += 1) {
        const pair = ACCENT_ALPHA_STOPS[i];
        const suffix = pair[0];
        const a = pair[1];
        root.style.setProperty(`--es-a-${suffix}`, `rgba(${r},${g},${b},${a})`);
    }
    root.style.setProperty('--es-focus-ring', `rgba(${r},${g},${b},0.35)`);
    root.style.setProperty('--es-focus-glow', `rgba(${r},${g},${b},0.1)`);
}

function formatSliderReadout(action, val) {
    const fmt = action.valueFormat;
    if (fmt === 'percent') return `${Math.round(val * 100)}%`;
    if (fmt === 'px') return `${Math.round(val)}px`;
    const step = Number(action.step) || 1;
    if (step >= 1) return `${Math.round(val)}`;
    return `${Math.round(val * 100) / 100}`;
}

const defaultCoordHudData = {
    x: 0,
    y: 0,
    z: 0,
    heading: 0,
    street: '',
    crossing: null
};

function getUiScale() {
    const width = window.innerWidth || 1920;
    const height = window.innerHeight || 1080;
    const widthScale = width / 1920;
    const heightScale = height / 1080;
    const blendedScale = (widthScale * 0.68) + (heightScale * 0.32);
    const shortViewportPenalty = height < 900 ? ((900 - height) / 900) * 0.08 : 0;
    return clamp(blendedScale - shortViewportPenalty, 0.9, 2);
}

function getViewportProfile(shellRect) {
    const width = window.innerWidth || 1920;
    const height = window.innerHeight || 1080;
    const s = shellRect || {};
    const shellW = s.width || width;
    const shellH = s.height || height;

    return {
        width,
        height,
        isNarrow: width <= 1220 || (width <= 1360 && height <= 780),
        isShort: height <= 760,
        isCramped: (width <= 980 || height <= 700) || shellW <= 680 || shellH <= 560
    };
}

function applyUiScale(baseScale) {
    const rootStyles = window.getComputedStyle(document.documentElement);
    const adminScale = Number.parseFloat(rootStyles.getPropertyValue('--es-admin-scale')) || 1;
    document.documentElement.style.setProperty('--es-ui-scale', baseScale * adminScale);
}

applyUiScale(getUiScale());
const handleWindowResize = () => applyUiScale(getUiScale());
window.addEventListener('resize', handleWindowResize);

function normalizeValues(values) {
    if (!Array.isArray(values)) return [];
    return values.map((entry) => {
        if (typeof entry === 'string' || typeof entry === 'number') {
            return { label: String(entry), value: entry };
        }
        if (Array.isArray(entry)) {
            return { label: entry[0], value: entry[1] };
        }
        if (isPlainObject(entry)) {
            return { label: entry.label, value: entry.value };
        }
        return { label: String(entry ?? ''), value: entry };
    });
}

function normalizeVoiceState(value) {
    const source = isPlainObject(value) ? value : {};
    const rawProximity = source.proximity;
    const rawChannel = source.channel;
    const proximity = rawProximity === null || rawProximity === undefined ? NaN : Number(rawProximity);
    const channel = rawChannel === null || rawChannel === undefined ? NaN : Number(rawChannel);

    return {
        proximity: Number.isFinite(proximity) && proximity >= 0.5 && proximity <= 10000 ? proximity : null,
        channel: Number.isInteger(channel) && channel >= 0 && channel <= 65535 ? channel : null,
    };
}

function isPercentValues(values) {
    if (!Array.isArray(values) || values.length === 0) return false;
    return values.every((option) => typeof option.label === 'string' && option.label.trim().endsWith('%'));
}

function CustomSelect({ options, value, disabled, onChange, ariaLabel }) {
    const [open, setOpen] = useState(false);
    const wrapperRef = React.useRef(null);
    const triggerRef = React.useRef(null);
    const listboxId = React.useId();
    const [menuStyle, setMenuStyle] = useState(null);
    const selected = options.find((option) => String(option.value) === String(value)) || options[0];

    useLayoutEffect(() => {
        if (!open) {
            setMenuStyle(null);
            return undefined;
        }
        const update = () => {
            const el = wrapperRef.current;
            if (!el) return;
            const r = el.getBoundingClientRect();
            const scale = Number.parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--es-ui-scale')) || 1;
            const gap = 4 * scale;
            const pad = 8;
            const desiredMax = 220 * scale;
            const availableWidth = Math.max(0, window.innerWidth - (pad * 2));
            const menuWidth = Math.min(r.width, availableWidth);
            const menuLeft = Math.min(
                Math.max(pad, r.left),
                Math.max(pad, window.innerWidth - pad - menuWidth)
            );
            const spaceBelow = window.innerHeight - r.bottom - gap - pad;
            const spaceAbove = r.top - gap - pad;
            const openBelow = spaceBelow >= 160 || spaceBelow >= spaceAbove;
            if (openBelow) {
                setMenuStyle({
                    position: 'fixed',
                    top: r.bottom + gap,
                    bottom: 'auto',
                    left: menuLeft,
                    width: menuWidth,
                    minWidth: menuWidth,
                    maxWidth: menuWidth,
                    maxHeight: Math.min(desiredMax, Math.max(80, spaceBelow)),
                    overflowY: 'auto',
                    zIndex: 10020
                });
            } else {
                setMenuStyle({
                    position: 'fixed',
                    top: 'auto',
                    bottom: window.innerHeight - r.top + gap,
                    left: menuLeft,
                    width: menuWidth,
                    minWidth: menuWidth,
                    maxWidth: menuWidth,
                    maxHeight: Math.min(desiredMax, Math.max(80, spaceAbove)),
                    overflowY: 'auto',
                    zIndex: 10020
                });
            }
        };
        update();
        window.addEventListener('resize', update);
        document.addEventListener('scroll', update, true);
        return () => {
            window.removeEventListener('resize', update);
            document.removeEventListener('scroll', update, true);
        };
    }, [open]);

    useEffect(() => {
        if (!open) return undefined;
        const handleClick = (event) => {
            const t = event.target;
            if (wrapperRef.current && wrapperRef.current.contains(t)) return;
            if (t.closest && t.closest('.admin-select-options')) return;
            setOpen(false);
        };
        window.addEventListener('mousedown', handleClick);
        return () => window.removeEventListener('mousedown', handleClick);
    }, [open]);

    useEffect(() => {
        if (!open) return undefined;
        const frame = window.requestAnimationFrame(() => {
            const listbox = document.getElementById(listboxId);
            const optionButtons = listbox ? Array.from(listbox.querySelectorAll('.admin-select-option')) : [];
            const selectedIndex = Math.max(0, options.findIndex((option) => String(option.value) === String(value)));
            if (optionButtons[selectedIndex]) optionButtons[selectedIndex].focus();
        });
        return () => window.cancelAnimationFrame(frame);
    }, [listboxId, open, options, value]);

    const handleToggle = (event) => {
        event.preventDefault();
        if (disabled) return;
        setOpen((prev) => !prev);
    };

    const handleSelect = (option) => {
        if (disabled) return;
        onChange(option.value);
        setOpen(false);
        window.requestAnimationFrame(() => triggerRef.current && triggerRef.current.focus());
    };

    const handleTriggerKeyDown = (event) => {
        if (disabled) return;
        if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
            event.preventDefault();
            setOpen(true);
        } else if (event.key === 'Escape') {
            setOpen(false);
        }
    };

    const handleOptionKeyDown = (event, index) => {
        const listbox = document.getElementById(listboxId);
        const optionButtons = listbox ? Array.from(listbox.querySelectorAll('.admin-select-option')) : [];
        if (event.key === 'Escape') {
            event.preventDefault();
            setOpen(false);
            window.requestAnimationFrame(() => triggerRef.current && triggerRef.current.focus());
            return;
        }
        let nextIndex = null;
        if (event.key === 'ArrowDown') nextIndex = Math.min(optionButtons.length - 1, index + 1);
        if (event.key === 'ArrowUp') nextIndex = Math.max(0, index - 1);
        if (event.key === 'Home') nextIndex = 0;
        if (event.key === 'End') nextIndex = optionButtons.length - 1;
        if (nextIndex !== null && optionButtons[nextIndex]) {
            event.preventDefault();
            optionButtons[nextIndex].focus();
        }
    };

    const optionsEl = open && React.createElement('div', {
        className: 'admin-select-options admin-select-options-portal',
        id: listboxId,
        role: 'listbox',
        style: menuStyle || { position: 'fixed', top: -9999, left: -9999, minWidth: 0, maxHeight: 0, zIndex: 10020, visibility: 'hidden' }
    },
        options.map((option, index) => React.createElement('button', {
            type: 'button',
            key: option.value,
            className: `admin-select-option${String(option.value) === String(value) ? ' active' : ''}`,
            role: 'option',
            'aria-selected': String(option.value) === String(value),
            onKeyDown: (event) => handleOptionKeyDown(event, index),
            onClick: () => handleSelect(option)
        }, option.label))
    );

    return React.createElement('div', {
        className: `admin-select${open ? ' open' : ''}${disabled ? ' disabled' : ''}`,
        ref: wrapperRef
    },
        React.createElement('button', {
            type: 'button',
            className: 'admin-select-trigger',
            ref: triggerRef,
            onClick: handleToggle,
            onKeyDown: handleTriggerKeyDown,
            disabled,
            'aria-label': ariaLabel,
            'aria-haspopup': 'listbox',
            'aria-expanded': open,
            'aria-controls': listboxId
        },
            React.createElement('span', { className: 'admin-select-label' }, selected ? selected.label : 'Select'),
            React.createElement('span', { className: 'admin-select-chevron' }, React.createElement(Icon, { name: 'chevron-down', size: 14 }))
        ),
        optionsEl && createPortal(optionsEl, document.body)
    );
}

function PersonalVehicleModal({ vehicles, settings, onCancel, onSpawn, onDelete, onSave, onToggleSetting }) {
    const [search, setSearch] = useState('');
    const [activeCategory, setActiveCategory] = useState('all');

    const categories = [
        { id: 'all', label: 'All' },
        { id: 'compacts', label: 'Compacts' },
        { id: 'sedans', label: 'Sedans' },
        { id: 'suvs', label: 'SUVs' },
        { id: 'coupes', label: 'Coupes' },
        { id: 'muscle', label: 'Muscle' },
        { id: 'sportsclassics', label: 'Sports Classics' },
        { id: 'sports', label: 'Sports' },
        { id: 'super', label: 'Super' },
        { id: 'motorcycles', label: 'Motorcycles' },
        { id: 'offroad', label: 'Off-Road' },
        { id: 'industrial', label: 'Industrial' },
        { id: 'utility', label: 'Utility' },
        { id: 'vans', label: 'Vans' },
        { id: 'cycles', label: 'Cycles' },
        { id: 'boats', label: 'Boats' },
        { id: 'helicopters', label: 'Helicopters' },
        { id: 'planes', label: 'Planes' },
        { id: 'service', label: 'Service' },
        { id: 'emergency', label: 'Emergency' },
        { id: 'military', label: 'Military' },
        { id: 'commercial', label: 'Commercial' },
        { id: 'trains', label: 'Trains' },
        { id: 'openwheel', label: 'Open Wheel' },
        { id: 'other', label: 'Other' }
    ];

    const vehicleList = useMemo(() => {
        if (!vehicles) return [];
        if (Array.isArray(vehicles)) {
            return vehicles.map((entry) => ({
                id: entry.id || entry.name,
                name: entry.name,
                model: entry.model,
                modelLabel: entry.modelLabel || entry.model,
                category: entry.category || 'other'
            }));
        }

        return Object.entries(vehicles).map(([name, data]) => ({
            id: data.id || name,
            name,
            model: data.model,
            modelLabel: data.modelLabel || data.model,
            category: data.category || 'other'
        }));
    }, [vehicles]);

    const filteredVehicles = useMemo(() => {
        let list = vehicleList;
        if (activeCategory !== 'all') {
            list = list.filter(v => v.category === activeCategory);
        }
        if (search.trim()) {
            const query = search.toLowerCase();
            list = list.filter(v => v.name.toLowerCase().includes(query) || (v.modelLabel && String(v.modelLabel).toLowerCase().includes(query)));
        }
        return list;
    }, [vehicleList, activeCategory, search]);

    const groupedVehicles = useMemo(() => {
        const groups = {};
        filteredVehicles.forEach((vehicle) => {
            if (!groups[vehicle.category]) groups[vehicle.category] = [];
            groups[vehicle.category].push(vehicle);
        });

        Object.keys(groups).forEach((key) => {
            groups[key].sort((a, b) => a.name.localeCompare(b.name));
        });

        return groups;
    }, [filteredVehicles]);

    const stats = useMemo(() => {
        const s = {};
        vehicleList.forEach(v => {
            s[v.category] = (s[v.category] || 0) + 1;
        });
        return s;
    }, [vehicleList]);

    const isAutoReplace = settings.replacePersonalVehicle !== false;

    const renderVehicleItem = (v) => React.createElement('div', { className: 'pv-item', key: v.id || v.name },
        React.createElement('div', { className: 'pv-item-info' },
            React.createElement('div', { className: 'pv-item-name' }, v.name),
            React.createElement('div', { className: 'pv-item-model' }, v.modelLabel || v.model || 'Unknown')
        ),
        React.createElement('div', { className: 'pv-item-actions' },
            React.createElement('button', { className: 'admin-button success', onClick: () => onSpawn(v.id) }, 'Spawn'),
            React.createElement('button', { className: 'admin-button', onClick: () => onSave(v.id) }, 'Update'),
            React.createElement('button', { className: 'admin-button danger', onClick: () => onDelete(v.id) }, 'Delete')
        )
    );

    const renderEmptyState = () => React.createElement('div', { className: 'pv-empty-state' },
        React.createElement('svg', { 
            className: 'pv-empty-state-icon', 
            viewBox: '0 0 24 24', 
            fill: 'none',
            stroke: 'currentColor',
            strokeWidth: '1.5',
            strokeLinecap: 'round',
            strokeLinejoin: 'round'
        },
            React.createElement('path', { d: 'M5 17a2 2 0 1 0 4 0a2 2 0 0 0-4 0' }),
            React.createElement('path', { d: 'M15 17a2 2 0 1 0 4 0a2 2 0 0 0-4 0' }),
            React.createElement('path', { d: 'M5 17H3v-4l2-5h9l4 5h1a2 2 0 0 1 2 2v2h-2m-4 0H9' }),
            React.createElement('path', { d: 'M10 5l1 3h4' })
        ),
        React.createElement('div', { className: 'pv-empty-state-text' }, vehicleList.length === 0 ? 'No saved vehicles' : 'No vehicles match your filter'),
        React.createElement('div', { className: 'pv-empty-state-hint' }, vehicleList.length === 0 ? 'Use "Save to Personal Vehicles" to add one' : 'Try a different category or search term')
    );

    const renderVehicleList = () => {
        if (filteredVehicles.length === 0) return renderEmptyState();
        
        if (activeCategory === 'all') {
            return categories.filter(cat => cat.id !== 'all').map(cat => {
                const items = groupedVehicles[cat.id] || [];
                if (items.length === 0) return null;
                return React.createElement('div', { className: 'pv-group', key: cat.id },
                    React.createElement('div', { className: 'pv-group-title' }, cat.label),
                    items.map(renderVehicleItem)
                );
            });
        }
        
        return filteredVehicles.map(renderVehicleItem);
    };

    return React.createElement('div', { className: 'admin-modal personal-vehicle-modal', onClick: onCancel },
        React.createElement('div', { className: 'admin-modal-card large', onClick: (e) => e.stopPropagation() },
            React.createElement('div', { className: 'admin-modal-header' },
                React.createElement('div', { className: 'admin-modal-title' }, 'Personal Vehicles'),
                React.createElement('div', { className: 'admin-modal-subtitle' }, `${vehicleList.length} saved vehicle${vehicleList.length !== 1 ? 's' : ''}`)
            ),

            React.createElement('div', { className: 'pv-layout' },
                React.createElement('div', { className: 'pv-sidebar' },
                    categories.map(cat => {
                        const count = cat.id === 'all' ? vehicleList.length : (stats[cat.id] || 0);
                        const isEmpty = count === 0 && cat.id !== 'all';
                        return React.createElement('button', {
                            key: cat.id,
                            className: `pv-category-btn${activeCategory === cat.id ? ' active' : ''}${isEmpty ? ' empty' : ''}`,
                            onClick: () => !isEmpty && setActiveCategory(cat.id)
                        },
                            React.createElement('span', null, cat.label),
                            React.createElement('span', { className: 'pv-cat-count' }, count)
                        );
                    })
                ),

                React.createElement('div', { className: 'pv-main' },
                    React.createElement('div', { className: 'pv-controls' },
                        React.createElement('div', { className: 'admin-search' },
                            React.createElement('input', {
                                value: search,
                                placeholder: 'Search vehicles...',
                                autoFocus: true,
                                onKeyDown: (e) => e.stopPropagation(),
                                onChange: (e) => setSearch(e.target.value)
                            })
                        ),
                        React.createElement('div', {
                            className: 'pv-toggle-option',
                            onClick: () => onToggleSetting('replacePersonalVehicle', !isAutoReplace),
                            title: 'Delete vehicle you are in before spawning (same as Options → Replace Previous Spawned Vehicle)'
                        },
                            React.createElement('div', { className: `admin-toggle${isAutoReplace ? ' active' : ''}`, 'aria-hidden': true }),
                            React.createElement('span', null, 'Replace prev.')
                        )
                    ),

                    React.createElement('div', { className: 'pv-list' }, renderVehicleList())
                )
            ),

            React.createElement('div', { className: 'admin-modal-actions' },
                React.createElement('button', { className: 'admin-button', onClick: onCancel }, 'Close')
            )
        )
    );
}

// Inline Prompt Component - Replaces modal for simple inputs
function InlinePrompt({ fields, onCancel, onConfirm }) {
    const [values, setValues] = useState({});

    const handleChange = (name, value) => {
        setValues((prev) => ({ ...prev, [name]: value }));
    };

    const handleKeyDown = (e) => {
        e.stopPropagation();
        if (e.key === 'Enter') {
            onConfirm(values);
        }
        if (e.key === 'Escape') {
            onCancel();
        }
    };

    return React.createElement('div', { className: 'admin-inline-prompt', onClick: (e) => e.stopPropagation() },
        React.createElement('div', { className: 'admin-inline-prompt-fields' },
            fields.map((field, index) => React.createElement('div', { className: 'admin-inline-prompt-field', key: field.name },
                React.createElement('label', null, field.label),
                React.createElement('input', {
                    value: values[field.name] || '',
                    placeholder: field.placeholder || '',
                    autoFocus: index === 0,
                    onKeyDown: handleKeyDown,
                    onChange: (e) => handleChange(field.name, e.target.value)
                })
            ))
        ),
        React.createElement('div', { className: 'admin-inline-prompt-actions' },
            React.createElement('button', { className: 'admin-button', onClick: onCancel }, 'Cancel'),
            React.createElement('button', { className: 'admin-button success', onClick: () => onConfirm(values) }, 'Confirm')
        )
    );
}

// Inline Personal Vehicles Panel - Accordion-style vehicle manager
function InlinePersonalVehicles({ vehicles, settings, onSpawn, onDelete, onSave, onToggleSetting, onClose }) {
    const [search, setSearch] = useState('');
    const [activeCategory, setActiveCategory] = useState('all');
    const [hovered, setHovered] = useState(null);

    const categories = [
        { id: 'all', label: 'All' },
        { id: 'super', label: 'Super' },
        { id: 'sports', label: 'Sports' },
        { id: 'sportsclassics', label: 'Classics' },
        { id: 'muscle', label: 'Muscle' },
        { id: 'sedans', label: 'Sedans' },
        { id: 'coupes', label: 'Coupes' },
        { id: 'compacts', label: 'Compacts' },
        { id: 'suvs', label: 'SUVs' },
        { id: 'offroad', label: 'Off-Road' },
        { id: 'motorcycles', label: 'Bikes' },
        { id: 'cycles', label: 'Cycles' },
        { id: 'vans', label: 'Vans' },
        { id: 'commercial', label: 'Commercial' },
        { id: 'industrial', label: 'Industrial' },
        { id: 'utility', label: 'Utility' },
        { id: 'service', label: 'Service' },
        { id: 'helicopters', label: 'Helis' },
        { id: 'planes', label: 'Planes' },
        { id: 'boats', label: 'Boats' },
        { id: 'emergency', label: 'Emergency' },
        { id: 'military', label: 'Military' },
        { id: 'openwheel', label: 'Open Wheel' },
        { id: 'other', label: 'Other' }
    ];

    const vehicleList = useMemo(() => {
        if (!vehicles) return [];
        if (Array.isArray(vehicles)) {
            return vehicles.map((entry) => ({
                id: entry.id || entry.name,
                name: entry.name,
                model: entry.model,
                modelLabel: entry.modelLabel || entry.model,
                category: entry.category || 'other'
            }));
        }
        return Object.entries(vehicles).map(([name, data]) => ({
            id: data.id || name,
            name,
            model: data.model,
            modelLabel: data.modelLabel || data.model,
            category: data.category || 'other'
        }));
    }, [vehicles]);

    const filteredVehicles = useMemo(() => {
        let list = vehicleList;
        if (activeCategory !== 'all') {
            list = list.filter(v => v.category === activeCategory);
        }
        if (search.trim()) {
            const query = search.toLowerCase();
            list = list.filter(v => v.name.toLowerCase().includes(query) || (v.modelLabel && String(v.modelLabel).toLowerCase().includes(query)));
        }
        return list.sort((a, b) => a.name.localeCompare(b.name));
    }, [vehicleList, activeCategory, search]);

    const stats = useMemo(() => {
        const s = { all: vehicleList.length };
        vehicleList.forEach(v => {
            s[v.category] = (s[v.category] || 0) + 1;
        });
        return s;
    }, [vehicleList]);

    const isAutoReplace = settings.replacePersonalVehicle !== false;

    const handleSpawn = (v, e) => {
        e.stopPropagation();
        onSpawn(v.id);
    };

    const handleDelete = (v, e) => {
        e.stopPropagation();
        onDelete(v.id);
    };

    const handleUpdate = (v, e) => {
        e.stopPropagation();
        onSave(v.id);
    };

    const availableCategories = categories.filter(cat => cat.id === 'all' || stats[cat.id] > 0);

    return React.createElement('div', { className: 'admin-inline-vehicles', onClick: (e) => e.stopPropagation() },
        // Header with search and category
        React.createElement('div', { className: 'admin-inline-vehicles-header' },
            React.createElement('input', {
                className: 'admin-inline-vehicles-search',
                value: search,
                placeholder: 'Search...',
                autoFocus: true,
                onKeyDown: (e) => e.stopPropagation(),
                onChange: (e) => setSearch(e.target.value)
            }),
            React.createElement(CustomSelect, {
                options: availableCategories.map(c => ({ label: `${c.label} (${stats[c.id] || 0})`, value: c.id })),
                value: activeCategory,
                onChange: setActiveCategory
            }),
            React.createElement('div', {
                className: 'admin-inline-vehicles-toggle',
                onClick: () => onToggleSetting('replacePersonalVehicle', !isAutoReplace),
                title: 'Replace previous spawned vehicle: delete occupied vehicle before spawn (list, preview, garage, personal)'
            },
                React.createElement('div', { className: `admin-toggle${isAutoReplace ? ' active' : ''}`, 'aria-hidden': true }),
                React.createElement('span', null, 'Replace')
            )
        ),
        // Vehicle list
        React.createElement('div', { className: 'admin-inline-vehicles-list' },
            filteredVehicles.length === 0 
                ? React.createElement('div', { className: 'admin-inline-vehicles-empty' }, 
                    vehicleList.length === 0 ? 'No saved vehicles. Use "Save Current Vehicle" to add one.' : 'No vehicles match your filter.')
                : filteredVehicles.map(v => React.createElement('div', {
                    key: v.id,
                    className: `admin-inline-vehicle-item${hovered === v.id ? ' hovered' : ''}`,
                    onMouseEnter: () => setHovered(v.id),
                    onMouseLeave: () => setHovered(null),
                    onClick: (e) => handleSpawn(v, e)
                },
                    React.createElement('div', { className: 'admin-inline-vehicle-info' },
                        React.createElement('span', { className: 'admin-inline-vehicle-name' }, v.name),
                        React.createElement('span', { className: 'admin-inline-vehicle-model' }, v.modelLabel || v.model)
                    ),
                    React.createElement('div', { className: 'admin-inline-vehicle-actions' },
                        hovered === v.id && React.createElement('button', {
                            className: 'admin-button small',
                            onClick: (e) => handleUpdate(v, e),
                            title: 'Update with current vehicle'
                        }, '↻'),
                        hovered === v.id && React.createElement('button', {
                            className: 'admin-button small danger',
                            onClick: (e) => handleDelete(v, e),
                            title: 'Delete'
                        }, '×'),
                        React.createElement('span', { className: 'admin-inline-vehicle-spawn' }, '→')
                    )
                ))
        ),
        // Footer
        React.createElement('div', { className: 'admin-inline-vehicles-footer' },
            React.createElement('span', null, `${filteredVehicles.length} of ${vehicleList.length} vehicles`),
            React.createElement('button', { className: 'admin-button small', onClick: onClose }, 'Close')
        )
    );
}

// Inline Vehicle Spawner - Preview any vehicle before final spawn
function InlineVehicleSpawner({ settings, addonVehicles, onSpawn, onPreview, onClearPreview, onToggleSetting, onClose, extrasEnabled = false, launchKey = 0, launchModel = null, launchResumeOnly = false, previewSharedProp = false }) {
    const [search, setSearch] = useState('');
    const [activeCategory, setActiveCategory] = useState('super');
    const [customModel, setCustomModel] = useState('');
    const [hovered, setHovered] = useState(null);
    const [previewModel, setPreviewModel] = useState('');
    const [previewName, setPreviewName] = useState('');
    const [extrasList, setExtrasList] = useState([]);
    const [shareOn, setShareOn] = useState(previewSharedProp === true);

    // Popular vehicles organized by category
    const vehicleDatabase = useMemo(() => ({
        super: [
            { model: 'adder', name: 'Adder' },
            { model: 'autarch', name: 'Autarch' },
            { model: 'banshee2', name: 'Banshee 900R' },
            { model: 'bullet', name: 'Bullet' },
            { model: 'cheetah', name: 'Cheetah' },
            { model: 'cyclone', name: 'Cyclone' },
            { model: 'deveste', name: 'Deveste Eight' },
            { model: 'emerus', name: 'Emerus' },
            { model: 'entityxf', name: 'Entity XF' },
            { model: 'entity2', name: 'Entity XXR' },
            { model: 'fmj', name: 'FMJ' },
            { model: 'furia', name: 'Furia' },
            { model: 'gp1', name: 'GP1' },
            { model: 'infernus', name: 'Infernus' },
            { model: 'italigtb', name: 'Itali GTB' },
            { model: 'italigtb2', name: 'Itali GTB Custom' },
            { model: 'krieger', name: 'Krieger' },
            { model: 'le7b', name: 'RE-7B' },
            { model: 'nero', name: 'Nero' },
            { model: 'nero2', name: 'Nero Custom' },
            { model: 'osiris', name: 'Osiris' },
            { model: 'penetrator', name: 'Penetrator' },
            { model: 'pfister811', name: '811' },
            { model: 'prototipo', name: 'X80 Proto' },
            { model: 'reaper', name: 'Reaper' },
            { model: 's80', name: 'S80RR' },
            { model: 'sc1', name: 'SC1' },
            { model: 'scramjet', name: 'Scramjet' },
            { model: 'sheava', name: 'ETR1' },
            { model: 't20', name: 'T20' },
            { model: 'taipan', name: 'Taipan' },
            { model: 'tempesta', name: 'Tempesta' },
            { model: 'tezeract', name: 'Tezeract' },
            { model: 'thrax', name: 'Thrax' },
            { model: 'tigon', name: 'Tigon' },
            { model: 'turismor', name: 'Turismo R' },
            { model: 'tyrant', name: 'Tyrant' },
            { model: 'tyrus', name: 'Tyrus' },
            { model: 'vacca', name: 'Vacca' },
            { model: 'vagner', name: 'Vagner' },
            { model: 'visione', name: 'Visione' },
            { model: 'voltic', name: 'Voltic' },
            { model: 'xa21', name: 'XA-21' },
            { model: 'zentorno', name: 'Zentorno' },
            { model: 'zorrusso', name: 'Zorrusso' }
        ],
        sports: [
            { model: '9f', name: '9F' },
            { model: '9f2', name: '9F Cabrio' },
            { model: 'alpha', name: 'Alpha' },
            { model: 'banshee', name: 'Banshee' },
            { model: 'bestiagts', name: 'Bestia GTS' },
            { model: 'buffalo', name: 'Buffalo' },
            { model: 'buffalo2', name: 'Buffalo S' },
            { model: 'carbonizzare', name: 'Carbonizzare' },
            { model: 'comet2', name: 'Comet' },
            { model: 'comet3', name: 'Comet Retro' },
            { model: 'comet4', name: 'Comet Safari' },
            { model: 'comet5', name: 'Comet SR' },
            { model: 'coquette', name: 'Coquette' },
            { model: 'elegy', name: 'Elegy Retro' },
            { model: 'elegy2', name: 'Elegy RH8' },
            { model: 'feltzer2', name: 'Feltzer' },
            { model: 'flashgt', name: 'Flash GT' },
            { model: 'furoregt', name: 'Furore GT' },
            { model: 'gb200', name: 'GB200' },
            { model: 'hotring', name: 'Hotring Sabre' },
            { model: 'italigto', name: 'Itali GTO' },
            { model: 'jester', name: 'Jester' },
            { model: 'jester2', name: 'Jester (Racecar)' },
            { model: 'jester3', name: 'Jester Classic' },
            { model: 'khamelion', name: 'Khamelion' },
            { model: 'kuruma', name: 'Kuruma' },
            { model: 'kuruma2', name: 'Kuruma (Armored)' },
            { model: 'locust', name: 'Locust' },
            { model: 'lynx', name: 'Lynx' },
            { model: 'massacro', name: 'Massacro' },
            { model: 'massacro2', name: 'Massacro (Racecar)' },
            { model: 'neo', name: 'Neo' },
            { model: 'neon', name: 'Neon' },
            { model: 'ninef', name: '9F' },
            { model: 'omnis', name: 'Omnis' },
            { model: 'paragon', name: 'Paragon R' },
            { model: 'pariah', name: 'Pariah' },
            { model: 'penumbra', name: 'Penumbra' },
            { model: 'raiden', name: 'Raiden' },
            { model: 'rapidgt', name: 'Rapid GT' },
            { model: 'rapidgt2', name: 'Rapid GT Cabrio' },
            { model: 'raptor', name: 'Raptor' },
            { model: 'revolter', name: 'Revolter' },
            { model: 'ruston', name: 'Ruston' },
            { model: 'schafter3', name: 'Schafter V12' },
            { model: 'schafter4', name: 'Schafter LWB' },
            { model: 'schlagen', name: 'Schlagen GT' },
            { model: 'sentinel3', name: 'Sentinel Classic' },
            { model: 'seven70', name: 'Seven-70' },
            { model: 'specter', name: 'Specter' },
            { model: 'specter2', name: 'Specter Custom' },
            { model: 'streiter', name: 'Streiter' },
            { model: 'sultan', name: 'Sultan' },
            { model: 'surano', name: 'Surano' },
            { model: 'tropos', name: 'Tropos Rallye' },
            { model: 'verlierer2', name: 'Verlierer' },
            { model: 'vstr', name: 'V-STR' },
            { model: 'zr380', name: 'ZR380' }
        ],
        muscle: [
            { model: 'blade', name: 'Blade' },
            { model: 'buccaneer', name: 'Buccaneer' },
            { model: 'buccaneer2', name: 'Buccaneer Custom' },
            { model: 'chino', name: 'Chino' },
            { model: 'chino2', name: 'Chino Custom' },
            { model: 'clique', name: 'Clique' },
            { model: 'coquette3', name: 'Coquette BlackFin' },
            { model: 'deviant', name: 'Deviant' },
            { model: 'dominator', name: 'Dominator' },
            { model: 'dominator2', name: 'Pisswasser Dominator' },
            { model: 'dominator3', name: 'Dominator GTX' },
            { model: 'dukes', name: 'Dukes' },
            { model: 'dukes2', name: 'Duke O\'Death' },
            { model: 'ellie', name: 'Ellie' },
            { model: 'faction', name: 'Faction' },
            { model: 'faction2', name: 'Faction Custom' },
            { model: 'faction3', name: 'Faction Donk' },
            { model: 'gauntlet', name: 'Gauntlet' },
            { model: 'gauntlet2', name: 'Redwood Gauntlet' },
            { model: 'gauntlet3', name: 'Gauntlet Classic' },
            { model: 'gauntlet4', name: 'Gauntlet Hellfire' },
            { model: 'hermes', name: 'Hermes' },
            { model: 'hotknife', name: 'Hotknife' },
            { model: 'hustler', name: 'Hustler' },
            { model: 'impaler', name: 'Impaler' },
            { model: 'imperator', name: 'Imperator' },
            { model: 'lurcher', name: 'Lurcher' },
            { model: 'moonbeam', name: 'Moonbeam' },
            { model: 'moonbeam2', name: 'Moonbeam Custom' },
            { model: 'nightshade', name: 'Nightshade' },
            { model: 'peyote2', name: 'Peyote Gasser' },
            { model: 'phoenix', name: 'Phoenix' },
            { model: 'picador', name: 'Picador' },
            { model: 'ratloader', name: 'Rat-Loader' },
            { model: 'ratloader2', name: 'Rat-Truck' },
            { model: 'ruiner', name: 'Ruiner' },
            { model: 'ruiner2', name: 'Ruiner 2000' },
            { model: 'sabregt', name: 'Sabre Turbo' },
            { model: 'sabregt2', name: 'Sabre Turbo Custom' },
            { model: 'slamvan', name: 'Slamvan' },
            { model: 'slamvan2', name: 'Lost Slamvan' },
            { model: 'slamvan3', name: 'Slamvan Custom' },
            { model: 'stalion', name: 'Stallion' },
            { model: 'stalion2', name: 'Burger Shot Stallion' },
            { model: 'tampa', name: 'Tampa' },
            { model: 'tampa3', name: 'Weaponized Tampa' },
            { model: 'tulip', name: 'Tulip' },
            { model: 'vamos', name: 'Vamos' },
            { model: 'vigero', name: 'Vigero' },
            { model: 'virgo', name: 'Virgo' },
            { model: 'virgo2', name: 'Virgo Classic Custom' },
            { model: 'virgo3', name: 'Virgo Classic' },
            { model: 'voodoo', name: 'Voodoo Custom' },
            { model: 'yosemite', name: 'Yosemite' }
        ],
        offroad: [
            { model: 'bfinjection', name: 'BF Injection' },
            { model: 'bifta', name: 'Bifta' },
            { model: 'blazer', name: 'Blazer' },
            { model: 'blazer2', name: 'Blazer Lifeguard' },
            { model: 'blazer3', name: 'Hot Rod Blazer' },
            { model: 'blazer4', name: 'Street Blazer' },
            { model: 'blazer5', name: 'Blazer Aqua' },
            { model: 'bodhi2', name: 'Bodhi' },
            { model: 'brawler', name: 'Brawler' },
            { model: 'bruiser', name: 'Bruiser' },
            { model: 'brutus', name: 'Brutus' },
            { model: 'caracara', name: 'Caracara' },
            { model: 'caracara2', name: 'Caracara 4x4' },
            { model: 'dloader', name: 'Duneloader' },
            { model: 'dubsta3', name: 'Dubsta 6x6' },
            { model: 'dune', name: 'Dune Buggy' },
            { model: 'everon', name: 'Everon' },
            { model: 'freecrawler', name: 'Freecrawler' },
            { model: 'hellion', name: 'Hellion' },
            { model: 'insurgent', name: 'Insurgent' },
            { model: 'insurgent2', name: 'Insurgent Pick-Up' },
            { model: 'insurgent3', name: 'Insurgent Pick-Up Custom' },
            { model: 'kalahari', name: 'Kalahari' },
            { model: 'kamacho', name: 'Kamacho' },
            { model: 'marshall', name: 'Marshall' },
            { model: 'mesa3', name: 'Merryweather Mesa' },
            { model: 'monster', name: 'Liberator' },
            { model: 'nightshark', name: 'Nightshark' },
            { model: 'outlaw', name: 'Outlaw' },
            { model: 'rancherxl', name: 'Rancher XL' },
            { model: 'rcbandito', name: 'RC Bandito' },
            { model: 'rebel', name: 'Rebel' },
            { model: 'rebel2', name: 'Rusty Rebel' },
            { model: 'riata', name: 'Riata' },
            { model: 'sandking', name: 'Sandking XL' },
            { model: 'sandking2', name: 'Sandking SWB' },
            { model: 'technical', name: 'Technical' },
            { model: 'technical2', name: 'Technical Aqua' },
            { model: 'technical3', name: 'Technical Custom' },
            { model: 'trophytruck', name: 'Trophy Truck' },
            { model: 'trophytruck2', name: 'Desert Raid' },
            { model: 'vagrant', name: 'Vagrant' },
            { model: 'winky', name: 'Winky' },
            { model: 'zhaba', name: 'Zhaba' }
        ],
        motorcycles: [
            { model: 'akuma', name: 'Akuma' },
            { model: 'avarus', name: 'Avarus' },
            { model: 'bagger', name: 'Bagger' },
            { model: 'bati', name: 'Bati 801' },
            { model: 'bati2', name: 'Bati 801RR' },
            { model: 'bf400', name: 'BF400' },
            { model: 'carbonrs', name: 'Carbon RS' },
            { model: 'chimera', name: 'Chimera' },
            { model: 'cliffhanger', name: 'Cliffhanger' },
            { model: 'daemon', name: 'Daemon' },
            { model: 'daemon2', name: 'Daemon Custom' },
            { model: 'defiler', name: 'Defiler' },
            { model: 'deathbike', name: 'Deathbike' },
            { model: 'diablous', name: 'Diabolus' },
            { model: 'diablous2', name: 'Diabolus Custom' },
            { model: 'double', name: 'Double T' },
            { model: 'enduro', name: 'Enduro' },
            { model: 'esskey', name: 'Esskey' },
            { model: 'faggio', name: 'Faggio' },
            { model: 'faggio2', name: 'Faggio Sport' },
            { model: 'faggio3', name: 'Faggio Mod' },
            { model: 'fcr', name: 'FCR 1000' },
            { model: 'fcr2', name: 'FCR 1000 Custom' },
            { model: 'gargoyle', name: 'Gargoyle' },
            { model: 'hakuchou', name: 'Hakuchou' },
            { model: 'hakuchou2', name: 'Hakuchou Drag' },
            { model: 'hexer', name: 'Hexer' },
            { model: 'innovation', name: 'Innovation' },
            { model: 'lectro', name: 'Lectro' },
            { model: 'manchez', name: 'Manchez' },
            { model: 'nemesis', name: 'Nemesis' },
            { model: 'nightblade', name: 'Nightblade' },
            { model: 'oppressor', name: 'Oppressor' },
            { model: 'oppressor2', name: 'Oppressor Mk II' },
            { model: 'pcj', name: 'PCJ-600' },
            { model: 'ratbike', name: 'Rat Bike' },
            { model: 'ruffian', name: 'Ruffian' },
            { model: 'sanchez', name: 'Sanchez' },
            { model: 'sanchez2', name: 'Sanchez Livery' },
            { model: 'sanctus', name: 'Sanctus' },
            { model: 'shotaro', name: 'Shotaro' },
            { model: 'sovereign', name: 'Sovereign' },
            { model: 'stryder', name: 'Stryder' },
            { model: 'thrust', name: 'Thrust' },
            { model: 'vader', name: 'Vader' },
            { model: 'vindicator', name: 'Vindicator' },
            { model: 'vortex', name: 'Vortex' },
            { model: 'wolfsbane', name: 'Wolfsbane' },
            { model: 'zombiea', name: 'Zombie Bobber' },
            { model: 'zombieb', name: 'Zombie Chopper' }
        ],
        helicopters: [
            { model: 'akula', name: 'Akula' },
            { model: 'annihilator', name: 'Annihilator' },
            { model: 'buzzard', name: 'Buzzard' },
            { model: 'buzzard2', name: 'Buzzard Attack' },
            { model: 'cargobob', name: 'Cargobob' },
            { model: 'cargobob2', name: 'Cargobob (Jetsam)' },
            { model: 'cargobob3', name: 'Cargobob (TPE)' },
            { model: 'cargobob4', name: 'Cargobob (Drop Zone)' },
            { model: 'frogger', name: 'Frogger' },
            { model: 'frogger2', name: 'Frogger (TPE)' },
            { model: 'havok', name: 'Havok' },
            { model: 'hunter', name: 'Hunter' },
            { model: 'maverick', name: 'Maverick' },
            { model: 'polmav', name: 'Police Maverick' },
            { model: 'savage', name: 'Savage' },
            { model: 'seasparrow', name: 'Sea Sparrow' },
            { model: 'skylift', name: 'Skylift' },
            { model: 'supervolito', name: 'SuperVolito' },
            { model: 'supervolito2', name: 'SuperVolito Carbon' },
            { model: 'swift', name: 'Swift' },
            { model: 'swift2', name: 'Swift Deluxe' },
            { model: 'valkyrie', name: 'Valkyrie' },
            { model: 'valkyrie2', name: 'Valkyrie MOD.0' },
            { model: 'volatus', name: 'Volatus' }
        ],
        planes: [
            { model: 'alphaz1', name: 'Alpha-Z1' },
            { model: 'avenger', name: 'Avenger' },
            { model: 'avenger2', name: 'Avenger (Interior)' },
            { model: 'besra', name: 'Besra' },
            { model: 'bombushka', name: 'Bombushka' },
            { model: 'cargoplane', name: 'Cargo Plane' },
            { model: 'cuban800', name: 'Cuban 800' },
            { model: 'dodo', name: 'Dodo' },
            { model: 'duster', name: 'Duster' },
            { model: 'howard', name: 'Howard NX-25' },
            { model: 'hydra', name: 'Hydra' },
            { model: 'jet', name: 'Luxor' },
            { model: 'lazer', name: 'P-996 LAZER' },
            { model: 'luxor', name: 'Luxor' },
            { model: 'luxor2', name: 'Luxor Deluxe' },
            { model: 'mammatus', name: 'Mammatus' },
            { model: 'microlight', name: 'Ultralight' },
            { model: 'miljet', name: 'Miljet' },
            { model: 'mogul', name: 'Mogul' },
            { model: 'molotok', name: 'Molotok' },
            { model: 'nimbus', name: 'Nimbus' },
            { model: 'nokota', name: 'Nokota' },
            { model: 'pyro', name: 'Pyro' },
            { model: 'rogue', name: 'Rogue' },
            { model: 'seabreeze', name: 'Seabreeze' },
            { model: 'shamal', name: 'Shamal' },
            { model: 'starling', name: 'Starling' },
            { model: 'strikeforce', name: 'B-11 Strikeforce' },
            { model: 'stunt', name: 'Mallard' },
            { model: 'titan', name: 'Titan' },
            { model: 'tula', name: 'Tula' },
            { model: 'velum', name: 'Velum' },
            { model: 'velum2', name: 'Velum 5-Seater' },
            { model: 'vestra', name: 'Vestra' },
            { model: 'volatol', name: 'Volatol' }
        ],
        boats: [
            { model: 'dinghy', name: 'Dinghy' },
            { model: 'dinghy2', name: 'Dinghy (2-Seater)' },
            { model: 'dinghy3', name: 'Dinghy (Heist)' },
            { model: 'dinghy4', name: 'Dinghy (Yacht)' },
            { model: 'jetmax', name: 'Jetmax' },
            { model: 'marquis', name: 'Marquis' },
            { model: 'predator', name: 'Police Predator' },
            { model: 'seashark', name: 'Seashark' },
            { model: 'seashark2', name: 'Seashark (Lifeguard)' },
            { model: 'seashark3', name: 'Seashark (Yacht)' },
            { model: 'speeder', name: 'Speeder' },
            { model: 'speeder2', name: 'Speeder (Yacht)' },
            { model: 'squalo', name: 'Squalo' },
            { model: 'submersible', name: 'Submersible' },
            { model: 'submersible2', name: 'Kraken' },
            { model: 'suntrap', name: 'Suntrap' },
            { model: 'toro', name: 'Toro' },
            { model: 'toro2', name: 'Toro (Yacht)' },
            { model: 'tropic', name: 'Tropic' },
            { model: 'tropic2', name: 'Tropic (Yacht)' },
            { model: 'tug', name: 'Tug' }
        ],
        emergency: [
            { model: 'ambulance', name: 'Ambulance' },
            { model: 'fbi', name: 'FIB' },
            { model: 'fbi2', name: 'FIB SUV' },
            { model: 'firetruk', name: 'Fire Truck' },
            { model: 'lguard', name: 'Lifeguard' },
            { model: 'pbus', name: 'Police Prison Bus' },
            { model: 'police', name: 'Police Cruiser' },
            { model: 'police2', name: 'Police Cruiser (Buffalo)' },
            { model: 'police3', name: 'Police Cruiser (Interceptor)' },
            { model: 'police4', name: 'Unmarked Cruiser' },
            { model: 'policeb', name: 'Police Bike' },
            { model: 'policeold1', name: 'Police Rancher' },
            { model: 'policeold2', name: 'Police Roadcruiser' },
            { model: 'policet', name: 'Police Transporter' },
            { model: 'polmav', name: 'Police Maverick' },
            { model: 'pranger', name: 'Park Ranger' },
            { model: 'predator', name: 'Police Predator' },
            { model: 'riot', name: 'RCV' },
            { model: 'riot2', name: 'RCV (Spoiler)' },
            { model: 'sheriff', name: 'Sheriff Cruiser' },
            { model: 'sheriff2', name: 'Sheriff SUV' }
        ],
        military: [
            { model: 'apc', name: 'APC' },
            { model: 'barracks', name: 'Barracks' },
            { model: 'barracks2', name: 'Barracks Semi' },
            { model: 'barracks3', name: 'Barracks (Covered)' },
            { model: 'barrage', name: 'Barrage' },
            { model: 'chernobog', name: 'Chernobog' },
            { model: 'crusader', name: 'Crusader' },
            { model: 'halftrack', name: 'Half-track' },
            { model: 'khanjali', name: 'TM-02 Khanjali' },
            { model: 'minitank', name: 'Invade and Persuade Tank' },
            { model: 'rhino', name: 'Rhino Tank' },
            { model: 'scarab', name: 'Scarab' },
            { model: 'thruster', name: 'Thruster (Jetpack)' },
            { model: 'trailersmall2', name: 'AA Trailer' }
        ],
        compacts: [
            { model: 'asbo', name: 'Asbo' },
            { model: 'blista', name: 'Blista' },
            { model: 'blista2', name: 'Blista Compact' },
            { model: 'blista3', name: 'Blista Go Go Monkey' },
            { model: 'brioso', name: 'Brioso R/A' },
            { model: 'brioso2', name: 'Brioso 300' },
            { model: 'brioso3', name: 'Brioso 300 Widebody' },
            { model: 'club', name: 'Club' },
            { model: 'dilettante', name: 'Dilettante' },
            { model: 'dilettante2', name: 'Dilettante (Patrol)' },
            { model: 'issi2', name: 'Issi' },
            { model: 'issi3', name: 'Issi Classic' },
            { model: 'issi4', name: 'Arena Issi' },
            { model: 'issi5', name: 'Issi Sport' },
            { model: 'kanjo', name: 'Blista Kanjo' },
            { model: 'panto', name: 'Panto' },
            { model: 'prairie', name: 'Prairie' },
            { model: 'rhapsody', name: 'Rhapsody' },
            { model: 'weevil', name: 'Weevil' },
            { model: 'weevil2', name: 'Weevil Custom' }
        ],
        sedans: [
            { model: 'asea', name: 'Asea' },
            { model: 'asea2', name: 'Asea (Snow)' },
            { model: 'asterope', name: 'Asterope' },
            { model: 'cog55', name: 'Cognoscenti 55' },
            { model: 'cog552', name: 'Cognoscenti 55 (Armored)' },
            { model: 'cognoscenti', name: 'Cognoscenti' },
            { model: 'cognoscenti2', name: 'Cognoscenti (Armored)' },
            { model: 'emperor', name: 'Emperor' },
            { model: 'emperor2', name: 'Emperor (Rusty)' },
            { model: 'emperor3', name: 'Emperor (Snow)' },
            { model: 'fugitive', name: 'Fugitive' },
            { model: 'glendale', name: 'Glendale' },
            { model: 'glendale2', name: 'Glendale Custom' },
            { model: 'ingot', name: 'Ingot' },
            { model: 'intruder', name: 'Intruder' },
            { model: 'premier', name: 'Premier' },
            { model: 'primo', name: 'Primo' },
            { model: 'primo2', name: 'Primo Custom' },
            { model: 'regina', name: 'Regina' },
            { model: 'romero', name: 'Romero Hearse' },
            { model: 'schafter2', name: 'Schafter' },
            { model: 'schafter5', name: 'Schafter V12 (Armored)' },
            { model: 'schafter6', name: 'Schafter LWB (Armored)' },
            { model: 'stafford', name: 'Stafford' },
            { model: 'stanier', name: 'Stanier' },
            { model: 'stratum', name: 'Stratum' },
            { model: 'stretch', name: 'Stretch' },
            { model: 'superd', name: 'Super Diamond' },
            { model: 'surge', name: 'Surge' },
            { model: 'tailgater', name: 'Tailgater' },
            { model: 'tailgater2', name: 'Tailgater S' },
            { model: 'warrener', name: 'Warrener' },
            { model: 'warrener2', name: 'Warrener HKR' },
            { model: 'washington', name: 'Washington' }
        ],
        coupes: [
            { model: 'cogcabrio', name: 'Cognoscenti Cabrio' },
            { model: 'exemplar', name: 'Exemplar' },
            { model: 'f620', name: 'F620' },
            { model: 'felon', name: 'Felon' },
            { model: 'felon2', name: 'Felon GT' },
            { model: 'jackal', name: 'Jackal' },
            { model: 'oracle', name: 'Oracle XS' },
            { model: 'oracle2', name: 'Oracle' },
            { model: 'sentinel', name: 'Sentinel XS' },
            { model: 'sentinel2', name: 'Sentinel' },
            { model: 'windsor', name: 'Windsor' },
            { model: 'windsor2', name: 'Windsor Drop' },
            { model: 'zion', name: 'Zion' },
            { model: 'zion2', name: 'Zion Cabrio' }
        ],
        sportsclassics: [
            { model: 'ardent', name: 'Ardent' },
            { model: 'btype', name: 'Roosevelt' },
            { model: 'btype2', name: 'Fr\u00e4nken Stange' },
            { model: 'btype3', name: 'Roosevelt Valor' },
            { model: 'casco', name: 'Casco' },
            { model: 'cheburek', name: 'Cheburek' },
            { model: 'cheetah2', name: 'Cheetah Classic' },
            { model: 'coquette2', name: 'Coquette Classic' },
            { model: 'deluxo', name: 'Deluxo' },
            { model: 'dynasty', name: 'Dynasty' },
            { model: 'feltzer3', name: 'Stirling GT' },
            { model: 'gt500', name: 'GT500' },
            { model: 'infernus2', name: 'Infernus Classic' },
            { model: 'jb700', name: 'JB 700' },
            { model: 'jb7002', name: 'JB 700W' },
            { model: 'mamba', name: 'Mamba' },
            { model: 'manana', name: 'Manana' },
            { model: 'michelli', name: 'Michelli GT' },
            { model: 'monroe', name: 'Monroe' },
            { model: 'nebula', name: 'Nebula Turbo' },
            { model: 'peyote', name: 'Peyote' },
            { model: 'pigalle', name: 'Pigalle' },
            { model: 'rapidgt3', name: 'Rapid GT Classic' },
            { model: 'retinue', name: 'Retinue' },
            { model: 'retinue2', name: 'Retinue Mk II' },
            { model: 'savestra', name: 'Savestra' },
            { model: 'stinger', name: 'Stinger' },
            { model: 'stingergt', name: 'Stinger GT' },
            { model: 'stromberg', name: 'Stromberg' },
            { model: 'swinger', name: 'Swinger' },
            { model: 'torero', name: 'Torero' },
            { model: 'tornado', name: 'Tornado' },
            { model: 'tornado2', name: 'Tornado (Convertible)' },
            { model: 'tornado3', name: 'Tornado Custom' },
            { model: 'tornado4', name: 'Tornado (Marachi)' },
            { model: 'tornado5', name: 'Tornado Rat Rod' },
            { model: 'tornado6', name: 'Tornado (Rusty)' },
            { model: 'turismo2', name: 'Turismo Classic' },
            { model: 'viseris', name: 'Viseris' },
            { model: 'z190', name: '190z' },
            { model: 'zion3', name: 'Zion Classic' },
            { model: 'ztype', name: 'Z-Type' }
        ],
        industrial: [
            { model: 'bulldozer', name: 'Bulldozer' },
            { model: 'caddy', name: 'Caddy' },
            { model: 'caddy2', name: 'Caddy (Bunker)' },
            { model: 'caddy3', name: 'Caddy (Utility)' },
            { model: 'cutter', name: 'Cutter' },
            { model: 'docktug', name: 'Dock Tug' },
            { model: 'dump', name: 'Dump' },
            { model: 'flatbed', name: 'Flatbed' },
            { model: 'guardian', name: 'Guardian' },
            { model: 'handler', name: 'Dock Handler' },
            { model: 'mixer', name: 'Cement Mixer' },
            { model: 'mixer2', name: 'Mixer' },
            { model: 'rubble', name: 'Rubble' },
            { model: 'tiptruck', name: 'Tip Truck' },
            { model: 'tiptruck2', name: 'Tip Truck 2' }
        ],
        utility: [
            { model: 'airtug', name: 'Airtug' },
            { model: 'forklift', name: 'Forklift' },
            { model: 'mower', name: 'Mower' },
            { model: 'ripley', name: 'Ripley' },
            { model: 'sadler', name: 'Sadler' },
            { model: 'sadler2', name: 'Sadler (Snow)' },
            { model: 'scrap', name: 'Scrap Truck' },
            { model: 'towtruck', name: 'Tow Truck' },
            { model: 'towtruck2', name: 'Tow Truck (Large)' },
            { model: 'tractor', name: 'Tractor' },
            { model: 'tractor2', name: 'Field Master' },
            { model: 'tractor3', name: 'Tractor (Snow)' },
            { model: 'utillitruck', name: 'Utility Truck' },
            { model: 'utillitruck2', name: 'Utility Truck 2' },
            { model: 'utillitruck3', name: 'Utility Truck 3' }
        ],
        vans: [
            { model: 'bison', name: 'Bison' },
            { model: 'bison2', name: 'Bison (Utility)' },
            { model: 'bison3', name: 'Bison (Snow)' },
            { model: 'bobcatxl', name: 'Bobcat XL' },
            { model: 'boxville', name: 'Boxville' },
            { model: 'boxville2', name: 'Boxville (LSDS)' },
            { model: 'boxville3', name: 'Boxville (Go Postal)' },
            { model: 'boxville4', name: 'Boxville (Humane)' },
            { model: 'boxville5', name: 'Boxville (Armored)' },
            { model: 'burrito', name: 'Burrito' },
            { model: 'burrito2', name: 'Burrito (Bugstars)' },
            { model: 'burrito3', name: 'Burrito (Utility)' },
            { model: 'burrito4', name: 'Burrito (Snow)' },
            { model: 'burrito5', name: 'Burrito (Gang)' },
            { model: 'camper', name: 'Camper' },
            { model: 'gburrito', name: 'Gang Burrito' },
            { model: 'gburrito2', name: 'Gang Burrito (Lost)' },
            { model: 'journey', name: 'Journey' },
            { model: 'minivan', name: 'Minivan' },
            { model: 'minivan2', name: 'Minivan Custom' },
            { model: 'paradise', name: 'Paradise' },
            { model: 'pony', name: 'Pony' },
            { model: 'pony2', name: 'Pony (Carpet)' },
            { model: 'rumpo', name: 'Rumpo' },
            { model: 'rumpo2', name: 'Rumpo (Deludamol)' },
            { model: 'rumpo3', name: 'Rumpo Custom' },
            { model: 'speedo', name: 'Speedo' },
            { model: 'speedo2', name: 'Clown Van' },
            { model: 'speedo4', name: 'Speedo Custom' },
            { model: 'surfer', name: 'Surfer' },
            { model: 'surfer2', name: 'Surfer (Rusty)' },
            { model: 'taco', name: 'Taco Van' },
            { model: 'youga', name: 'Youga' },
            { model: 'youga2', name: 'Youga Classic' },
            { model: 'youga3', name: 'Youga Classic 4x4' }
        ],
        cycles: [
            { model: 'bmx', name: 'BMX' },
            { model: 'cruiser', name: 'Cruiser' },
            { model: 'fixter', name: 'Fixter' },
            { model: 'scorcher', name: 'Scorcher' },
            { model: 'tribike', name: 'Whippet Race Bike' },
            { model: 'tribike2', name: 'Endurex Race Bike' },
            { model: 'tribike3', name: 'Tri-Cycles Race Bike' }
        ],
        service: [
            { model: 'airbus', name: 'Airport Bus' },
            { model: 'brickade', name: 'Brickade' },
            { model: 'bus', name: 'Bus' },
            { model: 'coach', name: 'Coach' },
            { model: 'festivalbus', name: 'Festival Bus' },
            { model: 'limo2', name: 'Turreted Limo' },
            { model: 'rallytruck', name: 'Rally Truck' },
            { model: 'rentbus', name: 'Rental Shuttle Bus' },
            { model: 'taxi', name: 'Taxi' },
            { model: 'tourbus', name: 'Tour Bus' },
            { model: 'trash', name: 'Trashmaster' },
            { model: 'trash2', name: 'Trashmaster (Rusty)' },
            { model: 'wastelander', name: 'Wastelander' }
        ],
        commercial: [
            { model: 'benson', name: 'Benson' },
            { model: 'biff', name: 'Biff' },
            { model: 'hauler', name: 'Hauler' },
            { model: 'hauler2', name: 'Hauler Custom' },
            { model: 'mule', name: 'Mule' },
            { model: 'mule2', name: 'Mule (Armored)' },
            { model: 'mule3', name: 'Mule (Heist)' },
            { model: 'mule4', name: 'Mule Custom' },
            { model: 'packer', name: 'Packer' },
            { model: 'phantom', name: 'Phantom' },
            { model: 'phantom2', name: 'Phantom Wedge' },
            { model: 'phantom3', name: 'Phantom Custom' },
            { model: 'pounder', name: 'Pounder' },
            { model: 'pounder2', name: 'Pounder Custom' },
            { model: 'stockade', name: 'Stockade' },
            { model: 'stockade3', name: 'Stockade (Snow)' },
            { model: 'terbyte', name: 'Terrorbyte' }
        ],
        openwheel: [
            { model: 'formula', name: 'PR4' },
            { model: 'formula2', name: 'R88' },
            { model: 'openwheel1', name: 'BR8' },
            { model: 'openwheel2', name: 'DR1' }
        ],
        suvs: [
            { model: 'baller', name: 'Baller' },
            { model: 'baller2', name: 'Baller (Old)' },
            { model: 'baller3', name: 'Baller LE' },
            { model: 'baller4', name: 'Baller LE LWB' },
            { model: 'baller5', name: 'Baller LE (Armored)' },
            { model: 'baller6', name: 'Baller LE LWB (Armored)' },
            { model: 'bjxl', name: 'BeeJay XL' },
            { model: 'cavalcade', name: 'Cavalcade' },
            { model: 'cavalcade2', name: 'Cavalcade (Old)' },
            { model: 'contender', name: 'Contender' },
            { model: 'dubsta', name: 'Dubsta' },
            { model: 'dubsta2', name: 'Dubsta (Black)' },
            { model: 'fq2', name: 'FQ 2' },
            { model: 'granger', name: 'Granger' },
            { model: 'gresley', name: 'Gresley' },
            { model: 'habanero', name: 'Habanero' },
            { model: 'huntley', name: 'Huntley S' },
            { model: 'landstalker', name: 'Landstalker' },
            { model: 'mesa', name: 'Mesa' },
            { model: 'mesa2', name: 'Mesa (Snow)' },
            { model: 'novak', name: 'Novak' },
            { model: 'patriot', name: 'Patriot' },
            { model: 'patriot2', name: 'Patriot Stretch' },
            { model: 'radi', name: 'Radius' },
            { model: 'rebla', name: 'Rebla GTS' },
            { model: 'rocoto', name: 'Rocoto' },
            { model: 'seminole', name: 'Seminole' },
            { model: 'serrano', name: 'Serrano' },
            { model: 'toros', name: 'Toros' },
            { model: 'xls', name: 'XLS' },
            { model: 'xls2', name: 'XLS (Armored)' }
        ]
    }), []);

    const addonVehicleList = useMemo(() => {
        if (!Array.isArray(addonVehicles) || addonVehicles.length === 0) return [];

        const baseModels = new Set();
        Object.values(vehicleDatabase).forEach((list) => {
            if (!Array.isArray(list)) return;
            list.forEach((entry) => {
                if (entry && entry.model) {
                    baseModels.add(String(entry.model).toLowerCase());
                }
            });
        });

        const seen = new Set();
        return addonVehicles
            .map((entry) => {
                const model = entry && entry.model ? String(entry.model).trim().toLowerCase() : '';
                if (!model || seen.has(model)) return null;
                seen.add(model);

                const fallbackName = model
                    .replace(/_/g, ' ')
                    .replace(/\b\w/g, (s) => s.toUpperCase());
                const name = (entry && (entry.name || entry.gameName)) ? String(entry.name || entry.gameName).trim() : fallbackName;

                return {
                    model,
                    name,
                    isReplacement: baseModels.has(model),
                    sourceType: entry && entry.sourceType ? String(entry.sourceType) : 'metadata',
                    ownerResource: entry && entry.ownerResource ? String(entry.ownerResource) : undefined,
                    dataResource: entry && entry.dataResource ? String(entry.dataResource) : undefined
                };
            })
            .filter(Boolean)
            .sort((a, b) => a.name.localeCompare(b.name));
    }, [addonVehicles, vehicleDatabase]);

    const vehicleDatabaseWithAddons = useMemo(() => ({
        ...vehicleDatabase,
        addons: addonVehicleList
    }), [vehicleDatabase, addonVehicleList]);

    const categories = [
        { id: 'addons', label: 'Addons' },
        { id: 'super', label: 'Super' },
        { id: 'sports', label: 'Sports' },
        { id: 'sportsclassics', label: 'Classics' },
        { id: 'muscle', label: 'Muscle' },
        { id: 'coupes', label: 'Coupes' },
        { id: 'sedans', label: 'Sedans' },
        { id: 'compacts', label: 'Compacts' },
        { id: 'suvs', label: 'SUVs' },
        { id: 'offroad', label: 'Off-Road' },
        { id: 'vans', label: 'Vans' },
        { id: 'motorcycles', label: 'Bikes' },
        { id: 'cycles', label: 'Cycles' },
        { id: 'commercial', label: 'Commercial' },
        { id: 'industrial', label: 'Industrial' },
        { id: 'utility', label: 'Utility' },
        { id: 'service', label: 'Service' },
        { id: 'helicopters', label: 'Helis' },
        { id: 'planes', label: 'Planes' },
        { id: 'boats', label: 'Boats' },
        { id: 'emergency', label: 'Emergency' },
        { id: 'military', label: 'Military' },
        { id: 'openwheel', label: 'Open Wheel' }
    ];

    const filteredVehicles = useMemo(() => {
        const categoryVehicles = vehicleDatabaseWithAddons[activeCategory] || [];
        if (!search.trim()) return categoryVehicles;
        const query = search.toLowerCase();
        return categoryVehicles.filter(v => 
            v.name.toLowerCase().includes(query) || 
            v.model.toLowerCase().includes(query)
        );
    }, [vehicleDatabaseWithAddons, activeCategory, search]);

    const isAutoReplace = settings.replacePersonalVehicle !== false;

    useEffect(() => {
        fetchNui('cortex-admin:requestAddonVehicles');
    }, []);

    useEffect(() => {
        setShareOn(previewSharedProp === true);
    }, [previewSharedProp, launchKey]);

    useEffect(() => {
        if (!launchKey) return;
        const m = launchModel && String(launchModel).trim();
        if (!m) return;
        if (launchResumeOnly) {
            setPreviewModel(m);
            setPreviewName(m);
            return;
        }
        if (onPreview) onPreview(m);
        setPreviewModel(m);
        setPreviewName(m);
    }, [launchKey, launchModel, launchResumeOnly, onPreview]);

    const refreshExtras = useCallback(async () => {
        if (!extrasEnabled || !previewModel) {
            setExtrasList([]);
            return;
        }
        const res = await fetchNui('cortex-admin:getPreviewVehicleExtras');
        const ex = res && res.data && res.data.extras;
        setExtrasList(Array.isArray(ex) ? ex : []);
    }, [extrasEnabled, previewModel]);

    useEffect(() => {
        if (!extrasEnabled) {
            setExtrasList([]);
            return undefined;
        }
        if (!previewModel) {
            setExtrasList([]);
            return undefined;
        }
        let cancelled = false;
        const t = window.setTimeout(() => {
            refreshExtras().then(() => {
                if (cancelled) return;
            });
        }, 120);
        return () => {
            cancelled = true;
            window.clearTimeout(t);
        };
    }, [extrasEnabled, previewModel, refreshExtras]);

    const handleExtraToggle = useCallback(async (id) => {
        await fetchNui('cortex-admin:togglePreviewVehicleExtra', { extraId: id });
        refreshExtras();
    }, [refreshExtras]);

    const handleSharePreview = useCallback(async (e) => {
        if (e) e.stopPropagation();
        if (!previewModel) return;
        const next = !shareOn;
        const res = await fetchNui('cortex-admin:setVehiclePreviewShared', { shared: next });
        if (res.ok && res.data && res.data.ok) {
            setShareOn(next);
        }
    }, [previewModel, shareOn]);

    const setPreviewSelection = (model, name) => {
        if (!model) return;
        if (onPreview) onPreview(model);
        setPreviewModel(model);
        setPreviewName(name || model);
    };

    const handlePreviewCustom = () => {
        const model = customModel.trim();
        if (model) {
            setPreviewSelection(model, model);
            setCustomModel('');
        }
    };

    const handlePreviewFromList = (v, e) => {
        e.stopPropagation();
        setPreviewSelection(v.model, v.name);
    };

    const handleClearPreview = (e) => {
        if (e) e.stopPropagation();
        if (onClearPreview) onClearPreview();
        setPreviewModel('');
        setPreviewName('');
        setShareOn(false);
    };

    const handleSpawnPreview = async (e) => {
        if (e) e.stopPropagation();
        if (!previewModel) return;
        if (extrasEnabled) {
            const res = await fetchNui('cortex-admin:spawnPreviewVehicle');
            if (res.ok && res.data && res.data.ok) {
                setPreviewModel('');
                setPreviewName('');
                setExtrasList([]);
                setShareOn(false);
            }
            return;
        }
        if (onClearPreview) onClearPreview();
        onSpawn(previewModel);
        setPreviewModel('');
        setPreviewName('');
        setShareOn(false);
    };

    const handleKeyDown = (e) => {
        e.stopPropagation();
        if (e.key === 'Enter') {
            handlePreviewCustom();
        }
    };

    const handleClose = () => {
        onClose();
    };

    return React.createElement('div', {
        className: extrasEnabled ? 'admin-inline-spawner admin-inline-spawner--preview' : 'admin-inline-spawner',
        onClick: (e) => e.stopPropagation()
    },
        // Custom model input row
        React.createElement('div', { className: 'admin-inline-spawner-custom' },
            React.createElement('input', {
                className: 'admin-inline-spawner-input',
                value: customModel,
                placeholder: 'Model name (e.g., adder)',
                'aria-label': 'Vehicle model',
                autoFocus: true,
                onKeyDown: handleKeyDown,
                onChange: (e) => setCustomModel(e.target.value)
            }),
            React.createElement('button', {
                className: 'admin-button small',
                onClick: handlePreviewCustom,
                disabled: !customModel.trim()
            }, 'Preview')
        ),
        // Category and filter row
        React.createElement('div', { className: 'admin-inline-spawner-header' },
            React.createElement('input', {
                className: 'admin-inline-spawner-search',
                value: search,
                placeholder: 'Filter...',
                'aria-label': 'Filter vehicles',
                onKeyDown: (e) => e.stopPropagation(),
                onChange: (e) => setSearch(e.target.value)
            }),
            React.createElement(CustomSelect, {
                options: categories.map(c => ({ 
                    label: `${c.label} (${(vehicleDatabaseWithAddons[c.id] || []).length})`, 
                    value: c.id 
                })),
                value: activeCategory,
                ariaLabel: 'Vehicle category',
                onChange: setActiveCategory
            }),
            React.createElement('button', {
                type: 'button',
                className: 'admin-inline-spawner-toggle',
                onClick: () => onToggleSetting('replacePersonalVehicle', !isAutoReplace),
                role: 'switch',
                'aria-checked': isAutoReplace,
                title: 'Replace previous spawned vehicle: delete occupied vehicle before spawn (list, preview, personal, garage)'
            },
                React.createElement('div', { className: `admin-toggle${isAutoReplace ? ' active' : ''}`, 'aria-hidden': true }),
                React.createElement('span', null, 'Replace')
            )
        ),
        // Vehicle list
        React.createElement('div', { className: 'admin-inline-spawner-list' },
            filteredVehicles.length === 0 
                ? React.createElement('div', { className: 'admin-inline-spawner-empty' }, 'No vehicles match your filter.')
                : filteredVehicles.map(v => React.createElement('button', {
                    type: 'button',
                    key: v.model,
                    className: `admin-inline-spawner-item${hovered === v.model ? ' hovered' : ''}`,
                    onMouseEnter: () => setHovered(v.model),
                    onMouseLeave: () => setHovered(null),
                    onClick: (e) => handlePreviewFromList(v, e)
                },
                    React.createElement('div', { className: 'admin-inline-spawner-info' },
                        React.createElement('div', { className: 'admin-inline-spawner-name-row' },
                            React.createElement('span', { className: 'admin-inline-spawner-name' }, v.name),
                            v.isReplacement && React.createElement('span', { className: 'admin-inline-spawner-badge replacement' }, 'Replacement'),
                            v.sourceType === 'stream_fallback' && React.createElement('span', { className: 'admin-inline-spawner-badge fallback' }, 'Fallback')
                        ),
                        React.createElement('span', { className: 'admin-inline-spawner-model' }, v.model)
                    )
                ))
        ),
        extrasEnabled && previewModel && React.createElement('div', { className: 'admin-inline-spawner-extras' },
            React.createElement('div', { className: 'admin-inline-spawner-extras-title' }, 'Extras'),
            extrasList.length === 0
                ? React.createElement('div', { className: 'admin-inline-spawner-extras-empty' }, 'No extras on this model.')
                : React.createElement('div', { className: 'admin-inline-spawner-extras-grid' },
                    extrasList.map((ex) => React.createElement('button', {
                        key: ex.id,
                        type: 'button',
                        className: `admin-inline-spawner-extra${ex.on ? ' on' : ''}`,
                        onClick: (ev) => {
                            ev.stopPropagation();
                            handleExtraToggle(ex.id);
                        }
                    }, `Extra ${ex.id}`))
                )
        ),
        // Footer
        React.createElement('div', { className: 'admin-inline-spawner-footer' },
            previewModel
                ? React.createElement('div', { className: 'admin-inline-spawner-status', 'aria-live': 'polite' },
                    React.createElement('div', { className: 'admin-inline-spawner-status-line' },
                        React.createElement('span', { className: 'admin-inline-spawner-status-k' }, extrasEnabled ? 'Preview' : 'Selected'),
                        React.createElement('span', { className: 'admin-inline-spawner-status-name', title: previewName }, previewName)
                    ),
                    React.createElement('div', { className: 'admin-inline-spawner-status-sub', title: `${previewModel}${extrasEnabled ? ' · extras kept on spawn' : ''}` },
                        React.createElement('code', { className: 'admin-inline-spawner-status-code' }, previewModel),
                        extrasEnabled && React.createElement('span', { className: 'admin-inline-spawner-status-hint' }, ' · extras kept on spawn')
                    )
                )
                : React.createElement('div', { className: 'admin-inline-spawner-status', 'aria-live': 'polite' },
                    React.createElement('div', { className: 'admin-inline-spawner-status-sub' }, `${filteredVehicles.length} vehicles in category`)
                ),
            React.createElement('div', { className: 'admin-inline-spawner-footer-actions' },
                previewModel && extrasEnabled && React.createElement('button', {
                    type: 'button',
                    className: `admin-button small admin-inline-spawner-footer-btn${shareOn ? ' success' : ''}`,
                    onClick: handleSharePreview,
                    title: 'Other players can see this preview and extras'
                }, shareOn ? 'Shared' : 'Share'),
                previewModel && React.createElement('button', {
                    type: 'button',
                    className: 'admin-button small success admin-inline-spawner-footer-btn',
                    onClick: handleSpawnPreview,
                    title: extrasEnabled ? 'Spawn with current extras and setup' : 'Spawn this vehicle'
                }, 'Spawn'),
                previewModel && React.createElement('button', { type: 'button', className: 'admin-button small admin-inline-spawner-footer-btn', onClick: handleClearPreview }, 'Clear'),
                React.createElement('button', { type: 'button', className: 'admin-button small admin-inline-spawner-footer-btn', onClick: handleClose }, 'Close')
            )
        )
    );
}

// ============================================================================
// INLINE INVENTORY - Searchable item dropdown with give-to-player support
// ============================================================================

function InlineInventory({ items, players, onClose }) {
    const [search, setSearch] = useState('');
    const [selectedItem, setSelectedItem] = useState(null);
    const [amount, setAmount] = useState(1);
    const [targetPlayer, setTargetPlayer] = useState('');
    const [loading, setLoading] = useState(false);

    // Request items on first render if not cached
    useEffect(() => {
        if (!items || items.length === 0) {
            fetchNui('cortex-admin:requestItems');
        }
    }, []);

    const filteredItems = useMemo(() => {
        if (!items || !Array.isArray(items)) return [];
        if (!search.trim()) return items;
        const q = search.toLowerCase();
        return items.filter(item =>
            (item.name && item.name.toLowerCase().includes(q)) ||
            (item.label && item.label.toLowerCase().includes(q))
        );
    }, [items, search]);

    const handleGive = () => {
        if (!selectedItem || !targetPlayer) return;
        setLoading(true);
        fetchNui('cortex-admin:giveItem', {
            target: targetPlayer,
            item: selectedItem.name,
            amount: Math.max(1, parseInt(amount) || 1)
        }).then(() => {
            setLoading(false);
        });
    };

    const playerOptions = useMemo(() => {
        if (!players || !Array.isArray(players)) return [];
        return players.map(p => ({ label: `[${p.id}] ${p.name}`, value: p.id }));
    }, [players]);

    return React.createElement('div', { className: 'admin-inline-inventory' },
        // Target player selector
        React.createElement('div', { className: 'admin-inline-inventory-row' },
            React.createElement('label', { className: 'admin-inline-inventory-label' }, 'Target Player'),
            React.createElement('select', {
                className: 'admin-inline-inventory-select',
                value: targetPlayer,
                onChange: (e) => setTargetPlayer(e.target.value)
            },
                React.createElement('option', { value: '' }, '-- Select Player --'),
                playerOptions.map(p => React.createElement('option', { key: p.value, value: p.value }, p.label))
            )
        ),
        // Item search
        React.createElement('div', { className: 'admin-inline-inventory-search' },
            React.createElement(Icon, { name: 'search', size: 14, className: 'admin-inline-inventory-search-icon' }),
            React.createElement('input', {
                type: 'text',
                className: 'admin-inline-inventory-search-input',
                placeholder: 'Search items...',
                value: search,
                onChange: (e) => setSearch(e.target.value)
            }),
            search && React.createElement('button', {
                className: 'admin-inline-inventory-search-clear',
                onClick: () => setSearch('')
            }, React.createElement(Icon, { name: 'x', size: 12 }))
        ),
        // Item list
        React.createElement('div', { className: 'admin-inline-inventory-list' },
            (!items || items.length === 0)
                ? React.createElement('div', { className: 'admin-inline-inventory-empty' }, 'Loading items...')
                : filteredItems.length === 0
                    ? React.createElement('div', { className: 'admin-inline-inventory-empty' }, 'No items found')
                    : filteredItems.slice(0, 200).map(item =>
                        React.createElement('div', {
                            key: item.name,
                            className: `admin-inline-inventory-item${selectedItem && selectedItem.name === item.name ? ' selected' : ''}`,
                            onClick: () => setSelectedItem(item)
                        },
                            React.createElement('span', { className: 'admin-inline-inventory-item-label' }, item.label || item.name),
                            React.createElement('span', { className: 'admin-inline-inventory-item-name' }, item.name),
                            item.weight > 0 && React.createElement('span', { className: 'admin-inline-inventory-item-weight' }, `${(item.weight / 1000).toFixed(1)}kg`)
                        )
                    )
        ),
        // Selected item + amount + give
        selectedItem && React.createElement('div', { className: 'admin-inline-inventory-give' },
            React.createElement('div', { className: 'admin-inline-inventory-selected', title: selectedItem.name },
                React.createElement('span', { className: 'admin-inline-inventory-selected-label' }, selectedItem.label || selectedItem.name),
                React.createElement('code', { className: 'admin-inline-inventory-selected-code' }, selectedItem.name)
            ),
            React.createElement('div', { className: 'admin-inline-inventory-give-row' },
                React.createElement('input', {
                    type: 'number',
                    className: 'admin-inline-inventory-amount',
                    'aria-label': 'Amount',
                    min: 1,
                    max: 9999,
                    value: amount,
                    onChange: (e) => setAmount(e.target.value)
                }),
                React.createElement('button', {
                    className: 'admin-button success',
                    onClick: handleGive,
                    disabled: loading || !targetPlayer
                }, loading ? 'Giving...' : 'Give Item')
            )
        ),
        // Footer
        React.createElement('div', { className: 'admin-inline-inventory-footer' },
            React.createElement('span', null, `${filteredItems.length} of ${(items || []).length} items`),
            React.createElement('button', { className: 'admin-button small', onClick: onClose }, 'Close')
        )
    );
}

// ============================================================================
// INLINE GARAGE - Personal vehicle list from QBX garage
// ============================================================================

function InlineGarage({ vehicles, onClose }) {
    const [search, setSearch] = useState('');
    const [activeGarage, setActiveGarage] = useState('all');
    const [loading, setLoading] = useState(null);

    // Request garage vehicles on first render
    useEffect(() => {
        fetchNui('cortex-admin:requestGarage');
    }, []);

    const stateLabels = { 0: 'Out', 1: 'Garaged', 2: 'Impounded' };
    const stateClasses = { 0: 'state-out', 1: 'state-garaged', 2: 'state-impounded' };

    const garageNames = useMemo(() => {
        if (!vehicles || !Array.isArray(vehicles)) return ['all'];
        const names = new Set();
        vehicles.forEach(v => { if (v.garage) names.add(v.garage); });
        return ['all', ...Array.from(names).sort()];
    }, [vehicles]);

    const filteredVehicles = useMemo(() => {
        if (!vehicles || !Array.isArray(vehicles)) return [];
        let list = vehicles;
        if (activeGarage !== 'all') {
            list = list.filter(v => v.garage === activeGarage);
        }
        if (search.trim()) {
            const q = search.toLowerCase();
            list = list.filter(v =>
                (v.label && v.label.toLowerCase().includes(q)) ||
                (v.model && v.model.toLowerCase().includes(q)) ||
                (v.plate && v.plate.toLowerCase().includes(q)) ||
                (v.brand && v.brand.toLowerCase().includes(q))
            );
        }
        return list;
    }, [vehicles, activeGarage, search]);

    const handleSpawn = (vehicleId) => {
        setLoading(vehicleId);
        fetchNui('cortex-admin:spawnGarageVehicle', { vehicleId }).then(() => {
            setTimeout(() => setLoading(null), 1000);
        });
    };

    return React.createElement('div', { className: 'admin-inline-garage' },
        // Search + refresh
        React.createElement('div', { className: 'admin-inline-garage-toolbar' },
            React.createElement('div', { className: 'admin-inline-garage-search' },
                React.createElement(Icon, { name: 'search', size: 14, className: 'admin-inline-garage-search-icon' }),
                React.createElement('input', {
                    type: 'text',
                    className: 'admin-inline-garage-search-input',
                    placeholder: 'Search vehicles...',
                    value: search,
                    onChange: (e) => setSearch(e.target.value)
                }),
                search && React.createElement('button', {
                    className: 'admin-inline-garage-search-clear',
                    onClick: () => setSearch('')
                }, React.createElement(Icon, { name: 'x', size: 12 }))
            ),
            React.createElement('button', {
                className: 'admin-button small admin-inline-garage-refresh',
                onClick: () => { fetchNui('cortex-admin:requestGarage'); }
            }, 'Refresh')
        ),
        // Garage filter tabs
        garageNames.length > 2 && React.createElement('div', { className: 'admin-inline-garage-tabs' },
            garageNames.map(name =>
                React.createElement('button', {
                    key: name,
                    className: `admin-inline-garage-tab${activeGarage === name ? ' active' : ''}`,
                    onClick: () => setActiveGarage(name)
                }, name === 'all' ? 'All Garages' : name)
            )
        ),
        // Vehicle list
        React.createElement('div', { className: 'admin-inline-garage-list' },
            (!vehicles || vehicles.length === 0)
                ? React.createElement('div', { className: 'admin-inline-garage-empty' }, 'Loading garage...')
                : filteredVehicles.length === 0
                    ? React.createElement('div', { className: 'admin-inline-garage-empty' }, 'No vehicles found')
                    : filteredVehicles.map(veh =>
                        React.createElement('div', { key: veh.id, className: 'admin-inline-garage-item' },
                            React.createElement('div', { className: 'admin-inline-garage-item-info' },
                                React.createElement('div', { className: 'admin-inline-garage-item-name' },
                                    veh.brand ? `${veh.brand} ${veh.label}` : veh.label
                                ),
                                React.createElement('div', { className: 'admin-inline-garage-item-details' },
                                    React.createElement('span', { className: 'admin-inline-garage-item-plate' }, veh.plate || 'No Plate'),
                                    React.createElement('span', { className: 'admin-inline-garage-item-garage' }, veh.garage || 'Unknown'),
                                    React.createElement('span', { className: `admin-inline-garage-item-state ${stateClasses[veh.state] || ''}` },
                                        stateLabels[veh.state] || 'Unknown'
                                    )
                                )
                            ),
                            React.createElement('div', { className: 'admin-inline-garage-item-actions' },
                                React.createElement('button', {
                                    className: 'admin-button success',
                                    onClick: () => handleSpawn(veh.id),
                                    disabled: loading === veh.id
                                }, loading === veh.id ? 'Spawning...' : 'Spawn')
                            )
                        )
                    )
        ),
        // Footer
        React.createElement('div', { className: 'admin-inline-garage-footer' },
            React.createElement('span', null, `${filteredVehicles.length} of ${(vehicles || []).length} vehicles`),
            React.createElement('button', { className: 'admin-button small', onClick: onClose }, 'Close')
        )
    );
}

// QBX action definitions for inline prompts
const qbxActionConfigs = {
    'player.kill': { needsTarget: true, label: 'Kill', callback: 'cortex-admin:killPlayer', color: 'danger' },
    'player.reviveTarget': { needsTarget: true, label: 'Revive', callback: 'cortex-admin:revivePlayer', color: 'success' },
    'player.sitInVehicle': { needsTarget: true, label: 'Sit In', callback: 'cortex-admin:sitInVehicle', color: '' },
    'player.openInventory': { needsTarget: true, label: 'Open', callback: 'cortex-admin:openInventory', color: '' },
    'player.setJob': { needsTarget: true, fields: [{ name: 'job', label: 'Job Name', placeholder: 'police' }, { name: 'grade', label: 'Grade', placeholder: '0', type: 'number' }], callback: 'cortex-admin:setJob', color: 'success' },
    'player.setGang': { needsTarget: true, fields: [{ name: 'gang', label: 'Gang Name', placeholder: 'ballas' }, { name: 'grade', label: 'Grade', placeholder: '0', type: 'number' }], callback: 'cortex-admin:setGang', color: 'success' },
    'player.setCash': { needsTarget: true, fields: [{ name: 'amount', label: 'Amount', placeholder: '1000', type: 'number' }], callback: 'cortex-admin:setMoney', extra: { moneyType: 'cash', actionId: 'player.setCash' }, color: 'success' },
    'player.setBank': { needsTarget: true, fields: [{ name: 'amount', label: 'Amount', placeholder: '1000', type: 'number' }], callback: 'cortex-admin:setMoney', extra: { moneyType: 'bank', actionId: 'player.setBank' }, color: 'success' },
    'player.giveMoney': { needsTarget: true, fields: [{ name: 'amount', label: 'Amount', placeholder: '1000', type: 'number' }, { name: 'moneyType', label: 'Type', placeholder: 'cash', options: ['cash', 'bank'] }], callback: 'cortex-admin:giveMoney', color: 'success' },
    'player.setFood': { needsTarget: true, fields: [{ name: 'value', label: 'Hunger (0-100)', placeholder: '100', type: 'number' }], callback: 'cortex-admin:setMetadata', extra: { key: 'hunger', actionId: 'player.setFood' }, color: 'success' },
    'player.setThirst': { needsTarget: true, fields: [{ name: 'value', label: 'Thirst (0-100)', placeholder: '100', type: 'number' }], callback: 'cortex-admin:setMetadata', extra: { key: 'thirst', actionId: 'player.setThirst' }, color: 'success' },
    'player.setStress': { needsTarget: true, fields: [{ name: 'value', label: 'Stress (0-100)', placeholder: '0', type: 'number' }], callback: 'cortex-admin:setMetadata', extra: { key: 'stress', actionId: 'player.setStress' }, color: 'success' },
    'player.setRoutingBucket': { needsTarget: true, fields: [{ name: 'bucket', label: 'Bucket ID', placeholder: '0', type: 'number' }], callback: 'cortex-admin:setRoutingBucket', color: 'success' },
    'vehicle.adminCar': { needsTarget: false, label: 'Save to Garage', callback: 'cortex-admin:adminCar', color: 'success' },
    'server.pullStash': { needsTarget: false, fields: [{ name: 'stash', label: 'Stash Name', placeholder: 'police_stash' }], callback: 'cortex-admin:pullStash', color: 'success' },
};

function InlineQBXAction({ config, players, onClose }) {
    const [targetPlayer, setTargetPlayer] = useState('');
    const [fieldValues, setFieldValues] = useState(() => {
        // Initialize select fields with their first option as default
        const initial = {};
        if (config.fields) {
            config.fields.forEach(f => {
                if (f.options && f.options.length > 0) initial[f.name] = f.options[0];
            });
        }
        return initial;
    });
    const [loading, setLoading] = useState(false);

    const handleFieldChange = (name, value) => {
        setFieldValues(prev => ({ ...prev, [name]: value }));
    };

    const handleSubmit = () => {
        const payload = { ...(config.extra || {}), ...fieldValues };
        if (config.needsTarget) {
            if (!targetPlayer) return;
            payload.target = targetPlayer;
        }
        setLoading(true);
        fetchNui(config.callback, payload).then(() => {
            setLoading(false);
        });
    };

    const handleKeyDown = (e) => {
        e.stopPropagation();
        if (e.key === 'Enter') handleSubmit();
        if (e.key === 'Escape') onClose();
    };

    return React.createElement('div', { className: 'admin-inline-qbx', onClick: (e) => e.stopPropagation() },
        // Target player selector
        config.needsTarget && React.createElement('div', { className: 'admin-inline-qbx-row' },
            React.createElement('label', null, 'Target'),
            React.createElement('select', {
                className: 'admin-inline-qbx-select',
                value: targetPlayer,
                onChange: (e) => setTargetPlayer(e.target.value),
                onKeyDown: handleKeyDown
            },
                React.createElement('option', { value: '' }, '-- Select Player --'),
                (players || []).map(p => React.createElement('option', { key: p.id, value: p.id }, `[${p.id}] ${p.name}`))
            )
        ),
        // Dynamic fields
        config.fields && config.fields.map(field =>
            React.createElement('div', { key: field.name, className: 'admin-inline-qbx-row' },
                React.createElement('label', null, field.label),
                field.options
                    ? React.createElement('select', {
                        className: 'admin-inline-qbx-select',
                        value: fieldValues[field.name] || field.options[0] || '',
                        onChange: (e) => handleFieldChange(field.name, e.target.value),
                        onKeyDown: handleKeyDown
                    }, field.options.map(opt => React.createElement('option', { key: opt, value: opt }, opt)))
                    : React.createElement('input', {
                        className: 'admin-inline-qbx-input',
                        type: field.type || 'text',
                        placeholder: field.placeholder || '',
                        value: fieldValues[field.name] || '',
                        onChange: (e) => handleFieldChange(field.name, e.target.value),
                        onKeyDown: handleKeyDown
                    })
            )
        ),
        // Submit / Close
        React.createElement('div', { className: 'admin-inline-qbx-actions' },
            React.createElement('button', {
                className: `admin-button ${config.color || 'success'}`,
                onClick: handleSubmit,
                disabled: loading || (config.needsTarget && !targetPlayer)
            }, loading ? 'Working...' : (config.label || 'Submit')),
            React.createElement('button', { className: 'admin-button small', onClick: onClose }, 'Cancel')
        )
    );
}

function InlineWeaponAttachments({ onClose }) {
    const [weaponName, setWeaponName] = useState('');
    const [rows, setRows] = useState([]);
    const [busy, setBusy] = useState(false);

    const refresh = useCallback(async () => {
        const res = await fetchNui('cortex-admin:getWeaponAttachments');
        const d = res && res.data;
        if (d && d.ok) {
            setWeaponName(d.weaponName || '');
            setRows(Array.isArray(d.components) ? d.components : []);
        } else {
            setWeaponName('');
            setRows([]);
        }
    }, []);

    useEffect(() => {
        refresh();
    }, [refresh]);

    const toggle = async (h) => {
        if (busy || !h) return;
        setBusy(true);
        try {
            await fetchNui('cortex-admin:toggleWeaponAttachment', { componentHash: h });
            await refresh();
        } finally {
            setBusy(false);
        }
    };

    return React.createElement('div', { className: 'admin-inline-weapon-attachments', onClick: (e) => e.stopPropagation() },
        React.createElement('div', { className: 'admin-inline-spawner-extras-title' }, 'Attachments'),
        React.createElement('div', { className: 'admin-inline-spawner-status-sub', style: { marginBottom: 8 } },
            weaponName ? `Weapon: ${weaponName}` : 'Equip a weapon (in hand) to customize.'),
        rows.length === 0
            ? React.createElement('div', { className: 'admin-inline-spawner-extras-empty' },
                weaponName ? 'No attachment slots found for this weapon.' : 'Nothing to show.')
            : React.createElement('div', { className: 'admin-inline-spawner-extras-grid' },
                rows.map((row) => React.createElement('button', {
                    key: row.hash,
                    type: 'button',
                    className: `admin-inline-spawner-extra${row.on ? ' on' : ''}`,
                    disabled: busy,
                    onClick: (e) => {
                        e.stopPropagation();
                        toggle(row.hash);
                    }
                }, row.label || row.hash))
            ),
        React.createElement('div', { className: 'admin-inline-prompt-actions', style: { marginTop: 10 } },
            React.createElement('button', {
                type: 'button',
                className: 'admin-button small',
                onClick: (e) => {
                    e.stopPropagation();
                    refresh();
                }
            }, 'Refresh'),
            React.createElement('button', {
                type: 'button',
                className: 'admin-button small',
                onClick: (e) => {
                    e.stopPropagation();
                    onClose();
                }
            }, 'Close')
        )
    );
}

const ActionItem = React.memo(function ActionItem({ action, toggles, favorites, allowed, onToggle, onSelect, onAction, onFavorite, onContextMenu, isSelected, settings, onPromptSubmit, personalVehicles, addonVehicles, onSpawnVehicle, onDeleteVehicle, onSaveVehicle, onToggleSetting, onSpawnAnyVehicle, onPreviewAnyVehicle, onClearVehiclePreview, players, vehiclePreviewLaunch }) {
    const [expanded, setExpanded] = useState(false);
    const rowClickTimerRef = React.useRef(null);
    const isToggle = action.type === 'toggle';
    const isSelect = action.type === 'select';
    const isDock = action.type === 'dock';
    const isPrompt = action.type === 'prompt';
    const isPersonalVehicles = action.id === 'vehicle.personal';
    const isVehicleSpawner = action.id === 'vehicle.spawn';
    const isWeaponAttachments = action.id === 'weapons.attachments';
    const isQBXAction = !!qbxActionConfigs[action.id];
    const isWorkspace = action.type === 'workspace';
    const isAction = action.type === 'action' || isPrompt || isWorkspace;
    const isFavorite = favorites.includes(action.id);
    const isOptionToggle = isToggle && action.id.startsWith('options.');
    const optionKey = isOptionToggle ? action.id.replace('options.', '') : null;
    const isEnabled = isOptionToggle ? settings[optionKey] === true : toggles[action.id] === true;
    const isAllowed = allowed[action.id] !== false;

    useEffect(() => {
        if (!isVehicleSpawner || !vehiclePreviewLaunch || !vehiclePreviewLaunch.token) return;
        setExpanded(true);
    }, [isVehicleSpawner, vehiclePreviewLaunch && vehiclePreviewLaunch.token]);

    useEffect(() => {
        const closePanel = () => setExpanded(false);
        window.addEventListener('cortex-admin:closeActionPanels', closePanel);
        return () => {
            window.removeEventListener('cortex-admin:closeActionPanels', closePanel);
            if (rowClickTimerRef.current) window.clearTimeout(rowClickTimerRef.current);
        };
    }, []);

    const controls = [];

    if (isDock) {
        const side = normalizeMenuDock(action.selected);
        const mkBtn = (value, label, iconName) => React.createElement('button', {
            type: 'button',
            className: `admin-dock-choice${side === value ? ' active' : ''}${!isAllowed ? ' disabled' : ''}`,
            disabled: !isAllowed,
            'aria-pressed': side === value,
            onClick: (e) => {
                e.stopPropagation();
                if (!isAllowed || side === value) return;
                onSelect(action, value);
            }
        }, React.createElement(Icon, { name: iconName, size: 13 }), React.createElement('span', { className: 'admin-dock-choice-label' }, label));
        controls.push(React.createElement('div', {
            key: 'dock',
            className: 'admin-dock-segmented',
            role: 'group',
            'aria-label': action.label || 'Menu dock side'
        }, mkBtn('left', 'Left', 'panel-left'), mkBtn('right', 'Right', 'panel-right')));
    }

    if (action.type === 'color') {
        const raw = typeof action.selected === 'string' ? action.selected : '#e8a23f';
        const v = normalizeHex6(raw) || '#e8a23f';
        controls.push(React.createElement('input', {
            key: 'color',
            type: 'color',
            className: 'admin-color-input',
            value: v,
            disabled: !isAllowed,
            'aria-label': action.label || 'Accent color',
            onChange: (e) => onSelect(action, e.target.value)
        }));
    }

    if (action.type === 'slider') {
        const min = Number(action.min);
        const max = Number(action.max);
        const step = Number(action.step);
        const safeStep = Number.isFinite(step) && step > 0 ? step : 1;
        const lo = Number.isFinite(min) ? min : 0;
        const hi = Number.isFinite(max) ? max : 100;
        const rawVal = Number(action.selected);
        const val = clamp(Number.isFinite(rawVal) ? rawVal : lo, lo, hi);
        const label = formatSliderReadout(action, val);
        controls.push(React.createElement('div', { key: 'slider', className: 'admin-slider' },
            React.createElement('input', {
                type: 'range',
                min: lo,
                max: hi,
                step: safeStep,
                value: val,
                disabled: !isAllowed,
                'aria-label': action.label || action.id,
                'aria-valuemin': lo,
                'aria-valuemax': hi,
                'aria-valuenow': val,
                onChange: (e) => {
                    const next = safeStep < 1 ? parseFloat(e.target.value) : parseFloat(e.target.value);
                    if (Number.isFinite(next)) onSelect(action, next);
                }
            }),
            React.createElement('span', { className: 'admin-slider-value' }, label)
        ));
    }

    if (isSelect) {
        const options = normalizeValues(action.values);
        const isPercentSelect = isPercentValues(options);
        const useSlider = isPercentSelect;

        if (useSlider) {
            const selectedIndex = Math.max(0, options.findIndex((option) => String(option.value) === String(action.selected)));
            const activeIndex = selectedIndex >= 0 ? selectedIndex : 0;
            const activeOption = options[activeIndex] || options[0];

            controls.push(React.createElement('div', { key: 'slider', className: 'admin-slider' },
                React.createElement('input', {
                    type: 'range',
                    min: 0,
                    max: Math.max(0, options.length - 1),
                    step: 1,
                    value: activeIndex,
                    disabled: !isAllowed,
                    'aria-label': action.label || action.id,
                    onChange: (e) => {
                        const index = Number(e.target.value);
                        const nextOption = options[index];
                        if (nextOption) onSelect(action, nextOption.value);
                    }
                }),
                React.createElement('span', { className: 'admin-slider-value' }, activeOption ? activeOption.label : '')
            ));
        } else {
            controls.push(React.createElement(CustomSelect, {
                key: 'select',
                options,
                value: action.selected,
                disabled: !isAllowed,
                onChange: (value) => onSelect(action, value)
            }));
        }
    }

    if (isToggle) {
        controls.push(React.createElement('button', {
            key: 'toggle-pill',
            className: `admin-option-toggle${isEnabled ? ' active' : ''}${!isAllowed ? ' disabled' : ''}`,
            type: 'button',
            title: `${isEnabled ? 'Disable' : 'Enable'} ${action.label}`,
            'aria-label': `${isEnabled ? 'Disable' : 'Enable'} ${action.label}`,
            disabled: !isAllowed,
            onClick: (e) => {
                e.stopPropagation();
                onToggle(action, !isEnabled);
            }
        }, React.createElement('span', { className: 'admin-option-toggle-thumb' })));
    }

    if (isAction) {
        // Only expandable rows get a chevron; plain action rows are activated by clicking the row itself.
        const isExpandable = isPrompt || isPersonalVehicles || isVehicleSpawner || isQBXAction || isWeaponAttachments;
        if (isExpandable) {
            const handleButtonClick = (e) => {
                if (e) e.stopPropagation();
                setExpanded(!expanded);
            };

            controls.push(React.createElement('button', {
                key: 'chevron',
                className: `admin-action-chevron${expanded ? ' expanded' : ''}${!isAllowed ? ' disabled' : ''}`,
                type: 'button',
                title: `${expanded ? 'Collapse' : 'Expand'} ${action.label}`,
                'aria-label': `${expanded ? 'Collapse' : 'Expand'} ${action.label}`,
                disabled: !isAllowed,
                onClick: handleButtonClick
            }, React.createElement(Icon, { name: 'chevron-right', size: 15 })));
        }
    }

    // Build class name with selected state
    const isActive = isToggle && isEnabled;
    let className = 'admin-action';
    if (!isAllowed) className += ' disabled';
    if (isSelected) className += ' selected';
    if (isActive) className += ' active';
    if (expanded) className += ' expanded';
    if (expanded && isVehicleSpawner) className += ' admin-action--vehicle-spawner-inline';

    const activateRow = () => {
        if (!isAllowed) return;
        if (isSelect || isDock || action.type === 'slider' || action.type === 'color') return;
        if (isPrompt || isPersonalVehicles || isVehicleSpawner || isQBXAction || isWeaponAttachments) {
            setExpanded(!expanded);
        } else if (isAction) {
            onAction(action);
        }
        if (isToggle) onToggle(action, !isEnabled);
    };

    const handleClick = (e) => {
        if (!isAllowed) return;
        if (e.target.closest('.admin-select') || e.target.closest('.admin-slider') || e.target.closest('.admin-color-input') || e.target.closest('.admin-button') || e.target.closest('.admin-action-chevron') || e.target.closest('.admin-toggle') || e.target.closest('.admin-option-toggle') || e.target.closest('.admin-action-star') || e.target.closest('.admin-inline-prompt') || e.target.closest('.admin-inline-vehicles') || e.target.closest('.admin-inline-spawner') || e.target.closest('.admin-inline-spawner-extra') || e.target.closest('.admin-inline-qbx') || e.target.closest('.admin-inline-weapon-attachments') || e.target.closest('.admin-dock-segmented')) {
            return;
        }

        if (settings.doubleClickToRun === true && (isAction || isToggle)) {
            if (e.detail > 1) return;
            if (rowClickTimerRef.current) window.clearTimeout(rowClickTimerRef.current);
            rowClickTimerRef.current = window.setTimeout(() => {
                rowClickTimerRef.current = null;
                activateRow();
            }, 180);
            return;
        }

        activateRow();
    };

    const handleDoubleClick = (e) => {
        if (!isAllowed || settings.doubleClickToRun !== true || (!isAction && !isToggle)) return;
        if (e.target.closest('button, input, select, textarea, .admin-select, .admin-slider, .admin-inline-prompt, .admin-inline-vehicles, .admin-inline-spawner, .admin-inline-qbx, .admin-inline-weapon-attachments')) return;
        if (rowClickTimerRef.current) {
            window.clearTimeout(rowClickTimerRef.current);
            rowClickTimerRef.current = null;
        }
        activateRow();
    };

    const handlePromptConfirm = (values) => {
        if (onPromptSubmit) {
            onPromptSubmit(action, values);
        }
        setExpanded(false);
    };

    const handlePromptCancel = () => {
        setExpanded(false);
    };

    return React.createElement('div', {
        className,
        onDoubleClick: handleDoubleClick,
        onClick: handleClick,
        onContextMenu: (event) => {
            event.preventDefault();
            event.stopPropagation();
            if (typeof onContextMenu === 'function') onContextMenu(event, action);
        }
    },
        React.createElement('div', { className: 'admin-action-row' },
            React.createElement('div', { className: 'admin-action-left' },
                React.createElement('div', {
                    className: `admin-action-enabled-dot${isToggle && isEnabled ? ' visible' : ''}`,
                    'aria-hidden': true
                }),
                React.createElement('div', { className: 'admin-action-info' },
                    React.createElement('div', { className: 'admin-action-label' }, action.label),
                    React.createElement('div', { className: 'admin-action-description' }, action.description || '')
                )
            ),
            React.createElement('div', { className: 'admin-action-controls' },
                React.createElement('button', {
                    className: `admin-action-star${isFavorite ? ' active' : ''}`,
                    type: 'button',
                    'data-tooltip': isFavorite ? `Remove ${action.label} from favorites` : `Add ${action.label} to favorites`,
                    'aria-label': isFavorite ? `Remove ${action.label} from favorites` : `Add ${action.label} to favorites`,
                    'aria-pressed': isFavorite,
                    onClick: (e) => {
                        e.stopPropagation();
                        onFavorite(action.id);
                    }
                }, React.createElement(Icon, { name: 'star', size: 14 })),
                controls
            )
        ),
        // Inline prompt expansion
        expanded && isPrompt && action.prompt && React.createElement(InlinePrompt, {
            fields: action.prompt.fields || [],
            onCancel: handlePromptCancel,
            onConfirm: handlePromptConfirm
        }),
        // Inline personal vehicles expansion
        expanded && isPersonalVehicles && React.createElement(InlinePersonalVehicles, {
            vehicles: personalVehicles || [],
            settings: settings,
            onSpawn: onSpawnVehicle,
            onDelete: onDeleteVehicle,
            onSave: onSaveVehicle,
            onToggleSetting: onToggleSetting,
            onClose: () => setExpanded(false)
        }),
        // Inline vehicle spawner expansion
        expanded && isVehicleSpawner && React.createElement(InlineVehicleSpawner, {
            settings: settings,
            addonVehicles: addonVehicles || [],
            onSpawn: onSpawnAnyVehicle,
            onPreview: onPreviewAnyVehicle,
            onClearPreview: onClearVehiclePreview,
            onToggleSetting: onToggleSetting,
            onClose: () => setExpanded(false),
            extrasEnabled: true,
            launchKey: vehiclePreviewLaunch ? vehiclePreviewLaunch.token : 0,
            launchModel: vehiclePreviewLaunch ? vehiclePreviewLaunch.model : null,
            launchResumeOnly: vehiclePreviewLaunch ? vehiclePreviewLaunch.resumeOnly === true : false,
            previewSharedProp: vehiclePreviewLaunch ? vehiclePreviewLaunch.shared === true : false
        }),
        // QBX inline action expansion
        expanded && isQBXAction && React.createElement(InlineQBXAction, {
            config: qbxActionConfigs[action.id],
            players: players,
            onClose: () => setExpanded(false)
        }),
        expanded && isWeaponAttachments && React.createElement(InlineWeaponAttachments, {
            onClose: () => setExpanded(false)
        })
    );
});


function Modal({ title, description, fields, onCancel, onConfirm }) {
    const [values, setValues] = useState(() => {
        const initialValues = {};
        (fields || []).forEach((field) => {
            initialValues[field.name] = field.initialValue || '';
        });
        return initialValues;
    });

    useEffect(() => {
        const initialValues = {};
        (fields || []).forEach((field) => {
            initialValues[field.name] = field.initialValue || '';
        });
        setValues(initialValues);
    }, [fields]);

    const handleChange = (name, value) => {
        setValues((prev) => ({ ...prev, [name]: value }));
    };

    const handleKeyDown = (e) => {
        e.stopPropagation();
        if (e.key === 'Enter') {
            onConfirm(values);
        }
        if (e.key === 'Escape') {
            onCancel();
        }
    };

    return createPortal(
        React.createElement('div', { className: 'admin-modal', onClick: onCancel },
            React.createElement('div', { className: 'admin-modal-card', onClick: (e) => e.stopPropagation() },
                React.createElement('div', { className: 'admin-modal-title' }, title),
                description && React.createElement('div', { className: 'admin-modal-field admin-modal-description' },
                    React.createElement('p', { className: 'admin-modal-description-text' }, description)
                ),
                fields.map((field, index) => React.createElement('div', { className: 'admin-modal-field', key: field.name },
                    React.createElement('label', null, field.label),
                    React.createElement('input', {
                        value: values[field.name] || '',
                        placeholder: field.placeholder || '',
                        autoFocus: index === 0,
                        onKeyDown: handleKeyDown,
                        onChange: (e) => handleChange(field.name, e.target.value)
                    })
                )),
                React.createElement('div', { className: 'admin-modal-actions' },
                    React.createElement('button', { className: 'admin-button danger', onClick: onCancel }, 'Cancel'),
                    React.createElement('button', {
                        className: 'admin-button success',
                        onClick: () => onConfirm(values)
                    }, 'Confirm')
                )
            )
        ),
        document.body
    );
}

function ConfirmModal({ title, message, onCancel, onConfirm }) {
    return createPortal(
        React.createElement('div', { className: 'admin-modal' },
            React.createElement('div', { className: 'admin-modal-card' },
                React.createElement('div', { className: 'admin-modal-title' }, title || 'Are you sure?'),
                React.createElement('div', { className: 'admin-modal-field admin-modal-description' },
                    React.createElement('p', { className: 'admin-modal-description-text' }, message || 'This action cannot be undone.')
                ),
                React.createElement('div', { className: 'admin-modal-actions' },
                    React.createElement('button', { className: 'admin-button', onClick: onCancel }, 'Cancel'),
                    React.createElement('button', { className: 'admin-button danger', onClick: onConfirm }, 'Confirm')
                )
            )
        ),
        document.body
    );
}

const CONTEXT_RUN_EXCLUSIONS = new Set([
    'vehicle.personal',
    'vehicle.spawn',
    'weapons.attachments'
]);

function ActionContextMenu({ context, favorites, allowed, onActivate, onFavorite, onClose }) {
    const menuRef = React.useRef(null);
    const action = context && context.action;

    useEffect(() => {
        if (!context) return undefined;
        const closeOutside = (event) => {
            if (menuRef.current && !menuRef.current.contains(event.target)) onClose();
        };
        const closeOnViewportChange = () => onClose();
        document.addEventListener('pointerdown', closeOutside);
        window.addEventListener('resize', closeOnViewportChange);
        window.addEventListener('blur', closeOnViewportChange);
        return () => {
            document.removeEventListener('pointerdown', closeOutside);
            window.removeEventListener('resize', closeOnViewportChange);
            window.removeEventListener('blur', closeOnViewportChange);
        };
    }, [context, onClose]);

    if (!context || !action) return null;

    const isFavorite = favorites.includes(action.id);
    const canRun = allowed[action.id] !== false
        && (action.type === 'action' || action.type === 'prompt' || action.type === 'toggle')
        && !CONTEXT_RUN_EXCLUSIONS.has(action.id);
    const left = Math.min(Math.max(8, Number(context.x) || 8), Math.max(8, window.innerWidth - 226));
    const top = Math.min(Math.max(8, Number(context.y) || 8), Math.max(8, window.innerHeight - (canRun ? 112 : 76)));

    return createPortal(h('div', {
        ref: menuRef,
        className: 'admin-action-context-menu',
        role: 'menu',
        'aria-label': `${action.label || 'Action'} options`,
        style: { left: `${left}px`, top: `${top}px` }
    },
        h('div', { className: 'admin-action-context-title' }, action.label || action.id),
        canRun && h('button', {
            type: 'button',
            role: 'menuitem',
            onClick: () => { onActivate(action); onClose(); }
        }, h(Icon, { name: action.type === 'toggle' ? 'toggle-right' : 'play', size: 13 }), action.type === 'toggle' ? 'Toggle' : action.type === 'prompt' ? 'Open prompt' : 'Run action'),
        h('button', {
            type: 'button',
            role: 'menuitem',
            onClick: () => { onFavorite(action.id); onClose(); }
        }, h(Icon, { name: 'star', size: 13 }), isFavorite ? 'Remove favorite' : 'Add favorite')
    ), document.body);
}

const PLAYER_WORKSPACE_ACTIONS = [
    { id: 'goto', permission: 'player.goto', label: 'Go to', icon: 'navigation' },
    { id: 'bring', permission: 'player.bring', label: 'Bring', icon: 'log-in' },
    { id: 'waypoint', permission: 'player.waypoint', label: 'Waypoint', icon: 'map-pin' },
    { id: 'spectate', permission: 'player.spectate', label: 'Spectate', icon: 'eye' },
    { id: 'message', permission: 'player.message', label: 'Message', icon: 'message-square' },
    { id: 'identifiers', permission: 'player.identifiers', label: 'Identifiers', icon: 'fingerprint' },
    { id: 'freeze', permission: 'player.freeze', label: 'Freeze', icon: 'snowflake' },
    { id: 'kill', permission: 'player.kill', label: 'Kill', icon: 'skull', danger: true },
    { id: 'kick', permission: 'player.kick', label: 'Kick', icon: 'log-out', danger: true },
    { id: 'ban', permission: 'player.ban', label: 'Ban', icon: 'ban', danger: true },
];

const PlayerList = React.memo(function PlayerList({ players, onAction, allowed, identifiers }) {
    const safePlayers = Array.isArray(players) ? players : [];
    const [query, setQuery] = useState('');
    const [selectedId, setSelectedId] = useState(null);
    const filtered = useMemo(() => {
        const needle = query.trim().toLowerCase();
        return safePlayers.filter((player) => !needle
            || String(player.name || '').toLowerCase().includes(needle)
            || String(player.id || '').includes(needle));
    }, [safePlayers, query]);
    const selected = safePlayers.find((player) => String(player.id) === String(selectedId)) || filtered[0] || null;

    useEffect(() => {
        if (selected && String(selected.id) !== String(selectedId)) setSelectedId(selected.id);
    }, [selected && selected.id]);

    return h('div', { className: 'admin-player-workspace' },
        h('div', { className: 'admin-workspace-toolbar' },
            h('div', { className: 'admin-search-wrapper' },
                h(Icon, { name: 'search', size: 14, className: 'admin-search-icon' }),
                h('input', {
                    className: 'admin-search-input',
                    value: query,
                    placeholder: 'Find a player by name or ID',
                    'aria-label': 'Find online player',
                    onChange: (event) => setQuery(event.target.value),
                    onKeyDown: (event) => event.stopPropagation()
                })
            ),
            h('span', { className: 'admin-workspace-count' }, `${filtered.length} / ${safePlayers.length}`)
        ),
        safePlayers.length === 0
            ? h('div', { className: 'admin-state-panel', role: 'status' },
                h(Icon, { name: 'users', size: 22 }),
                h('strong', null, 'No players online'),
                h('span', null, 'The server player directory is empty.'))
            : h('div', { className: 'admin-player-split' },
                h('div', { className: 'admin-player-directory', role: 'listbox', 'aria-label': 'Online players' },
                    filtered.length === 0
                        ? h('div', { className: 'admin-no-results' }, 'No players match this filter.')
                        : filtered.map((player) => h('button', {
                            type: 'button',
                            role: 'option',
                            key: player.id,
                            className: `admin-player-row${selected && String(selected.id) === String(player.id) ? ' selected' : ''}`,
                            'aria-selected': selected && String(selected.id) === String(player.id),
                            onClick: () => setSelectedId(player.id),
                            onDoubleClick: () => !player.isSelf && allowed['player.goto'] !== false && onAction('goto', player)
                        },
                            h('span', { className: `admin-player-presence${player.dead ? ' dead' : ''}` }),
                            h('span', { className: 'admin-player-row-copy' },
                                h('span', { className: 'admin-player-name' }, player.name || `Player ${player.id}`),
                                h('span', { className: 'admin-player-row-meta' }, `#${player.id} · ${Number(player.ping || 0)} ms · bucket ${Number(player.bucket || 0)}`)
                            ),
                            player.isSelf && h('span', { className: 'admin-player-self' }, 'You'),
                            h(Icon, { name: 'chevron-right', size: 13 })
                        ))
                ),
                h('section', { className: 'admin-player-inspector', 'aria-label': 'Selected player actions' },
                    selected && h(React.Fragment, null,
                        h('div', { className: 'admin-player-inspector-head' },
                            h('div', null,
                                h('span', { className: 'admin-workspace-eyebrow' }, `PLAYER #${selected.id}`),
                                h('h3', null, selected.name || `Player ${selected.id}`)
                            ),
                            h('span', { className: `admin-status-label${selected.dead ? ' danger' : ''}` }, selected.dead ? 'Dead' : 'Online')
                        ),
                        h('div', { className: 'admin-player-action-grid' },
                            PLAYER_WORKSPACE_ACTIONS.map((entry) => {
                                const disabled = selected.isSelf || (allowed && allowed[entry.permission] === false);
                                return h('button', {
                                    type: 'button',
                                    key: entry.id,
                                    className: `admin-player-action${entry.danger ? ' danger' : ''}`,
                                    disabled,
                                    title: disabled && selected.isSelf ? 'Unavailable for your own player' : entry.label,
                                    onClick: () => onAction(entry.id, selected)
                                }, h(Icon, { name: entry.icon, size: 14 }), h('span', null, entry.label));
                            })
                        ),
                        identifiers && String(identifiers.target) === String(selected.id) && h('div', { className: 'admin-identifier-panel' },
                            h('div', { className: 'admin-section-kicker' }, 'Durable identifiers'),
                            Array.isArray(identifiers.identifiers) && identifiers.identifiers.length > 0
                                ? identifiers.identifiers.map((value, index) => h('code', { key: `${value}-${index}`, title: value }, value))
                                : h('span', { className: 'admin-muted-copy' }, 'No durable identifiers were returned.')
                        )
                    )
                )
            )
    );
});

function WorkspaceHeader({ eyebrow, title, description, meta, actions }) {
    return h('header', { className: 'admin-workspace-header' },
        h('div', { className: 'admin-workspace-heading' },
            eyebrow && h('span', { className: 'admin-workspace-eyebrow' }, eyebrow),
            h('div', { className: 'admin-workspace-title-row' },
                h('h2', null, title),
                meta != null && h('span', { className: 'admin-workspace-meta' }, meta)
            ),
            description && h('p', null, description)
        ),
        actions && h('div', { className: 'admin-workspace-header-actions' }, actions)
    );
}

function getMigrationDomainCount(domain) {
    if (!domain || typeof domain !== 'object') return 0;
    return Number(domain.count || domain.total || 0) || 0;
}

function VmenuMigrationWorkspace({ onPrompt, allowed, banImportResult }) {
    const [snapshot, setSnapshot] = useState(null);
    const [phase, setPhase] = useState('loading');
    const [error, setError] = useState('');
    const [result, setResult] = useState(null);

    const refresh = useCallback(async () => {
        setPhase('loading');
        setError('');
        const response = await fetchNui('cortex-admin:getVmenuMigrationSnapshot');
        const payload = response.data;
        if (!response.ok || !payload || payload.error || payload.ok === false) {
            setSnapshot(null);
            setError(payload && (payload.error || payload.reason) ? String(payload.error || payload.reason) : 'Migration status could not be loaded.');
            setPhase('error');
            return;
        }
        setSnapshot(payload);
        setPhase('ready');
    }, []);

    useEffect(() => {
        if (allowed && allowed['migration.read'] === false) {
            setPhase('forbidden');
            return;
        }
        refresh();
    }, [refresh, allowed && allowed['migration.read']]);

    useEffect(() => {
        if (banImportResult && typeof banImportResult === 'object') {
            setResult((previous) => ({ ...(previous || {}), bans: banImportResult }));
        }
    }, [banImportResult]);

    const runImport = useCallback(async () => {
        setPhase('importing');
        setError('');
        const response = await fetchNui('cortex-admin:importVmenuMigrationData');
        const payload = response.data || {};
        const importResult = payload.result || payload;
        if (!response.ok || payload.ok === false) {
            setResult(importResult);
            setError(importResult.message || importResult.reason || payload.error || 'No importable vMenu data was found.');
            setPhase('error');
            return;
        }
        setResult(importResult);
        await refresh();
    }, [refresh]);

    const confirmImport = useCallback(() => {
        const config = {
            title: 'Import all vMenu data?',
            description: 'Cortex will copy recoverable peds, vehicles, weapon loadouts, categories, settings, locations, configuration, and bans. Existing Cortex records are kept when names collide. ACE permissions stay authoritative.',
            fields: [],
            onSubmit: runImport
        };
        if (typeof onPrompt === 'function') onPrompt(config); else runImport();
    }, [onPrompt, runImport]);

    const domains = snapshot ? [
        { id: 'mp-peds', label: 'MP characters', source: snapshot.peds && snapshot.peds.source, count: getMigrationDomainCount(snapshot.peds), imported: Number(snapshot.peds && snapshot.peds.importedCount || 0), ready: snapshot.peds && snapshot.peds.available },
        { id: 'peds', label: 'Saved peds', source: snapshot.nonMpPeds && snapshot.nonMpPeds.source, count: getMigrationDomainCount(snapshot.nonMpPeds), ready: snapshot.nonMpPeds && snapshot.nonMpPeds.available },
        { id: 'vehicles', label: 'Saved vehicles', source: snapshot.vehicles && snapshot.vehicles.source, count: getMigrationDomainCount(snapshot.vehicles), imported: Number(snapshot.vehicles && snapshot.vehicles.importedCount || 0), ready: snapshot.vehicles && snapshot.vehicles.available },
        { id: 'loadouts', label: 'Weapon loadouts', source: snapshot.weaponLoadouts && snapshot.weaponLoadouts.source, count: getMigrationDomainCount(snapshot.weaponLoadouts), imported: Number(snapshot.weaponLoadouts && snapshot.weaponLoadouts.importedCount || 0), ready: snapshot.weaponLoadouts && snapshot.weaponLoadouts.available },
        { id: 'settings', label: 'Personal settings', source: snapshot.fallback && snapshot.fallback.scope, count: getMigrationDomainCount(snapshot.settings), ready: snapshot.settings && snapshot.settings.available },
        { id: 'categories', label: 'Library categories', source: snapshot.fallback && snapshot.fallback.scope, count: Number(snapshot.categories && snapshot.categories.peds || 0) + Number(snapshot.categories && snapshot.categories.vehicles || 0), imported: Number(snapshot.categories && snapshot.categories.importedPeds || 0) + Number(snapshot.categories && snapshot.categories.importedVehicles || 0), ready: snapshot.categories && (snapshot.categories.peds > 0 || snapshot.categories.vehicles > 0) },
    ] : [];
    const configDomains = snapshot && snapshot.config && snapshot.config.domains ? Object.entries(snapshot.config.domains) : [];
    const hasImportableData = domains.some((entry) => entry.ready || entry.count > 0)
        || configDomains.some(([, entry]) => entry && entry.available)
        || Boolean(snapshot && snapshot.vmenuRunning);

    if (phase === 'forbidden') {
        return h('div', { className: 'admin-workspace' },
            h(WorkspaceHeader, { eyebrow: 'COMPATIBILITY', title: 'vMenu import', description: 'Copy recoverable vMenu data into Cortex-owned storage.' }),
            h('div', { className: 'admin-state-panel error', role: 'alert' },
                h(Icon, { name: 'lock-keyhole', size: 22 }),
                h('strong', null, 'Permission required'),
                h('span', null, 'Your ACE role does not grant migration.read.'))
        );
    }

    if (phase === 'loading' && !snapshot) {
        return h('div', { className: 'admin-workspace' },
            h(WorkspaceHeader, { eyebrow: 'COMPATIBILITY', title: 'vMenu import', description: 'Inspecting local and server-owned vMenu data.' }),
            h('div', { className: 'admin-state-panel', role: 'status' }, h(Icon, { name: 'loader-circle', size: 22 }), h('strong', null, 'Scanning recoverable data'), h('span', null, 'Reading the vMenu bridge, host KVP, and imported server configuration.'))
        );
    }

    if (phase === 'error' && !snapshot) {
        return h('div', { className: 'admin-workspace' },
            h(WorkspaceHeader, { eyebrow: 'COMPATIBILITY', title: 'vMenu import', description: 'The migration status could not be loaded.' }),
            h('div', { className: 'admin-state-panel error', role: 'alert' }, h(Icon, { name: 'triangle-alert', size: 22 }), h('strong', null, 'Migration unavailable'), h('span', null, error), h('button', { type: 'button', className: 'admin-button', onClick: refresh }, 'Try again'))
        );
    }

    return h('div', { className: 'admin-workspace admin-migration-workspace' },
        h(WorkspaceHeader, {
            eyebrow: 'COMPATIBILITY',
            title: 'vMenu import',
            description: 'Copy durable vMenu data into Cortex, then remove vMenu without losing personal libraries or server configuration.',
            meta: snapshot && snapshot.vmenuRunning ? 'vMenu live' : 'Offline import',
            actions: h(React.Fragment, null,
                h('button', { type: 'button', className: 'admin-button', onClick: refresh, disabled: phase === 'importing' }, h(Icon, { name: 'refresh-cw', size: 14 }), 'Refresh'),
                h('button', { type: 'button', className: 'admin-button success', onClick: confirmImport, disabled: phase === 'importing' || !hasImportableData || (allowed && allowed['migration.import'] === false), title: allowed && allowed['migration.import'] === false ? 'Your ACE role does not grant migration.import.' : undefined }, h(Icon, { name: 'download', size: 14 }), phase === 'importing' ? 'Importing…' : 'Import everything')
            )
        }),
        h('section', { className: 'admin-workspace-section' },
            h('div', { className: 'admin-workspace-section-head' }, h('div', null, h('span', { className: 'admin-section-kicker' }, 'Personal libraries'), h('h3', null, 'Recoverable client data')), h('span', null, `${domains.reduce((sum, entry) => sum + entry.count, 0)} records detected`)),
            h('div', { className: 'admin-domain-list' }, domains.map((entry) => h('div', { className: 'admin-domain-row', key: entry.id },
                h('span', { className: `admin-domain-status${entry.ready ? ' ready' : ''}` }),
                h('span', { className: 'admin-domain-copy' }, h('strong', null, entry.label), h('small', null, entry.source || 'Not detected')),
                h('span', { className: 'admin-domain-count' }, entry.count),
                h('span', { className: 'admin-domain-imported' }, entry.imported ? `${entry.imported} in Cortex` : 'Not imported')
            )))
        ),
        h('section', { className: 'admin-workspace-section' },
            h('div', { className: 'admin-workspace-section-head' }, h('div', null, h('span', { className: 'admin-section-kicker' }, 'Server configuration'), h('h3', null, 'Cortex-owned copies')), h('span', null, snapshot && snapshot.config && snapshot.config.resource ? snapshot.config.resource : 'No live resource')),
            configDomains.length === 0
                ? h('div', { className: 'admin-inline-empty' }, 'No vMenu configuration domains have been imported yet.')
                : h('div', { className: 'admin-config-domain-grid' }, configDomains.map(([name, entry]) => h('div', { className: 'admin-config-domain', key: name },
                    h('div', null, h('strong', null, name.replace(/([A-Z])/g, ' $1')), h('small', null, entry && entry.sourcePath ? entry.sourcePath : 'Stored in Cortex')),
                    h('span', null, Number(entry && entry.count || 0))
                )))
        ),
        h('div', { className: 'admin-migration-note' },
            h(Icon, { name: 'shield-check', size: 16 }),
            h('div', null, h('strong', null, 'ACE permissions remain live'), h('span', null, snapshot && snapshot.permissions && snapshot.permissions.note ? snapshot.permissions.note : 'Existing vMenu.* grants are treated as Cortex permission aliases; they are not copied into mutable client storage.'))
        ),
        snapshot && snapshot.fallback && snapshot.fallback.localHostOnly && h('div', { className: 'admin-migration-note muted' },
            h(Icon, { name: 'hard-drive', size: 16 }),
            h('div', null, h('strong', null, 'Host-local KVP recovery'), h('span', null, 'This fallback reads the CitizenFX KVP on the FXServer host. Each remote player must import their private vMenu data from their own client or a running bridge.'))
        ),
        result && h('div', { className: `admin-import-result${result.ok === false ? ' error' : ''}`, role: 'status' },
            h('strong', null, result.ok === false ? 'Import finished with no recoverable records' : 'Latest import complete'),
            h('span', null, ['peds', 'nonMpPeds', 'vehicles', 'weaponLoadouts', 'settings', 'locations'].map((key) => `${key}: ${Number(result[key] && result[key].imported || 0)}`).join(' · ')),
            result.bans && h('span', null, `bans: ${Number(result.bans.imported || 0)} imported · ${Number(result.bans.skipped || 0)} skipped`)
        ),
        error && h('div', { className: 'admin-inline-error', role: 'alert' }, error)
    );
}

function formatBanExpiry(value) {
    const timestamp = Number(value || 0);
    if (!timestamp) return 'Permanent';
    const date = new Date(timestamp * 1000);
    return Number.isNaN(date.getTime()) ? 'Unknown expiry' : date.toLocaleString();
}

function BannedPlayersWorkspace({ onPrompt, allowed }) {
    const [query, setQuery] = useState('');
    const [offset, setOffset] = useState(0);
    const [page, setPage] = useState({ records: [], total: 0, hasMore: false, limit: 50 });
    const [phase, setPhase] = useState('loading');
    const [error, setError] = useState('');

    const load = useCallback(async (nextOffset = offset, nextQuery = query) => {
        if (allowed && allowed['player.viewBans'] === false) {
            setPhase('forbidden');
            return;
        }
        setPhase('loading');
        setError('');
        const response = await fetchNui('cortex-admin:getBanList', { query: nextQuery, offset: nextOffset, limit: 50 });
        const payload = response.data || {};
        if (!response.ok || payload.ok === false) {
            setPage({ records: [], total: 0, hasMore: false, limit: 50 });
            setError(payload.error || 'Ban records could not be loaded.');
            setPhase(payload.error === 'forbidden' ? 'forbidden' : 'error');
            return;
        }
        setPage({ records: Array.isArray(payload.records) ? payload.records : [], total: Number(payload.total || 0), hasMore: payload.hasMore === true, limit: Number(payload.limit || 50) });
        setOffset(Number(payload.offset || 0));
        setPhase('ready');
    }, [offset, query, allowed && allowed['player.viewBans']]);

    useEffect(() => {
        const timer = window.setTimeout(() => load(0, query), 180);
        return () => window.clearTimeout(timer);
    }, [query]);

    const unban = useCallback((record) => {
        const execute = async () => {
            const response = await fetchNui('cortex-admin:unban', { id: record.id });
            if (!response.ok || !response.data || response.data.ok !== true) {
                setError(response.data && response.data.error ? response.data.error : 'The ban could not be removed.');
                return;
            }
            load(offset, query);
        };
        const config = { title: `Unban ${record.playerName || record.id}?`, description: `Remove ban ${record.id}. This player can reconnect immediately if no other ban matches their identifiers.`, fields: [], onSubmit: execute };
        if (typeof onPrompt === 'function') onPrompt(config); else execute();
    }, [load, offset, query, onPrompt]);

    if (phase === 'forbidden') {
        return h('div', { className: 'admin-workspace' }, h(WorkspaceHeader, { eyebrow: 'MODERATION', title: 'Banned players', description: 'Review and revoke Cortex and imported vMenu bans.' }), h('div', { className: 'admin-state-panel error', role: 'alert' }, h(Icon, { name: 'lock-keyhole', size: 22 }), h('strong', null, 'Permission required'), h('span', null, 'Your ACE role does not grant player.viewBans.')));
    }

    return h('div', { className: 'admin-workspace admin-ban-workspace' },
        h(WorkspaceHeader, { eyebrow: 'MODERATION', title: 'Banned players', description: 'Stable Cortex ban IDs include native Cortex records and durable records imported from vMenu.', meta: `${page.total} active`, actions: h('button', { type: 'button', className: 'admin-button', onClick: () => load(offset, query) }, h(Icon, { name: 'refresh-cw', size: 14 }), 'Refresh') }),
        h('div', { className: 'admin-workspace-toolbar' },
            h('div', { className: 'admin-search-wrapper' }, h(Icon, { name: 'search', size: 14, className: 'admin-search-icon' }), h('input', { className: 'admin-search-input', value: query, placeholder: 'Search player, reason, admin, or ban ID', 'aria-label': 'Search bans', onChange: (event) => setQuery(event.target.value), onKeyDown: (event) => event.stopPropagation() })),
            h('span', { className: 'admin-workspace-count' }, phase === 'loading' ? 'Loading…' : `${page.records.length} shown`)
        ),
        error && h('div', { className: 'admin-inline-error', role: 'alert' }, error),
        phase === 'loading' && page.records.length === 0
            ? h('div', { className: 'admin-state-panel', role: 'status' }, h(Icon, { name: 'loader-circle', size: 22 }), h('strong', null, 'Loading active bans'))
            : page.records.length === 0
                ? h('div', { className: 'admin-state-panel', role: 'status' }, h(Icon, { name: 'shield-check', size: 22 }), h('strong', null, query ? 'No matching bans' : 'No active bans'), h('span', null, query ? 'Try a different name, reason, admin, or ID.' : 'No Cortex or imported vMenu ban currently blocks a player.'))
                : h('div', { className: 'admin-ban-list' }, page.records.map((record) => h('article', { className: 'admin-ban-row', key: record.id },
                    h('div', { className: 'admin-ban-primary' }, h('strong', null, record.playerName || 'Unknown player'), h('code', null, record.id || 'unknown')),
                    h('div', { className: 'admin-ban-reason' }, record.reason || 'No reason recorded'),
                    h('div', { className: 'admin-ban-meta' }, h('span', null, `By ${record.adminName || 'Unknown'}`), h('span', null, formatBanExpiry(record.expiresAt || record.expires)), record.provenance && h('span', null, record.provenance)),
                    h('button', { type: 'button', className: 'admin-button danger', onClick: () => unban(record) }, h(Icon, { name: 'user-round-check', size: 13 }), 'Unban')
                ))),
        page.total > page.limit && h('div', { className: 'admin-pagination' },
            h('button', { type: 'button', className: 'admin-button', disabled: offset <= 0, onClick: () => load(Math.max(0, offset - page.limit), query) }, 'Previous'),
            h('span', null, `${offset + 1}–${Math.min(page.total, offset + page.records.length)} of ${page.total}`),
            h('button', { type: 'button', className: 'admin-button', disabled: !page.hasMore, onClick: () => load(offset + page.limit, query) }, 'Next')
        )
    );
}

function ImportedDataWorkspace({ allowed }) {
    const [configuration, setConfiguration] = useState(null);
    const [locations, setLocations] = useState([]);
    const [phase, setPhase] = useState('loading');
    const [error, setError] = useState('');

    const load = useCallback(async () => {
        if (allowed && allowed['migration.read'] === false) {
            setPhase('forbidden');
            return;
        }
        setPhase('loading');
        setError('');
        const [configResponse, locationResponse] = await Promise.all([
            fetchNui('cortex-admin:getVmenuImportedConfiguration'),
            fetchNui('cortex-admin:getSavedTeleportLocations')
        ]);
        const configPayload = configResponse.data || {};
        if (!configResponse.ok || configPayload.ok === false) {
            setError(configPayload.error || 'Imported configuration could not be loaded.');
            setPhase(configPayload.error === 'forbidden' ? 'forbidden' : 'error');
            return;
        }
        setConfiguration(configPayload);
        setLocations(Array.isArray(locationResponse.data) ? locationResponse.data : []);
        setPhase('ready');
    }, [allowed && allowed['migration.read']]);
    useEffect(() => { load(); }, [load]);

    const domainRows = useMemo(() => {
        const domains = configuration && configuration.domains ? configuration.domains : {};
        const rows = [];
        const push = (domain, label, data) => rows.push({ domain, label, count: Number(data && data.count || 0), sample: data && Array.isArray(data.sample) ? data.sample : [] });
        const addons = domains.addons || {};
        push('addons', 'Addon vehicles', addons.vehicles);
        push('addons', 'Addon peds', addons.peds);
        push('addons', 'Addon weapons', addons.weapons);
        push('extras', 'Vehicle extra maps', domains.extras);
        const configLocations = domains.locations || {};
        push('locations', 'Configured teleports', configLocations.teleports);
        push('locations', 'Configured blips', configLocations.blips);
        const whitelists = domains.modelWhitelists || {};
        push('whitelists', 'Whitelisted vehicles', whitelists.vehicles);
        push('whitelists', 'Whitelisted peds', whitelists.peds);
        push('whitelists', 'Whitelisted weapons', whitelists.weapons);
        push('tattoos', 'Tattoo definitions', domains.tattoos);
        const categories = configuration && configuration.categories ? configuration.categories : {};
        push('categories', 'Ped categories', categories.peds);
        push('categories', 'Vehicle categories', categories.vehicles);
        return rows;
    }, [configuration]);

    if (phase === 'forbidden') return h('div', { className: 'admin-workspace' }, h(WorkspaceHeader, { eyebrow: 'ARCHIVE', title: 'Imported data', description: 'Review Cortex-owned copies of vMenu configuration and locations.' }), h('div', { className: 'admin-state-panel error' }, h(Icon, { name: 'lock-keyhole', size: 22 }), h('strong', null, 'Permission required'), h('span', null, 'Your ACE role does not grant migration.read.')));

    return h('div', { className: 'admin-workspace admin-imported-workspace' },
        h(WorkspaceHeader, { eyebrow: 'ARCHIVE', title: 'Imported data', description: 'These records are owned by Cortex and remain available after vMenu is stopped or removed.', meta: phase === 'loading' ? 'Loading' : `${domainRows.reduce((sum, row) => sum + row.count, 0)} config records`, actions: h('button', { type: 'button', className: 'admin-button', onClick: load }, h(Icon, { name: 'refresh-cw', size: 14 }), 'Refresh') }),
        error && h('div', { className: 'admin-inline-error', role: 'alert' }, error),
        h('section', { className: 'admin-workspace-section' },
            h('div', { className: 'admin-workspace-section-head' }, h('div', null, h('span', { className: 'admin-section-kicker' }, 'Configuration'), h('h3', null, 'Imported vMenu domains')), h('span', null, `${domainRows.filter((row) => row.count > 0).length} populated`)),
            phase === 'loading' && !configuration
                ? h('div', { className: 'admin-inline-empty' }, 'Loading imported configuration…')
                : h('div', { className: 'admin-imported-domain-list' }, domainRows.map((row) => h('div', { className: 'admin-imported-domain-row', key: `${row.domain}-${row.label}` },
                    h('div', { className: 'admin-imported-domain-copy' }, h('span', { className: 'admin-imported-domain-group' }, row.domain), h('strong', null, row.label), row.sample.length > 0 && h('small', { title: row.sample.join(', ') }, row.sample.join(' · '))),
                    h('span', { className: 'admin-domain-count' }, row.count)
                )))
        ),
        h('section', { className: 'admin-workspace-section' },
            h('div', { className: 'admin-workspace-section-head' }, h('div', null, h('span', { className: 'admin-section-kicker' }, 'Locations'), h('h3', null, 'Cortex teleport library')), h('span', null, `${locations.length} saved`)),
            locations.length === 0
                ? h('div', { className: 'admin-inline-empty' }, 'No vMenu locations have been copied into the Cortex teleport library.')
                : h('div', { className: 'admin-imported-location-list' }, locations.slice(0, 200).map((entry) => h('div', { className: 'admin-imported-location-row', key: entry.name },
                    h('div', null, h('strong', null, entry.name), h('small', null, `${Number(entry.x || 0).toFixed(1)}, ${Number(entry.y || 0).toFixed(1)}, ${Number(entry.z || 0).toFixed(1)}`)),
                    h('button', { type: 'button', className: 'admin-button', onClick: () => fetchNui('cortex-admin:loadSavedTeleportLocation', { name: entry.name }) }, h(Icon, { name: 'navigation', size: 13 }), 'Go')
                )))
        )
    );
}

const ResourceManager = React.memo(function ResourceManager({ resources, onAction, onRefresh }) {
    const [filter, setFilter] = useState('');

    const resourceList = resources || [];
    const stats = useMemo(() => {
        return {
            total: resourceList.length,
            started: resourceList.filter(r => r.state === 'started').length,
            stopped: resourceList.filter(r => r.state === 'stopped' || r.state === 'uninitialized').length
        };
    }, [resourceList]);

    const filtered = resourceList.filter(res =>
        res.name.toLowerCase().includes(filter.toLowerCase()) ||
        res.description.toLowerCase().includes(filter.toLowerCase())
    );

    return React.createElement('div', { className: 'admin-resource-manager' },
        React.createElement('div', { className: 'admin-resource-stats' },
            React.createElement('span', { className: 'admin-resource-stat stat-total' },
                React.createElement('strong', null, stats.total),
                ' Total'
            ),
            React.createElement('span', { className: 'admin-resource-stat-sep' }, '·'),
            React.createElement('span', { className: 'admin-resource-stat stat-started' },
                React.createElement('strong', null, stats.started),
                ' Started'
            ),
            React.createElement('span', { className: 'admin-resource-stat-sep' }, '·'),
            React.createElement('span', { className: 'admin-resource-stat stat-stopped' },
                React.createElement('strong', null, stats.stopped),
                ' Stopped'
            )
        ),
        React.createElement('div', { className: 'admin-resource-toolbar' },
            React.createElement('div', { className: 'admin-search-wrapper' },
                React.createElement(Icon, { name: 'search', size: 16, className: 'admin-search-icon' }),
                React.createElement('input', {
                    type: 'text',
                    className: 'admin-search-input admin-resource-search-input',
                    value: filter,
                    placeholder: 'Search resources...',
                    onKeyDown: (e) => {
                        e.stopPropagation();
                        if (e.key === 'Escape') {
                            e.target.blur();
                            setFilter('');
                        }
                    },
                    onChange: (e) => setFilter(e.target.value)
                }),
                filter.length > 0 && React.createElement('button', {
                    type: 'button',
                    className: 'admin-search-clear',
                    title: 'Clear filter',
                    'aria-label': 'Clear filter',
                    onClick: () => setFilter('')
                }, React.createElement(Icon, { name: 'x', size: 12 }))
            ),
            React.createElement('button', {
                type: 'button',
                className: 'admin-button admin-resource-refresh',
                title: 'Refresh',
                onClick: onRefresh
            }, React.createElement(Icon, { name: 'refresh-cw', size: 15 }))
        ),
        React.createElement('div', { className: 'admin-actions admin-resource-list' },
            filtered.length === 0 ?
                React.createElement('div', { className: 'admin-no-results' }, 'No resources found matching your search.') :
                filtered.map((res) => React.createElement('div', {
                    className: `admin-action admin-resource-item state-${res.state}`,
                    key: res.name
                },
                    React.createElement('div', { className: 'admin-action-row' },
                        React.createElement('div', { className: 'admin-action-left' },
                            React.createElement('div', { className: 'admin-action-info' },
                                React.createElement('div', { className: 'admin-resource-title-row' },
                                    React.createElement('span', { className: `admin-resource-badge ${res.state}` }, res.state),
                                    React.createElement('span', { className: 'admin-action-label' }, res.name)
                                ),
                                res.description && res.description !== 'No description' &&
                                    React.createElement('div', { className: 'admin-action-description admin-resource-desc' }, res.description),
                                React.createElement('div', { className: 'admin-resource-meta' },
                                    React.createElement('span', { title: 'Version' },
                                        React.createElement(Icon, { name: 'plug', size: 11 }),
                                        res.version
                                    ),
                                    React.createElement('span', { title: 'Author' },
                                        React.createElement(Icon, { name: 'user', size: 11 }),
                                        res.author
                                    )
                                )
                            )
                        ),
                        React.createElement('div', { className: 'admin-action-controls' },
                            res.state === 'uninitialized' || res.state === 'stopped' ?
                                React.createElement('button', {
                                    type: 'button',
                                    className: 'admin-button success admin-resource-control-btn',
                                    title: 'Start',
                                    onClick: () => onAction('start', res.name)
                                }, React.createElement(Icon, { name: 'play', size: 13 })) :
                                React.createElement('button', {
                                    type: 'button',
                                    className: 'admin-button danger admin-resource-control-btn',
                                    title: 'Stop',
                                    onClick: () => onAction('stop', res.name)
                                }, React.createElement(Icon, { name: 'square', size: 13 })),
                            React.createElement('button', {
                                type: 'button',
                                className: 'admin-button admin-resource-control-btn',
                                title: 'Restart',
                                onClick: () => onAction('restart', res.name)
                            }, React.createElement(Icon, { name: 'rotate-ccw', size: 13 }))
                        )
                    )
                ))
        )
    );
});

function WardrobeValueStepper({ value, min, max, onCommit, disabled }) {
    const [draft, setDraft] = useState(String(value));
    useEffect(() => {
        setDraft(String(value));
    }, [value]);
    const apply = () => {
        const parsed = parseInt(draft, 10);
        let next = Number.isFinite(parsed) ? parsed : value;
        if (next < min) next = min;
        if (next > max) next = max;
        onCommit(next);
        setDraft(String(next));
    };
    const onChangeDraft = (e) => {
        const v = e.target.value;
        if (v === '' || v === '-') {
            setDraft(v);
            return;
        }
        if (/^-?\d*$/.test(v)) setDraft(v);
    };
    return React.createElement('div', { className: 'appearance-stepper-group' },
        React.createElement('button', {
            type: 'button',
            className: 'appearance-stepper-btn',
            disabled,
            onClick: () => onCommit(Math.max(min, value - 1))
        }, React.createElement(Icon, { name: 'chevron-left', size: 14 })),
        React.createElement('div', { className: 'appearance-stepper-input-wrap' },
            React.createElement('input', {
                type: 'text',
                className: 'appearance-stepper-input',
                value: draft,
                disabled,
                onChange: onChangeDraft,
                onKeyDown: (e) => {
                    e.stopPropagation();
                    if (e.key === 'Enter') e.target.blur();
                },
                onBlur: apply
            }),
            React.createElement('span', { className: 'appearance-stepper-max' }, `/ ${max}`)
        ),
        React.createElement('button', {
            type: 'button',
            className: 'appearance-stepper-btn',
            disabled,
            onClick: () => onCommit(Math.min(max, value + 1))
        }, React.createElement(Icon, { name: 'chevron-right', size: 14 }))
    );
}

function WardrobeDualStepper({
    drawable,
    texture,
    minDrawable,
    maxDrawable,
    maxTexture,
    onDrawable,
    onTexture,
    disabled,
    drawableLabel = 'Drawable',
    textureLabel = 'Texture'
}) {
    return React.createElement('div', { className: 'appearance-stepper-row appearance-stepper-row--wardrobe' },
        React.createElement('div', { className: 'appearance-stepper-unit' },
            React.createElement('span', { className: 'appearance-stepper-unit-label' }, drawableLabel),
            React.createElement(WardrobeValueStepper, {
                value: drawable,
                min: minDrawable,
                max: maxDrawable,
                onCommit: onDrawable,
                disabled
            })
        ),
        React.createElement('div', { className: 'appearance-stepper-sep' }),
        React.createElement('div', { className: 'appearance-stepper-unit' },
            React.createElement('span', { className: 'appearance-stepper-unit-label' }, textureLabel),
            React.createElement(WardrobeValueStepper, {
                value: texture,
                min: 0,
                max: maxTexture,
                onCommit: onTexture,
                disabled
            })
        )
    );
}

const VehicleConfig = {
    mods: [
        // Exterior
        { id: 0, label: 'Spoilers', cat: 'Exterior' },
        { id: 1, label: 'Front Bumper', cat: 'Exterior' },
        { id: 2, label: 'Rear Bumper', cat: 'Exterior' },
        { id: 3, label: 'Side Skirt', cat: 'Exterior' },
        { id: 4, label: 'Exhaust', cat: 'Exterior' },
        { id: 5, label: 'Frame', cat: 'Exterior' },
        { id: 6, label: 'Grille', cat: 'Exterior' },
        { id: 7, label: 'Hood', cat: 'Exterior' },
        { id: 8, label: 'Fender', cat: 'Exterior' },
        { id: 9, label: 'Right Fender', cat: 'Exterior' },
        { id: 10, label: 'Roof', cat: 'Exterior' },
        { id: 25, label: 'Plate Holders', cat: 'Exterior' },
        { id: 26, label: 'Vanity Plates', cat: 'Exterior' },
        { id: 38, label: 'Hydraulics', cat: 'Exterior' },
        { id: 42, label: 'Arch Cover', cat: 'Exterior' },
        { id: 43, label: 'Aerials', cat: 'Exterior' },
        { id: 45, label: 'Tank', cat: 'Exterior' },
        { id: 48, label: 'Livery', cat: 'Exterior' },
        
        // Performance
        { id: 11, label: 'Engine', cat: 'Performance' },
        { id: 12, label: 'Brakes', cat: 'Performance' },
        { id: 13, label: 'Transmission', cat: 'Performance' },
        { id: 15, label: 'Suspension', cat: 'Performance' },
        { id: 16, label: 'Armor', cat: 'Performance' },
        { id: 18, label: 'Turbo', isToggle: true, cat: 'Performance' },
        
        // Interior
        { id: 27, label: 'Trim Design', cat: 'Interior' },
        { id: 28, label: 'Ornaments', cat: 'Interior' },
        { id: 29, label: 'Dashboard design', cat: 'Interior' },
        { id: 30, label: 'Dial Design', cat: 'Interior' },
        { id: 31, label: 'Door Speaker', cat: 'Interior' },
        { id: 32, label: 'Seats', cat: 'Interior' },
        { id: 33, label: 'Steering Wheel', cat: 'Interior' },
        { id: 34, label: 'Shifter Leavers', cat: 'Interior' },
        { id: 35, label: 'Plaques', cat: 'Interior' },
        { id: 36, label: 'Speakers', cat: 'Interior' },
        { id: 37, label: 'Trunk', cat: 'Interior' },
        { id: 44, label: 'Trim', cat: 'Interior' },
        
        // Engine Bay
        { id: 39, label: 'Engine Block', cat: 'Engine' },
        { id: 40, label: 'Air Filter', cat: 'Engine' },
        { id: 41, label: 'Strut Bar', cat: 'Engine' },
        
        // Lighting & Misc
        { id: 14, label: 'Horns', cat: 'Misc' },
        { id: 20, label: 'Tire Smoke', isToggle: true, cat: 'Misc' },
        { id: 22, label: 'Xenon Lights', isToggle: true, cat: 'Misc' },
        { id: 46, label: 'Windows', cat: 'Misc' },
        { id: 23, label: 'Front Wheels', cat: 'Wheels' },
        { id: 24, label: 'Back Wheels', cat: 'Wheels' },
    ],
    colors: [
        { id: 'primary', label: 'Primary Color' },
        { id: 'secondary', label: 'Secondary Color' },
        { id: 'pearlescent', label: 'Pearlescent' },
        { id: 'wheel', label: 'Wheel Color' },
        { id: 'dashboard', label: 'Dashboard Color' },
        { id: 'trim', label: 'Interior Color' },
    ],
    plates: [
        { label: 'Blue on White 1', value: 0 },
        { label: 'Blue on White 2', value: 1 },
        { label: 'Blue on White 3', value: 2 },
        { label: 'Yellow on Blue', value: 3 },
        { label: 'Yellow on Black', value: 4 },
        { label: 'North Yankton', value: 5 },
        { label: 'E-Cola', value: 6 },
        { label: 'Las Venturas', value: 7 },
        { label: 'Liberty City', value: 8 },
        { label: 'LS Car Meet', value: 9 },
        { label: 'LSPD', value: 10 },
        { label: 'Pounders', value: 11 },
        { label: 'Sprunk', value: 12 },
    ],
    windows: [
        { label: 'None', value: 0 },
        { label: 'Pure Black', value: 1 },
        { label: 'Dark Smoke', value: 2 },
        { label: 'Light Smoke', value: 3 },
        { label: 'Stock', value: 4 },
        { label: 'Limo', value: 5 },
        { label: 'Green', value: 6 },
    ],
    wheelTypes: [
        { label: 'Sport', value: 0 },
        { label: 'Muscle', value: 1 },
        { label: 'Lowrider', value: 2 },
        { label: 'SUV', value: 3 },
        { label: 'Offroad', value: 4 },
        { label: 'Tuner', value: 5 },
        { label: 'Bike Wheels', value: 6 },
        { label: 'High End', value: 7 },
        { label: 'Benny\'s Original', value: 8 },
        { label: 'Benny\'s Bespoke', value: 9 },
        { label: 'Open Wheel', value: 10 },
        { label: 'Street', value: 11 },
        { label: 'Track', value: 12 },
    ],
    xenonColors: [
        { label: 'Default', value: 255 },
        { label: 'White', value: 0 },
        { label: 'Blue', value: 1 },
        { label: 'Electric Blue', value: 2 },
        { label: 'Mint Green', value: 3 },
        { label: 'Lime Green', value: 4 },
        { label: 'Yellow', value: 5 },
        { label: 'Golden Shower', value: 6 },
        { label: 'Orange', value: 7 },
        { label: 'Red', value: 8 },
        { label: 'Pony Pink', value: 9 },
        { label: 'Hot Pink', value: 10 },
        { label: 'Purple', value: 11 },
        { label: 'Blacklight', value: 12 },
    ],
    paintFinishes: [
        { label: 'Normal', value: 0 },
        { label: 'Metallic', value: 1 },
        { label: 'Pearlescent', value: 2 },
        { label: 'Matte', value: 3 },
        { label: 'Metal', value: 4 },
        { label: 'Chrome', value: 5 },
    ],
    chameleonColors: [
        'Monochrome', 'Night & Day', 'The Verlierer', 'Sprunk Extreme',
        'Vice City', 'Synthwave Nights', 'Four Seasons', 'Maisonette 9 Throwback',
        'Bubblegum', 'Full Rainbow', 'Sunset', 'The Seven', 'Kamen Rider',
        'Chromatic Aberration', "It's Christmas!", 'Temperature'
    ].map((label, index) => ({ label, value: 223 + index }))
};

const AppearanceConfig = {
    components: [
        { id: 0, label: 'Face' },
        { id: 1, label: 'Mask' },
        { id: 2, label: 'Hair' },
        { id: 3, label: 'Arms / Upper' },
        { id: 4, label: 'Legs / Pants' },
        { id: 5, label: 'Bags' },
        { id: 6, label: 'Shoes' },
        { id: 7, label: 'Accessories' },
        { id: 8, label: 'Undershirt' },
        { id: 9, label: 'Kevlar / Vest' },
        { id: 10, label: 'Decals / Badges' },
        { id: 11, label: 'Torso 2 / Jacket' }
    ],
    props: [
        { id: 0, label: 'Hats' },
        { id: 1, label: 'Glasses' },
        { id: 2, label: 'Ears' },
        { id: 6, label: 'Watches' },
        { id: 7, label: 'Braces' }
    ],
    features: [
        { id: 0, label: 'Nose Width' },
        { id: 1, label: 'Nose Peak Height' },
        { id: 2, label: 'Nose Peak Length' },
        { id: 3, label: 'Nose Bone Height' },
        { id: 4, label: 'Nose Peak Lowering' },
        { id: 5, label: 'Nose Bone Twist' },
        { id: 6, label: 'Eyebrow Height' },
        { id: 7, label: 'Eyebrow Forward' },
        { id: 8, label: 'Cheekbone Height' },
        { id: 9, label: 'Cheekbone Width' },
        { id: 10, label: 'Cheek Width' },
        { id: 11, label: 'Eyes Opening' },
        { id: 12, label: 'Lips Thickness' },
        { id: 13, label: 'Jaw Bone Width' },
        { id: 14, label: 'Jaw Bone Back Length' },
        { id: 15, label: 'Chin Bone Lowering' },
        { id: 16, label: 'Chin Bone Length' },
        { id: 17, label: 'Chin Bone Width' },
        { id: 18, label: 'Chin Hole' },
        { id: 19, label: 'Neck Thickness' }
    ],
    colors: [
        { id: 'hair', label: 'Hair Color', type: 'hair' },
        { id: 'hairHighlight', label: 'Hair Highlight', type: 'hairHighlight' },
        { id: 'eyes', label: 'Eye Color', type: 'eyes' },
        { id: 'eyebrows', label: 'Eyebrow Color', type: 'overlay', overlayId: 2 },
        { id: 'beard', label: 'Beard Color', type: 'overlay', overlayId: 1 },
        { id: 'makeup', label: 'Makeup Color', type: 'overlay', overlayId: 4 },
        { id: 'lipstick', label: 'Lipstick Color', type: 'overlay', overlayId: 8 }
    ],
    heritage: [
        { field: 'shapeFirstID', label: 'Mother Face', min: 0, max: 45, step: 1 },
        { field: 'shapeSecondID', label: 'Father Face', min: 0, max: 45, step: 1 },
        { field: 'skinFirstID', label: 'Mother Skin', min: 0, max: 45, step: 1 },
        { field: 'skinSecondID', label: 'Father Skin', min: 0, max: 45, step: 1 },
        { field: 'shapeMix', label: 'Face Mix', min: 0, max: 1, step: 0.05 },
        { field: 'skinMix', label: 'Skin Mix', min: 0, max: 1, step: 0.05 }
    ],
    overlays: [
        { id: 0, label: 'Blemishes', hasColor: false },
        { id: 1, label: 'Beard', hasColor: true },
        { id: 2, label: 'Eyebrows', hasColor: true },
        { id: 3, label: 'Ageing', hasColor: false },
        { id: 4, label: 'Makeup', hasColor: true },
        { id: 5, label: 'Blush', hasColor: true, hasSecondColor: true },
        { id: 6, label: 'Complexion', hasColor: false },
        { id: 7, label: 'Sun Damage', hasColor: false },
        { id: 8, label: 'Lipstick', hasColor: true, hasSecondColor: true },
        { id: 9, label: 'Moles / Freckles', hasColor: false },
        { id: 10, label: 'Chest Hair', hasColor: true },
        { id: 11, label: 'Body Blemishes', hasColor: false }
    ]
};

function LegacyAppearanceView({ onPrompt }) {
    const [data, setData] = useState(null);
    const [savedPeds, setSavedPeds] = useState([]);
    const [saveName, setSaveName] = useState('');
    const [activeSubTab, setActiveSubTab] = useState('clothing');

    const refreshData = useCallback(() => {
        fetchNui('cortex-admin:getAppearance').then(res => res.json()).then((payload) => setData(normalizeAppearancePayload(payload)));
        fetchNui('cortex-admin:getSavedPeds').then(res => res.json()).then((payload) => setSavedPeds(normalizeSavedOutfitList(payload)));
    }, []);

    useEffect(() => {
        refreshData();
    }, [refreshData]);

    if (!data) return React.createElement('div', { className: 'admin-no-results' }, 'Loading appearance data...');

    const handleUpdate = (type, id, drawable, texture) => {
        fetchNui('cortex-admin:setAppearance', { type, id, drawable, texture });
        setData(prev => {
            const next = { ...prev };
            const key = type === 'component' ? 'components' : 'props';
            next[key] = { ...prev[key], [id]: { drawable, texture } };
            return next;
        });
    };

    const handleFeatureUpdate = (id, value) => {
        // We'll need a new NUI callback for face features if not handled by setAppearance
        fetchNui('cortex-admin:action', { id: 'player.setFaceFeature', data: { id, value } });
        setData(prev => ({
            ...prev,
            features: { ...prev.features, [id]: value }
        }));
    };

    const handleSave = () => {
        if (!saveName.trim()) return;
        fetchNui('cortex-admin:action', { id: 'player.saveMpPed', data: { name: saveName.trim() } });
        setSaveName('');
        setTimeout(refreshData, 500);
    };

    const handleImport = () => {
        const onConfirm = () => {
            fetchNui('cortex-admin:importVmenuSavedPeds').then(() => setTimeout(refreshData, 500));
        };

        if (!onPrompt) {
            if (window.confirm('Copy all saved vMenu MP outfits into cortex-admin local storage? Existing cortex-admin outfits with the same name will be kept.')) {
                onConfirm();
            }
            return;
        }

        onPrompt({
            title: 'Import from vMenu?',
            description: 'This copies all saved vMenu MP outfits into cortex-admin local storage so they keep working without vMenu running. Existing cortex-admin outfits with the same name are kept.',
            fields: [],
            onSubmit: onConfirm
        });
    };

    const handleLoad = (ped) => {
        fetchNui('cortex-admin:action', { id: 'player.loadMpPed', data: { entry: ped } });
        setTimeout(refreshData, 800);
    };

    const handleDelete = (ped) => {
        fetchNui('cortex-admin:deleteSavedPed', { entry: ped });
        setTimeout(refreshData, 500);
    };

    const handleRename = (ped) => {
        if (!onPrompt) return;
        onPrompt({
            title: `Rename Outfit: ${ped.name}`,
            description: ped.source === 'vmenu' ? 'This renames the vMenu save directly.' : 'Enter a new name for this outfit.',
            fields: [{ name: 'name', label: 'New Name', placeholder: 'Outfit name', initialValue: ped.name }],
            onSubmit: (values) => {
                const newName = values && values.name ? values.name.trim() : '';
                if (!newName) return;
                fetchNui('cortex-admin:renameSavedPed', { entry: ped, newName });
                setTimeout(refreshData, 500);
            }
        });
    };

    const handleClone = (ped) => {
        if (!onPrompt) return;
        onPrompt({
            title: `Clone Outfit: ${ped.name}`,
            description: ped.source === 'vmenu' ? 'This creates a new vMenu save cloned from the selected outfit.' : 'Enter a name for the cloned outfit.',
            fields: [{ name: 'name', label: 'Clone Name', placeholder: 'Outfit name', initialValue: `${ped.name}_clone` }],
            onSubmit: (values) => {
                const newName = values && values.name ? values.name.trim() : '';
                if (!newName) return;
                fetchNui('cortex-admin:cloneSavedPed', { entry: ped, newName });
                setTimeout(refreshData, 500);
            }
        });
    };

    const handleOverwrite = (ped) => {
        if (!onPrompt) return;
        onPrompt({
            title: `Overwrite Outfit: ${ped.name}?`,
            description: ped.source === 'vmenu'
                ? 'This will replace the existing vMenu outfit with your current appearance.'
                : 'This will save your current appearance over this outfit.',
            fields: [],
            onSubmit: () => {
                fetchNui('cortex-admin:action', { id: 'player.saveMpPed', data: { name: ped.name, entry: ped } });
                setTimeout(refreshData, 500);
            }
        });
    };

    const ClickableValue = ({ value, max, min, onConfirm, disabled = false }) => {
        const [editing, setEditing] = useState(false);
        const [inputValue, setInputValue] = useState(value.toString());

        if (disabled) {
            return React.createElement('span', { className: 'appearance-value' }, `${value}/${max}`);
        }

        const handleConfirm = () => {
            const num = parseInt(inputValue);
            if (!isNaN(num)) {
                onConfirm(Math.max(min, Math.min(max, num)));
            }
            setEditing(false);
        };

        if (editing) {
            return React.createElement('input', {
                className: 'appearance-value-input',
                value: inputValue,
                autoFocus: true,
                onChange: (e) => setInputValue(e.target.value),
                onKeyDown: (e) => { e.stopPropagation(); if (e.key === 'Enter') handleConfirm(); if (e.key === 'Escape') setEditing(false); },
                onBlur: handleConfirm
            });
        }

        return React.createElement('span', { className: 'appearance-value clickable', onClick: () => setEditing(true) }, `${value}/${max}`);
    };

    const renderSlider = (item, type) => {
        const isComponent = type === 'component';
        const current = isComponent ? data.components[item.id] : data.props[item.id];
        const max = isComponent ? data.maxComponents[item.id] : data.maxProps[item.id];

        if (!current || !max) return null;

        const drawableCount = Number(max.drawables);
        const textureCount = Number(max.textures);
        if (!Number.isFinite(drawableCount) || !Number.isFinite(textureCount)) return null;

        const minDrawable = isComponent ? 0 : -1;
        const maxDrawables = Math.max(minDrawable, drawableCount - 1);
        const maxTextures = Math.max(0, textureCount - 1);

        return React.createElement('div', { className: 'appearance-row appearance-row--wardrobe', key: `${type}-${item.id}` },
            React.createElement('div', { className: 'appearance-label' }, item.label),
            React.createElement(WardrobeDualStepper, {
                drawable: current.drawable,
                texture: current.texture,
                minDrawable,
                maxDrawable: maxDrawables,
                maxTexture: maxTextures,
                disabled: false,
                onDrawable: (v) => handleUpdate(type, item.id, v, 0),
                onTexture: (v) => handleUpdate(type, item.id, current.drawable, v)
            })
        );
    };

    const renderFeatureSlider = (item) => {
        const value = (data.features && data.features[item.id]) || 0;
        return React.createElement('div', { className: 'appearance-row feature', key: `feature-${item.id}` },
            React.createElement('div', { className: 'appearance-label' }, item.label),
            React.createElement('div', { className: 'appearance-control wide' },
                React.createElement('span', { className: 'appearance-value' }, value.toFixed(2)),
                React.createElement('input', { type: 'range', className: 'appearance-slider', min: -1, max: 1, step: 0.05, value: value, 'aria-label': item.label, onChange: (e) => handleFeatureUpdate(item.id, parseFloat(e.target.value)) }),
                React.createElement('div', { className: 'appearance-btns' },
                    React.createElement('button', { className: 'appearance-btn', onClick: () => handleFeatureUpdate(item.id, Math.max(-1, value - 0.05)) }, '−'),
                    React.createElement('button', { className: 'appearance-btn', onClick: () => handleFeatureUpdate(item.id, Math.min(1, value + 0.05)) }, '+')
                )
            )
        );
    };

    const subTabs = [
        { id: 'general', label: 'General', icon: 'fa-user' },
        { id: 'clothing', label: 'Clothing', icon: 'fa-shirt' },
        { id: 'props', label: 'Props', icon: 'fa-hat-cowboy' },
        { id: 'face', label: 'Face Features', icon: 'fa-face-smile' },
        { id: 'colors', label: 'Colors', icon: 'fa-palette' },
        { id: 'outfits', label: 'Saved Outfits', icon: 'fa-box' }
    ];

    const legacySubtabLucide = { general: 'user', clothing: 'shirt', props: 'glasses', face: 'smile', colors: 'palette', outfits: 'archive' };

    return React.createElement('div', { className: 'admin-appearance' },
        React.createElement('div', { className: 'admin-tabs subtabs' },
            subTabs.map(tab => React.createElement('button', {
                key: tab.id,
                type: 'button',
                className: `admin-tab${activeSubTab === tab.id ? ' active' : ''}`,
                onClick: () => setActiveSubTab(tab.id)
            }, React.createElement(Icon, { name: legacySubtabLucide[tab.id] || 'circle', size: 14 }), tab.label))
        ),

        // Content Scroll Area
        React.createElement('div', { className: 'appearance-content-area' },
            activeSubTab === 'general' && React.createElement('div', { className: 'admin-section' },
                React.createElement('div', { className: 'admin-section-title' }, 'Quick Actions'),
                React.createElement('div', { className: 'appearance-quick-actions' },
                    React.createElement('button', { className: 'admin-button', onClick: () => fetchNui('cortex-admin:action', { id: 'player.setModel', data: { model: 'mp_m_freemode_01' } }).then(() => setTimeout(refreshData, 1000)) }, 'Male MP'),
                    React.createElement('button', { className: 'admin-button', onClick: () => fetchNui('cortex-admin:action', { id: 'player.setModel', data: { model: 'mp_f_freemode_01' } }).then(() => setTimeout(refreshData, 1000)) }, 'Female MP'),
                    React.createElement('button', { type: 'button', className: 'admin-button', onClick: refreshData }, React.createElement(Icon, { name: 'refresh-cw', size: 14 }))
                )
            ),

            activeSubTab === 'clothing' && React.createElement('div', { className: 'admin-section' },
                React.createElement('div', { className: 'appearance-header appearance-header--legacy-wardrobe' },
                    React.createElement('span', null, 'Component'),
                    React.createElement('div', { className: 'appearance-legacy-wardrobe-h-cols' },
                        React.createElement('span', null, 'Drawable'),
                        React.createElement('span', null, 'Texture')
                    )
                ),
                AppearanceConfig.components.map(c => renderSlider(c, 'component'))
            ),

            activeSubTab === 'props' && React.createElement('div', { className: 'admin-section' },
                React.createElement('div', { className: 'appearance-header appearance-header--legacy-wardrobe' },
                    React.createElement('span', null, 'Prop'),
                    React.createElement('div', { className: 'appearance-legacy-wardrobe-h-cols' },
                        React.createElement('span', null, 'Index'),
                        React.createElement('span', null, 'Texture')
                    )
                ),
                AppearanceConfig.props.map(p => renderSlider(p, 'prop'))
            ),

            activeSubTab === 'face' && React.createElement('div', { className: 'admin-section' },
                AppearanceConfig.features.map(f => renderFeatureSlider(f))
            ),

            activeSubTab === 'colors' && React.createElement('div', { className: 'admin-section' },
                AppearanceConfig.colors.map(c => React.createElement('div', { className: 'appearance-row', key: c.id },
                    React.createElement('div', { className: 'appearance-label' }, c.label),
                    React.createElement('div', { className: 'appearance-control wide' },
                        React.createElement(ClickableValue, {
                            value: c.type === 'hair' ? (data.hairColor || 0) :
                                c.type === 'hairHighlight' ? (data.hairHighlightColor || 0) :
                                    c.type === 'eyes' ? (data.eyeColor || 0) :
                                        (data.overlays && data.overlays[c.overlayId] ? data.overlays[c.overlayId].color : 0),
                            max: 63,
                            min: 0,
                            onConfirm: (v) => {
                                fetchNui('cortex-admin:setAppearance', { type: 'color', colorType: c.type, id: c.overlayId, value: v });
                                setData(prev => ({ ...prev, [c.type === 'hair' ? 'hairColor' : c.type === 'hairHighlight' ? 'hairHighlightColor' : c.type === 'eyes' ? 'eyeColor' : 'overlayColor']: v }));
                            }
                        }),
                        React.createElement('input', {
                            type: 'range',
                            className: 'appearance-slider',
                            'aria-label': c.label,
                            min: 0,
                            max: 63,
                            value: c.type === 'hair' ? (data.hairColor || 0) :
                                c.type === 'hairHighlight' ? (data.hairHighlightColor || 0) :
                                    c.type === 'eyes' ? (data.eyeColor || 0) :
                                        (data.overlays && data.overlays[c.overlayId] ? data.overlays[c.overlayId].color : 0),
                            onChange: (e) => {
                                const v = parseInt(e.target.value);
                                fetchNui('cortex-admin:setAppearance', { type: 'color', colorType: c.type, id: c.overlayId, value: v });
                                setData(prev => ({ ...prev, [c.type === 'hair' ? 'hairColor' : c.type === 'hairHighlight' ? 'hairHighlightColor' : c.type === 'eyes' ? 'eyeColor' : 'overlayColor']: v }));
                            }
                        })
                    )
                ))
            ),

            activeSubTab === 'outfits' && React.createElement('div', { className: 'admin-section' },
                React.createElement('div', { className: 'appearance-save-section' },
                    React.createElement('input', { type: 'text', className: 'appearance-input', placeholder: 'Outfit name...', value: saveName, onChange: (e) => setSaveName(e.target.value), onKeyDown: (e) => { e.stopPropagation(); if (e.key === 'Enter') handleSave(); } }),
                    React.createElement('button', { className: 'admin-button success', onClick: handleSave, disabled: !saveName.trim() }, 'Save Current'),
                    React.createElement('button', { className: 'admin-button', onClick: handleImport }, 'Import from vMenu')
                ),
                savedPeds.length > 0 ?
                    React.createElement('div', { className: 'appearance-saved-list grid' },
                        savedPeds.map(ped => React.createElement('div', { className: 'appearance-saved-item card', key: ped.id },
                            React.createElement('div', { className: 'card-header' },
                                React.createElement('div', { className: 'card-title-row' },
                                    React.createElement('span', { className: 'card-title', title: ped.name }, ped.name),
                                    React.createElement(React.Fragment, null,
                                        React.createElement('span', { className: 'card-tag' }, ped.source || 'cortex-admin'),
                                        ped.isDefault && React.createElement('span', { className: 'card-tag' }, 'default')
                                    )
                                )
                            ),
                            React.createElement('div', { className: 'card-actions' },
                                React.createElement('button', { type: 'button', className: 'admin-button small', title: 'Load', onClick: () => handleLoad(ped) }, React.createElement(Icon, { name: 'download', size: 14 })),
                                React.createElement('button', { type: 'button', className: 'admin-button small', title: 'Overwrite', onClick: () => handleOverwrite(ped) }, React.createElement(Icon, { name: 'save', size: 14 })),
                                React.createElement('button', { type: 'button', className: 'admin-button small', title: 'Clone', onClick: () => handleClone(ped) }, React.createElement(Icon, { name: 'copy', size: 14 })),
                                React.createElement('button', { type: 'button', className: 'admin-button small', title: 'Rename', onClick: () => handleRename(ped) }, React.createElement(Icon, { name: 'pencil', size: 14 })),
                                React.createElement('button', { type: 'button', className: 'admin-button small danger', title: 'Delete', onClick: () => handleDelete(ped) }, React.createElement(Icon, { name: 'trash-2', size: 14 }))
                            )
                        ))
                    ) :
                    React.createElement('div', { className: 'appearance-no-saved' }, 'No saved outfits.')
            )
        )
    );
}

function AppearanceCollapsible({ title, meta, isNew = false, expanded, onToggle, children, className }) {
    const sectionClass = [className, 'appearance-collapsible'].filter(Boolean).join(' ');
    return React.createElement('section', { className: sectionClass },
        React.createElement('button', {
            type: 'button',
            className: 'appearance-collapsible-trigger',
            onClick: onToggle,
            'aria-expanded': expanded
        },
            React.createElement('span', { className: 'appearance-collapsible-chevron' },
                React.createElement(Icon, { name: expanded ? 'chevron-down' : 'chevron-right', size: 16 })
            ),
            React.createElement('span', { className: 'appearance-collapsible-title' }, title),
            isNew && React.createElement('span', {
                className: 'feature-discovery-dot',
                role: 'status',
                'aria-label': 'New feature',
                title: 'New feature'
            }),
            meta != null && meta !== '' && React.createElement('span', { className: 'appearance-collapsible-meta' }, meta)
        ),
        expanded && React.createElement('div', { className: 'appearance-collapsible-panel' }, children)
    );
}

function AppearanceWorkspaceView({ onPrompt } = {}) {
    const [data, setData] = useState(null);
    const [savedPeds, setSavedPeds] = useState([]);
    const [migrationInfo, setMigrationInfo] = useState(null);
    const [shareTargets, setShareTargets] = useState([]);
    const [selectedShareTarget, setSelectedShareTarget] = useState('');
    const [saveName, setSaveName] = useState('');
    const [savedPedSearch, setSavedPedSearch] = useState('');
    const [discoveredFeatureReleases, setDiscoveredFeatureReleases] = useState(readDiscoveredFeatureReleases);
    const [generatorOptions, setGeneratorOptions] = useState({
        mode: 'outfit',
        style: 'polished',
        gender: 'keep',
        hairTone: 'any',
        palette: 'neutral',
        faceProfile: 'everyday',
        ageProfile: 'young',
        complexion: 'clean',
        hairStyle: 'any',
        makeup: 'subtle',
        accessories: false
    });
    const [generatorBusy, setGeneratorBusy] = useState('');
    const [generatorCanUndo, setGeneratorCanUndo] = useState(false);
    const [generatorStatus, setGeneratorStatus] = useState(null);
    const [catOpen, setCatOpen] = useState({
        generator: false,
        workspace: true,
        library: false,
        wardrobeClothing: true,
        wardrobeProps: false,
        wardrobeColors: false,
        face: false,
        heritage: false
    });

    const toggleCat = useCallback((key) => {
        setCatOpen((prev) => ({ ...prev, [key]: !prev[key] }));
    }, []);

    const markFeatureDiscovered = useCallback((featureKey) => {
        const release = FEATURE_RELEASES[featureKey];
        if (!release) return;
        setDiscoveredFeatureReleases((previous) => {
            if (previous[featureKey] === release) return previous;
            const next = { ...previous, [featureKey]: release };
            writeDiscoveredFeatureReleases(next);
            return next;
        });
    }, []);

    const refreshData = useCallback(() => {
        fetchNui('cortex-admin:getAppearance').then((res) => res.json()).then((payload) => setData(normalizeAppearancePayload(payload)));
        fetchNui('cortex-admin:getSavedPeds').then((res) => res.json()).then((payload) => setSavedPeds(normalizeSavedOutfitList(payload)));
        fetchNui('cortex-admin:getVmenuMigrationSnapshot').then((res) => res.json()).then((payload) => setMigrationInfo(payload && typeof payload === 'object' ? payload : null));
        fetchNui('cortex-admin:getWardrobeShareTargets').then((res) => res.json()).then((payload) => {
            const targets = Array.isArray(payload)
                ? payload
                : (payload && Array.isArray(payload.targets) ? payload.targets : []);

            setShareTargets(targets);
            setSelectedShareTarget((prev) => {
                if (targets.some((target) => String(target.id) === String(prev))) {
                    return String(prev);
                }

                return targets[0] ? String(targets[0].id) : '';
            });
        });
    }, []);

    useEffect(() => {
        refreshData();
    }, [refreshData]);

    useEffect(() => {
        const handleAppearanceRefresh = () => refreshData();
        window.addEventListener('cortex-admin:appearanceRefresh', handleAppearanceRefresh);
        return () => window.removeEventListener('cortex-admin:appearanceRefresh', handleAppearanceRefresh);
    }, [refreshData]);

    useLayoutEffect(() => {
        if (!data) return;
        scheduleLucideIcons();
    }, [Boolean(data), catOpen]);

    const openPrompt = useCallback((config) => {
        if (!config || typeof config.onSubmit !== 'function') return;

        if (typeof onPrompt === 'function') {
            onPrompt(config);
            return;
        }

        const fields = Array.isArray(config.fields) ? config.fields : [];
        if (fields.length > 0) {
            const firstField = fields[0];
            const response = window.prompt(config.title || firstField.label || 'Enter value', firstField.initialValue || '');
            if (response === null) return;
            config.onSubmit({ [firstField.name]: response });
            return;
        }

        const confirmed = window.confirm(config.description || config.title || 'Confirm this action?');
        if (confirmed) {
            config.onSubmit({});
        }
    }, [onPrompt]);

    const filteredSavedPeds = useMemo(() => {
        const query = savedPedSearch.trim().toLowerCase();
        return savedPeds
            .slice()
            .sort((a, b) => String(a && a.name != null ? a.name : '').localeCompare(String(b && b.name != null ? b.name : '')))
            .filter((ped) => {
                if (!query) return true;
                const source = String(ped.source || 'cortex-admin').toLowerCase();
                const name = String(ped && ped.name != null ? ped.name : '').toLowerCase();
                return name.includes(query) || source.includes(query);
            });
    }, [savedPedSearch, savedPeds]);

    if (!data) return React.createElement('div', { className: 'admin-no-results' }, 'Loading appearance data...');

    const handleUpdate = (type, id, drawable, texture) => {
        fetchNui('cortex-admin:setAppearance', { type, id, drawable, texture });
        setData((prev) => {
            const next = { ...prev };
            const key = type === 'component' ? 'components' : 'props';
            next[key] = { ...prev[key], [id]: { drawable, texture } };
            return next;
        });
    };

    const handleFeatureUpdate = (id, value) => {
        fetchNui('cortex-admin:action', { id: 'player.setFaceFeature', data: { id, value } });
        setData((prev) => ({
            ...prev,
            features: { ...prev.features, [id]: value }
        }));
    };

    const handleBlendUpdate = (field, value) => {
        fetchNui('cortex-admin:setAppearance', { type: 'blend', field, value });
        setData((prev) => ({
            ...prev,
            headBlend: {
                ...(prev.headBlend || {}),
                [field]: value
            }
        }));
    };

    const handleOverlayUpdate = (id, field, value) => {
        fetchNui('cortex-admin:setAppearance', { type: 'overlay', id, field, value });
        setData((prev) => ({
            ...prev,
            overlays: {
                ...(prev.overlays || {}),
                [id]: {
                    ...((prev.overlays && prev.overlays[id]) ? prev.overlays[id] : {}),
                    [field]: value
                }
            }
        }));
    };

    const handleSave = () => {
        if (!saveName.trim()) return;
        fetchNui('cortex-admin:action', { id: 'player.saveMpPed', data: { name: saveName.trim() } });
        setSaveName('');
        setTimeout(refreshData, 500);
    };

    const handleShareCurrent = () => {
        if (!selectedShareTarget) {
            refreshData();
            return;
        }

        fetchNui('cortex-admin:shareWardrobe', { target: parseInt(selectedShareTarget, 10) })
            .then(() => setTimeout(refreshData, 300));
    };

    const handleImport = () => {
        openPrompt({
            title: 'Import from vMenu?',
            description: 'This copies all saved vMenu MP outfits into cortex-admin local storage so they keep working without vMenu running. Existing cortex-admin outfits with the same name are kept.',
            fields: [],
            onSubmit: () => {
                fetchNui('cortex-admin:importVmenuSavedPeds').then(() => setTimeout(refreshData, 500));
            }
        });
    };

    const handleImportAll = () => {
        openPrompt({
            title: 'Import all vMenu data?',
            description: 'This permanently imports durable vMenu data into cortex-admin, including saved MP outfits and saved vehicles when available. ACE permissions stay active and are not copied into storage.',
            fields: [],
            onSubmit: () => {
                fetchNui('cortex-admin:importVmenuMigrationData')
                    .then((res) => res.json())
                    .then(() => setTimeout(refreshData, 600));
            }
        });
    };

    const handleLoad = (ped) => {
        fetchNui('cortex-admin:action', { id: 'player.loadMpPed', data: { entry: ped } });
        setTimeout(refreshData, 800);
    };

    const handleDelete = (ped) => {
        openPrompt({
            title: `Delete outfit: ${ped.name}?`,
            description: ped.source === 'vmenu'
                ? 'This permanently removes the selected vMenu outfit.'
                : 'This permanently removes the saved outfit from cortex-admin local storage.',
            fields: [],
            onSubmit: () => {
                fetchNui('cortex-admin:deleteSavedPed', { entry: ped });
                setTimeout(refreshData, 500);
            }
        });
    };

    const handleRename = (ped) => {
        openPrompt({
            title: `Rename outfit: ${ped.name}`,
            description: ped.source === 'vmenu'
                ? 'This renames the vMenu save directly.'
                : 'Pick a new library name for this saved outfit.',
            fields: [{ name: 'name', label: 'New name', placeholder: 'Outfit name', initialValue: ped.name }],
            onSubmit: (values) => {
                const newName = values && values.name ? values.name.trim() : '';
                if (!newName) return;
                fetchNui('cortex-admin:renameSavedPed', { entry: ped, newName });
                setTimeout(refreshData, 500);
            }
        });
    };

    const handleClone = (ped) => {
        openPrompt({
            title: `Clone outfit: ${ped.name}`,
            description: ped.source === 'vmenu'
                ? 'This creates a new vMenu save cloned from the selected outfit.'
                : 'Create a second preset from this outfit.',
            fields: [{ name: 'name', label: 'Clone name', placeholder: 'Clone name', initialValue: `${ped.name} Copy` }],
            onSubmit: (values) => {
                const newName = values && values.name ? values.name.trim() : '';
                if (!newName) return;
                fetchNui('cortex-admin:cloneSavedPed', { entry: ped, newName });
                setTimeout(refreshData, 500);
            }
        });
    };

    const handleOverwrite = (ped) => {
        openPrompt({
            title: `Overwrite outfit: ${ped.name}?`,
            description: ped.source === 'vmenu'
                ? 'This replaces the existing vMenu outfit with your current appearance.'
                : 'This replaces the saved outfit with your current appearance.',
            fields: [],
            onSubmit: () => {
                fetchNui('cortex-admin:action', { id: 'player.saveMpPed', data: { name: ped.name, entry: ped } });
                setTimeout(refreshData, 500);
            }
        });
    };

    const handleSetDefault = (ped) => {
        fetchNui('cortex-admin:action', { id: 'player.setDefaultSavedPed', data: { entry: ped } });
        setTimeout(refreshData, 400);
    };

    const setGeneratorOption = (key, value) => {
        setGeneratorOptions((prev) => ({ ...prev, [key]: value }));
    };

    const handleGenerateAppearance = () => {
        if (generatorBusy) return;
        setGeneratorBusy('generate');
        setGeneratorStatus({ type: 'progress', message: 'Building a new look…' });
        fetchNui('cortex-admin:randomizeAppearance', generatorOptions)
            .then((res) => res.json())
            .then((result) => {
                if (!result || result.ok !== true) {
                    const messages = {
                        freemode_required: 'Switch to a freemode character before generating an outfit.',
                        model_forbidden: 'The server did not authorize that freemode model.',
                        model_load_failed: 'The selected freemode model could not be loaded.',
                        ped_unavailable: 'Your player character is not available yet.',
                        no_compatible_outfit: 'This freemode model did not expose a usable top, pants, and shoe combination.'
                    };
                    setGeneratorStatus({ type: 'error', message: messages[result && result.error] || 'The appearance could not be generated.' });
                    setGeneratorCanUndo(Boolean(result && result.canUndo));
                    return;
                }

                setGeneratorCanUndo(result.canUndo === true);
                setGeneratorStatus({
                    type: 'success',
                    message: `${result.outfitName || 'Curated outfit'} applied${result.mode === 'character' ? ' with a new character' : ' without changing your face or hair'}.`
                });
                setTimeout(refreshData, 250);
            })
            .catch(() => setGeneratorStatus({ type: 'error', message: 'The appearance generator did not respond.' }))
            .finally(() => setGeneratorBusy(''));
    };

    const handleUndoGeneratedAppearance = () => {
        if (generatorBusy || !generatorCanUndo) return;
        setGeneratorBusy('undo');
        setGeneratorStatus({ type: 'progress', message: 'Restoring the previous look…' });
        fetchNui('cortex-admin:undoRandomizedAppearance')
            .then((res) => res.json())
            .then((result) => {
                if (!result || result.ok !== true) {
                    setGeneratorCanUndo(Boolean(result && result.canUndo));
                    setGeneratorStatus({ type: 'error', message: 'The previous appearance could not be restored.' });
                    return;
                }
                setGeneratorCanUndo(false);
                setGeneratorStatus({ type: 'success', message: 'Previous appearance restored.' });
                setTimeout(refreshData, 250);
            })
            .catch(() => setGeneratorStatus({ type: 'error', message: 'The appearance undo did not respond.' }))
            .finally(() => setGeneratorBusy(''));
    };

    const ClickableValue = ({ value, max, min, onConfirm, disabled = false }) => {
        const [editing, setEditing] = useState(false);
        const [inputValue, setInputValue] = useState(value.toString());

        if (disabled) {
            return React.createElement('span', { className: 'appearance-value' }, `${value}/${max}`);
        }

        const handleConfirm = () => {
            const num = parseInt(inputValue);
            if (!isNaN(num)) {
                onConfirm(Math.max(min, Math.min(max, num)));
            }
            setEditing(false);
        };

        if (editing) {
            return React.createElement('input', {
                className: 'appearance-value-input',
                value: inputValue,
                autoFocus: true,
                onChange: (e) => setInputValue(e.target.value),
                onKeyDown: (e) => {
                    e.stopPropagation();
                    if (e.key === 'Enter') handleConfirm();
                    if (e.key === 'Escape') setEditing(false);
                },
                onBlur: handleConfirm
            });
        }

        return React.createElement('span', { className: 'appearance-value clickable', onClick: () => setEditing(true) }, `${value}/${max}`);
    };

    const renderSlider = (item, type) => {
        const isComponent = type === 'component';
        const current = isComponent ? data.components[item.id] : data.props[item.id];
        const max = isComponent ? data.maxComponents[item.id] : data.maxProps[item.id];

        if (!current || !max) return null;

        const drawableCount = Number(max.drawables);
        const textureCount = Number(max.textures);
        if (!Number.isFinite(drawableCount) || !Number.isFinite(textureCount)) return null;

        const minDrawable = isComponent ? 0 : -1;
        const maxDrawables = Math.max(minDrawable, drawableCount - 1);
        const maxTextures = Math.max(0, textureCount - 1);

        return React.createElement('div', { className: 'appearance-row appearance-row--wardrobe', key: `${type}-${item.id}` },
            React.createElement('div', { className: 'appearance-label' }, item.label),
            React.createElement(WardrobeDualStepper, {
                drawable: current.drawable,
                texture: current.texture,
                minDrawable,
                maxDrawable: maxDrawables,
                maxTexture: maxTextures,
                disabled: !data.isFreemode,
                drawableLabel: isComponent ? 'Drawable' : 'Index',
                onDrawable: (v) => handleUpdate(type, item.id, v, 0),
                onTexture: (v) => handleUpdate(type, item.id, current.drawable, v)
            })
        );
    };

    const clampFace = (v) => {
        const n = Number(v);
        if (!Number.isFinite(n)) return 0;
        return Math.min(1, Math.max(-1, Math.round(n * 100) / 100));
    };

    const renderFeatureSlider = (item) => {
        const raw = data.features && data.features[item.id] !== undefined ? data.features[item.id] : data.features && data.features[String(item.id)] !== undefined ? data.features[String(item.id)] : 0;
        const value = clampFace(raw);
        const disabled = !data.isFreemode;
        const bump = (delta) => handleFeatureUpdate(item.id, clampFace(value + delta));
        const onRange = (e) => handleFeatureUpdate(item.id, clampFace(parseFloat(e.target.value)));
        return React.createElement('div', { className: 'appearance-row appearance-row--feature feature', key: `feature-${item.id}` },
            React.createElement('div', { className: 'appearance-label appearance-label--feature' }, item.label),
            React.createElement('div', { className: 'appearance-control appearance-control--feature wide' },
                React.createElement('span', { className: 'appearance-value appearance-value--feature' }, value.toFixed(2)),
                React.createElement('input', {
                    type: 'range',
                    className: 'appearance-slider appearance-slider--feature',
                    'aria-label': item.label,
                    min: -1,
                    max: 1,
                    step: 0.01,
                    value: value,
                    disabled,
                    onInput: onRange,
                    onChange: onRange
                }),
                React.createElement('div', { className: 'appearance-btns appearance-btns--feature' },
                    React.createElement('button', { type: 'button', className: 'appearance-btn', disabled, onClick: () => bump(-0.05) }, '−'),
                    React.createElement('button', { type: 'button', className: 'appearance-btn', disabled, onClick: () => bump(0.05) }, '+')
                )
            )
        );
    };

    const renderColorSlider = (item) => {
        const disabled = !data.isFreemode;
        const value = item.type === 'hair' ? (data.hairColor || 0) :
            item.type === 'hairHighlight' ? (data.hairHighlightColor || 0) :
                item.type === 'eyes' ? (data.eyeColor || 0) :
                    (data.overlays && data.overlays[item.overlayId] ? data.overlays[item.overlayId].color : 0);

        const updateColorValue = (nextValue) => {
            fetchNui('cortex-admin:setAppearance', { type: 'color', colorType: item.type, id: item.overlayId, value: nextValue });
            setData((prev) => {
                if (item.type === 'hair') {
                    return { ...prev, hairColor: nextValue };
                }
                if (item.type === 'hairHighlight') {
                    return { ...prev, hairHighlightColor: nextValue };
                }
                if (item.type === 'eyes') {
                    return { ...prev, eyeColor: nextValue };
                }

                return {
                    ...prev,
                    overlays: {
                        ...prev.overlays,
                        [item.overlayId]: {
                            ...(prev.overlays && prev.overlays[item.overlayId] ? prev.overlays[item.overlayId] : {}),
                            color: nextValue
                        }
                    }
                };
            });
        };

        return React.createElement('div', { className: 'appearance-row', key: `color-${item.id}` },
            React.createElement('div', { className: 'appearance-label' }, item.label),
            React.createElement('div', { className: 'appearance-control wide' },
                React.createElement(ClickableValue, {
                    value,
                    max: 63,
                    min: 0,
                    disabled,
                    onConfirm: updateColorValue
                }),
                React.createElement('input', {
                    type: 'range',
                    className: 'appearance-slider',
                    'aria-label': item.label,
                    min: 0,
                    max: 63,
                    value,
                    disabled,
                    onChange: (e) => updateColorValue(parseInt(e.target.value))
                })
            )
        );
    };

    const heritageControlCount = AppearanceConfig.heritage.length + AppearanceConfig.overlays.length;
    const modelStatusLabel = data.isFreemode ? 'MP Freemode' : 'Custom Ped';

    const faceGroups = [
        { id: 'upper', label: 'Upper Face', items: AppearanceConfig.features.slice(0, 10) },
        { id: 'lower', label: 'Lower Face', items: AppearanceConfig.features.slice(10) }
    ];

    const renderWardrobePanel = (headerLabels, content, opts) => {
        const scrollBody = opts && opts.scrollBody;
        const shellClass = ['appearance-list-shell', 'appearance-list-shell--wardrobe', scrollBody ? 'appearance-list-shell--wardrobe-scroll' : ''].filter(Boolean).join(' ');
        const stackClass = ['appearance-section-stack', scrollBody ? 'appearance-section-stack--wardrobe-scroll' : ''].filter(Boolean).join(' ');
        return React.createElement('div', { className: shellClass },
            headerLabels && React.createElement('div', { className: 'appearance-header appearance-header--wardrobe' },
                React.createElement('span', { className: 'appearance-h-col-comp' }, headerLabels[0]),
                React.createElement('div', { className: 'appearance-h-col-steppers' },
                    React.createElement('span', { className: 'appearance-h-col-dt' }, headerLabels[1]),
                    React.createElement('span', { className: 'appearance-h-col-dt' }, headerLabels[2])
                )
            ),
            React.createElement('div', { className: stackClass }, content)
        );
    };

    const renderLibraryState = () => {
        if (filteredSavedPeds.length > 0) {
            return React.createElement('div', { className: 'appearance-preset-list' },
                filteredSavedPeds.map((ped) => {
                    const sourceLabel = String(ped.source || 'cortex-admin');
                    const showVmenu = sourceLabel === 'vmenu';
                    const showMeta = showVmenu || ped.isDefault;
                    return React.createElement('div', { className: 'appearance-preset-row appearance-saved-outfit-row', key: ped.id },
                        React.createElement('div', { className: 'appearance-preset-main' },
                            React.createElement('div', { className: 'appearance-preset-name', title: ped.name }, ped.name),
                            showMeta && React.createElement('div', { className: 'appearance-preset-meta' },
                                showVmenu && React.createElement('span', { className: 'appearance-preset-source' }, 'vMenu'),
                                ped.isDefault && React.createElement('span', { className: 'appearance-preset-flag' }, 'default')
                            )
                        ),
                        React.createElement('div', { className: 'appearance-preset-toolbar' },
                            React.createElement('button', {
                                type: 'button',
                                className: 'admin-button success appearance-tool-btn appearance-icon-btn',
                                onClick: () => handleLoad(ped),
                                title: 'Load outfit',
                                'aria-label': `Load ${ped.name}`
                            }, React.createElement(Icon, { name: 'log-in', size: 14 }), React.createElement('span', null, 'Load')),
                            React.createElement('button', {
                                type: 'button',
                                className: 'admin-button appearance-tool-btn appearance-icon-btn',
                                onClick: () => handleSetDefault(ped),
                                title: 'Set default',
                                'aria-label': `Set ${ped.name} as default`
                            }, React.createElement(Icon, { name: 'star', size: 14 })),
                            React.createElement('button', {
                                type: 'button',
                                className: 'admin-button appearance-tool-btn appearance-icon-btn',
                                onClick: () => handleOverwrite(ped),
                                title: 'Overwrite with current look',
                                'aria-label': `Overwrite ${ped.name}`
                            }, React.createElement(Icon, { name: 'save', size: 14 })),
                            React.createElement('button', {
                                type: 'button',
                                className: 'admin-button appearance-tool-btn appearance-icon-btn',
                                onClick: () => handleClone(ped),
                                title: 'Clone outfit',
                                'aria-label': `Clone ${ped.name}`
                            }, React.createElement(Icon, { name: 'copy', size: 14 })),
                            React.createElement('button', {
                                type: 'button',
                                className: 'admin-button appearance-tool-btn appearance-icon-btn',
                                onClick: () => handleRename(ped),
                                title: 'Rename outfit',
                                'aria-label': `Rename ${ped.name}`
                            }, React.createElement(Icon, { name: 'pencil', size: 14 })),
                            React.createElement('button', {
                                type: 'button',
                                className: 'admin-button danger appearance-tool-btn appearance-icon-btn',
                                onClick: () => handleDelete(ped),
                                title: 'Delete outfit',
                                'aria-label': `Delete ${ped.name}`
                            }, React.createElement(Icon, { name: 'trash-2', size: 14 }))
                        )
                    );
                })
            );
        }

        return React.createElement('div', { className: 'appearance-empty-state centered' },
            React.createElement(Icon, { name: 'shirt', size: 36 }),
            React.createElement('div', { className: 'appearance-empty-title' },
                savedPeds.length === 0 ? 'No saved outfits yet' : 'No outfits match this filter'
            ),
            React.createElement('div', { className: 'appearance-empty-copy' },
                savedPeds.length === 0 ? 'Save current look or import from vMenu.' : 'No matches — adjust search.'
            )
        );
    };

    const generatorChoice = (key, value, label, description) => React.createElement('button', {
        type: 'button',
        className: `appearance-generator-choice${generatorOptions[key] === value ? ' is-selected' : ''}`,
        'aria-pressed': generatorOptions[key] === value,
        disabled: Boolean(generatorBusy),
        onClick: () => setGeneratorOption(key, value)
    },
        React.createElement('strong', null, label),
        description && React.createElement('span', null, description)
    );

    const generatorSelect = (key, label, options) => React.createElement('div', {
        className: 'appearance-generator-select',
        key
    },
        React.createElement('span', null, label),
        React.createElement(CustomSelect, {
            options,
            value: generatorOptions[key],
            disabled: Boolean(generatorBusy),
            onChange: (value) => setGeneratorOption(key, value),
            ariaLabel: label
        })
    );

    const renderGenerator = () => React.createElement('div', { className: 'appearance-generator' },
        React.createElement('fieldset', { className: 'appearance-generator-fieldset' },
            React.createElement('legend', null, 'Generate'),
            React.createElement('div', { className: 'appearance-generator-choices appearance-generator-choices--mode' },
                generatorChoice('mode', 'outfit', 'Outfit only', 'Keep face, hair, heritage'),
                generatorChoice('mode', 'character', 'Full character', 'New identity and wardrobe')
            )
        ),
        React.createElement('fieldset', { className: 'appearance-generator-fieldset' },
            React.createElement('legend', null, 'Style direction'),
            React.createElement('div', { className: 'appearance-generator-choices appearance-generator-choices--style' },
                generatorChoice('style', 'polished', 'Polished', 'Shirts, polos, clean shoes'),
                generatorChoice('style', 'casual', 'Casual', 'T-shirts, denim, canvas'),
                generatorChoice('style', 'street', 'Street', 'Cargos, boots, high tops')
            )
        ),
        React.createElement('div', { className: 'appearance-generator-grid' },
            generatorSelect('palette', 'Clothing palette', [
                { value: 'neutral', label: 'Restrained' },
                { value: 'tonal', label: 'Tonal' },
                { value: 'varied', label: 'Mixed' }
            ]),
            generatorOptions.mode === 'character' && generatorSelect('gender', 'Body model', [
                { value: 'keep', label: 'Keep current' },
                { value: 'random', label: 'Surprise me' },
                { value: 'male', label: 'Freemode male' },
                { value: 'female', label: 'Freemode female' }
            ]),
            generatorOptions.mode === 'character' && generatorSelect('faceProfile', 'Face profile', [
                { value: 'everyday', label: 'Everyday' },
                { value: 'east_asian', label: 'East Asian' },
                { value: 'soft', label: 'Soft features' }
            ]),
            generatorOptions.mode === 'character' && generatorSelect('ageProfile', 'Age', [
                { value: 'young', label: 'Young adult' },
                { value: 'adult', label: 'Adult' },
                { value: 'mature', label: 'Mature' }
            ]),
            generatorOptions.mode === 'character' && generatorSelect('complexion', 'Complexion', [
                { value: 'clean', label: 'Clean' },
                { value: 'natural', label: 'Natural detail' }
            ]),
            generatorOptions.mode === 'character' && generatorSelect('hairStyle', 'Hair shape', [
                { value: 'any', label: 'Any reviewed style' },
                { value: 'short', label: 'Short' },
                { value: 'medium', label: 'Medium' },
                { value: 'long', label: 'Long / tied' },
                { value: 'updo', label: 'Updo' }
            ]),
            generatorOptions.mode === 'character' && generatorSelect('hairTone', 'Natural hair tone', [
                { value: 'any', label: 'Any natural tone' },
                { value: 'dark', label: 'Dark' },
                { value: 'warm', label: 'Warm brown / auburn' },
                { value: 'light', label: 'Blonde / light' }
            ]),
            generatorOptions.mode === 'character' && generatorSelect('makeup', 'Makeup', [
                { value: 'none', label: 'None' },
                { value: 'subtle', label: 'Subtle' },
                { value: 'polished', label: 'Polished' }
            ]),
            React.createElement('button', {
                type: 'button',
                role: 'switch',
                className: `appearance-generator-switch${generatorOptions.accessories ? ' is-on' : ''}`,
                'aria-checked': generatorOptions.accessories,
                disabled: Boolean(generatorBusy),
                onClick: () => setGeneratorOption('accessories', !generatorOptions.accessories)
            },
                React.createElement('span', null,
                    React.createElement('strong', null, 'Accessories'),
                    React.createElement('small', null, generatorOptions.accessories ? 'Preset watch or glasses' : 'No added props')
                ),
                React.createElement('span', { className: 'appearance-generator-switch-track', 'aria-hidden': true },
                    React.createElement('span', { className: 'appearance-generator-switch-thumb' })
                )
            )
        ),
        React.createElement('div', { className: 'appearance-generator-actions' },
            React.createElement('button', {
                type: 'button',
                className: 'admin-button success appearance-generator-primary',
                disabled: Boolean(generatorBusy),
                onClick: handleGenerateAppearance
            },
                React.createElement(Icon, { name: generatorBusy === 'generate' ? 'loader-circle' : 'dices', size: 16, className: generatorBusy === 'generate' ? 'is-spinning' : '' }),
                React.createElement('span', null, generatorBusy === 'generate'
                    ? 'Generating…'
                    : generatorOptions.mode === 'character' ? 'Generate character' : 'Generate outfit')
            ),
            React.createElement('button', {
                type: 'button',
                className: 'admin-button appearance-generator-undo appearance-icon-btn',
                disabled: Boolean(generatorBusy) || !generatorCanUndo,
                title: generatorCanUndo ? 'Restore the look from before the last roll' : 'Generate a look first',
                'aria-label': generatorBusy === 'undo' ? 'Restoring previous look' : 'Undo last roll',
                onClick: handleUndoGeneratedAppearance
            },
                React.createElement(Icon, { name: generatorBusy === 'undo' ? 'loader-circle' : 'undo-2', size: 16, className: generatorBusy === 'undo' ? 'is-spinning' : '' })
            )
        ),
        React.createElement('div', {
            className: `appearance-generator-status${generatorStatus ? ` is-${generatorStatus.type}` : ''}`,
            role: 'status',
            'aria-live': 'polite'
        }, generatorStatus ? generatorStatus.message : '')
    );

    const migrationAvailable = Boolean(migrationInfo && (
        (migrationInfo.peds && migrationInfo.peds.available)
        || (migrationInfo.vehicles && migrationInfo.vehicles.available)
    ));

    const renderWorkspaceStack = () => React.createElement('div', { className: 'appearance-workspace-stack' },
        React.createElement('div', { className: 'appearance-workspace-block' },
            React.createElement('div', { className: 'appearance-block-label' }, 'Save outfit'),
            !data.isFreemode && React.createElement('div', { className: 'appearance-inline-note warning' },
                'Not freemode — switch MP model for full wardrobe.'
            ),
            React.createElement('div', { className: 'appearance-save-row' },
                React.createElement('input', {
                    type: 'text',
                    className: 'appearance-input',
                    placeholder: 'Name this outfit...',
                    value: saveName,
                    onChange: (e) => setSaveName(e.target.value),
                    onKeyDown: (e) => {
                        e.stopPropagation();
                        if (e.key === 'Enter') handleSave();
                    }
                }),
                React.createElement('button', {
                    type: 'button',
                    className: 'admin-button success appearance-tool-btn',
                    onClick: handleSave,
                    disabled: !saveName.trim()
                }, React.createElement(Icon, { name: 'save', size: 14 }), React.createElement('span', null, 'Save'))
            )
        ),
        shareTargets.length > 0
            ? React.createElement('div', { className: 'appearance-workspace-block' },
                React.createElement('div', { className: 'appearance-block-label' }, 'Share nearby'),
                React.createElement('div', { className: 'appearance-share-toolbar' },
                    React.createElement('div', { className: 'appearance-share-select-wrap' },
                        React.createElement(CustomSelect, {
                            options: shareTargets.map((target) => ({
                                label: `${target.name} · ${Number(target.distance || 0).toFixed(1)}m`,
                                value: String(target.id)
                            })),
                            value: selectedShareTarget,
                            onChange: (value) => setSelectedShareTarget(String(value)),
                            ariaLabel: 'Nearby player'
                        })
                    ),
                    React.createElement('div', { className: 'appearance-share-actions' },
                        React.createElement('button', {
                            type: 'button',
                            className: 'admin-button small appearance-tool-btn',
                            onClick: refreshData,
                            title: 'Refresh nearby players',
                            'aria-label': 'Refresh nearby players'
                        }, React.createElement(Icon, { name: 'refresh-cw', size: 14 })),
                        React.createElement('button', {
                            type: 'button',
                            className: 'admin-button success appearance-tool-btn',
                            onClick: handleShareCurrent,
                            disabled: !selectedShareTarget
                        }, React.createElement(Icon, { name: 'send', size: 14 }), React.createElement('span', null, 'Send'))
                    )
                )
            )
            : React.createElement('div', { className: 'appearance-workspace-utility appearance-workspace-utility--empty-share' },
                React.createElement('div', { className: 'appearance-workspace-utility-copy' },
                    React.createElement(Icon, { name: 'users', size: 14 }),
                    React.createElement('span', null, 'No nearby players')
                ),
                React.createElement('div', { className: 'appearance-share-actions' },
                    React.createElement('button', {
                        type: 'button',
                        className: 'admin-button small appearance-tool-btn appearance-icon-btn',
                        onClick: refreshData,
                        title: 'Refresh nearby players',
                        'aria-label': 'Refresh nearby players'
                    }, React.createElement(Icon, { name: 'refresh-cw', size: 14 }))
                )
            ),
        migrationAvailable && React.createElement('div', { className: 'appearance-workspace-utility appearance-workspace-utility--import' },
            React.createElement('div', { className: 'appearance-workspace-utility-copy' },
                React.createElement(Icon, { name: 'archive-restore', size: 14 }),
                React.createElement('span', null, 'vMenu data available')
            ),
            React.createElement('div', { className: 'appearance-workspace-utility-actions' },
                React.createElement('button', {
                    type: 'button',
                    className: 'admin-button small appearance-tool-btn',
                    onClick: handleImportAll
                }, React.createElement(Icon, { name: 'download', size: 14 }), React.createElement('span', null, 'Import'))
            )
        )
    );

    const renderFaceBody = () => React.createElement(React.Fragment, null,
        React.createElement('div', { className: 'appearance-section-intro appearance-section-intro--hero' },
            'Drag sliders or use ±. Each control is −1 to 1. Slider uses fine steps for smoother sculpting.'
        ),
        React.createElement('div', { className: 'appearance-face-stack' },
            faceGroups.map((group) => React.createElement('div', { className: 'appearance-list-shell appearance-panel--face', key: group.id },
                React.createElement('div', { className: 'appearance-group-header' },
                    React.createElement('div', { className: 'appearance-group-copy' },
                        React.createElement('div', { className: 'appearance-group-title' }, group.label),
                        React.createElement('div', { className: 'appearance-section-intro' }, `${group.items.length} controls`)
                    ),
                    React.createElement('div', { className: 'appearance-group-count' }, `${group.items.length}`)
                ),
                React.createElement('div', { className: 'appearance-section-stack' },
                    group.items.map((feature) => renderFeatureSlider(feature))
                )
            ))
        )
    );

    const renderHeritageSlider = (item) => {
        const current = data.headBlend && data.headBlend[item.field] !== undefined ? data.headBlend[item.field] : item.min;
        const isFloat = item.step < 1;
        const disabled = !data.isFreemode;
        const updateValue = (nextValue) => handleBlendUpdate(item.field, nextValue);
        const displayValue = isFloat ? Number(current).toFixed(2) : current;
        const onRange = (e) => updateValue(isFloat ? parseFloat(e.target.value) : parseInt(e.target.value, 10));

        return React.createElement('div', { className: 'appearance-row appearance-row--heritage', key: `blend-${item.field}` },
            React.createElement('div', { className: 'appearance-label appearance-label--heritage' }, item.label),
            React.createElement('div', { className: 'appearance-control appearance-control--heritage wide' },
                React.createElement('span', { className: 'appearance-value appearance-value--heritage' }, displayValue),
                React.createElement('input', {
                    type: 'range',
                    className: 'appearance-slider appearance-slider--heritage',
                    'aria-label': item.label,
                    min: item.min,
                    max: item.max,
                    step: item.step,
                    value: current,
                    disabled,
                    onInput: onRange,
                    onChange: onRange
                })
            )
        );
    };

    const renderOverlayControl = (item) => {
        const overlay = (data.overlays && data.overlays[item.id]) || { style: 0, opacity: 0, color: 0, secondColor: 0, maxStyles: 0 };
        const maxStyle = Math.max(0, ((overlay.maxStyles || 1) - 1));
        const disabled = !data.isFreemode;

        const row = (label, valueEl, inputEl) => React.createElement('div', { className: 'appearance-row appearance-row--overlay' },
            React.createElement('div', { className: 'appearance-label appearance-label--overlay' }, label),
            React.createElement('div', { className: 'appearance-control appearance-control--overlay wide' },
                valueEl,
                inputEl
            )
        );

        return React.createElement('div', { className: 'appearance-list-shell appearance-overlay-card', key: `overlay-${item.id}` },
            React.createElement('div', { className: 'appearance-overlay-card-head' },
                React.createElement('div', { className: 'appearance-group-title appearance-overlay-name' }, item.label),
                React.createElement('div', { className: 'appearance-section-intro' }, 'Style · opacity · palette')
            ),
            React.createElement('div', { className: 'appearance-section-stack appearance-overlay-rows' },
                row(
                    'Style',
                    React.createElement('span', { className: 'appearance-value appearance-value--overlay' }, `${overlay.style || 0} / ${maxStyle}`),
                    React.createElement('input', {
                        type: 'range',
                        className: 'appearance-slider appearance-slider--overlay',
                        'aria-label': `${item.label} style`,
                        min: 0,
                        max: maxStyle,
                        step: 1,
                        value: overlay.style || 0,
                        disabled,
                        onInput: (e) => handleOverlayUpdate(item.id, 'style', parseInt(e.target.value, 10)),
                        onChange: (e) => handleOverlayUpdate(item.id, 'style', parseInt(e.target.value, 10))
                    })
                ),
                row(
                    'Opacity',
                    React.createElement('span', { className: 'appearance-value appearance-value--overlay' }, Number(overlay.opacity || 0).toFixed(2)),
                    React.createElement('input', {
                        type: 'range',
                        className: 'appearance-slider appearance-slider--overlay',
                        'aria-label': `${item.label} opacity`,
                        min: 0,
                        max: 1,
                        step: 0.01,
                        value: overlay.opacity || 0,
                        disabled,
                        onInput: (e) => handleOverlayUpdate(item.id, 'opacity', parseFloat(e.target.value)),
                        onChange: (e) => handleOverlayUpdate(item.id, 'opacity', parseFloat(e.target.value))
                    })
                ),
                item.hasColor && row(
                    'Color A',
                    React.createElement('span', { className: 'appearance-value appearance-value--overlay' }, `${overlay.color || 0} / 63`),
                    React.createElement('input', {
                        type: 'range',
                        className: 'appearance-slider appearance-slider--overlay',
                        'aria-label': `${item.label} color A`,
                        min: 0,
                        max: 63,
                        step: 1,
                        value: overlay.color || 0,
                        disabled,
                        onInput: (e) => handleOverlayUpdate(item.id, 'color', parseInt(e.target.value, 10)),
                        onChange: (e) => handleOverlayUpdate(item.id, 'color', parseInt(e.target.value, 10))
                    })
                ),
                item.hasSecondColor && row(
                    'Color B',
                    React.createElement('span', { className: 'appearance-value appearance-value--overlay' }, `${overlay.secondColor || 0} / 63`),
                    React.createElement('input', {
                        type: 'range',
                        className: 'appearance-slider appearance-slider--overlay',
                        'aria-label': `${item.label} color B`,
                        min: 0,
                        max: 63,
                        step: 1,
                        value: overlay.secondColor || 0,
                        disabled,
                        onInput: (e) => handleOverlayUpdate(item.id, 'secondColor', parseInt(e.target.value, 10)),
                        onChange: (e) => handleOverlayUpdate(item.id, 'secondColor', parseInt(e.target.value, 10))
                    })
                )
            )
        );
    };

    const renderHeritageBody = () => React.createElement(React.Fragment, null,
        !data.isFreemode && React.createElement('div', { className: 'appearance-inline-note warning' },
            'Heritage and cosmetic overlays are designed for MP freemode peds and may not apply cleanly on story or addon models.'
        ),
        React.createElement('div', { className: 'appearance-migration-actions appearance-heritage-toolbar' },
            React.createElement('button', {
                type: 'button',
                className: 'admin-button appearance-tool-btn appearance-tool-btn--grow',
                onClick: () => fetchNui('cortex-admin:action', { id: 'player.randomizeMpFace' }).then(() => setTimeout(refreshData, 300)),
                disabled: !data.isFreemode
            }, React.createElement(Icon, { name: 'sparkles', size: 16 }), React.createElement('span', null, 'Randomize face')),
            React.createElement('button', {
                type: 'button',
                className: 'admin-button appearance-tool-btn appearance-tool-btn--grow',
                onClick: () => fetchNui('cortex-admin:action', { id: 'player.clearPedTattoos' }).then(() => setTimeout(refreshData, 300))
            }, React.createElement(Icon, { name: 'eraser', size: 16 }), React.createElement('span', null, 'Clear tattoos'))
        ),
        React.createElement('div', { className: 'appearance-heritage-layout' },
            React.createElement('div', { className: 'appearance-list-shell appearance-heritage-blend' },
                React.createElement('div', { className: 'appearance-group-header' },
                    React.createElement('div', { className: 'appearance-group-copy' },
                        React.createElement('div', { className: 'appearance-group-title' }, 'Heritage blend'),
                        React.createElement('div', { className: 'appearance-section-intro' }, 'Parents, skin tones, mix sliders.')
                    ),
                    React.createElement('div', { className: 'appearance-group-count' }, `${AppearanceConfig.heritage.length}`)
                ),
                React.createElement('div', { className: 'appearance-section-stack' },
                    AppearanceConfig.heritage.map((item) => renderHeritageSlider(item))
                )
            ),
            React.createElement('div', { className: 'appearance-overlay-scroll' },
                React.createElement('div', { className: 'appearance-overlay-list-title' }, 'Head overlays'),
                AppearanceConfig.overlays.map((item) => renderOverlayControl(item))
            )
        )
    );

    const mpMaleActive = data.isFreemode && modelHashU32(data.model) === MODEL_HASH_MP_M;
    const mpFemaleActive = data.isFreemode && modelHashU32(data.model) === MODEL_HASH_MP_F;

    const savedLabel = `${savedPeds.length} saved`;

    return React.createElement('div', { className: 'admin-appearance' },
        React.createElement('div', { className: 'appearance-summary-bar' },
            React.createElement('div', { className: 'appearance-summary-compact', title: modelStatusLabel },
                React.createElement('span', { className: 'appearance-summary-model' }, modelStatusLabel),
                React.createElement('span', { className: 'appearance-summary-sep', 'aria-hidden': true }, '·'),
                React.createElement('span', { className: 'appearance-summary-count' }, savedLabel)
            ),
            React.createElement('div', { className: 'appearance-model-bar' },
                data.isFreemode && React.createElement('div', { className: 'appearance-gender-split' },
                    React.createElement('button', {
                        type: 'button',
                        className: `appearance-gender-btn${mpMaleActive ? ' active' : ''}`,
                        onClick: () => fetchNui('cortex-admin:action', { id: 'player.setModel', data: { model: 'mp_m_freemode_01' } }).then(() => setTimeout(refreshData, 1000))
                    }, 'Male'),
                    React.createElement('button', {
                        type: 'button',
                        className: `appearance-gender-btn${mpFemaleActive ? ' active' : ''}`,
                        onClick: () => fetchNui('cortex-admin:action', { id: 'player.setModel', data: { model: 'mp_f_freemode_01' } }).then(() => setTimeout(refreshData, 1000))
                    }, 'Female')
                ),
                React.createElement('button', {
                    type: 'button',
                    className: 'admin-button small appearance-top-refresh',
                    title: 'Refresh',
                    onClick: refreshData
                }, React.createElement(Icon, { name: 'refresh-cw', size: 16 }))
            )
        ),
        React.createElement('div', { className: 'appearance-content-area appearance-content-area--scroll' },
            React.createElement(AppearanceCollapsible, {
                title: 'Appearance generator',
                isNew: discoveredFeatureReleases.appearanceGenerator !== FEATURE_RELEASES.appearanceGenerator,
                expanded: catOpen.generator,
                onToggle: () => {
                    if (!catOpen.generator) markFeatureDiscovered('appearanceGenerator');
                    toggleCat('generator');
                }
            }, renderGenerator()),
            React.createElement(AppearanceCollapsible, {
                title: 'Outfit workspace',
                expanded: catOpen.workspace,
                onToggle: () => toggleCat('workspace')
            }, renderWorkspaceStack()),
            React.createElement(AppearanceCollapsible, {
                title: 'Saved outfits',
                expanded: catOpen.library,
                onToggle: () => toggleCat('library')
            },
                React.createElement('div', { className: 'appearance-library-panel' },
                    React.createElement('input', {
                        type: 'text',
                        className: 'appearance-input appearance-library-filter',
                        placeholder: 'Search…',
                        value: savedPedSearch,
                        onChange: (e) => setSavedPedSearch(e.target.value),
                        onKeyDown: (e) => e.stopPropagation()
                    }),
                    React.createElement('div', { className: 'appearance-list-shell appearance-library-shell' }, renderLibraryState())
                )
            ),
            React.createElement(AppearanceCollapsible, {
                title: 'Clothing components',
                meta: String(AppearanceConfig.components.length),
                expanded: catOpen.wardrobeClothing,
                onToggle: () => toggleCat('wardrobeClothing'),
                className: 'appearance-collapsible--wardrobe-clothing'
            }, renderWardrobePanel(['Component', 'Drawable', 'Texture'], AppearanceConfig.components.map((c) => renderSlider(c, 'component')), { scrollBody: true })),
            React.createElement(AppearanceCollapsible, {
                title: 'Props',
                meta: String(AppearanceConfig.props.length),
                expanded: catOpen.wardrobeProps,
                onToggle: () => toggleCat('wardrobeProps'),
                className: 'appearance-collapsible--wardrobe-props'
            }, renderWardrobePanel(['Prop', 'Index', 'Texture'], AppearanceConfig.props.map((p) => renderSlider(p, 'prop')), { scrollBody: true })),
            React.createElement(AppearanceCollapsible, {
                title: 'Palette',
                meta: String(AppearanceConfig.colors.length),
                expanded: catOpen.wardrobeColors,
                onToggle: () => toggleCat('wardrobeColors')
            }, renderWardrobePanel(null, AppearanceConfig.colors.map((c) => renderColorSlider(c)))),
            React.createElement(AppearanceCollapsible, {
                title: 'Face sculpt',
                meta: String(AppearanceConfig.features.length),
                expanded: catOpen.face,
                onToggle: () => toggleCat('face')
            }, renderFaceBody()),
            React.createElement(AppearanceCollapsible, {
                title: 'Heritage & overlays',
                meta: String(heritageControlCount),
                expanded: catOpen.heritage,
                onToggle: () => toggleCat('heritage')
            }, renderHeritageBody())
        )
    );
}

function VoiceChatWorkspace({ actions, toggles, allowed, voiceState, onToggle, onSelect, onPromptSubmit }) {
    const [channelInput, setChannelInput] = useState('');
    const [proximityOverride, setProximityOverride] = useState(null);

    const voiceActions = useMemo(() => {
        const map = {};
        (Array.isArray(actions) ? actions : []).forEach((action) => {
            if (action && action.tab === 'voice') map[action.id] = action;
        });
        return map;
    }, [actions]);

    const enabledAction = voiceActions['voice.enabled'] || null;
    const speakerAction = voiceActions['voice.showSpeaker'] || null;
    const statusAction = voiceActions['voice.showStatus'] || null;
    const proximityAction = voiceActions['voice.proximity'] || null;
    const channelAction = voiceActions['voice.channel'] || null;
    const actionAllowed = (action) => !!action && (!allowed || allowed[action.id] !== false);

    const safeToggles = isPlainObject(toggles) ? toggles : {};
    const enabled = safeToggles['voice.enabled'] === true;
    const showSpeaker = safeToggles['voice.showSpeaker'] === true;
    const showStatus = safeToggles['voice.showStatus'] === true;
    const proximityOptions = normalizeValues(proximityAction && proximityAction.values);
    const normalizedVoiceState = normalizeVoiceState(voiceState);
    const reportedProximity = normalizedVoiceState.proximity;
    const currentChannel = normalizedVoiceState.channel;
    const proximityValue = proximityOverride !== null
        ? proximityOverride
        : reportedProximity;
    const activeProximity = proximityOptions.find((option) => String(option.value) === String(proximityValue)) || null;
    const proximityAvailable = actionAllowed(proximityAction) && typeof onSelect === 'function';
    const channelAvailable = actionAllowed(channelAction) && typeof onPromptSubmit === 'function';
    const isGlobalProximity = activeProximity && Number(activeProximity.value) >= 9999;
    const proximityMetric = activeProximity
        ? (isGlobalProximity ? 'GLOBAL' : `${Number(activeProximity.value)} M`)
        : (reportedProximity !== null
            ? (reportedProximity >= 9999 ? 'GLOBAL' : `${reportedProximity} M`)
            : '--');
    const currentChannelLabel = currentChannel === null ? '--' : (currentChannel > 0 ? `#${currentChannel}` : 'NONE');
    const rawChannel = channelInput.trim();
    const parsedChannel = rawChannel === '' ? NaN : Number(rawChannel);
    const channelInputValid = Number.isInteger(parsedChannel) && parsedChannel >= 0 && parsedChannel <= 65535;
    const channelField = channelAction && channelAction.prompt && Array.isArray(channelAction.prompt.fields)
        ? channelAction.prompt.fields[0]
        : null;

    useEffect(() => {
        setProximityOverride(null);
    }, [reportedProximity]);

    const handleProximity = (option) => {
        if (!proximityAction || !proximityAvailable) return;
        setProximityOverride(option.value);
        onSelect(proximityAction, option.value);
    };

    const submitChannel = (nextChannel) => {
        if (!channelAction || !channelAvailable) return;
        const numericChannel = Number(nextChannel);
        if (!Number.isInteger(numericChannel) || numericChannel < 0 || numericChannel > 65535) return;
        onPromptSubmit(channelAction, { channel: numericChannel });
        setChannelInput('');
    };

    const renderSwitch = (action, isOn) => {
        if (!action) return h('span', { className: 'voice-control-unavailable' }, 'Unavailable');
        const canUse = actionAllowed(action);
        return h('button', {
            type: 'button',
            role: 'switch',
            className: `voice-switch${isOn ? ' is-on' : ''}`,
            title: canUse ? `${isOn ? 'Disable' : 'Enable'} ${action.label}` : `Permission required for ${action.label}`,
            'aria-label': `${action.label}: ${isOn ? 'on' : 'off'}`,
            'aria-checked': isOn,
            disabled: !canUse,
            onClick: () => typeof onToggle === 'function' && onToggle(action, !isOn)
        },
            h('span', { className: 'voice-switch-track', 'aria-hidden': true },
                h('span', { className: 'voice-switch-thumb' })
            )
        );
    };

    const renderIndicator = (action, isOn, iconName) => action && h('div', {
        className: `voice-indicator-row${isOn ? ' is-on' : ''}`,
        key: action.id
    },
        h(Icon, { name: iconName, size: 15, className: 'voice-indicator-icon' }),
        h('div', { className: 'voice-control-copy' },
            h('h4', null, action.label),
            h('p', null, action.description)
        ),
        renderSwitch(action, isOn)
    );

    const optionParts = (option) => {
        const label = String(option.label || option.value || '');
        const match = label.match(/^(.+?)\s*\(([^)]+)\)$/);
        return match
            ? { label: match[1], metric: match[2] }
            : { label, metric: Number(option.value) >= 9999 ? 'Unbounded' : `${option.value}m` };
    };

    if (Object.keys(voiceActions).length === 0) {
        return h('div', { className: 'admin-workspace voice-workspace' },
            h('div', { className: 'admin-state-panel', role: 'status' },
                h(Icon, { name: 'audio-lines', size: 22 }),
                h('strong', null, 'Voice controls unavailable'),
                h('span', null, 'The vMenu compatibility action catalog did not load.')
            )
        );
    }

    return h('div', { className: 'voice-workspace' },
        h('main', { className: 'voice-control-surface' },
                h('section', {
                    className: `voice-control-section voice-master-control${enabled ? ' is-on' : ''}`,
                    'aria-labelledby': 'voice-master-title'
                },
                    h('div', { className: 'voice-control-heading' },
                        h(Icon, { name: 'power', size: 16 }),
                        h('div', { className: 'voice-control-copy' },
                            h('h3', { id: 'voice-master-title' }, enabledAction ? enabledAction.label : 'Enable Voice Chat'),
                            h('p', null, enabledAction ? enabledAction.description : 'Enable or disable the native FiveM voice channel')
                        )
                    ),
                    renderSwitch(enabledAction, enabled)
                ),

                h('section', { className: 'voice-control-section', 'aria-labelledby': 'voice-proximity-title' },
                    h('div', { className: 'voice-section-header' },
                        h('div', { className: 'voice-control-heading' },
                            h(Icon, { name: 'radio-tower', size: 16 }),
                            h('div', { className: 'voice-control-copy' },
                                h('h3', { id: 'voice-proximity-title' }, proximityAction ? proximityAction.label : 'Voice Chat Proximity'),
                                h('p', null, proximityAction ? proximityAction.description : 'Set the native talker proximity')
                            )
                        ),
                        h('output', { className: 'voice-section-readout', 'aria-live': 'polite' }, proximityMetric)
                    ),
                    h('div', { className: 'voice-proximity-grid', role: 'group', 'aria-label': 'Talker proximity' },
                        proximityOptions.map((option) => {
                            const selected = proximityValue !== null && String(proximityValue) === String(option.value);
                            const parts = optionParts(option);
                            return h('button', {
                                key: String(option.value),
                                type: 'button',
                                className: `voice-proximity-option${selected ? ' is-active' : ''}`,
                                disabled: !proximityAvailable,
                                'aria-pressed': selected,
                                onClick: () => handleProximity(option)
                            },
                                h('span', { className: 'voice-proximity-label' }, parts.label),
                                h('span', { className: 'voice-proximity-metric' }, parts.metric)
                            );
                        })
                    ),
                    proximityAction && !actionAllowed(proximityAction) && h('span', { className: 'voice-permission-note' },
                        h(Icon, { name: 'lock-keyhole', size: 11 }), 'Permission required'
                    )
                ),

                h('section', { className: 'voice-control-section', 'aria-labelledby': 'voice-channel-title' },
                    h('div', { className: 'voice-section-header' },
                        h('div', { className: 'voice-control-heading' },
                            h(Icon, { name: 'hash', size: 16 }),
                            h('div', { className: 'voice-control-copy' },
                                h('h3', { id: 'voice-channel-title' }, channelAction ? channelAction.label : 'Voice Chat Channel'),
                                h('p', null, channelAction ? channelAction.description : 'Join a numbered native voice channel, or 0 to leave')
                            )
                        ),
                        h('div', { className: 'voice-channel-current', 'aria-live': 'polite' },
                            h('span', null, 'CURRENT'),
                            h('strong', null, currentChannelLabel)
                        )
                    ),
                    h('form', {
                        className: 'voice-channel-form',
                        onSubmit: (event) => {
                            event.preventDefault();
                            if (channelInputValid) submitChannel(parsedChannel);
                        }
                    },
                        h('label', { className: 'voice-channel-field' },
                            h('span', { className: 'voice-channel-label' }, channelField && channelField.label ? channelField.label : 'Channel (0-65535)'),
                            h('span', { className: 'voice-channel-input-wrap' },
                                h('span', { className: 'voice-channel-prefix', 'aria-hidden': true }, '#'),
                                h('input', {
                                    type: 'text',
                                    inputMode: 'numeric',
                                    pattern: '[0-9]*',
                                    maxLength: 5,
                                    className: 'voice-channel-input',
                                    placeholder: channelField && channelField.placeholder ? channelField.placeholder : '0',
                                    value: channelInput,
                                    disabled: !actionAllowed(channelAction),
                                    'aria-invalid': rawChannel !== '' && !channelInputValid,
                                    'aria-describedby': 'voice-channel-hint',
                                    onChange: (event) => setChannelInput(event.target.value.replace(/[^0-9]/g, '').slice(0, 5)),
                                    onKeyDown: (event) => {
                                        event.stopPropagation();
                                        if (event.key === 'Escape') setChannelInput('');
                                    }
                                })
                            )
                        ),
                        h('div', { className: 'voice-channel-actions' },
                            h('button', {
                                type: 'submit',
                                className: 'admin-button voice-channel-submit',
                                disabled: !channelInputValid || !channelAvailable
                            }, h(Icon, { name: 'log-in', size: 13 }), 'Join'),
                            h('button', {
                                type: 'button',
                                className: 'admin-button voice-channel-leave',
                                disabled: currentChannel === null || currentChannel === 0 || !channelAvailable,
                                onClick: () => submitChannel(0)
                            }, 'Leave')
                        )
                    ),
                    h('p', {
                        id: 'voice-channel-hint',
                        className: `voice-channel-hint${rawChannel !== '' && !channelInputValid ? ' is-error' : ''}`
                    }, rawChannel !== '' && !channelInputValid
                        ? 'Enter a whole number from 0 to 65535.'
                        : 'Channel 0 returns you to proximity voice.')
                ),

                (speakerAction || statusAction) && h('section', { className: 'voice-control-section voice-indicators', 'aria-labelledby': 'voice-indicators-title' },
                    h('div', { className: 'voice-section-header' },
                        h('div', { className: 'voice-control-heading' },
                            h(Icon, { name: 'monitor-up', size: 16 }),
                            h('div', { className: 'voice-control-copy' },
                                h('h3', { id: 'voice-indicators-title' }, 'On-screen indicators'),
                                h('p', null, 'Choose which voice details remain visible during play.')
                            )
                        )
                    ),
                    h('div', { className: 'voice-indicator-list' },
                        renderIndicator(speakerAction, showSpeaker, 'users-round'),
                        renderIndicator(statusAction, showStatus, 'mic')
                    )
                )
        )
    );
}

function TeleportWorkspaceView({ onPrompt } = {}) {
    const [locations, setLocations] = useState([]);
    const [search, setSearch] = useState('');

    const refreshLocations = useCallback(() => {
        fetchNui('cortex-admin:getSavedTeleportLocations').then((res) => res.json()).then((data) => setLocations(Array.isArray(data) ? data : []));
    }, []);

    useEffect(() => {
        refreshLocations();
    }, [refreshLocations]);

    const openPrompt = useCallback((config) => {
        if (!config || typeof config.onSubmit !== 'function') return;

        if (typeof onPrompt === 'function') {
            onPrompt(config);
            return;
        }

        const fields = Array.isArray(config.fields) ? config.fields : [];
        if (fields.length > 0) {
            const firstField = fields[0];
            const response = window.prompt(config.title || firstField.label || 'Enter value', firstField.initialValue || '');
            if (response === null) return;
            config.onSubmit({ [firstField.name]: response });
            return;
        }

        if (window.confirm(config.description || config.title || 'Confirm this action?')) {
            config.onSubmit({});
        }
    }, [onPrompt]);

    const filteredLocations = useMemo(() => {
        const query = search.trim().toLowerCase();
        return locations.filter((entry) => {
            if (!query) return true;
            return entry.name.toLowerCase().includes(query);
        });
    }, [locations, search]);

    const handleSaveCurrent = () => {
        openPrompt({
            title: 'Save current location',
            fields: [{ name: 'name', label: 'Location name', placeholder: 'Mission Row' }],
            onSubmit: (values) => {
                const name = values && values.name ? values.name.trim() : '';
                if (!name) return;
                fetchNui('cortex-admin:saveCurrentTeleportLocation', { name }).then(() => setTimeout(refreshLocations, 250));
            }
        });
    };

    const handleDelete = (entry) => {
        openPrompt({
            title: `Delete location: ${entry.name}?`,
            description: 'This removes the saved teleport location from cortex-admin.',
            fields: [],
            onSubmit: () => {
                fetchNui('cortex-admin:deleteSavedTeleportLocation', { name: entry.name }).then(() => setTimeout(refreshLocations, 250));
            }
        });
    };

    return React.createElement('div', { className: 'admin-teleport-workspace' },
        React.createElement('div', { className: 'admin-section' },
            React.createElement('div', { className: 'admin-section-title' }, 'Quick Teleport'),
            React.createElement('div', { className: 'admin-teleport-quick' },
                React.createElement('button', {
                    className: 'admin-button small appearance-action-button',
                    onClick: () => fetchNui('cortex-admin:action', { id: 'teleport.waypoint' })
                }, React.createElement(Icon, { name: 'map-pin', size: 14 }), React.createElement('span', null, 'Waypoint')),
                React.createElement('button', {
                    className: 'admin-button small appearance-action-button',
                    onClick: () => fetchNui('cortex-admin:action', { id: 'teleport.back' })
                }, React.createElement(Icon, { name: 'undo-2', size: 14 }), React.createElement('span', null, 'Back')),
                React.createElement('button', {
                    className: 'admin-button small success appearance-action-button',
                    onClick: handleSaveCurrent
                }, React.createElement(Icon, { name: 'bookmark', size: 14 }), React.createElement('span', null, 'Save Current'))
            )
        ),
        React.createElement('div', { className: 'admin-section' },
            React.createElement('div', { className: 'admin-section-title' }, 'Saved Locations'),
            React.createElement('div', { className: 'admin-teleport-library-toolbar' },
                React.createElement('div', { className: 'admin-search-wrapper' },
                    React.createElement(Icon, { name: 'search', size: 14, className: 'admin-search-icon' }),
                    React.createElement('input', {
                        type: 'text',
                        className: 'admin-search-input',
                        placeholder: 'Filter saved locations...',
                        value: search,
                        onChange: (e) => setSearch(e.target.value),
                        onKeyDown: (e) => e.stopPropagation()
                    })
                ),
                React.createElement('button', {
                    className: 'admin-button small appearance-action-button',
                    onClick: refreshLocations
                }, React.createElement(Icon, { name: 'refresh-cw', size: 14 }), React.createElement('span', null, 'Refresh'))
            ),
            filteredLocations.length === 0
                ? React.createElement('div', { className: 'admin-teleport-empty' },
                    React.createElement('div', { className: 'admin-teleport-empty-title' }, locations.length === 0 ? 'No saved locations yet' : 'No locations match this filter'),
                    React.createElement('div', { className: 'admin-teleport-empty-copy' }, locations.length === 0 ? 'Save your current position to build a reusable teleport library.' : 'Try a different search term or clear the filter.')
                )
                : React.createElement('div', { className: 'admin-teleport-list' },
                    React.createElement('div', { className: 'appearance-preset-list' },
                        filteredLocations.map((entry) => React.createElement('div', { className: 'appearance-preset-row admin-teleport-preset-row', key: entry.name },
                            React.createElement('div', { className: 'appearance-preset-main' },
                                React.createElement('div', { className: 'appearance-preset-name-row' },
                                    React.createElement('div', { className: 'appearance-preset-name', title: entry.name }, entry.name),
                                    React.createElement('div', { className: 'appearance-preset-badge' }, `${Number(entry.x).toFixed(1)}, ${Number(entry.y).toFixed(1)}`)
                                ),
                                React.createElement('div', { className: 'appearance-preset-subtitle' }, `Z ${Number(entry.z).toFixed(1)} • H ${Number(entry.h || 0).toFixed(1)}°`)
                            ),
                            React.createElement('div', { className: 'appearance-preset-actions' },
                                React.createElement('button', {
                                    className: 'admin-button small success appearance-action-button',
                                    onClick: () => fetchNui('cortex-admin:loadSavedTeleportLocation', { name: entry.name })
                                }, 'Load'),
                                React.createElement('button', {
                                    className: 'admin-button small danger appearance-action-button',
                                    onClick: () => handleDelete(entry)
                                }, 'Delete')
                            )
                        ))
                    )
                )
        )
    );
}

function VehicleView() {
    const [data, setData] = useState(null);
    const [phase, setPhase] = useState('loading');
    const [status, setStatus] = useState('Reading the vehicle you are driving…');
    const [catOpen, setCatOpen] = useState({
        mods: true,
        colors: false,
        wheels: false,
        extras: false,
        liveries: false,
        lights: false
    });

    const toggleCat = useCallback((key) => {
        setCatOpen((prev) => ({ ...prev, [key]: !prev[key] }));
    }, []);

    const refreshData = useCallback(async () => {
        setPhase('loading');
        const response = await fetchNui('cortex-admin:getVehicleCustomization');
        const payload = response && response.data;
        if (!response.ok || !payload || payload.ok === false || !payload.mods) {
            const reason = payload && payload.error;
            setData(null);
            setPhase(reason === 'forbidden' ? 'forbidden' : 'error');
            setStatus(reason === 'driver_required'
                ? 'Take the driver seat to customize this vehicle.'
                : reason === 'forbidden'
                    ? 'Your ACE role does not grant vehicle customization.'
                    : 'Drive a vehicle to open its customization controls.');
            return;
        }
        setData(payload);
        setPhase('ready');
        setStatus(`${payload.vehicle && payload.vehicle.label || 'Current vehicle'} · ${payload.vehicle && payload.vehicle.plate || 'no plate'}`);
    }, []);

    useEffect(() => {
        refreshData();
    }, [refreshData]);

    const visibleModCount = useMemo(() => {
        if (!data) return 0;
        return VehicleConfig.mods.filter((m) => {
            if (m.cat === 'Wheels') return false;
            const current = data.mods[m.id];
            return current && (current.isToggle || current.max > 0);
        }).length;
    }, [data]);

    const wheelsExtrasCount = useMemo(() => {
        if (!data) return 0;
        let n = 3;
        for (const m of VehicleConfig.mods.filter((x) => x.cat === 'Wheels')) {
            const current = data.mods[m.id];
            if (current && (current.isToggle || current.max > 0)) n += 1;
        }
        return n;
    }, [data]);

    useLayoutEffect(() => {
        if (!data) return;
        scheduleLucideIcons();
    }, [data, catOpen]);

    if (!data) return React.createElement('div', { className: 'admin-workspace vehicle-customizer-state' },
        React.createElement(WorkspaceHeader, {
            eyebrow: 'VEHICLE',
            title: 'Vehicle customizer',
            description: 'Native modifications, paint, liveries, extras, wheels and lighting.',
            actions: React.createElement('button', { type: 'button', className: 'admin-button', onClick: refreshData }, React.createElement(Icon, { name: 'refresh-cw', size: 14 }), 'Retry')
        }),
        React.createElement('div', { className: `admin-state-panel${phase === 'forbidden' || phase === 'error' ? ' error' : ''}`, role: phase === 'error' ? 'alert' : 'status' },
            React.createElement(Icon, { name: phase === 'loading' ? 'loader-circle' : phase === 'forbidden' ? 'lock-keyhole' : 'car-front', size: 22 }),
            React.createElement('strong', null, phase === 'loading' ? 'Reading vehicle' : phase === 'forbidden' ? 'Permission required' : 'Driver seat required'),
            React.createElement('span', null, status)
        )
    );

    const permissions = data.permissions || { mods: true, colors: true, liveries: true, extras: true, underglow: true, plate: true };

    const handleUpdate = async (type, id, value, isToggle, enabled) => {
        const response = await fetchNui('cortex-admin:setVehicleCustomization', { type, id, value, isToggle, enabled });
        if (!response.ok || !response.data || response.data.ok !== true) {
            setStatus(`Change rejected: ${response.data && response.data.error || response.error || 'request failed'}`);
            await refreshData();
            return false;
        }
        setStatus('Change applied');
        if (type === 'mod') {
            setData(prev => {
                const next = { ...prev };
                if (isToggle) {
                    next.mods[id] = { ...prev.mods[id], enabled };
                } else {
                    next.mods[id] = { ...prev.mods[id], current: value };
                }
                return next;
            });
        } else if (type === 'color') {
            setData(prev => ({
                ...prev,
                colors: { ...prev.colors, [id]: value },
                ...(id === 'primary' ? { customPrimary: { ...prev.customPrimary, enabled: false } } : {}),
                ...(id === 'secondary' ? { customSecondary: { ...prev.customSecondary, enabled: false } } : {})
            }));
        } else if (type === 'paintFinish') {
            setData(prev => ({ ...prev, paintFinish: { ...prev.paintFinish, [id]: value } }));
        } else if (type === 'customColor') {
            const key = id === 'primary' ? 'customPrimary' : 'customSecondary';
            setData(prev => ({ ...prev, [key]: { enabled: !!enabled, value: value || prev[key]?.value || [0, 0, 0] } }));
        } else if (type === 'xenonColor') {
            setData(prev => ({ ...prev, xenonColor: value }));
        } else if (type === 'neon') {
            const key = 'neon' + id.charAt(0).toUpperCase() + id.slice(1);
            if (id === 'all') {
                setData(prev => ({ ...prev, neonFront: value, neonBack: value, neonLeft: value, neonRight: value }));
            } else {
                setData(prev => ({ ...prev, [key]: value }));
            }
        } else if (type === 'neonColor') {
            setData(prev => ({ ...prev, neonColor: value }));
        } else if (type === 'tyreSmokeColor') {
            setData(prev => ({ ...prev, tyreSmokeColor: value }));
        } else if (type === 'livery') {
            setData(prev => ({ ...prev, livery: value }));
        } else if (type === 'extra') {
            setData(prev => ({ ...prev, extras: (prev.extras || []).map((extra) => extra.id === id ? { ...extra, enabled: !!enabled } : extra) }));
        } else if (type === 'enveff') {
            setData(prev => ({ ...prev, enveffScale: value }));
        } else {
            setData(prev => ({ ...prev, [type]: value }));
        }
        return true;
    };

    const renderSlider = (item) => {
        const current = data.mods[item.id];
        if (!current) return null;
        if (!current.isToggle && current.max <= 0) return null;

        if (item.isToggle || current.isToggle) {
            return React.createElement('div', { className: 'appearance-row', key: `mod-${item.id}` },
                React.createElement('div', { className: 'appearance-label' }, item.label),
                React.createElement('div', { className: 'appearance-control align-right' },
                    React.createElement('div', {
                        className: `admin-toggle${current.enabled ? ' active' : ''}`,
                        role: 'switch',
                        'aria-checked': current.enabled,
                        tabIndex: 0,
                        onKeyDown: (e) => {
                            if (e.key === 'Enter' || e.key === ' ') {
                                e.preventDefault();
                                handleUpdate('mod', item.id, null, true, !current.enabled);
                            }
                        },
                        onClick: () => handleUpdate('mod', item.id, null, true, !current.enabled)
                    })
                )
            );
        }

        const max = current.max - 1;
        const modName = (current.names && current.names[current.current]) || (current.current === -1 ? 'Stock' : `Mod ${current.current + 1}`);

        return React.createElement('div', { className: 'appearance-row mod-row', key: `mod-${item.id}` },
            React.createElement('div', { className: 'mod-info' },
                React.createElement('div', { className: 'mod-current-name' }, modName),
                React.createElement('div', { className: 'appearance-label' }, item.label)
            ),
            React.createElement('div', { className: 'appearance-control wide' },
                React.createElement('span', { className: 'appearance-value' }, `${current.current}/${max}`),
                React.createElement('input', {
                    type: 'range',
                    className: 'appearance-slider',
                    'aria-label': item.label,
                    min: -1,
                    max: max,
                    value: current.current,
                    onChange: (e) => handleUpdate('mod', item.id, parseInt(e.target.value))
                }),
                React.createElement('div', { className: 'appearance-btns' },
                    React.createElement('button', { className: 'appearance-btn', onClick: () => handleUpdate('mod', item.id, Math.max(-1, current.current - 1)) }, '−'),
                    React.createElement('button', { className: 'appearance-btn', onClick: () => handleUpdate('mod', item.id, Math.min(max, current.current + 1)) }, '+')
                )
            )
        );
    };

    const renderSection = (title, items) => {
        const validItems = items.filter(m => {
            const current = data.mods[m.id];
            return current && (current.isToggle || current.max > 0);
        });

        if (validItems.length === 0) return null;

        return React.createElement('div', { className: 'admin-section mod-section', key: title },
            React.createElement('div', { className: 'admin-section-title' }, title),
            validItems.map(m => renderSlider(m))
        );
    };

    const renderPermissionNotice = (label) => React.createElement('div', { className: 'admin-inline-empty permission' }, `Your ACE role does not grant ${label}.`);

    const renderRgbEditor = (id, label, stateKey) => {
        const colorState = data[stateKey] || { enabled: false, value: [0, 0, 0] };
        const color = [0, 1, 2].map((index) => clamp(Number(colorState.value && colorState.value[index]) || 0, 0, 255));
        const hex = `#${color.map((channel) => Math.round(channel).toString(16).padStart(2, '0')).join('')}`;
        const setColor = (next) => handleUpdate('customColor', id, next, false, true);

        return React.createElement('div', { className: 'vehicle-custom-rgb', key: id },
            React.createElement('div', { className: 'vehicle-custom-rgb-head' },
                React.createElement('div', null,
                    React.createElement('strong', null, label),
                    React.createElement('span', null, colorState.enabled ? `${color.join(', ')}` : 'Indexed color active')
                ),
                React.createElement('button', {
                    type: 'button',
                    className: `admin-option-toggle${colorState.enabled ? ' active' : ''}`,
                    'aria-label': `${colorState.enabled ? 'Disable' : 'Enable'} ${label}`,
                    'aria-pressed': !!colorState.enabled,
                    onClick: () => handleUpdate('customColor', id, color, false, !colorState.enabled)
                }, React.createElement('span', { className: 'admin-option-toggle-thumb' }))
            ),
            React.createElement('div', { className: 'vehicle-custom-rgb-controls' },
                React.createElement('input', {
                    type: 'color',
                    className: 'admin-color-input vehicle-custom-rgb-swatch',
                    value: hex,
                    'aria-label': `${label} color picker`,
                    onChange: (event) => {
                        const parsed = hexToRgb(event.target.value);
                        if (parsed) setColor([parsed.r, parsed.g, parsed.b]);
                    }
                }),
                ['Red', 'Green', 'Blue'].map((channelLabel, index) => React.createElement('label', { className: 'vehicle-custom-rgb-channel', key: channelLabel },
                    React.createElement('span', null, channelLabel, React.createElement('output', null, color[index])),
                    React.createElement('input', {
                        type: 'range',
                        min: 0,
                        max: 255,
                        value: color[index],
                        'aria-label': `${label} ${channelLabel}`,
                        onChange: (event) => {
                            const next = [...color];
                            next[index] = Number(event.target.value);
                            setColor(next);
                        }
                    })
                ))
            )
        );
    };

    return React.createElement('div', { className: 'admin-appearance vehicle-customizer' },
        React.createElement('div', { className: 'vehicle-customizer-toolbar' },
            React.createElement('div', null,
                React.createElement('span', { className: 'admin-section-kicker' }, 'CURRENT VEHICLE'),
                React.createElement('strong', null, data.vehicle && data.vehicle.label || 'Vehicle customizer'),
                React.createElement('small', { role: 'status', 'aria-live': 'polite' }, status)
            ),
            React.createElement('button', { type: 'button', className: 'admin-button', onClick: refreshData }, React.createElement(Icon, { name: 'refresh-cw', size: 14 }), 'Refresh')
        ),
        React.createElement('div', { className: 'appearance-content-area appearance-content-area--scroll' },
            React.createElement(AppearanceCollapsible, {
                title: 'Modifications',
                meta: String(visibleModCount),
                expanded: catOpen.mods,
                onToggle: () => toggleCat('mods')
            }, permissions.mods ? React.createElement(React.Fragment, null,
                renderSection('Performance', VehicleConfig.mods.filter(m => m.cat === 'Performance')),
                renderSection('Exterior', VehicleConfig.mods.filter(m => m.cat === 'Exterior')),
                renderSection('Interior', VehicleConfig.mods.filter(m => m.cat === 'Interior')),
                renderSection('Engine Bay', VehicleConfig.mods.filter(m => m.cat === 'Engine')),
                renderSection('Misc', VehicleConfig.mods.filter(m => m.cat === 'Misc'))
            ) : renderPermissionNotice('vehicle modifications')),
            React.createElement(AppearanceCollapsible, {
                title: 'Colors',
                meta: permissions.colors ? 'Indexed · RGB · Finish' : 'Locked',
                expanded: catOpen.colors,
                onToggle: () => toggleCat('colors')
            }, permissions.colors ? React.createElement(React.Fragment, null,
                React.createElement('div', { className: 'admin-section' },
                    React.createElement('div', { className: 'admin-section-title' }, 'Indexed colors'),
                    VehicleConfig.colors.map(c => React.createElement('div', { className: 'appearance-row', key: c.id },
                        React.createElement('div', { className: 'appearance-label' }, c.label),
                        React.createElement('div', { className: 'appearance-control wide' },
                            React.createElement('span', { className: 'appearance-value' }, data.colors[c.id]),
                            React.createElement('input', {
                                type: 'range',
                                className: 'appearance-slider',
                                'aria-label': c.label,
                                min: 0,
                                max: 160,
                                value: Math.min(160, data.colors[c.id] || 0),
                                onChange: (e) => handleUpdate('color', c.id, parseInt(e.target.value))
                            }),
                            React.createElement('div', { className: 'appearance-btns' },
                                React.createElement('button', { type: 'button', className: 'appearance-btn', onClick: () => handleUpdate('color', c.id, Math.max(0, Math.min(160, data.colors[c.id] || 0) - 1)) }, '−'),
                                React.createElement('button', { type: 'button', className: 'appearance-btn', onClick: () => handleUpdate('color', c.id, Math.min(160, (data.colors[c.id] || 0) + 1)) }, '+')
                            )
                        )
                    )),
                    ['primary', 'secondary'].map((id) => React.createElement('div', { className: 'appearance-row', key: `chameleon-${id}` },
                        React.createElement('div', { className: 'appearance-label' }, `${id === 'primary' ? 'Primary' : 'Secondary'} Chameleon`),
                        React.createElement(CustomSelect, {
                            options: [{ label: 'Choose chameleon…', value: '' }, ...VehicleConfig.chameleonColors],
                            value: data.colors[id] >= 223 && data.colors[id] <= 238 ? data.colors[id] : '',
                            ariaLabel: `${id} chameleon color`,
                            onChange: (value) => value !== '' && handleUpdate('color', id, value)
                        })
                    ))
                ),
                React.createElement('div', { className: 'admin-section vehicle-paint-section' },
                    React.createElement('div', { className: 'admin-section-title' }, 'Paint finish & fade'),
                    ['primary', 'secondary'].map((id) => React.createElement('div', { className: 'appearance-row', key: `finish-${id}` },
                        React.createElement('div', { className: 'appearance-label' }, `${id === 'primary' ? 'Primary' : 'Secondary'} Finish`),
                        React.createElement(CustomSelect, {
                            options: VehicleConfig.paintFinishes,
                            value: data.paintFinish && data.paintFinish[id] || 0,
                            ariaLabel: `${id} paint finish`,
                            onChange: (value) => handleUpdate('paintFinish', id, value)
                        })
                    )),
                    React.createElement('div', { className: 'appearance-row' },
                        React.createElement('div', { className: 'appearance-label' }, 'Environment Effect'),
                        React.createElement('div', { className: 'appearance-control wide' },
                            React.createElement('span', { className: 'appearance-value' }, `${Math.round(Number(data.enveffScale || 0) * 100)}%`),
                            React.createElement('input', {
                                type: 'range', className: 'appearance-slider', min: 0, max: 1, step: 0.05,
                                value: Number(data.enveffScale || 0), 'aria-label': 'Vehicle environment effect',
                                onChange: (event) => handleUpdate('enveff', null, Number(event.target.value))
                            })
                        )
                    )
                ),
                React.createElement('div', { className: 'admin-section' },
                    React.createElement('div', { className: 'admin-section-title' }, 'Custom RGB'),
                    renderRgbEditor('primary', 'Primary custom color', 'customPrimary'),
                    renderRgbEditor('secondary', 'Secondary custom color', 'customSecondary')
                )
            ) : renderPermissionNotice('vehicle colors')),
            React.createElement(AppearanceCollapsible, {
                title: 'Wheels & fitment',
                meta: String(wheelsExtrasCount),
                expanded: catOpen.wheels,
                onToggle: () => toggleCat('wheels')
            }, React.createElement('div', { className: 'admin-section' },
                React.createElement('div', { className: 'appearance-row' },
                    React.createElement('div', { className: 'appearance-label' }, 'Wheel Type'),
                    React.createElement(CustomSelect, {
                        options: VehicleConfig.wheelTypes,
                        value: data.wheelType,
                        disabled: !permissions.mods,
                        onChange: (v) => handleUpdate('wheelType', null, v)
                    })
                ),
                permissions.mods ? renderSection('Wheels', VehicleConfig.mods.filter(m => m.cat === 'Wheels')) : renderPermissionNotice('wheel modifications'),
                React.createElement('div', { className: 'appearance-row' },
                    React.createElement('div', { className: 'appearance-label' }, 'Plate Type'),
                    React.createElement(CustomSelect, {
                        options: VehicleConfig.plates,
                        value: data.plate,
                        disabled: !permissions.plate,
                        onChange: (v) => handleUpdate('plate', null, v)
                    })
                ),
                React.createElement('div', { className: 'appearance-row' },
                    React.createElement('div', { className: 'appearance-label' }, 'Window Tint'),
                    React.createElement(CustomSelect, {
                        options: VehicleConfig.windows,
                        value: data.windowTint,
                        disabled: !permissions.mods,
                        onChange: (v) => handleUpdate('window', null, v)
                    })
                )
            )),
            React.createElement(AppearanceCollapsible, {
                title: 'Vehicle extras',
                meta: permissions.extras ? String((data.extras || []).length) : 'Locked',
                expanded: catOpen.extras,
                onToggle: () => toggleCat('extras')
            }, permissions.extras
                ? ((data.extras || []).length === 0
                    ? React.createElement('div', { className: 'admin-inline-empty' }, 'This vehicle model has no native extras.')
                    : React.createElement('div', { className: 'vehicle-custom-extra-grid' }, (data.extras || []).map((extra) => React.createElement('button', {
                        type: 'button',
                        className: `vehicle-custom-extra${extra.enabled ? ' active' : ''}`,
                        key: extra.id,
                        'aria-pressed': !!extra.enabled,
                        onClick: () => handleUpdate('extra', extra.id, null, false, !extra.enabled)
                    },
                        React.createElement('span', { className: 'vehicle-custom-extra-id' }, String(extra.id).padStart(2, '0')),
                        React.createElement('span', null, extra.label || `Extra #${extra.id}`),
                        React.createElement('small', null, extra.enabled ? 'On' : 'Off')
                    )))
                ) : renderPermissionNotice('vehicle extras')),
            React.createElement(AppearanceCollapsible, {
                title: 'Native liveries',
                meta: permissions.liveries ? String((data.liveries || []).length) : 'Locked',
                expanded: catOpen.liveries,
                onToggle: () => toggleCat('liveries')
            }, permissions.liveries
                ? ((data.liveries || []).length === 0
                    ? React.createElement('div', { className: 'admin-inline-empty' }, 'This vehicle has no native livery set. Mod-slot liveries remain under Modifications.')
                    : React.createElement('div', { className: 'admin-section' },
                        React.createElement('div', { className: 'appearance-row' },
                            React.createElement('div', { className: 'appearance-label' }, 'Livery'),
                            React.createElement(CustomSelect, {
                                options: data.liveries,
                                value: data.livery,
                                ariaLabel: 'Native vehicle livery',
                                onChange: (value) => handleUpdate('livery', null, value)
                            })
                        )
                    )) : renderPermissionNotice('vehicle liveries')),
            React.createElement(AppearanceCollapsible, {
                title: 'Lights',
                expanded: catOpen.lights,
                onToggle: () => toggleCat('lights')
            }, React.createElement(React.Fragment, null,
                React.createElement('div', { className: 'admin-section' },
                    React.createElement('div', { className: 'admin-section-title' }, 'Xenon Headlights'),
                    React.createElement('div', { className: 'appearance-row' },
                        React.createElement('div', { className: 'appearance-label' }, 'Xenon Lights'),
                        React.createElement('div', { className: 'appearance-control align-right' },
                            React.createElement('button', {
                                type: 'button',
                                className: `admin-toggle${data.mods['22']?.enabled ? ' active' : ''}`,
                                role: 'switch',
                                'aria-checked': !!data.mods['22']?.enabled,
                                disabled: !permissions.mods,
                                onClick: () => handleUpdate('mod', 22, null, true, !data.mods['22']?.enabled)
                            })
                        )
                    ),
                    React.createElement('div', { className: 'appearance-row' },
                        React.createElement('div', { className: 'appearance-label' }, 'Xenon Color'),
                        React.createElement(CustomSelect, {
                            options: VehicleConfig.xenonColors,
                            value: data.xenonColor ?? 255,
                            disabled: !permissions.mods,
                            onChange: (v) => handleUpdate('xenonColor', null, v)
                        })
                    )
                ),
                React.createElement('div', { className: 'admin-section' },
                    React.createElement('div', { className: 'admin-section-title' }, 'Neon Lights'),
                    React.createElement('div', { className: 'appearance-row' },
                        React.createElement('div', { className: 'appearance-label' }, 'All Neons'),
                        React.createElement('div', { className: 'appearance-control align-right' },
                            React.createElement('button', {
                                type: 'button',
                                className: `admin-toggle${(data.neonFront && data.neonBack && data.neonLeft && data.neonRight) ? ' active' : ''}`,
                                role: 'switch',
                                'aria-checked': !!(data.neonFront && data.neonBack && data.neonLeft && data.neonRight),
                                disabled: !permissions.underglow,
                                onClick: () => {
                                    const allOn = data.neonFront && data.neonBack && data.neonLeft && data.neonRight;
                                    handleUpdate('neon', 'all', !allOn);
                                }
                            })
                        )
                    ),
                    React.createElement('div', { className: 'appearance-row' },
                        React.createElement('div', { className: 'appearance-label' }, 'Front'),
                        React.createElement('div', { className: 'appearance-control align-right' },
                            React.createElement('button', {
                                type: 'button',
                                className: `admin-toggle${data.neonFront ? ' active' : ''}`,
                                role: 'switch',
                                'aria-checked': !!data.neonFront,
                                disabled: !permissions.underglow,
                                onClick: () => handleUpdate('neon', 'front', !data.neonFront)
                            })
                        )
                    ),
                    React.createElement('div', { className: 'appearance-row' },
                        React.createElement('div', { className: 'appearance-label' }, 'Back'),
                        React.createElement('div', { className: 'appearance-control align-right' },
                            React.createElement('button', {
                                type: 'button',
                                className: `admin-toggle${data.neonBack ? ' active' : ''}`,
                                role: 'switch',
                                'aria-checked': !!data.neonBack,
                                disabled: !permissions.underglow,
                                onClick: () => handleUpdate('neon', 'back', !data.neonBack)
                            })
                        )
                    ),
                    React.createElement('div', { className: 'appearance-row' },
                        React.createElement('div', { className: 'appearance-label' }, 'Left'),
                        React.createElement('div', { className: 'appearance-control align-right' },
                            React.createElement('button', {
                                type: 'button',
                                className: `admin-toggle${data.neonLeft ? ' active' : ''}`,
                                role: 'switch',
                                'aria-checked': !!data.neonLeft,
                                disabled: !permissions.underglow,
                                onClick: () => handleUpdate('neon', 'left', !data.neonLeft)
                            })
                        )
                    ),
                    React.createElement('div', { className: 'appearance-row' },
                        React.createElement('div', { className: 'appearance-label' }, 'Right'),
                        React.createElement('div', { className: 'appearance-control align-right' },
                            React.createElement('button', {
                                type: 'button',
                                className: `admin-toggle${data.neonRight ? ' active' : ''}`,
                                role: 'switch',
                                'aria-checked': !!data.neonRight,
                                disabled: !permissions.underglow,
                                onClick: () => handleUpdate('neon', 'right', !data.neonRight)
                            })
                        )
                    ),
                    React.createElement('div', { className: 'admin-section-title', style: { marginTop: '1rem' } }, 'Neon Color'),
                    ['Red', 'Green', 'Blue'].map((label, idx) => React.createElement('div', { className: 'appearance-row', key: `neon-${label}` },
                        React.createElement('div', { className: 'appearance-label' }, label),
                        React.createElement('div', { className: 'appearance-control wide' },
                            React.createElement('span', { className: 'appearance-value' }, (data.neonColor && data.neonColor[idx]) || 0),
                            React.createElement('input', {
                                type: 'range',
                                className: 'appearance-slider',
                                'aria-label': `Neon ${label}`,
                                min: 0,
                                max: 255,
                                disabled: !permissions.underglow,
                                value: (data.neonColor && data.neonColor[idx]) || 0,
                                onChange: (e) => {
                                    const newColor = [...(data.neonColor || [0, 0, 0])];
                                    newColor[idx] = parseInt(e.target.value);
                                    handleUpdate('neonColor', null, newColor);
                                }
                            })
                        )
                    ))
                ),
                React.createElement('div', { className: 'admin-section' },
                    React.createElement('div', { className: 'admin-section-title' }, 'Tire Smoke'),
                    React.createElement('div', { className: 'appearance-row' },
                        React.createElement('div', { className: 'appearance-label' }, 'Tire Smoke'),
                        React.createElement('div', { className: 'appearance-control align-right' },
                            React.createElement('button', {
                                type: 'button',
                                className: `admin-toggle${data.mods['20']?.enabled ? ' active' : ''}`,
                                role: 'switch',
                                'aria-checked': !!data.mods['20']?.enabled,
                                disabled: !permissions.mods,
                                onClick: () => handleUpdate('mod', 20, null, true, !data.mods['20']?.enabled)
                            })
                        )
                    ),
                    React.createElement('div', { className: 'admin-section-title', style: { marginTop: '1rem' } }, 'Smoke Color'),
                    ['Red', 'Green', 'Blue'].map((label, idx) => React.createElement('div', { className: 'appearance-row', key: `smoke-${label}` },
                        React.createElement('div', { className: 'appearance-label' }, label),
                        React.createElement('div', { className: 'appearance-control wide' },
                            React.createElement('span', { className: 'appearance-value' }, (data.tyreSmokeColor && data.tyreSmokeColor[idx]) || 0),
                            React.createElement('input', {
                                type: 'range',
                                className: 'appearance-slider',
                                'aria-label': `Tire smoke ${label}`,
                                min: 0,
                                max: 255,
                                disabled: !permissions.colors,
                                value: (data.tyreSmokeColor && data.tyreSmokeColor[idx]) || 0,
                                onChange: (e) => {
                                    const newColor = [...(data.tyreSmokeColor || [0, 0, 0])];
                                    newColor[idx] = parseInt(e.target.value);
                                    handleUpdate('tyreSmokeColor', null, newColor);
                                }
                            })
                        )
                    ))
                )
            ))
        )
    );
}

function VehicleTuningView() {
    const [snapshot, setSnapshot] = useState(null);
    const [activeGroup, setActiveGroup] = useState('Powertrain');
    const [loading, setLoading] = useState(true);
    const [status, setStatus] = useState({ tone: 'neutral', text: 'Reading current vehicle...' });
    const [customAudio, setCustomAudio] = useState('');
    const [pendingReset, setPendingReset] = useState(null);
    const pendingFieldTimers = React.useRef(new Map());
    const tuningRequestVersion = React.useRef(0);

    const loadSnapshot = useCallback(async () => {
        setLoading(true);
        setStatus({ tone: 'neutral', text: 'Reading current vehicle...' });
        const response = await fetchNui('cortex-admin:getVehicleTuning');
        const payload = response.data || {};

        if (!response.ok || payload.ok !== true) {
            setSnapshot(null);
            setStatus({ tone: 'error', text: payload.message || 'Live tuning could not find a drivable vehicle.' });
            setLoading(false);
            return;
        }

        setSnapshot(payload);
        setCustomAudio(payload.audio && payload.audio.value ? payload.audio.value : '');
        const nextFields = Array.isArray(payload.fields) ? payload.fields : [];
        const firstGroup = nextFields[0] ? nextFields[0].group : 'Powertrain';
        setActiveGroup((current) => nextFields.some((field) => field.group === current) ? current : firstGroup);
        setStatus({ tone: 'live', text: 'Live values are connected to this vehicle.' });
        setLoading(false);
    }, []);

    useEffect(() => {
        loadSnapshot();
        return () => {
            pendingFieldTimers.current.forEach((timerId) => window.clearTimeout(timerId));
            pendingFieldTimers.current.clear();
        };
    }, [loadSnapshot]);

    const updateFieldLocally = useCallback((fieldId, value) => {
        setSnapshot((current) => {
            if (!current || !Array.isArray(current.fields)) return current;
            return {
                ...current,
                fields: current.fields.map((field) => field.id === fieldId ? { ...field, value } : field)
            };
        });
    }, []);

    const commitField = useCallback(async (fieldId, value) => {
        const requestVersion = tuningRequestVersion.current;
        const response = await fetchNui('cortex-admin:setVehicleHandling', { field: fieldId, value });
        const payload = response.data || {};
        if (!response.ok || payload.ok !== true) {
            if (requestVersion !== tuningRequestVersion.current) return;
            setStatus({ tone: 'error', text: payload.message || 'The handling value was rejected.' });
            return;
        }

        if (requestVersion !== tuningRequestVersion.current) return;

        if (Number.isFinite(Number(payload.value))) {
            updateFieldLocally(fieldId, Number(payload.value));
        }
        setStatus({ tone: 'live', text: 'Handling applied in real time.' });
    }, [updateFieldLocally]);

    const queueField = useCallback((field, rawValue, immediate = false) => {
        const numericValue = clamp(Number(rawValue), Number(field.min), Number(field.max));
        if (!Number.isFinite(numericValue)) return;

        updateFieldLocally(field.id, numericValue);
        const existingTimer = pendingFieldTimers.current.get(field.id);
        if (existingTimer) window.clearTimeout(existingTimer);

        if (immediate) {
            pendingFieldTimers.current.delete(field.id);
            commitField(field.id, numericValue);
            return;
        }

        const timerId = window.setTimeout(() => {
            pendingFieldTimers.current.delete(field.id);
            commitField(field.id, numericValue);
        }, 90);
        pendingFieldTimers.current.set(field.id, timerId);
    }, [commitField, updateFieldLocally]);

    const resetTuning = useCallback(async (scope) => {
        pendingFieldTimers.current.forEach((timerId) => window.clearTimeout(timerId));
        pendingFieldTimers.current.clear();
        if (scope !== 'audio') tuningRequestVersion.current += 1;
        setPendingReset(scope);
        setStatus({ tone: 'neutral', text: scope === 'audio' ? 'Restoring factory engine audio...' : 'Restoring captured handling...' });
        try {
            const response = await fetchNui('cortex-admin:resetVehicleTuning', { scope });
            const payload = response.data || {};

            if (!response.ok || payload.ok !== true) {
                setStatus({ tone: 'error', text: payload.message || 'The baseline could not be restored.' });
                return;
            }

            if (scope === 'audio') {
                setSnapshot((current) => current ? { ...current, audio: { ...current.audio, value: '' } } : current);
                setCustomAudio('');
            } else {
                setSnapshot(payload);
            }
            setStatus({ tone: 'live', text: scope === 'audio' ? 'Factory engine audio restored.' : 'Captured handling restored.' });
        } finally {
            setPendingReset(null);
        }
    }, []);

    const resetField = useCallback(async (field) => {
        if (!field) return;

        tuningRequestVersion.current += 1;

        const existingTimer = pendingFieldTimers.current.get(field.id);
        if (existingTimer) {
            window.clearTimeout(existingTimer);
            pendingFieldTimers.current.delete(field.id);
        }

        setPendingReset(field.id);
        setStatus({ tone: 'neutral', text: `Restoring ${field.label} to its captured default...` });

        try {
            const response = await fetchNui('cortex-admin:resetVehicleTuningField', { field: field.id });
            const payload = response.data || {};
            if (!response.ok || payload.ok !== true) {
                setStatus({ tone: 'error', text: payload.message || `Could not restore ${field.label}.` });
                return;
            }

            const restoredValue = Number.isFinite(Number(payload.value))
                ? Number(payload.value)
                : Number(field.defaultValue);
            updateFieldLocally(field.id, restoredValue);
            setStatus({ tone: 'live', text: `${field.label} restored to its captured default.` });
        } finally {
            setPendingReset(null);
        }
    }, [updateFieldLocally]);

    const applyAudio = useCallback(async (soundName) => {
        const normalized = String(soundName || '').trim();
        if (!normalized) {
            resetTuning('audio');
            return;
        }

        setStatus({ tone: 'neutral', text: `Loading ${normalized} engine audio...` });
        const response = await fetchNui('cortex-admin:setVehicleEngineAudio', { soundName: normalized });
        const payload = response.data || {};
        if (!response.ok || payload.ok !== true) {
            setStatus({ tone: 'error', text: payload.message || 'That engine audio name could not be applied.' });
            return;
        }

        setSnapshot((current) => current ? { ...current, audio: { ...current.audio, value: payload.value || normalized } } : current);
        setCustomAudio(payload.value || normalized);
        setStatus({ tone: 'live', text: `${payload.value || normalized} engine audio is active.` });
    }, [resetTuning]);

    if (loading && !snapshot) {
        return React.createElement('div', { className: 'admin-tuning-state', role: 'status' },
            React.createElement('div', { className: 'admin-tuning-state-icon' }, React.createElement(Icon, { name: 'gauge', size: 24 })),
            React.createElement('strong', null, 'Connecting live tuning'),
            React.createElement('span', null, status.text)
        );
    }

    if (!snapshot) {
        return React.createElement('div', { className: 'admin-tuning-state admin-tuning-state--error', role: 'alert' },
            React.createElement('div', { className: 'admin-tuning-state-icon' }, React.createElement(Icon, { name: 'car-front', size: 24 })),
            React.createElement('strong', null, 'No tuning target'),
            React.createElement('span', null, status.text),
            React.createElement('button', { type: 'button', className: 'admin-button small', onClick: loadSnapshot }, 'Try again')
        );
    }

    const fields = Array.isArray(snapshot.fields) ? snapshot.fields : [];
    const groups = [...new Set(fields.map((field) => field.group).filter(Boolean))];
    const activeFields = fields.filter((field) => field.group === activeGroup);
    const modifiedCount = fields.filter((field) => Math.abs(Number(field.value) - Number(field.defaultValue)) > 0.0001).length;
    const audio = snapshot.audio || { value: '', defaultValue: '', presets: [] };
    const baseAudioOptions = [
        { label: `Factory (${audio.defaultValue || 'vehicle default'})`, value: '' },
        ...(Array.isArray(audio.presets) ? audio.presets : [])
    ];
    const audioOptions = audio.value && !baseAudioOptions.some((option) => String(option.value) === String(audio.value))
        ? [{ label: `${audio.value} (active)`, value: audio.value }, ...baseAudioOptions]
        : baseAudioOptions;
    const audioChanged = Boolean(audio.value)
        && String(audio.value).toUpperCase() !== String(audio.defaultValue || '').toUpperCase();

    return React.createElement('div', { className: 'admin-tuning-workspace' },
        React.createElement('header', { className: 'admin-tuning-hero' },
            React.createElement('div', { className: 'admin-tuning-hero-main' },
                React.createElement('div', { className: 'admin-tuning-eyebrow' }, 'Live vehicle data'),
                React.createElement('h2', null, snapshot.vehicle.label || 'Current vehicle'),
                React.createElement('div', { className: 'admin-tuning-vehicle-meta' },
                    React.createElement('code', null, snapshot.vehicle.model || 'UNKNOWN'),
                    snapshot.vehicle.plate && React.createElement('span', null, snapshot.vehicle.plate)
                )
            ),
            React.createElement('div', { className: 'admin-tuning-hero-actions' },
                React.createElement('button', { type: 'button', className: 'admin-button small', onClick: loadSnapshot },
                    React.createElement(Icon, { name: 'refresh-cw', size: 13 }), 'Refresh target'
                )
            )
        ),

        React.createElement('div', { className: 'admin-tuning-status-line', 'aria-live': 'polite' },
            React.createElement('span', { className: `admin-tuning-status-dot ${status.tone}` }),
            React.createElement('span', null, status.text),
            React.createElement('strong', null, `${modifiedCount} changed`),
            status.tone === 'error' && React.createElement('span', { className: 'admin-tuning-status-tag' }, 'Target unavailable')
        ),

        React.createElement('section', { className: 'admin-tuning-audio', 'aria-labelledby': 'tuning-audio-title' },
            React.createElement('div', { className: 'admin-tuning-section-copy' },
                React.createElement(Icon, { name: 'audio-waveform', size: 14, className: 'admin-tuning-section-icon' }),
                React.createElement('div', null,
                    React.createElement('h3', { id: 'tuning-audio-title' }, 'Engine audio'),
                    React.createElement('p', null, 'Choose a preset or apply an installed audioNameHash.'),
                    React.createElement('div', { className: 'admin-tuning-setting-baseline' },
                        'Default ', React.createElement('code', null, audio.defaultValue || 'vehicle default')
                    )
                )
            ),
            React.createElement('div', { className: 'admin-tuning-audio-controls' },
                React.createElement(CustomSelect, {
                    options: audioOptions,
                    value: audio.value || '',
                    ariaLabel: 'Engine audio preset',
                    onChange: applyAudio
                }),
                React.createElement('div', { className: 'admin-tuning-audio-custom' },
                    React.createElement('input', {
                        type: 'text',
                        value: customAudio,
                        maxLength: 64,
                        placeholder: 'Custom audio name',
                        'aria-label': 'Custom engine audio name',
                        onChange: (event) => setCustomAudio(event.target.value),
                        onKeyDown: (event) => {
                            if (event.key === 'Enter') applyAudio(customAudio);
                        }
                    }),
                    React.createElement('button', { type: 'button', className: 'admin-button small success', disabled: !customAudio.trim(), onClick: () => applyAudio(customAudio) }, 'Apply')
                ),
                React.createElement('button', {
                    type: 'button',
                    className: `admin-tuning-restore${audioChanged ? ' is-changed' : ''}`,
                    disabled: !audioChanged || Boolean(pendingReset),
                    onClick: () => resetTuning('audio'),
                    title: 'Restore engine audio to the captured default'
                },
                    React.createElement(Icon, { name: 'rotate-ccw', size: 13 }),
                    React.createElement('span', null, 'Restore default')
                )
            )
        ),

        React.createElement('section', { className: 'admin-tuning-handling', 'aria-labelledby': 'tuning-handling-title' },
            React.createElement('div', { className: 'admin-tuning-handling-header' },
                React.createElement('div', { className: 'admin-tuning-section-copy' },
                    React.createElement(Icon, { name: 'sliders-horizontal', size: 14, className: 'admin-tuning-section-icon' }),
                    React.createElement('div', null,
                        React.createElement('h3', { id: 'tuning-handling-title' }, 'Handling channels'),
                        React.createElement('p', null, 'Every adjustment is written to CHandlingData while you move it.')
                    )
                ),
                React.createElement('button', { type: 'button', className: 'admin-button small admin-tuning-global-reset', disabled: modifiedCount === 0 || Boolean(pendingReset), onClick: () => resetTuning('handling'), title: 'Restore every handling setting to its captured default' },
                    React.createElement(Icon, { name: 'rotate-ccw', size: 13 }), 'Restore all'
                )
            ),
            React.createElement('div', { className: 'admin-tuning-group-tabs', role: 'tablist', 'aria-label': 'Handling category' },
                groups.map((group) => React.createElement('button', {
                    key: group,
                    type: 'button',
                    role: 'tab',
                    'aria-selected': activeGroup === group,
                    className: activeGroup === group ? 'active' : '',
                    onClick: () => setActiveGroup(group)
                }, group))
            ),
            React.createElement('div', { className: 'admin-tuning-field-grid' },
                activeFields.map((field) => {
                    const value = Number(field.value);
                    const precision = Number.isInteger(Number(field.precision)) ? Number(field.precision) : 2;
                    const changed = Math.abs(value - Number(field.defaultValue)) > 0.0001;
                    const formattedDefault = Number(field.defaultValue).toFixed(precision);
                    return React.createElement('div', { className: `admin-tuning-field${changed ? ' changed' : ''}`, key: field.id },
                        React.createElement('div', { className: 'admin-tuning-field-head' },
                            React.createElement('div', null,
                                React.createElement('label', { htmlFor: `tune-${field.id}` }, field.label),
                                React.createElement('span', null, field.description)
                            ),
                            React.createElement('div', { className: 'admin-tuning-field-head-actions' },
                                changed && React.createElement('span', { className: 'admin-tuning-modified' }, 'Edited'),
                                React.createElement('button', {
                                    type: 'button',
                                    className: `admin-tuning-restore${changed ? ' is-changed' : ''}`,
                                    disabled: !changed || Boolean(pendingReset),
                                    onClick: () => resetField(field),
                                    title: `Restore ${field.label} to ${formattedDefault}`,
                                    'aria-label': `Restore ${field.label} to its captured default`
                                },
                                    React.createElement(Icon, { name: 'rotate-ccw', size: 12 }),
                                    React.createElement('span', null, 'Restore default')
                                )
                            )
                        ),
                        React.createElement('div', { className: 'admin-tuning-field-controls' },
                            React.createElement('input', {
                                id: `tune-${field.id}`,
                                type: 'range',
                                'aria-label': field.label,
                                min: field.min,
                                max: field.max,
                                step: field.step,
                                value,
                                onChange: (event) => queueField(field, event.target.value),
                                onPointerUp: (event) => queueField(field, event.currentTarget.value, true),
                                onKeyUp: (event) => {
                                    if (event.key === 'ArrowLeft' || event.key === 'ArrowRight' || event.key === 'Home' || event.key === 'End') {
                                        queueField(field, event.currentTarget.value, true);
                                    }
                                }
                            }),
                            React.createElement('div', { className: 'admin-tuning-number-wrap' },
                                React.createElement('input', {
                                    type: 'number',
                                    min: field.min,
                                    max: field.max,
                                    step: field.step,
                                    value: Number.isFinite(value) ? value.toFixed(precision) : '',
                                    'aria-label': `${field.label} value`,
                                    onChange: (event) => updateFieldLocally(field.id, Number(event.target.value)),
                                    onBlur: (event) => queueField(field, event.target.value, true),
                                    onKeyDown: (event) => {
                                        if (event.key === 'Enter') {
                                            queueField(field, event.currentTarget.value, true);
                                            event.currentTarget.blur();
                                        }
                                    }
                                }),
                                field.unit && React.createElement('span', null, field.unit)
                            )
                        ),
                        React.createElement('div', { className: 'admin-tuning-field-baseline' },
                            'Default ', formattedDefault, field.unit ? ` ${field.unit}` : ''
                        )
                    );
                })
            )
        ),
        React.createElement('p', { className: 'admin-tuning-footnote' },
            'Changes apply instantly to the current vehicle. Defaults are captured when this editor opens and are restored when the session ends.'
        )
    );
}

// Sidebar Navigation Component with FontAwesome icons
// Framework-specific items (inventory, garage) are conditionally included
const baseSidebarItems = [
    { id: 'all', label: 'All Commands', lucide: 'zap', tab: 'all' },
    { id: 'favorites', label: 'Favorites', lucide: 'star-filled', tab: 'favorites' },
    { type: 'divider' },
    { id: 'player', label: 'Player', lucide: 'user', tab: 'player' },
    { id: 'vehicle', label: 'Vehicle', lucide: 'car', tab: 'vehicle' },
    { id: 'vehicle_tuning', label: 'Live Vehicle Tuning', lucide: 'gauge', tab: 'vehicle_tuning', requiresPermission: 'vehicle.liveTuning' },
    { id: 'world', label: 'World', lucide: 'globe', tab: 'world' },
    { id: 'weapons', label: 'Weapons', lucide: 'crosshair', tab: 'weapons' },
    { id: 'voice', label: 'Voice Chat', lucide: 'radio', tab: 'voice' },
    { id: 'teleport', label: 'Teleport', lucide: 'map-pin', tab: 'teleport' },
    { id: 'appearance', label: 'Appearance', lucide: 'shirt', tab: 'appearance' },
    { id: 'vehicle_custom', label: 'Vehicle Customizer', lucide: 'palette', tab: 'vehicle_custom', requiresAnyPermissions: ['vehicle.customMods', 'vehicle.customColors', 'vehicle.customLiveries', 'vehicle.customExtras', 'vehicle.customUnderglow', 'vehicle.plateType'] },
    { id: 'inventory', label: 'Inventory', lucide: 'package', tab: 'inventory', requiresFramework: 'inventory' },
    { id: 'garage', label: 'Garage', lucide: 'warehouse', tab: 'garage', requiresFramework: 'garage' },
];

const sidebarFooterNavItems = [
    { id: 'migration', label: 'Import vMenu', lucide: 'download', tab: 'migration' },
    { id: 'imported', label: 'Imported Data', lucide: 'archive', tab: 'imported' },
    { id: 'bans', label: 'Banned Players', lucide: 'shield-ban', tab: 'bans' },
    { id: 'dev', label: 'Dev Tools', lucide: 'code', tab: 'dev' },
    { id: 'recording', label: 'Recording', lucide: 'video', tab: 'recording' },
    { id: 'options', label: 'Options', lucide: 'settings', tab: 'options' },
    { id: 'server', label: 'Server Resources', lucide: 'server', tab: 'server' },
];

function Sidebar({ activeView, onViewChange, activeTab, frameworkInfo, allowed }) {
    const sidebarItems = useMemo(() => {
        return baseSidebarItems.filter(item => {
            if (item.requiresPermission && allowed && allowed[item.requiresPermission] === false) return false;
            if (item.requiresAnyPermissions && allowed && !item.requiresAnyPermissions.some((permission) => allowed[permission] === true)) return false;
            if (!item.requiresFramework) return true;
            if (item.requiresFramework === 'inventory') return frameworkInfo && frameworkInfo.hasInventory;
            if (item.requiresFramework === 'garage') return frameworkInfo && frameworkInfo.hasGarage;
            return true;
        });
    }, [frameworkInfo, allowed]);
    return React.createElement('div', { className: 'admin-sidebar' },
        React.createElement('div', { className: 'admin-sidebar-items' },
            sidebarItems.map((item, index) => {
                if (item.type === 'divider') {
                    return React.createElement('div', { key: `divider-${index}`, className: 'admin-sidebar-divider' });
                }

                const isActive = activeTab === item.tab;
                return React.createElement('button', {
                    key: item.id,
                    type: 'button',
                    className: `admin-sidebar-item ${item.id}${isActive ? ' active' : ''}`,
                    onClick: () => onViewChange(item.id, item.tab),
                    'data-tooltip': item.label,
                    title: item.label,
                    'aria-label': item.label
                },
                    React.createElement('div', { className: 'admin-sidebar-icon' },
                        React.createElement(Icon, { name: item.lucide, size: 17 })
                    ),
                    React.createElement('span', { className: 'admin-sidebar-label' }, item.label)
                );
            })
        ),
        React.createElement('div', { className: 'admin-sidebar-footer' },
            sidebarFooterNavItems.map((item) => {
                const isActive = activeTab === item.tab;
                return React.createElement('button', {
                    key: item.id,
                    type: 'button',
                    className: `admin-sidebar-item ${item.id}${isActive ? ' active' : ''}`,
                    onClick: () => onViewChange(item.id, item.tab),
                    'data-tooltip': item.label,
                    title: item.label,
                    'aria-label': item.label
                },
                    React.createElement('div', { className: 'admin-sidebar-icon' },
                        React.createElement(Icon, { name: item.lucide, size: 17 })
                    ),
                    React.createElement('span', { className: 'admin-sidebar-label' }, item.label)
                );
            }),
            React.createElement('button', {
                className: 'admin-sidebar-item logout',
                type: 'button',
                onClick: () => fetchNui('cortex-admin:close'),
                'data-tooltip': 'Close Menu',
                title: 'Close Menu',
                'aria-label': 'Close Menu'
            },
                React.createElement('div', { className: 'admin-sidebar-icon' },
                    React.createElement(Icon, { name: 'power', size: 15 })
                ),
                React.createElement('span', { className: 'admin-sidebar-label' }, 'Close')
            )
        )
    );
}


// Coordinate HUD Component - displays live coordinates on middle-left of screen
function CoordHud({ visible, data }) {
    if (!visible) return null;

    const { x, y, z, heading, street, crossing } = data;
    const locationText = crossing ? `${street} / ${crossing}` : street;

    return React.createElement('div', { className: 'admin-coord-hud' },
        React.createElement('div', { className: 'admin-coord-hud-header' },
            React.createElement('span', { className: 'admin-coord-hud-title' }, 'COORDINATES'),
            React.createElement('span', { className: 'admin-coord-hud-subtitle' }, locationText || 'Unknown')
        ),
        React.createElement('div', { className: 'admin-coord-hud-body' },
            React.createElement('div', { className: 'admin-coord-hud-row' },
                React.createElement('span', { className: 'admin-coord-hud-label' }, 'X'),
                React.createElement('span', { className: 'admin-coord-hud-value' }, x.toFixed(3))
            ),
            React.createElement('div', { className: 'admin-coord-hud-row' },
                React.createElement('span', { className: 'admin-coord-hud-label' }, 'Y'),
                React.createElement('span', { className: 'admin-coord-hud-value' }, y.toFixed(3))
            ),
            React.createElement('div', { className: 'admin-coord-hud-row' },
                React.createElement('span', { className: 'admin-coord-hud-label' }, 'Z'),
                React.createElement('span', { className: 'admin-coord-hud-value' }, z.toFixed(3))
            ),
            React.createElement('div', { className: 'admin-coord-hud-row' },
                React.createElement('span', { className: 'admin-coord-hud-label' }, 'H'),
                React.createElement('span', { className: 'admin-coord-hud-value' }, heading.toFixed(1) + '°')
            )
        ),
        React.createElement('div', { className: 'admin-coord-hud-footer' },
            React.createElement('span', null, 'vector3(' + x.toFixed(2) + ', ' + y.toFixed(2) + ', ' + z.toFixed(2) + ')')
        )
    );
}

function CoordHudPanel() {
    const [visible, setVisible] = useState(false);
    const [showCoordinates, setShowCoordinates] = useState(true);
    const [showLocation, setShowLocation] = useState(true);
    const [data, setData] = useState(defaultCoordHudData);

    useEffect(() => {
        const handleMessage = (event) => {
            const payload = asObject(event.data);

            if (payload.action === 'cortex-admin:setCoordHud') {
                const nextData = asObject(payload.data);
                setVisible(nextData.visible === true);
                if (typeof nextData.showCoordinates === 'boolean') setShowCoordinates(nextData.showCoordinates);
                if (typeof nextData.showLocation === 'boolean') setShowLocation(nextData.showLocation);
                return;
            }

            if (payload.action === 'cortex-admin:updateCoordHud') {
                const nextData = asObject(payload.data);
                setData({
                    x: asFiniteNumber(nextData.x, 0),
                    y: asFiniteNumber(nextData.y, 0),
                    z: asFiniteNumber(nextData.z, 0),
                    heading: asFiniteNumber(nextData.heading, 0),
                    street: asString(nextData.street, ''),
                    crossing: nextData.crossing == null ? null : asString(nextData.crossing, '')
                });
            }
        };

        window.addEventListener('message', handleMessage);
        return () => window.removeEventListener('message', handleMessage);
    }, []);

    if (!visible) return null;

    const { x, y, z, heading, street, crossing } = data;
    const locationText = crossing ? `${street} / ${crossing}` : street;
    const vector3Text = `vector3(${x.toFixed(2)}, ${y.toFixed(2)}, ${z.toFixed(2)})`;
    const vector4Text = `vector4(${x.toFixed(2)}, ${y.toFixed(2)}, ${z.toFixed(2)}, ${heading.toFixed(2)})`;

    const copyCoords = (format) => {
        fetchNui('cortex-admin:action', {
            id: 'player.copyCoords',
            data: { format }
        });
    };

    return React.createElement('div', { className: 'admin-coord-hud' },
        React.createElement('div', { className: 'admin-coord-hud-header' },
            React.createElement('span', { className: 'admin-coord-hud-title' }, showCoordinates ? 'COORDINATES' : 'LOCATION'),
            showLocation && React.createElement('span', { className: 'admin-coord-hud-subtitle' }, locationText || 'Unknown')
        ),
        showCoordinates && React.createElement('div', { className: 'admin-coord-hud-body' },
            React.createElement('div', { className: 'admin-coord-hud-row' },
                React.createElement('span', { className: 'admin-coord-hud-label' }, 'X'),
                React.createElement('span', { className: 'admin-coord-hud-value' }, x.toFixed(3))
            ),
            React.createElement('div', { className: 'admin-coord-hud-row' },
                React.createElement('span', { className: 'admin-coord-hud-label' }, 'Y'),
                React.createElement('span', { className: 'admin-coord-hud-value' }, y.toFixed(3))
            ),
            React.createElement('div', { className: 'admin-coord-hud-row' },
                React.createElement('span', { className: 'admin-coord-hud-label' }, 'Z'),
                React.createElement('span', { className: 'admin-coord-hud-value' }, z.toFixed(3))
            ),
            React.createElement('div', { className: 'admin-coord-hud-row' },
                React.createElement('span', { className: 'admin-coord-hud-label' }, 'H'),
                React.createElement('span', { className: 'admin-coord-hud-value' }, heading.toFixed(1) + '\u00b0')
            )
        ),
        showCoordinates && React.createElement('div', { className: 'admin-coord-hud-footer' },
            React.createElement('div', { className: 'admin-coord-hud-copy-row' },
                React.createElement('span', {
                    className: 'admin-coord-hud-copy-text',
                    title: vector3Text
                }, vector3Text),
                React.createElement('button', {
                    type: 'button',
                    className: 'admin-coord-hud-copy-button',
                    onClick: () => copyCoords('vector3')
                }, 'Copy V3')
            ),
            React.createElement('div', { className: 'admin-coord-hud-copy-row' },
                React.createElement('span', {
                    className: 'admin-coord-hud-copy-text',
                    title: vector4Text
                }, vector4Text),
                React.createElement('button', {
                    type: 'button',
                    className: 'admin-coord-hud-copy-button',
                    onClick: () => copyCoords('vector4')
                }, 'Copy V4')
            )
        )
    );
}

function SpeedHudPanel() {
    const [visible, setVisible] = useState(false);
    const [position, setPosition] = useState('top-left');
    const [units, setUnits] = useState('mph');
    const [speed, setSpeed] = useState(0);

    useEffect(() => {
        const handleMessage = (event) => {
            const payload = asObject(event.data);
            if (payload.action === 'cortex-admin:setSpeedHud') {
                const d = asObject(payload.data);
                setVisible(d.visible === true);
                if (typeof d.position === 'string' && d.position.length > 0) {
                    setPosition(d.position);
                }
                if (typeof d.units === 'string' && d.units.length > 0) {
                    setUnits(d.units.toLowerCase());
                }
                return;
            }
            if (payload.action === 'cortex-admin:updateSpeedHud') {
                const d = asObject(payload.data);
                setSpeed(asFiniteNumber(d.speed, 0));
            }
        };

        window.addEventListener('message', handleMessage);
        return () => window.removeEventListener('message', handleMessage);
    }, []);

    if (!visible) return null;

    const unitLabel = units === 'kph' ? 'KPH' : 'MPH';
    const posClass = `admin-speed-hud--${position}`;

    return React.createElement('div', {
        className: `admin-speed-hud ${posClass}`,
        'aria-live': 'polite'
    },
        React.createElement('span', { className: 'admin-speed-hud-num' }, speed.toFixed(1)),
        React.createElement('span', { className: 'admin-speed-hud-unit' }, unitLabel)
    );
}

function VehicleHealthHudPanel() {
    const [state, setState] = useState({ visible: false, engine: 0, body: 0, tank: 0 });

    useEffect(() => {
        const handleMessage = (event) => {
            const payload = asObject(event.data);
            if (payload.action !== 'cortex-admin:setVehicleHealthHud') return;
            const data = asObject(payload.data);
            setState({
                visible: data.visible === true,
                engine: asFiniteNumber(data.engine, 0),
                body: asFiniteNumber(data.body, 0),
                tank: asFiniteNumber(data.tank, 0)
            });
        };
        window.addEventListener('message', handleMessage);
        return () => window.removeEventListener('message', handleMessage);
    }, []);

    if (!state.visible) return null;
    const rows = [
        ['Engine', state.engine],
        ['Body', state.body],
        ['Tank', state.tank]
    ];
    return h('section', { className: 'admin-vmenu-hud admin-vehicle-health-hud', 'aria-label': 'Vehicle health' },
        h('header', null, h(Icon, { name: 'activity', size: 13 }), h('span', null, 'VEHICLE HEALTH')),
        h('div', { className: 'admin-vmenu-hud-rows' }, rows.map(([label, value]) => {
            const normalized = clamp(value / 10, 0, 100);
            const danger = value <= 300;
            return h('div', { className: `admin-vmenu-hud-row${danger ? ' danger' : ''}`, key: label },
                h('span', null, label),
                h('div', { className: 'admin-vmenu-hud-meter', 'aria-hidden': 'true' }, h('i', { style: { width: `${normalized}%` } })),
                h('strong', null, Math.round(value))
            );
        }))
    );
}

function VoiceHudPanel() {
    const [state, setState] = useState({ visible: false, showStatus: false, talking: false, speakers: [] });

    useEffect(() => {
        const handleMessage = (event) => {
            const payload = asObject(event.data);
            if (payload.action === 'cortex-admin:setVoiceHud') {
                const data = asObject(payload.data);
                const talking = data.talking === true;
                const speakers = asArray(data.speakers).slice(0, 6).map((entry) => asString(entry)).filter(Boolean);
                setState({
                    visible: data.visible === true && (talking || speakers.length > 0),
                    showStatus: data.showStatus === true,
                    talking,
                    speakers
                });
                return;
            }

            // Toggle state is authoritative. This closes a stale HUD even if a
            // separate overlay message was delayed or missed by CEF.
            if (payload.action === 'cortex-admin:setState') {
                const toggles = asObject(asObject(payload.data).toggles);
                if (Object.keys(toggles).length === 0) return;
                const showSpeakers = toggles['voice.showSpeaker'] === true;
                const showStatus = toggles['voice.showStatus'] === true;
                setState((prev) => ({
                    ...prev,
                    showStatus,
                    visible: (showStatus && prev.talking) || (showSpeakers && prev.speakers.length > 0)
                }));
            }
        };
        window.addEventListener('message', handleMessage);
        return () => window.removeEventListener('message', handleMessage);
    }, []);

    if (!state.visible || (!state.talking && state.speakers.length === 0)) return null;
    const localTalking = state.showStatus && state.talking;
    return h('section', {
        className: `admin-vmenu-hud admin-voice-hud${localTalking ? ' talking' : ''}${state.speakers.length > 0 ? ' has-speakers' : ''}`,
        'aria-label': 'Voice activity'
    },
        h('header', null,
            h(Icon, { name: localTalking ? 'mic' : 'users-round', size: 13 }),
            h('span', null, localTalking ? 'TRANSMITTING' : 'ACTIVE SPEAKERS')
        ),
        state.speakers.length > 0
            ? h('div', { className: 'admin-voice-speakers' }, state.speakers.map((name, index) => h('span', { key: `${name}-${index}` }, name)))
            : null
    );
}

function TimeHudPanel() {
    const [state, setState] = useState({ visible: false, hour: 0, minute: 0 });

    useEffect(() => {
        const handleMessage = (event) => {
            const payload = asObject(event.data);
            if (payload.action === 'cortex-admin:setTimeHud') {
                const data = asObject(payload.data);
                setState({
                    visible: data.visible === true,
                    hour: clamp(Math.trunc(asFiniteNumber(data.hour, 0)), 0, 23),
                    minute: clamp(Math.trunc(asFiniteNumber(data.minute, 0)), 0, 59)
                });
                return;
            }

            // The full toggle map is the source of truth for overlay lifetime.
            if (payload.action === 'cortex-admin:setState') {
                const toggles = asObject(asObject(payload.data).toggles);
                if (Object.keys(toggles).length > 0 && toggles['dev.showTime'] !== true) {
                    setState((prev) => ({ ...prev, visible: false }));
                }
            }
        };
        window.addEventListener('message', handleMessage);
        return () => window.removeEventListener('message', handleMessage);
    }, []);

    if (!state.visible) return null;
    return h('div', { className: 'admin-time-hud', 'aria-label': 'Current game time' },
        h(Icon, { name: 'clock-3', size: 13 }),
        h('span', null, `${String(state.hour).padStart(2, '0')}:${String(state.minute).padStart(2, '0')}`)
    );
}

function WardrobeShareInbox({ open }) {
    const [requests, setRequests] = useState([]);

    useEffect(() => {
        const handleMessage = (event) => {
            const payload = asObject(event.data);
            if (payload.action !== 'cortex-admin:setState') {
                return;
            }

            const data = asObject(payload.data);
            if (!Array.isArray(data.wardrobeShareRequests)) {
                return;
            }

            setRequests(data.wardrobeShareRequests.map((request) => {
                const next = asObject(request);
                return {
                    shareId: asString(next.shareId),
                    senderName: asString(next.senderName, 'Unknown'),
                    title: asString(next.title, 'Current Outfit')
                };
            }).filter((request) => request.shareId));
        };

        window.addEventListener('message', handleMessage);
        return () => window.removeEventListener('message', handleMessage);
    }, []);

    const emitAppearanceRefresh = () => {
        window.dispatchEvent(new CustomEvent('cortex-admin:appearanceRefresh'));
    };

    const handleAction = (eventName, shareId, refreshAppearance) => {
        if (!shareId) return;
        fetchNui(eventName, { shareId }).then(() => {
            if (refreshAppearance) {
                emitAppearanceRefresh();
            }
        });
    };

    if (!open || requests.length === 0) return null;

    return React.createElement('div', { className: 'admin-wardrobe-share-stack' },
        requests.slice(0, 3).map((request, index) => React.createElement('div', {
            className: 'admin-wardrobe-share-card',
            key: request.shareId || index
        },
            React.createElement('div', { className: 'admin-wardrobe-share-eyebrow' }, 'Wardrobe Share'),
            React.createElement('div', { className: 'admin-wardrobe-share-title' }, `${request.senderName} sent ${request.title.toLowerCase()}`),
            React.createElement('div', { className: 'admin-wardrobe-share-copy' }, 'Accept wears it now. Save stores a new local outfit without copying the sender\'s face, hair, or skin.'),
            React.createElement('div', { className: 'admin-wardrobe-share-actions' },
                React.createElement('button', {
                    type: 'button',
                    className: 'admin-button small success',
                    onClick: () => handleAction('cortex-admin:acceptWardrobeShare', request.shareId, true)
                }, 'Accept'),
                React.createElement('button', {
                    type: 'button',
                    className: 'admin-button small',
                    onClick: () => handleAction('cortex-admin:saveWardrobeShare', request.shareId, true)
                }, 'Save Copy'),
                React.createElement('button', {
                    type: 'button',
                    className: 'admin-button small danger',
                    onClick: () => handleAction('cortex-admin:dismissWardrobeShare', request.shareId, false)
                }, 'Dismiss')
            )
        ))
    );
}

const DEDICATED_VMENU_WORKSPACES = new Set(['migration', 'bans', 'imported', 'voice']);

function App() {
    const [open, setOpen] = useState(false);
    const [actions, setActions] = useState([]);
    const [actionSelections, setActionSelections] = useState({});
    const [tabs, setTabs] = useState([]);
    const [favorites, setFavorites] = useState([]);
    const [settings, setSettings] = useState({});
    const [toggles, setToggles] = useState({});
    const [allowed, setAllowed] = useState({});
    const [players, setPlayers] = useState([]);
    const [playerIdentifiers, setPlayerIdentifiers] = useState(null);
    const [vmenuBanImportResult, setVmenuBanImportResult] = useState(null);
    const [personalVehicles, setPersonalVehicles] = useState([]);
    const [addonVehicles, setAddonVehicles] = useState([]);
    const [inventoryItems, setInventoryItems] = useState([]);
    const [garageVehicles, setGarageVehicles] = useState([]);
    const [frameworkInfo, setFrameworkInfo] = useState({ framework: 'standalone', hasInventory: false, hasGarage: false, hasQBX: false });
    const [voiceState, setVoiceState] = useState({ proximity: null, channel: null });
    const [activeTab, setActiveTab] = useState('all');
    const [vehiclePreviewLaunch, setVehiclePreviewLaunch] = useState({ token: 0, model: null, shared: false, resumeOnly: false });

    const [activeView, setActiveView] = useState('commands');
    const [search, setSearch] = useState('');
    const [resources, setResources] = useState([]);
    const [prompt, setPrompt] = useState(null);
    const [playerPrompt, setPlayerPrompt] = useState(null);
    const [confirmAction, setConfirmAction] = useState(null);
    const [actionContext, setActionContext] = useState(null);

    // New state for keyboard navigation and greeting
    const [selectedIndex, setSelectedIndex] = useState(-1);
    const [playerName, setPlayerName] = useState('Admin');
    const [gameHour, setGameHour] = useState(12);
    const [gameMinute, setGameMinute] = useState(0);
    const [currentWeather, setCurrentWeather] = useState('CLEAR');
    const [dockPosition, setDockPosition] = useState('right');
    const [viewportProfile, setViewportProfile] = useState(getViewportProfile);
    const lastTabRef = React.useRef(activeTab);
    
    // Ref for activate function (used by Enter key handler)
    const activateRef = React.useRef(null);
    
    // Ref for search input (used by / key shortcut)
    const searchRef = React.useRef(null);
    const shellRef = React.useRef(null);
    const typingStateRef = React.useRef(false);

    useLayoutEffect(() => {
        if (!open) return;
        scheduleLucideIcons();
    }, [open, activeTab]);

    // Layout - permanent sidebar
    const showSidebar = true;

    const decoratedActions = useMemo(() => {
        if (!open) return [];
        return actions.map((action) => {
            if (action.hidden === true) return null;
            // Filter out framework-specific actions when framework isn't active
            if (action.framework === 'qbx' && (!frameworkInfo || !frameworkInfo.hasQBX)) return null;
            if (action.tab === 'inventory' && (!frameworkInfo || !frameworkInfo.hasInventory)) return null;
            if (action.tab === 'garage' && (!frameworkInfo || !frameworkInfo.hasGarage)) return null;
            if (action.id === 'options.menuAccentColor') {
                return { ...action, selected: normalizeHex6(settings.menuAccentColor) || '#e8a23f' };
            }
            if (action.id === 'options.uiScale') return { ...action, selected: settings.uiScale };
            if (action.id === 'options.uiOpacity') {
                const o = Number(settings.uiOpacity);
                return { ...action, selected: Number.isFinite(o) ? o : 0.94 };
            }
            if (action.id === 'options.speedHudUnits') return { ...action, selected: settings.speedHudUnits || 'mph' };
            if (action.id === 'options.speedHudPosition') return { ...action, selected: settings.speedHudPosition || 'top-left' };
            if (action.id === 'options.menuPosition') return { ...action, selected: dockPosition };
            if (action.id === 'world.weather') return { ...action, selected: currentWeather };
            if (action.id === 'world.time') return { ...action, selected: gameHour };
            if (action.id === 'vehicle.personal') return action;
            if (Object.prototype.hasOwnProperty.call(actionSelections, action.id)) {
                return { ...action, selected: actionSelections[action.id] };
            }
            return action;
        }).filter(Boolean);
    }, [open, actions, actionSelections, settings, dockPosition, currentWeather, gameHour, frameworkInfo]);

    const filteredActions = useMemo(() => {
        if (!open) return [];
        const query = search.trim().toLowerCase();
        let list = decoratedActions;
        if (activeTab && activeTab !== 'all' && activeTab !== 'favorites') {
            const cmdTab = activeTab === 'players' ? 'player' : activeTab;
            list = list.filter((action) => action.tab === cmdTab);
        }
        if (activeTab === 'favorites') {
            list = list.filter((action) => favorites.includes(action.id));
        }
        if (query.length > 0) {
            list = list.filter((action) => {
                const label = (action.label || '').toLowerCase();
                const description = (action.description || '').toLowerCase();
                return label.includes(query) || description.includes(query);
            });
        }
        // Sort favorites to top when in 'all' tab
        if (activeTab === 'all') {
            list = [...list].sort((a, b) => {
                const aFav = favorites.includes(a.id);
                const bFav = favorites.includes(b.id);
                if (aFav && !bFav) return -1;
                if (!aFav && bFav) return 1;
                return 0; // Preserve original order for items with same favorite status
            });
        }
        return list;
    }, [decoratedActions, activeTab, favorites, search]);

    const groupedActions = useMemo(() => {
        const groups = [];
        const groupIndex = new Map();
        const append = (label, action) => {
            if (!groupIndex.has(label)) {
                groupIndex.set(label, groups.length);
                groups.push({ label, actions: [] });
            }
            groups[groupIndex.get(label)].actions.push(action);
        };

        if (activeTab === 'all') {
            filteredActions.forEach((action) => {
                const label = favorites.includes(action.id) ? 'Favorites' : (action.section || 'General');
                append(label, action);
            });
        } else {
            filteredActions.forEach((action) => append(action.section || 'General', action));
        }
        return groups;
    }, [filteredActions, activeTab, favorites]);

    const displayActions = useMemo(() => groupedActions.flatMap((group) => group.actions), [groupedActions]);
    const displayActionIndexes = useMemo(() => {
        const index = new Map();
        displayActions.forEach((action, actionIndex) => index.set(action.id, actionIndex));
        return index;
    }, [displayActions]);

    const filteredActionsRef = React.useRef(displayActions);
    React.useEffect(() => {
        filteredActionsRef.current = displayActions;
    }, [displayActions]);


    const applySettings = useCallback((nextSettings) => {
        const rawScale = Number(nextSettings.uiScale) || 1.0;
        const uiScale = Math.min(1.6, Math.max(1.0, rawScale));
        const rawOpacity = Number(nextSettings.uiOpacity);
        const uiOpacity = Math.min(1.0, Math.max(0.35, Number.isFinite(rawOpacity) ? rawOpacity : 0.94));
        // Bake the admin scale into --es-ui-scale so the element's actual DOM size
        // matches its visual size
        const baseScale = getUiScale();
        document.documentElement.style.setProperty('--es-admin-scale', uiScale);
        document.documentElement.style.setProperty('--es-ui-scale', baseScale * uiScale);
        document.documentElement.style.setProperty('--es-admin-opacity', String(uiOpacity));
        applyMenuAccentCss(nextSettings.menuAccentColor || '#e8a23f');
    }, []);

    const setTypingState = useCallback((isTyping) => {
        const next = isTyping === true;
        if (typingStateRef.current === next) return;
        typingStateRef.current = next;
        fetchNui('cortex-admin:setTypingState', { typing: next });
    }, []);


    const handleMessage = useCallback((event) => {
        const payload = asObject(event.data);

        if (payload.action === 'cortex-admin:setState') {
            const data = asObject(payload.data);
            if (typeof data.open === 'boolean') setOpen(data.open);
            if (Array.isArray(data.actions)) setActions(data.actions);
            if (Array.isArray(data.tabs)) setTabs(data.tabs);
            if (Array.isArray(data.favorites)) setFavorites(data.favorites);
            if (isPlainObject(data.settings)) {
                const nextSettings = data.settings;
                setSettings(nextSettings);
                setDockPosition(normalizeMenuDock(nextSettings.menuPosition));
                applySettings(nextSettings);
            }
            if (isPlainObject(data.toggles)) setToggles(data.toggles);
            if (isPlainObject(data.allowed)) setAllowed(data.allowed);
            if (Array.isArray(data.players)) setPlayers(data.players);
            if ('personalVehicles' in data) {
                setPersonalVehicles(Array.isArray(data.personalVehicles) || isPlainObject(data.personalVehicles) ? data.personalVehicles : []);
            }
            if (Array.isArray(data.addonVehicles)) setAddonVehicles(data.addonVehicles);
            if (isPlainObject(data.vehiclePreview)) {
                const vp = data.vehiclePreview;
                setVehiclePreviewLaunch((prev) => ({
                    ...prev,
                    shared: vp.shared === true,
                    model: (typeof vp.model === 'string' && vp.model.trim()) ? vp.model.trim() : prev.model,
                }));
            }
            if (Array.isArray(data.inventoryItems)) setInventoryItems(data.inventoryItems);
            if (Array.isArray(data.garageVehicles)) setGarageVehicles(data.garageVehicles);
            if (isPlainObject(data.voiceState)) {
                setVoiceState(normalizeVoiceState(data.voiceState));
            }
            if (isPlainObject(data.frameworkInfo)) {
                const frameworkInfo = data.frameworkInfo;
                setFrameworkInfo({
                    framework: asString(frameworkInfo.framework, 'standalone'),
                    hasInventory: frameworkInfo.hasInventory === true,
                    hasGarage: frameworkInfo.hasGarage === true,
                    hasQBX: frameworkInfo.hasQBX === true
                });
            }
            if (typeof data.playerName === 'string') setPlayerName(data.playerName);
            if ('gameHour' in data) setGameHour(asFiniteNumber(data.gameHour, 12));
            if ('gameMinute' in data) setGameMinute(asFiniteNumber(data.gameMinute, 0));
            if (typeof data.currentWeather === 'string' && data.currentWeather.length > 0) setCurrentWeather(data.currentWeather);
            if (Array.isArray(data.resources)) setResources(data.resources);
        }

        if (payload.action === 'cortex-admin:updateRuntimeState') {
            const data = asObject(payload.data);

            if (Array.isArray(data.players)) setPlayers(data.players);
            if ('gameHour' in data) {
                const nextGameHour = asFiniteNumber(data.gameHour, 12);
                setGameHour((prev) => (prev === nextGameHour ? prev : nextGameHour));
            }
            if ('gameMinute' in data) {
                const nextGameMinute = asFiniteNumber(data.gameMinute, 0);
                setGameMinute((prev) => (prev === nextGameMinute ? prev : nextGameMinute));
            }
            if (typeof data.currentWeather === 'string' && data.currentWeather.length > 0) {
                const nextWeather = data.currentWeather;
                setCurrentWeather((prev) => (prev === nextWeather ? prev : nextWeather));
            }
        }

        if (payload.action === 'cortex-admin:open') {
            setOpen(true);
        }

        if (payload.action === 'cortex-admin:vehiclePreviewPage') {
            const data = asObject(payload.data);
            const rawModel = data.model;
            const modelStr = typeof rawModel === 'string' && rawModel.trim() ? rawModel.trim() : null;
            setVehiclePreviewLaunch((prev) => ({
                token: prev.token + 1,
                model: modelStr,
                shared: false,
                resumeOnly: true,
            }));
            setActiveTab('vehicle');
        }

        if (payload.action === 'cortex-admin:vehiclePreviewResume') {
            const data = asObject(payload.data);
            const rawModel = data.model;
            const modelStr = typeof rawModel === 'string' && rawModel.trim() ? rawModel.trim() : null;
            if (!modelStr) return;
            setVehiclePreviewLaunch((prev) => ({
                token: prev.token + 1,
                model: modelStr,
                shared: data.shared === true,
                resumeOnly: data.resumeOnly !== false,
            }));
            setActiveTab('vehicle');
        }

        if (payload.action === 'cortex-admin:close') {
            setOpen(false);
        }

        if (payload.action === 'cortex-admin:copyText') {
            const text = payload.data && payload.data.text;
            if (text) {
                copyTextToClipboard(text);
            }
        }

        if (payload.action === 'cortex-admin:setTab') {
            const tab = asString(asObject(payload.data).tab);
            if (tab) setActiveTab(tab);
        }

        if (payload.action === 'cortex-admin:setPlayerIdentifiers') {
            const data = asObject(payload.data);
            const target = asFiniteNumber(data.target, 0);
            setPlayerIdentifiers(target > 0 ? {
                target,
                name: asString(data.name, 'Unknown'),
                identifiers: asArray(data.identifiers).slice(0, 16).map((entry) => asString(entry)).filter(Boolean)
            } : null);
        }

        if (payload.action === 'cortex-admin:setVmenuBanImportResult') {
            setVmenuBanImportResult(asObject(payload.data));
        }

        if (payload.action === 'cortex-admin:setVoiceState') {
            const data = asObject(payload.data);
            setVoiceState(normalizeVoiceState(data));
        }

        if (payload.action === 'cortex-admin:reload') {
            window.location.reload();
        }

    }, [applySettings]);

    useEffect(() => {
        window.addEventListener('message', handleMessage);
        fetchNui('cortex-admin:ready');

        return () => {
            window.removeEventListener('message', handleMessage);
            setTypingState(false);
        };
    }, [handleMessage, setTypingState]);

    useEffect(() => {
        const handleViewportResize = () => {
            setViewportProfile(getViewportProfile());
        };

        window.addEventListener('resize', handleViewportResize);
        return () => window.removeEventListener('resize', handleViewportResize);
    }, []);

    // Track shell resize (drag handle) so cramped layout engages when the shell itself shrinks
    useEffect(() => {
        if (!open) return undefined;
        const shell = shellRef.current;
        if (!shell || typeof ResizeObserver === 'undefined') return undefined;
        const measure = () => {
            const r = shell.getBoundingClientRect();
            setViewportProfile(getViewportProfile({ width: r.width, height: r.height }));
        };
        const observer = new ResizeObserver(measure);
        observer.observe(shell);
        return () => observer.disconnect();
    }, [open]);

    useEffect(() => {
        applySettings(settings);
    }, [settings, viewportProfile.width, viewportProfile.height, applySettings]);

    useEffect(() => {
        if (!open) {
            setTypingState(false);
            return undefined;
        }

        const syncTypingState = () => {
            const active = document.activeElement;
            const tag = active && active.tagName ? active.tagName.toLowerCase() : '';
            const isTyping = tag === 'input' || tag === 'textarea' || (active && active.isContentEditable === true);
            setTypingState(isTyping);
        };

        const handleFocusIn = () => {
            syncTypingState();
        };

        const handleFocusOut = () => {
            setTimeout(syncTypingState, 0);
        };

        syncTypingState();
        document.addEventListener('focusin', handleFocusIn);
        document.addEventListener('focusout', handleFocusOut);

        return () => {
            document.removeEventListener('focusin', handleFocusIn);
            document.removeEventListener('focusout', handleFocusOut);
            setTypingState(false);
        };
    }, [open, setTypingState]);

    useEffect(() => {
        if (!open) return undefined;

        const keyHandler = (event) => {
            if (event.key === 'Escape') {
                event.preventDefault();
                event.stopPropagation();
                if (actionContext) {
                    setActionContext(null);
                    return;
                }
                if (prompt) {
                    setPrompt(null);
                    return;
                }
                if (playerPrompt) {
                    setPlayerPrompt(null);
                    return;
                }
                if (confirmAction) {
                    setConfirmAction(null);
                    return;
                }
                if (document.querySelector('.admin-action.expanded')) {
                    window.dispatchEvent(new CustomEvent('cortex-admin:closeActionPanels'));
                    return;
                }
                fetchNui('cortex-admin:close');
                return;
            }

            const target = event.target;
            const tag = target && target.tagName ? target.tagName.toLowerCase() : '';
            const isTyping = tag === 'input' || tag === 'textarea' || (target && target.isContentEditable);

            if (isTyping) return;
            if (isDedicatedVmenuWorkspace) return;

            if (event.key === 'ArrowDown') {
                event.preventDefault();
                setSelectedIndex((prev) => {
                    const maxIndex = Math.max(0, filteredActionsRef.current.length - 1);
                    if (prev < 0) return 0;
                    return Math.min(maxIndex, prev + 1);
                });
            }
            if (event.key === 'ArrowUp') {
                event.preventDefault();
                setSelectedIndex((prev) => (prev <= 0 ? -1 : prev - 1));
            }

            if (event.key === 'ArrowLeft') {
                event.preventDefault();
                setActiveTab(prev => {
                    const currentIdx = tabs.findIndex(t => t.id === prev);
                    const newIdx = Math.max(0, currentIdx - 1);
                    return tabs[newIdx]?.id || prev;
                });
            }
            if (event.key === 'ArrowRight') {
                event.preventDefault();
                setActiveTab(prev => {
                    const currentIdx = tabs.findIndex(t => t.id === prev);
                    const newIdx = Math.min(tabs.length - 1, currentIdx + 1);
                    return tabs[newIdx]?.id || prev;
                });
            }

            if (event.key === 'Enter') {
                event.preventDefault();
                if (activateRef.current) activateRef.current();
            }

            if (event.key === 'Backspace') {
                event.preventDefault();
                setActiveTab('all');
                setSelectedIndex(-1);
                setSearch('');
            }

            // Focus search with / key
            if (event.key === '/' || event.key === 'f' && event.ctrlKey) {
                event.preventDefault();
                if (searchRef.current) {
                    searchRef.current.focus();
                    searchRef.current.select();
                }
            }
        };

        window.addEventListener('keydown', keyHandler);

        return () => {
            window.removeEventListener('keydown', keyHandler);
        };
    }, [open, tabs, actionContext, prompt, playerPrompt, confirmAction, activeTab]);

    // Reset selected index only when tab changes
    useEffect(() => {
        if (lastTabRef.current !== activeTab) {
            setSelectedIndex(-1);
            lastTabRef.current = activeTab;
        }
    }, [activeTab]);

    // Preserve the current tab and search when the menu is reopened.
    useEffect(() => {
        if (open) {
            setSelectedIndex(-1);
        }
    }, [open]);

    useEffect(() => {
        if (!open) {
            setPrompt(null);
            setPlayerPrompt(null);
            setConfirmAction(null);
            setActionContext(null);
        }
    }, [open]);

    useEffect(() => {
        if (!open) return;
        const selectedAction = document.querySelector('.admin-action.selected');
        if (selectedAction && typeof selectedAction.scrollIntoView === 'function') {
            selectedAction.scrollIntoView({ block: 'nearest' });
        }
    }, [open, selectedIndex, displayActions]);

    const queueAction = useCallback((action, payload, eventName = 'cortex-admin:action') => {
        if (!action) return;
        // Personal vehicles now handled inline via ActionItem
        const data = payload || { id: action.id };
        if (action.requiresConfirm) {
            setConfirmAction({ action, eventName, payload: data });
            return;
        }
        if (action.type === 'prompt') {
            setPrompt(action);
            return;
        }
        fetchNui(eventName, data);
    }, []);

    const handleConfirmAction = useCallback(() => {
        if (!confirmAction || !confirmAction.action) return;
        const eventName = confirmAction.eventName || 'cortex-admin:action';
        const payload = confirmAction.payload || { id: confirmAction.action.id };
        fetchNui(eventName, payload);
        setConfirmAction(null);
    }, [confirmAction]);

    const handleCancelConfirm = useCallback(() => setConfirmAction(null), []);

    const confirmDetails = useMemo(() => {
        if (!confirmAction || !confirmAction.action) return { title: 'Confirm Action', message: 'Are you sure you want to continue?' };
        const action = confirmAction.action;
        const payload = confirmAction.payload || {};
        let message = action.description || 'Are you sure you want to continue?';

        if (payload.value !== undefined && Array.isArray(action.values)) {
            const options = normalizeValues(action.values);
            const matched = options.find((option) => String(option.value) === String(payload.value));
            if (matched) {
                message = `${message} (${matched.label})`;
            }
        }

        return {
            title: action.label || 'Confirm Action',
            message
        };
    }, [confirmAction]);

    const activateAction = React.useCallback((action) => {
        if (!action) return;
        if (allowed[action.id] === false) return;

        if (action.type === 'toggle') {
            const isEnabled = toggles[action.id] === true;
            setToggles(prev => ({ ...prev, [action.id]: !isEnabled }));
            fetchNui('cortex-admin:toggle', { id: action.id, enabled: !isEnabled });
        } else if (action.type === 'workspace') {
            if (action.workspaceTab) setActiveTab(action.workspaceTab);
        } else if (action.type === 'select' || action.type === 'dock' || action.type === 'slider' || action.type === 'color') {
            return;
        } else {
            queueAction(action);
        }
    }, [allowed, toggles, queueAction]);

    const activateSelectedItem = React.useCallback(() => {
        const actions = filteredActionsRef.current;
        if (!actions || actions.length === 0 || selectedIndex < 0) return;
        const clampedIdx = Math.min(Math.max(0, selectedIndex), actions.length - 1);
        activateAction(actions[clampedIdx]);
    }, [selectedIndex, activateAction]);


    // Keep activateRef updated
    React.useEffect(() => {
        activateRef.current = activateSelectedItem;
    }, [activateSelectedItem]);

    const handleToggle = useCallback((action, enabled) => {
        if (action.id.startsWith('options.')) {
            const settingKey = action.id.replace('options.', '');
            setSettings((prev) => ({ ...prev, [settingKey]: enabled }));
            fetchNui('cortex-admin:toggle', { id: action.id, enabled });
            return;
        }
        setToggles((prev) => ({ ...prev, [action.id]: enabled }));
        fetchNui('cortex-admin:toggle', { id: action.id, enabled });
    }, []);

    const handleSelect = useCallback((action, value) => {
        setActionSelections((previous) => ({ ...previous, [action.id]: value }));
        if (action.id === 'options.menuPosition') {
            const next = normalizeMenuDock(value);
            setDockPosition(next);
            setSettings((prev) => ({ ...prev, menuPosition: next }));
            fetchNui('cortex-admin:select', { id: action.id, value: next });
            return;
        }
        if (action.id.startsWith('options.')) {
            const key = action.id.replace('options.', '');
            setSettings((prev) => ({ ...prev, [key]: value }));
        }
        queueAction(action, { id: action.id, value }, 'cortex-admin:select');
    }, [queueAction]);

    const handleAction = useCallback((action) => {
        if (action && action.type === 'workspace' && action.workspaceTab) {
            setActiveTab(action.workspaceTab);
            return;
        }
        queueAction(action);
    }, [queueAction]);

    const handlePromptSubmit = useCallback((action, values) => {
        fetchNui('cortex-admin:action', { id: action.id, data: values });
    }, []);

    const handlePreviewAnyVehicle = useCallback((model) => {
        if (!model) return;
        fetchNui('cortex-admin:previewVehicle', { model });
    }, []);

    const handleClearVehiclePreview = useCallback(() => {
        fetchNui('cortex-admin:clearVehiclePreview');
    }, []);

    const handleFavorite = useCallback((id) => {
        setFavorites((previous) => previous.includes(id)
            ? previous.filter((entry) => entry !== id)
            : [...previous, id]);
        fetchNui('cortex-admin:favorite', { id });
    }, []);

    const handlePromptConfirm = (values) => {
        if (prompt && typeof prompt.onSubmit === 'function') {
            prompt.onSubmit(values || {});
        } else {
            fetchNui('cortex-admin:action', { id: prompt.id, data: values });
        }
        setPrompt(null);
    };

    const handlePlayerAction = useCallback((action, player) => {
        if (action === 'message' || action === 'kick' || action === 'ban') {
            const fields = action === 'message'
                ? [{ name: 'message', label: 'Message', placeholder: 'Enter a private admin message' }]
                : [{ name: 'reason', label: 'Reason', placeholder: 'Reason' }];
            if (action === 'ban') {
                fields.push({ name: 'duration', label: 'Duration (mins, blank = perm)', placeholder: '0' });
            }
            setPlayerPrompt({ action, player, title: `${action.toUpperCase()} ${player.name}`, fields });
            return;
        }
        fetchNui('cortex-admin:playerAction', { action, target: player.id });
    }, []);

    const handlePlayerPromptConfirm = useCallback((values) => {
        fetchNui('cortex-admin:playerAction', {
            action: playerPrompt.action,
            target: playerPrompt.player.id,
            message: values.message,
            reason: values.reason,
            duration: values.duration
        });
        setPlayerPrompt(null);
    }, [playerPrompt]);

    const appClass = `admin-app${open ? ' open' : ''}`;
    const shellClasses = ['admin-shell'];
    shellClasses.push(`docked-${dockPosition}`);
    if (viewportProfile.isNarrow) shellClasses.push('is-narrow');
    if (viewportProfile.isShort) shellClasses.push('is-short');
    if (viewportProfile.isCramped) shellClasses.push('is-cramped');
    const shellClass = shellClasses.join(' ');
    const showTargetInfo = settings.showTargetInfo !== false;
    const isDedicatedVmenuWorkspace = DEDICATED_VMENU_WORKSPACES.has(activeTab);
    const activeTabLabel = useMemo(() => {
        const navItems = baseSidebarItems.concat(sidebarFooterNavItems).filter((item) => item && !item.type);
        const match = navItems.find((item) => item.tab === activeTab);
        if (match) return match.label;
        return activeTab.charAt(0).toUpperCase() + activeTab.slice(1).replace(/_/g, ' ');
    }, [activeTab]);

    // Handle sidebar view switching - now directly sets tab
    const handleViewChange = useCallback((viewId, tab) => {
        setActiveView(viewId);
        setActionContext(null);
        if (tab) {
            setActiveTab(tab);
            if (tab === 'server') {
                fetchNui('cortex-admin:requestResources');
            }
            if (tab === 'inventory') {
                fetchNui('cortex-admin:requestItems');
            }
            if (tab === 'garage') {
                fetchNui('cortex-admin:requestGarage');
            }
        }
    }, []);

    // Close handler
    const handleClose = useCallback(() => {
        fetchNui('cortex-admin:close');
    }, []);

    const handleResourceAction = useCallback((action, name) => {
        fetchNui('cortex-admin:resourceAction', { action, name });
    }, []);

    const handleResourceRefresh = useCallback(() => {
        fetchNui('cortex-admin:requestResources');
    }, []);

    const handleInventoryClose = useCallback(() => {
        setActiveTab('all');
    }, []);

    const handleGarageClose = useCallback(() => {
        setActiveTab('all');
    }, []);

    const handleSpawnPersonalVehicle = useCallback((vehicleId) => {
        fetchNui('cortex-admin:action', { id: 'vehicle.personal', data: { id: vehicleId } });
    }, []);

    const handleDeletePersonalVehicle = useCallback((vehicleId) => {
        fetchNui('cortex-admin:action', { id: 'vehicle.removePersonal', data: { id: vehicleId } });
    }, []);

    const handleSavePersonalVehicle = useCallback((vehicleId) => {
        fetchNui('cortex-admin:action', { id: 'vehicle.savePersonal', data: { id: vehicleId } });
    }, []);

    const handleToggleInlineSetting = useCallback((key, value) => {
        setSettings((prev) => ({ ...prev, [key]: value }));
        fetchNui('cortex-admin:toggle', { id: `options.${key}`, enabled: value });
    }, []);

    const handleSpawnAnyVehicle = useCallback((model) => {
        fetchNui('cortex-admin:action', { id: 'vehicle.spawn', data: { model } });
    }, []);

    return React.createElement(React.Fragment, null,
        React.createElement(CoordHudPanel),
        React.createElement(SpeedHudPanel),
        React.createElement(VehicleHealthHudPanel),
        React.createElement(VoiceHudPanel),
        React.createElement(TimeHudPanel),
        React.createElement(WardrobeShareInbox, { open }),
        React.createElement('div', {
            className: appClass
        },
        open && React.createElement('div', { ref: shellRef, className: shellClass },
            // Left Sidebar
            showSidebar && React.createElement(Sidebar, {
                activeView,
                activeTab,
                onViewChange: handleViewChange,
                frameworkInfo,
                allowed
            }),

            // Main Content Area
            React.createElement('div', { className: 'admin-main' },
                React.createElement('header', { className: 'admin-topbar' },
                    React.createElement('div', { className: 'admin-topbar-left' },
                        React.createElement('div', { className: 'admin-brand' },
                            React.createElement('span', { className: 'admin-brand-mark', 'aria-hidden': true }),
                            React.createElement('span', { className: 'admin-brand-name' }, 'CORTEX'),
                        ),
                        React.createElement('div', { className: 'admin-topbar-context' },
                            React.createElement('strong', null, activeTabLabel)
                        )
                    ),
                    React.createElement('div', { className: 'admin-topbar-right' },
                        React.createElement('div', { className: 'admin-topbar-player' },
                            React.createElement(Icon, { name: 'user', size: 12 }),
                            React.createElement('span', null, playerName)
                        ),
                        React.createElement('button', {
                            type: 'button',
                            className: 'admin-header-btn close-btn',
                            onClick: handleClose,
                            title: 'Close menu (Esc)',
                            'aria-label': 'Close menu'
                        }, React.createElement(Icon, { name: 'x', size: 14 }))
                    )
                ),
                // Content Area
                React.createElement('div', { className: 'admin-content' },
                    React.createElement('div', {
                        className: 'admin-column',
                        onWheel: (e) => {
                            const delta = e.deltaY !== 0 ? e.deltaY : e.deltaX;
                            if (delta === 0) return;

                            const canScroll = (element) => element
                                && element.scrollHeight > element.clientHeight
                                && (delta < 0
                                    ? element.scrollTop > 0
                                    : element.scrollTop + element.clientHeight < element.scrollHeight);
                            const localOwner = e.target.closest('.appearance-section-stack--wardrobe-scroll, .appearance-overlay-scroll');
                            const pageOwner = e.currentTarget.querySelector('.appearance-content-area--scroll');

                            // Shift-wheel arrives as deltaX in CEF. Route it to the nearest
                            // vertical owner instead of the non-scrolling appearance column.
                            if (e.deltaX !== 0 && e.deltaY === 0) {
                                const owner = canScroll(localOwner)
                                    ? localOwner
                                    : canScroll(pageOwner)
                                        ? pageOwner
                                        : e.currentTarget;
                                owner.scrollTop += delta;
                                return;
                            }

                            // Keep the page scrollable while the pointer is over its fixed
                            // toolbar rather than directly above the nested content owner.
                            if (pageOwner && !pageOwner.contains(e.target) && canScroll(pageOwner)) {
                                pageOwner.scrollTop += delta;
                            }
                        }
                    },
                        // Search Bar (always visible, prominent in sidebar mode)
                        activeTab !== 'vehicle_tuning' && activeTab !== 'appearance' && !isDedicatedVmenuWorkspace && React.createElement('div', { className: 'admin-search-bar' },
                            React.createElement('div', { className: 'admin-search-wrapper' },
                                React.createElement(Icon, { name: 'search', size: 18, className: 'admin-search-icon' }),
                                React.createElement('input', {
                                    ref: searchRef,
                                    type: 'text',
                                    className: 'admin-search-input',
                                    value: search,
                                    'aria-label': 'Search commands',
                                    placeholder: 'Search commands...',
                                    onKeyDown: (e) => {
                                        e.stopPropagation();
                                        if (e.key === 'Escape') {
                                            e.target.blur();
                                            setSearch('');
                                        }
                                    },
                                    onChange: (e) => {
                                        setSearch(e.target.value);
                                        setSelectedIndex(-1);
                                    }
                                }),
                                search.length > 0 && React.createElement('button', {
                                    type: 'button',
                                    className: 'admin-search-clear',
                                    title: 'Clear search',
                                    'aria-label': 'Clear search',
                                    onClick: () => {
                                        setSearch('');
                                        setSelectedIndex(-1);
                                        if (searchRef.current) searchRef.current.focus();
                                    }
                                }, React.createElement(Icon, { name: 'x', size: 12 })),
                                React.createElement('kbd', { className: 'admin-search-kbd' }, '/')
                            )
                        ),

                        // Special sections for specific tabs
                        (activeTab === 'player' || activeTab === 'players') && React.createElement('div', { className: 'admin-section' },
                            React.createElement('div', { className: 'admin-section-title' }, 'Online Players'),
                            React.createElement(PlayerList, { players, onAction: handlePlayerAction, allowed, identifiers: playerIdentifiers })
                        ),

                        activeTab === 'server' && React.createElement('div', { className: 'admin-section' },
                            React.createElement('div', { className: 'admin-section-title' }, 'Resource Manager'),
                            React.createElement(ResourceManager, {
                                resources,
                                onAction: handleResourceAction,
                                onRefresh: handleResourceRefresh
                            })
                        ),

                        activeTab === 'appearance' && React.createElement(AppearanceErrorBoundary, null,
                            React.createElement(AppearanceWorkspaceView, { onPrompt: setPrompt })
                        ),
                        activeTab === 'voice' && React.createElement(VoiceChatWorkspace, {
                            actions: decoratedActions,
                            toggles,
                            allowed,
                            voiceState,
                            onToggle: handleToggle,
                            onSelect: handleSelect,
                            onPromptSubmit: handlePromptSubmit
                        }),
                        activeTab === 'vehicle_custom' && React.createElement(VehicleView),
                        activeTab === 'vehicle_tuning' && React.createElement(VehicleTuningView),
                        activeTab === 'teleport' && React.createElement(TeleportWorkspaceView, { onPrompt: setPrompt }),
                        activeTab === 'migration' && React.createElement(VmenuMigrationWorkspace, { onPrompt: setPrompt, allowed, banImportResult: vmenuBanImportResult }),
                        activeTab === 'bans' && React.createElement(BannedPlayersWorkspace, { onPrompt: setPrompt, allowed }),
                        activeTab === 'imported' && React.createElement(ImportedDataWorkspace, { allowed }),

                        // Inventory View (QBX only)
                        activeTab === 'inventory' && frameworkInfo.hasInventory && React.createElement(InlineInventory, {
                            items: inventoryItems,
                            players: players,
                            onClose: handleInventoryClose
                        }),

                        // Garage View (QBX only)
                        activeTab === 'garage' && frameworkInfo.hasGarage && React.createElement(InlineGarage, {
                            vehicles: garageVehicles,
                            onClose: handleGarageClose
                        }),

                        // General Commands Section (Filtered by Tab)
                        activeTab !== 'appearance' && activeTab !== 'vehicle_custom' && activeTab !== 'vehicle_tuning' && activeTab !== 'inventory' && activeTab !== 'garage' && !isDedicatedVmenuWorkspace && React.createElement('div', {
                            className: activeTab === 'recording' ? 'admin-section admin-section--recording' : 'admin-section'
                        },
                            React.createElement('div', { className: 'admin-command-overview' },
                                React.createElement('div', null,
                                    React.createElement('span', { className: 'admin-section-kicker' }, activeTab === 'all' ? 'COMMAND LIBRARY' : activeTab === 'favorites' ? 'PINNED' : 'CATEGORY'),
                                    React.createElement('h2', null,
                                        activeTab === 'all' ? 'All commands' :
                                            activeTab === 'favorites' ? 'Favorite actions' :
                                                activeTab === 'recording' ? 'Recording & capture' :
                                                    `${activeTab.charAt(0).toUpperCase() + activeTab.slice(1)} commands`)
                                ),
                                React.createElement('span', { className: 'admin-command-count' }, `${displayActions.length} available`)
                            ),
                            filteredActions.length === 0
                                ? React.createElement('div', { className: 'admin-no-results admin-command-empty' }, 'No commands found in this category.')
                                : React.createElement('div', { className: 'admin-action-groups' },
                                    groupedActions.map((group) => React.createElement('section', { className: 'admin-action-group', key: group.label },
                                        React.createElement('div', { className: 'admin-action-group-header' },
                                            React.createElement('h3', null, group.label),
                                            React.createElement('span', null, group.actions.length)
                                        ),
                                        React.createElement('div', { className: 'admin-actions' },
                                            group.actions.map((action) => {
                                                const actionIndex = displayActionIndexes.get(action.id);
                                                const maxIdx = Math.max(0, displayActions.length - 1);
                                                const clampedIndex = selectedIndex < 0 ? -1 : Math.min(Math.max(0, selectedIndex), maxIdx);
                                                return React.createElement(ActionItem, {
                                                    key: action.id,
                                                    action,
                                                    toggles,
                                                    favorites,
                                                    allowed,
                                                    onToggle: handleToggle,
                                                    onSelect: handleSelect,
                                                    onAction: handleAction,
                                                    onFavorite: handleFavorite,
                                                    onContextMenu: (event, selectedAction) => {
                                                        setSelectedIndex(actionIndex);
                                                        setActionContext({ action: selectedAction, x: event.clientX, y: event.clientY });
                                                    },
                                                    onPromptSubmit: handlePromptSubmit,
                                                    isSelected: actionIndex === clampedIndex,
                                                    settings: settings,
                                                    personalVehicles: personalVehicles,
                                                    addonVehicles: addonVehicles,
                                                    onSpawnVehicle: handleSpawnPersonalVehicle,
                                                    onDeleteVehicle: handleDeletePersonalVehicle,
                                                    onSaveVehicle: handleSavePersonalVehicle,
                                                    onToggleSetting: handleToggleInlineSetting,
                                                    onSpawnAnyVehicle: handleSpawnAnyVehicle,
                                                    onPreviewAnyVehicle: handlePreviewAnyVehicle,
                                                    onClearVehiclePreview: handleClearVehiclePreview,
                                                    players: players,
                                                    vehiclePreviewLaunch: vehiclePreviewLaunch
                                                });
                                            })
                                        )
                                    ))
                                )
                        )
                    )
                )
            )
        )),
        prompt && React.createElement(Modal, {
            title: prompt.title || (prompt.prompt ? prompt.prompt.title : 'Enter Details'),
            description: prompt.description || (prompt.prompt ? prompt.prompt.description : ''),
            fields: prompt.fields || (prompt.prompt ? prompt.prompt.fields : []),
            onCancel: () => setPrompt(null),
            onConfirm: handlePromptConfirm
        }),
        playerPrompt && React.createElement(Modal, {
            title: playerPrompt.title,
            fields: playerPrompt.fields,
            onCancel: () => setPlayerPrompt(null),
            onConfirm: handlePlayerPromptConfirm
        }),
        confirmAction && React.createElement(ConfirmModal, {
            title: confirmDetails.title,
            message: confirmDetails.message,
            onCancel: handleCancelConfirm,
            onConfirm: handleConfirmAction
        }),
        actionContext && React.createElement(ActionContextMenu, {
            context: actionContext,
            favorites,
            allowed,
            onActivate: activateAction,
            onFavorite: handleFavorite,
            onClose: () => setActionContext(null)
        })
        // Personal vehicles now handled inline via ActionItem
    );
}

const rootElement = document.getElementById('root');
if (rootElement) {
    ReactDOM.createRoot(rootElement).render(React.createElement(App));
} else if (window.console && typeof window.console.error === 'function') {
    window.console.error('[cortex-admin] Missing #root element');
}
