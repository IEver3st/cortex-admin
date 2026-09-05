# Persistent wardrobe previews

The generator scans the actual male and female freemode drawables loaded on an authorized admin client, including streamed collections. It captures texture 0 for components 1 through 11 and props 0, 1, 2, 6 and 7. Face morphology, overlays, tattoos, non-freemode ped wardrobes and every individual texture/color variant are outside this catalog.

Existing curated cutout images remain preferred. Uncatalogued clothing now uses isolated garment captures with transparent backgrounds: clear non-target drawable slots, hide the head with per-frame reset flag 166, measure two empty-stage PNG frames with the local capture ped invisible, then render the isolated garment against those same two backings. Foreground alpha is recovered against the measured background at each pixel, accounting for uneven shading instead of assuming the four corners have one flat color. Only the visible garment is fitted into a 256px tile with consistent margins. Green, magenta, black and white clothing are not removed by a hue filter. Clothing meshes that themselves include skin remain faithful to those meshes; the reference library also documents manual editing on some images. No AI-generated garment details or inferred names are used. Generated photos appear under **Clothing > All available**, plus the hair and accessories grids.

## First run

1. In the server console: `refresh`, `ensure screenshot-basic`, then `restart cortex-admin` after deploying these files. Confirm `[wardrobe-catalog] Server ready (cutout-4)` in the server console and `Client ready (cutout-4)` in F8. screenshot-basic is already present in this server's `[extras]` folder; it remains an optional dependency for normal menu use.
2. Join with permission for `dev.takePhoto` (the existing Cortex dev/admin permission path), stand on foot somewhere safe, and close other cameras/freecam.
3. Run `/cortex_catalog sample`. This captures eight previews: top, trousers, shoes and hat for each body. Check framing, lighting, streamed texture readiness and interference from other resources' HUDs before the long run.
4. Run `/cortex_catalog build` to generate missing previews. Leave that client connected until completion. F8 logs progress every 100 drawables.
5. Reopen Character studio and choose **All available**. Normal browsing does not capture anything.

**Console syntax:** the commands below use in-game chat syntax. In F8, omit the leading slash: `cortex_catalog sample`. F8 immediately prints `Requesting sample from server...`, followed by server status or a five-second acknowledgement timeout. Status/errors and accepted starts also print in the server console. Generation requires a player client; the server console supports status/cancel and explains where to run capture commands.

| Command | Behavior |
| --- | --- |
| `/cortex_catalog build` | First build or resume. Skip valid persisted images. |
| `/cortex_catalog update` | Scan again and capture new identities only. |
| `/cortex_catalog rebuild` | Recapture existing identities as well, for replaced assets or framing changes. |
| `/cortex_catalog sample` | Recapture eight framing samples; does not mark a full build complete. |
| `/cortex_catalog status` | Current saved/cached counts, or last completed job. Also works in server console. |
| `/cortex_catalog cancel` | Stop the current job while keeping saved previews. Also works in server console. |

Backspace also cancels capture. One job is allowed server-wide. Commands do not automatically run on startup or player join: a renderer must be available, and taking over a player's view for the initial job requires deliberate use of the build command.

## Persistence and cost

Server resource KVP stores each 256 by 256 WebP independently, keyed by schema version, body, component/prop slot, collection name and local drawable. Global IDs are resolved on the current ped during lookup. Restarting Cortex or FXServer retains completed images; reinstalling without the server KVP database does not. Back up FXServer's KVP storage with your normal server data backup.

**Migration:** transparent captures use cache version 2 and a separate completion record. Old version-1 mannequin thumbnails remain untouched in storage but are never served or treated as complete. Run `sample`, then `build` to populate the new cache. Invisible/empty clothing slots have an explicit empty marker so repeated builds can skip them without saving a fake photograph.

Before each body's first new capture, the system validates body isolation with the same four-frame process. Visible body parts fail this check before any thumbnail is saved. Each subsequent item also measures its empty stage at its exact camera position. The processor rejects non-responsive backdrops over more than 2% of the frame, or missing background measurements inside the garment bounds, as well as movement/lighting instability and clipping. Small unchanged overlays outside the garment can be excluded using the measured stage. Errors report backdrop coverage where applicable, the capture phase, and camera/stage heights. These measurements distinguish missing stage coverage from uneven shading; they do not assume a HUD caused every failure. Whole-screen screenshots never go to the server.

Full screenshots stay on the capture client. Only compressed thumbnails up to 64 KiB use bounded latent transfers. Pages mount at most 24 thumbnail requests; there is no whole-catalog image download and no generation loop while idle. Generation waits for clothing preload completion plus `Config.WardrobeCapture.settleMs` (750 ms by default; accepted range 250 to 5000). Total time and disk usage depend on actual item count, client GPU, streaming and network performance; no runtime timing has been measured.

The capture ped is local and non-networked. The player's model, outfit, coordinates, weather and routing bucket are not rewritten. The player's body remains frozen in the world and remains subject to other resources, damage and needs systems. A dedicated maintenance client in a safe location is recommended. Camera takeover, death/model change, reopening the menu, Backspace, screenshot dependency loss, disconnect and timeouts stop the job. Resource stop deletes the mannequin and camera and restores the previous player freeze state. Other resources' NUI overlays may still appear in screenshots; disable those for the capture session if the sample shows them.

Update skips unchanged collection identities, so replacing a YDD/YTD in place requires `rebuild`. Removed clothing stays cached but is not listed because browsing uses the live drawable counts. There is no destructive cache pruning. Capture is capped at 50,000 items per job; the existing component editor's 4,096 drawable limit remains in place.

## Verification handoff

Validation commands: `bun run test`, `bun run build`, JavaScript syntax checks and `git diff --check`. Cutout tests cover transparency, garment/background color collisions, black and white fabric, antialiased edges, empty drawables, rejected captures, cache version isolation, and final framing. These are deterministic fixture/source checks, not proof of GTA lighting or CEF output. Earlier whole-checkout skill audits reported unrelated styling/development-folder issues; those paths are maintained separately. No in-game or CEF automation was performed.

At the cutout-3 handoff, all 19 Lua specs passed, as did focused thumbnail tests and syntax checks. The wider test/build commands encountered separate console navigation and ActionItem layout-contract failures in the concurrently changing checkout. The NUI audit reported zero errors and one existing modal pointer-capture warning; resource packaging audit still reports development dependencies and the invalid `.opencode` lockfile. Those failures are not in the capture pipeline and were not silently removed to make a check pass.

At the cutout-4 handoff, the full `bun run test` suite and `bun run build` pass. The new regression reproduces the previous corner-color rejection on an unobstructed but unevenly shaded backdrop, then verifies per-pixel background measurements recover the garment correctly. Coverage tests still reject missing stage regions and holes inside the garment. In-game output remains a user-run verification step.

Browser photo requests run four at a time, with at most 96 queued requests and a 128-image cache. Leaving a page cancels its queued reads. Completion or cancellation after saving images invalidates browser caches; reopen the studio to refresh displayed images.

Static checks do not prove GTA rendering. On this server, verify the eight sample photos at your normal resolution and ultrawide if used, both bodies, a streamed top, a hat and an undershirt. Confirm selection still applies the matching drawable and texture zero. Then:

- Cancel midway, repeat `build`, and confirm saved items are skipped.
- Restart Cortex during capture, then restart FXServer after a saved batch; confirm cleanup and persistence.
- Revoke capture permission or disconnect the capture client; confirm another authorized admin can start after cancellation/timeout.
- Try the command as an unauthorized player; no capture or writes should occur.
- Keep a second player connected: no network mannequin, model changes or camera takeover should appear on that player. Late joining players should read the persisted photos.
- Measure idle and active resmon/client GPU cost and page delivery time. Generated framing, CEF output, performance and multiplayer behavior remain untested until these user-run checks complete.

API references checked: [Cfx collection-based natives](https://docs.fivem.net/docs/scripting-manual/using-new-game-features/collection-based-natives/), [screenshot-basic API](https://github.com/citizenfx/screenshot-basic/blob/master/README.md), [Cfx discussion of hiding the head on current artifacts](https://github.com/citizenfx/fivem/discussions/3447), [the reference image library's capture provenance](https://github.com/Colbss/FiveM-ClothingData), and the installed FiveM native declarations and screenshot-basic client source. The capture predecessor's non-head empty-drawable behavior was checked in [fivem-greenscreener](https://github.com/Bentix-cs/fivem-greenscreener); this implementation keeps the existing Cortex lifecycle/authority and implements its own dual-background matte instead of importing that resource.
