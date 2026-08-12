# vMenu Parity + Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a phased migration and parity path so `cortex-admin` can permanently import durable vMenu data, preserve ACE behavior, and progressively replace vMenu.

**Architecture:** Build a migration foundation first using the existing vMenu bridge and KVP fallback readers, then expand parity domain-by-domain. Persist imported records in `cortex-admin` storage and keep ACE permissions as the live access-control model.

**Tech Stack:** FiveM Lua, NUI React-in-JS, resource KVP storage, vMenu exports, fallback KVP snapshot reader

---

### Task 1: Migration Snapshot API

**Files:**
- Modify: `client/actions.lua`
- Modify: `client/nui.lua`

- [ ] **Step 1: Add a migration snapshot builder**
- [ ] **Step 2: Report vMenu availability and durable-data counts**
- [ ] **Step 3: Report ACE compatibility summary**
- [ ] **Step 4: Expose snapshot via NUI callback**

### Task 2: Permanent Vehicle Import

**Files:**
- Modify: `client/actions.lua`

- [ ] **Step 1: Reuse existing vMenu vehicle normalization helpers**
- [ ] **Step 2: Copy vMenu vehicle entries into cortex-admin storage**
- [ ] **Step 3: Skip duplicates safely and preserve metadata**
- [ ] **Step 4: Refresh cached personal vehicle summaries**

### Task 3: One-Click vMenu Import

**Files:**
- Modify: `client/actions.lua`
- Modify: `client/nui.lua`

- [ ] **Step 1: Add combined import orchestrator**
- [ ] **Step 2: Import peds and vehicles in one action**
- [ ] **Step 3: Return structured success/failure summary**
- [ ] **Step 4: Keep ACE permissions in passthrough mode**

### Task 4: Migration UI

**Files:**
- Modify: `ui/app.js`
- Modify: `ui/style.css`

- [ ] **Step 1: Add migration status panel**
- [ ] **Step 2: Show detected counts and ACE mode**
- [ ] **Step 3: Add one-click import action**
- [ ] **Step 4: Refresh appearance/library state after import**

### Task 5: Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-03-24-vmenu-parity-migration.md`

- [ ] **Step 1: Run targeted syntax validation where feasible**
- [ ] **Step 2: Verify callbacks and references are wired correctly**
- [ ] **Step 3: Summarize Phase 1 results and next parity phase**
