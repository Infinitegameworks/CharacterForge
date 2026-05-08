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

## Common Pitfalls

1. **Flat structure required** — don't use subdirectories for modules
2. **Property assignment syntax** — use `props.field = value`, never `sprite.properties(PK) = {}`
3. **Timer ontick has no args** — reference outer variable, not a callback parameter
4. **No top-level menus** — use hub-panel pattern for universal compatibility
5. **sitechange recursion** — opening a file in a sitechange handler triggers another sitechange. Use a re-entrancy guard flag.
6. **Sprite event leak on tab switch** — unsubscribe from old sprite before subscribing to new one
7. **Save hook covers 3 commands** — SaveFile, SaveFileAs, SaveFileCopyAs. Missing any = validation bypass.
8. **aftercommand for metadata writes** — writing properties in `beforecommand` may not persist in the save (data may already be serialized). Use `aftercommand` instead.
9. **Array tables must be sequential** — `is_array_table()` checks integer keys starting at 1. Never use `table.remove()` then reassign to properties. Rebuild the full table.
10. **`app.apiVersion`** — check at the top of init(). Version 23+ required for extension properties, Timer, events.
