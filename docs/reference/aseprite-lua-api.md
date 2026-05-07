# Aseprite Lua Scripting API Reference

## 1. File / Sprite Access

**Opening files**: `app.open(filename)` loads `.ase`/`.aseprite` and returns a `Sprite` (or `nil`).
- In GUI mode: creates a visible tab (no "hidden" open mode)
- In `--batch` mode (`aseprite -b --script myscript.lua`): no UI, ideal for data processing

**Directory scanning**: `app.fs.listFiles(path)` returns table of filenames.

```lua
local dir = "C:\\sprites"
for _, filename in ipairs(app.fs.listFiles(dir)) do
  if app.fs.fileExtension(filename) == "aseprite" then
    local sprite = app.open(app.fs.joinPath(dir, filename))
    if sprite then
      -- inspect structure
      sprite:close()
    end
  end
end
```

**Sprite properties**:
- `sprite.filename`, `sprite.width`, `sprite.height`
- `sprite.colorMode` (RGB, Grayscale, Indexed)
- `sprite.frames` (array of Frame objects), `#sprite.frames` for count
- `sprite.layers` (top-level layers only — recurse for groups)
- `sprite.tags`, `sprite.slices`, `sprite.tilesets`
- `sprite.properties` (structured custom data)
- `sprite.data` (string user data)

## 2. Layer API

| Property | Type | R/W | Notes |
|----------|------|-----|-------|
| `name` | string | R/W | |
| `opacity` | 0-255 | R/W | nil for groups |
| `blendMode` | BlendMode | R/W | nil for groups |
| `isGroup` | boolean | R | |
| `isVisible` | boolean | R | |
| `isEditable` | boolean | R | locked state |
| `isImage` | boolean | R | contains cels |
| `isTilemap` | boolean | R | |
| `isBackground` | boolean | R | |
| `isCollapsed`/`isExpanded` | boolean | R | group expand state |
| `layers` | table | R | children (groups only) |
| `parent` | Sprite/Layer | R/W | hierarchy navigation |
| `stackIndex` | int | R/W | reorder within parent |
| `color` | Color | R/W | timeline display color |
| `data` | string | R/W | user-defined text |
| `properties` | Properties | R/W | structured custom data |
| `cels` | table | R | all cels on this layer |
| `uuid` | UUID | R | unique identifier |
| `tileset` | Tileset | R/W | tilemaps only |

**Hierarchy traversal**: `layer.layers` for group children, `layer.parent` for upward traversal.

**Creating layers**:
```lua
sprite:newLayer()             -- image layer
sprite:newGroup()             -- group layer
sprite:newLayer{ name="Arm", parent=bodyGroup }
```

## 3. Tag API

| Property | Type | R/W | Notes |
|----------|------|-----|-------|
| `name` | string | R/W | |
| `fromFrame` | Frame | R | |
| `toFrame` | Frame | R | |
| `frames` | number | R | computed frame count |
| `aniDir` | AniDir | R/W | FORWARD, REVERSE, PING_PONG, PING_PONG_REVERSE |
| `color` | Color | R/W | timeline color |
| `repeats` | number | R/W | 0=infinite |
| `data` | string | R/W | free-form text |
| `properties` | Properties | R/W | structured extension data |
| `sprite` | Sprite | R | parent reference |

## 4. Custom Data / Properties System

Two tiers on Sprites, Layers, Cels, Tags, Slices, Tilesets, Tiles:

**`data` (string)**: Simple free-form text. Read/write.

**`properties` (structured)**: Full structured storage supporting:
- Integers, floats, strings, booleans
- Vectors (arrays): `{1, 2, 3}`
- Maps (tables): `{x=1, y=2, name="foo"}`
- Nested up to 128 levels deep

**User properties**:
```lua
layer.properties.hitboxType = "damage"
layer.properties.hitboxRect = {x=0, y=0, w=16, h=16}
```

**Extension-namespaced properties** (persist in .aseprite file):
```lua
local key = "mypublisher/my-extension"
sprite.properties(key).projectVersion = "1.0"
sprite.properties(key).metadata = { exported=true, lastSync=12345 }
```

Properties integrate with undo/redo automatically. Data persists in the file format.

## 5. File I/O

**JSON** (built-in since v1.3-rc5):
```lua
local data = json.decode(text)
local text = json.encode(table)
```

**Standard Lua `io` library**:
```lua
local f = io.open("C:\\config\\project.json", "r")
local content = f:read("*a")
f:close()
```

**Filesystem utilities (`app.fs`)**:
- `listFiles(path)` — directory listing
- `isFile(fn)`, `isDirectory(fn)` — existence checks
- `fileSize(fn)` — byte size
- `makeDirectory(path)`, `makeAllDirectories(path)` — create dirs
- `removeDirectory(path)` — remove empty dir (no file deletion!)
- `joinPath(...)`, `normalizePath()`, `filePath()`, `fileName()`, `fileExtension()`, `fileTitle()`
- Special: `app.fs.userDocsPath`, `app.fs.userConfigPath`, `app.fs.tempPath`, `app.fs.appPath`

**LIMITATION**: No `os.remove()` or `app.fs.deleteFile()`. Cannot delete files.

## 6. Events / Hooks

**App-level events** (`app.events:on`):
| Event | Fires When |
|-------|-----------|
| `'sitechange'` | User switches sprite/layer/frame |
| `'beforesitechange'` | Before switching |
| `'fgcolorchange'` | Foreground color changes |
| `'bgcolorchange'` | Background color changes |
| `'beforecommand'` | Before any command (ev.name, ev.params, ev.stopPropagation()) |
| `'aftercommand'` | After any command (ev.name, ev.params) |

**Sprite-level events** (`sprite.events:on`):
| Event | Fires When |
|-------|-----------|
| `'change'` | Sprite modified (ev.fromUndo boolean) |
| `'filenamechange'` | Filename changed |
| `'layerblendmode'` | Layer blend mode changed |
| `'layername'` | Layer renamed |
| `'layeropacity'` | Layer opacity changed |
| `'layervisibility'` | Layer visibility toggled |

**No native on-save/on-open/on-export events**. Workaround via `beforecommand`:
```lua
app.events:on('beforecommand', function(ev)
  if ev.name == "SaveFile" then
    -- pre-save validation
  end
end)
```

## 7. Dialog UI Widgets

**Available widgets**: `entry` (text), `number`, `label`, `button`, `check`, `radio`, `combobox` (dropdown), `slider`, `color`, `shades`, `file` (browser), `separator`, `newrow`, `tab`/`endtabs`, `canvas`

**Canvas widget** (power tool for custom UI):
- `onpaint` — GraphicsContext with fillRect, strokeRect, fillText, measureText, drawImage, beginPath/lineTo/cubicTo/stroke/fill, clip, save/restore, drawThemeRect/drawThemeImage
- Mouse events: `onmousemove`, `onmousedown`, `onmouseup`, `ondblclick`, `onwheel`
- Keyboard: `onkeydown`, `onkeyup`

**Dialog features**: Resizable (v1.3.15+), `dialog:modify{}` for live updates, `dialog:repaint()`, `dialog.data` for values, `dialog.bounds`, `onclose` callback.

**NOT available natively**: listbox, tree view, table/grid, scrollable list, progress bar, rich text. Must be hand-built with Canvas.

## 8. Cross-File Operations

Fully feasible. In GUI mode each `app.open()` flashes a tab before `close()`. In `--batch` mode, no UI.

Pattern for project scanning:
```lua
local results = {}
for _, file in ipairs(app.fs.listFiles(dir)) do
  if app.fs.fileExtension(file) == "aseprite" then
    local path = app.fs.joinPath(dir, file)
    local sprite = app.open(path)
    if sprite then
      table.insert(results, {
        name = file,
        layers = #sprite.layers,
        tags = #sprite.tags,
        frames = #sprite.frames,
      })
      sprite:close()
    end
  end
end
```

## 9. Extension Packaging

**package.json manifest**:
```json
{
  "name": "my-extension",
  "displayName": "My Extension",
  "description": "Description",
  "version": "1.0",
  "author": { "name": "Dev", "email": "dev@example.com" },
  "publisher": "mypublisher",
  "license": "MIT",
  "categories": ["Scripts"],
  "contributes": {
    "scripts": [{ "path": "./plugin.lua" }],
    "keys": [{ "id": "MyExtension", "path": "./default.aseprite-keys" }]
  }
}
```

**Plugin lifecycle**:
- `init(plugin)` — on Aseprite startup / extension load
- `exit(plugin)` — on Aseprite shutdown / extension unload

**Plugin object**:
- `plugin.preferences` — auto-saved/restored Lua table (persistent state)
- `plugin.name`, `plugin.displayName`, `plugin.version`, `plugin.path`

**Menu registration**:
```lua
plugin:newCommand{
  id="myCommand",
  title="My Command",
  group="sprite_properties",
  onclick=function() --[[ handler ]] end,
  onenabled=function() return app.activeSprite ~= nil end
}
plugin:newMenuGroup{ id="myMenu", title="My Menu", group="sprite_properties" }
plugin:newMenuSeparator{ group="myMenu" }
```

**Code sharing**: Use `dofile()` (not `require`) with paths relative to script. Functions must NOT be `local` to be cross-file accessible. Actually `require` works within extensions for modules that return tables.

**Distribution**: ZIP folder → rename to `.aseprite-extension`. Install via Edit > Preferences > Extensions > Add.

## 10. Limitations

**Hard limits**:
- No `os.remove()` / file deletion
- No native listbox, tree, table, progress bar widgets
- No "hidden" sprite open in GUI mode (tabs flash)
- No on-save/on-open/on-export lifecycle events (use beforecommand workaround)
- No frame-level userData/properties
- `sprite.layers` returns only first-level (must recurse for groups)
- `dofile()` breaks with non-ASCII Windows paths
- All Lua runs on main thread — blocks UI during execution
- No async/threading
- Properties nesting limited to 128 levels

**Workarounds**:
- WebSocket class enables IPC with external processes
- Canvas widget for custom UI (lists, trees, etc.)
- `beforecommand`/`aftercommand` intercept save/open/export
- CLI `--batch` mode for headless multi-file processing
- `app.command.X{ ui=false }` suppresses command dialogs
- Timer class for periodic callbacks (cannot yield during long ops)

## 11. Useful Constants / Globals

- `app.apiVersion` — current API version number
- `app.version` — Aseprite version object
- `app.activeSprite` — currently focused sprite
- `app.activeLayer`, `app.activeFrame`, `app.activeCel`
- `app.range` — current selection range in timeline
- `app.alert()` — show message dialog
- `app.transaction()` — wrap operations in undo group

## 12. Security Model

- Extension directory scripts = trusted (full permissions)
- Arbitrary location scripts may trigger security prompt
- `dofile()` with non-.lua extensions shows "?" in security dialog
