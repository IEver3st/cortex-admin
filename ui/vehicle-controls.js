/* Shared studio controls. Native availability stays authoritative. */
function createVehicleUpdateQueue(send) {
    let running = false;
    let closed = false;
    const pending = [];
    const drain = async () => {
        if (running || closed) return;
        running = true;
        while (pending.length && !closed) {
            const job = pending.shift();
            try { job.resolve(await send(job.payload)); }
            catch (error) { job.resolve({ ok: false, error: String(error) }); }
        }
        running = false;
    };
    return {
        push(payload, key) {
            if (closed) return Promise.resolve({ cancelled: true });
            return new Promise(resolve => {
                // Only replace consecutive unsent changes to the same control.
                // A wheel-type / wheel-index boundary must retain its ordering.
                const tail = pending[pending.length - 1];
                if (key && tail?.key === key) {
                    pending.pop().resolve({ superseded: true });
                }
                pending.push({ payload, key, resolve });
                drain();
            });
        },
        close() {
            closed = true;
            pending.splice(0).forEach(job => job.resolve({ cancelled: true }));
        }
    };
}

function applyVehicleDraft(prev, { type, id, value, isToggle, enabled }) {
    if (!prev) return prev;
    if (type === 'mod') return { ...prev, mods: { ...prev.mods, [id]: { ...prev.mods[id], ...(isToggle ? { enabled } : { current: value }) } } };
    if (type === 'color') return { ...prev, colors: { ...prev.colors, [id]: value },
        ...(id === 'primary' ? { customPrimary: { ...prev.customPrimary, enabled: false } } : {}),
        ...(id === 'secondary' ? { customSecondary: { ...prev.customSecondary, enabled: false } } : {}) };
    if (type === 'paintFinish') return { ...prev, paintFinish: { ...prev.paintFinish, [id]: value } };
    if (type === 'customColor') {
        const key = id === 'primary' ? 'customPrimary' : 'customSecondary';
        return { ...prev, [key]: { enabled: !!enabled, value: value || prev[key]?.value || [0, 0, 0] } };
    }
    if (type === 'extra') return { ...prev, extras: (prev.extras || []).map(extra => extra.id === id ? { ...extra, enabled: !!enabled } : extra) };
    if (type === 'neon') return id === 'all'
        ? { ...prev, neonFront: value, neonBack: value, neonLeft: value, neonRight: value }
        : { ...prev, ['neon' + id.charAt(0).toUpperCase() + id.slice(1)]: value };
    return { ...prev, [type === 'enveff' ? 'enveffScale' : type === 'window' ? 'windowTint' : type]: value };
}

function StudioSwitch({ label, description, checked, disabled, onChange }) {
    const h = React.createElement;
    return h('button', { type: 'button', className: 'appearance-generator-switch studio-toggle-row',
        role: 'switch', 'aria-checked': !!checked, disabled, onClick: () => onChange(!checked) },
        h('span', null, h('strong', null, label), description && h('small', null, description)),
        h('span', { className: 'studio-switch-state', 'aria-hidden': true }, checked ? 'On' : 'Off'));
}

function vehicleWheelImage(type, name) {
    // Do not infer an image from its native index: DLC and add-ons can change it.
    const key = String(name || '').toLowerCase().replace(/[^a-z0-9]/g, '');
    return window.VehicleCatalogData?.wheels[String(type)]?.[key]?.image;
}

function VehicleCatalogPages({ page, count, size, onPage }) {
    const h = React.createElement;
    const pages = Math.max(1, Math.ceil(count / size));
    return h('div', { className: 'vehicle-catalog-pages' },
        h('button', { type: 'button', disabled: page <= 0, onClick: () => onPage(page - 1), 'aria-label': 'Previous page' }, 'Previous'),
        h('span', null, `${page + 1} / ${pages}`),
        h('button', { type: 'button', disabled: page >= pages - 1, onClick: () => onPage(page + 1), 'aria-label': 'Next page' }, 'Next'));
}

function VehiclePaintPicker({ channels, colors, customPrimary, customSecondary, onChange }) {
    const h = React.createElement;
    const [channel, setChannel] = React.useState('primary');
    const [query, setQuery] = React.useState('');
    const [page, setPage] = React.useState(0);
    const palette = window.VehicleCatalogData.colors;
    const active = palette.find(color => color.id === colors[channel]);
    const custom = channel === 'primary' ? customPrimary : channel === 'secondary' ? customSecondary : null;
    const filtered = palette.filter(color => `${color.id} ${color.name}`.toLowerCase().includes(query.toLowerCase().trim()));
    const visiblePage = Math.min(page, Math.max(0, Math.ceil(filtered.length / 64) - 1));
    return h('div', { className: 'vehicle-paint-picker' },
        h('div', { className: 'vehicle-paint-channels', 'aria-label': 'Paint areas' }, channels.map(item => {
            const selected = palette.find(color => color.id === colors[item.id]);
            const rgb = item.id === 'primary' ? customPrimary : item.id === 'secondary' ? customSecondary : null;
            const hex = rgb?.enabled ? `rgb(${rgb.value.join(',')})` : selected?.hex;
            return h('button', { key: item.id, type: 'button', 'aria-pressed': channel === item.id,
                onClick: () => { setChannel(item.id); setQuery(''); setPage(Math.floor((selected?.id || 0) / 64)); } },
                h('span', { className: 'vehicle-color-chip', style: hex ? { backgroundColor: hex } : {}, 'aria-hidden': true }), item.label);
        })),
        h('div', { className: 'vehicle-catalog-selection', 'aria-live': 'polite' },
            h('strong', null, custom?.enabled ? 'Custom RGB active' : active?.name || `Special finish #${colors[channel]}`),
            h('span', null, custom?.enabled ? custom.value.join(' / ') : `#${colors[channel]}`)),
        h('input', { type: 'search', className: 'appearance-input', value: query, placeholder: 'Find a color or ID', 'aria-label': 'Find paint color',
            onChange: event => { setQuery(event.target.value); setPage(0); } }),
        h('div', { className: 'vehicle-paint-grid', 'aria-label': `${channel} paint colors` }, filtered.slice(visiblePage * 64, (visiblePage + 1) * 64).map(color =>
            h('button', { key: color.id, type: 'button', title: `${color.name} · #${color.id}`, 'aria-label': `${color.name}, color ${color.id}`,
                'aria-pressed': !custom?.enabled && color.id === colors[channel], style: { backgroundColor: color.hex }, onClick: () => onChange(channel, color.id) },
                h('span', { 'aria-hidden': true }, color.id)))),
        filtered.length === 0 && h('p', { className: 'studio-caption' }, 'No colors match.'),
        h(VehicleCatalogPages, { page: visiblePage, count: filtered.length, size: 64, onPage: setPage }),
        h('p', { className: 'studio-caption' }, 'Base color samples. Finish and lighting are visible on the vehicle.'));
}

function VehicleWheelPicker({ type, slot, label, mod, disabled, onChange }) {
    const h = React.createElement;
    const [query, setQuery] = React.useState('');
    const [page, setPage] = React.useState(0);
    const [failed, setFailed] = React.useState({});
    if (!mod || mod.max <= 0) return null;
    const choices = Array.from({ length: mod.max + 1 }, (_, position) => {
        const id = position - 1;
        const name = id === -1 ? 'Stock' : mod.names?.[id] || `Wheel #${id}`;
        return { id, name, image: id >= 0 ? vehicleWheelImage(type, name) : null };
    });
    const filtered = choices.filter(item => `${item.name} ${item.id}`.toLowerCase().includes(query.toLowerCase().trim()));
    const visiblePage = Math.min(page, Math.max(0, Math.ceil(filtered.length / 9) - 1));
    return h('section', { className: 'vehicle-wheel-picker', 'aria-label': label, 'aria-busy': disabled },
        h('div', { className: 'vehicle-catalog-selection' }, h('strong', null, label), h('span', null, `${mod.max} designs`)),
        h('input', { type: 'search', className: 'appearance-input', value: query, placeholder: 'Find a wheel or ID', 'aria-label': `Find ${label.toLowerCase()}`,
            onChange: event => { setQuery(event.target.value); setPage(0); } }),
        h('div', { className: 'vehicle-wheel-grid' }, filtered.slice(visiblePage * 9, (visiblePage + 1) * 9).map(item =>
            h('button', { key: item.id, type: 'button', disabled, 'aria-pressed': mod.current === item.id,
                'aria-label': `${item.name}, ${item.id === -1 ? 'stock' : 'wheel ' + item.id}`, onClick: () => onChange(slot, item.id) },
                item.image && !failed[item.image]
                    ? h('img', { src: item.image, alt: '', loading: 'lazy', decoding: 'async', width: 192, height: 192,
                        onError: () => setFailed(prev => ({ ...prev, [item.image]: true })) })
                    : h('span', { className: 'vehicle-wheel-no-image' }, item.id === -1 ? 'FACTORY' : 'LIVE PREVIEW'),
                h('strong', null, item.name), h('small', null, item.id === -1 ? 'Original wheels' : `#${item.id}`)))),
        filtered.length === 0 && h('p', { className: 'studio-caption' }, 'No wheels match.'),
        h(VehicleCatalogPages, { page: visiblePage, count: filtered.length, size: 9, onPage: setPage }),
        h('p', { className: 'studio-caption' }, 'Design references · GTA Wiki. Paint and tires vary. Unpictured wheels preview on your vehicle.'));
}

function vehiclePlateChoices(options, build) {
    return options.filter(option => !option.minBuild || Number(build) >= option.minBuild);
}

function VehiclePlatePicker({ options, value, text, gameBuild, disabled, onChange }) {
    const h = React.createElement;
    const [failed, setFailed] = React.useState({});
    const available = vehiclePlateChoices(options, gameBuild);
    const selected = options.find(option => option.value === value);
    const registration = String(text || 'CORTEX').trim().slice(0, 8);
    const inks = { 0: '#152b55', 1: '#e3b652', 2: '#e3b652', 3: '#152b55', 4: '#152b55', 5: '#172027',
        6: '#fff', 7: '#173247', 8: '#152b55', 9: '#152b55', 10: '#f4cf54', 11: '#eac458', 12: '#fff' };
    return h('section', { className: 'vehicle-plate-picker', 'aria-label': 'Plate type' },
        h('div', { className: 'vehicle-catalog-selection' }, h('strong', null, 'Plate type'), h('span', null, selected?.label || `Style #${value}`)),
        h('div', { className: 'vehicle-plate-grid' }, available.map(option => {
            const image = window.VehicleCatalogData.plates?.[option.value];
            return h('button', { key: option.value, type: 'button', disabled, 'aria-label': option.label,
                'aria-pressed': option.value === value, onClick: () => onChange(option.value) },
                h('span', { className: 'vehicle-plate-example' },
                    image && !failed[image] && h('img', { src: image, alt: '', loading: 'lazy', decoding: 'async', width: 256, height: 128,
                        onError: () => setFailed(prev => ({ ...prev, [image]: true })) }),
                    h('span', { className: 'vehicle-plate-registration', style: { color: image && !failed[image] ? inks[option.value] : 'inherit' }, 'aria-hidden': true }, registration)),
                h('strong', null, option.label), h('small', null, `#${option.value}`));
        })),
        h('p', { className: 'studio-caption' }, 'Style examples use your existing plate text. Vehicle-specific plate replacements may differ.'),
        available.length < options.length && h('p', { className: 'studio-caption' }, 'Additional plate styles require game build 3095 or newer.'));
}

function VehicleTintExample({ id, label }) {
    const h = React.createElement;
    const clip = React.useId();
    // Known native glass colors come from carcols. The two additional native
    // enum entries have no dumped material, so their examples are illustrative.
    const tint = window.VehicleCatalogData.tints?.[id] ?? (id === 6 ? '#344c3e99' : '#080a0ae0');
    return h('svg', { viewBox: '0 0 220 96', role: 'img', 'aria-label': `${label} tint illustration` },
        h('defs', null, h('clipPath', { id: clip }, h('path', { d: 'M28 18H154L192 76H13Z' }))),
        h('path', { d: 'M23 11H159L205 83H4Z', fill: '#70787c' }),
        h('g', { clipPath: `url(#${clip})` },
            h('path', { d: 'M0 0H220V96H0Z', fill: '#a8b8be' }),
            h('path', { d: 'M0 46L41 30L74 44L110 29L158 39L193 24L220 36V96H0Z', fill: '#849592' }),
            h('path', { d: 'M39 36H58Q63 36 63 42V50H68L77 80H24L34 50H37V41Q37 36 39 36M122 36H141Q146 36 146 42V50H151L160 80H107L117 50H120V41Q120 36 122 36', fill: '#4b5053' }),
            h('path', { d: 'M0 0H220V96H0Z', fill: tint })),
        h('path', { d: 'M28 18H154L192 76H13Z', fill: 'none', stroke: '#20262a', strokeWidth: 4 }),
        h('path', { d: 'M91 18L91 76', stroke: '#20262a', strokeWidth: 5 }));
}

function VehicleTintPicker({ options, value, disabled, onChange }) {
    const h = React.createElement;
    return h('section', { className: 'vehicle-tint-picker', 'aria-label': 'Window tint' },
        h('div', { className: 'vehicle-catalog-selection' }, h('strong', null, 'Window tint'), h('span', null, options.find(option => option.value === value)?.label || 'Factory glass')),
        h('div', { className: 'vehicle-tint-grid' }, options.map(option =>
            h('button', { key: option.value, type: 'button', disabled, 'aria-pressed': option.value === value,
                'aria-label': option.label, onClick: () => onChange(option.value) },
                h(VehicleTintExample, { id: option.value, label: option.label }),
                h('strong', null, option.label), h('small', null, option.value === 4 ? 'Factory glass' : option.value >= 5 ? 'Model dependent' : `#${option.value}`)))),
        h('p', { className: 'studio-caption' }, 'Illustrated tint samples. Glass materials and lighting change the result; check it on the vehicle.'));
}
