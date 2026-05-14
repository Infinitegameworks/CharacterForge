# CharacterForge

Blueprint-driven layer management for Aseprite. Define a character's body parts, outfit variants, and animations in a single blueprint file, then generate animation files with the correct layer structure already in place.

## How It Works

A **blueprint** is an `.ase` file that defines your character's structure:

- **Parts** -- top-level body regions (head, torso, legs, etc.)
- **Slots** -- equipment positions within a part (default, or named slots like "armor", "accessory")
- **Variants** -- visual options per slot (base, plus any outfits or state effects)
- **Animations** -- the list of animations the character needs (idle, walk, run, etc.)

When you create a new animation from a blueprint, CharacterForge generates an `.ase` file with the full layer group hierarchy pre-built. As you draw, the panel validates your layer structure against the blueprint in real time.

## Requirements

Aseprite v1.3-rc3 or later (API version 23+).

## Install

1. Clone or download this repo
2. Create a junction link (or copy) into your Aseprite extensions directory:

```
# Windows
mklink /J "%APPDATA%\Aseprite\extensions\character-forge" C:\Dev\CharacterForge

# macOS / Linux
ln -s /path/to/CharacterForge ~/Library/Application\ Support/Aseprite/extensions/character-forge
```

3. Restart Aseprite

The extension registers commands under **Sprite > Properties** in the menu bar.

## Usage

### Create a Blueprint

**Sprite > CharacterForge: New Blueprint** opens a dialog with preset templates (Humanoid, Simple Humanoid, Upper Body) or custom configuration. Enter your character name, body parts, outfit variants, state effects, and planned animations.

### Blueprint From Existing Sprite

**Sprite > CharacterForge: Blueprint From Current Sprite** infers a schema from an existing layered sprite. Top-level groups become parts, nested groups become slots and variants.

### Create Animations

**Sprite > CharacterForge: New Animation** generates a new `.ase` file from a blueprint with the correct layer hierarchy. The blueprint tracks which animations exist and which are still missing.

### Link Existing Animations

**Sprite > CharacterForge: Link Animation** registers an existing sprite as an animation for a character. CharacterForge validates the layer structure and caches the schema.

### Panel

**Sprite > CharacterForge** opens a dockable panel that shows:

- **Blueprint view** -- animation progress (started, complete, not created) with a "Start Next" button
- **Animation view** -- per-part validation status with frame counts and variant completeness
- **Slot filter chips** -- click to solo/hide specific equipment slots
- **View controls** -- solo part, solo outfit, show all managed layers

### Strict Save

When save mode is set to "block" (default), CharacterForge prevents saving animation files that have structural errors. Toggle between strict and warn-only mode via the Settings dialog or **Sprite > CharacterForge: Toggle Strict Save**.

## Schema

Character data is stored in Aseprite's extension properties under the namespace `infinitegameworks/character-forge`. Blueprint files have `type: "blueprint"`, animation files have `type: "animation"` with a cached copy of the schema for offline validation.

The schema uses a **Part > Slot > Variant** hierarchy with stable IDs. `normalizeSchema()` in `blueprint.lua` is the central normalization function -- all reads and writes go through it.

### Variant Types

- **variant** -- visual alternatives (outfits, equipment)
- **state** -- conditional effects that only apply to specific animations (via `applies_to` filter)

### Intentionally Absent

Mark a variant layer as intentionally absent to skip frame-count validation for that variant. Useful when a body part doesn't need a particular outfit (e.g., a hat that doesn't apply to the legs).

## Files

| File | Purpose |
|---|---|
| `plugin.lua` | Entry point, command registration, save-time validation hooks |
| `blueprint.lua` | Schema CRUD, layer structure management, blueprint discovery |
| `blueprint_editor.lua` | Create and edit blueprint dialogs |
| `validator.lua` | Layer structure validation against schema |
| `panel.lua` | Dockable panel UI with canvas rendering |
| `utils.lua` | Shared color constants |
| `__pref.lua` | Preference initialization |

## License

MIT
