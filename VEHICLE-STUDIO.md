# Vehicle studio

Visual contract: a stationary, cursor-operated vehicle editor using the character
studio's approved floating navigation, translucent rows, ivory selections and
condensed display type. The vehicle dominates the transparent center. A left
inspector shows one customization category; a small right lighting deck provides
time presets, a clock slider and a cycling toggle. Rotation, orbit and zoom stay
at the bottom. Live edits remain on the vehicle; garage saving is optional.
Exiting deletes only an explicitly spawned private preview.
No currency, full-width panel backing, gradients, blur or dashboard cards.

Reuse existing React controls, icons, scale tokens and vehicle data. Critical
states: invalid/unavailable model, permission denial, loading/cancel, stale
session, empty mod lists, save-name conflict, lost camera/entity and reduced
motion. Target 1080p, 1440p, ultrawide and narrow layouts at scales 1.0 and 1.6.
Visual acceptance and two-client isolation require user-run in-game checks.

## Body and performance controls

The modification workbench replaces discrete sliders in both the studio and live
customizer. Performance uses compact tuning rows with Stock and direct numbered
upgrade keys. Suspension falls back to Setup names and armor to Level names;
native labels take precedence. Turbo uses the studio's diagonal-cap switch.
Bodywork groups the available exterior, cabin, engine-bay and other parts into
an index. Only one part expands into a single scrollable list, including Stock,
without pagination. The list height stays bounded and opens at the installed
variant. Load GTA's `mod_mnu` text bank before resolving native part labels;
unnamed addon parts retain numbered fallbacks. Streaming waits are bounded and
revalidate the target vehicle/session before reading its customization state.

Selections wait for the existing customization callback before changing their
confirmed state. Repeated clicks are locked while pending, and failures remain
visible. This changes no native indices, permissions, studio targets or saves.

Parts-list revision checks: build/layout contract, action parity, 18 Lua specs
and seven workbench tests pass. Source audits report no findings in the workbench
JS/CSS. Tests cover native Stock (-1), turbo false, pending/retry, unavailable
groups, escaped labels, all 4096 options without pagination, text-bank loading,
timeout and stale targets. Static markup is not visual or in-game evidence;
no runtime was automated.

The runtime-file copy passes resource validation with the existing `lua54`
warning. The development checkout itself is flagged for its existing
`node_modules` folders and `.opencode/package-lock.json`; those were preserved.

Runtime handoff: restart `cortex-admin`, open **Body & performance**, select and
restore Stock on an engine upgrade, then toggle Turbo both ways. In Bodywork,
expand a spoiler, select a named variant and switch groups. Check a stock car
and an addon with many variants, keyboard focus, rejection feedback, bright/night
readability, scrolling at 1080p/1440p and scales 1.0/1.6, and Escape/reopen.

## Entry and behavior

Open **Customizer > Open vehicle studio** to edit the vehicle you are currently
driving, or the last vehicle you occupied within 15 metres when on foot. Changes
apply directly to that entity. A different driver blocks editing. Network control
must be acquired within 1.5 seconds; loss of control ends the session.
The vehicle is temporarily frozen; its prior freeze state is restored on close.
Its position, heading, collision, locks, engine and damage are left intact.
Camera orbit/zoom works around the real vehicle; vehicle rotation is preview-only.
Use **Preview another model** explicitly to spawn a disposable private vehicle,
while standing on foot in a level outdoor area.
Vehicles over 22 metres are rejected to keep the preview near the player.
The existing driven-vehicle customizer remains available below the launcher.

Only model-preview mode uses `CreateVehicle(..., false, false)` and is locked, invincible,
frozen and collisionless. It is never promoted to a networked entity. There is
no player teleport, routing-bucket change or server time/weather event.
Customization reuses the existing typed callback validation and native setters,
with a required matching studio session for studio targets. Old sessions fail
without falling back to the player's real vehicle. Per-category ACEs still apply;
opening additionally requires `vehicle.spawn` and saving `vehicle.savePersonal`.

Paint, mods, wheels/windows, extras, native liveries and lighting use the existing
model-specific availability data. Save creates a new canonical personal-garage
record; duplicate names are rejected. Spawn saved builds later through the garage.
Done/Escape releases the live vehicle or deletes the preview and restores the camera, local clock and prior
ped freeze state. Menu close, resource stop, permission loss, model replacement
and camera takeover also clean up. Loading is bounded to eight seconds and can
be cancelled without creating a late vehicle.

Dawn/day/sunset/night and a minute slider affect only the local clock. A complete
day/night cycle takes two minutes; stopping holds the displayed time. The admin's
world-time handler retains incoming world state while the studio owns the local
override, then restores frozen world time on exit if applicable. Weather is
unchanged. Other resources that independently force clock time may still require
a coordinated pause/resume adapter; that integration has not been live-tested.

Native sources checked 2026-09-04:
[local vehicle creation](https://github.com/citizenfx/natives/blob/master/VEHICLE/CreateVehicle.md),
[local clock override](https://github.com/citizenfx/natives/blob/master/NETWORK/NetworkOverrideClockTime.md),
[clearing the override](https://github.com/citizenfx/natives/blob/master/NETWORK/NetworkClearClockTimeOverride.md).

## Verification

Passed for the live-target repair: 16 Lua specs, two catalog tests, UI build/layout
contract, action parity and JavaScript syntax. The resource-wide audits still
flag existing dependency folders, `.opencode/package-lock.json`, and gradients
in `ui/style.css`; they do not pass for this development checkout.
Native-stub tests exercise direct current/last-vehicle paint writes, source preservation,
clock bounds/wrapping, rendering-handle races, cancellation, session rejection,
permission revocation, false-valued toggles, garage naming and restart cleanup.
These are not in-game or visual proof. No FiveM/GTA/NUI runtime was automated.

User acceptance:

1. Restart the resource, open a stock and an addon car, and inspect all categories.
   Change paint, a wheel mod, an extra and livery; save, close and load from garage.
2. Rotate the vehicle, orbit/zoom the camera and switch low/high views. Check
   framing and ground placement; the camera must stay steady while idle.
3. Cycle light presets and a full day/night pass. Close and confirm normal time
   returns, including when the admin's world clock was frozen beforehand.
4. From a second client nearby, confirm no preview vehicle or time changes appear.
   In live mode, confirm edits appear on the original vehicle for the observer
   and a client entering scope later. Transfer ownership and confirm the studio
   closes safely, with no stuck freeze or further edits from the old session.
5. Cancel loading, close/reopen rapidly, close the admin menu, revoke permissions,
   replace the ped and restart the resource. No vehicle, camera or clock override
   should remain. Confirm another camera owner is preserved.
6. Inspect bright/dark readability and independent inspector scrolling at 1080p,
   1440p, ultrawide and UI scales 1.0/1.6. No solid fullscreen backing or clipping.
7. Open while driving a stationary car, change paint, and close. Repeat after
   stepping out nearby. Both paths must edit the same car, spawn nothing, and
   retain changes after Done/Escape. Repeat with resource restart while open.
   Missing, distant and occupied-by-another-driver vehicles must fail clearly.


## Shared switches, paint samples and wheel photographs

The menu, voice, clothing and vehicle controls share the angled On/Off state tab.
Vehicle paint uses a searchable, paged palette of 161 GTA base RGB colors. Xenon
colors have swatches, and neon/smoke have RGB color pickers. Reflective finishes
and chameleon paint still need the live vehicle and the lighting controls.

Wheel selection uses nine photographic references per page. The 491 local WebP
images cover 13 stock wheel categories and total about 3.4 MB. Matching requires
both wheel type and exact normalized English native name; images are never
assigned by guessed array position. Stock, add-on and untranslated/unmatched
names keep a selectable live-preview option. The runtime's native count/name
list controls availability for the active vehicle and build. Changing wheel type
refreshes both wheel slots before selection is unlocked.

Provenance: [GTA Wiki wheel gallery](https://gta.fandom.com/wiki/Vehicle_Customization_in_GTA_V/Wheels)
and [DurtyFree's extracted vehicle colors](https://github.com/DurtyFree/gta-v-data-dumps/blob/master/vehicleColors.json).
`ui/vehicle-catalog/sources.json` retains URLs and hashes. All reference images
are bundled; NUI makes no external image requests. Rebuild with
`python tools/fetch-vehicle-catalog.py` (BeautifulSoup and Pillow tooling required).

Range changes now publish immediate local drafts and coalesce consecutive unsent
updates to the same control, preserving category/mod ordering. Failed writes
reconcile with native state. The lighting clock no longer rerenders the customizer;
portal wheel events do not enter the hidden admin menu's scroll routing. Scroll
containers use native scrolling, stable gutters and bounded image pages.

Static checks cover slow requests, cancellation, request ordering, immutable
drafts, native-name image matching, thumbnail hashes, bounded markup, accessible
switch state and asset loading order. In-game smoothness and visual layout remain
user acceptance checks: drag RGB/time quickly, switch Sport/Track and choose a
pictured wheel, toggle lights/voice/options with keyboard, and check On/Off,
scrolling and color readability over both daylight and night scenes.


### Plates and tint examples

Wheels has three local views: Wheels, Plates and Window tint. Plate choices use
13 cropped original texture references with the vehicle's current registration
text, retain native indices, and hide indices 6-12 below build 3095. The native
setter also rejects those newer styles on older builds. Corrected labels:
1 = Yellow on Black, 2 = Yellow on Blue, 3 = Blue on White 2,
4 = Blue on White 3, 10 = LS Panic.

The mapping/build requirement comes from the
[Cfx plate native reference](https://github.com/citizenfx/natives/blob/master/VEHICLE/GetVehicleNumberPlateTextIndex.md).
The inspected [original texture sheet](https://www.lcpdfr.com/forums/topic/155615-gta-online-license-plates/)
is credited and hashed in sources.json with the exact crop map. Custom streamed
plate replacements may differ from these stock examples.

Tint cards are explicitly labeled illustrations, not vehicle photographs or
measured light-transmission percentages. IDs follow the
[Cfx tint enum](https://github.com/citizenfx/natives/blob/master/VEHICLE/SetVehicleWindowTint.md).
IDs 0-4 use the extracted carcols ARGB values, preserving leading alpha zeroes;
Limo and Green use illustrative colors because the dump supplies no corresponding
material values. Actual factory glass, custom vehicle materials and scene
lighting determine the in-game result. Check these on the selected vehicle.

Latest validation: UI build/layout, 18 Lua specs, 18 vehicle JavaScript tests,
action parity, JavaScript syntax and CSS compilation passed. The full test
command currently stops at two console_navigation.test.mjs failures involving
console-index-toggle / Expand navigation; those concern the separate navigation
redesign, not the studio controls. A separate wardrobe_capture.test.mjs crop
fixture also fails after the wardrobe matte changes. The 18 vehicle tests pass. The new controls pass the
scoped NUI/frontend source audits. These checks do not establish rendered NUI
appearance or in-game scroll performance.
