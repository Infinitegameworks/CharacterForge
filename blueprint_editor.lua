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

local function findNamedItem(list, name)
  for _, item in ipairs(list or {}) do
    if item.name == name then return item end
  end
  return nil
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

local function defaultSlot(variants)
  local vars = {{ id = "variant_base", name = "base", type = "variant", required = true }}
  for _, v in ipairs(variants or {}) do
    if v.name ~= "base" then vars[#vars + 1] = cloneVariant(v) end
  end
  return {
    id = "slot_default",
    name = "default",
    required = true,
    variants = vars,
  }
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

local function partVariantNames(part, variantType)
  local names = {}
  local seen = {}
  for _, slot in ipairs(part.slots or {}) do
    for _, v in ipairs(slot.variants or {}) do
      if v.name ~= "base" and (not variantType or v.type == variantType) and not seen[v.name] then
        names[#names + 1] = v.name
        seen[v.name] = true
      end
    end
  end
  return names
end

local function partVariantNamesForRemove(part)
  local names = {}
  local seen = {}
  for _, slot in ipairs(part.slots or {}) do
    for _, v in ipairs(slot.variants or {}) do
      if v.name ~= "base" and not seen[v.name] then
        local label = v.name .. " (" .. (v.type == "state" and "effect" or "outfit") .. ")"
        names[#names + 1] = v.name
        seen[v.name] = true
      end
    end
  end
  return names
end

local function partSummary(part)
  local outfits = partVariantNames(part, "variant")
  local effects = partVariantNames(part, "state")
  local text = #outfits .. " outfit(s)"
  if #effects > 0 then text = text .. ", " .. #effects .. " effect(s)" end
  return text
end

local function schemaSummary(schema)
  local parts = #(schema.body_parts or {})
  local anims = #(schema.animations or {})
  return tostring(parts) .. " parts, " .. tostring(anims) .. " animations"
end

local function applyBlueprintSchema(sprite, schema)
  schema = blueprint.normalizeSchema(schema)
  app.transaction(function()
    blueprint.writeBlueprintSchema(sprite, schema)
    blueprint.ensureLayerStructure(sprite, schema, { rename = false })
  end)
  return blueprint.readBlueprintSchema(sprite)
end

-- ─── Templates ──────────────────────────────────────────

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

-- ─── Create Dialog (Two-Step) ───────────────────────────

function blueprintEditor.showCreateDialog()
  local dlg = Dialog{ title = "Create Character — Step 1: Structure" }

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
  dlg:entry{ id = "defaultOutfits", label = "Default Outfits:", text = "" }
  dlg:entry{ id = "defaultEffects", label = "Default Effects:", text = "" }
  dlg:entry{ id = "animations", label = "Animations:", text = TEMPLATE_ANIMATIONS }
  dlg:file{
    id = "saveDir",
    label = "Save In:",
    filename = "",
    open = false,
    save = false,
    filetypes = {},
  }
  dlg:button{ id = "next", text = "Next: Per-Part Setup" }
  dlg:button{ id = "createNow", text = "Create With Defaults" }
  dlg:button{ id = "cancel", text = "Cancel" }

  dlg:show()

  if dlg.data.cancel or (not dlg.data.next and not dlg.data.createNow) then return end

  local charName = trim(dlg.data.characterName)
  if charName == "" then
    app.alert("Character name is required.")
    return
  end

  local partNameList = parseList(dlg.data.bodyParts, "")
  if #partNameList == 0 then
    app.alert("At least one body part is required.")
    return
  end

  local defaultOutfits = parseList(dlg.data.defaultOutfits, "")
  local defaultEffects = parseList(dlg.data.defaultEffects, "")
  local animText = dlg.data.animations
  local saveDir = dlg.data.saveDir

  local bodyParts = {}
  for _, partName in ipairs(partNameList) do
    local variants = {{ id = "variant_base", name = "base", type = "variant", required = true }}
    for _, name in ipairs(defaultOutfits) do
      variants[#variants + 1] = { name = name, type = "variant", required = false }
    end
    for _, name in ipairs(defaultEffects) do
      variants[#variants + 1] = { name = name, type = "state", required = false }
    end
    bodyParts[#bodyParts + 1] = {
      name = partName,
      sort_order = #bodyParts + 1,
      slots = { defaultSlot(variants) },
    }
  end

  if dlg.data.next then
    blueprintEditor._showStep2(charName, bodyParts, animText, saveDir)
  else
    blueprintEditor._finishCreate(charName, bodyParts, animText, saveDir)
  end
end

function blueprintEditor._showStep2(charName, bodyParts, animText, saveDir)
  local dlg = Dialog{ title = "Create Character — Step 2: Per-Part Outfits" }

  local function selectedPart()
    local name = dlg.data.partSelect
    return findNamedItem(bodyParts, name)
  end

  local function refreshPartView()
    local part = selectedPart()
    if part then
      dlg:modify{ id = "partInfo", text = part.name .. ": " .. partSummary(part) }
      dlg:modify{ id = "currentOutfits", text = "Outfits: " .. table.concat(partVariantNames(part, "variant"), ", ") }
      dlg:modify{ id = "currentEffects", text = "Effects: " .. table.concat(partVariantNames(part, "state"), ", ") }
      dlg:modify{ id = "removeChoice", options = partVariantNamesForRemove(part) }
    end
  end

  local partNameOptions = {}
  for _, part in ipairs(bodyParts) do
    partNameOptions[#partNameOptions + 1] = part.name
  end

  dlg:combobox{
    id = "partSelect",
    label = "Part:",
    options = partNameOptions,
    onchange = function() refreshPartView() end,
  }
  dlg:label{ id = "partInfo", text = "" }
  dlg:label{ id = "currentOutfits", text = "" }
  dlg:label{ id = "currentEffects", text = "" }

  dlg:separator{ text = "Add to This Part" }
  dlg:entry{ id = "addNames", label = "Names:", text = "" }
  dlg:combobox{ id = "addKind", label = "Kind:", options = { "outfit", "effect" } }
  dlg:button{
    id = "addBtn",
    text = "Add",
    onclick = function()
      local part = selectedPart()
      if not part then return end
      local kindLabel = dlg.data.addKind or "outfit"
      local kind = kindLabel == "effect" and "state" or "variant"
      for _, name in ipairs(parseList(dlg.data.addNames, "")) do
        if name ~= "base" then
          for _, slot in ipairs(part.slots or {}) do
            if not hasNamedItem(slot.variants, name) then
              slot.variants[#slot.variants + 1] = {
                name = name,
                type = kind,
                required = false,
              }
            end
          end
        end
      end
      dlg:modify{ id = "addNames", text = "" }
      refreshPartView()
    end
  }

  dlg:separator{ text = "Remove from This Part" }
  dlg:combobox{ id = "removeChoice", label = "Remove:", options = {} }
  dlg:button{
    id = "removeBtn",
    text = "Remove",
    onclick = function()
      local part = selectedPart()
      if not part then return end
      local name = dlg.data.removeChoice
      if not name or name == "" then return end
      for _, slot in ipairs(part.slots or {}) do
        removeNamedItem(slot.variants, name)
      end
      refreshPartView()
    end
  }

  dlg:separator()
  dlg:button{ id = "create", text = "Create Blueprint" }
  dlg:button{ id = "back", text = "Back" }

  refreshPartView()
  dlg:show()

  if dlg.data.back then
    blueprintEditor.showCreateDialog()
    return
  end

  if not dlg.data.create then return end

  blueprintEditor._finishCreate(charName, bodyParts, animText, saveDir)
end

function blueprintEditor._finishCreate(charName, bodyParts, animText, saveDir)
  local schema = blueprint.normalizeSchema({
    character_name = charName,
    body_parts = bodyParts,
    animations = makeAnimations(animText),
  })

  local spr = Sprite(64, 64, ColorMode.RGB)
  blueprint.ensureLayerStructure(spr, schema)

  if spr.layers[1] and spr.layers[1].name == "Layer 1" then
    spr.layers[1].name = "Reference"
  end

  blueprint.writeBlueprintSchema(spr, schema)

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

-- ─── Edit Dialog (Part-Scoped) ──────────────────────────

function blueprintEditor.showEditDialog()
  local spr = app.activeSprite
  if not spr or not blueprint.isBlueprint(spr) then
    app.alert("Open a CharacterForge blueprint first.")
    return
  end

  local schema = blueprint.readBlueprintSchema(spr)
  local dlg = Dialog{ title = "Edit: " .. (schema.character_name or "Blueprint") }

  local function partNames()
    local names = {}
    for _, part in ipairs(schema.body_parts or {}) do
      names[#names + 1] = part.name
    end
    return names
  end

  local function animNames()
    local names = {}
    for _, anim in ipairs(schema.animations or {}) do
      names[#names + 1] = anim.name
    end
    return names
  end

  local function selectedPart()
    local name = dlg.data.editPart
    return findNamedItem(schema.body_parts, name)
  end

  local function commit()
    schema = applyBlueprintSchema(spr, schema)
  end

  local function refreshPartView()
    local part = selectedPart()
    if part then
      dlg:modify{ id = "partDetail", text = part.name .. ": " .. partSummary(part) }
      local outfitList = partVariantNames(part, "variant")
      local effectList = partVariantNames(part, "state")
      dlg:modify{ id = "outfitList", text = #outfitList > 0 and table.concat(outfitList, ", ") or "(none)" }
      dlg:modify{ id = "effectList", text = #effectList > 0 and table.concat(effectList, ", ") or "(none)" }
      dlg:modify{ id = "removeFromPart", options = partVariantNamesForRemove(part) }
    else
      dlg:modify{ id = "partDetail", text = "No part selected" }
      dlg:modify{ id = "outfitList", text = "" }
      dlg:modify{ id = "effectList", text = "" }
      dlg:modify{ id = "removeFromPart", options = {} }
    end
  end

  local function refreshAll()
    dlg:modify{ id = "summary", text = schemaSummary(schema) }
    dlg:modify{ id = "editPart", options = partNames() }
    dlg:modify{ id = "removePart", options = partNames() }
    dlg:modify{ id = "removeAnimation", options = animNames() }
    refreshPartView()
  end

  dlg:label{ id = "summary", text = schemaSummary(schema) }

  -- ── Parts section ──
  dlg:separator{ text = "Parts" }
  dlg:entry{ id = "newParts", label = "Add:", text = "" }
  dlg:button{
    id = "addParts",
    text = "Add Part(s)",
    onclick = function()
      for _, name in ipairs(parseList(dlg.data.newParts, "")) do
        if not hasNamedItem(schema.body_parts, name) then
          schema.body_parts[#schema.body_parts + 1] = {
            name = name,
            sort_order = #schema.body_parts + 1,
            slots = { defaultSlot() },
          }
        end
      end
      dlg:modify{ id = "newParts", text = "" }
      commit()
      refreshAll()
    end
  }
  dlg:combobox{ id = "removePart", label = "Remove:", options = partNames() }
  dlg:button{
    id = "removePartBtn",
    text = "Remove Part",
    onclick = function()
      local name = dlg.data.removePart
      if not name or name == "" then return end
      if app.alert{ title = "Remove Part", text = "Remove '" .. name .. "'?", buttons = { "Remove", "Cancel" } } == 1 then
        removeNamedItem(schema.body_parts, name)
        commit()
        refreshAll()
      end
    end
  }

  -- ── Per-part variant editing ──
  dlg:separator{ text = "Edit Part" }
  dlg:combobox{
    id = "editPart",
    label = "Part:",
    options = partNames(),
    onchange = function() refreshPartView() end,
  }
  dlg:label{ id = "partDetail", text = "" }
  dlg:label{ id = "outfitList", text = "" }
  dlg:label{ id = "effectList", text = "" }

  dlg:entry{ id = "addToPart", label = "Add:", text = "" }
  dlg:combobox{ id = "addKind", label = "Kind:", options = { "outfit", "effect" } }
  dlg:button{
    id = "addToPartBtn",
    text = "Add to Part",
    onclick = function()
      local part = selectedPart()
      if not part then app.alert("Select a part first."); return end
      local kindLabel = dlg.data.addKind or "outfit"
      local kind = kindLabel == "effect" and "state" or "variant"
      for _, name in ipairs(parseList(dlg.data.addToPart, "")) do
        if name ~= "base" then
          for _, slot in ipairs(part.slots or {}) do
            if not hasNamedItem(slot.variants, name) then
              slot.variants[#slot.variants + 1] = {
                name = name,
                type = kind,
                required = false,
              }
            end
          end
        end
      end
      dlg:modify{ id = "addToPart", text = "" }
      commit()
      refreshAll()
    end
  }

  dlg:combobox{ id = "removeFromPart", label = "Remove:", options = {} }
  dlg:button{
    id = "removeFromPartBtn",
    text = "Remove from Part",
    onclick = function()
      local part = selectedPart()
      if not part then return end
      local name = dlg.data.removeFromPart
      if not name or name == "" then return end
      for _, slot in ipairs(part.slots or {}) do
        removeNamedItem(slot.variants, name)
      end
      commit()
      refreshAll()
    end
  }

  -- ── Bulk add to all parts ──
  dlg:separator{ text = "All Parts (Bulk)" }
  dlg:entry{ id = "bulkAdd", label = "Add:", text = "" }
  dlg:combobox{ id = "bulkKind", label = "Kind:", options = { "outfit", "effect" } }
  dlg:button{
    id = "bulkAddBtn",
    text = "Add to All Parts",
    onclick = function()
      local kindLabel = dlg.data.bulkKind or "outfit"
      local kind = kindLabel == "effect" and "state" or "variant"
      for _, part in ipairs(schema.body_parts or {}) do
        for _, name in ipairs(parseList(dlg.data.bulkAdd, "")) do
          if name ~= "base" then
            for _, slot in ipairs(part.slots or {}) do
              if not hasNamedItem(slot.variants, name) then
                slot.variants[#slot.variants + 1] = {
                  name = name,
                  type = kind,
                  required = false,
                }
              end
            end
          end
        end
      end
      dlg:modify{ id = "bulkAdd", text = "" }
      commit()
      refreshAll()
    end
  }

  -- ── Animations ──
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
      refreshAll()
    end
  }
  dlg:combobox{ id = "removeAnimation", label = "Remove:", options = animNames() }
  dlg:button{
    id = "removeAnimationBtn",
    text = "Remove Animation",
    onclick = function()
      local name = dlg.data.removeAnimation
      if not name or name == "" then return end
      if app.alert{ title = "Remove Animation", text = "Remove '" .. name .. "'?", buttons = { "Remove", "Cancel" } } == 1 then
        removeNamedItem(schema.animations, name)
        commit()
        refreshAll()
      end
    end
  }

  dlg:separator()
  dlg:button{ id = "close", text = "Close", onclick = function() dlg:close() end }

  refreshAll()
  dlg:show{ wait = false }
end

return blueprintEditor
