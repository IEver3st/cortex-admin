// Full screenshots stay on the capture client. Only a bounded 256px thumbnail
// crosses the network. This listener performs no work while generation is idle.
(() => {
    const cache = new Map();
    const queue = [];
    let active = 0;
    const drain = () => {
        while (active < 4 && queue.length) {
            const task = queue.shift();
            if (!task.isActive()) { task.resolve(null); continue; }
            active += 1;
            task.read().then(result => {
                const photo = result?.ok && /^data:image\/webp;base64,/.test(result.photo) ? result.photo : null;
                if (photo) {
                    cache.set(task.key, photo);
                    if (cache.size > 128) cache.delete(cache.keys().next().value);
                }
                task.resolve(photo);
            }).catch(() => task.resolve(null)).finally(() => { active -= 1; drain(); });
        }
    };
    // Bound requests across fast page changes; cancelled pages never start new reads.
    window.WardrobePhotos = {
        read(key, read, isActive) {
            if (cache.has(key)) return Promise.resolve(cache.get(key));
            for (let i = queue.length - 1; i >= 0; i -= 1) {
                if (!queue[i].isActive()) queue.splice(i, 1)[0].resolve(null);
            }
            if (queue.length >= 96) return Promise.resolve(null);
            return new Promise(resolve => { queue.push({ key, read, isActive, resolve }); drain(); });
        },
    };
    window.addEventListener('message', async ({ data }) => {
        if (data?.action === 'cortex-admin:catalog:changed') { cache.clear(); return; }
        if (data?.action !== 'cortex-admin:catalog:process') return;
        const reply = { id: data.id, step: data.step, capture: data.capture };
        try {
            if (data.v !== 3 || !Array.isArray(data.images) || data.images.length !== 4) throw new Error('Capture protocol mismatch. Restart cortex-admin.');
            const images = await Promise.all(data.images.map(async src => {
                const image = new Image(); image.src = src; await image.decode(); return image;
            }));
            if (images.some(image => image.naturalWidth !== images[0].naturalWidth || image.naturalHeight !== images[0].naturalHeight)) {
                throw new Error('Resolution changed between captures. Retry sample.');
            }
            const edge = Math.min(images[0].naturalWidth, images[0].naturalHeight);
            const size = Math.min(1024, edge);
            const work = document.createElement('canvas');
            work.width = work.height = size;
            const context = work.getContext('2d', { willReadFrequently: true });
            const pixels = images.map(image => {
                context.clearRect(0, 0, size, size);
                context.drawImage(image, (image.naturalWidth - edge) / 2, (image.naturalHeight - edge) / 2, edge, edge, 0, 0, size, size);
                return context.getImageData(0, 0, size, size).data;
            });
            const matte = WardrobeMatte.extract(pixels[2], pixels[3], size, size, { first: pixels[0], second: pixels[1] });
            if (matte.empty) reply.empty = true;
            else {
                context.putImageData(new ImageData(matte.data, size, size), 0, 0);
                const canvas = document.createElement('canvas');
                canvas.width = canvas.height = 256;
                const output = canvas.getContext('2d');
                const bounds = matte.bounds;
                const scale = 216 / Math.max(bounds.width, bounds.height);
                const width = bounds.width * scale, height = bounds.height * scale;
                output.drawImage(work, bounds.x, bounds.y, bounds.width, bounds.height, (256 - width) / 2, (256 - height) / 2, width, height);
                reply.image = canvas.toDataURL('image/webp', 0.92);
            }
        } catch (error) {
            const context = typeof data.context === 'string' ? ` [${data.context.slice(0, 85)}]` : '';
            reply.error = String(error.message || 'Thumbnail processing failed.').slice(0, 150) + context;
        }
        try {
            await fetch(`https://${GetParentResourceName()}/cortex-admin:catalog:processed`, {
                method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(reply),
                signal: AbortSignal.timeout(10000),
            });
        } catch { /* The client watchdog ends the job if CEF cannot respond. */ }
    });
})();
