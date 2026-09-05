// Recover foreground alpha from two stationary renders against different backings.
// Unlike hue keying, a green or magenta garment remains opaque in both frames.
(() => {
    const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
    function extract(first, second, width, height, backgrounds) {
        if (!Number.isInteger(width) || !Number.isInteger(height) || width < 16 || height < 16
            || width > 1024 || height > 1024 || first.length !== width * height * 4 || second.length !== first.length) {
            throw new Error('Invalid capture dimensions.');
        }
        if (!backgrounds || backgrounds.first?.length !== first.length || backgrounds.second?.length !== first.length) {
            throw new Error('Measured backdrop frames are missing. Restart cortex-admin.');
        }
        const a = backgrounds.first, b = backgrounds.second;
        const unmeasured = new Uint8Array(width * height);
        let missing = 0;
        for (let i = 0; i < first.length; i += 4) {
            const energy = (b[i] - a[i]) ** 2 + (b[i + 1] - a[i + 1]) ** 2 + (b[i + 2] - a[i + 2]) ** 2;
            if (energy < 1600) { unmeasured[i / 4] = 1; missing += 1; }
        }
        if (missing > width * height * 0.02) {
            throw new Error(`Backdrop did not change across ${(100 * missing / (width * height)).toFixed(1)}% of the capture. Stage coverage, camera, or an overlay needs inspection.`);
        }
        const data = new Uint8ClampedArray(first.length);
        let left = width, top = height, right = -1, bottom = -1, mass = 0, unstable = 0;
        for (let i = 0; i < data.length; i += 4) {
            if (unmeasured[i / 4]) continue;
            let dot = 0, energy = 0;
            for (let c = 0; c < 3; c += 1) {
                const delta = b[i + c] - a[i + c];
                dot += (second[i + c] - first[i + c]) * delta;
                energy += delta * delta;
            }
            let alpha = clamp(1 - dot / energy, 0, 1);
            if (alpha < 0.035) continue;
            if (alpha > 0.965) alpha = 1;
            let residual = 0;
            for (let c = 0; c < 3; c += 1) {
                residual += ((second[i + c] - first[i + c]) - (1 - alpha) * (b[i + c] - a[i + c])) ** 2;
                data[i + c] = clamp((first[i + c] + second[i + c] - (1 - alpha) * (a[i + c] + b[i + c])) / (2 * alpha), 0, 255);
            }
            if (residual > 1800) unstable += 1;
            data[i + 3] = Math.round(alpha * 255);
            if (alpha > 0.12) {
                const x = (i / 4) % width, y = Math.floor(i / 4 / width);
                left = Math.min(left, x); right = Math.max(right, x);
                top = Math.min(top, y); bottom = Math.max(bottom, y);
                mass += alpha;
            }
        }
        if (mass < 4) return { empty: true, data, bounds: null };
        if (unstable > Math.max(12, mass * 0.025)) {
            throw new Error('Clothing moved or lighting changed between captures. Retry sample with other camera/weather effects disabled.');
        }
        if (left < 2 || top < 2 || right > width - 3 || bottom > height - 3) {
            throw new Error('The garment or another overlay touches the image edge. Retry sample with a clear capture view.');
        }
        let covered = 0;
        for (let y = top; y <= bottom; y += 1) for (let x = left; x <= right; x += 1) covered += unmeasured[y * width + x];
        if (covered > Math.max(2, (right - left + 1) * (bottom - top + 1) * 0.002)) {
            throw new Error('A non-responsive backdrop region overlaps the garment. Capture aborted to avoid a hole in the cutout.');
        }
        const padding = 2;
        left = Math.max(0, left - padding); top = Math.max(0, top - padding);
        right = Math.min(width - 1, right + padding); bottom = Math.min(height - 1, bottom + padding);
        return { empty: false, data, bounds: { x: left, y: top, width: right - left + 1, height: bottom - top + 1 } };
    }
    const api = { extract };
    globalThis.WardrobeMatte = api;
    if (typeof module !== 'undefined') module.exports = api;
})();
