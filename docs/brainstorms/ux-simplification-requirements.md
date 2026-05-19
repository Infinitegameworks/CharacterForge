# CharacterForge UX Simplification — Requirements

**Status**: Approved (post-review)
**Date**: 2026-05-09
**Scope**: UX improvement pass on existing working plugin — 5 changes (C4 deferred)

## Problem Statement

CharacterForge works but exposes too much complexity to artists. The vocabulary is developer-oriented ("variants", "slots", "schema"), the creation flow demands too many upfront decisions, and the validation panel shows technical status instead of actionable progress. Artists need a tool that guides them through their work, not one that reports on data structures.

## Goals

1. An artist with no technical background can create a blueprint and start drawing in under 60 seconds
2. The panel answers "what should I draw next?" not "what's technically wrong?"
3. The plugin feels like a drawing assistant, not a database manager

## Non-Goals

- Changing the underlying data model (Part/Slot/Variant with IDs stays)
- Removing any existing functionality (advanced users can still access everything)
- Phase 2 features (cross-file scan, dashboard, etc.)
- Auto-registration (C4 — deferred to a separate follow-up, see Deferred section)
- Opening animation files from the blueprint progress view (too expensive for the default panel)

---

## Changes

### C1: Preset Templates for Blueprint Creation

Add a template dropdown to the blueprint creation dialog that pre-fills body parts and animations.

**Presets:**
- **Humanoid** (6 parts): head, torso, left_arm, right_arm, left_leg, right_leg
- **Simple Humanoid** (3 parts): head, torso, legs
- **Upper Body** (3 parts): head, torso, arms

**Behavior:**
- Dialog opens with a template combobox as the first field (default: Humanoid)
- Selecting a template writes the pre-filled values into the body parts entry field
- The body parts entry field is always visible (Aseprite's Dialog API cannot hide/show widgets post-construction) — template selection overwrites its content
- "Custom" option in the template dropdown clears the parts field so the artist can type freely
- Default animations pre-filled: "idle, walk, run" (artist can edit)
- Artist flow: pick template, type character name, optionally tweak parts/outfits/animations, confirm

### C2: Progressive Disclosure — Hide Slots

The "Slots" concept is invisible in the default UI when only the default slot exists.

**Behavior:**
- Blueprint creation dialog: no "Slots" entry field. Default slot is used automatically.
- Blueprint edit dialog: slot section hidden unless the active blueprint has multiple slots (checked via `blueprint.listSlotNames()` returning more than one name)
- Panel: slot filter chips and Solo/Hide Slot buttons hidden when only one slot exists
- When slots are hidden, the default slot is used transparently for all operations
- Slot-related Sprite menu commands (`Solo Slot`, `Hide Slot`) guarded by `onenabled` — disabled when active blueprint has only the default slot

**Trigger for revealing slots:** Any blueprint with `listSlotNames().length > 1` shows all slot UI controls. This is determined by the schema, not by a user toggle.

### C3: "Start Next Animation" Button

One-click creation of the next undrawn animation from the blueprint's animation list.

**Behavior:**
- Button visible on the panel when a blueprint or registered animation is active
- Reads the blueprint's animation list, finds the first animation with `status == "missing"`
- Creates the animation file automatically (same logic as `showNewAnimationDialog` but without showing a dialog — uses blueprint path + animation name directly)
- If the active file is an animation (not a blueprint): reads `blueprint_ref`, opens the blueprint to get the schema and animation list, creates the next missing animation, closes the blueprint
- The new file opens automatically after creation
- Button is always constructed with text "Start Next" — when no missing animations remain, it's disabled via `dlg:modify{ id=x, enabled=false }` (Aseprite supports `enabled` modification but not text modification post-construction)
- If no blueprint is linked, button is disabled

### C5: Artist-Friendly Language

Rename UI-facing labels only. Internal data types and property keys stay unchanged.

**Renames (UI only):**
| Technical term | Artist term | Where |
|---------------|-------------|-------|
| variant (equipment type) | Outfit | Dialog labels, panel text, alerts |
| state variant | Effect | Dialog labels, panel text, alerts |
| "Register Animation" | "Link Animation" | Panel button, Sprite menu command title |
| "cached schema" in messages | "character definition" | Alert text, panel status text |
| "validation" in panel text | "check" or "status" | Panel labels, status messages |
| "Blueprint not found" | "Character file not found" | Panel status text |
| "structural errors" | "missing layers" or "structure issues" | Save-block alert |

Internal code variables, property keys (`type = "variant"`), function names, and the solutions doc keep the technical terms.

### C6: Progress View

Replace the validation-focused panel canvas with a progress-oriented display.

**When viewing a blueprint:**
Show the animation list with coarse per-animation status:
- Format: `idle: complete` / `walk: started` / `run: not created`
- **complete** = animation file exists and last validation result was "pass" or "warn"
- **started** = animation file exists (status is "valid" or "invalid" in registry)
- **not created** = animation file doesn't exist (status is "missing" in registry)
- Data source: `schema.animations[].status` + `app.fs.isFile()` for existence check (no file opens)
- Show count summary: "3/5 animations started, 2 complete"

**When viewing an animation:**
Show the current file's part-level status:
- Format: `head: drawn (8f)` / `torso: empty` / `right_arm: drawn (8f)`
- **drawn (Nf)** = body part has N frames with drawn content in base variant
- **empty** = body part group exists but base variant has no drawn frames
- **missing** = body part group doesn't exist in the layer structure
- Data source: `lastValidation.layer_status` (already computed and cached)

**The current validation grid** (variant cells with B/V/S labels, slot filter chips) moves behind a "Details" button that opens the existing detailed view. Not removed — just not the default.

**Error/warning footer:** "2 issues — tap Details" shown at the bottom when validation has errors or warnings.

---

## Deferred

### C4: Auto-Registration (separate follow-up)

Deferred because it introduces new event logic, directory scanning, and dismissal state — categorically different from the presentation-only changes in this batch. Will be implemented as a focused follow-up after this UX pass ships.

---

## Platform Constraints (from review)

1. **Aseprite Dialog API cannot hide/show widgets post-construction** — all widgets are constructed once at dialog creation. Workaround: always show fields, use `dlg:modify` to change content/enabled state. No dynamic visibility.
2. **Aseprite Dialog API cannot change button text post-construction** — `dlg:modify{ id, text }` does not work for buttons. Workaround: use `dlg:modify{ id, enabled }` to disable buttons; keep static text that works in both states (e.g., "Start Next" works whether or not animations remain).
3. **Opening files in `sitechange` handler causes tab flash** — already handled by re-entrancy guard. C3's "Start Next" from animation view must open the blueprint briefly (acceptable, same pattern as schema refresh).

---

## Success Criteria

1. Artist creates a new humanoid character blueprint in 3 actions: pick template, type name, confirm
2. Slot controls are hidden when the active blueprint has only the default slot
3. Starting the next missing animation is one click from the panel
4. No technical jargon ("variant", "schema", "validation", "register") visible in the default panel or dialog flow
5. Panel shows animation-level progress at a glance without expanding or clicking anything
