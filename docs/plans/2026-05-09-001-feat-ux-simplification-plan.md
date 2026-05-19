---
title: "feat: CharacterForge UX Simplification"
type: feat
status: completed
date: 2026-05-09
origin: docs/brainstorms/ux-simplification-requirements.md
---

# CharacterForge UX Simplification

## Overview

Five presentation-layer changes to make CharacterForge feel like a drawing assistant rather than a database manager. No data model changes — all work is in UI strings, dialog construction, and panel canvas rendering.

## Requirements Trace

- R1. Artist creates blueprint in 3 actions: pick template, type name, confirm (C1)
- R2. Slot controls hidden when only default slot exists (C2)
- R3. One-click "Start Next" for next missing animation (C3)
- R4. No technical jargon in default UI flow (C5)
- R5. Animation-level progress at a glance without expanding (C6)

## Scope Boundaries

- No data model changes — Part/Slot/Variant with IDs stays
- No auto-registration (C4 deferred)
- No file-opening for blueprint progress view (coarse status only)
- Internal code, property keys, and solutions doc keep technical terms

## Key Technical Decisions

- **Template dropdown overwrites parts field**: Templates write into the existing entry field rather than hiding/showing fields (Aseprite Dialog API cannot hide widgets post-construction)
- **Slot visibility is schema-driven, not user-toggled**: `listSlotNames().length > 1` determines whether slot controls appear — no "Advanced" checkbox needed
- **"Start Next" button stays constructed with static text**: Use `dlg:modify{ enabled=false }` when no animations remain — can't change button text post-construction
- **Progress uses coarse status from blueprint registry**: `schema.animations[].status` + `app.fs.isFile()` — no animation file opens from blueprint view

## Implementation Units

- [ ] **Unit 1: Artist-friendly language (C5)**

**Goal:** Replace all technical jargon in user-facing strings.

**Requirements:** R4

**Dependencies:** None — pure string changes, do first so all subsequent work uses new terms.

**Files:**
- Modify: `plugin.lua` (command titles)
- Modify: `panel.lua` (status text, button labels, canvas text)
- Modify: `blueprint.lua` (alert messages, dialog titles/labels)
- Modify: `blueprint_editor.lua` (dialog labels, field labels)

**Approach:**
- Search-and-replace across all user-facing strings per the rename table in requirements
- Command titles: "Register Animation" → "Link Animation", "variant" → "outfit" in labels
- Panel text: "validation" → "check"/"status", "cached schema" → "character definition", "Blueprint not found" → "Character file not found"
- Dialog labels: "Variants:" → "Outfits:", "States:" → "Effects:"
- Do NOT rename internal variables, function names, property keys, or log messages

**Test scenarios:**
- Happy path: Open panel, create blueprint, link animation — no instance of "variant", "schema", "validation", or "register" visible in any dialog or panel text
- Edge case: Error messages from save-blocking still make sense with new terms ("missing layers" not "structural errors")

**Verification:**
- Walk through every dialog and panel state — no technical jargon visible to the artist

---

- [ ] **Unit 2: Preset templates for blueprint creation (C1)**

**Goal:** Add template dropdown to blueprint creation dialog.

**Requirements:** R1

**Dependencies:** Unit 1 (uses new terminology)

**Files:**
- Modify: `blueprint_editor.lua` (`showCreateDialog`)

**Approach:**
- Add a combobox as the first field: options = ["Humanoid (6 parts)", "Simple Humanoid (3 parts)", "Upper Body (3 parts)", "Custom"]
- Define preset data as a local table mapping template name → parts list + default animations
- On dialog construction, pre-fill the parts entry field with the default template (Humanoid)
- `onchange` handler on the combobox: overwrite the parts entry field content via `dlg:modify{ id="bodyParts", text=presetParts }`
- "Custom" clears the parts field so the artist can type freely
- Pre-fill animations entry with "idle, walk, run" for all presets

**Patterns to follow:**
- Existing `dlg:combobox` + `dlg:modify` pattern already used in panel.lua for slot filter

**Test scenarios:**
- Happy path: Select "Humanoid" template → parts field shows "head, torso, left_arm, right_arm, left_leg, right_leg", animations shows "idle, walk, run"
- Happy path: Select "Simple Humanoid" → parts field shows "head, torso, legs"
- Happy path: Select "Custom" → parts field clears, artist can type
- Happy path: Change template after typing custom parts → overwrites with template parts
- Integration: Create blueprint with Humanoid template → resulting .ase has all 6 body part groups

**Verification:**
- Artist picks template, types name, confirms — blueprint created with correct structure in 3 actions

---

- [ ] **Unit 3: Hide slot controls (C2)**

**Goal:** Slot UI invisible when only default slot exists.

**Requirements:** R2

**Dependencies:** Unit 1

**Files:**
- Modify: `panel.lua` (conditionally skip slot chips and slot buttons)
- Modify: `blueprint_editor.lua` (`showCreateDialog` — remove slots field; `showEditDialog` — conditionally show slot section)
- Modify: `plugin.lua` (slot-related command `onenabled` guards)

**Approach:**
- Panel: in `drawSlotChips()`, check `blueprint.listSlotNames(schema)` — if only one name (or empty), skip drawing chips entirely. In dialog construction, skip Solo/Hide Slot buttons if single slot.
- Blueprint creation: remove the "Slots:" entry field entirely (default slot is always created automatically by `normalizeSchema`)
- Blueprint edit: wrap the "Slots" separator + fields in a condition: `if countSlots(schema) > 1 then ... end`
- Plugin commands: `cfSoloSlot`/`cfHideSlot` — add `onenabled` that checks active blueprint/animation has multiple slots
- Panel slot filter combobox: hide by constructing it conditionally or always showing "all" as only option when single slot

**Test scenarios:**
- Happy path: Create blueprint with default template → no "Slot" text appears anywhere in panel or dialogs
- Happy path: Blueprint with multiple slots → slot chips, Solo/Hide buttons, and edit fields all appear
- Edge case: Switch between single-slot and multi-slot sprites — panel updates correctly

**Verification:**
- Default humanoid workflow never shows the word "Slot" or slot-related controls

---

- [ ] **Unit 4: Progress view (C6)**

**Goal:** Panel shows animation-level progress instead of validation grid.

**Requirements:** R5

**Dependencies:** Unit 1, Unit 3

**Files:**
- Modify: `panel.lua` (canvas `onPaint`, `refreshPanel`)

**Approach:**
- Blueprint view: iterate `schema.animations`, show one line per animation:
  - Check file existence via `app.fs.isFile(app.fs.joinPath(blueprintDir, anim.file))`
  - Status label: "complete" (status=="valid"), "started" (file exists, status!="valid"), "not created" (status=="missing" or file doesn't exist)
  - Summary line: "X/Y animations started, Z complete"
- Animation view: iterate `lastValidation.layer_status`, show one line per part:
  - "partName: drawn (Nf)" when base_frames > 0
  - "partName: empty" when base_frames == 0
  - "partName: missing" when part has status "fail" and no layer found
- Move the existing validation grid (variant cells, B/V/S labels) behind a "Details" button that opens a separate dialog or toggles canvas mode
- Keep error/warning footer: "N issues — tap Details"

**Patterns to follow:**
- Existing `drawText`, `drawStatusDot`, `fillRect` helpers in panel.lua
- `utils.statusColor()` for pass/warn/fail coloring

**Test scenarios:**
- Happy path: Open blueprint with 3 animations (1 complete, 1 started, 1 not created) → panel shows progress list with correct labels
- Happy path: Open registered animation with 6 parts (4 drawn, 2 empty) → panel shows part status with frame counts
- Edge case: Blueprint with no animations defined → panel shows "No animations defined yet"
- Edge case: Animation with validation errors → footer shows "N issues — tap Details"
- Integration: "Details" button opens the existing validation grid view

**Verification:**
- Panel shows "what to draw next" at a glance for both blueprint and animation views

---

- [ ] **Unit 5: Start Next Animation button (C3)**

**Goal:** One-click creation of next missing animation.

**Requirements:** R3

**Dependencies:** Unit 4 (progress view shows animation status)

**Files:**
- Modify: `blueprint.lua` (add `createNextAnimation(blueprintPath)` function)
- Modify: `panel.lua` (add button, wire to function)

**Approach:**
- `blueprint.createNextAnimation(bpPath)`:
  - Open blueprint, read schema
  - Find first animation with `status == "missing"`
  - If none found, return nil
  - Create the animation file (reuse logic from `showNewAnimationDialog` — extract the file-creation part into a shared helper)
  - Update blueprint registry, save blueprint, close if we opened it
  - Return the created file path
- Panel: add "Start Next" button in the Create section
  - `onclick`: determine blueprint path (if active is blueprint, use it; if animation, read `blueprint_ref`)
  - Call `createNextAnimation`, refresh panel
  - If nil returned (all done), show alert "All animations have been started"
- Button enabled state: check if blueprint has any `status == "missing"` animations
  - On `refreshPanel`, update via `dlg:modify{ id="btnStartNext", enabled=hasMissing }`

**Patterns to follow:**
- `openSpriteForPath` pattern in blueprint.lua for safe blueprint open/close
- `runAction` wrapper in panel.lua for pcall + refresh

**Test scenarios:**
- Happy path: Blueprint has idle(valid), walk(missing), run(missing) → click "Start Next" → creates walk animation, opens it, panel refreshes
- Happy path: Click again → creates run animation
- Happy path: Click again → "All animations have been started" alert, button disabled
- Edge case: Active file is animation (not blueprint) → reads blueprint_ref, opens blueprint, creates next animation
- Edge case: Blueprint has no animations defined → button disabled
- Error path: Blueprint file not found → alert "Character file not found"

**Verification:**
- Three clicks from blueprint creation to having 3 animation files open and ready to draw

---

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| `dlg:modify` for combobox `onchange` may not fire on initial construction | Pre-fill parts field at construction time, not just on change |
| Slot visibility check on every panel refresh adds overhead | `listSlotNames` is a simple loop over schema — negligible cost |
| "Details" button for validation grid adds a second dialog | Keep it simple — reuse the existing canvas rendering in a new `Dialog{ wait=false }` |

## Sources & References

- **Origin document:** [docs/brainstorms/ux-simplification-requirements.md](docs/brainstorms/ux-simplification-requirements.md)
- Architecture: [docs/solutions/aseprite-extension-development-patterns.md](docs/solutions/aseprite-extension-development-patterns.md)
