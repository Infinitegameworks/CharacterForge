---
title: "feat: CharacterForge Phase 1 — Core Validation Loop"
type: feat
status: active
date: 2026-05-06
origin: docs/brainstorms/aseprite-character-pipeline-plugin-requirements.md
deepened: 2026-05-06
---

# CharacterForge Phase 1 — Core Validation Loop

## Overview

Implement the MVP of CharacterForge, an Aseprite Lua extension that enforces layered character structure through blueprint-driven validation. Phase 1 delivers: blueprint creation, animation file generation from blueprints, structural validation (layers, variants, frame counts, naming), on-save error blocking, and a persistent validation status panel.

## Problem Frame

Artists drawing layered character sprites across many animation files have no tooling to enforce layer structure, validate naming consistency, or catch frame-count mismatches. Errors propagate silently until the game engine import fails. CharacterForge eliminates these errors at the source by defining a character blueprint that enforces structure across all animation files. (see origin: `docs/brainstorms/aseprite-character-pipeline-plugin-requirements.md`)

## Requirements Trace

- R1. Artist can create a character blueprint defining body parts, variants, and expected animations (Goal 3, F1.1)
- R2. One-click generation of correctly-structured animation files from a blueprint (Goal 3, F2.1)
- R3. Structural validation: required layers, required base variant, frame count consistency (Goal 1, F3.1/F3.2/F3.4)
- R4. Naming validation: exact match against blueprint-defined names (Goal 1, F4.1)
- R5. On-save blocking for hard errors across all three save commands (Goal 1, F7.2)
- R6. Persistent status panel with debounced updates (Goal 2 partial, F7.1)
- R7. All data persists in .ase extension properties — no external files (Goal 4)
- R8. Cached schema in animation files — never open another file during save (AD1)

## Scope Boundaries

- Phase 1 only — no cross-file scan, no blueprint dashboard, no progress reporting
- No edit-distance typo suggestions — clear error messages suffice
- No blueprint edit propagation — lazy validation on file open (Phase 2)
- No CLI batch mode
- Blueprint files store an animation registry but it is only updated on create/register, not by scanning

## Context & Research

### Relevant Patterns (from Attachment System analysis)

- Extension-namespaced properties via `sprite.properties("publisher/extension-name")`
- `setupSprite()` pattern for first-interaction initialization
- Schema versioning with migration logic
- `require` for module loading within extensions (returns tables)
- `beforecommand`/`aftercommand` for lifecycle interception

### Aseprite Lua API Constraints

- No hidden sprite open in GUI mode (tabs flash)
- `sprite.layers` returns top-level only — must recurse for groups
- Canvas widget for custom UI (no native listbox/tree)
- `LayerName` event fires on rename; `Change` event fires on every undo state change (including paint strokes)
- Timer class available for debouncing
- `app.transaction()` wraps operations in undo group
- Arrays in properties must be clean sequential tables (AD6)
- `ev.stopPropagation()` blocks the intercepted command

### Institutional Learnings

- None yet (greenfield project). Patterns established here become the foundation.

## Key Technical Decisions

- **Property namespace**: `"infinitegameworks/character-forge"` — collision-free, persists in binary format
- **Schema caching (AD1)**: Animation files carry a full copy of the blueprint schema for offline validation
- **Save interception (AD3)**: `beforecommand` for `SaveFile`, `SaveFileAs`, `SaveFileCopyAs`
- **Panel debouncing (AD4)**: `LayerName` immediate, `Change` 500ms debounce via Timer, layer tree hash comparison
- **Array safety (AD6)**: Always rebuild tables before writing to properties — never `table.remove()` + reassign
- **Module structure**: `require`-based modules returning tables (confirmed working in Aseprite extensions)

## Open Questions

### Resolved During Planning

- **Dialog widget for blueprint creation**: Use standard Aseprite Dialog widgets (entry, button, combobox) — no canvas needed for Phase 1 dialogs. Canvas only for the status panel.
- **How to detect layer tree changes for panel**: Compute a hash of `{layer.name, layer.isGroup, layer.parent}` for all layers. Compare to cached hash. Only re-validate when hash differs.
- **Where to store debounce timer**: As a module-level variable in `ui/panel.lua`. Timer lifetime tied to dialog lifetime via `onclose` cleanup.

### Deferred to Implementation

- Exact GraphicsContext draw calls for the status panel (depends on seeing real rendering)
- Whether `app.transaction()` is needed when writing properties during blueprint creation (test in Aseprite)
- Exact dialog layout dimensions (iterate visually)

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```
┌─────────────────────────────────────────────────────────────┐
│                        plugin.lua                            │
│  init(): register commands, wire beforecommand handler       │
│  exit(): close panel dialog                                  │
└────────────┬────────────────────┬───────────────────────────┘
             │                    │
    ┌────────▼────────┐  ┌───────▼────────┐
    │  blueprint.lua  │  │  validator.lua  │
    │                 │  │                 │
    │ readSchema()    │  │ validate()      │
    │ writeSchema()   │  │ validateLayers  │
    │ isBlueprint()   │  │ validateVariant │
    │ isAnimation()   │  │ validateFrames  │
    │ cacheSchema()   │  │ validateNames   │
    │ createBlueprint │  │ buildLayerHash  │
    │ createAnimation │  │                 │
    │ registerAnim()  │  └───────▲────────┘
    └────────┬────────┘          │
             │                   │
    ┌────────▼───────────────────┴────────┐
    │           ui/panel.lua               │
    │                                      │
    │ Canvas widget: status indicators     │
    │ Event wiring: LayerName + Change     │
    │ Debounce timer (500ms)               │
    │ Degraded mode display                │
    └──────────────────────────────────────┘
```

**Data flow on save:**
1. `beforecommand` fires for SaveFile/SaveFileAs/SaveFileCopyAs
2. Check `sprite.properties(PK).type == "animation"`
3. Read `cached_schema` from sprite's own properties
4. Run `validator.validate(sprite, cached_schema)`
5. If hard errors: `ev.stopPropagation()` + show error dialog
6. If pass/warn: allow save, update `last_validated` + `validation_result` + `layer_status`

**Data flow on panel update:**
1. `LayerName` event or debounced `Change` event fires
2. Compute layer tree hash, compare to cached hash
3. If different: run `validator.validate()`, update panel canvas
4. If same: no-op (paint stroke, not structural change)

## Implementation Units

- [ ] **Unit 1: Project scaffolding and extension manifest**

**Goal:** Create a loadable Aseprite extension with the correct structure, module stubs, and menu registration.

**Requirements:** R7 (extension properties foundation)

**Dependencies:** None

**Files:**
- Create: `package.json`
- Create: `plugin.lua`
- Create: `blueprint.lua`
- Create: `validator.lua`
- Create: `ui/panel.lua`
- Create: `ui/blueprint_editor.lua`
- Create: `ui/utils.lua`

**Approach:**
- `package.json` with publisher `"infinitegameworks"`, name `"character-forge"`, single script entry `"./plugin.lua"`
- `plugin.lua` defines `init(plugin)` and `exit(plugin)`, requires all modules, registers menu commands (stubbed handlers)
- Each module file returns a table with its public API (empty stubs initially)
- Define `PK = "infinitegameworks/character-forge"` as the property key constant in a shared location (top of `blueprint.lua`, exported)
- Register menu group "CharacterForge" under `sprite_properties`
- Register commands: "Create Blueprint", "New Animation from Blueprint", "Register Animation", "Validation Panel"

**Patterns to follow:**
- Attachment System's `package.json` structure (see `docs/reference/aseprite-attachment-system.md`)
- `require`-based module loading

**Test scenarios:**
- Happy path: Install extension in Aseprite, confirm it appears in Edit > Preferences > Extensions without errors
- Happy path: CharacterForge menu group appears in Sprite menu with all 4 commands listed
- Edge case: Extension loads cleanly even with no active sprite (onenabled guards return false)

**Verification:**
- Extension loads without Lua errors in Aseprite console
- All menu commands appear (greyed out when no sprite open)

---

- [ ] **Unit 2: Blueprint data model and property helpers**

**Goal:** Implement read/write functions for blueprint and animation schemas in extension properties.

**Requirements:** R7, R8

**Dependencies:** Unit 1

**Files:**
- Modify: `blueprint.lua`

**Approach:**
- `PK` constant: `"infinitegameworks/character-forge"`
- `SCHEMA_VERSION = 1`
- `readBlueprintSchema(sprite)` — reads `sprite.properties(PK)`, returns structured table or nil
- `writeBlueprintSchema(sprite, schema)` — builds clean sequential tables for all arrays, writes to `sprite.properties(PK)`
- `readAnimationData(sprite)` — reads animation file's properties
- `writeAnimationData(sprite, data)` — writes animation metadata + cached schema
- `isBlueprint(sprite)` — checks `type == "blueprint"`
- `isAnimation(sprite)` — checks `type == "animation"`
- `cacheSchemaInAnimation(sprite, blueprintSchema)` — copies body_parts + variants into animation's `cached_schema` with timestamp
- All write functions rebuild arrays from scratch (AD6 compliance)
- Include `setupSprite(sprite)` that initializes properties if missing

**Patterns to follow:**
- Attachment System's `db.lua` — `setupSprite()` pattern, property key constant, schema versioning

**Test scenarios:**
- Happy path: Write a full blueprint schema, read it back — all fields match including nested arrays
- Happy path: Write animation data with cached_schema, read it back — round-trip integrity
- Edge case: Read from a sprite with no CharacterForge properties — returns nil gracefully
- Edge case: Write a schema with empty body_parts array — stored as empty sequential table, reads back as empty table
- Integration: `isBlueprint()` returns true for a sprite after `writeBlueprintSchema()`, false for a fresh sprite

**Verification:**
- In Aseprite scripting console: create sprite, write schema, close + reopen file, read schema — identical data returned

---

- [ ] **Unit 3: Validator core — layer structure and frame counts**

**Goal:** Implement all structural validation logic that determines pass/warn/fail for an animation file.

**Requirements:** R3, R4

**Dependencies:** Unit 2

**Files:**
- Modify: `validator.lua`

**Approach:**
- `validate(sprite, schema)` — orchestrator, returns `{ result="pass"|"warn"|"fail", errors={}, warnings={} }`
- `validateRequiredLayers(sprite, schema)` — recurse `sprite.layers`, check each `schema.body_parts[].name` exists as a top-level group. Missing = error.
- `validateRequiredVariants(sprite, schema)` — for each body part group found, check sub-groups match `schema.variants`. Missing base = error. Missing equipment variant = warning.
- `validateFrameCounts(sprite, schema)` — for each body part, count cels in base variant. Compare all other variant sub-groups' cel count. Mismatch = error.
- `validateNames(sprite, schema)` — case-sensitive exact match of layer group names against schema-defined names. Mismatch = error with clear message.
- `buildLayerTreeHash(sprite)` — compute a string hash of layer names + hierarchy for change detection
- Helper: `findLayerByName(layers, name)` — iterates layer array looking for exact name match
- Helper: `countCels(layer)` — counts non-empty cels across all frames for a layer
- All validators accumulate into shared `errors` and `warnings` arrays

**Patterns to follow:**
- Structured result objects (not exceptions/asserts)
- Clear error messages: include expected name, found name, body part context

**Test scenarios:**
- Happy path: Sprite with all required layers, all variants, matching frame counts → result "pass", no errors
- Error path: Missing one body part group → result "fail", error names the missing group
- Error path: Missing base variant in one body part → result "fail", error names the part + variant
- Edge case: Equipment variant missing → result "warn" (not "fail"), warning lists the missing variant
- Error path: Frame count mismatch (base=8, armor=6) → result "fail", error names part + variant + counts
- Error path: Layer named "Right_Leg" when schema expects "right_leg" → result "fail", error shows exact mismatch
- Edge case: Sprite with extra layers not in schema → no error (unexpected layers are Phase 2)
- Edge case: Empty sprite (no layers at all) → result "fail", all body parts reported as missing

**Verification:**
- Programmatic test: create sprites with various structural problems, run validator, assert correct error/warning output

---

- [ ] **Unit 4: Create Blueprint dialog**

**Goal:** Artist-facing dialog for defining a new character blueprint, with file generation.

**Requirements:** R1

**Dependencies:** Unit 2

**Files:**
- Modify: `ui/blueprint_editor.lua`
- Modify: `plugin.lua` (wire command handler)

**Approach:**
- Dialog uses standard widgets: `entry` (character name), `entry` + `button` for adding items, `combobox` for selecting/removing existing items, `combobox` for variant type selection, `entry` for animation names
- **Add/Remove pattern**: Entry field + "Add" button to append. Combobox populated with current items + "Remove" button to delete the selected item. `dlg:modify{ id=comboboxId, options=updatedList }` refreshes the combobox options dynamically.
- State tracked in local tables during dialog interaction (body_parts list, variants list, animations list)
- On confirm:
  1. Create new sprite via `Sprite(64, 64, ColorMode.RGB)` (default canvas size)
  2. Create layer groups matching body_parts (sorted by sort_order)
  3. Within each body part group, create sub-groups for each variant
  4. Write blueprint schema via `writeBlueprintSchema()`
  5. Save the new sprite to the character directory via `sprite:saveAs(path)`
- Dialog validates: character name not empty, at least one body part, "base" variant always included
- Use `app.fs.joinPath()` for path construction

**Patterns to follow:**
- Aseprite Dialog API: `dlg:entry{}`, `dlg:button{}`, `dlg:separator{}`, `dlg:modify{}`

**Test scenarios:**
- Happy path: Fill in character name "hero", add 3 body parts, add 2 variants, add 2 animations → blueprint .ase created with correct layer groups and properties
- Edge case: Try to confirm with empty character name → validation message, dialog stays open
- Edge case: Try to confirm with no body parts → validation message
- Happy path: "base" variant auto-included and cannot be removed
- Integration: After creation, `readBlueprintSchema()` on the new file returns the exact schema entered

**Verification:**
- Create a blueprint via the dialog, open the resulting .ase file, verify layer structure matches input, verify extension properties are populated

---

- [ ] **Unit 5: New Animation from Blueprint**

**Goal:** One-click generation of a correctly-structured animation file linked to a blueprint.

**Requirements:** R2, R8

**Dependencies:** Unit 2, Unit 4

**Files:**
- Modify: `blueprint.lua` (add `createAnimationFromBlueprint()`)
- Modify: `plugin.lua` (wire command handler)

**Approach:**
- Command handler: show file picker (`dlg:file{ open=true, filetypes={"ase","aseprite"} }`) for blueprint selection, then `dlg:entry{}` for animation name
- Open selected blueprint, read schema via `readBlueprintSchema()`
- Create new sprite (same dimensions as blueprint sprite)
- Build layer structure: for each body_part → create group, for each variant → create sub-group within
- Write animation properties via `writeAnimationData()` including: blueprint_ref (relative path), cached_schema, character_name, animation_name
- Save new sprite in same directory as blueprint: `{character_name}_{animation_name}.ase`
- Update blueprint's animations registry: append new entry with name + relative file path + status "valid"
- Close the blueprint sprite after reading (it was opened just to read schema)

**Patterns to follow:**
- `app.fs.filePath()` to get blueprint directory
- `app.fs.joinPath()` for output path construction
- Relative path computation: just the filename since both live in same directory

**Test scenarios:**
- Happy path: Select blueprint, enter "idle" → creates `hero_idle.ase` with all body part groups + variant sub-groups + correct properties
- Happy path: Blueprint's animation registry now lists the new animation
- Edge case: Animation name already exists in registry → warning dialog, artist can overwrite or cancel
- Edge case: Blueprint file picker cancelled → no action, no error
- Integration: After creation, running `validate()` on the new file with its cached_schema returns "pass"

**Verification:**
- Generate animation file, open it, confirm layer structure matches blueprint, confirm `cached_schema` is populated and matches blueprint

---

- [ ] **Unit 6: Register Existing Animation**

**Goal:** Link a manually-created .ase file to a blueprint, enabling validation.

**Requirements:** R8

**Dependencies:** Unit 3, Unit 5

**Files:**
- Modify: `blueprint.lua` (add `registerAnimation()`)
- Modify: `plugin.lua` (wire command handler)

**Approach:**
- Requires an active sprite (guarded by `onenabled`)
- Show file picker for blueprint selection
- Open blueprint, read schema
- Run `validate(activeSprite, schema)` on the current file
- Show results dialog: errors/warnings listed. If hard errors exist, still allow registration (artist may fix structure after linking)
- Write animation properties to active sprite: blueprint_ref, cached_schema, character_name, animation_name (prompted via entry dialog)
- Update blueprint's animation registry
- Close blueprint sprite

**Test scenarios:**
- Happy path: Open existing .ase with correct structure, register to blueprint → properties written, registry updated, validation passes
- Happy path: Open .ase with structural issues, register → properties written with warnings shown, artist informed of what needs fixing
- Edge case: No active sprite → command disabled (onenabled returns false)
- Edge case: Active sprite is already registered to a different blueprint → confirm overwrite dialog

**Verification:**
- Register an existing file, confirm properties are written, confirm blueprint registry updated

---

- [ ] **Unit 7: On-Save validation hook**

**Goal:** Block saving animation files that have hard structural errors.

**Requirements:** R5

**Dependencies:** Unit 3

**Files:**
- Modify: `plugin.lua` (beforecommand handler)

**Approach:**
- In `init()`: `app.events:on('beforecommand', onBeforeCommand)` AND `app.events:on('aftercommand', onAfterCommand)`
- `onBeforeCommand(ev)`:
  - Check `ev.name` is one of: "SaveFile", "SaveFileAs", "SaveFileCopyAs"
  - Check `app.activeSprite` exists and `isAnimation(app.activeSprite)`
  - Read `cached_schema` from sprite properties
  - If no cached_schema: allow save (not a managed file, or degraded mode)
  - Run `validate(sprite, cached_schema)`
  - If result is "fail": `ev.stopPropagation()`, show `app.alert()` with error list
  - If result is "pass" or "warn": allow save (set a module-level `pendingValidationResult` flag)
- `onAfterCommand(ev)`:
  - Check same save command names
  - If `pendingValidationResult` is set: write `last_validated` + `validation_result` + `layer_status` to properties. Clear the flag. (File becomes dirty again — acceptable bookkeeping write.)
- In `exit()`: disconnect both event handlers

**Patterns to follow:**
- Attachment System's `beforecommand` pattern
- `ev.stopPropagation()` to block the command

**Test scenarios:**
- Happy path: Save valid animation file → save proceeds, validation metadata updated in properties
- Error path: Save file with missing required layer → save blocked, error dialog shown listing missing layers
- Error path: Save file with frame count mismatch → save blocked, error dialog shows mismatch details
- Happy path: Save file with only warnings (missing optional equipment variant) → save proceeds, warnings logged
- Edge case: Save non-animation file (blueprint or unregistered) → no validation, save proceeds normally
- Edge case: File has no cached_schema (never registered) → save proceeds without validation
- Integration: After blocked save, artist adds missing layer, saves again → save succeeds

**Verification:**
- Delete a required layer group from a registered animation, attempt save → blocked with clear error. Re-add layer, save again → succeeds.

---

- [ ] **Unit 8: Persistent status panel (canvas widget)**

**Goal:** Always-visible validation status with debounced live updates.

**Requirements:** R6

**Dependencies:** Unit 3

**Files:**
- Modify: `ui/panel.lua`
- Modify: `ui/utils.lua`
- Modify: `plugin.lua` (command to open panel, event wiring)

**Approach:**
- Panel is a non-modal dialog (`dlg:show{ wait=false }`) with a canvas widget
- Canvas draws: header with character name, list of body parts with colored status dots (green/yellow/red), frame count per variant, blueprint link status bar at bottom
- Color scheme in `ui/utils.lua`: STATUS_PASS (green), STATUS_WARN (yellow), STATUS_FAIL (red), STATUS_UNKNOWN (grey)
- Event wiring (done when panel opens):
  - `sprite.events:on('layername', onLayerName)` → immediate re-validate + repaint
  - `sprite.events:on('change', onSpriteChange)` → start/reset 500ms debounce timer
  - `app.events:on('sitechange', onSiteChange)` → re-evaluate if active sprite changed (different file)
- **Sprite switch unsubscribe/resubscribe pattern**: Track `currentSprite` reference and event connection objects. On `sitechange` to a different sprite: unsubscribe `layername` and `change` from old sprite, subscribe to new sprite. Prevents double-firing if user switches back and forth.
- Debounce implementation: use Timer class. On `Change` event: if timer active, cancel it. Start new 500ms timer. On timer fire: compute layer hash, if different from cached, re-validate.
- Degraded mode: if `blueprint_ref` file doesn't exist, show "Blueprint not found — using cached schema" in status bar. Add "Re-link" button (opens file picker to update `blueprint_ref`).
- `onclose` callback: disconnect all event handlers from current sprite, cancel timer, disconnect app-level sitechange
- Panel tracks current sprite reference — if `sitechange` detects a different sprite, unsubscribe old, subscribe new, re-read properties and re-validate

**Patterns to follow:**
- Canvas GraphicsContext: `fillRect` for backgrounds, `fillText` for labels, colored circles for status dots
- Aseprite Timer class for debouncing

**Test scenarios:**
- Happy path: Open registered animation file, open panel → shows correct status per body part with colors
- Happy path: Rename a layer to wrong name → panel updates immediately (LayerName event), shows red indicator
- Happy path: Add a new frame to base variant only → after 500ms debounce, panel shows frame count mismatch
- Edge case: Rapid paint strokes (Change events) → panel does NOT re-validate on each stroke, only after 500ms quiet period
- Edge case: Switch to a different sprite tab → panel refreshes to show new file's validation status
- Edge case: Open non-animation file → panel shows "Not a CharacterForge animation" or similar neutral state
- Edge case: Blueprint file not found → panel shows degraded mode with "Re-link" action

**Verification:**
- Open panel, make structural changes to the file, observe panel updates within 500ms without blocking the drawing workflow

---

- [ ] **Unit 9: Schema cache refresh on file open**

**Goal:** Detect stale cached schemas and offer refresh when the blueprint has been updated.

**Requirements:** R8

**Dependencies:** Unit 2, Unit 8

**Files:**
- Modify: `plugin.lua` (sitechange handler enhancement)
- Modify: `blueprint.lua` (add `refreshSchemaCache()`)

**Approach:**
- **Re-entrancy guard**: Module-level `isRefreshingCache` flag. Set true before opening blueprint, cleared after closing. The `sitechange` handler checks this flag and short-circuits if true — prevents recursive loop from `app.open()` triggering another `sitechange`.
- On `sitechange` event (already wired for panel): if `isRefreshingCache` → return. If the newly-active sprite `isAnimation()`:
  - Read `blueprint_ref` from properties
  - Resolve to absolute path via `app.fs.joinPath(sprite directory, blueprint_ref)`
  - If file exists: set `isRefreshingCache = true`, open it, read schema, compare to `cached_schema.cache_timestamp`
  - If blueprint schema is newer (or cached_schema is missing timestamp): show notification "Blueprint updated — N new requirements. Accept?" via `app.alert` with OK/Cancel
  - On accept: update `cached_schema` in the animation file's properties, re-validate, repaint panel
  - On dismiss: do nothing (stale cache persists until next open)
  - Close the blueprint sprite, set `isRefreshingCache = false`
- If `blueprint_ref` file doesn't exist: set degraded mode flag, panel shows indicator
- Throttle: only check once per sprite (cache the last-checked sprite filename + result)

**Patterns to follow:**
- `app.fs.isFile()` for existence check before attempting open
- `app.fs.filePath(sprite.filename)` to get the current file's directory

**Test scenarios:**
- Happy path: Open animation whose blueprint hasn't changed → no notification, normal validation
- Happy path: Modify blueprint (add new body part), then open an animation → notification "1 new requirement detected", accept → cache updated, panel shows new requirement as red
- Edge case: Blueprint file moved/deleted → degraded mode, no crash, panel shows "Blueprint not found"
- Edge case: Animation file has no blueprint_ref → no refresh attempted, no error
- Edge case: Open same file twice in a row → only checks blueprint on first open (throttled)

**Verification:**
- Modify a blueprint's body_parts, open a previously-created animation, confirm refresh notification appears and updates validation state

---

- [ ] **Unit 10: Integration testing and polish**

**Goal:** End-to-end workflow validation and UX polish for the complete Phase 1 feature set.

**Requirements:** R1, R2, R3, R4, R5, R6, R7, R8

**Dependencies:** All previous units

**Files:**
- Modify: `plugin.lua` (final wiring, menu ordering)
- Modify: `ui/panel.lua` (layout polish)
- Modify: `ui/utils.lua` (shared constants)

**Approach:**
- Full workflow test: create blueprint → generate 3 animations → validate all pass → intentionally break one → confirm save blocks → fix → confirm save succeeds
- Verify menu command ordering and naming consistency
- Verify panel doesn't leak event handlers when closed and reopened
- Verify all error messages are actionable and reference specific layer/variant names
- Test with realistic character complexity: 6 body parts, 3 variants, 8-frame animations
- Confirm `schema_version` field is correctly written and readable

**Test scenarios:**
- Integration: Full workflow — Create "hero" blueprint with head/torso/arms/legs + base/armor variants + idle/walk/run animations → generate all 3 → validate all pass
- Integration: Delete "right_arm" group from hero_idle → save blocked → re-add → save succeeds → panel shows green
- Integration: Rename "torso" to "Torso" → save blocked with naming error → rename back → save succeeds
- Integration: Add frames to base variant only (mismatch) → save blocked → add matching frames to variants → save succeeds
- Integration: Close panel, reopen → event handlers work correctly, no double-firing
- Edge case: Create blueprint, do NOT create any animations, open panel → shows neutral state
- Edge case: Register an existing animation that has structural issues → registration succeeds, panel shows errors, save will block until fixed

**Verification:**
- Complete the full artist workflow end-to-end in under 5 minutes without encountering unexpected errors or crashes

## System-Wide Impact

- **Interaction graph:** `beforecommand` handler intercepts ALL save commands application-wide. Guard clause (`isAnimation()` check) ensures non-CharacterForge files are unaffected.
- **Error propagation:** Validation errors surface as `app.alert()` dialogs. No silent failures. Blocked saves leave the file in its current unsaved state (safe).
- **State lifecycle risks:** Panel's event handlers must be disconnected on close to prevent ghost callbacks. Timer must be cancelled. Sprite reference must be validated against `app.activeSprite` before accessing.
- **API surface parity:** No external APIs. All interaction is through Aseprite's extension property system.
- **Unchanged invariants:** Normal Aseprite file behavior for non-CharacterForge files is completely unaffected. The `beforecommand` handler short-circuits immediately for non-animation files.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `ev.stopPropagation()` may not reliably block save in all Aseprite versions | Test with target Aseprite version (v1.3+). If unreliable, fall back to modifying file state post-save as a detection mechanism. |
| Timer class behavior for debouncing may differ from expected | Prototype the debounce pattern in Unit 8 early. If Timer doesn't support cancel/restart, use a timestamp comparison approach instead. |
| Opening blueprint file in `sitechange` handler may briefly flash a tab | Acceptable for cache refresh (happens once per file open, not during drawing). Tab closes immediately after read. |
| Canvas widget performance with many body parts (10+) | Keep draw operations minimal — flat list of colored dots + text. No complex tree rendering in Phase 1. |
| Dialog widget limitations for blueprint creation (no dynamic list widget) | Use entry + button + combobox + remove pattern. `dlg:modify{}` refreshes combobox options dynamically. |
| Recursive `sitechange` loop when opening blueprint for cache refresh | Re-entrancy guard flag (`isRefreshingCache`) prevents handler from re-triggering during blueprint open/close. |
| Per-sprite event handler leak on tab switch | Explicit unsubscribe from old sprite's events before subscribing to new sprite in `sitechange` handler. Track connection objects for cleanup. |
| `aftercommand` metadata write makes file dirty after save | Acceptable trade-off — validation metadata is bookkeeping. Artist can ignore the "unsaved" indicator or save again. |

## Sources & References

- **Origin document:** [docs/brainstorms/aseprite-character-pipeline-plugin-requirements.md](docs/brainstorms/aseprite-character-pipeline-plugin-requirements.md)
- Attachment System architecture: [docs/reference/aseprite-attachment-system.md](docs/reference/aseprite-attachment-system.md)
- Aseprite Lua API: [docs/reference/aseprite-lua-api.md](docs/reference/aseprite-lua-api.md)
- Extension ecosystem: [docs/reference/aseprite-extension-ecosystem.md](docs/reference/aseprite-extension-ecosystem.md)
