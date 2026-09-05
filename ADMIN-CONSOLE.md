# Cortex admin menu

## Current visual contract

The latest September 4 revision keeps the sidebar style and restores a full-height
edge dock. It supersedes the small floating desk. The user's
in-game screenshots establish the rejected baseline: an icon rail, a cramped floating
window, favorite stars after labels, flattened toggle caps and studio
buttons that require a second click.

- Job: find and operate admin tools from a full-height, edge-docked menu while
  keeping the world visible. Preserve existing action and permission contracts.
- Width: 30vw on desktop with a 560px minimum for smaller viewports; retain
  full viewport height and edge docking. The latest screenshot rejects 46vw.
- Layout: a persistent labeled task sidebar; Player, Vehicles, World, Server and
  Developer workflows; secondary page tabs; fixed search/section filtering above
  an independently scrolling work area. Self controls and Online Players have
  separate pages, so the directory cannot push personal commands below the fold.
- First viewport: Workspace shows actual pinned commands and a small set of
  registered quick tools. Command library contains the complete searchable list.
  Studios remain outside the scrolling navigation and launch immediately through their existing
  camera/session owners. Done returns to the previous menu page.
- Material: ivory and ink, square controls, condensed italic section titles,
  thin rules, diagonal selection ends. No gradients, blur or viewport backing.
- Rows: left favorite column, command copy, right controls. Descriptions may wrap.
  Command toggle end caps stretch from divider to divider through the complete
  row height, including wrapped descriptions. Off has a visible
  dark plate, On an ivory plate. Preserve checked and disabled semantics.
- Responsive: scale-aware desktop sidebar; below 1000px, a labeled Browse tools
  menu retains every destination, including Preferences. Secondary controls wrap.
- States: pinned/empty/search, section filters, permission restrictions, keyboard
  focus, launch pending/rejection, late launch completion, close/reopen, reduced
  motion, long names and compact dimensions. No invented actions or telemetry.

## Runtime handoff

Restart `cortex-admin`. Confirm the new labeled sidebar and Workspace first.
Check full-height edge docking, left favorites, toggle geometry in both states,
command section filtering,
and the separate Self / Online Players tabs. Launch Character or Vehicle once from the sidebar;
Done should restore the previous page. Check no-source-vehicle/permission errors,
Escape while opening, menu close/reopen, and resource restart.

Repeat on both sides at 1080p/1440p and ultrawide, scales 1.0/1.6, bright and dark
scenes. At a narrow viewport check Browse tools, Preferences and scrolling.
Runtime, rendered acceptance and performance remain user-run. Static markup is
used only for composition/contract checks and is not visual evidence.

## Current static checks

Build, action parity (261 actions), all seven console tests, CSS compilation,
vehicle catalogue/workbench tests and four focused studio lifecycle Lua specs
pass. The NUI audit has zero errors and one existing intentional-modal warning.
Broader tests currently fail on the female appearance capsule's purple accents
and the wardrobe matte's uneven-backdrop fixture. Those files are being changed
outside this menu pass; no wardrobe generation or capture behavior was changed
to satisfy these checks.
