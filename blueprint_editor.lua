local blueprint = require 'blueprint'

local blueprintEditor = {}

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function parseList(value, fallback)
  local text = trim(value)
  if text == "" then text = fallback or "" end
  text = text:gsub("[\r\n;]+", ",")

  local out = {}
  local seen = {}
  for item in string.gmatch(text, "([^,]+)") do
    local name = trim(item)
    if name ~= "" and not seen[name] then
      out[#out + 1] = name
      seen[name] = true
    end
  end
  return out
end

local function makeVariants(variantText, stateText)
  local variants = {
    { id = "variant_base", name = "base", type = "variant", required = true },
  }

  for _, name in ipairs(parseList(variantText, "")) do
    if name ~= "base" then
      variants[#variants + 1] = {
        name = name,
        type = "variant",
        required = false,
      }
    end
  end

  for _, name in ipairs(parseList(stateText, "")) do
    if name ~= "base" then
      variants[#variants + 1] = {
        name = name,
        type = "state",
        required = false,
      }
    end
  end

  return variants
end

local function cloneVariants(variants)
  local out = {}
  for i, variant in ipairs(variants or {}) do
    out[i] = {
      id = variant.id,
      name = variant.name,
      type = variant.type,
      required = variant.required,
    }
  end
  return out
end

local function makeBodyParts(partsText, slotsText, variants)
  local bodyParts = {}
  local slots = parseList(slotsText, "default")

  for _, partName in ipairs(parseList(partsText, "")) do
    local partSlots = {}
    for _, slotName in ipairs(slots) do
      partSlots[#partSlots + 1] = {
        name = slotName,
        required = true,
        variants = cloneVariants(variants),
      }
    end

    bodyParts[#bodyParts + 1] = {
      name = partName,
      sort_order = #bodyParts + 1,
      slots = partSlots,
    }
  end

  return bodyParts
end

local function makeAnimations(text)
  local animations = {}
  for _, name in ipairs(parseList(text, "")) do
    animations[#animations + 1] = {
      name = name,
      file = "",
      status = "missing",
    }
  end
  return animations
end

local function hasNamedItem(list, name)
  for _, item in ipairs(list or {}) do
    if item.name == name then return true end
  end
  return false
end

local function removeNamedItem(list, name)
  for i = #list, 1, -1 do
    if list[i].name == name then
      table.remove(list, i)
      return true
    end
  end
  return false
end

local function cloneVariant(variant)
  return {
    id = variant.id,
    name = variant.name,
    type = variant.type,
    required = variant.required,
    applies_to = variant.applies_to,
  }
end

local function cloneSlot(slot)
  local variants = {}
  for _, variant in ipairs(slot.variants or {}) do
    variants[#variants + 1] = cloneVariant(variant)
  end
  return {
    id = slot.id,
    name = slot.name,
    required = slot.required,
    variants = variants,
  }
end

local function defaultSlot()
  return {
    id = "slot_default",
    name = "default",
    required = true,
    variants = {
      { id = "variant_base", name = "base", type = "variant", required = true },
    },
  }
end

local function slotTemplates(schema)
  local slots = {}
  local seen = {}
  for _, part in ipairs(schema.body_parts or {}) do
    for _, slot in ipairs(part.slots or {}) do
      if not seen[slot.name] then
        slots[#slots + 1] = cloneSlot(slot)
        seen[slot.name] = true
      end
    end
  end
  if #slots == 0 then slots[1] = defaultSlot() end
  return slots
end

local function partOptions(schema)
  local options = { "all parts" }
  for _, part in ipairs(schema.body_parts or {}) do
    options[#options + 1] = part.name
  end
  return options
end

local function partNames(schema)
  local options = {}
  for _, part in ipairs(schema.body_parts or {}) do
    options[#options + 1] = part.name
  end
  return options
end

local function variantNames(schema)
  local names = {}
  local seen = {}
  for _, part in ipairs(schema.body_parts or {}) do
    for _, slot in ipairs(part.slots or {}) do
      for _, variant in ipairs(slot.variants or {}) do
        if variant.name ~= "base" and not seen[variant.name] then
          names[#names + 1] = variant.name
          seen[variant.name] = true
        end
      end
    end
  end
  return names
end

local function animationNames(schema)
  local names = {}
  for _, anim in ipairs(schema.animations or {}) do
    names[#names + 1] = anim.name
  end
  return names
end

local function slotOptions(schema)
  local options = { "all slots" }
  local seen = {}
  for _, slot in ipairs(slotTemplates(schema)) do
    if not seen[slot.name] then
      options[#options + 1] = slot.name
      seen[slot.name] = true
    end
  end
  return options
end

local function countSlots(schema)
  local seen = {}
  local count = 0
  for _, part in ipairs(schema.body_parts or {}) do
    for _, slot in ipairs(part.slots or {}) do
      if not seen[slot.name] then
        seen[slot.name] = true
        count = count + 1
      end
    end
  end
  return count
end

local function countVariants(schema, variantType)
  local seen = {}
  local count = 0
  for _, part in ipairs(schema.body_parts or {}) do
    for _, slot in ipairs(part.slots or {}) do
      for _, variant in ipairs(slot.variants or {}) do
        if variant.type == variantType and variant.name ~= "base" and not seen[variant.name] then
          seen[variant.name] = true
          count = count + 1
        end
      end
    end
  end
  return count
end

local function schemaSummary(schema)
  return tostring(#(schema.body_parts or {})) .. " parts, " ..
         tostring(countSlots(schema)) .. " slots, " ..
         tostring(countVariants(schema, "variant")) .. " outfits, " ..
         tostring(countVariants(schema, "state")) .. " effects"
end

local function applyBlueprintSchema(sprite, schema)
  schema = blueprint.normalizeSchema(schema)
  app.transaction(function()
    blueprint.writeBlueprintSchema(sprite, schema)
    blueprint.ensureLayerStructure(sprite, schema, { rename = false })
  end)
  return blueprint.readBlueprintSchema(sprite)
end

local TEMPLATE_OPTIONS = {
  "Humanoid (6 parts)",
  "Simple Humanoid (3 parts)",
  "Upper Body (3 parts)",
  "Custom",
}

local TEMPLATE_PARTS = {
  ["Humanoid (6 parts)"] = "head, torso, left_arm, right_arm, left_leg, right_leg",
  ["Simple Humanoid (3 parts)"] = "head, torso, legs",
  ["Upper Body (3 parts)"] = "head, torso, arms",
  ["Custom"] = "",
}

local TEMPLATE_ANIMATIONS = "idle, walk, run"

function blueprintEditor.showCreateDialog()
  local dlg = Dialog{ title = "Create Character Blueprint" }

  dlg:combobox{
    id = "template",
    label = "Template:",
    options = TEMPLATE_OPTIONS,
    onchange = function()
      local selected = dlg.data.template or "Custom"
      dlg:modify{ id = "bodyParts", text = TEMPLATE_PARTS[selected] or "" }
      dlg:modify{ id = "animations", text = selected ~= "Custom" and TEMPLATE_ANIMATIONS or "" }
    end,
  }
  dlg:entry{ id = "characterName", label = "Character:", text = "" }
  dlg:entry{ id = "bodyParts", label = "Parts:", text = TEMPLATE_PARTS[TEMPLATE_OPTIONS[1]] }
  dlg:entry{ id = "regularVariants", label = "Outfits:", text = "armor" }
  dlg:entry{ id = "stateVariants", label = "Effects:", text = "" }
  dlg:entry{ id = "animations", label = "Animations:", text = TEMPLATE_ANIMATIONS }
  dlg:file{
    id = "saveDir",
    label = "Save In:",
    filename = "",
    open = false,
    save = false,
    filetypes = {},
  }
  dlg:button{ id = "create", text = "Create" }
  dlg:button{ id = "cancel", text = "Cancel" }

  dlg:show()

  if not dlg.data.create then return end

  local charName = trim(dlg.data.characterName)
  if charName == "" then
    app.alert("Character name is required.")
    return
  end

  local variants = makeVariants(dlg.data.regularVariants, dlg.data.stateVariants)
  local bodyParts = makeBodyParts(dlg.data.bodyParts, "default", variants)
  if #bodyParts == 0 then
    app.alert("At least one body part is required.")
    return
  end

  local schema = blueprint.normalizeSchema({
    character_name = charName,
    body_parts = bodyParts,
    animations = makeAnimations(dlg.data.animations),
  })

  local spr = Sprite(64, 64, ColorMode.RGB)
  blueprint.ensureLayerStructure(spr, schema)

  if spr.layers[1] and spr.layers[1].name == "Layer 1" then
    spr.layers[1].name = "Reference"
  end

  blueprint.writeBlueprintSchema(spr, schema)

  local saveDir = dlg.data.saveDir
  if saveDir and saveDir ~= "" then
    local dir = app.fs.filePath(saveDir)
    if dir == "" then dir = saveDir end
    app.fs.makeAllDirectories(dir)
    local path = app.fs.joinPath(dir, charName .. "_blueprint.ase")
    spr:saveAs(path)
    blueprint.rememberBlueprint(path)
  end

  app.alert("Blueprint created: " .. charName)
end

function blueprintEditor.showEditDialog()
  local spr = app.activeSprite
  if not spr or not blueprint.isBlueprint(spr) then
    app.alert("Open a CharacterForge blueprint first.")
    return
  end

  local schema = blueprint.readBlueprintSchema(spr)
  local dlg = Dialog{ title = "Edit Blueprint" }

  local hasSlotSection = countSlots(schema) > 1

  local function refresh()
    schema = blueprint.readBlueprintSchema(spr)
    dlg:modify{ id = "summary", text = schemaSummary(schema) }
    dlg:modify{ id = "removePart", options = partNames(schema) }
    if hasSlotSection then
      dlg:modify{ id = "targetPart", options = partOptions(schema) }
      dlg:modify{ id = "removeSlot", options = slotOptions(schema) }
    end
    dlg:modify{ id = "targetSlot", options = slotOptions(schema) }
    dlg:modify{ id = "removeVariant", options = variantNames(schema) }
    dlg:modify{ id = "removeAnimation", options = animationNames(schema) }
  end

  local function commit()
    schema = applyBlueprintSchema(spr, schema)
    refresh()
  end

  dlg:label{ id = "summary", text = schemaSummary(schema) }

  dlg:separator{ text = "Parts" }
  dlg:entry{ id = "newParts", label = "Add:", text = "" }
  dlg:button{
    id = "addParts",
    text = "Add Part(s)",
    onclick = function()
      local templates = slotTemplates(schema)
      for _, name in ipairs(parseList(dlg.data.newParts, "")) do
        if not hasNamedItem(schema.body_parts, name) then
          local slots = {}
          for _, slot in ipairs(templates) do
            slots[#slots + 1] = cloneSlot(slot)
          end
          schema.body_parts[#schema.body_parts + 1] = {
            name = name,
            sort_order = #schema.body_parts + 1,
            slots = slots,
          }
        end
      end
      dlg:modify{ id = "newParts", text = "" }
      commit()
    end
  }
  dlg:combobox{ id = "removePart", label = "Remove:", options = partNames(schema) }
  dlg:button{
    id = "removeParts",
    text = "Remove Part",
    onclick = function()
      local name = dlg.data.removePart
      if not name or name == "" then return end
      local confirm = app.alert{
        title = "Remove Part",
        text = "Remove '" .. name .. "' from all slots?",
        buttons = { "Remove", "Cancel" },
      }
      if confirm == 1 then
        removeNamedItem(schema.body_parts, name)
        commit()
      end
    end
  }

  if countSlots(schema) > 1 then
    dlg:separator{ text = "Slots" }
    dlg:combobox{ id = "targetPart", label = "Part:", options = partOptions(schema) }
    dlg:entry{ id = "newSlots", label = "Add:", text = "" }
    dlg:button{
      id = "addSlots",
      text = "Add Slot(s)",
      onclick = function()
        local target = dlg.data.targetPart or "all parts"
        for _, part in ipairs(schema.body_parts or {}) do
          if target == "all parts" or target == part.name then
            for _, slotName in ipairs(parseList(dlg.data.newSlots, "")) do
              if not hasNamedItem(part.slots, slotName) then
                part.slots[#part.slots + 1] = {
                  name = slotName,
                  required = true,
                  variants = {
                    { id = "variant_base", name = "base", type = "variant", required = true },
                  },
                }
              end
            end
          end
        end
        dlg:modify{ id = "newSlots", text = "" }
        commit()
      end
    }
    dlg:combobox{ id = "removeSlot", label = "Remove:", options = slotOptions(schema) }
    dlg:button{
      id = "removeSlots",
      text = "Remove Slot",
      onclick = function()
        local name = dlg.data.removeSlot
        if not name or name == "" or name == "all slots" then return end
        local target = dlg.data.targetPart or "all parts"
        local confirm = app.alert{
          title = "Remove Slot",
          text = "Remove slot '" .. name .. "' from " .. target .. "?",
          buttons = { "Remove", "Cancel" },
        }
        if confirm == 1 then
          for _, part in ipairs(schema.body_parts or {}) do
            if target == "all parts" or target == part.name then
              removeNamedItem(part.slots, name)
            end
          end
          commit()
        end
      end
    }
  end

  dlg:separator{ text = "Outfits And Effects" }
  dlg:combobox{ id = "targetSlot", label = "Slot:", options = slotOptions(schema) }
  dlg:entry{ id = "newVariants", label = "Add:", text = "" }
  dlg:combobox{ id = "variantKind", label = "Kind:", options = { "outfit", "effect" } }
  dlg:check{ id = "required", label = "Required", selected = false }
  dlg:button{
    id = "addVariants",
    text = "Add",
    onclick = function()
      local target = dlg.data.targetSlot or "all slots"
      local kindLabel = dlg.data.variantKind or "outfit"
      local kind = kindLabel == "effect" and "state" or "variant"
      for _, part in ipairs(schema.body_parts or {}) do
        for _, slot in ipairs(part.slots or {}) do
          if target == "all slots" or target == slot.name then
            for _, name in ipairs(parseList(dlg.data.newVariants, "")) do
              if name ~= "base" and not hasNamedItem(slot.variants, name) then
                slot.variants[#slot.variants + 1] = {
                  name = name,
                  type = kind,
                  required = dlg.data.required and true or false,
                }
              end
            end
          end
        end
      end
      dlg:modify{ id = "newVariants", text = "" }
      commit()
    end
  }
  dlg:combobox{ id = "removeVariant", label = "Remove:", options = variantNames(schema) }
  dlg:button{
    id = "removeVariants",
    text = "Remove Outfit/Effect",
    onclick = function()
      local name = dlg.data.removeVariant
      if not name or name == "" then return end
      local target = dlg.data.targetSlot or "all slots"
      local confirm = app.alert{
        title = "Remove Outfit/Effect",
        text = "Remove '" .. name .. "' from " .. target .. "?",
        buttons = { "Remove", "Cancel" },
      }
      if confirm == 1 then
        for _, part in ipairs(schema.body_parts or {}) do
          for _, slot in ipairs(part.slots or {}) do
            if target == "all slots" or target == slot.name then
              removeNamedItem(slot.variants, name)
            end
          end
        end
        commit()
      end
    end
  }

  dlg:separator{ text = "Animations" }
  dlg:entry{ id = "newAnimations", label = "Add:", text = "" }
  dlg:button{
    id = "addAnimations",
    text = "Add Animation(s)",
    onclick = function()
      for _, name in ipairs(parseList(dlg.data.newAnimations, "")) do
        if not hasNamedItem(schema.animations, name) then
          schema.animations[#schema.animations + 1] = {
            name = name,
            file = "",
            status = "missing",
          }
        end
      end
      dlg:modify{ id = "newAnimations", text = "" }
      commit()
    end
  }
  dlg:combobox{ id = "removeAnimation", label = "Remove:", options = animationNames(schema) }
  dlg:button{
    id = "removeAnimations",
    text = "Remove Animation",
    onclick = function()
      local name = dlg.data.removeAnimation
      if not name or name == "" then return end
      local confirm = app.alert{
        title = "Remove Animation",
        text = "Remove animation '" .. name .. "'?",
        buttons = { "Remove", "Cancel" },
      }
      if confirm == 1 then
        removeNamedItem(schema.animations, name)
        commit()
      end
    end
  }

  dlg:separator()
  dlg:button{ id = "close", text = "Close", onclick = function() dlg:close() end }
  dlg:show{ wait = false }
end

return blueprintEditor
