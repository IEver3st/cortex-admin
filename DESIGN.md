---
version: alpha
name: Cortex Console
description: In-game admin console for FiveM — neutral ink surfaces, one configurable accent, typography-driven hierarchy.
colors:
  primary: "#0e1116"
  secondary: "#191e28"
  tertiary: "#e8a23f"
  ink-0: "#0a0c0f"
  ink-1: "#0e1116"
  ink-2: "#131720"
  ink-3: "#191e28"
  ink-4: "#212836"
  ink-5: "#2a3242"
  text-1: "#eceff4"
  text-2: "#aeb6c1"
  text-3: "#79828e"
  text-4: "#4e5661"
  accent: "#e8a23f"
  accent-hover: "#ecb157"
  success: "#45c78b"
  danger: "#e5605f"
  warning: "#e8b34b"
  info: "#5ea0e6"
  section-inventory: "#e0873c"
  line-1: "rgba(255, 255, 255, 0.05)"
  line-2: "rgba(255, 255, 255, 0.09)"
  line-3: "rgba(255, 255, 255, 0.14)"
  focus-ring: "rgba(232, 162, 63, 0.55)"
typography:
  h1:
    fontFamily: Inter
    fontSize: 1.375rem
    fontWeight: 700
    lineHeight: 1.2
    letterSpacing: "0.005em"
  section-title:
    fontFamily: Inter
    fontSize: 0.625rem
    fontWeight: 700
    lineHeight: 1.4
    letterSpacing: "0.10em"
  label:
    fontFamily: Inter
    fontSize: 0.781rem
    fontWeight: 500
    lineHeight: 1.35
    letterSpacing: "0.005em"
  body-md:
    fontFamily: Inter
    fontSize: 0.688rem
    fontWeight: 400
    lineHeight: 1.45
  caption:
    fontFamily: Inter
    fontSize: 0.594rem
    fontWeight: 400
    lineHeight: 1.4
  mono:
    fontFamily: Cascadia Mono
    fontSize: 0.688rem
    fontWeight: 400
    lineHeight: 1.4
rounded:
  sm: 5px
  md: 7px
  lg: 10px
  shell: 14px
spacing:
  xs: 4px
  sm: 6px
  md: 8px
  lg: 10px
  xl: 12px
  2xl: 16px
  3xl: 20px
components:
  shell:
    backgroundColor: "{colors.ink-1}"
    rounded: "{rounded.shell}"
    padding: 0px
  sidebar-item:
    backgroundColor: "transparent"
    textColor: "{colors.text-3}"
    rounded: "{rounded.md}"
    padding: 7px
  sidebar-item-active:
    backgroundColor: "rgba(232, 162, 63, 0.10)"
    textColor: "{colors.text-1}"
    rounded: "{rounded.md}"
    padding: 7px
  button-primary:
    backgroundColor: "{colors.ink-3}"
    textColor: "{colors.text-1}"
    rounded: "{rounded.md}"
    padding: 6px
  button-primary-hover:
    backgroundColor: "{colors.ink-4}"
    textColor: "{colors.text-1}"
    rounded: "{rounded.md}"
    padding: 6px
  button-success:
    backgroundColor: "rgba(69, 199, 139, 0.12)"
    textColor: "{colors.success}"
    rounded: "{rounded.md}"
    padding: 6px
  button-danger:
    backgroundColor: "rgba(229, 96, 95, 0.12)"
    textColor: "{colors.danger}"
    rounded: "{rounded.md}"
    padding: 6px
  action-row:
    backgroundColor: "transparent"
    textColor: "{colors.text-1}"
    rounded: "{rounded.md}"
    padding: 7px
  action-row-selected:
    backgroundColor: "rgba(232, 162, 63, 0.07)"
    textColor: "{colors.text-1}"
    rounded: "{rounded.md}"
    padding: 7px
  input:
    backgroundColor: "{colors.ink-2}"
    textColor: "{colors.text-1}"
    rounded: "{rounded.md}"
    padding: 7px
  settings-section:
    backgroundColor: "transparent"
    borderColor: "{colors.line-1}"
    rounded: 0px
    padding: 11px 0px
  toggle:
    width: 34px
    height: 19px
    backgroundColor: "transparent"
    rounded: 999px
    padding: 0px
  toggle-compact:
    width: 30px
    height: 18px
    backgroundColor: "transparent"
    rounded: 999px
    padding: 0px
  segmented-control:
    backgroundColor: "transparent"
    borderColor: "{colors.line-2}"
    rounded: "{rounded.md}"
    padding: 0px
---

## Overview

Cortex Console is an in-game FiveM admin NUI. The screen behind the menu is the
game world, so the design stays out of the way: deep neutral ink surfaces at
~98% opacity, flat hairline-divided settings instead of card stacks, and a
single warm amber accent (`#e8a23f`, user-configurable at runtime) reserved for
selection, focus, and live state. Nothing competes with the accent. Status
colors (success/danger/warning/info) appear only as soft-tinted text-on-tint
pairs.

The UI renders through CEF at arbitrary game resolutions, so nearly every
dimension is multiplied by a runtime `--es-ui-scale` factor. Tokens here are
the **1× base values**; never hard-code a scaled pixel value.

## Colors

- **Ink scale (ink-0 → ink-5):** the only surfaces. `ink-1` is the shell
  background, `ink-2`/`ink-3` are inputs and buttons, `ink-4`/`ink-5` are hover
  states. Surfaces never use pure black or saturated tints.
- **Accent (#e8a23f):** written at runtime by `applyMenuAccentCss` in
  `ui/app.js`; the CSS custom property is the contract, not this hex value.
  Used for active nav, selected rows, focus rings, and favorite stars — never
  for large fills.
- **Text scale (text-1 → text-4):** `text-1` primary, `text-2` secondary,
  `text-3` descriptions/placeholders, `text-4` disabled. All four pass WCAG AA
  on ink surfaces.
- **Status colors:** always paired with their `-soft` background (12% alpha)
  and `-border` (~28% alpha) variants; solid status fills are a Don't.
- **Hairlines (line-1/2/3):** 5–14% white. Borders do the separation work
  that elevation does in light themes.

## Typography

Inter (`--font-ui`) for everything; Cascadia Mono (`--font-mono`) for
coordinates, resource names, and code. Hierarchy is driven by weight and the
text color scale, not size jumps — the whole UI lives between 8.5px and 14px
(at 1× scale). Section titles are 10px bold uppercase with 0.10em tracking;
row labels are 11–12.5px medium; descriptions are 9.5–10.5px in `text-3`.

## Layout & Spacing

Spacing is a 4px base grid; the working values are 4/6/8/10/12/16/20px
(multiplied by `--es-ui-scale`). Row padding is 7px vertical; control gaps are
6–10px; section rhythm is 12–16px.

Three shell modes, all in `ui/style.css`:

- **Floating** (default): centered, `min(1560px, 94vw) × min(920px, 90vh)`,
  `border-radius: {rounded.shell}`, `resize: both`.
- **Docked left/right:** full-height edge panel, 780px wide (max 48vw).
- **Responsive:** `is-narrow` (viewport ≤1220px) collapses the 176px labeled
  sidebar to a 48px icon rail and shrinks the docked shell to 620px/60vw;
  `is-cramped` (≤980px or shell ≤680px) additionally trims paddings and hides
  topbar context. Breakpoints live in `getViewportProfile` in `ui/app.js`.

## Container discipline

The shell, a modal, and a true popover may establish a surface. Ordinary page
content should not keep inventing more surfaces inside them.

- Start with the first useful control when the sidebar and topbar already name
  the destination. Do not repeat that context with an eyebrow, page title,
  description, and status pill.
- Group settings with spacing and `line-1` dividers. Do not wrap every setting
  or section in a rounded, filled card.
- Do not add a summary or telemetry panel that repeats values already visible
  in the controls below it. Show extra state only when it changes a decision.
- A card needs an independent job, such as a modal, a temporary warning, or a
  selectable record. "This content belongs to the same page" is not enough.
- At idle, transient HUDs render nothing. Never leave an empty status box on
  screen to explain that nothing is happening.

## Canonical settings pattern

The Voice page is the reference for compact settings screens. Keep these rules
when changing it or building a similar page:

- The first row is the first setting. There is no `NATIVE VOICE` eyebrow,
  repeated `Voice controls` heading, descriptive intro, or engine status pill.
- Do not restore the `Live state` telemetry card. The toggle, selected range,
  channel readout, and indicator switches already expose the useful state.
- Settings sections stay transparent and square. A single `line-1` divider
  separates sections.
- A switch renders only its track and thumb. Its row label and accessible name
  carry the meaning. Never add an `ON` or `OFF` label or an outer switch box.
- Proximity options share one compact segmented container. Use four columns at
  docked width and two only at the cramped breakpoint. Internal hairlines,
  hover, focus, and selected fill communicate structure without four cards.
- The voice HUD exists only during live speech. Local transmission or a nearby
  speaker may mount it. Idle voice must leave no HUD DOM behind.

Treat these as rejection criteria. A passing build does not excuse duplicated
page context, card stacks, boxed switches, or idle status UI. Inspect the
docked and cramped layouts before accepting a settings-screen change.

## Elevation & Depth

One shadow language only: `0 8px 24px rgba(0,0,0,0.5)` for dropdowns/popovers,
`0 12px 32px rgba(0,0,0,0.45)` for modals, `0 32px 80px rgba(0,0,0,0.62)` for
the floating shell. Docked shells use a lateral shadow (±24px, 0, 64px) instead.
**Never use `backdrop-filter`** — FiveM's CEF samples an empty layer and
renders solid black behind the menu.

## Shapes

Small radii throughout: 5px (chips, small buttons), 7px (buttons, inputs,
rows), 10px (modals and independent overlays), 14px (the floating shell only).
Settings sections are square and transparent. A radius is not permission to
turn a section into a card. Docked shells and full-bleed panels are square
(radius 0). The active-nav indicator is a 3px accent bar, not a filled pill.

## Components

- **`sidebar-item`:** icon + 11.5px label; active state is a 10% accent tint
  plus the 3px left bar. In icon-rail mode the label hides and a tooltip
  (`::after` from `data-tooltip`) appears on hover.
- **`button-primary`:** the default button is intentionally quiet — ink-3
  fill, hairline border, ink-4 on hover, `transform: scale(0.98)` on press.
  `success`/`danger` variants are text-on-soft-tint, never solid.
- **`action-row`:** the core list unit — 12.5px label over a 10.5px
  description, controls (toggle/select/chevron) right-aligned, selected state
  is a 7% accent tint with a 2.5px left bar. Labels ellipsize; they never wrap.
- **`input` / `select`:** ink-2 fill, hairline border, focus is a 3px
  accent-glow ring (`--es-focus-glow`), never a layout-shifting outline.
- **`settings-section`:** transparent, square, and separated from the next
  section by one `line-1` divider. It is not a card.
- **`toggle`:** a bare 34×19px track and thumb. Compact settings such as Voice
  use the 30×18px variant. The button keeps `role="switch"`, `aria-checked`, a
  visible focus ring, and a descriptive accessible name. Never put it inside
  a second visual container.
- **`segmented-control`:** one outer hairline and internal dividers. Options do
  not get separate borders, decorative indexes, or redundant check icons.

## Do's and Don'ts

**Do**

- Reference tokens / CSS custom properties; the runtime scale and accent
  override depend on them.
- Keep new surfaces inside the ink scale and new text inside the text scale.
- Respect the three shell modes — test floating, docked, and `is-narrow`.
- Ellipsize overflowing labels with `text-overflow: ellipsis`.
- Use the Voice page as the density reference for settings screens.

**Don't**

- Don't introduce a second accent hue or solid status-color fills.
- Don't use `backdrop-filter` or transparent shell backgrounds (CEF black-box
  artifact).
- Don't hard-code pixels without the `--es-ui-scale` multiplier.
- Don't add box-shadows outside the three elevation levels, or borders heavier
  than `line-3`.
- Don't let labels wrap to a second line in rows — shorten the string instead.
- Don't stack rounded cards for settings, duplicate page context, or repeat
  control values in a separate summary panel.
- Don't add `ON`/`OFF` text containers around switches.
