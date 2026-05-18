# CharacterForge

Aseprite extension for managing layered character animation pipelines. Define a character's body parts, outfits, and animations in a single blueprint file, then generate animation files with the correct layer structure already in place.

## How It Works

A **blueprint** is an `.ase` file that stores the character definition:

- **Parts** -- body regions (head, torso, arms, legs, hair, etc.)
- **Outfits** -- per-part visual alternatives (armor on torso, ponytail on hair, etc.)
- **Effects** -- conditional overlays that apply to specific animations (damaged, powered-up)
- **Animations** -- the list of animation files the character needs (idle, walk, run, etc.)
- **Directions** (optional) -- facing directions (front, back, 4-dir, 8-dir). Each animation × direction becomes its own file.

Outfits and effects are configured **per-part** -- hair can have unique hairstyle variants while torso has armor variants.

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

- **Step 1**: Pick a template, set character name. Add parts, default outfits, effects, and animations one at a time using type-and-click controls. Optionally enable directions with presets (8-dir, 4-dir, front/back, custom).
- **Step 2** (optional): Per-part customization. Select each part from a dropdown and add/remove outfits and effects specific to that part. "Create With Defaults" skips this step.

When directions are enabled, each animation is expanded into one file per direction (e.g., `character_idle_front.ase`, `character_idle_back.ase`).

### 2. Open the Panel

**Sprite > CharacterForge** opens the floating panel. Buttons adapt to what you're viewing:

**When viewing a blueprint:**
- Animation progress list with collapsible groups
- Directional animations auto-group by base name (click group header to collapse/expand)
- Click any animation row to open an existing file or create a missing one
- Drag animation rows to group headers to reorganize
- Per-animation progress: "5/12 done" with color-coded dots
- Edit Blueprint, New Animation buttons

**When viewing an animation:**
- Variant checklist showing every part and variant with auto-detected done status
- Variants are "done" when their frame count matches the base variant -- no manual marking needed
- Click any variant row to select that layer in the timeline for drawing
- Edit Animation button -- modify the animation's parts/outfits with optional blueprint propagation
- Go to Blueprint, Refresh from Blueprint buttons

**When viewing an unregistered sprite:**
- New Blueprint, Blueprint From Current, Link Animation buttons

### 3. Draw and Track Progress

As you draw each animation:
- The panel automatically detects completion by comparing frame counts to the base variant
- When all non-skipped variants have matching frame counts, the animation shows as complete
- Progress syncs to the blueprint when you switch tabs (no manual action needed)
- Mouse wheel scrolls the panel; scrollbar is draggable

### 4. Edit the Blueprint

**Edit Blueprint** opens a hub with focused action dialogs:

- **Edit Parts** -- add, rename, or remove body parts
- **Edit Outfits / Effects** -- per-part dropdown to add, rename, or remove outfits and effects. Bulk-add applies to all parts at once.
- **Edit Animations** -- add, rename, or remove animations. Assign animations to groups or create new groups.

If the blueprint structure changes and animations already exist, a warning reminds you to refresh them.

### 5. Edit an Animation

**Edit Animation** (visible when viewing an animation) opens a hub to modify the animation's own schema:

- Edit parts and outfits/effects scoped to this animation
- "Apply to blueprint too" checkbox propagates changes to the blueprint file

## Directions

Directions are optional. When enabled in the create wizard, you choose from presets:

| Preset | Directions |
|---|---|
| 8-Direction | front, front_right, right, back_right, back, back_left, left, front_left |
| 4-Direction | front, right, back, left |
| Front / Back | front, back |
| Front Only | front |
| Custom | pick individual directions |

Each animation × direction becomes a separate file. In the blueprint panel, directional animations auto-group under their base name (e.g., "idle" group contains front, back, left, right). Dragging a directional animation warns before breaking it out of its direction group -- "Move All" keeps directions together, "Move This Only" breaks one out.

## Animation Groups

The blueprint progress view supports collapsible groups for organizing animations:

- Directional animations auto-group by base animation name
- Custom groups can be created via Edit Animations > Groups
- Drag animation rows to group headers to reorganize
- Click a group header to collapse/expand
- Group headers show aggregate progress (done/total)

## Blueprint-Animation Coupling

Animations store a reference to their blueprint (filename + absolute path fallback). Path resolution checks the same directory, parent directory, and the stored absolute path.

If the blueprint's structure changes, open each animation and click **Refresh from Blueprint** to update the cached schema.

## Auto-Completion Detection

Variants are automatically "done" when their drawn frame count matches the base variant in the same part/slot. The base variant must have at least one frame. Skipped (intentionally absent) variants are excluded. No manual marking is needed.

## Strict Save

When save mode is "block" (default), CharacterForge prevents saving animation files with structural errors. Toggle via Settings or **CharacterForge: Toggle Strict Save**.

## Variants

### Outfits

Visual alternatives configured per-part. Each part can have its own set. The base variant is always required. Frame counts must match the base.

### Effects

Conditional overlays that only apply to specific animations via an `applies_to` filter.

### Skipped (Intentionally Absent)

Mark a variant as skipped via Settings > Toggle Absent to exclude it from frame-count validation.

## Schema

Character data is stored in Aseprite extension properties under `infinitegameworks/character-forge`. The internal model uses a **Part > Slot > Variant** hierarchy with stable IDs. `normalizeSchema()` in `blueprint.lua` is the central normalization function.

## Files

| File | Purpose |
|---|---|
| `plugin.lua` | Entry point, command registration, save-time validation hooks |
| `blueprint.lua` | Schema CRUD, layer structure, animation creation, completion sync |
| `blueprint_editor.lua` | Two-step create wizard, hub-style edit dialogs, animation editor |
| `validator.lua` | Layer structure and frame-count validation |
| `panel.lua` | Floating panel with context-sensitive controls, scrollable canvas, drag-and-drop |
| `dialog_utils.lua` | Shared dialog helpers: scrollable list canvas, truncated alerts |
| `utils.lua` | Shared color constants |
| `__pref.lua` | Preference initialization |

## License

MIT
