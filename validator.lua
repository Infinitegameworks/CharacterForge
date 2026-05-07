local validator = {}

function validator.validate(sprite, schema)
  local errors = {}
  local warnings = {}
  local layerStatus = {}

  validator.validateRequiredLayers(sprite, schema, errors)
  validator.validateRequiredVariants(sprite, schema, errors, warnings, layerStatus)
  validator.validateFrameCounts(sprite, schema, errors, layerStatus)
  validator.validateNames(sprite, schema, errors)

  local result = "pass"
  if #errors > 0 then
    result = "fail"
  elseif #warnings > 0 then
    result = "warn"
  end

  return {
    result = result,
    errors = errors,
    warnings = warnings,
    layer_status = layerStatus,
  }
end

function validator.validateRequiredLayers(sprite, schema, errors)
  if not schema or not schema.body_parts then return end

  for _, part in ipairs(schema.body_parts) do
    local found = validator.findLayerByName(sprite.layers, part.name)
    if not found then
      table.insert(errors, "Missing required body part group: '" .. part.name .. "'")
    elseif not found.isGroup then
      table.insert(errors, "'" .. part.name .. "' must be a layer group, not an image layer")
    end
  end
end

function validator.validateRequiredVariants(sprite, schema, errors, warnings, layerStatus)
  if not schema or not schema.body_parts or not schema.variants then return end

  for _, part in ipairs(schema.body_parts) do
    local partLayer = validator.findLayerByName(sprite.layers, part.name)
    if not partLayer or not partLayer.isGroup then goto continue end

    local status = { part = part.name, base_frames = 0, variants_complete = {} }

    for _, variant in ipairs(schema.variants) do
      local variantLayer = validator.findLayerByName(partLayer.layers, variant.name)
      if not variantLayer then
        if variant.name == "base" or variant.required then
          table.insert(errors, "Missing required variant '" .. variant.name .. "' in body part '" .. part.name .. "'")
        elseif variant.type == "equipment" then
          table.insert(warnings, "Missing equipment variant '" .. variant.name .. "' in body part '" .. part.name .. "'")
        end
      else
        table.insert(status.variants_complete, variant.name)
      end
    end

    table.insert(layerStatus, status)
    ::continue::
  end
end

function validator.validateFrameCounts(sprite, schema, errors, layerStatus)
  if not schema or not schema.body_parts or not schema.variants then return end

  for _, part in ipairs(schema.body_parts) do
    local partLayer = validator.findLayerByName(sprite.layers, part.name)
    if not partLayer or not partLayer.isGroup then goto continue end

    local baseLayer = validator.findLayerByName(partLayer.layers, "base")
    if not baseLayer then goto continue end

    local baseFrames = validator.countCels(baseLayer)

    for i, ls in ipairs(layerStatus) do
      if ls.part == part.name then
        layerStatus[i].base_frames = baseFrames
        break
      end
    end

    for _, variant in ipairs(schema.variants) do
      if variant.name == "base" then goto nextVariant end

      local variantLayer = validator.findLayerByName(partLayer.layers, variant.name)
      if not variantLayer then goto nextVariant end

      local variantFrames = validator.countCels(variantLayer)
      if variantFrames ~= baseFrames and variantFrames > 0 then
        table.insert(errors,
          "Frame count mismatch in '" .. part.name .. "': " ..
          "variant '" .. variant.name .. "' has " .. variantFrames ..
          " frames but base has " .. baseFrames)
      end

      ::nextVariant::
    end
    ::continue::
  end
end

function validator.validateNames(sprite, schema, errors)
  if not schema or not schema.body_parts then return end

  for _, part in ipairs(schema.body_parts) do
    local found = validator.findLayerByNameInsensitive(sprite.layers, part.name)
    if found and found.name ~= part.name then
      table.insert(errors,
        "Name mismatch: expected '" .. part.name ..
        "', found '" .. found.name .. "' — layer names are case-sensitive")
    end

    if found and found.isGroup and schema.variants then
      for _, variant in ipairs(schema.variants) do
        local varFound = validator.findLayerByNameInsensitive(found.layers, variant.name)
        if varFound and varFound.name ~= variant.name then
          table.insert(errors,
            "Name mismatch in '" .. part.name .. "': expected variant '" ..
            variant.name .. "', found '" .. varFound.name .. "' — layer names are case-sensitive")
        end
      end
    end
  end
end

function validator.buildLayerTreeHash(sprite)
  if not sprite then return "" end
  local parts = {}
  validator._hashLayers(sprite.layers, parts, 0)
  return table.concat(parts, "|")
end

function validator._hashLayers(layers, parts, depth)
  for _, layer in ipairs(layers) do
    table.insert(parts, string.rep(".", depth) .. layer.name .. (layer.isGroup and "/" or ""))
    if layer.isGroup and layer.layers then
      validator._hashLayers(layer.layers, parts, depth + 1)
    end
  end
end

function validator.findLayerByName(layers, name)
  for _, layer in ipairs(layers) do
    if layer.name == name then
      return layer
    end
  end
  return nil
end

function validator.findLayerByNameInsensitive(layers, name)
  local lower = string.lower(name)
  for _, layer in ipairs(layers) do
    if string.lower(layer.name) == lower then
      return layer
    end
  end
  return nil
end

function validator.countCels(layer)
  if not layer then return 0 end
  local count = 0
  if layer.cels then
    for _, cel in ipairs(layer.cels) do
      if cel.image then
        count = count + 1
      end
    end
  end
  if layer.isGroup and layer.layers then
    for _, child in ipairs(layer.layers) do
      count = count + validator.countCels(child)
    end
  end
  return count
end

return validator
