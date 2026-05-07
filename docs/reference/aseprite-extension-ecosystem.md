# Aseprite Extension Ecosystem Survey (May 2026)

## Layer Structure & Templates

| Plugin | What It Does | URL |
|--------|-------------|-----|
| **Layer Presets** (fletchmakes) | Save/load reusable layer stacks (name, opacity, blend, color). Max 15 layers. Additive only — no validation. | github.com/fletchmakes/layer-presets |
| **FW_Templates** (HenryStrattonFW) | Duplicate a master .ase as new sprite with all layers/groups/content. | github.com/HenryStrattonFW/FW_Templates |
| **CreateSpriteWithPreset** | Canvas size presets only (no layers). | itch.io: dinoandcat |
| **Canvas Templates** (JRiggles) | Canvas size presets only. | github.com/JRiggles/Canvas-Templates |

## Layer Management & Organization

| Plugin | What It Does | URL |
|--------|-------------|-----|
| **RampantDespair Extension** | Mass-import images (dirs=groups), batch rename, sort, export to Spine. | github.com/RampantDespair/Aseprite-Extension |
| **Layer Managers** | Create/remove/adjust/move/merge layers via UI. | community.aseprite.org/t/27849 |
| **Layer Sorting** (phydokz) | Sort layers per-frame via z-index. | itch.io: phydokz |
| **Save/Load Layer Visibility** | Named visibility presets (e.g., "armor set A" vs "set B"). | community.aseprite.org/t/23512 |
| **AsepriteExtensions** (tosik) | Layer visibility patterns + batch export presets. | github.com/tosik/AsepriteExtensions |

## Tagging & Metadata

| Plugin | What It Does | URL |
|--------|-------------|-----|
| **Custom Data Manager** (Bramvale) | View/edit structured metadata on Tags, Layers, Slices, Cels. Types: string, int, float, bool, enum, vector3. Config-driven. | github.com/Bramvale-Studios/aseprite-custom-data |
| **Tag Pivots** (Bramvale) | Custom pivot points per animation tag. | github.com/Bramvale-Studios/aseprite-tag-pivots |
| **Slice Renamer** (sodedromme) | Batch rename slices, auto-number, engine-friendly transforms, export as JSON/CSV. | itch.io: sodedromme |

## Character Pipeline & Modular Characters

| Plugin | What It Does | URL |
|--------|-------------|-----|
| **Attachment System** (official) | Hierarchical sub-sprites via tiles/tilesets. Modular body part reuse across animations. EXPERIMENTAL. | github.com/aseprite/Attachment-System |
| **Export Combinations** | Export every layer x tag combination. For modular characters in Unity. | github.com/ntd280804/Aseprite-Export-Combinations |
| **Modular Spritesheets (nested tags)** | Export modular layers with nested tag structures. | community.aseprite.org/t/25831 |
| **Asemulator** | Preview/test character animations in game-like environment inside Aseprite. | itch.io: maplegecko |
| **Animation Suite** (thkaspar) | Import animations from other sprites, generate perfect loops. | itch.io: thkaspar |

## Export & Naming

| Plugin | What It Does | URL |
|--------|-------------|-----|
| **Advanced Exports** (Coldfox) | Batch export with `[ignore]`/`[include]` keywords, per-file settings. v5.6. | itch.io: coldfox-co |
| **Export Groups/Layers/Tags** | Export spritesheets split by layers + tags. | community.aseprite.org/t/14489 |

## Gap Analysis — What Doesn't Exist

1. **Layer structure validation/enforcement** — No plugin checks "does this file have the required layers?"
2. **Naming convention linting** — No plugin scans names against a ruleset
3. **Cross-file consistency** — Nothing ensures character files share the same layer structure
4. **Project-level asset catalog** — Nothing tracks characters/animations/variants across files
5. **Completeness tracking** — Nothing tracks "character A has idle/walk but is missing jump"
6. **Game engine integration contract** — No plugin exports a manifest designed for engine consumption
7. **Schema-driven workflow** — No plugin enforces a project-wide layer/tag schema from a config file
