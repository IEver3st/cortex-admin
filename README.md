# cortex-admin

![FiveM](https://img.shields.io/badge/FiveM-Resource-orange)
![QBX](https://img.shields.io/badge/QBX-Compatible-blue)
![Lua](https://img.shields.io/badge/Lua-5.4-blue)
![License](https://img.shields.io/badge/License-MIT-green)

**Admin/dev menu with QBX framework support.**

`cortex-admin` is a FiveM server-side admin and developer menu built with a React NUI frontend. It provides player, vehicle, world, weapons, teleport, appearance, inventory, garage, dev, recording and server management tools, with optional automatic integration for `qbx_core`, `ox_inventory`, and `qbx_vehicles`.

## Features

The menu is organized into tabs. The full declarative action catalog lives in `shared/actions.lua` and currently ships **130 actions**.

- **Player** – god mode, invisibility, noclip, super jump, fast run/swim, infinite stamina, no ragdoll, heal, armor, revive, wanted level, freeze, clean/dry/wet player, ped model swap, save/load MP peds.
- **Vehicle** – spawn, preview, save personal vehicles, repair, clean, delete, flip, engine toggle, vehicle godmode, speed limiter, torque/power multipliers, plate text, bike seatbelt, max performance mods.
- **World** – set weather (with zone editor), set time, freeze time, blackout, dynamic weather, disable NPCs/traffic, clear area/vehicles/peds/objects.
- **Weapons** – give weapon, give all, remove all, save/load/delete loadouts, infinite ammo, set ammo, attachments, tints, parachute.
- **Teleport** – waypoint, marker, coordinates, back, save/load/delete custom locations.
- **Appearance** – randomize MP face, clear ped tattoos, set default outfit.
- **Vehicle Customizer** – dedicated UI tab for tuning/styling the current vehicle.
- **Inventory** *(QBX + ox_inventory)* – give items to players from the full item list.
- **Garage** *(QBX + qbx_vehicles)* – spawn personal vehicles from the QBX garage.
- **Dev** – coordinate/speed HUD, hide HUD, night/thermal vision, player blips, freecam, reset UI.
- **Recording** – take photo, gallery, start/stop/discard Rockstar Editor recordings.
- **Server** – resource manager (start/stop/restart/ensure/refresh), pull stash.
- **Options** – accent color, UI scale/opacity, menu position, double-click to run, show target info, auto-load saved ped, restore ped on death, default to MP ped, replace spawned vehicle, disable aircraft turbulence, quit session before editor.
- **Favorites / All** – bookmark and browse every action.

<details>
<summary>Full action catalog</summary>

### appearance
- Set Default Outfit
- Randomize MP Face
- Clear Ped Tattoos

### dev
- Coordinate HUD
- Speed HUD
- Speed HUD Units
- Speed HUD Position
- Hide HUD
- Night Vision
- Thermal Vision
- Show Player Blips
- Set My Stress *(QBX only)*
- Reset & Reload UI

### garage
- My Garage *(QBX only)*

### inventory
- Give Item *(QBX only)*

### options
- Accent Color
- UI Scale
- Menu Opacity
- Menu Position
- Double-Click to Run
- Show Target Info
- Auto-Load Saved Ped
- Replace Previous Spawned Vehicle
- Disable Aircraft Turbulence
- Restore Ped on Death
- Default to MP Ped

### player
- God Mode
- Invisibility
- Noclip
- Super Jump
- Infinite Stamina
- No Ragdoll
- Fast Run
- Fast Swim
- Heal
- Max Armor
- Revive
- Clear Wanted
- Never Wanted
- Set Wanted Level
- Freeze Player
- Everyone Ignores
- Clean Player
- Dry Player
- Wet Player
- Set Ped Model
- Save MP Ped
- Load MP Ped
- Save Ped
- Load Ped
- Copy Coords
- Copy Heading
- Kill Player *(QBX only)*
- Revive Player *(QBX only)*
- Sit In Vehicle *(QBX only)*
- Set Job *(QBX only)*
- Set Gang *(QBX only)*
- Set Cash *(QBX only)*
- Set Bank *(QBX only)*
- Give Money *(QBX only)*
- Set Hunger *(QBX only)*
- Set Thirst *(QBX only)*
- Set Stress *(QBX only)*
- Open Inventory *(QBX only)*
- Set Routing Bucket *(QBX only)*

### recording
- Take Photo
- Open Gallery
- Start Recording
- Stop Recording
- Discard Recording
- Rockstar Editor
- Freecam
- Quit Session Before Editor

### server
- Resource Manager
- Pull Stash *(QBX only)*
- Refresh Resources

### teleport
- Teleport to Waypoint
- Teleport to Marker
- Teleport to Coords
- Teleport Back
- Save Location
- Load Saved Location
- Delete Saved Location

### vehicle
- Spawn Vehicle
- Vehicle Preview
- Personal Vehicles
- Save Current Vehicle
- Repair Vehicle
- Clean Vehicle
- Delete Vehicle
- Destroy Engine
- Flip Vehicle
- Engine Toggle
- Vehicle Godmode
- Keep Vehicle Clean
- Speed Limiter
- Clear Speed Limit
- Torque Multiplier
- Power Multiplier
- Change Plate Text
- Bike Seatbelt
- Max Performance Mods
- Admin Car *(QBX only)*
- Give Current Vehicle Keys *(QBX only)*

### weapons
- Give Weapon
- Give Weapon (Custom)
- Give All Weapons
- Remove All Weapons
- Save Weapon Loadout
- Load Weapon Loadout
- Delete Weapon Loadout
- Infinite Ammo
- Set Ammo
- Weapon attachments
- Weapon tint
- Parachute

### world
- Set Weather
- Weather Zone Editor
- Reload Weather Zones
- Force Zone Weather
- Force Current Zone Weather
- Set Time
- Freeze Time
- Blackout
- Dynamic Weather
- Disable NPCs & Traffic
- Clear Area
- Delete Vehicles
- Delete Peds
- Delete Objects
</details>

## Installation

1. Make sure `es_lib` is installed and started before `cortex-admin`.
2. Place this resource in your server resources directory, for example `resources/[eco]/cortex-admin`.
3. Add the permission file to `server.cfg` **before** `ensure cortex-admin`:
   ```
   exec resources/[eco]/cortex-admin/permissions.cfg
   ensure cortex-admin
   ```
4. Restart the server.

The default command to open the menu is `/esadmin` and the default keybind is `F10`. Both can be changed in `shared/config.lua`.

## Configuration

All client-side and shared configuration lives in `shared/config.lua`:

| Setting | Description |
|---------|-------------|
| `Config.Command` | Chat command to open the menu (`esadmin`). |
| `Config.Keybind` | Default keybind (`F10`). |
| `Config.DefaultSettings` | UI scale, opacity, accent color, menu position, ped behavior, etc. |
| `Config.Permissions` | Tab-level ACE permission strings. |
| `Config.ActionPermissions` | Fine-grained ACE permissions for individual actions. |
| `Config.QBXPermissions` | Automatic permission mapping for QBX `god`/`admin`/`mod` ACE groups. |
| `Config.WeaponList` | Weapons available in the Give Weapon action. |
| `Config.BanIdentifierTypes` | Identifier types persisted when banning a player. |

Server behavior, framework bridging and action handlers are implemented in `server/main.lua`, `server/bridge.lua`, `server/actions.lua`, and `server/vmenu_fallback.lua`.

## Permissions

Access is controlled entirely by FiveM ACE permissions:

- `cortex-admin.all` – full menu access.
- `cortex-admin.<tab>` – access to a whole tab (`player`, `vehicle`, `world`, etc.).
- `cortex-admin.<tab>.<action>` – access to a specific action when fine-grained ACEs are used (see `Config.ActionPermissions`).

When `qbx_core` is running, the QBX groups `god`, `admin`, and `mod` are automatically mapped to the equivalent `cortex-admin` permissions via `Config.QBXPermissions`. You still need `command.esadmin` (or `command`) in ACE so players can open the menu.

The bundled `permissions.cfg` grants `cortex-admin.all` and `command.esadmin` to `group.admin`:

```cfg
add_ace group.admin "cortex-admin.all" allow
add_ace group.admin "command.esadmin" allow
```

Do **not** uncomment the `builtin.everyone` lines on a production server.

## Commands

The resource registers a large set of convenience chat commands. All commands respect the same ACE permission checks used by the menu.

<details>
<summary>Registered commands</summary>

| Command | Description |
|---------|-------------|
| `/esadmin` | Open the admin menu. |
| `/tp X Y [Z]` | Teleport to coordinates (supports `X=..., Y=...` style). |
| `/tpm` | Teleport to the map waypoint. |
| `/tpmarker` | Teleport to the current marker. |
| `/tpback` | Teleport to the previous location. |
| `/parachute` | Give a parachute. |
| `/noclip` | Toggle noclip. |
| `/god` | Toggle god mode. |
| `/vanish` | Toggle invisibility. |
| `/heal` | Heal the player. |
| `/armor` | Give max armor. |
| `/revive` | Revive the player. |
| `/coords` | Print current coordinates. |
| `/copycoords` | Copy current coordinates to clipboard. |
| `/heading` | Print current heading. |
| `/copyheading` | Copy current heading to clipboard. |
| `/dv` | Delete the vehicle you are in. |
| `/delveh` / `/deleteveh` | Alias for delete vehicle. |
| `/car <model>` | Spawn a vehicle model. |
| `/veh` / `/spawnveh` | Alias for `/car`. |
| `/fix` / `/fixveh` / `/repair` / `/repairveh` | Repair the current vehicle. |
| `/clean` / `/cleanveh` | Clean the current vehicle. |
| `/flip` | Flip the current vehicle. |
| `/maxmods` | Apply max performance mods. |
| `/weapon <model>` | Give a weapon. |
| `/giveweapon` | Alias for `/weapon`. |
| `/ammo <model> [amount]` | Set ammo for a weapon. |
| `/clearweapons` | Remove all weapons. |
| `/preview <model>` | Preview a vehicle model. |
| `/esadmin_reset` | Reset and reload the UI. |
</details>

### Exports

```lua
exports.cortex-admin:teleportToCoords(x, y, showNotification)
```

Teleports the local player to the given `x`/`y` coordinates, optionally displaying a notification.

## Architecture

- `fxmanifest.lua` – resource manifest; declares scripts, files, `es_lib` dependency, the `teleportToCoords` export and the `ui_page`.
- `shared/bridge.lua` – runtime detection for `qbx_core`, `ox_inventory`, and `qbx_vehicles`.
- `shared/config.lua` – central configuration, permission strings, and QBX permission mapping.
- `shared/actions.lua` – declarative catalog of 130 menu actions used by both client and server.
- `shared/weapon_component_hashes.lua` – weapon/tint/attachment data.
- `client/main.lua` – menu state, command registration, key mapping, world sync, NUI focus.
- `client/nui.lua` – NUI callbacks, vehicle preview logic, wardrobe sharing.
- `client/actions.lua` – client-side implementations for player, vehicle, appearance, teleport, dev and recording actions.
- `server/main.lua` – permission validation, world state, player actions (kick/ban/freeze/bring), resource manager, addon-vehicle metadata parsing, and ban storage.
- `server/bridge.lua` – QBX player/inventory/garage abstraction.
- `server/actions.lua` – ban persistence helpers.
- `server/vmenu_fallback.lua` – optional vMenu KVP snapshot reader for migration.
- `ui/` – React-based NUI frontend (`index.html`, `app.js`, `style.css`, `preview-shim.js`).
- `tools/` – `dev-server.ts` (Bun-based local preview server) and `export-preview-state.mjs` (regenerates `ui/preview-state.json` from `shared/actions.lua`).

## Development / UI Preview

The UI can be previewed in a normal browser:

1. (Optional) Regenerate the preview state when `shared/actions.lua` changes:
   ```bash
   node tools/export-preview-state.mjs
   ```
2. Start the local dev server:
   ```bash
   bun run dev
   ```
3. Open the URL printed in the terminal, for example:
   ```
   http://127.0.0.1:5173/?preview=1&debug=1
   ```

> The preview server requires [Bun](https://bun.sh). If you do not have Bun, you can serve `ui/` with any static file server and append `?preview=1&debug=1` to `index.html`.

## Limitations

- Requires `es_lib` to be installed and started first.
- QBX-branded tabs and actions (`Inventory`, `Garage`, `Give Money`, `Set Job/Gang`, `Admin Car`, etc.) require `qbx_core`, `ox_inventory`, or `qbx_vehicles` and will not function on a standalone server.
- Permissions are enforced through FiveM ACE; misconfiguring `permissions.cfg` can grant unintended access.
- The NUI frontend loads React, ReactDOM, Lucide icons, and Google Fonts from public CDNs. Servers or clients without internet access, or with a strict CSP, may fail to render the menu.
- Vehicle preview and customizer features rely on live NUI messages and native vehicle spawning; addon vehicles are discovered by scanning other resources’ `vehicles.meta` declarations and stream files.
- vMenu migration depends on local vMenu KVP data being readable from the server’s `APPDATA`/`HOME` paths.
- Some vehicle/appearance parity features are still being expanded; see `docs/superpowers` for the design backlog.
- Runtime debug writers are disabled unless `Config.Debug` is enabled. Generated `.cursor/` logs and UI test artifacts are ignored and should not be included in release packages.

## License

Released under the [MIT License](LICENSE).

Copyright (c) 2026 Ever3st.

## Disclaimer

`cortex-admin` is an independent FiveM resource and is not affiliated with, endorsed by, or sponsored by Cfx, Rockstar Games, or the QBX project. Trademarks and registered trademarks are the property of their respective owners.
