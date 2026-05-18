local blueprint = require 'blueprint'

local validator = {}

local function addIssue(list, message)
  list[#list + 1] = message
end

local function countSet(set)
  local count = 0
  for _ in pairs(set or {}) do count = count + 1 end
  return count
end

local function collectFrameSet(layer, frames)
  frames = frames or {}
  if not layer then return frames end

  if layer.cels then
    for _, cel in ipairs(layer.cels) do
      if cel.image then
        local frameNumber = nil
        if cel.frame and cel.frame.frameNumber then
          frameNumber = cel.frame.frameNumber
        elseif cel.frameNumber then
          frameNumber = cel.frameNumber
        end
        if frameNumber then frames[frameNumber] = true end
      end
    end
  end

  if layer.isGroup then
    for _, child in ipairs(layer.layers or {}) do
      collectFrameSet(child, frames)
    end
  end

  return frames
end

local function activeFrameCount(layer)
  return countSet(collectFrameSet(layer, {}))
end

local function isVariantAbsent(layer)
  if not layer then return false end
  local props = layer.properties(blueprint.PK)
  return props and props.intentionally_absent
end

local function baseVariantForSlot(slot)
  for _, variant in ipairs(slot.variants or {}) do
    if variant.name == "base" or variant.id == "variant_base" or variant.id == "base" then
      return variant
    end
  end
  return slot.variants and slot.variants[1] or nil
end

local function markStatus(status, level)
  if level == "fail" then
    status.status = "fail"
  elseif level == "warn" and status.status ~= "fail" then
    status.status = "warn"
  elseif not status.status then
    status.status = "pass"
  end
end

local function validateLayerName(kindLabel, layer, expectedName, errors, warnings)
  if not layer then return end
  local kind, id = blueprint.getLayerIdentity(layer)
  if id and layer.name ~= expectedName then
    addIssue(warnings, kindLabel .. " linked by ID is named '" .. layer.name .. "'; expected '" .. expectedName .. "'")
  elseif not id and layer.name ~= expectedName then
    addIssue(errors, kindLabel .. " name mismatch: expected '" .. expectedName .. "', found '" .. layer.name .. "'")
  end
  if kind and layer.isGroup == false then
    addIssue(errors, kindLabel .. " '" .. expectedName .. "' must be a group")
  end
end

local function findCaseMismatch(layers, expectedName)
  local insensitive = blueprint.findLayerByNameInsensitive(layers, expectedName)
  if insensitive and insensitive.name ~= expectedName then return insensitive end
  return nil
end

function validator.validate(sprite, schema)
  local errors = {}
  local warnings = {}
  local layerStatus = {}
  local normalized = blueprint.normalizeSchema(schema)

  for _, part in ipairs(normalized.body_parts or {}) do
    local partStatus = {
      id = part.id,
      part = part.name,
      status = "pass",
      base_frames = 0,
      variants_complete = {},
      slots = {},
    }

    local partLayer = blueprint.findLayerByIdOrName(sprite.layers, "part", part.id, part.name)
    if not partLayer then
      local mismatch = findCaseMismatch(sprite.layers, part.name)
      if mismatch then
        addIssue(errors, "Name mismatch: expected '" .. part.name .. "', found '" .. mismatch.name .. "'")
      else
        addIssue(errors, "Missing required body part group: '" .. part.name .. "'")
      end
      markStatus(partStatus, "fail")
      layerStatus[#layerStatus + 1] = partStatus
    elseif not partLayer.isGroup then
      addIssue(errors, "'" .. part.name .. "' must be a layer group, not an image layer")
      markStatus(partStatus, "fail")
      layerStatus[#layerStatus + 1] = partStatus
    else
      validateLayerName("Body part", partLayer, part.name, errors, warnings)

      for _, slot in ipairs(part.slots or {}) do
        local slotStatus = {
          id = slot.id,
          slot = slot.name,
          status = "pass",
          base_frames = 0,
          variants = {},
        }

        local slotLayer = blueprint.findLayerByIdOrName(partLayer.layers, "slot", slot.id, slot.name)
        local searchLayer = slotLayer
        if not searchLayer and (slot.id == "slot_default" or slot.name == "default") then
          searchLayer = partLayer
        end

        if not searchLayer then
          local mismatch = findCaseMismatch(partLayer.layers, slot.name)
          if mismatch then
            addIssue(errors, "Name mismatch in '" .. part.name .. "': expected slot '" .. slot.name .. "', found '" .. mismatch.name .. "'")
          else
            addIssue(errors, "Missing required slot '" .. slot.name .. "' in body part '" .. part.name .. "'")
          end
          markStatus(slotStatus, "fail")
          markStatus(partStatus, "fail")
        else
          if slotLayer then
            validateLayerName("Slot in '" .. part.name .. "'", slotLayer, slot.name, errors, warnings)
          end

          local baseVariant = baseVariantForSlot(slot)
          local baseLayer = baseVariant and blueprint.findLayerByIdOrName(searchLayer.layers, "variant", baseVariant.id, baseVariant.name)
          local baseFrames = activeFrameCount(baseLayer)
          slotStatus.base_frames = baseFrames
          if partStatus.base_frames == 0 then partStatus.base_frames = baseFrames end

          for _, variant in ipairs(slot.variants or {}) do
            local variantStatus = {
              id = variant.id,
              variant = variant.name,
              type = variant.type,
              required = variant.required and true or false,
              status = "pass",
              frames = 0,
              absent = false,
            }

            local variantLayer = blueprint.findLayerByIdOrName(searchLayer.layers, "variant", variant.id, variant.name)
            if not variantLayer then
              local mismatch = findCaseMismatch(searchLayer.layers, variant.name)
              if mismatch then
                addIssue(errors, "Name mismatch in '" .. part.name .. "/" .. slot.name .. "': expected variant '" .. variant.name .. "', found '" .. mismatch.name .. "'")
                markStatus(variantStatus, "fail")
                markStatus(slotStatus, "fail")
                markStatus(partStatus, "fail")
              elseif variant.required or variant.name == "base" then
                addIssue(errors, "Missing required variant '" .. variant.name .. "' in '" .. part.name .. "/" .. slot.name .. "'")
                markStatus(variantStatus, "fail")
                markStatus(slotStatus, "fail")
                markStatus(partStatus, "fail")
              else
                addIssue(warnings, "Missing optional variant '" .. variant.name .. "' in '" .. part.name .. "/" .. slot.name .. "'")
                markStatus(variantStatus, "warn")
                markStatus(slotStatus, "warn")
                markStatus(partStatus, "warn")
              end
            else
              validateLayerName("Variant in '" .. part.name .. "/" .. slot.name .. "'", variantLayer, variant.name, errors, warnings)
              local frames = activeFrameCount(variantLayer)
              variantStatus.frames = frames
              variantStatus.absent = isVariantAbsent(variantLayer)

              if variantStatus.absent then
                variantStatus.status = "absent"
              elseif frames > 0 then
                partStatus.variants_complete[#partStatus.variants_complete + 1] = variant.name
              end

              if baseVariant and variant.id ~= baseVariant.id and not variantStatus.absent then
                if frames ~= baseFrames and (frames > 0 or baseFrames > 0) then
                  addIssue(errors,
                    "Frame count mismatch in '" .. part.name .. "/" .. slot.name .. "': " ..
                    "variant '" .. variant.name .. "' has " .. tostring(frames) ..
                    " active frame(s) but base has " .. tostring(baseFrames))
                  markStatus(variantStatus, "fail")
                  markStatus(slotStatus, "fail")
                  markStatus(partStatus, "fail")
                end
              end
            end

            slotStatus.variants[#slotStatus.variants + 1] = variantStatus
          end
        end

        partStatus.slots[#partStatus.slots + 1] = slotStatus
      end
      layerStatus[#layerStatus + 1] = partStatus
    end
  end

  validator.validateUnexpectedLayers(sprite, normalized, warnings)

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

function validator.validateUnexpectedLayers(sprite, schema, warnings)
  local normalized = blueprint.normalizeSchema(schema)
  local expectedParts = {}
  for _, part in ipairs(normalized.body_parts or {}) do
    expectedParts[part.id] = true
    expectedParts[part.name] = true
  end

  for _, layer in ipairs(sprite.layers or {}) do
    if layer.isGroup and layer.name ~= "Reference" and layer.name ~= "Hitbox" then
      local _, id = blueprint.getLayerIdentity(layer)
      if not expectedParts[id] and not expectedParts[layer.name] then
        addIssue(warnings, "Unexpected top-level group '" .. layer.name .. "'")
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
  for _, layer in ipairs(layers or {}) do
    local kind, id = blueprint.getLayerIdentity(layer)
    table.insert(parts, string.rep(".", depth) .. layer.name .. ":" .. tostring(kind) .. ":" .. tostring(id) .. (layer.isGroup and "/" or ""))
    if layer.isGroup and layer.layers then
      validator._hashLayers(layer.layers, parts, depth + 1)
    end
  end
end

function validator.findLayerByName(layers, name)
  return blueprint.findLayerByName(layers, name)
end

function validator.findLayerByNameInsensitive(layers, name)
  return blueprint.findLayerByNameInsensitive(layers, name)
end

function validator.countCels(layer)
  return activeFrameCount(layer)
end

return validator
