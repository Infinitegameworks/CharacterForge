# Aseprite Attachment System — Architecture Analysis

## Overview

Official experimental plugin by Igara Studio (Aseprite team), sponsored by Soupmasters for "Big Boy Boxing". Enables hierarchical modular character sprites using tiles/tilesets as sub-sprites.

**Repo**: `aseprite/Attachment-System` (MIT, Lua, v0.2.7)

## Core Concepts

- **Attachments**: Tilemap layers where one large tile per frame = one body part instance. Tileset tiles are canvas-sized (not small tiles).
- **Categories**: Multiple tilesets for the same layer = variations (e.g., "Base" vs "Armored" for body). Categories maintain identical tile count/ordering.
- **Folders**: Organizational views of attachments within a layer (e.g., "Base Set" auto-folder, plus custom folders for animation grouping).
- **Anchors**: Reference points on tiles that define how child layers attach to parent layers. Stored per-tile in the base tileset.

## Data Model (Extension Properties)

All data stored via **extension-namespaced properties** in the `.aseprite` file itself (no external config files for sprite data). Key: `"aseprite/Attachment-System"`.

```
Sprite.properties(PK) = {
  version = 4                    -- DB schema version for migrations
}

Tileset.properties(PK) = {
  id = categoryID                -- unique ID, referenced by layers
}

Layer.properties(PK) = {
  id = layerID,                  -- unique per tilemap layer
  categories = { catID1, catID2, ... },
  folders = {
    { name = "Folder Name",
      items = { { tile=tileIndex, position=Point(col,row) }, ... },
      viewport = Size(columns, rows) }
  }
}

Tile.properties(PK) = {
  ref = Point(x, y),            -- reference point (base tileset only)
  anchors = {
    { layerId = layerID, position = Point(x, y) },
    ...
  }
}
```

## Key Patterns Worth Mirroring

### 1. Extension-Namespaced Properties for In-File Metadata
Rather than external sidecar files, the Attachment System stores ALL structured data inside the `.aseprite` file using `obj.properties("publisher/extension-name")`. This means:
- Data travels with the file (no sync issues)
- Undo/redo integration is automatic
- Other tools can read but won't collide (namespaced)

### 2. Schema Versioning with Migration
`sprite.properties(PK).version` tracks the DB version. `setupSprite()` runs migrations when the version is outdated. This is critical for plugin evolution.

### 3. ID-Based References (Not Name-Based)
Layers and categories use numeric IDs, not names. This means renaming a layer doesn't break references. IDs are auto-incremented via `calculateNewLayerID()` / `calculateNewCategoryID()`.

### 4. `setupSprite()` Pattern
On first interaction with a sprite, the plugin runs `db.setupSprite(spr)` which:
- Assigns IDs to any un-ID'd tilesets/layers
- Creates default folders
- Runs schema migrations
- Sets `tileManagementPlugin` to claim tile management

### 5. Batch-Mode Export Pipeline
`export.lua` runs headless via `aseprite -b sprite.aseprite -script export.lua`. It:
- Duplicates tilemap layers per category (creating "layer/category" splits)
- Runs `ExportSpriteSheet` with `ui=false`, `splitLayers=true`
- Outputs `.png` spritesheet + `.json` data file
- Supports `-script-param` for custom output paths

### 6. Plugin Structure
```
package.json          -- manifest
plugin.lua            -- init/exit, delegates to commands + pref + main
db.lua                -- data model, properties read/write, migrations
base.lua              -- utility functions
commands.lua          -- menu command registration
main.lua              -- UI dialog (canvas-based custom rendering)
export.lua            -- CLI batch export script
pref.lua              -- preferences persistence
```

## Patterns to Adapt (Not Copy)

The Attachment System is built for **tile-based modular characters** (each body part is a tile in a tileset). Our plugin is for **layer-based character pipeline management** (each body part is a regular layer or layer group). Different data model, but same organizational principles:

- **Their tilesets = our layer schema definitions** (what layers should exist)
- **Their categories = our character variants** (different costumes/equipment)
- **Their folders = our animation groups** (organizational views)
- **Their anchors = our layer relationships** (how parts connect)
- **Their export.lua = our manifest export** (data for the game engine)

## What They Don't Do (Our Differentiators)

1. No cross-file validation or consistency checks
2. No project-level inventory/catalog
3. No naming convention enforcement
4. No completeness tracking
5. No external schema config (everything is per-sprite, no project-wide rules)
6. No game engine integration contract
