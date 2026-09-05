import { test } from 'bun:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import matte from '../ui/wardrobe-matte.js';

const BACKINGS = [[24, 128, 24], [224, 48, 224]];
function backing(rgb, size = 64) {
    return Uint8ClampedArray.from({ length: size * size * 4 }, (_, i) => i % 4 === 3 ? 255 : rgb[i % 4]);
}
const uniformBackgrounds = () => ({ first: backing(BACKINGS[0]), second: backing(BACKINGS[1]) });
function garment(frame, bg, color, alpha = 1, bounds = [20, 18, 44, 48], size = 64) {
    for (let y = bounds[1]; y < bounds[3]; y += 1) for (let x = bounds[0]; x < bounds[2]; x += 1) {
        const i = (y * size + x) * 4;
        for (let c = 0; c < 3; c += 1) frame[i + c] = color[c] * alpha + bg[c] * (1 - alpha);
    }
}

test('dual backing removes the stage, preserves green, magenta and black clothing, and recovers antialiased edges', () => {
    for (const color of [...BACKINGS, [0, 0, 0], [240, 242, 245]]) {
        for (const alpha of [1, 0.5]) {
            const frames = BACKINGS.map(bg => { const frame = backing(bg); garment(frame, bg, color, alpha); return frame; });
            const result = matte.extract(...frames, 64, 64, uniformBackgrounds());
            assert.equal(result.empty, false);
            assert.deepEqual(result.bounds, { x: 18, y: 16, width: 28, height: 34 });
            assert.equal(result.data[3], 0, 'the stage must be transparent');
            const pixel = (24 * 64 + 24) * 4;
            for (let c = 0; c < 3; c += 1) assert.ok(Math.abs(result.data[pixel + c] - color[c]) <= 3);
            assert.ok(Math.abs(result.data[pixel + 3] - alpha * 255) <= 2);
        }
    }
});

test('a clean backdrop with uneven rendered shading uses measured background pixels instead of rejecting its corners', () => {
    const backgrounds = BACKINGS.map(bg => {
        const frame = backing(bg);
        for (let y = 0; y < 64; y += 1) for (let x = 0; x < 64; x += 1) {
            const shade = 0.65 + 0.35 * (x + y) / 126;
            for (let c = 0; c < 3; c += 1) frame[(y * 64 + x) * 4 + c] *= shade;
        }
        return frame;
    });
    const frames = backgrounds.map(background => {
        const frame = new Uint8ClampedArray(background);
        garment(frame, [0, 0, 0], [15, 120, 25]);
        return frame;
    });
    const result = matte.extract(...frames, 64, 64, { first: backgrounds[0], second: backgrounds[1] });
    assert.equal(result.empty, false);
    assert.deepEqual(result.bounds, { x: 18, y: 16, width: 28, height: 34 });
    assert.equal(result.data[3], 0);
    const pixel = (24 * 64 + 24) * 4;
    assert.deepEqual([...result.data.slice(pixel, pixel + 4)], [15, 120, 25, 255]);
});

test('measured coverage excludes small overlays outside the garment but rejects holes or broad missing coverage', () => {
    const run = (rect, expected) => {
        const backgrounds = BACKINGS.map(bg => backing(bg));
        for (const background of backgrounds) garment(background, [0, 0, 0], [80, 80, 80], 1, rect);
        const frames = backgrounds.map(background => {
            const frame = new Uint8ClampedArray(background);
            garment(frame, [0, 0, 0], [25, 25, 25]);
            return frame;
        });
        const extract = () => matte.extract(...frames, 64, 64, { first: backgrounds[0], second: backgrounds[1] });
        if (expected) assert.throws(extract, expected);
        else assert.equal(extract().empty, false);
    };
    run([2, 2, 6, 6]);
    run([25, 25, 29, 29], /overlaps the garment/);
    run([0, 0, 64, 8], /12.5%/);
});

test('blank clothing slots produce an empty marker; duplicate, clipped and moving captures fail instead of saving bad thumbnails', () => {
    const frames = BACKINGS.map(bg => backing(bg));
    assert.equal(matte.extract(...frames, 64, 64, uniformBackgrounds()).empty, true);
    assert.throws(() => matte.extract(frames[0], frames[0], 64, 64, { first: frames[0], second: frames[0] }), /did not change/);
    const clipped = BACKINGS.map(bg => { const frame = backing(bg); garment(frame, bg, [255, 0, 0], 1, [0, 20, 16, 40]); return frame; });
    assert.throws(() => matte.extract(...clipped, 64, 64, uniformBackgrounds()), /image edge/);
    const moved = BACKINGS.map((bg, index) => { const frame = backing(bg); garment(frame, bg, [10, 10, 10], 1, [20 + index * 8, 18, 44 + index * 8, 48]); return frame; });
    assert.throws(() => matte.extract(...moved, 64, 64, uniformBackgrounds()), /moved|lighting changed/);
});

test('thumbnail reads bound concurrency, discard cancelled pages, cache hits and invalidate after a job', async () => {
    let listener;
    const window = { addEventListener: (_, fn) => { listener = fn; } };
    vm.runInNewContext(readFileSync(new URL('../ui/wardrobe-capture.js', import.meta.url), 'utf8'), { window });
    const api = window.WardrobePhotos;
    const pending = [];
    let calls = 0, pageActive = true;
    const read = () => { calls += 1; return new Promise(resolve => pending.push(resolve)); };
    const reads = Array.from({ length: 24 }, (_, i) => api.read(String(i), read, () => pageActive));
    assert.equal(calls, 4);
    pageActive = false;
    pending.forEach(resolve => resolve({ ok: true, photo: 'data:image/webp;base64,UklGRabc' }));
    await Promise.all(reads);
    assert.equal(calls, 4, 'unmounted pages must not consume the remaining request budget');
    assert.equal(await api.read('0', read, () => true), 'data:image/webp;base64,UklGRabc');
    assert.equal(calls, 4);
    await listener({ data: { action: 'cortex-admin:catalog:changed' } });
    const refreshed = api.read('0', read, () => true);
    assert.equal(calls, 5);
    pending.at(-1)({ ok: false, error: 'forbidden' });
    assert.equal(await refreshed, null);
});

test('capture uses two measured stage frames and two garment frames before fitting a transparent 256px tile', async () => {
    let listener, response, frameIndex = 0, outputCanvas;
    const draws = [];
    const pixels = [...BACKINGS.map(bg => backing(bg, 1024)), ...BACKINGS.map(bg => {
        const frame = backing(bg, 1024); garment(frame, bg, [200, 20, 20], 1, [300, 250, 700, 750], 1024); return frame;
    })];
    const work = { getContext: () => ({ clearRect() {},
        drawImage: (...args) => draws.push(args.slice(1)), getImageData: () => ({ data: pixels[frameIndex++] }), putImageData() {} }) };
    const canvas = { getContext: () => ({ drawImage: (...args) => draws.push(args.slice(1)) }),
        toDataURL: (type, quality) => { assert.equal(type, 'image/webp'); assert.equal(quality, 0.92); return 'webp'; } };
    class Image { naturalWidth = 3440; naturalHeight = 1440; async decode() {} }
    const window = { addEventListener: (_, fn) => { listener = fn; } };
    vm.runInNewContext(readFileSync(new URL('../ui/wardrobe-capture.js', import.meta.url), 'utf8'), {
        window, Image, ImageData: class {}, WardrobeMatte: matte,
        document: { createElement: () => { if (!outputCanvas) { outputCanvas = canvas; return work; } return canvas; } },
        GetParentResourceName: () => 'cortex-admin', AbortSignal,
        fetch: async (url, options) => { assert.equal(url, 'https://cortex-admin/cortex-admin:catalog:processed'); response = JSON.parse(options.body); },
    });
    await listener({ data: { action: 'cortex-admin:catalog:process', v: 3, id: 'job', step: 9, capture: 4,
        images: ['stage A', 'stage B', 'garment A', 'garment B'] } });
    assert.deepEqual(draws[0], [1000, 0, 1440, 1440, 0, 0, 1024, 1024]);
    for (let i = 1; i < 4; i += 1) assert.deepEqual(draws[i], draws[0]);
    assert.deepEqual(draws[4].slice(0, 4), [298, 248, 404, 504], 'export crops to clothing bounds, not the whole character');
    assert.equal(draws[4][7], 216, 'longest side has consistent breathing room');
    assert.equal(canvas.width, 256);
    assert.equal(canvas.height, 256);
    assert.deepEqual(response, { id: 'job', step: 9, capture: 4, image: 'webp' });
});

test('the matte processor is packaged and loaded before its capture consumer', () => {
    const html = readFileSync(new URL('../ui/index.html', import.meta.url), 'utf8');
    const manifest = readFileSync(new URL('../fxmanifest.lua', import.meta.url), 'utf8');
    assert.ok(html.indexOf('src="wardrobe-matte.js"') >= 0);
    assert.ok(html.indexOf('src="wardrobe-matte.js"') < html.indexOf('src="wardrobe-capture.js"'));
    assert.ok(manifest.includes("'ui/wardrobe-matte.js'"));
    assert.ok(manifest.includes("'ui/wardrobe-capture.js'"));
});
