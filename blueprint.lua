local blueprint = {}

local PK = "infinitegameworks/character-forge"
local SCHEMA_VERSION = 1

blueprint.PK = PK
blueprint.SCHEMA_VERSION = SCHEMA_VERSION

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
  return props
end

function blueprint.writeBlueprintSchema(sprite, schema)
  if not sprite then return false end

  local bodyParts = {}
  for i, part in ipairs(schema.body_parts or {}) do
    bodyParts[i] = { name = part.name, sort_order = part.sort_order }
  end

  local variants = {}
  for i, v in ipairs(schema.variants or {}) do
    local entry = {
      name = v.name,
      type = v.type,
      required = v.required
    }
    if v.applies_to then
      local appliesTo = {}
      for j, a in ipairs(v.applies_to) do
        appliesTo[j] = a
      end
      entry.applies_to = appliesTo
    end
    variants[i] = entry
  end

  local animations = {}
  for i, anim in ipairs(schema.animations or {}) do
    animations[i] = {
      name = anim.name,
      file = anim.file or "",
      status = anim.status or "missing"
    }
  end

  sprite.properties(PK) = {
    schema_version = SCHEMA_VERSION,
    type = "blueprint",
    character_name = schema.character_name or "",
    body_parts = bodyParts,
    variants = variants,
    animations = animations,
  }

  return true
end

function blueprint.readAnimationData(sprite)
  if not sprite then return nil end
  local props = sprite.properties(PK)
  if not props or props.type ~= "animation" then return nil end
  return props
end

function blueprint.writeAnimationData(sprite, data)
  if not sprite then return false end

  local cachedSchema = nil
  if data.cached_schema then
    local bodyParts = {}
    for i, part in ipairs(data.cached_schema.body_parts or {}) do
      bodyParts[i] = { name = part.name, sort_order = part.sort_order }
    end

    local variants = {}
    for i, v in ipairs(data.cached_schema.variants or {}) do
      local entry = { name = v.name, type = v.type, required = v.required }
      if v.applies_to then
        local appliesTo = {}
        for j, a in ipairs(v.applies_to) do
          appliesTo[j] = a
        end
        entry.applies_to = appliesTo
      end
      variants[i] = entry
    end

    cachedSchema = {
      body_parts = bodyParts,
      variants = variants,
      cache_timestamp = data.cached_schema.cache_timestamp or os.time(),
    }
  end

  local layerStatus = {}
  if data.layer_status then
    for i, ls in ipairs(data.layer_status) do
      local variantsComplete = {}
      for j, vc in ipairs(ls.variants_complete or {}) do
        variantsComplete[j] = vc
      end
      layerStatus[i] = {
        part = ls.part,
        base_frames = ls.base_frames,
        variants_complete = variantsComplete,
      }
    end
  end

  sprite.properties(PK) = {
    schema_version = SCHEMA_VERSION,
    type = "animation",
    blueprint_ref = data.blueprint_ref or "",
    character_name = data.character_name or "",
    animation_name = data.animation_name or "",
    cached_schema = cachedSchema,
    last_validated = data.last_validated or 0,
    validation_result = data.validation_result or "unknown",
    layer_status = layerStatus,
  }

  return true
end

function blueprint.cacheSchemaInAnimation(sprite, blueprintSchema)
  if not sprite then return false end
  local data = blueprint.readAnimationData(sprite) or {}
  data.cached_schema = {
    body_parts = blueprintSchema.body_parts,
    variants = blueprintSchema.variants,
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

function blueprint.showNewAnimationDialog()
  local dlg = Dialog{ title = "New Animation from Blueprint" }

  dlg:file{
    id = "blueprintFile",
    label = "Blueprint:",
    filename = "",
    open = true,
    filetypes = { "ase", "aseprite" }
  }
  dlg:entry{ id = "animName", label = "Animation Name:", text = "" }
  dlg:button{ id = "create", text = "Create" }
  dlg:button{ id = "cancel", text = "Cancel" }

  dlg:show()

  if not dlg.data.create then return end

  local bpPath = dlg.data.blueprintFile
  local animName = dlg.data.animName

  if not bpPath or bpPath == "" then
    app.alert("Please select a blueprint file.")
    return
  end
  if not animName or animName == "" then
    app.alert("Please enter an animation name.")
    return
  end

  local bpSprite = app.open(bpPath)
  if not bpSprite then
    app.alert("Could not open blueprint file.")
    return
  end

  local schema = blueprint.readBlueprintSchema(bpSprite)
  if not schema then
    bpSprite:close()
    app.alert("Selected file is not a CharacterForge blueprint.")
    return
  end

  local charName = schema.character_name or "character"
  local fileName = charName .. "_" .. animName .. ".ase"

  for _, anim in ipairs(schema.animations or {}) do
    if anim.name == animName and anim.status ~= "missing" then
      local confirm = app.alert{
        title = "Animation Exists",
        text = "Animation '" .. animName .. "' already registered. Overwrite?",
        buttons = { "Overwrite", "Cancel" }
      }
      if confirm ~= 1 then
        bpSprite:close()
        return
      end
      break
    end
  end

  local newSprite = Sprite(bpSprite.width, bpSprite.height, bpSprite.colorMode)

  for _, part in ipairs(schema.body_parts or {}) do
    local partGroup = newSprite:newGroup()
    partGroup.name = part.name

    for _, variant in ipairs(schema.variants or {}) do
      if variant.type == "state" and variant.applies_to then
        local applies = false
        for _, a in ipairs(variant.applies_to) do
          if a == animName then applies = true; break end
        end
        if not applies then goto nextVariant end
      end

      local varGroup = newSprite:newGroup()
      varGroup.name = variant.name
      varGroup.parent = partGroup

      ::nextVariant::
    end
  end

  if newSprite.layers[1] and newSprite.layers[1].name == "Layer 1" then
    newSprite:deleteLayer(newSprite.layers[1])
  end

  local bpDir = app.fs.filePath(bpPath)
  local savePath = app.fs.joinPath(bpDir, fileName)

  local animData = {
    blueprint_ref = app.fs.fileName(bpPath),
    character_name = charName,
    animation_name = animName,
    cached_schema = {
      body_parts = schema.body_parts,
      variants = schema.variants,
      cache_timestamp = os.time(),
    },
    last_validated = 0,
    validation_result = "unknown",
    layer_status = {},
  }
  blueprint.writeAnimationData(newSprite, animData)

  newSprite:saveAs(savePath)

  local animations = schema.animations or {}
  local found = false
  for i, anim in ipairs(animations) do
    if anim.name == animName then
      animations[i].file = fileName
      animations[i].status = "valid"
      found = true
      break
    end
  end
  if not found then
    table.insert(animations, { name = animName, file = fileName, status = "valid" })
  end
  schema.animations = animations
  blueprint.writeBlueprintSchema(bpSprite, schema)
  bpSprite:save()
  bpSprite:close()

  app.alert("Animation created: " .. fileName)
end

function blueprint.showRegisterDialog()
  local spr = app.activeSprite
  if not spr then
    app.alert("No active sprite to register.")
    return
  end

  if blueprint.isAnimation(spr) then
    local data = blueprint.readAnimationData(spr)
    local confirm = app.alert{
      title = "Already Registered",
      text = "This file is already registered to '" .. (data.character_name or "unknown") ..
             "'. Re-register to a different blueprint?",
      buttons = { "Re-register", "Cancel" }
    }
    if confirm ~= 1 then return end
  end

  local dlg = Dialog{ title = "Register Animation to Blueprint" }

  dlg:file{
    id = "blueprintFile",
    label = "Blueprint:",
    filename = "",
    open = true,
    filetypes = { "ase", "aseprite" }
  }
  dlg:entry{ id = "animName", label = "Animation Name:", text = "" }
  dlg:button{ id = "register", text = "Register" }
  dlg:button{ id = "cancel", text = "Cancel" }

  dlg:show()

  if not dlg.data.register then return end

  local bpPath = dlg.data.blueprintFile
  local animName = dlg.data.animName

  if not bpPath or bpPath == "" then
    app.alert("Please select a blueprint file.")
    return
  end
  if not animName or animName == "" then
    app.alert("Please enter an animation name.")
    return
  end

  local bpSprite = app.open(bpPath)
  if not bpSprite then
    app.alert("Could not open blueprint file.")
    return
  end

  local schema = blueprint.readBlueprintSchema(bpSprite)
  if not schema then
    bpSprite:close()
    app.alert("Selected file is not a CharacterForge blueprint.")
    return
  end

  local validator = require("validator")
  local result = validator.validate(spr, {
    body_parts = schema.body_parts,
    variants = schema.variants,
  })

  if #result.errors > 0 or #result.warnings > 0 then
    local msg = "Validation results for this file:\n\n"
    for _, err in ipairs(result.errors) do
      msg = msg .. "[ERROR] " .. err .. "\n"
    end
    for _, warn in ipairs(result.warnings) do
      msg = msg .. "[WARN] " .. warn .. "\n"
    end
    msg = msg .. "\nRegister anyway? You can fix these issues after linking."
    local proceed = app.alert{
      title = "Validation Issues",
      text = msg,
      buttons = { "Register", "Cancel" }
    }
    if proceed ~= 1 then
      bpSprite:close()
      return
    end
  end

  local charName = schema.character_name or "character"
  local bpFileName = app.fs.fileName(bpPath)

  local animData = {
    blueprint_ref = bpFileName,
    character_name = charName,
    animation_name = animName,
    cached_schema = {
      body_parts = schema.body_parts,
      variants = schema.variants,
      cache_timestamp = os.time(),
    },
    last_validated = os.time(),
    validation_result = result.result,
    layer_status = result.layer_status or {},
  }
  blueprint.writeAnimationData(spr, animData)

  local animations = schema.animations or {}
  local sprFileName = app.fs.fileName(spr.filename)
  local found = false
  for i, anim in ipairs(animations) do
    if anim.name == animName then
      animations[i].file = sprFileName
      animations[i].status = result.result == "fail" and "invalid" or "valid"
      found = true
      break
    end
  end
  if not found then
    table.insert(animations, {
      name = animName,
      file = sprFileName,
      status = result.result == "fail" and "invalid" or "valid"
    })
  end
  schema.animations = animations
  blueprint.writeBlueprintSchema(bpSprite, schema)
  bpSprite:save()
  bpSprite:close()

  app.alert("Registered '" .. animName .. "' to " .. charName .. " blueprint.")
end

return blueprint
