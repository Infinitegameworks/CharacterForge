# CharacterForge

Aseprite extension for managing layered character animation pipelines. Define a character's body parts, outfits, and animations in a single blueprint file, then generate animation files with the correct layer structure already in place.

## How It Works

A **blueprint** is an `.ase` file that stores the character definition:

- **Parts** -- body regions (head, torso, arms, legs, hair, etc.)
- **Outfits** -- per-part visual alternatives (armor on torso, ponytail on hair, etc.)
- **Effects** -- conditional overlays that apply to specific animations (damaged, powered-up)
- **Animations** -- the list of animation files the character needs (idle, walk, run, etc.)

Outfits and effects are configured **per-part** -- hair can have unique hairstyle variants while torso has armor variants. A bulk-add option applies outfits across all parts when that makes sense.

## Requirements

Aseprite v1.3-rc3 or later (API version 23+).

## Install

1. Clone or download this repo
2. Create a junction link (or copy) into your Aseprite extensions directory:

```powershell
# Windows
mklink /J "%APPDATA%\Aseprite\extensions\character-forge" C:\Dev\CharacterForge
```

```bash
# macOS / Linux
ln -s /path/to/CharacterForge ~/Library/Application\ Support/Aseprite/extensions/character-forge
```

3. Restart Aseprite

Commands register under **Sprite > Properties** in the menu bar.

## Workflow

### 1. Create a Blueprint

**Sprite > CharacterForge: New Blueprint** opens a two-step setup:

- **Step 1**: Pick a template (Humanoid, Simple Humanoid, Upper Body, or Custom). Set character name, parts, default outfits/effects, and planned animations.
- **Step 2** (optional): Per-part customization. Select each part from a dropdown and add/remove outfits and effects specific to that part. "Create With Defaults" skips this step.

### 2. Open the Panel

**Sprite > CharacterForge** opens the floating panel. The panel adapts to what you're viewing:

**When viewing a blueprint:**
- Animation progress list -- click any row to open an existing animation or create a missing one
- Edit Blueprint button -- opens the hub editor
- New Animation button -- manual creation dialog

**When viewing an animation:**
- Variant checklist -- shows every part and variant with done/not-done status
- Click any variant row to toggle it as done
- Progress counter (e.g., "5/12 variants done")
- Go to Blueprint button -- opens the linked blueprint
- Refresh from Blueprint button -- re-caches the schema if the blueprint changed

**When viewing an unregistered sprite:**
- New Blueprint, Blueprint From Current, Link Animation buttons

### 3. Draw and Track Progress

As you draw each animation:
- The panel shows per-part variant status with frame counts
- Click variants to mark them done when you're satisfied with the art
- When all non-skipped variants are done, the blueprint shows the animation as "complete"
- Mouse wheel scrolls the panel when content overflows; scrollbar is draggable

### 4. Edit the Blueprint

**Edit Blueprint** opens a hub with focused action dialogs:

- **Edit Parts** -- add/remove body parts, see current part summary
- **Edit Outfits / Effects** -- select a part from a dropdown, add/remove outfits and effects for that specific part. Bulk-add option applies to all parts at once.
- **Edit Animations** -- add/remove planned animations

If the blueprint structure changes and animations already exist, a warning reminds you to refresh them.

## Blueprint-Animation Coupling

Animations store a reference to their blueprint (filename + absolute path fallback). The cached schema lets animations validate and display their checklist even when the blueprint isn't open.

If the blueprint is renamed or moved, the fallback path resolves the link. Use **Link Animation** to re-establish a broken connection.

If the blueprint's structure changes (parts or outfits added/removed), open each animation and click **Refresh from Blueprint** to update the cached schema.

## Strict Save

When save mode is "block" (default), CharacterForge prevents saving animation files that have structural errors (missing layers, frame count mismatches). Toggle between strict and warn-only mode via Settings or **CharacterForge: Toggle Strict Save**.

## Variants

### Outfits

Visual alternatives configured per-part. Each part can have its own set -- hair might have ponytail/short/braids while torso has armor/casual. The base variant is always required. Frame counts must match the base.

### Effects

Conditional overlays that only apply to specific animations via an `applies_to` filter. For example, a "damaged" effect that only appears in hit/death animations.

### Skipped (Intentionally Absent)

Mark a variant as skipped via Settings > Toggle Absent. Skipped variants are excluded from frame-count validation. Useful when a variant doesn't apply to a specific part (e.g., helmet outfit doesn't need leg art).

## Schema

Character data is stored in Aseprite extension properties under `infinitegameworks/character-forge`. The internal model uses a **Part > Slot > Variant** hierarchy with stable IDs. `normalizeSchema()` in `blueprint.lua` is the central normalization function.

## Files

| File | Purpose |
|---|---|
| `plugin.lua` | Entry point, command registration, save-time validation hooks |
| `blueprint.lua` | Schema CRUD, layer structure, animation creation, completion sync |
| `blueprint_editor.lua` | Two-step create dialog, hub-style edit dialog |
| `validator.lua` | Layer structure and frame-count validation |
| `panel.lua` | Floating panel with context-sensitive controls and scrollable canvas |
| `utils.lua` | Shared color constants |
| `__pref.lua` | Preference initialization |

## License

MIT
