# CharacterForge — Project Backlog

**Project**: CharacterForge (Aseprite character pipeline plugin)
**Repo**: `C:\Dev\CharacterForge`
**Requirements**: `docs/brainstorms/aseprite-character-pipeline-plugin-requirements.md`

---

## Phase 1 — Core Validation Loop (MVP)

### TASK-1: Project scaffolding and extension manifest
- **Status**: To Do
- **Priority**: P0
- **Description**: Create the Aseprite extension structure: `package.json`, `plugin.lua` (init/exit), module stubs, property key constant. Verify the extension loads in Aseprite without errors.
- **Acceptance**: Extension appears in Edit > Preferences > Extensions. `init()` runs without error. Menu commands are registered (even if stubbed).

### TASK-2: Blueprint data model and property helpers
- **Status**: To Do
- **Priority**: P0
- **Description**: Implement property read/write helpers for the blueprint schema. Functions: `readBlueprintSchema(sprite)`, `writeBlueprintSchema(sprite, schema)`, `isBlueprint(sprite)`. Ensure clean sequential table construction for all arrays. Include `schema_version` field with inline migration stub.
- **Acceptance**: Can programmatically write and read back a full blueprint schema from a sprite's extension properties. Round-trip test passes.

### TASK-3: Create Blueprint dialog (F1.1)
- **Status**: To Do
- **Priority**: P0
- **Description**: Implement the "Create Character Blueprint" menu command and dialog. Fields: character name, body part list (add/remove), variant list (name + type), animation list (names). On confirm: create new .ase file with layer group structure matching the schema, write blueprint properties.
- **Acceptance**: Artist can create a blueprint via CharacterForge > Create Blueprint. Generated .ase has correct layer groups and extension properties. Re-opening and reading properties returns the same schema.

### TASK-4: New Animation from Blueprint (F2.1)
- **Status**: To Do
- **Priority**: P0
- **Description**: Implement "New Animation from Blueprint" menu command. Dialog: select blueprint file (file picker filtered to .ase in character directories), enter animation name. Generate new .ase with: all body part groups, all variant sub-groups, 1 frame, extension properties (blueprint_ref, cached_schema, character_name, animation_name). Place in same directory as blueprint. Update blueprint's animation registry.
- **Acceptance**: One-click generation of a correctly structured animation file. Properties include cached schema. Blueprint's animations list updated.

### TASK-5: Register Existing Animation (F2.2)
- **Status**: To Do
- **Priority**: P1
- **Description**: Menu command to link an already-open .ase file to a blueprint. Opens file picker for blueprint selection. Validates current file's layer structure against blueprint schema. On match (or with warnings): writes blueprint_ref + cached_schema to the file's extension properties. Updates blueprint's animation registry.
- **Acceptance**: Existing .ase file gets linked to a blueprint. Validation results shown. Properties written correctly.

### TASK-6: Validator core — layer structure checks (F3.1, F3.2, F3.4)
- **Status**: To Do
- **Priority**: P0
- **Description**: Implement `validator.lua` with functions:
  - `validateRequiredLayers(sprite, schema)` → checks all body part groups exist (hard error if missing)
  - `validateRequiredVariants(sprite, schema)` → checks base variant exists per part (hard error), equipment variants (warning)
  - `validateFrameCounts(sprite, schema)` → checks all variant sub-groups match base frame count (hard error)
  - Returns structured result: `{ pass/warn/fail, errors=[], warnings=[] }`
- **Acceptance**: Validator correctly identifies missing layers, missing base variants, and frame count mismatches against a cached schema.

### TASK-7: Naming validation (F4.1)
- **Status**: To Do
- **Priority**: P1
- **Description**: Extend validator with `validateNames(sprite, schema)`. Checks layer group names against blueprint-defined names (case-sensitive exact match). Clear error messages: "Expected `right_leg`, found `Right_Leg`".
- **Acceptance**: Name mismatches detected with clear, actionable error messages.

### TASK-8: On-Save validation hook (F7.2)
- **Status**: To Do
- **Priority**: P0
- **Description**: Wire `beforecommand` handler for `SaveFile`, `SaveFileAs`, `SaveFileCopyAs`. On trigger: if file has `type = "animation"` properties, run validator. If hard errors (missing required layers, missing base, frame count mismatch): call `ev.stopPropagation()` to block save, show error dialog listing all hard errors. Soft warnings shown in alert but don't block.
- **Acceptance**: Saving a file with missing required layers is blocked with a clear error dialog. Saving a file with only warnings proceeds.

### TASK-9: Persistent status panel — canvas widget (F7.1)
- **Status**: To Do
- **Priority**: P1
- **Description**: Implement `ui/panel.lua` as a persistent dialog with a canvas widget. Shows: body part names with green/yellow/red indicators, frame count status, blueprint link status. Wire to `LayerName` event (immediate) and `Change` event (500ms debounce via Timer). Detect structural changes by comparing layer tree snapshot. Show "Blueprint not found" + Re-link action when blueprint_ref is unreachable.
- **Acceptance**: Panel opens, shows validation state, updates within 500ms of layer structure changes, debounces paint-stroke noise.

### TASK-10: Schema cache refresh on file open
- **Status**: To Do
- **Priority**: P1
- **Description**: When an animation file is opened (detected via `sitechange` event + checking if active sprite changed): if blueprint_ref resolves to an existing file, open it, compare schema against cached_schema. If different: show notification "Blueprint updated — N new requirements detected", offer to update cache. If blueprint unreachable: show degraded-mode indicator.
- **Acceptance**: Opening an animation file with a stale cache triggers a refresh notification. Blueprint unreachable shows degraded mode.

---

## Phase 2 — Project Visibility

### TASK-11: Cross-file scan with progress dialog (F5.2)
- **Status**: To Do
- **Priority**: P1
- **Description**: Implement batch scan: iterate all .ase files in the character directory (using `app.fs.listFiles`), open each, read extension properties, validate against blueprint schema, close. Show progress dialog ("Scanning X/Y files..."). Collect results into a report data structure.
- **Acceptance**: Scan completes for 20 files in under 10 seconds. Results include per-file validation status.

### TASK-12: Blueprint Dashboard dialog (F1.3)
- **Status**: To Do
- **Priority**: P1
- **Description**: Dialog showing character status. Use standard Dialog widgets (labels, combobox for animation selection, buttons for actions). Canvas widget for the completion status grid (body parts x variants, color-coded). Actions: "Create Missing Animation", "Open Animation", "Validate All" (triggers F5.2).
- **Acceptance**: Dashboard shows accurate completion data. Actions work correctly.

### TASK-13: Unexpected layer detection (F3.3)
- **Status**: To Do
- **Priority**: P2
- **Description**: Extend validator: `validateUnexpectedLayers(sprite, schema)`. Flags layer groups that exist in the file but aren't in the blueprint's body_parts or variants lists. Returns as warnings.
- **Acceptance**: Extra layers flagged without blocking save.

### TASK-14: Animation registry management (F6.1)
- **Status**: To Do
- **Priority**: P1
- **Description**: Blueprint properties maintain an `animations` array with: name, relative file path, status (valid/invalid/missing). Updated by: F2.1 (new animation), F2.2 (register), F5.2 (scan). Add helper functions for registry CRUD.
- **Acceptance**: Registry accurately reflects file existence and validation state after scan.

### TASK-15: Progress reporting (F6.3)
- **Status**: To Do
- **Priority**: P2
- **Description**: Compute progress from scan results + per-file layer_status. Output: "Hero: 7/12 animations complete, 68% variant coverage". Show in dashboard and as text in validation report.
- **Acceptance**: Progress percentages are accurate and update after scan.

### TASK-16: Validation Report dialog (F7.3)
- **Status**: To Do
- **Priority**: P2
- **Description**: On-demand dialog showing all issues across all animation files. Launched from dashboard "Validate All" result or directly via menu. Lists per-file: errors, warnings, variant completion gaps.
- **Acceptance**: Report shows complete picture of all validation issues for a character.

### TASK-17: Lazy blueprint change propagation (AD2)
- **Status**: To Do
- **Priority**: P1
- **Description**: When a blueprint's schema is edited (body parts added/removed, variants changed): the blueprint file is saved normally. Animation files detect the change on next open (TASK-10 cache refresh handles this). Add UI notification: "Blueprint schema changed since this file's cache was last updated. Accept new requirements?"
- **Acceptance**: Editing a blueprint doesn't touch animation files. Animation files detect and surface changes on open.

---

## Future / Deferred

### TASK-18: CLI batch validation script
- **Status**: Deferred
- **Priority**: P3
- **Description**: Standalone `validate.lua` script runnable via `aseprite -b --script validate.lua -script-param dir=sprites/hero/`. Outputs validation report to stdout or JSON file. For CI/CD integration.

### TASK-19: Binary .aseprite parser for headless property reading
- **Status**: Deferred
- **Priority**: P3
- **Description**: Implement minimal .aseprite binary format parser in Lua (read USER_DATA / PROPERTIES chunks) to read extension properties without `app.open()`. Eliminates tab flashing and UI blocking during cross-file scan.

### TASK-20: Blueprint inheritance / shared templates
- **Status**: Deferred
- **Priority**: P3
- **Description**: Allow blueprints to inherit from a "base blueprint" (e.g., all humanoids share the same body_parts). Child blueprints can add/override variants and animations. Reduces duplication across similar characters.

### TASK-21: Multi-character project dashboard
- **Status**: Deferred
- **Priority**: P3
- **Description**: Project-level view scanning multiple character directories. Shows all characters with progress bars. Requires defining a "project root" path.

### TASK-22: UE5 integration brainstorm
- **Status**: Deferred
- **Priority**: P2
- **Description**: Separate brainstorm session for the UE5 side: extending Paper2DPlus's .ase importer to parse CharacterForge extension properties, designing the new character asset that consumes this data, and defining the import workflow.
