# Character studio

Open **Appearance > Open character studio**. The studio uses the current player
ped, a front-facing camera, floating section navigation and translucent controls.
The wardrobe opens on demand; clothing shows a contextual garment-detail panel.
Condensed section titles and ivory selections replace the solid admin panels.
Studio styles live in `ui/character-studio.css`. It has no
currency or checkout. **Done / Escape** returns to the admin menu. Changes apply
live; use Save outfit for persistence. Generator Undo restores the previous roll.

## Clothing and generation

- Nine directions: Polished, Casual, Street, Sport, Utility, Biker, Resort,
  Nightlife and Designer. Each body has 22 modern families plus five legacy
  fallback families. Compatible modern families take priority, so newer pieces
  are used in actual rolls instead of being buried in the manual catalog.
- The expansion adds 42 drawables per body: 22 tops, 12 bottoms and eight shoes,
  with multiple named textures per palette. It reaches Casino, Tuners, Contract,
  Criminal Enterprises, Drug Wars and 2023 collections without changing the
  server game build. Tops own their researched torso and bare undershirt together.
  Low shoes stay with shorts; road/logger boots have dedicated trouser families.
  Open suit jackets and tall boots remain manual choices.
- Color stays on one focal piece. Most families color the top; the sneaker
  rotation family in Street, Sport and Designer can color the shoes with Mixed.
  Supporting pieces stay restrained. Tonal and Mixed now allow the broader DLC
  colors on female clothing too; there is no blanket female color exclusion.
- The authored pools contain 14,331 distinct male and 15,659 distinct female
  combinations across styles/palettes, before runtime filtering. These counts
  exclude accessories and character features, and do not imply rendered fit QA.
- Catalog picks have researched names/IDs; 110 local WebP reference photographs
  total about 2 MB. Photos show texture zero, not the player's current texture.
- All available lists the live drawable range for the selected component,
  including addon items. Uncatalogued items use numbered tiles, not invented
  names or photographs. Manual tops may need arms and undershirt adjustments.
- The client reports `GetGameBuildNumber()`. Current server.cfg specifies 3095.
  Native drawable/texture limits and collection name/local index are checked
  before curated entries enter the generator or catalog. This prevents a custom
  item occupying a missing DLC global index from passing as the intended item.
- The index source was captured on build 3407; this is not a requirement to
  upgrade. Entries must match the running game's collections. With unavailable
  collection natives, only base-game generator pieces remain eligible. Directions
  with no complete available family report unavailable instead of applying a
  partial outfit. The index builder now includes every source drawable, including
  newer torso meshes, rather than silently stopping at drawable 130.

Expansion provenance: names/textures are from
[v-clothingnames at 84020cf](https://github.com/root-cause/v-clothingnames/tree/84020cfa80b1a2fdc86f0e8eb438d313f343c015),
torso pairings from
[v-besttorso at a2eba9f](https://github.com/root-cause/v-besttorso/tree/a2eba9f862baf7c6da34a4b5d1bd36a4abbf8e03),
and collection/local IDs from
[FiveM-ClothingData at 6178655](https://github.com/Colbss/FiveM-ClothingData/tree/6178655616ea88e3e2bf191b32bc4878b9c3b5eb).
All 84 new drawables, selected textures and top/torso pairs were cross-checked
against those datasets. The photo library has no reference photographs for these
additions; existing captures or numbered tiles remain the truthful fallback.
The generator does not depend on thumbnails. Garment clipping remains unverified
until the runtime handoff below.

## Sources

Researched 2026-09-04:

- [RAGE Multiplayer numbered clothing catalog](https://wiki.rage.mp/wiki/Clothes)
  with male/female category galleries. This is a reference, not an exhaustive
  list of the server's custom clothing or a build compatibility authority.
- [Colbss/FiveM-ClothingData](https://github.com/Colbss/FiveM-ClothingData), pinned
  to `6178655616ea88e3e2bf191b32bc4878b9c3b5eb`: collection identity and photos.
  Its README permits image use and notes that labels are incomplete. Existing
  curated labels are retained instead of importing unverified labels wholesale.
- [Cfx collection indexing](https://docs.fivem.net/docs/scripting-manual/using-new-game-features/collection-based-natives/).
- Existing catalog names/torso provenance remains in
  `shared/appearance_catalog.lua`. Per-image URLs are in `ui/wardrobe/sources.json`.

Rebuild catalog assets with `python tools/fetch-wardrobe-thumbnails.py`.
This is an authoring tool; the running resource does not contact these websites.

## Validation and runtime handoff

The camera is configured before activation and frames head/foot skeletal bounds
instead of fixed offsets from the ped origin. Bounds and heading are captured
once per ped; the shot stays anchored through idle animation and small root
movement. Lifecycle polling does not rewrite camera transforms. Explicit orbit,
zoom and section controls update the shot, model replacement captures new bounds,
and an external relocation over two metres moves the anchor with the ped.
On acquisition it establishes
streaming focus on the ped, temporarily raises entity LOD distance to at least
512, and requests one AI/animation refresh. Original detail distance and freeze
state are restored on close or ped replacement, unless another resource has
subsequently changed the detail value. Cleanup respects camera/focus takeover.
These changes address likely streaming/framing causes of the reported detail
degradation; native stubs cannot prove the in-game LOD symptom is resolved.

Native behavior references: [streaming focus](https://github.com/citizenfx/natives/blob/master/STREAMING/SetFocusEntity.md),
[entity LOD distance](https://github.com/citizenfx/natives/blob/master/ENTITY/SetEntityLodDist.md),
[bone coordinates](https://github.com/citizenfx/natives/blob/master/PED/GetPedBoneCoords.md),
[one-time animation refresh](https://github.com/citizenfx/natives/blob/master/PED/ForcePedAiAndAnimationUpdate.md).

Deterministic checks: `bun run test`, `bun run build`, `bun run audit:actions`,
JavaScript compilation, Lua syntax and manifest/asset checks. Tests execute the
camera module and NUI validation with native stubs, not a FiveM instance. They
cover skeletal framing, configure-before-activation, temporary detail/focus state,
rapid reopen, prior freeze state, ped replacement, vehicle rejection, resource stop,
camera takeover, permission rejection, malformed requests, callback completion,
collection mismatches and texture boundaries.

No FiveM, GTA or NUI runtime was driven or visually verified. To accept the change:

### World LOD regression diagnostic (2026-09-04)

Follow-up trace: the player moved less than 0.3 m, but the reported final camera
was `(128000, 128000, 21600)` with rendering handle `-1` and no studio camera.
Only the before-open sample survived, indicating teardown before the settled
samples. A regression now reproduces the lifecycle defect: camera activation
can have no published rendering handle, the old watcher closed the studio, and
cleanup destroyed its camera without disabling the script-render request.

The controller now treats only a concrete different camera handle as takeover,
waits one render tick before watching, and tracks its render request separately
from camera existence. Close releases that request when no foreign camera owns
rendering, including a pending/lost handle, then deactivates and destroys its
camera. Tests cover delayed handles, early close, lost cameras and real takeover.
Diagnostic revision `studio-lod-diag-2` includes active/request state and a closing
sample. This fixes the reproduced lifecycle bug; confirmation of the live visual
result still requires reopening the studio after the resource restart.

The user's retest still shows low-detail peds and nearby vehicles. The earlier
focus/LOD adjustments are **not a verified fix**. No teleport is called by the
studio-open or catalog paths. A native-stub reproduction does confirm that
out-of-range bone coordinates previously produced a remote camera; these now
fall back to bounded ped-relative framing. Whether this occurred in-game remains
unknown. Existing client logs lack the camera/focus readbacks needed to decide.

After restarting this resource, enter the studio, wait three seconds, and run
`cortex_studio_debug camera` in F8. Close F8 and observe whether world detail
recovers. After three seconds run `cortex_studio_debug` and provide the
`[cortex-studio-debug]` lines (also present in the normal CitizenFX log).
The first command prints the baseline before changing **only** streaming focus
to the existing camera's position. `cortex_studio_debug player` reverses that
probe; closing the studio restores normal focus. The probe checks the active
camera and existing appearance permission. No teleport, model change or new
network message is involved.

Samples distinguish player displacement, invalid skeletal bounds, incorrect
camera writes, a different final rendered camera, and queued streaming work.
`playerIsFocus=false` is expected in coordinate-focus mode; it is not itself an
error. There is no exposed focus-position getter in this diagnostic, so another
resource's exact streaming target cannot be inferred from that flag. Three
bounded samples are retained in memory per opening; logging happens only on the
diagnostic command. Remove this temporary diagnostic after the cause is verified.

### Runtime acceptance

1. Restart `cortex-admin`, stand on foot in an open area, then open the studio.
   Compare ped face/clothing detail immediately before and after entry, in Body
   and Face views. Check camera framing, rotation and zoom. An existing scripted camera should
   prevent opening. No ped is teleported, spawned or placed in another bucket.
2. On build 3095, generate male/female looks in all nine styles and palettes.
   Check sleeves, torso gaps, waist/shoe clipping and combinations in motion.
   Verify outfit-only leaves face/hair unchanged, full-character changes the
   selected identity, and Undo restores the preceding appearance.
   In particular check revere-collar sleeves, cardigan/chore jacket undershirts,
   large-cargo hems, road/logger boot seams, pool sliders with shorts and the
   Mixed sneaker family. Confirm names include the newer collections' garments.
3. Select tops, pants and shoes from photographed picks, then switch to All
   available. Change drawables with different texture counts. Confirm the texture
   limit updates, search/page navigation works, and prop -1 removes the prop.
4. Exercise heritage, body model, 20 face controls, hair, eye color, overlays and
   clear tattoos. Save/load/rename/share/import using existing wardrobe actions.
5. Check 1920x1080, 2560x1440, 3440x1440 and a narrow viewport at scales 1.0/1.6.
   The center must stay transparent. Tabs, Done and camera controls must remain
   reachable, with independent panel scrolling and keyboard focus visible. Check
   control readability against bright sand/sky and dark interiors; open/close
   Wardrobe and confirm it does not occupy the right side until requested.
6. Close/reopen rapidly; press Escape inside inputs/selects and outside them;
   open a save-management confirmation. Restart the resource while editing,
   replace the ped, die or revoke permissions. Camera/freeze/focus must clean up.
7. With another client, verify clothing changes and wardrobe sharing still
   replicate through the existing game/server paths. No new network protocol was
   introduced. No resmon/performance or live visual claims have been made.

Whole-checkout audits also flag pre-existing gradients in unrelated/shared UI,
development node_modules folders, mixed lockfiles and `.opencode` JSON. These
were not removed or rewritten as part of the studio change. The studio's authored
surfaces are flat; its shared confirmation card is overridden to a solid fill.
