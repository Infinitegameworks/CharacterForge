# CharacterForge — Aseprite Character Pipeline Plugin Requirements

**Status**: Reviewed (feasibility + scope)
**Date**: 2026-05-06
**Scope**: Aseprite Lua extension only (UE5 asset/importer is a separate brainstorm)
**Plugin Name**: CharacterForge
**Publisher Namespace**: `"infinitegameworks/character-forge"`

## Problem Statement

Layered character art for 2D games requires strict organizational discipline across many files. An artist drawing a character with body-part layers, equipment variants, and state variants across 10+ animations has no tooling to enforce structure, validate consistency, or track completeness. Mistakes (missing layers, wrong frame counts, inconsistent naming) propagate silently until they hit the game engine import pipeline.

No existing Aseprite extension addresses layer structure validation, cross-file consistency, naming enforcement, or project-level completeness tracking.

## Goals

1. Eliminate structural errors at the source (Aseprite) rather than catching them downstream in the engine
2. Give artists a clear, always-visible progress picture of what's been drawn and what's missing
3. Reduce setup friction for new animations — one click from blueprint to ready-to-draw file
4. Establish a data contract (stored in .ase extension properties) that a UE5 importer can consume directly

## Non-Goals

- Runtime sprite composition (that's the engine's job)
- Art direction or style enforcement (the plugin doesn't judge art quality)
- Automated sprite sheet export (existing plugins handle this; we focus on structure/metadata)
- UE5 plugin implementation (separate project, separate brainstorm)
- Blueprint inheritance/templates across characters (future consideration)

## Users

**Primary**: Artists drawing layered character sprites for games using Aseprite
**Secondary**: Technical artists / developers who define character schemas and consume the data in-engine

---

## Core Concepts

### Character Blueprint (.ase)

A special-purpose Aseprite file — one per character — that serves as:
- **Schema**: Defines required body parts (layer groups), variant slots, and naming
- **Animation registry**: Lists all expected animations and tracks which exist
- **Template source**: Plugin generates new animation files from the blueprint's layer structure

The blueprint may or may not contain actual art (e.g., a reference pose). Its primary purpose is structural definition stored in extension properties.

### Animation File (.ase)

A standard Aseprite file — one per animation per character — containing the actual drawn art. Created from a blueprint (or manually registered to one). Validated against a **cached copy** of the blueprint's schema stored in its own extension properties.

### Body Parts

Top-level layer groups in the blueprint/animation files representing decomposed character parts (e.g., `head`, `torso`, `right_arm`, `left_leg`). These are the structural units that must be consistent across all animation files.

### Variants

Sub-groups within a body part group representing visual alternatives:
- **Equipment variants**: Must be drawn across ALL animations (e.g., `armor`, `red_pants`)
- **State variants**: Drawn selectively for specific animations (e.g., `damaged`, `glowing`)
- **Base**: The default variant — always required

### Variant Frame Count Rule

Every variant sub-group within a body part must have the same number of frames/cels as the `base` variant for that animation. If `right_leg/base` has 8 frames, `right_leg/armor` must also have exactly 8 frames.

---

## File Organization

```
sprites/
  hero/
    hero_blueprint.ase       <- character blueprint (schema + registry)
    hero_idle.ase             <- animation file
    hero_walk.ase
    hero_run.ase
    hero_attack_light.ase
    ...
  enemy_slime/
    enemy_slime_blueprint.ase
    enemy_slime_idle.ase
    ...
```

- **Directory per character**: All files for a character in one folder
- **Blueprint references**: The blueprint's extension properties store a registry of animation files (paths relative to the blueprint). This is the authoritative link — directory scanning is for discovery, not authority.
- **File naming**: Blueprint-defined. The blueprint specifies expected file name patterns for its animations.

---

## Architectural Decisions (from review)

### AD1: Blueprint Schema Cached in Animation Files

Animation files store a **cached copy** of the blueprint schema (body parts, variants, naming rules) in their own extension properties. This means:
- On-save validation NEVER opens the blueprint file (unsafe during save handlers — changes active document context)
- Validation works offline (blueprint deleted/moved = degraded mode with stale cache, not failure)
- Cache is refreshed when the animation file is opened and the blueprint is reachable

**Degraded mode**: If `blueprint_ref` path is unreachable:
- Status panel shows "Blueprint not found — using cached schema"
- Save validation still works (uses cached schema)
- "Re-link Blueprint" action available in panel
- Cross-file features disabled until re-linked

### AD2: Lazy Blueprint Change Propagation

When a blueprint is edited, changes do NOT batch-write to all animation files. Instead:
- Each animation file checks its cached schema against the live blueprint on next open
- If the blueprint has changed: "Blueprint updated — X new requirements detected" notification
- Artist can accept (update cache + validate) or dismiss

This eliminates the multi-file write coordination problem entirely.

### AD3: Save Interception Covers All Save Commands

Intercept via `beforecommand` for: `SaveFile`, `SaveFileAs`, `SaveFileCopyAs`.
Known limitation: Programmatic `Sprite:saveAs()` / `Sprite:saveCopyAs()` from other scripts bypass `beforecommand`.

### AD4: Panel Update Debouncing

The persistent status panel does NOT re-validate on every `sprite.events:on('change')` (fires on every paint stroke). Instead:
- `LayerName` event → immediate re-validate (naming/structure may have changed)
- `Change` event → 500ms debounce timer. Only re-validate if no further Change events arrive within the window.
- Structure-affecting changes (layer add/remove/reorder) are detected by comparing layer tree hash to cached hash.

### AD5: Cross-File Scan Uses Blocking Dialog

Phase 2's cross-file scan opens each .ase file via `app.open()` + property read + `sprite:close()`. This causes tab flashing and blocks the UI.
- Show a "Scanning... (X/Y files)" progress dialog
- Accept tab flashing as a known UX limitation for now
- Future optimization: implement minimal .aseprite binary parser in Lua to read only the properties chunk without opening files

### AD6: Array Properties Must Be Clean Sequential Tables

Aseprite's `is_array_table()` checks for sequential integer keys starting at 1. All array-type properties must be written as freshly-constructed tables, never modified in-place with `table.remove()`. Always rebuild the full table and re-assign.

---

## Delivery Phases

### Phase 1 — Core Validation Loop (MVP)

Delivers Goals 1, 3, 4 (partial). A complete, shippable tool.

| Feature | Description |
|---------|-------------|
| F1.1 | Create Blueprint (dialog + file generation) |
| F2.1 | New Animation from Blueprint (template generation) |
| F2.2 | Register Existing Animation |
| F3.1 | Required Layer Check (hard error) |
| F3.2 | Required Variant Check (base = hard error, equipment = warning) |
| F3.4 | Frame Count Consistency (hard error) |
| F4.1 | Blueprint-Defined Names (exact match validation) |
| F7.1 | Persistent Status Panel (canvas widget, debounced) |
| F7.2 | On-Save Validation (all three save commands) |
| AD1 | Blueprint schema caching in animation files |

### Phase 2 — Project Visibility

Delivers Goal 2 fully.

| Feature | Description |
|---------|-------------|
| F1.3 | Blueprint Dashboard (using Dialog widgets + canvas for grid) |
| F3.3 | Unexpected Layer Detection (warning) |
| F5.1 | Layer Structure Consistency (cross-file) |
| F5.2 | Cross-File Scan (blocking dialog with progress) |
| F6.1 | Animation Registry (in blueprint properties) |
| F6.3 | Progress Reporting (computed on-demand from scan results) |
| F7.3 | Validation Report Dialog |
| AD2 | Lazy blueprint change propagation |

### Deferred

| Feature | Reason |
|---------|--------|
| F1.2 (blueprint edit propagation as writes) | Replaced by AD2 lazy validation |
| F4.2 (edit-distance rename assistance) | Clear error messages are sufficient |
| F6.2 (persisted 3D completion matrix) | Derived on-demand from per-file validation; no need to persist |
| CLI batch mode | Useful but not required for artist workflow |
| Binary .aseprite parser for headless property reading | Optimization for cross-file scan performance |
| Blueprint inheritance | Future consideration for multi-character projects |

---

## Feature Requirements

### F1: Blueprint Management

**F1.1 — Create Blueprint**
Artist creates a new character blueprint via plugin menu command. Interactive dialog:
- Character name
- Body part list (add/remove/reorder groups)
- Per-part variant slots (name, type: equipment vs state)
- Initial animation list (names of expected animations)

Result: A new .ase file with the defined layer/group structure and all metadata in extension properties.

**F1.3 — Blueprint Dashboard** (Phase 2)
A dialog showing the character's full status:
- List of expected animations with status (exists / missing / invalid)
- Per-animation validation summary (computed on-demand via cross-file scan)
- Overall progress percentage
- Quick-action buttons: "Create Missing Animation", "Open Animation", "Validate All"

Implementation: Use standard Dialog widgets (labels, buttons, combobox) for navigation. Canvas widget only for the completion status grid.

### F2: Animation File Management

**F2.1 — New Animation from Blueprint**
Menu command: select a blueprint, name the animation. Plugin generates a new .ase file with:
- All required body part groups
- All variant sub-groups within each part
- 1 frame as starting point
- Extension properties linking back to the blueprint + cached schema
- File placed in the character's directory
- Blueprint's animation registry updated

**F2.2 — Register Existing Animation**
For files created manually: a command to link an existing .ase to a blueprint. Plugin validates layer structure and stores the blueprint reference + cached schema in extension properties.

**F2.3 — Animation Metadata**
Each animation file stores (in extension properties):
- Blueprint reference (relative path)
- Character name + animation name
- Cached blueprint schema (body parts, variants, naming rules)
- Schema cache timestamp (for staleness detection)
- Per-layer validation state
- Per-variant completion flags

### F3: Layer Structure Validation

**F3.1 — Required Layer Check**
Validate that all body part groups defined in the cached schema exist in the animation file. Missing groups are hard errors (block save).

**F3.2 — Required Variant Check**
Validate that all equipment variant sub-groups exist within each body part. Missing equipment variants are warnings (shown in panel, don't block save). Missing base variant is a hard error.

**F3.3 — Unexpected Layer Detection** (Phase 2)
Flag layers/groups that exist in the animation file but aren't defined in the cached schema. These are warnings.

**F3.4 — Frame Count Consistency**
Within each body part, all variant sub-groups must have the same number of drawn cels as the base. Mismatches are hard errors.

### F4: Naming Convention Enforcement

**F4.1 — Blueprint-Defined Names**
The cached schema defines exact expected names for body parts and variants. Animation files must use these exact names. Validation produces clear error messages: "Expected `right_leg`, found `Right_Leg` — layer names are case-sensitive."

### F5: Cross-File Consistency (Phase 2)

**F5.1 — Layer Structure Consistency**
All animation files for a character must have the same set of body part groups and variant sub-groups (as defined by the blueprint). Validated via "Validate All" in the dashboard.

**F5.2 — Cross-File Scan**
Batch operation with blocking progress dialog: open each .ase file in the character's directory, read extension properties, compare against blueprint. Generate report of inconsistencies. Updates animation registry in blueprint properties.

### F6: Asset Catalog & Inventory (Phase 2)

**F6.1 — Animation Registry**
Blueprint extension properties maintain:
- List of expected animation names
- For each: file path (relative), existence status, last scan result

Updated only during explicit cross-file scan (F5.2) or when creating/registering animations.

**F6.3 — Progress Reporting**
Computed on-demand from the latest scan results + per-file validation data:
- "Hero: 7/12 animations complete, 68% variant coverage"
- "hero_idle: all variants drawn. hero_attack: missing armor variants for left_arm, right_arm"

### F7: Validation UX

**F7.1 — Persistent Status Panel**
A canvas-widget dialog showing real-time validation status for the currently open file:
- Green/yellow/red indicators per body part
- Per-variant status (compact)
- Frame count validation results
- Blueprint link status + staleness indicator
- "Re-link Blueprint" action if blueprint unreachable

Event handling:
- `LayerName` → immediate re-validate
- `Change` → 500ms debounce, only if layer tree hash changed
- Panel draw uses green (pass), yellow (warnings), red (errors)

**F7.2 — On-Save Validation**
Intercept `beforecommand` for `SaveFile`, `SaveFileAs`, `SaveFileCopyAs`. Run hard-error checks:
- Missing required body part groups → block save, show error dialog
- Missing base variant → block save
- Frame count mismatch → block save
Soft warnings are shown in the panel but don't block save.

Uses cached schema only — never opens another file during save handler.

**F7.3 — Validation Report Dialog** (Phase 2)
On-demand detailed report showing all issues across all animation files for a character. Launched from blueprint dashboard.

---

## Data Schema (Extension Properties)

Property key: `"infinitegameworks/character-forge"`

### Blueprint File Properties

```lua
sprite.properties(PK) = {
  schema_version = 1,
  type = "blueprint",
  character_name = "hero",

  body_parts = {
    { name = "head", sort_order = 1 },
    { name = "torso", sort_order = 2 },
    { name = "right_arm", sort_order = 3 },
    { name = "left_arm", sort_order = 4 },
    { name = "right_leg", sort_order = 5 },
    { name = "left_leg", sort_order = 6 },
  },

  variants = {
    { name = "base", type = "equipment", required = true },
    { name = "armor", type = "equipment", required = false },
    { name = "red_pants", type = "equipment", required = false },
    { name = "damaged", type = "state", required = false,
      applies_to = { "hurt", "death" } },
  },

  animations = {
    { name = "idle", file = "hero_idle.ase", status = "valid" },
    { name = "walk", file = "hero_walk.ase", status = "valid" },
    { name = "run", file = "hero_run.ase", status = "missing" },
    { name = "attack_light", file = "hero_attack_light.ase", status = "invalid" },
  },
}
```

### Animation File Properties

```lua
sprite.properties(PK) = {
  schema_version = 1,
  type = "animation",
  blueprint_ref = "hero_blueprint.ase",
  character_name = "hero",
  animation_name = "idle",

  -- Cached blueprint schema (for offline validation)
  cached_schema = {
    body_parts = { ... },  -- copy of blueprint's body_parts
    variants = { ... },    -- copy of blueprint's variants
    cache_timestamp = 1746547200,
  },

  -- Validation results (updated on save/validate)
  last_validated = 1746547200,
  validation_result = "pass",  -- "pass" | "warn" | "fail"

  layer_status = {
    { part = "head", base_frames = 8, variants_complete = { "base", "armor" } },
    { part = "torso", base_frames = 8, variants_complete = { "base" } },
  }
}
```

---

## Plugin Architecture

```
character-forge/
  package.json              -- extension manifest
  plugin.lua                -- init/exit, command registration, event wiring
  blueprint.lua             -- blueprint CRUD, template generation, schema helpers
  validator.lua             -- all validation logic, schema caching, progress computation
  ui/
    panel.lua               -- persistent status panel (canvas widget)
    dashboard.lua           -- blueprint dashboard dialog (Phase 2)
    blueprint_editor.lua    -- blueprint creation/editing dialog
    utils.lua               -- shared UI drawing helpers (hit testing, colors, layout)
```

### Key Patterns

1. **Extension-namespaced properties** (`"infinitegameworks/character-forge"`) for all in-file data
2. **Schema versioning** (`schema_version = 1`) with inline migration in `plugin.lua`
3. **`setupSprite()` pattern** — on first interaction, ensure properties are initialized
4. **Cached schema in animation files** — never open another file during save validation
5. **`beforecommand` interception** for save-time validation (all three save commands)
6. **Clean sequential tables** — always rebuild arrays before writing to properties
7. **Debounced panel updates** — LayerName immediate, Change debounced 500ms

---

## Success Criteria

### Phase 1
1. Artist can create a new character blueprint with body parts, variants, and animation list in under 2 minutes
2. "New Animation from Blueprint" generates a ready-to-draw file with correct structure in one click
3. Persistent panel updates within 500ms of structural edits showing current validation status
4. On-save validation catches all structural errors (missing layers, frame count mismatches) before the file is saved
5. All data persists in .ase extension properties — no external config files required

### Phase 2
6. Blueprint dashboard shows accurate completeness data across all animations for a character
7. Cross-file validation scan completes in under 10 seconds for a character with 20 animation files

---

## Open Questions (for future consideration)

1. **Batch mode support**: CLI script for headless validation (CI/CD). Low priority but straightforward via `aseprite -b --script validate.lua`.
2. **Multi-character projects**: Project-level dashboard showing all characters. Deferred until single-character workflow is proven.
3. **Version control friendliness**: Binary .ase files don't diff well. Consider optional JSON schema export for reviewability.
4. **Binary .aseprite parser**: Lua-based parser for reading extension properties without opening files. Performance optimization for cross-file scan.
