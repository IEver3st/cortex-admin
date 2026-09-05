# es_admin design contract

Design standard for the FiveM administrative NUI in `ui/`. Read with `README.md`, `shared/actions.lua`, and `ui/style.css`. The exported action model, shipped tokens, and verified in-game behavior outrank this document; update it when they diverge.

The target is a fast, controlled administrative overlay: obvious under pressure, dense without becoming noisy, and explicit about scope and consequence.

## Decision order

1. Operational clarity
2. Navigation and target context
3. Hierarchy
4. Authority and action truth
5. Robustness
6. Polish
7. Distinctiveness
8. Decoration

Safety and target certainty always outrank speed or spectacle.

## Signature

es_admin uses three ideas consistently:

- a compact dark command surface with scarce indigo interaction color;
- action groups, target context, and confirmation scope expressed through alignment and rules;
- immediate `select -> review scope -> execute -> result` feedback.

Reference products may supply principles. Never copy their layouts, type, assets, copy, colors, or identity.

## Working doctrine

- Keep the current target, action category, permission state, and consequence visible.
- Give each view one leading task and one primary action.
- Use typography, alignment, rows, search, and structural separators before cards.
- Cards are reserved for discrete players, resources, or action records when containment aids selection.
- Show authoritative server results. Never present a click, client acknowledgement, fixture, or preview event as completed server action.
- Destructive or high-impact actions state exact scope and require deliberate confirmation.
- Every visible element must improve comprehension, target certainty, navigation, actionability, state, recovery, or product identity.

## Slop gate

If two generic patterns appear together, stop adding and subtract. Watch for dashboard metric cards, decorative pills, gradients or glow carrying hierarchy, icons in colored squares, excessive badges, fake terminal output, repeated headings, and helper copy that restates the selected action.

## Type, color, and surfaces

`ui/style.css` owns exact values. Use the `--es-*` roles rather than ad hoc colors.

- Indigo marks focus, selection, and the primary action. Semantic colors describe real success, warning, information, or failure and always have a text or shape cue.
- Outfit carries ordinary interface text. Share Tech Mono is for terse identifiers, command values, coordinates, and technical state, not all copy.
- Prefer one stable overlay with list, work area, and detail relationships. Temporary elevation belongs to menus, dialogs, and confirmations.
- Use small radii and quiet borders. Avoid card nesting, heavy shadow, glass, and decorative blur.

## Interaction

Every interactive element defines default, hover, focus-visible, active, disabled, pending, success, and error behavior where applicable. Keyboard order follows the visual order. Escape closes the top transient layer and returns focus. Search retains its value after recoverable errors. NUI focus is acquired and released deliberately.

Hit areas remain usable at the configured UI scale. Hover-only behavior is never required. Long names, identifiers, and action labels wrap or truncate with an accessible full value.

## Motion

Motion explains overlay entry, selection, disclosure, confirmation, progress, or result feedback. Reuse `--es-motion-*` and the shared ease. Keep distances small, never animate indefinitely, and provide an immediate reduced-motion path. Animation cannot delay an administrative action or obscure its result.

## Hardening

Stress awkward game aspect ratios, safe-zone and UI scaling, long player names and identifiers, empty and large action lists, missing permission, disconnected targets, stale selections, callback timeout, server rejection, partial data, keyboard-only use, and reduced motion. Preserve layout when late state arrives. Flex and grid children use `min-width: 0` and external text wraps safely.

## Validation

Before handoff:

1. Regenerate preview state after `shared/actions.lua` changes.
2. Inspect the browser preview at representative narrow and wide viewport sizes.
3. Exercise search, category navigation, target changes, confirmation, cancellation, timeout, rejection, success, focus restoration, and Escape behavior.
4. Verify the affected flow in FiveM when NUI focus, callbacks, permissions, or server authority changed.
5. Run `git diff --check`.

Browser preview is layout evidence only. It does not prove FiveM NUI focus, permissions, server execution, target synchronization, or multi-client behavior.

## Definition of done

The target, scope, and next action are obvious; authority and result state are truthful; the signature remains visible without borrowed reference styling; containment is justified; all relevant states exist; no overflow or avoidable shift remains; keyboard and reduced-motion paths work; and the real affected boundary has been verified.
