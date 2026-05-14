# Aseprite Extension Development Patterns

## Extension Registration & Loading

- Extensions live in `%APPDATA%\Aseprite\extensions\<name>/`
- For development, use a **junction link**: `New-Item -ItemType Junction -Path "$env:APPDATA\Aseprite\extensions\character-forge" -Target "C:\Dev\CharacterForge"`
- Aseprite reads `package.json` from the directory — no need to ZIP into `.aseprite-extension` during dev
- Extension appears in Edit > Preferences > Extensions when `package.json` is valid
- Restart Aseprite after every code change (no hot-reload)

## Module Loading

- **`require` works** for modules in the same directory as `plugin.lua` (flat structure)
- `require 'modulename'` (no `.lua` suffix, no path separators)
- Subdirectories (`require 'ui.panel'`) do NOT work reliably — **flatten all modules into the root directory**
- `dofile()` with explicit paths is an alternative but `require` is simpler for flat layouts
- Modules must `return` a table — standard Lua module pattern
- `require` caches modules (loaded once) — safe for multiple requires of the same module

## Property Assignment Syntax

**CRITICAL**: You CANNOT assign to `sprite.properties(PK)` as a whole:
```lua
-- WRONG — syntax error: "near '='"
sprite.properties(PK) = { key = "value" }

-- CORRECT — set individual fields
local props = sprite.properties(PK)
props.schema_version = 1
props.type = "blueprint"
props.body_parts = { ... }
```

This is the single most common error when starting Aseprite extension development.

## Menu System

- Extensions **cannot create top-level menu bar entries** — the menu bar structure is defined in `gui.xml` (compiled into Aseprite)
- `plugin:newMenuGroup{ id, title, group }` creates a submenu WITHIN an existing group
- `plugin:newCommand{ id, title, group, onclick, onenabled }` adds a command to a group
- Valid built-in groups: `"sprite_properties"`, `"file_scripts"`, `"help_about"`, etc.
- Group IDs come from `group="..."` attributes on items/separators in `gui.xml`
- For a custom top-level menu: modify `data/gui.xml` in Aseprite source to add a `<separator group="your_group" />` inside `<menu id="main_menu">`. This only works for source builds.
- **Universal approach for store-bought Aseprite**: Put one command in `"sprite_properties"` that opens a floating panel (hub pattern). All actions live as buttons inside the panel.

## Timer API

- `Timer{ interval=seconds, ontick=function() ... end }` creates a timer
- `timer:start()` begins firing, `timer:stop()` pauses it
- **The `ontick` callback receives NO arguments** — reference the timer variable from the outer scope:
```lua
-- WRONG — timer param is nil
debounceTimer = Timer{ interval=0.5, ontick=function(timer) timer:stop() end }

-- CORRECT — reference outer variable
debounceTimer = Timer{ interval=0.5, ontick=function() debounceTimer:stop() end }
```

## Dialog (Non-Modal Panel Pattern)

- `dlg:show{ wait=false }` creates a floating non-modal dialog (stays open while artist works)
- `dlg:canvas{ width, height, onpaint }` for custom rendering
- `dlg:button{ text, onclick }` for action buttons
- `dlg:repaint()` forces canvas redraw
- `dlg.onclose` callback fires when user closes the dialog — clean up event handlers here
- Dialogs cannot be docked into Aseprite's panels/toolbars (floating only)

## Event System

- **App-level**: `app.events:on("eventname", handler)` — fires globally
- **Sprite-level**: `sprite.events:on("eventname", handler)` — fires for that sprite only
- Sprite event handlers are per-sprite — when switching tabs, **unsubscribe from old sprite, subscribe to new**
- `"sitechange"` fires when active sprite/layer/frame changes (app-level)
- `"change"` fires on ANY sprite modification including paint strokes (sprite-level)
- `"layername"` fires on layer rename (sprite-level)
- `"beforecommand"` / `"aftercommand"` intercept any Aseprite command (app-level)
  - `ev.name` = command name (e.g., "SaveFile", "SaveFileAs", "SaveFileCopyAs")
  - `ev.stopPropagation()` blocks the command

## Debugging

- **Log to file**: `io.open(app.fs.joinPath(app.fs.tempPath, "myextension.log"), "w")` — viewable at `%TEMP%\myextension.log`
- **Wrap everything in pcall**: Errors in callbacks (onpaint, ontick, event handlers) show in Aseprite's console but don't appear in custom log files unless wrapped
- **Aseprite console**: Shows Lua runtime errors but is only visible in the UI (not readable from filesystem)
- `pcall(require, 'modulename')` catches load errors and lets the extension continue partially
- Always log module load status on startup to diagnose missing/broken modules

## Schema Architecture (v2)

CharacterForge uses a normalized schema model with stable IDs for rename-safe references.

### Hierarchy: Part → Slot → Variant
- **Parts** are top-level body groups (head, torso, left_arm...)
- **Slots** are equipment positions within a part (default, armor_slot, accessory...)
- **Variants** are visual alternatives within a slot (base, armor, damaged...)
- Each level has a stable `id` (e.g., `part_head`, `slot_default`, `variant_base`) and a display `name`

### ID-Based Layer Identity
Every managed layer gets extension properties marking its role:
```lua
blueprint.setLayerIdentity(layer, "part", "part_head")
blueprint.setLayerIdentity(layer, "slot", "slot_default")
blueprint.setLayerIdentity(layer, "variant", "variant_base")
```
Lookup: `blueprint.findLayerByIdOrName(layers, kind, id, name)` — tries ID first, falls back to name.

### normalizeSchema()
Central function that takes any schema (v1 flat variants, v2 with slots, partial data) and produces a fully normalized structure with IDs, default slots, and base variant guaranteed. Always call this before reading or comparing schemas.

### cleanArray()
Helper that rebuilds any array into a clean sequential table — required before writing to extension properties (AD6 compliance).

### Default Slot Collapsing
When a part has only one slot called "default", variants can live directly under the part layer (no intermediate slot group). `getSlotContainer()` and `findVariantLayer()` handle this transparently.

## Plugin Preferences (plugin.preferences)

- `plugin.preferences` is a Lua table auto-saved/restored across sessions
- Pass it to modules via `blueprint.setPreferences(plugin.preferences)` in `init()`
- Used for: `recent_blueprints` (MRU list), `project_roots` (search dirs), `save_mode` ("block"/"warn")
- MRU list capped at 12 entries, most recent first

## Blueprint Discovery

`blueprint.findBlueprints()` searches for blueprint files:
1. Recent blueprints from `plugin.preferences` (instant, no file scan)
2. Current sprite's directory + parent directory
3. Configured project root directories
4. Only opens files with "blueprint" in the filename (optimization)
5. Checks if already-active sprite matches path to avoid redundant open/close

Dialog pattern: `blueprintDialog(title)` returns a dialog with both a combobox of known blueprints AND a file picker fallback. `selectedBlueprintPath(dlg, byLabel)` resolves which one the user chose.

## Layer Structure Repair

`blueprint.ensureLayerStructure(sprite, schema, options)`:
- Creates missing part/slot/variant groups
- Optionally renames layers to match schema (`options.rename = true`)
- Sets layer identity properties on all managed groups
- Returns `{ created = N, renamed = N }` count

`blueprint.syncVariantFrames(sprite, schema)`:
- For each variant, creates empty cels to match base variant frame count
- Uses `firstImageLayer()` to find or create a drawable layer inside variant groups

## Intentionally Absent Variants

A variant layer can be marked `intentionally_absent = true` via `blueprint.toggleActiveVariantAbsent()`. This tells the validator to skip frame-count checks for that variant — useful when a variant doesn't apply to a specific animation but the slot structure requires it to exist.

## Visibility Controls

Layer visibility helpers for artist workflow:
- `soloActivePart(sprite)` — shows only the selected body part
- `soloActiveVariant(sprite)` — shows only the selected variant across all parts
- `showAllManagedLayers(sprite)` — reveals everything
- `setSlotVisibility(sprite, schema, slotName, mode)` — solo/show/hide a specific slot

## Canvas-Based Panel with Interactive Chips

The status panel uses both native dialog widgets AND a canvas for the validation preview:
- Canvas draws slot filter "chips" (clickable via `onmousedown` hit testing)
- `slotChipRects` tracks chip bounds for click detection
- `drawBlueprintPreview()` for blueprint files, `drawValidationPreview()` for animation files
- Variant cells show `[B]`ase/`[V]`ariant/`[S]`tate labels with status colors

## Blueprint Editor (Comma-Separated Input)

The create/edit dialogs use comma-separated text entry instead of add/remove buttons:
- `parseList(text)` splits comma/newline/semicolon-separated input, deduplicates
- One entry field per concept (parts, slots, variants, states, animations)
- Edit dialog is non-modal, commits changes immediately via `app.transaction()`
- Slot templates are derived from existing schema when adding new parts

## Create Blueprint From Current Sprite

`blueprint.schemaFromSprite(sprite, name)`:
- Reads existing layer hierarchy and infers schema
- Top-level groups → parts
- If a group's children have nested groups → slots detected
- Otherwise → single "default" slot with child groups as variants
- Sets identity properties on all discovered layers

## Common Pitfalls

1. **Flat structure required** — don't use subdirectories for modules
2. **Property assignment syntax** — use `props.field = value`, never `sprite.properties(PK) = {}`
3. **Timer ontick has no args** — reference outer variable, not a callback parameter
4. **No top-level menus** — use hub-panel pattern for universal compatibility
5. **sitechange recursion** — opening a file in a sitechange handler triggers another sitechange. Use a re-entrancy guard flag.
6. **Sprite event leak on tab switch** — unsubscribe from old sprite before subscribing to new one
7. **Save hook covers 3 commands** — SaveFile, SaveFileAs, SaveFileCopyAs. Missing any = validation bypass.
8. **aftercommand for metadata writes** — writing properties in `beforecommand` may not persist in the save (data may already be serialized). Use `aftercommand` instead.
9. **Array tables must be sequential** — `is_array_table()` checks integer keys starting at 1. Never use `table.remove()` then reassign to properties. Rebuild the full table via `cleanArray()`.
10. **`app.apiVersion`** — check at the top of init(). Version 23+ required for extension properties, Timer, events.
11. **Always call normalizeSchema()** before reading, comparing, or writing schemas. Raw properties may have missing IDs, old-format variants, or no default slot.
12. **Don't delete Layer 1** — rename to "Reference" instead. Deleting all image layers causes the palette panel to go black.
13. **openSpriteForPath()** — check if the sprite is already the active sprite before calling `app.open()`. Avoids tab flashing and unnecessary file I/O.
14. **Wrap schema comparison in signatures** — `schemaSignature()` produces a deterministic string for comparison. Don't compare raw tables.
15. **sprite:save() and sprite:close() don't exist on references** — Use `app.command.SaveFile()` / `app.command.CloseFile()` instead. Created `safeCloseSprite()` helper. See `aseprite-sprite-reference-and-file-operation-pitfalls.md` for details.
16. **Sprite() invalidates old sprite references** — Capture width/height/colorMode/palette into locals and finish all old-sprite work (save, close) BEFORE calling `Sprite()`.
17. **app.open() + CloseFile() hijacks active tab** — After CloseFile(), Aseprite picks an arbitrary next tab, not the previously-active one. No tab-restore API exists. Avoid the open-read-close pattern entirely.
18. **sitechange guard must cover the entire operation** — Keep `isRefreshingCache = true` through the full open-read-close cycle, not just around `app.open()`. CloseFile() and Sprite() also trigger sitechange synchronously.
19. **Never open files for background reading** — The "open, check schema freshness, close" pattern causes tab flashing, wrong-tab navigation, and re-entrancy. Cache cross-file data at write time instead.
