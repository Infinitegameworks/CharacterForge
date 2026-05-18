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
    animations[#animations + 1] = { name = name, file = "", status = "missing" }
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

local function partSummary(part)
  local outfits = partVariantNames(part, "variant")
  local effects = partVariantNames(part, "state")
  local text = #outfits .. " outfit(s)"
  if #effects > 0 then text = text .. ", " .. #effects .. " effect(s)" end
  return text
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

-- ─── Create: Step 1 ────────────────────────────────────

function blueprintEditor.showCreateDialog()
  local dlg = Dialog{ title = "Create Character — Step 1: Structure" }

  dlg:combobox{
    id = "template", label = "Template:", options = TEMPLATE_OPTIONS,
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
  dlg:file{ id = "saveDir", label = "Save In:", filename = "", open = false, save = false, filetypes = {} }
  dlg:button{ id = "next", text = "Next: Per-Part Setup" }
  dlg:button{ id = "createNow", text = "Create With Defaults" }
  dlg:button{ id = "cancel", text = "Cancel" }
  dlg:show()

  if dlg.data.cancel or (not dlg.data.next and not dlg.data.createNow) then return end

  local charName = trim(dlg.data.characterName)
  if charName == "" then app.alert("Character name is required."); return end

  local partNameList = parseList(dlg.data.bodyParts, "")
  if #partNameList == 0 then app.alert("At least one body part is required."); return end

  local defaultOutfits = parseList(dlg.data.defaultOutfits, "")
  local defaultEffects = parseList(dlg.data.defaultEffects, "")

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
      name = partName, sort_order = #bodyParts + 1,
      slots = { defaultSlot(variants) },
    }
  end

  if dlg.data.next then
    blueprintEditor._showStep2(charName, bodyParts, dlg.data.animations, dlg.data.saveDir)
  else
    blueprintEditor._finishCreate(charName, bodyParts, dlg.data.animations, dlg.data.saveDir)
  end
end

-- ─── Create: Step 2 (per-part, rebuilds on every action) ─

function blueprintEditor._showStep2(charName, bodyParts, animText, saveDir)
  local selectedName = bodyParts[1] and bodyParts[1].name or ""

  while true do
    local part = findNamedItem(bodyParts, selectedName)
    local partNames = {}
    for _, p in ipairs(bodyParts) do partNames[#partNames + 1] = p.name end

    local outfits = part and table.concat(partVariantNames(part, "variant"), ", ") or ""
    local effects = part and table.concat(partVariantNames(part, "state"), ", ") or ""
    local removeOpts = part and partVariantNames(part) or {}

    local title = "Step 2: " .. (part and part.name or "")
    if part then title = title .. " — " .. partSummary(part) end
    local dlg = Dialog{ title = title }

    dlg:combobox{ id = "partSelect", label = "Part:", option = selectedName, options = partNames }
    dlg:button{ id = "switchPart", text = "Switch Part", onclick = function()
      selectedName = dlg.data.partSelect or selectedName; dlg:close()
    end }

    dlg:separator{ text = "Outfits: " .. (outfits ~= "" and outfits or "(none)") }
    if effects ~= "" then dlg:label{ text = "Effects: " .. effects } end

    dlg:entry{ id = "addNames", label = "Add:", text = "" }
    dlg:combobox{ id = "addKind", label = "Kind:", options = { "outfit", "effect" } }
    dlg:button{ id = "addBtn", text = "Add", onclick = function()
      if not part then return end
      local kind = (dlg.data.addKind or "outfit") == "effect" and "state" or "variant"
      for _, name in ipairs(parseList(dlg.data.addNames, "")) do
        if name ~= "base" then
          for _, slot in ipairs(part.slots or {}) do
            if not hasNamedItem(slot.variants, name) then
              slot.variants[#slot.variants + 1] = { name = name, type = kind, required = false }
            end
          end
        end
      end
      dlg:close()
    end }

    if #removeOpts > 0 then
      dlg:combobox{ id = "removeChoice", label = "Remove:", options = removeOpts }
      dlg:button{ id = "removeBtn", text = "Remove", onclick = function()
        if not part then return end
        local name = dlg.data.removeChoice
        if name and name ~= "" then
          for _, slot in ipairs(part.slots or {}) do removeNamedItem(slot.variants, name) end
        end
        dlg:close()
      end }
    end

    dlg:separator()
    dlg:button{ id = "create", text = "Create Blueprint" }
    dlg:button{ id = "back", text = "Back" }
    dlg:show()

    if dlg.data.create then
      blueprintEditor._finishCreate(charName, bodyParts, animText, saveDir)
      return
    elseif dlg.data.back then
      blueprintEditor.showCreateDialog()
      return
    elseif not dlg.data.addBtn and not dlg.data.removeBtn and not dlg.data.switchPart then
      return
    end
  end
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

-- ─── Edit: Hub ──────────────────────────────────────────

local function countLinkedAnimations(schema)
  local count = 0
  for _, anim in ipairs(schema.animations or {}) do
    if anim.file and anim.file ~= "" then count = count + 1 end
  end
  return count
end

function blueprintEditor.showEditDialog()
  local spr = app.activeSprite
  if not spr or not blueprint.isBlueprint(spr) then
    app.alert("Open a CharacterForge blueprint first.")
    return
  end

  local schemaBefore = blueprint.readBlueprintSchema(spr)
  local charName = schemaBefore.character_name or "Blueprint"
  local partCount = #(schemaBefore.body_parts or {})
  local animCount = #(schemaBefore.animations or {})

  local dlg = Dialog{ title = "Edit: " .. charName .. " (" .. partCount .. " parts, " .. animCount .. " anims)" }
  dlg:button{ id = "editParts", text = "Edit Parts", onclick = function() dlg:close() end }
  dlg:button{ id = "editOutfits", text = "Edit Outfits / Effects", onclick = function() dlg:close() end }
  dlg:button{ id = "editAnimations", text = "Edit Animations", onclick = function() dlg:close() end }
  dlg:button{ id = "cancel", text = "Close" }
  dlg:show()

  if dlg.data.editParts then
    blueprintEditor._editParts(spr)
  elseif dlg.data.editOutfits then
    blueprintEditor._editOutfits(spr)
  elseif dlg.data.editAnimations then
    blueprintEditor._editAnimations(spr)
  end

  local schemaAfter = blueprint.readBlueprintSchema(spr)
  if schemaAfter then
    local linked = countLinkedAnimations(schemaAfter)
    if linked > 0 then
      local beforeSig = ""
      local afterSig = ""
      for _, part in ipairs(schemaBefore.body_parts or {}) do
        beforeSig = beforeSig .. part.name .. ":"
        for _, slot in ipairs(part.slots or {}) do
          for _, v in ipairs(slot.variants or {}) do beforeSig = beforeSig .. v.name .. "," end
        end
      end
      for _, part in ipairs(schemaAfter.body_parts or {}) do
        afterSig = afterSig .. part.name .. ":"
        for _, slot in ipairs(part.slots or {}) do
          for _, v in ipairs(slot.variants or {}) do afterSig = afterSig .. v.name .. "," end
        end
      end
      if beforeSig ~= afterSig then
        app.alert(tostring(linked) .. " animation(s) use this blueprint. Open each and use 'Refresh from Blueprint' to update their structure.")
      end
    end
  end
end

-- ─── Edit: Parts ────────────────────────────────────────

function blueprintEditor._editParts(spr)
  while true do
    local schema = blueprint.readBlueprintSchema(spr)
    local partNames = {}
    for _, part in ipairs(schema.body_parts or {}) do
      partNames[#partNames + 1] = part.name .. " — " .. partSummary(part)
    end

    local dlg = Dialog{ title = "Edit Parts (" .. #partNames .. ")" }

    if #partNames > 0 then
      dlg:label{ text = table.concat(partNames, "\n") }
    end

    dlg:separator{ text = "Add" }
    dlg:entry{ id = "newParts", label = "Names:", text = "" }
    dlg:button{ id = "addBtn", text = "Add Part(s)", onclick = function() dlg:close() end }

    if #partNames > 0 then
      local names = {}
      for _, part in ipairs(schema.body_parts or {}) do names[#names + 1] = part.name end
      dlg:separator{ text = "Remove" }
      dlg:combobox{ id = "removePart", label = "Part:", options = names }
      dlg:button{ id = "removeBtn", text = "Remove Part", onclick = function() dlg:close() end }
    end

    dlg:separator()
    dlg:button{ id = "back", text = "Back" }
    dlg:show()

    if dlg.data.addBtn then
      for _, name in ipairs(parseList(dlg.data.newParts, "")) do
        if not hasNamedItem(schema.body_parts, name) then
          schema.body_parts[#schema.body_parts + 1] = {
            name = name, sort_order = #schema.body_parts + 1,
            slots = { defaultSlot() },
          }
        end
      end
      applyBlueprintSchema(spr, schema)
    elseif dlg.data.removeBtn then
      local name = dlg.data.removePart
      if name and name ~= "" then
        if app.alert{ title = "Remove", text = "Remove '" .. name .. "'?", buttons = { "Remove", "Cancel" } } == 1 then
          removeNamedItem(schema.body_parts, name)
          applyBlueprintSchema(spr, schema)
        end
      end
    else
      blueprintEditor.showEditDialog()
      return
    end
  end
end

-- ─── Edit: Outfits / Effects ────────────────────────────

function blueprintEditor._editOutfits(spr)
  local selectedPartName = nil

  while true do
    local schema = blueprint.readBlueprintSchema(spr)
    local partNames = {}
    for _, part in ipairs(schema.body_parts or {}) do partNames[#partNames + 1] = part.name end

    if not selectedPartName or not findNamedItem(schema.body_parts, selectedPartName) then
      selectedPartName = partNames[1] or ""
    end

    local part = findNamedItem(schema.body_parts, selectedPartName)
    local outfits = part and partVariantNames(part, "variant") or {}
    local effects = part and partVariantNames(part, "state") or {}
    local removeOpts = part and partVariantNames(part) or {}

    local title = "Outfits / Effects: " .. selectedPartName
    if part then title = title .. " — " .. partSummary(part) end
    local dlg = Dialog{ title = title }

    dlg:combobox{ id = "partSelect", label = "Part:", option = selectedPartName, options = partNames }
    dlg:button{ id = "switchPart", text = "Switch Part", onclick = function()
      selectedPartName = dlg.data.partSelect or selectedPartName; dlg:close()
    end }

    dlg:separator{ text = "Outfits: " .. (#outfits > 0 and table.concat(outfits, ", ") or "(none)") }
    if #effects > 0 then
      dlg:label{ text = "Effects: " .. table.concat(effects, ", ") }
    else
      dlg:label{ text = "Effects: (none)" }
    end

    dlg:entry{ id = "addNames", label = "Add:", text = "" }
    dlg:combobox{ id = "addKind", label = "Kind:", options = { "outfit", "effect" } }
    dlg:button{ id = "addBtn", text = "Add to " .. selectedPartName, onclick = function() dlg:close() end }

    if #removeOpts > 0 then
      dlg:combobox{ id = "removeChoice", label = "Remove:", options = removeOpts }
      dlg:button{ id = "removeBtn", text = "Remove from " .. selectedPartName, onclick = function() dlg:close() end }
    end

    dlg:separator{ text = "Bulk" }
    dlg:entry{ id = "bulkNames", label = "Add:", text = "" }
    dlg:combobox{ id = "bulkKind", label = "Kind:", options = { "outfit", "effect" } }
    dlg:button{ id = "bulkBtn", text = "Add to All Parts", onclick = function() dlg:close() end }

    dlg:separator()
    dlg:button{ id = "back", text = "Back" }
    dlg:show()

    if dlg.data.addBtn then
      if part then
        local kind = (dlg.data.addKind or "outfit") == "effect" and "state" or "variant"
        for _, name in ipairs(parseList(dlg.data.addNames, "")) do
          if name ~= "base" then
            for _, slot in ipairs(part.slots or {}) do
              if not hasNamedItem(slot.variants, name) then
                slot.variants[#slot.variants + 1] = { name = name, type = kind, required = false }
              end
            end
          end
        end
        applyBlueprintSchema(spr, schema)
      end
    elseif dlg.data.removeBtn then
      if part then
        local name = dlg.data.removeChoice
        if name and name ~= "" then
          for _, slot in ipairs(part.slots or {}) do removeNamedItem(slot.variants, name) end
          applyBlueprintSchema(spr, schema)
        end
      end
    elseif dlg.data.bulkBtn then
      local kind = (dlg.data.bulkKind or "outfit") == "effect" and "state" or "variant"
      for _, p in ipairs(schema.body_parts or {}) do
        for _, name in ipairs(parseList(dlg.data.bulkNames, "")) do
          if name ~= "base" then
            for _, slot in ipairs(p.slots or {}) do
              if not hasNamedItem(slot.variants, name) then
                slot.variants[#slot.variants + 1] = { name = name, type = kind, required = false }
              end
            end
          end
        end
      end
      applyBlueprintSchema(spr, schema)
    elseif dlg.data.switchPart then
      -- loop continues with new part
    else
      blueprintEditor.showEditDialog()
      return
    end
  end
end

-- ─── Edit: Animations ───────────────────────────────────

function blueprintEditor._editAnimations(spr)
  while true do
    local schema = blueprint.readBlueprintSchema(spr)
    local animNames = {}
    local animLabels = {}
    for _, anim in ipairs(schema.animations or {}) do
      animNames[#animNames + 1] = anim.name
      local status = anim.status or "missing"
      animLabels[#animLabels + 1] = anim.name .. " [" .. status .. "]"
    end

    local dlg = Dialog{ title = "Edit Animations (" .. #animNames .. ")" }

    if #animLabels > 0 then
      dlg:label{ text = table.concat(animLabels, "\n") }
    end

    dlg:separator{ text = "Add" }
    dlg:entry{ id = "newAnims", label = "Names:", text = "" }
    dlg:button{ id = "addBtn", text = "Add Animation(s)", onclick = function() dlg:close() end }

    if #animNames > 0 then
      dlg:separator{ text = "Remove" }
      dlg:combobox{ id = "removeAnim", label = "Animation:", options = animNames }
      dlg:button{ id = "removeBtn", text = "Remove Animation", onclick = function() dlg:close() end }
    end

    dlg:separator()
    dlg:button{ id = "back", text = "Back" }
    dlg:show()

    if dlg.data.addBtn then
      for _, name in ipairs(parseList(dlg.data.newAnims, "")) do
        if not hasNamedItem(schema.animations, name) then
          schema.animations[#schema.animations + 1] = { name = name, file = "", status = "missing" }
        end
      end
      applyBlueprintSchema(spr, schema)
    elseif dlg.data.removeBtn then
      local name = dlg.data.removeAnim
      if name and name ~= "" then
        if app.alert{ title = "Remove", text = "Remove '" .. name .. "'?", buttons = { "Remove", "Cancel" } } == 1 then
          removeNamedItem(schema.animations, name)
          applyBlueprintSchema(spr, schema)
        end
      end
    else
      blueprintEditor.showEditDialog()
      return
    end
  end
end

return blueprintEditor
