local blueprint = {}

local PK = "infinitegameworks/character-forge"
local SCHEMA_VERSION = 2

blueprint.PK = PK
blueprint.SCHEMA_VERSION = SCHEMA_VERSION

local preferences = nil

local function safeCloseSprite(sprite)
  pcall(function()
    if sprite and sprite.close then
      sprite:close()
    else
      app.command.CloseFile()
    end
  end)
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function cleanArray(list)
  local out = {}
  for _, item in ipairs(list or {}) do
    out[#out + 1] = item
  end
  return out
end

function blueprint.slugify(value, fallback)
  local text = trim(value):lower()
  text = text:gsub("%s+", "_")
  text = text:gsub("[^%w_%-]", "")
  text = text:gsub("_+", "_")
  text = text:gsub("^_+", "")
  text = text:gsub("_+$", "")
  if text == "" then text = fallback or "item" end
  return text
end

local function uniqueId(existing, prefix, name)
  local base = prefix .. "_" .. blueprint.slugify(name, prefix)
  local id = base
  local i = 2
  while existing[id] do
    id = base .. "_" .. tostring(i)
    i = i + 1
  end
  existing[id] = true
  return id
end

local function copyAppliesTo(value)
  local out = {}
  for i, item in ipairs(value or {}) do
    out[i] = item
  end
  return out
end

local function normalizeVariant(variant, existing)
  local name = trim(variant and variant.name or "")
  if name == "" then name = "base" end
  local variantType = (variant and variant.type) or "variant"
  if variantType == "equipment" then variantType = "variant" end
  local id = variant and variant.id
  if not id or id == "" or existing[id] then
    id = uniqueId(existing, "variant", name)
  else
    existing[id] = true
  end

  local required = false
  if variant and variant.required ~= nil then
    required = variant.required and true or false
  end
  if name == "base" or id == "variant_base" or id == "base" then
    required = true
  end

  local entry = {
    id = id,
    name = name,
    type = variantType,
    required = required,
  }
  if variant and variant.applies_to then
    entry.applies_to = copyAppliesTo(variant.applies_to)
  end
  return entry
end

local function ensureBaseVariant(variants)
  for _, variant in ipairs(variants) do
    if variant.name == "base" or variant.id == "base" or variant.id == "variant_base" then
      variant.name = "base"
      variant.required = true
      return variants
    end
  end

  table.insert(variants, 1, {
    id = "variant_base",
    name = "base",
    type = "variant",
    required = true,
  })
  return variants
end

local function normalizeVariants(variants)
  local out = {}
  local existing = {}
  for _, variant in ipairs(variants or {}) do
    out[#out + 1] = normalizeVariant(variant, existing)
  end
  return ensureBaseVariant(out)
end

local function cloneVariants(variants)
  local out = {}
  local existing = {}
  for i, variant in ipairs(variants or {}) do
    out[i] = normalizeVariant(variant, existing)
  end
  return ensureBaseVariant(out)
end

local function normalizeSlot(slot, fallbackVariants, existing)
  local name = trim(slot and slot.name or "")
  if name == "" then name = "default" end
  local id = slot and slot.id
  if not id or id == "" or existing[id] then
    id = uniqueId(existing, "slot", name)
  else
    existing[id] = true
  end

  local variants = {}
  if slot and slot.variants and #slot.variants > 0 then
    variants = normalizeVariants(slot.variants)
  else
    variants = cloneVariants(fallbackVariants)
  end

  return {
    id = id,
    name = name,
    required = slot and slot.required ~= false,
    variants = variants,
  }
end

function blueprint.normalizeSchema(schema)
  schema = schema or {}
  local globalVariants = normalizeVariants(schema.variants or {})
  local bodyParts = {}
  local existingPartIds = {}

  for i, part in ipairs(schema.body_parts or {}) do
    local partName = trim(part.name)
    if partName ~= "" then
      local partId = part.id
      if not partId or partId == "" or existingPartIds[partId] then
        partId = uniqueId(existingPartIds, "part", partName)
      else
        existingPartIds[partId] = true
      end

      local slots = {}
      local existingSlotIds = {}
      if part.slots and #part.slots > 0 then
        for _, slot in ipairs(part.slots) do
          slots[#slots + 1] = normalizeSlot(slot, globalVariants, existingSlotIds)
        end
      else
        slots[1] = normalizeSlot({
          id = "slot_default",
          name = "default",
          variants = globalVariants,
          required = true,
        }, globalVariants, existingSlotIds)
      end

      bodyParts[#bodyParts + 1] = {
        id = partId,
        name = partName,
        sort_order = part.sort_order or i,
        slots = slots,
      }
    end
  end

  local animations = {}
  for i, anim in ipairs(schema.animations or {}) do
    animations[i] = {
      name = anim.name or "",
      file = anim.file or "",
      status = anim.status or "missing",
      last_result = anim.last_result or "",
      done_count = anim.done_count or 0,
      total_count = anim.total_count or 0,
    }
  end

  return {
    schema_version = SCHEMA_VERSION,
    type = schema.type,
    character_name = schema.character_name or "",
    body_parts = bodyParts,
    variants = globalVariants,
    animations = animations,
  }
end

local function writeVariantsToProperties(variants)
  local out = {}
  for i, variant in ipairs(variants or {}) do
    out[i] = {
      id = variant.id,
      name = variant.name,
      type = variant.type,
      required = variant.required and true or false,
    }
    if variant.applies_to then
      out[i].applies_to = copyAppliesTo(variant.applies_to)
    end
  end
  return out
end

local function writeSlotsToProperties(slots)
  local out = {}
  for i, slot in ipairs(slots or {}) do
    out[i] = {
      id = slot.id,
      name = slot.name,
      required = slot.required ~= false,
      variants = writeVariantsToProperties(slot.variants),
    }
  end
  return out
end

local function writePartsToProperties(parts)
  local out = {}
  for i, part in ipairs(parts or {}) do
    out[i] = {
      id = part.id,
      name = part.name,
      sort_order = part.sort_order or i,
      slots = writeSlotsToProperties(part.slots),
    }
  end
  return out
end

local function writeAnimationsToProperties(animations)
  local out = {}
  for i, anim in ipairs(animations or {}) do
    out[i] = {
      name = anim.name or "",
      file = anim.file or "",
      status = anim.status or "missing",
      last_result = anim.last_result or "",
      done_count = anim.done_count or 0,
      total_count = anim.total_count or 0,
    }
  end
  return out
end

function blueprint.setPreferences(prefs)
  preferences = prefs
  if preferences then
    preferences.recent_blueprints = preferences.recent_blueprints or {}
    preferences.project_roots = preferences.project_roots or {}
    preferences.save_mode = preferences.save_mode or "block"
  end
end

function blueprint.getSaveMode()
  return (preferences and preferences.save_mode) or "block"
end

function blueprint.toggleSaveMode()
  if not preferences then return "block" end
  if preferences.save_mode == "warn" then
    preferences.save_mode = "block"
  else
    preferences.save_mode = "warn"
  end
  return preferences.save_mode
end

function blueprint.rememberBlueprint(path)
  if not preferences or not path or path == "" then return end
  local recent = {}
  recent[1] = path
  for _, existing in ipairs(preferences.recent_blueprints or {}) do
    if existing ~= path and #recent < 12 then
      recent[#recent + 1] = existing
    end
  end
  preferences.recent_blueprints = recent
end

function blueprint.layerProperties(layer)
  if not layer then return nil end
  return layer.properties(PK)
end

function blueprint.setLayerIdentity(layer, kind, id)
  if not layer then return end
  local props = layer.properties(PK)
  props.kind = kind
  props.id = id
end

function blueprint.getLayerIdentity(layer)
  local props = blueprint.layerProperties(layer)
  if not props then return nil, nil end
  return props.kind, props.id
end

function blueprint.findLayerById(layers, kind, id)
  if not id or id == "" then return nil end
  for _, layer in ipairs(layers or {}) do
    local lk, lid = blueprint.getLayerIdentity(layer)
    if lid == id and (not kind or lk == kind) then
      return layer
    end
  end
  return nil
end

function blueprint.findLayerByName(layers, name)
  if not name or name == "" then return nil end
  for _, layer in ipairs(layers or {}) do
    if layer.name == name then
      return layer
    end
  end
  return nil
end

function blueprint.findLayerByNameInsensitive(layers, name)
  if not name or name == "" then return nil end
  local lower = string.lower(name)
  for _, layer in ipairs(layers or {}) do
    if string.lower(layer.name) == lower then
      return layer
    end
  end
  return nil
end

function blueprint.findLayerByIdOrName(layers, kind, id, name)
  return blueprint.findLayerById(layers, kind, id) or blueprint.findLayerByName(layers, name)
end

function blueprint.isBlueprint(sprite)
  if not sprite then return false end
  local props = sprite.properties(PK)
  return props and props.type == "blueprint"
end

function blueprint.isAnimation(sprite)
  if not sprite then return false end
  local props = sprite.properties(PK)
  return props and props.type == "animation"
end

function blueprint.readBlueprintSchema(sprite)
  if not sprite then return nil end
  local props = sprite.properties(PK)
  if not props or props.type ~= "blueprint" then return nil end
  local schema = blueprint.normalizeSchema(props)
  schema.type = "blueprint"
  return schema
end

function blueprint.writeBlueprintSchema(sprite, schema)
  if not sprite then return false end
  local normalized = blueprint.normalizeSchema(schema)

  local props = sprite.properties(PK)
  props.schema_version = SCHEMA_VERSION
  props.type = "blueprint"
  props.character_name = normalized.character_name
  props.body_parts = writePartsToProperties(normalized.body_parts)
  props.variants = writeVariantsToProperties(normalized.variants)
  props.animations = writeAnimationsToProperties(normalized.animations)

  if sprite.filename and sprite.filename ~= "" and app.fs.isFile(sprite.filename) then
    blueprint.rememberBlueprint(sprite.filename)
  end

  return true
end

function blueprint.readAnimationData(sprite)
  if not sprite then return nil end
  local props = sprite.properties(PK)
  if not props or props.type ~= "animation" then return nil end

  local data = {
    schema_version = props.schema_version or 1,
    type = "animation",
    blueprint_ref = props.blueprint_ref or "",
    blueprint_path = props.blueprint_path or "",
    character_name = props.character_name or "",
    animation_name = props.animation_name or "",
    cached_schema = nil,
    last_validated = props.last_validated or 0,
    validation_result = props.validation_result or "unknown",
    layer_status = cleanArray(props.layer_status or {}),
    absent_variants = cleanArray(props.absent_variants or {}),
  }

  if props.cached_schema then
    data.cached_schema = blueprint.normalizeSchema({
      character_name = props.character_name or "",
      body_parts = props.cached_schema.body_parts or {},
      variants = props.cached_schema.variants or {},
      animations = props.cached_schema.animations or {},
    })
    data.cached_schema.cache_timestamp = props.cached_schema.cache_timestamp or 0
  end

  return data
end

function blueprint.writeAnimationData(sprite, data)
  if not sprite then return false end

  local cachedSchema = nil
  if data.cached_schema then
    local normalized = blueprint.normalizeSchema(data.cached_schema)
    cachedSchema = {
      body_parts = writePartsToProperties(normalized.body_parts),
      variants = writeVariantsToProperties(normalized.variants),
      animations = writeAnimationsToProperties(normalized.animations),
      cache_timestamp = data.cached_schema.cache_timestamp or os.time(),
    }
  end

  local layerStatus = cleanArray(data.layer_status or {})
  local absentVariants = cleanArray(data.absent_variants or {})

  local props = sprite.properties(PK)
  props.schema_version = SCHEMA_VERSION
  props.type = "animation"
  props.blueprint_ref = data.blueprint_ref or ""
  props.blueprint_path = data.blueprint_path or ""
  props.character_name = data.character_name or ""
  props.animation_name = data.animation_name or ""
  props.cached_schema = cachedSchema
  props.last_validated = data.last_validated or 0
  props.validation_result = data.validation_result or "unknown"
  props.layer_status = layerStatus
  props.absent_variants = absentVariants

  return true
end

function blueprint.cacheSchemaInAnimation(sprite, blueprintSchema)
  if not sprite then return false end
  local data = blueprint.readAnimationData(sprite) or {}
  local normalized = blueprint.normalizeSchema(blueprintSchema)
  data.cached_schema = {
    body_parts = normalized.body_parts,
    variants = normalized.variants,
    animations = normalized.animations,
    cache_timestamp = os.time(),
  }
  data.type = "animation"
  return blueprint.writeAnimationData(sprite, data)
end

function blueprint.writeValidationResult(sprite, result)
  if not sprite then return false end
  local data = blueprint.readAnimationData(sprite)
  if not data then return false end

  data.last_validated = os.time()
  data.validation_result = result.result
  data.layer_status = result.layer_status or data.layer_status or {}

  return blueprint.writeAnimationData(sprite, data)
end

local function createGroup(sprite, parent, name, kind, id)
  local group = sprite:newGroup()
  group.name = name
  if parent then group.parent = parent end
  blueprint.setLayerIdentity(group, kind, id)
  return group
end

local function isDefaultSlot(slot)
  return slot.id == "slot_default" or slot.name == "default"
end

local function getSlotContainer(partLayer, slot, createMissing, sprite)
  local slotLayer = blueprint.findLayerByIdOrName(partLayer.layers, "slot", slot.id, slot.name)
  if slotLayer then
    blueprint.setLayerIdentity(slotLayer, "slot", slot.id)
    return slotLayer
  end

  if isDefaultSlot(slot) then
    for _, variant in ipairs(slot.variants or {}) do
      local direct = blueprint.findLayerByIdOrName(partLayer.layers, "variant", variant.id, variant.name)
      if direct then
        return partLayer
      end
    end
  end

  if createMissing then
    return createGroup(sprite, partLayer, slot.name, "slot", slot.id)
  end

  return nil
end

function blueprint.findVariantLayer(partLayer, slot, variant)
  if not partLayer then return nil end
  local slotLayer = blueprint.findLayerByIdOrName(partLayer.layers, "slot", slot.id, slot.name)
  if slotLayer then
    return blueprint.findLayerByIdOrName(slotLayer.layers, "variant", variant.id, variant.name), slotLayer
  end

  if isDefaultSlot(slot) then
    return blueprint.findLayerByIdOrName(partLayer.layers, "variant", variant.id, variant.name), partLayer
  end

  return nil, nil
end

function blueprint.ensureLayerStructure(sprite, schema, options)
  if not sprite then return { created = 0, renamed = 0 } end
  options = options or {}
  local normalized = blueprint.normalizeSchema(schema)
  local created = 0
  local renamed = 0

  for _, part in ipairs(normalized.body_parts or {}) do
    local partLayer = blueprint.findLayerByIdOrName(sprite.layers, "part", part.id, part.name)
    if not partLayer then
      partLayer = createGroup(sprite, nil, part.name, "part", part.id)
      created = created + 1
    else
      blueprint.setLayerIdentity(partLayer, "part", part.id)
      if options.rename and partLayer.name ~= part.name then
        partLayer.name = part.name
        renamed = renamed + 1
      end
    end

    for _, slot in ipairs(part.slots or {}) do
      local slotContainer = getSlotContainer(partLayer, slot, true, sprite)
      if slotContainer ~= partLayer then
        if options.rename and slotContainer.name ~= slot.name then
          slotContainer.name = slot.name
          renamed = renamed + 1
        end
        blueprint.setLayerIdentity(slotContainer, "slot", slot.id)
      end

      for _, variant in ipairs(slot.variants or {}) do
        local variantLayer = blueprint.findLayerByIdOrName(slotContainer.layers, "variant", variant.id, variant.name)
        if not variantLayer then
          variantLayer = createGroup(sprite, slotContainer, variant.name, "variant", variant.id)
          created = created + 1
        else
          blueprint.setLayerIdentity(variantLayer, "variant", variant.id)
          if options.rename and variantLayer.name ~= variant.name then
            variantLayer.name = variant.name
            renamed = renamed + 1
          end
        end
      end
    end
  end

  return { created = created, renamed = renamed }
end

local function childGroups(layer)
  local out = {}
  for _, child in ipairs(layer.layers or {}) do
    if child.isGroup then out[#out + 1] = child end
  end
  return out
end

local function variantFromLayer(layer, existing)
  local id = select(2, blueprint.getLayerIdentity(layer))
  if not id or id == "" or existing[id] then
    id = uniqueId(existing, "variant", layer.name)
  else
    existing[id] = true
  end
  blueprint.setLayerIdentity(layer, "variant", id)
  return {
    id = id,
    name = layer.name,
    type = "variant",
    required = layer.name == "base",
  }
end

function blueprint.schemaFromSprite(sprite, characterName)
  local bodyParts = {}
  local partIds = {}

  for _, layer in ipairs(sprite.layers or {}) do
    if layer.isGroup and layer.name ~= "Reference" then
      local partId = select(2, blueprint.getLayerIdentity(layer))
      if not partId or partId == "" or partIds[partId] then
        partId = uniqueId(partIds, "part", layer.name)
      else
        partIds[partId] = true
      end
      blueprint.setLayerIdentity(layer, "part", partId)

      local groups = childGroups(layer)
      local hasNestedGroups = false
      for _, group in ipairs(groups) do
        if #childGroups(group) > 0 then
          hasNestedGroups = true
          break
        end
      end

      local slots = {}
      if hasNestedGroups then
        local slotIds = {}
        for _, slotLayer in ipairs(groups) do
          local slotId = select(2, blueprint.getLayerIdentity(slotLayer))
          if not slotId or slotId == "" or slotIds[slotId] then
            slotId = uniqueId(slotIds, "slot", slotLayer.name)
          else
            slotIds[slotId] = true
          end
          blueprint.setLayerIdentity(slotLayer, "slot", slotId)

          local variantIds = {}
          local variants = {}
          for _, variantLayer in ipairs(childGroups(slotLayer)) do
            variants[#variants + 1] = variantFromLayer(variantLayer, variantIds)
          end
          slots[#slots + 1] = {
            id = slotId,
            name = slotLayer.name,
            required = true,
            variants = ensureBaseVariant(variants),
          }
        end
      else
        local variantIds = {}
        local variants = {}
        for _, variantLayer in ipairs(groups) do
          variants[#variants + 1] = variantFromLayer(variantLayer, variantIds)
        end
        slots[1] = {
          id = "slot_default",
          name = "default",
          required = true,
          variants = ensureBaseVariant(variants),
        }
      end

      bodyParts[#bodyParts + 1] = {
        id = partId,
        name = layer.name,
        sort_order = #bodyParts + 1,
        slots = slots,
      }
    end
  end

  return blueprint.normalizeSchema({
    character_name = characterName,
    body_parts = bodyParts,
    animations = {},
  })
end

local function addBlueprintResult(results, seen, path)
  if not path or path == "" or seen[path] or not app.fs.isFile(path) then return end
  seen[path] = true
  local active = app.activeSprite
  if active and active.filename == path and blueprint.isBlueprint(active) then
    local schema = blueprint.readBlueprintSchema(active)
    local name = schema and schema.character_name or app.fs.fileTitle(path)
    table.insert(results, { name = name, path = path, file = app.fs.fileName(path) })
    return
  end

  local spr = app.open(path)
  if not spr then return end
  if blueprint.isBlueprint(spr) then
    local schema = blueprint.readBlueprintSchema(spr)
    local name = schema and schema.character_name or app.fs.fileTitle(path)
    table.insert(results, { name = name, path = path, file = app.fs.fileName(path) })
  end
  safeCloseSprite(spr)
end

local function openSpriteForPath(path)
  local active = app.activeSprite
  if active and active.filename == path then
    return active, false
  end
  return app.open(path), true
end

function blueprint.findBlueprints()
  local results = {}
  local seen = {}

  if preferences then
    for _, path in ipairs(preferences.recent_blueprints or {}) do
      addBlueprintResult(results, seen, path)
    end
  end

  local searchDirs = {}
  local spr = app.activeSprite
  if spr and spr.filename and spr.filename ~= "" then
    local dir = app.fs.filePath(spr.filename)
    if dir and dir ~= "" then
      searchDirs[#searchDirs + 1] = dir
      local parent = app.fs.filePath(dir:sub(1, -2))
      if parent and parent ~= "" and parent ~= dir then
        searchDirs[#searchDirs + 1] = parent
      end
    end
  end
  if preferences then
    for _, dir in ipairs(preferences.project_roots or {}) do
      searchDirs[#searchDirs + 1] = dir
    end
  end

  for _, dir in ipairs(searchDirs) do
    if app.fs.isDirectory(dir) then
      for _, file in ipairs(app.fs.listFiles(dir) or {}) do
        local ext = app.fs.fileExtension(file)
        local lower = string.lower(file)
        if (ext == "ase" or ext == "aseprite") and string.find(lower, "blueprint", 1, true) then
          addBlueprintResult(results, seen, app.fs.joinPath(dir, file))
        end
      end
    end
  end

  return results
end

local function blueprintDialog(title)
  local blueprints = blueprint.findBlueprints()
  local labels = {}
  local byLabel = {}
  for _, bp in ipairs(blueprints) do
    local label = bp.name .. " (" .. bp.file .. ")"
    labels[#labels + 1] = label
    byLabel[label] = bp
  end
  if #labels == 0 then labels[1] = "Browse for blueprint..." end

  local dlg = Dialog{ title = title }
  dlg:combobox{ id = "blueprintChoice", label = "Known:", options = labels }
  dlg:file{
    id = "blueprintFile",
    label = "Or File:",
    filename = "",
    open = true,
    filetypes = { "ase", "aseprite" },
  }
  return dlg, byLabel
end

local function selectedBlueprintPath(dlg, byLabel)
  local explicit = dlg.data.blueprintFile
  if explicit and explicit ~= "" then return explicit end
  local selected = byLabel[dlg.data.blueprintChoice or ""]
  return selected and selected.path or nil
end

local function shouldIncludeVariant(variant, animName)
  if variant.type ~= "state" or not variant.applies_to then return true end
  for _, allowed in ipairs(variant.applies_to or {}) do
    if allowed == animName then return true end
  end
  return false
end

function blueprint.showNewAnimationDialog()
  local dlg, byLabel = blueprintDialog("New Animation from Blueprint")
  dlg:entry{ id = "animName", label = "Animation:", text = "" }
  dlg:button{ id = "create", text = "Create" }
  dlg:button{ id = "cancel", text = "Cancel" }
  dlg:show()

  if not dlg.data.create then return end

  local bpPath = selectedBlueprintPath(dlg, byLabel)
  local animName = trim(dlg.data.animName)

  if not bpPath or bpPath == "" then
    app.alert("Please select a blueprint.")
    return
  end
  if animName == "" then
    app.alert("Please enter an animation name.")
    return
  end

  local bpSprite, shouldCloseBlueprint = openSpriteForPath(bpPath)
  if not bpSprite then
    app.alert("Could not open blueprint file.")
    return
  end

  local schema = blueprint.readBlueprintSchema(bpSprite)
  if not schema then
    if shouldCloseBlueprint then safeCloseSprite(bpSprite) end
    app.alert("Selected file is not a CharacterForge blueprint.")
    return
  end

  local charName = schema.character_name or "character"
  local fileName = charName .. "_" .. animName .. ".ase"
  local bpDir = app.fs.filePath(bpPath)
  local savePath = app.fs.joinPath(bpDir, fileName)

  if app.fs.isFile(savePath) then
    local overwrite = app.alert{
      title = "Animation Exists",
      text = "A file named '" .. fileName .. "' already exists. Overwrite it?",
      buttons = { "Overwrite", "Cancel" },
    }
    if overwrite ~= 1 then
      if shouldCloseBlueprint then safeCloseSprite(bpSprite) end
      return
    end
  end

  local bpWidth = bpSprite.width
  local bpHeight = bpSprite.height
  local bpColorMode = bpSprite.colorMode
  local bpPalette = nil
  pcall(function() bpPalette = Palette(bpSprite.palettes[1]) end)

  local animations = schema.animations or {}
  local found = false
  for i, anim in ipairs(animations) do
    if anim.name == animName then
      animations[i].file = fileName
      animations[i].status = "started"
      found = true
      break
    end
  end
  if not found then
    animations[#animations + 1] = { name = animName, file = fileName, status = "started" }
  end
  schema.animations = animations
  blueprint.writeBlueprintSchema(bpSprite, schema)
  app.command.SaveFile()
  if shouldCloseBlueprint then safeCloseSprite(bpSprite) end
  blueprint.rememberBlueprint(bpPath)

  local newSprite = Sprite(bpWidth, bpHeight, bpColorMode)
  if bpPalette then newSprite:setPalette(bpPalette) end
  local filtered = blueprint.normalizeSchema(schema)
  for _, part in ipairs(filtered.body_parts or {}) do
    for _, slot in ipairs(part.slots or {}) do
      local variants = {}
      for _, variant in ipairs(slot.variants or {}) do
        if shouldIncludeVariant(variant, animName) then
          variants[#variants + 1] = variant
        end
      end
      slot.variants = variants
    end
  end
  blueprint.ensureLayerStructure(newSprite, filtered)

  if newSprite.layers[1] and newSprite.layers[1].name == "Layer 1" then
    newSprite.layers[1].name = "Reference"
  end

  blueprint.writeAnimationData(newSprite, {
    blueprint_ref = app.fs.fileName(bpPath),
    blueprint_path = bpPath,
    character_name = charName,
    animation_name = animName,
    cached_schema = {
      body_parts = schema.body_parts,
      variants = schema.variants,
      animations = schema.animations,
      cache_timestamp = os.time(),
    },
    last_validated = 0,
    validation_result = "unknown",
    layer_status = {},
  })

  newSprite:saveAs(savePath)

  app.alert("Animation created: " .. fileName)
end

function blueprint.showRegisterDialog()
  local spr = app.activeSprite
  if not spr then
    app.alert("No active sprite to link.")
    return
  end

  if blueprint.isAnimation(spr) then
    local data = blueprint.readAnimationData(spr)
    local confirm = app.alert{
      title = "Already Linked",
      text = "This file is already linked to '" .. (data.character_name or "unknown") .. "'. Link again?",
      buttons = { "Re-link", "Cancel" },
    }
    if confirm ~= 1 then return end
  end

  local defaultAnimName = ""
  if spr.filename and spr.filename ~= "" then
    defaultAnimName = app.fs.fileTitle(spr.filename)
    defaultAnimName = defaultAnimName:gsub("^%w+_", "")
  end

  local dlg, byLabel = blueprintDialog("Link Animation to Character")
  dlg:entry{ id = "animName", label = "Animation:", text = defaultAnimName }
  dlg:button{ id = "register", text = "Link" }
  dlg:button{ id = "cancel", text = "Cancel" }
  dlg:show()

  if not dlg.data.register then return end

  local bpPath = selectedBlueprintPath(dlg, byLabel)
  local animName = trim(dlg.data.animName)

  if not bpPath or bpPath == "" then
    app.alert("Please select a blueprint.")
    return
  end
  if animName == "" then
    app.alert("Please enter an animation name.")
    return
  end

  local bpSprite, shouldCloseBlueprint = openSpriteForPath(bpPath)
  if not bpSprite then
    app.alert("Could not open blueprint file.")
    return
  end

  local schema = blueprint.readBlueprintSchema(bpSprite)
  if not schema then
    if shouldCloseBlueprint then safeCloseSprite(bpSprite) end
    app.alert("Selected file is not a CharacterForge blueprint.")
    return
  end

  local validator = require 'validator'
  local repair = blueprint.ensureLayerStructure(spr, schema, { rename = false })
  local result = validator.validate(spr, schema)

  if #result.errors > 0 or #result.warnings > 0 then
    local msg = "Check results for this file:\n\n"
    for _, err in ipairs(result.errors) do msg = msg .. "[ERROR] " .. err .. "\n" end
    for _, warn in ipairs(result.warnings) do msg = msg .. "[WARN] " .. warn .. "\n" end
    if repair.created > 0 then
      msg = msg .. "\nCreated " .. tostring(repair.created) .. " missing group(s) before checking."
    end
    msg = msg .. "\nLink anyway?"
    local proceed = app.alert{
      title = "Status Issues",
      text = msg,
      buttons = { "Link", "Cancel" },
    }
    if proceed ~= 1 then
      if shouldCloseBlueprint then safeCloseSprite(bpSprite) end
      return
    end
  end

  local charName = schema.character_name or "character"
  local bpFileName = app.fs.fileName(bpPath)
  blueprint.writeAnimationData(spr, {
    blueprint_ref = bpFileName,
    blueprint_path = bpPath,
    character_name = charName,
    animation_name = animName,
    cached_schema = {
      body_parts = schema.body_parts,
      variants = schema.variants,
      animations = schema.animations,
      cache_timestamp = os.time(),
    },
    last_validated = os.time(),
    validation_result = result.result,
    layer_status = result.layer_status or {},
  })

  local animations = schema.animations or {}
  local sprFileName = app.fs.fileName(spr.filename)
  local found = false
  for i, anim in ipairs(animations) do
    if anim.name == animName then
      animations[i].file = sprFileName
      local allDone = result.result ~= "fail" and blueprint.checkAllVariantsDone(spr)
      animations[i].status = result.result == "fail" and "invalid" or (allDone and "valid" or "started")
      found = true
      break
    end
  end
  if not found then
    animations[#animations + 1] = {
      name = animName,
      file = sprFileName,
      status = result.result == "fail" and "invalid" or (blueprint.checkAllVariantsDone(spr) and "valid" or "started"),
    }
  end
  schema.animations = animations
  blueprint.writeBlueprintSchema(bpSprite, schema)
  app.command.SaveFile()
  if shouldCloseBlueprint then safeCloseSprite(bpSprite) end
  blueprint.rememberBlueprint(bpPath)

  app.alert("Linked '" .. animName .. "' to " .. charName .. " character.")
end

function blueprint.showCreateFromCurrentDialog()
  local spr = app.activeSprite
  if not spr then
    app.alert("Open a layered sprite first.")
    return
  end

  local defaultName = "character"
  if spr.filename and spr.filename ~= "" then
    defaultName = app.fs.fileTitle(spr.filename):gsub("_blueprint$", "")
  end

  local dlg = Dialog{ title = "Blueprint From Current Sprite" }
  dlg:entry{ id = "characterName", label = "Character:", text = defaultName }
  dlg:button{ id = "create", text = "Create" }
  dlg:button{ id = "cancel", text = "Cancel" }
  dlg:show()

  if not dlg.data.create then return end
  local charName = trim(dlg.data.characterName)
  if charName == "" then
    app.alert("Character name is required.")
    return
  end

  local schema = blueprint.schemaFromSprite(spr, charName)
  if #schema.body_parts == 0 then
    app.alert("No top-level layer groups found. Add body part groups first.")
    return
  end

  app.transaction(function()
    blueprint.ensureLayerStructure(spr, schema, { rename = false })
    blueprint.writeBlueprintSchema(spr, schema)
  end)
  if spr.filename and spr.filename ~= "" then
    blueprint.rememberBlueprint(spr.filename)
  end
  app.alert("Blueprint created from current sprite: " .. charName)
end

function blueprint.createNextAnimation(bpPath, targetAnimName)
  if not bpPath or bpPath == "" then return nil end
  if not app.fs.isFile(bpPath) then return nil end

  local bpSprite, shouldCloseBlueprint = openSpriteForPath(bpPath)
  if not bpSprite then return nil end

  local schema = blueprint.readBlueprintSchema(bpSprite)
  if not schema then
    if shouldCloseBlueprint then safeCloseSprite(bpSprite) end
    return nil
  end

  local nextAnim = nil
  if targetAnimName then
    for _, anim in ipairs(schema.animations or {}) do
      if anim.name == targetAnimName then
        nextAnim = anim
        break
      end
    end
  else
    for _, anim in ipairs(schema.animations or {}) do
      if anim.status == "missing" then
        nextAnim = anim
        break
      end
    end
  end

  if not nextAnim then
    if shouldCloseBlueprint then safeCloseSprite(bpSprite) end
    return nil
  end

  local animName = nextAnim.name or ""
  if animName == "" then
    if shouldCloseBlueprint then safeCloseSprite(bpSprite) end
    return nil
  end

  local charName = schema.character_name or "character"
  local fileName = charName .. "_" .. animName .. ".ase"
  local bpDir = app.fs.filePath(bpPath)
  local savePath = app.fs.joinPath(bpDir, fileName)

  if app.fs.isFile(savePath) then
    local overwrite = app.alert{
      title = "Animation Exists",
      text = "A file named '" .. fileName .. "' already exists. Overwrite it?",
      buttons = { "Overwrite", "Cancel" },
    }
    if overwrite ~= 1 then
      if shouldCloseBlueprint then safeCloseSprite(bpSprite) end
      return nil, "cancelled"
    end
  end

  local bpWidth = bpSprite.width
  local bpHeight = bpSprite.height
  local bpColorMode = bpSprite.colorMode
  local bpPalette = nil
  pcall(function() bpPalette = Palette(bpSprite.palettes[1]) end)

  local animations = schema.animations or {}
  for i, anim in ipairs(animations) do
    if anim.name == animName then
      animations[i].file = fileName
      animations[i].status = "started"
      break
    end
  end
  schema.animations = animations
  blueprint.writeBlueprintSchema(bpSprite, schema)
  app.command.SaveFile()
  if shouldCloseBlueprint then safeCloseSprite(bpSprite) end
  blueprint.rememberBlueprint(bpPath)

  local newSprite = Sprite(bpWidth, bpHeight, bpColorMode)
  if bpPalette then newSprite:setPalette(bpPalette) end

  local filtered = blueprint.normalizeSchema(schema)
  for _, part in ipairs(filtered.body_parts or {}) do
    for _, slot in ipairs(part.slots or {}) do
      local variants = {}
      for _, variant in ipairs(slot.variants or {}) do
        if shouldIncludeVariant(variant, animName) then
          variants[#variants + 1] = variant
        end
      end
      slot.variants = variants
    end
  end
  blueprint.ensureLayerStructure(newSprite, filtered)

  if newSprite.layers[1] and newSprite.layers[1].name == "Layer 1" then
    newSprite.layers[1].name = "Reference"
  end

  blueprint.writeAnimationData(newSprite, {
    blueprint_ref = app.fs.fileName(bpPath),
    blueprint_path = bpPath,
    character_name = charName,
    animation_name = animName,
    cached_schema = {
      body_parts = schema.body_parts,
      variants = schema.variants,
      animations = schema.animations,
      cache_timestamp = os.time(),
    },
    last_validated = 0,
    validation_result = "unknown",
    layer_status = {},
  })

  newSprite:saveAs(savePath)
  return savePath
end

local function collectFrameSet(layer, frames)
  if not layer then return frames end
  frames = frames or {}
  if layer.cels then
    for _, cel in ipairs(layer.cels) do
      local frameNumber = nil
      if cel.frame and cel.frame.frameNumber then
        frameNumber = cel.frame.frameNumber
      elseif cel.frameNumber then
        frameNumber = cel.frameNumber
      end
      if frameNumber then frames[frameNumber] = true end
    end
  end
  if layer.isGroup then
    for _, child in ipairs(layer.layers or {}) do
      collectFrameSet(child, frames)
    end
  end
  return frames
end

local function firstImageLayer(sprite, parent)
  if not parent then return nil end
  if not parent.isGroup then return parent end
  for _, child in ipairs(parent.layers or {}) do
    local found = firstImageLayer(sprite, child)
    if found then return found end
  end
  local layer = sprite:newLayer()
  layer.name = "art"
  layer.parent = parent
  blueprint.setLayerIdentity(layer, "art", "art")
  return layer
end

function blueprint.syncVariantFrames(sprite, schema)
  if not sprite then return 0 end
  local normalized = blueprint.normalizeSchema(schema)
  local added = 0

  for _, part in ipairs(normalized.body_parts or {}) do
    local partLayer = blueprint.findLayerByIdOrName(sprite.layers, "part", part.id, part.name)
    if partLayer then
      for _, slot in ipairs(part.slots or {}) do
        local baseVariant = slot.variants[1]
        for _, variant in ipairs(slot.variants or {}) do
          if variant.name == "base" or variant.id == "variant_base" then
            baseVariant = variant
            break
          end
        end
        local baseLayer = blueprint.findVariantLayer(partLayer, slot, baseVariant)
        local baseFrames = collectFrameSet(baseLayer, {})
        for _, variant in ipairs(slot.variants or {}) do
          if variant ~= baseVariant then
            local variantLayer = blueprint.findVariantLayer(partLayer, slot, variant)
            if variantLayer then
              local variantFrames = collectFrameSet(variantLayer, {})
              local targetLayer = firstImageLayer(sprite, variantLayer)
              for frameNumber in pairs(baseFrames) do
                if not variantFrames[frameNumber] and targetLayer then
                  local image = Image(sprite.spec)
                  image:clear()
                  sprite:newCel(targetLayer, frameNumber, image, Point(0, 0))
                  added = added + 1
                end
              end
            end
          end
        end
      end
    end
  end

  return added
end

local function ancestorChain(layer)
  local chain = {}
  local current = layer
  while current and current.parent and current.parent.layers do
    chain[#chain + 1] = current
    current = current.parent
  end
  return chain
end

local function activeManagedAncestor(kind)
  local layer = app.activeLayer
  for _, current in ipairs(ancestorChain(layer)) do
    local lk = select(1, blueprint.getLayerIdentity(current))
    if lk == kind then return current end
  end
  return nil
end

function blueprint.soloActivePart(sprite)
  sprite = sprite or app.activeSprite
  if not sprite then return false end
  local part = activeManagedAncestor("part")
  if not part then return false end
  for _, layer in ipairs(sprite.layers or {}) do
    if layer.isGroup then layer.isVisible = (layer == part) end
  end
  return true
end

function blueprint.soloActiveVariant(sprite)
  sprite = sprite or app.activeSprite
  if not sprite then return false end
  local variant = activeManagedAncestor("variant")
  if not variant then return false end
  local _, variantId = blueprint.getLayerIdentity(variant)
  if not variantId then return false end

  local function visit(layer)
    local kind, id = blueprint.getLayerIdentity(layer)
    if kind == "variant" then
      layer.isVisible = (id == variantId)
    end
    if layer.isGroup then
      for _, child in ipairs(layer.layers or {}) do visit(child) end
    end
  end
  for _, layer in ipairs(sprite.layers or {}) do visit(layer) end
  return true
end

function blueprint.showAllManagedLayers(sprite)
  sprite = sprite or app.activeSprite
  if not sprite then return false end
  local function visit(layer)
    local kind = select(1, blueprint.getLayerIdentity(layer))
    if kind == "part" or kind == "slot" or kind == "variant" then
      layer.isVisible = true
    end
    if layer.isGroup then
      for _, child in ipairs(layer.layers or {}) do visit(child) end
    end
  end
  for _, layer in ipairs(sprite.layers or {}) do visit(layer) end
  return true
end

function blueprint.listSlotNames(schema)
  local normalized = blueprint.normalizeSchema(schema)
  local names = {}
  local seen = {}
  for _, part in ipairs(normalized.body_parts or {}) do
    for _, slot in ipairs(part.slots or {}) do
      if not seen[slot.name] then
        names[#names + 1] = slot.name
        seen[slot.name] = true
      end
    end
  end
  return names
end

local function setLayerTreeVisibility(layer, visible)
  if not layer then return end
  layer.isVisible = visible
  if layer.isGroup then
    for _, child in ipairs(layer.layers or {}) do
      setLayerTreeVisibility(child, visible)
    end
  end
end

local function setSlotContentsVisible(partLayer, slot, visible)
  if not partLayer then return end
  local slotLayer = blueprint.findLayerByIdOrName(partLayer.layers, "slot", slot.id, slot.name)
  if slotLayer then
    setLayerTreeVisibility(slotLayer, visible)
    return
  end

  if isDefaultSlot(slot) then
    for _, variant in ipairs(slot.variants or {}) do
      local variantLayer = blueprint.findLayerByIdOrName(partLayer.layers, "variant", variant.id, variant.name)
      if variantLayer then setLayerTreeVisibility(variantLayer, visible) end
    end
  end
end

function blueprint.setSlotVisibility(sprite, schema, slotName, mode)
  if not sprite then return false end
  if mode == "all" then
    return blueprint.showAllManagedLayers(sprite)
  end

  local normalized = blueprint.normalizeSchema(schema)
  local changed = false

  for _, part in ipairs(normalized.body_parts or {}) do
    local partLayer = blueprint.findLayerByIdOrName(sprite.layers, "part", part.id, part.name)
    if partLayer then
      partLayer.isVisible = true
      for _, slot in ipairs(part.slots or {}) do
        if mode == "solo" then
          setSlotContentsVisible(partLayer, slot, slot.name == slotName)
          changed = true
        elseif mode == "hide" and slot.name == slotName then
          setSlotContentsVisible(partLayer, slot, false)
          changed = true
        elseif mode == "show" and slot.name == slotName then
          setSlotContentsVisible(partLayer, slot, true)
          changed = true
        end
      end
    end
  end

  return changed
end

function blueprint.toggleActiveVariantAbsent()
  local variant = activeManagedAncestor("variant")
  if not variant then return nil end
  local props = variant.properties(PK)
  props.intentionally_absent = not props.intentionally_absent
  return props.intentionally_absent
end

function blueprint.checkAllVariantsDone(sprite)
  if not sprite then return false, 0, 0 end
  local data = blueprint.readAnimationData(sprite)
  if not data or not data.cached_schema then return false, 0, 0 end
  local normalized = blueprint.normalizeSchema(data.cached_schema)

  local total = 0
  local done = 0
  for _, part in ipairs(normalized.body_parts or {}) do
    local partLayer = blueprint.findLayerByIdOrName(sprite.layers, "part", part.id, part.name)
    if not partLayer then goto nextPart end
    for _, slot in ipairs(part.slots or {}) do
      for _, variant in ipairs(slot.variants or {}) do
        local vl = blueprint.findVariantLayer(partLayer, slot, variant)
        if vl then
          local props = vl.properties(PK)
          if props and props.intentionally_absent then
            -- skip
          else
            total = total + 1
            if props and props.marked_done then done = done + 1 end
          end
        else
          total = total + 1
        end
      end
    end
    ::nextPart::
  end
  return done == total and total > 0, done, total
end

function blueprint.syncCompletionToBlueprint(animSprite, bpSprite)
  if not animSprite or not bpSprite then return false end
  local data = blueprint.readAnimationData(animSprite)
  if not data or not data.animation_name or data.animation_name == "" then return false end

  local allDone, doneCount, totalCount = blueprint.checkAllVariantsDone(animSprite)
  local schema = blueprint.readBlueprintSchema(bpSprite)
  if not schema then return false end

  local changed = false
  for i, anim in ipairs(schema.animations or {}) do
    if anim.name == data.animation_name then
      local newStatus = allDone and "valid" or "started"
      if anim.status ~= newStatus or anim.done_count ~= doneCount or anim.total_count ~= totalCount then
        schema.animations[i].status = newStatus
        schema.animations[i].done_count = doneCount
        schema.animations[i].total_count = totalCount
        changed = true
      end
      break
    end
  end

  if changed then
    blueprint.writeBlueprintSchema(bpSprite, schema)
  end
  return changed
end

return blueprint
