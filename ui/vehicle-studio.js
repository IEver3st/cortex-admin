function vehicleModChoiceLabel(item, state, value) {
    if (value === -1) return 'Stock';
    const nativeName = state.names?.[value];
    if (nativeName && nativeName !== 'NULL') return nativeName;
    const prefix = item.id === 15 ? 'Setup' : item.id === 16 ? 'Level' : item.cat === 'Performance' ? 'Stage' : 'Variant';
    return `${prefix} ${String(value + 1).padStart(2, '0')}`;
}

function VehicleModChoices({ item, state, pending, onSelect }) {
    const h = React.createElement;
    const list = React.useRef(null);
    React.useEffect(() => {
        const owner = list.current;
        const selected = owner?.querySelector('[aria-pressed="true"]');
        if (selected) owner.scrollTop = Math.max(0, selected.offsetTop - (owner.clientHeight - selected.offsetHeight) / 2);
    }, []);
    const total = state.max + 1;
    return h('div', { className: 'vehicle-mod-choices' },
        h('div', { ref: list, className: 'vehicle-mod-choice-list', role: 'group', 'aria-label': `${item.label} variants` },
            Array.from({ length: total }, (_, index) => {
                const value = index - 1;
                const selected = value === state.current;
                return h('button', { key: value, type: 'button', className: 'vehicle-mod-choice',
                    'aria-pressed': selected, 'aria-disabled': pending, onClick: () => onSelect(value) },
                    h('span', { className: 'vehicle-mod-choice-number', 'aria-hidden': true }, value === -1 ? 'S' : String(value + 1).padStart(2, '0')),
                    h('span', { className: 'vehicle-mod-choice-name' }, vehicleModChoiceLabel(item, state, value)),
                    selected && h(Icon, { name: 'check', size: 14 }));
            })));
}

function VehicleModWorkbench({ mods, config, onUpdate }) {
    const h = React.createElement;
    const [mode, setMode] = React.useState('Performance');
    const [group, setGroup] = React.useState('Exterior');
    const [expanded, setExpanded] = React.useState(null);
    const [pending, setPending] = React.useState(null);
    const [feedback, setFeedback] = React.useState(null);
    const locked = React.useRef(false);
    const alive = React.useRef(true);
    const detailsId = React.useId();
    React.useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);
    const available = config.filter(item => item.cat !== 'Wheels' && mods[item.id] && (mods[item.id].isToggle || mods[item.id].max > 0));
    const groups = [['Exterior', 'Exterior'], ['Interior', 'Cabin'], ['Engine', 'Engine bay'], ['Misc', 'Other']]
        .filter(([id]) => available.some(item => item.cat === id));
    const activeGroup = groups.some(([id]) => id === group) ? group : groups[0]?.[0];
    const items = available.filter(item => item.cat === (mode === 'Performance' ? mode : activeGroup));
    const change = async (item, value) => {
        if (locked.current) return;
        const state = mods[item.id];
        const toggle = !!(item.isToggle || state.isToggle);
        if ((toggle ? !!state.enabled : state.current) === value) return;
        locked.current = true;
        setPending(item.id);
        setFeedback({ text: `Applying ${item.label.toLowerCase()}…`, error: false });
        let ok = false;
        try { ok = await onUpdate('mod', item.id, toggle ? null : value, toggle, toggle ? value : undefined); }
        catch { /* Keep the confirmed selection and offer a retry on the same control. */ }
        finally {
            locked.current = false;
            if (alive.current) {
                setPending(null);
                setFeedback({ text: ok ? `${item.label} applied` : `${item.label} was not applied. Try again.`, error: !ok });
            }
        }
    };
    const toggleControl = item => {
        const state = mods[item.id];
        return h('button', { key: item.id, type: 'button', className: 'vehicle-mod-switch appearance-generator-switch studio-toggle-row', role: 'switch',
            'aria-label': item.label, 'aria-checked': !!state.enabled, 'aria-disabled': pending !== null,
            onClick: () => change(item, !state.enabled) },
            h('span', null, h('strong', null, item.label), h('small', null, pending === item.id ? 'Applying…' : state.enabled ? 'Enabled' : 'Disabled')),
            h('span', { className: 'studio-switch-state', 'aria-hidden': true }, state.enabled ? 'On' : 'Off'));
    };
    return h('div', { className: 'vehicle-mod-workbench', 'aria-busy': pending !== null },
        h('nav', { className: 'vehicle-mod-modes', 'aria-label': 'Modification type' },
            [['Performance', 'gauge'], ['Bodywork', 'car-front']].map(([id, icon]) => h('button', {
                key: id, type: 'button', 'aria-pressed': mode === id, onClick: () => { setMode(id); setExpanded(null); }
            }, h(Icon, { name: icon, size: 16 }), id))),
        mode === 'Bodywork' && groups.length > 0 && h('nav', { className: 'vehicle-mod-groups', 'aria-label': 'Bodywork groups' },
            groups.map(([id, label]) => h('button', { key: id, type: 'button', 'aria-pressed': activeGroup === id,
                onClick: () => { setGroup(id); setExpanded(null); } }, label))),
        h('div', { className: 'vehicle-mod-sheet-heading' }, h('span', null, mode === 'Performance' ? 'Tuning sheet' : 'Parts catalogue'),
            h('span', null, mode === 'Performance' ? 'Stock / upgrade' : `${items.length} ${items.length === 1 ? 'part' : 'parts'}`)),
        items.length === 0 && h('p', { className: 'vehicle-mod-empty' }, `This vehicle has no ${mode === 'Performance' ? 'performance upgrades' : 'bodywork options'}.`),
        h('div', { className: 'vehicle-mod-sheet' }, items.map(item => {
            const state = mods[item.id];
            if (item.isToggle || state.isToggle) return toggleControl(item);
            const selectedName = vehicleModChoiceLabel(item, state, state.current);
            if (mode === 'Performance' && state.max <= 8) return h('section', { key: item.id, className: 'vehicle-mod-stage-row', 'aria-label': item.label },
                h('div', { className: 'vehicle-mod-row-heading' }, h('strong', null, item.label), h('span', null, pending === item.id ? 'Applying…' : selectedName)),
                h('div', { className: 'vehicle-mod-stages', role: 'group', 'aria-label': `${item.label} upgrade` },
                    Array.from({ length: state.max + 1 }, (_, index) => {
                        const value = index - 1;
                        return h('button', { key: value, type: 'button', className: `vehicle-mod-stage${value >= 0 && value <= state.current ? ' is-reached' : ''}`,
                            'aria-label': `${item.label}: ${vehicleModChoiceLabel(item, state, value)}`,
                            title: vehicleModChoiceLabel(item, state, value), 'aria-pressed': state.current === value,
                            'aria-disabled': pending !== null, onClick: () => change(item, value) }, value === -1 ? 'Stock' : String(value + 1).padStart(2, '0'));
                    })));
            const isExpanded = expanded === item.id;
            const id = `${detailsId}-${item.id}`;
            return h('section', { key: item.id, className: `vehicle-mod-part${isExpanded ? ' is-expanded' : ''}` },
                h('button', { type: 'button', className: 'vehicle-mod-part-trigger', 'aria-expanded': isExpanded, 'aria-controls': isExpanded ? id : undefined,
                    onClick: () => setExpanded(isExpanded ? null : item.id) },
                    h('span', { className: 'vehicle-mod-part-copy' }, h('strong', null, item.label), h('small', null, pending === item.id ? 'Applying…' : selectedName)),
                    h('span', { className: 'vehicle-mod-part-count', title: `${state.max} variants plus stock` }, String(state.max).padStart(2, '0')),
                    h(Icon, { name: isExpanded ? 'chevron-up' : 'chevron-down', size: 15 })),
                isExpanded && h('div', { id }, h(VehicleModChoices, { key: item.id, item, state, pending: pending !== null, onSelect: value => change(item, value) })));
        })),
        h('div', { className: `vehicle-mod-feedback${feedback?.error ? ' is-error' : ''}`, role: 'status', 'aria-live': 'polite' },
            feedback ? feedback.text : 'Select a part to apply it.'));
}

function VehicleStudioWorkspace({ menuOpen, launchRequest = 0, onExit }) {
    const h = React.createElement;
    const [studio, setStudio] = React.useState(null);
    const [model, setModel] = React.useState('sultan');
    const [busy, setBusy] = React.useState(false);
    const [section, setSection] = React.useState('colors');
    const [message, setMessage] = React.useState('');
    const [name, setName] = React.useState('');
    const [minutes, setMinutes] = React.useState(720);
    const [cycle, setCycle] = React.useState(false);
    const [saving, setSaving] = React.useState(false);
    const [live, setLive] = React.useState(false);
    const current = React.useRef(null);
    const mounted = React.useRef(true);
    const menu = React.useRef(menuOpen);
    const operation = React.useRef(0);
    const queue = React.useRef(null);
    const cycleEpoch = React.useRef({ base: 720, at: 0 });
    menu.current = menuOpen;
    const tabs = [['mods', 'Body & performance'], ['colors', 'Paint'], ['wheels', 'Wheels'], ['extras', 'Extras'], ['liveries', 'Liveries'], ['lights', 'Lights']];
    const errors = {
        forbidden: 'Your role does not allow this action.', invalid_model: 'Enter a valid vehicle model name.',
        model_load_failed: 'The vehicle model could not load. Try another model.',
        stand_on_foot: 'Exit your vehicle before previewing another model.', camera_busy: 'Close the other camera first.',
        no_source_vehicle: 'Enter a vehicle first, or stand near the vehicle you just left.', source_too_far: 'Your last vehicle must be within 15 metres.',
        driver_required: 'Use the driver seat, or a vehicle with an empty driver seat.',
        no_control: 'Vehicle control is unavailable. Enter the driver seat and retry.',
        vehicle_destroyed: 'This vehicle is destroyed.',
        ground_unavailable: 'Move to an open, level outdoor area and retry.', model_too_large: 'This model is too large for the studio.',
        name_exists: 'That garage name already exists. Choose another.', invalid_name: 'Use a name between 1 and 64 characters.',
        studio_session_expired: 'This session has closed. Reopen the studio.', cancelled: 'Opening cancelled.'
    };
    const close = React.useCallback(() => {
        operation.current++;
        const active = current.current;
        current.current = null;
        setStudio(null); setBusy(false); setCycle(false);
        fetchNui('cortex-admin:vehicleStudio', { action: 'close', session: active?.session });
    }, []);
    React.useEffect(() => {
        mounted.current = true;
        queue.current = createVehicleUpdateQueue(payload => fetchNui('cortex-admin:vehicleStudio', payload));
        return () => {
            mounted.current = false; operation.current++; queue.current.close();
            fetchNui('cortex-admin:vehicleStudio', { action: 'close', session: current.current?.session });
        };
    }, []);
    React.useEffect(() => { if (!menuOpen) close(); }, [menuOpen, close]);
    React.useEffect(() => {
        if (!cycle) return;
        const timer = setInterval(() => setMinutes(Math.floor((cycleEpoch.current.base + (performance.now() - cycleEpoch.current.at) * 1440 / 120000) % 1440)), 250);
        return () => clearInterval(timer);
    }, [cycle]);
    React.useEffect(() => {
        const receive = event => {
            if (event.data?.action === 'cortex-admin:vehicleStudioClosed'
                && event.data.session === current.current?.session) {
                current.current = null; setStudio(null); setCycle(false);
            }
        };
        window.addEventListener('message', receive);
        return () => window.removeEventListener('message', receive);
    }, []);
    React.useEffect(() => {
        if (!studio) return;
        document.body.classList.add('character-studio-open', 'vehicle-studio-open');
        const tick = requestAnimationFrame(() => document.querySelector('.vehicle-studio .studio-tabs button')?.focus());
        return () => {
            cancelAnimationFrame(tick);
            document.body.classList.remove('character-studio-open', 'vehicle-studio-open');
            document.querySelector('.vehicle-studio-launcher button')?.focus();
        };
    }, [studio]);
    const open = async source => {
        if (busy) return;
        const token = ++operation.current;
        setBusy(true); setMessage('');
        const response = await fetchNui('cortex-admin:vehicleStudio', { action: 'open', source, model: model.trim() });
        const result = response.data;
        if (!mounted.current || !menu.current || token !== operation.current) {
            if (result?.ok) fetchNui('cortex-admin:vehicleStudio', { action: 'close', session: result.session });
            return;
        }
        setBusy(false);
        if (!response.ok || !result?.ok) return setMessage(errors[result?.error] || 'The studio could not open. Please retry.');
        current.current = result; setStudio(result); setName(''); setMinutes(720); setCycle(false); setSection('colors');
    };
    const lastStudioLaunch = React.useRef(0);
    React.useEffect(() => {
        if (!menuOpen || !launchRequest || lastStudioLaunch.current === launchRequest) return;
        lastStudioLaunch.current = launchRequest;
        open('current');
    }, [launchRequest, menuOpen]);
    const exitStudio = () => { close(); if (onExit) onExit(); };
    const control = async payload => {
        const session = current.current?.session;
        if (!session) return false;
        const response = await queue.current.push({ ...payload, session }, payload.action === 'lighting' ? `lighting:${session}` : null);
        if (response.superseded || response.cancelled) return false;
        if (!mounted.current || current.current?.session !== session) return false;
        if (!response.ok || !response.data?.ok) { setMessage(errors[response.data?.error] || 'The change could not be applied.'); return false; }
        setMessage(''); return true;
    };
    const lighting = (value, playing = false) => {
        cycleEpoch.current = { base: value, at: performance.now() };
        setMinutes(value); setCycle(playing);
        control({ action: 'lighting', minutes: value, cycle: playing });
    };
    const button = (label, icon, controlName, value) => h('button', {
        type: 'button', className: 'admin-button', 'aria-label': label, title: label,
        onClick: () => control({ action: 'camera', control: controlName, value })
    }, h(Icon, { name: icon, size: 17 }));
    const time = `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
    if (!studio) return h('div', { className: 'admin-appearance vehicle-studio-launcher' },
        h('span', { className: 'admin-section-kicker' }, 'VEHICLE WORKSHOP'),
        h('h2', null, 'Vehicle studio'),
        h('p', { className: 'studio-caption' }, 'Customize your current vehicle or the one you just left nearby. Changes apply directly to that vehicle.'),
        h('button', { type: 'button', className: 'admin-button studio-open-button', disabled: busy, onClick: () => open('current') },
            h(Icon, { name: 'car-front', size: 20 }), busy ? 'Preparing vehicle…' : 'Open vehicle studio', h(Icon, { name: 'arrow-up-right', size: 16 })),
        h('label', { className: 'vehicle-model-field' }, 'Vehicle model', h('input', { className: 'appearance-input', value: model, maxLength: 64,
            placeholder: 'sultan', disabled: busy, onChange: event => setModel(event.target.value), onKeyDown: event => { if (event.key === 'Enter' && !busy) open('model'); } })),
        h('button', { type: 'button', className: 'admin-button', disabled: busy || !model.trim(), onClick: () => open('model') }, 'Preview another model'),
        busy && h('button', { type: 'button', className: 'admin-button', onClick: close }, 'Cancel'),
        message && h('p', { role: 'alert', className: 'studio-error' }, message),
        h('button', { type: 'button', className: 'admin-button', 'aria-expanded': live, onClick: () => setLive(value => !value) }, live ? 'Hide live customizer' : 'Customize the vehicle I’m driving'),
        live && h(MemoVehicleView));
    return ReactDOM.createPortal(h('section', { className: 'character-studio vehicle-studio', 'aria-label': 'Vehicle studio',
        onKeyDown: event => { event.stopPropagation(); if (event.key === 'Escape' && !event.defaultPrevented) { event.preventDefault(); exitStudio(); } } },
        h('header', { className: 'studio-topbar' },
            h('div', { className: 'studio-brand' }, h('strong', null, 'CORTEX'), h('span', null, 'Vehicle studio')),
            h('nav', { className: 'studio-tabs', 'aria-label': 'Vehicle sections' }, tabs.map(([id, label]) => h('button', { key: id, type: 'button', 'aria-pressed': id === section, onClick: () => setSection(id) }, label))),
            h('div', { className: 'studio-head-actions' }, h('button', { type: 'button', className: 'studio-done', onClick: exitStudio }, 'Done', h(Icon, { name: 'arrow-up-right', size: 16 })))),
        h('div', { className: 'studio-panels' },
            h('section', { className: 'studio-panel studio-panel-primary' },
                h('div', { className: 'studio-panel-heading' }, h('div', { className: 'studio-overline' }, studio.preview ? 'PRIVATE PREVIEW' : 'EDITING YOUR VEHICLE'), h('h1', null, studio.label)),
                h('div', { className: 'studio-panel-scroll' }, h(MemoVehicleView, { key: studio.session, studioSession: studio.session, studioSection: section }))),
            h('aside', { className: 'studio-panel vehicle-lighting-panel', 'aria-label': 'Preview lighting and garage save' },
                h('div', { className: 'studio-drawer-heading' }, h('h2', null, 'Light study')),
                h('div', { className: 'studio-panel-scroll' },
                    h('div', { className: 'vehicle-light-time' }, h('strong', null, time), h('span', null, cycle ? '2-minute cycle' : 'Local time')),
                    h('div', { className: 'vehicle-light-presets' }, [[360, 'Dawn', 'sunrise'], [720, 'Day', 'sun'], [1110, 'Sunset', 'sunset'], [1380, 'Night', 'moon']].map(([value, label, icon]) => h('button', {
                        key: value, type: 'button', 'aria-pressed': !cycle && minutes === value, onClick: () => lighting(value)
                    }, h(Icon, { name: icon, size: 18 }), label))),
                    h('label', { className: 'vehicle-time-slider' }, 'Time of day', h('input', { type: 'range', min: 0, max: 1439, step: 1, value: minutes,
                        disabled: cycle, onChange: event => lighting(Number(event.target.value)), 'aria-valuetext': time })),
                    h(StudioSwitch, { label: 'Cycle day & night', checked: cycle, onChange: enabled => lighting(minutes, enabled) }),
                    h('p', { className: 'studio-caption' }, 'Lighting changes are visible only to you.'),
                    h('form', { className: 'vehicle-studio-save', onSubmit: async event => {
                        event.preventDefault(); if (saving) return; setSaving(true);
                        if (await control({ action: 'save', name })) setMessage('Build saved to your personal garage.');
                        if (mounted.current) setSaving(false);
                    } }, h('h3', null, 'Keep this build'),
                        h('input', { className: 'appearance-input', value: name, maxLength: 64, placeholder: 'Name this build', 'aria-label': 'Build name', disabled: !studio.canSave || saving, onChange: event => setName(event.target.value) }),
                        h('button', { type: 'submit', className: 'admin-button', disabled: !studio.canSave || !name.trim() || saving }, saving ? 'Saving…' : 'Save to garage'),
                        !studio.canSave && h('p', { className: 'studio-caption' }, 'Your role cannot save vehicles.')),
                    message && h('p', { className: 'vehicle-studio-status', role: 'status', 'aria-live': 'polite' }, message)))),
        h('footer', { className: 'studio-footer' }, h('div', { className: 'studio-camera' },
            studio.preview && h('div', { className: 'vehicle-camera-group' }, h('span', null, 'VEHICLE'), button('Rotate vehicle left', 'rotate-ccw', 'rotate', -1), button('Rotate vehicle right', 'rotate-cw', 'rotate', 1)),
            h('div', { className: 'vehicle-camera-group' }, h('span', null, 'CAMERA'), button('Orbit left', 'chevron-left', 'orbit', -1), button('Orbit right', 'chevron-right', 'orbit', 1), button('Zoom in', 'zoom-in', 'zoom', -1), button('Zoom out', 'zoom-out', 'zoom', 1), button('Low angle', 'arrow-down', 'view', 'low'), button('High angle', 'arrow-up', 'view', 'high'), button('Reset view', 'focus', 'reset'))),
            h('span', { className: 'studio-caption' }, studio.preview ? 'Preview only · Save to keep your build' : 'Changes apply to your vehicle · Garage save is optional', h('span', null, 'ESC / RETURN')))
    ), document.body);
}
