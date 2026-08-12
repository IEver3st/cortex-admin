# vMenu Parity + Migration Design

**Date:** 2026-03-24

**Goal**

Turn `cortex-admin` into a vMenu-class admin menu while preserving its current QBX/cortex-admin advantages, and provide a one-click migration path that permanently imports durable vMenu data into `cortex-admin` so vMenu can be removed afterward.

## Product Direction

- `cortex-admin` becomes the primary admin menu and long-term replacement for vMenu.
- `vMenu` can run alongside `cortex-admin` during transition.
- Durable vMenu data is imported into `cortex-admin` storage.
- ACE permissions remain the source of truth and retain vMenu-compatible behavior.
- Non-durable local settings are not imported.

## Durable Data to Migrate

- Saved MP peds / appearance presets
- Saved vehicle library / personal vehicles
- Teleport favorites and similar durable presets when available
- Durable admin favorites/loadouts where recoverable
- Permission behavior through ACE parity mapping

## Explicitly Out of Scope for Migration

- Pure UI preferences
- Transient runtime state
- In-memory-only vMenu state that cannot be recovered from exports or KVP data

## Architecture

### 1. Compatibility Layer

Add a dedicated vMenu compatibility layer inside `cortex-admin` that can:

- read live vMenu exports when vMenu is running,
- fall back to existing KVP snapshot parsing where possible,
- normalize vMenu schemas into `cortex-admin` schemas,
- import data idempotently,
- track provenance for imported entries.

### 2. Permissions Model

- Keep ACE permissions as the authority.
- Expand `cortex-admin` permission mapping to cover vMenu-equivalent actions.
- Preserve compatibility with existing `permissions.cfg` / ACE setups.

### 3. UI Model

Add a visible migration surface with:

- vMenu detection
- data counts by domain
- import actions
- result summaries
- clear messaging that ACE permissions remain live, not copied into local storage

## Phased Delivery

### Phase 1: Migration Foundation

- Add migration snapshot/status API
- Add one-click import flow
- Permanently import saved MP peds
- Permanently import saved vehicles
- Surface ACE compatibility summary
- Add UI entry point and result feedback

### Phase 2: Permissions Parity

- Audit all `cortex-admin` actions against vMenu-equivalent ACE behavior
- Add missing action-level permission mappings
- Validate parity under mixed admin/mod role setups

### Phase 3: Appearance / MP Ped Parity

- Complete heritage/head blend editing
- Expand overlays and face controls
- Add tattoos workflow
- Add randomization/default-character parity
- Improve saved outfit library UX

### Phase 4: Vehicle Parity

- Finish admin vehicle tools and saved vehicle parity
- Expand spawn/customization/admin controls
- Ensure imported vehicle library works without vMenu

### Phase 5: Remaining Admin Domains

- Player actions
- Weapons
- Teleport
- World controls
- Dev/server utilities

### Phase 6: Standalone Validation

- Verify `cortex-admin` functions without vMenu, except for ACE config still being present in the server environment
- Audit imported data correctness and parity gaps

## Risks

- Some vMenu data may be accessible only while vMenu is running
- Some domains may require KVP parsing rather than exports
- “Full parity” should be treated as functional parity, not byte-identical implementation

## Approved Recommendation

Use a **Bridge-First Migration** strategy:

1. keep both resources running,
2. import durable data into `cortex-admin`,
3. complete parity domain-by-domain,
4. remove vMenu once imports and parity are verified.
