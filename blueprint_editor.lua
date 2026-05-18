local blueprint = require 'blueprint'
local dialogUtils = require 'dialog_utils'

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

local function hasString(list, value)
  for _, item in ipairs(list or {}) do
    if item == value then return true end
  end
  return false
end

local function removeString(list, value)
  for i = #list, 1, -1 do
    if list[i] == value then
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

local DIRECTION_PRESETS = {
  { name = "8-Direction", dirs = { "front", "front_right", "right", "back_right", "back", "back_left", "left", "front_left" } },
  { name = "4-Direction", dirs = { "front", "right", "back", "left" } },
  { name = "Front / Back", dirs = { "front", "back" } },
  { name = "Front Only", dirs = { "front" } },
  { name = "Custom", dirs = {} },
}

local ALL_DIRECTIONS = { "front", "front_right", "right", "back_right", "back", "back_left", "left", "front_left" }

local function showDirectionSetup(currentDirs)
  local selected = {}
  for _, d in ipairs(currentDirs or {}) do selected[d] = true end

  local presetNames = {}
  for _, p in ipairs(DIRECTION_PRESETS) do presetNames[#presetNames + 1] = p.name end

  local dlg = Dialog{ title = "Direction Setup" }

  dlg:combobox{
    id = "preset", label = "Preset:", options = presetNames,
    onchange = function()
      local preset = dlg.data.preset or "Custom"
      for _, p in ipairs(DIRECTION_PRESETS) do
        if p.name == preset and preset ~= "Custom" then
          for _, d in ipairs(ALL_DIRECTIONS) do
            selected[d] = false
            pcall(function() dlg:modify{ id = "dir_" .. d, selected = false } end)
          end
          for _, d in ipairs(p.dirs) do
            selected[d] = true
            pcall(function() dlg:modify{ id = "dir_" .. d, selected = true } end)
          end
          break
        end
      end
    end,
  }

  dlg:separator{ text = "Directions" }
  for _, d in ipairs(ALL_DIRECTIONS) do
    dlg:check{ id = "dir_" .. d, label = d, selected = selected[d] == true }
  end

  dlg:separator()
  dlg:button{ id = "ok", text = "OK" }
  dlg:button{ id = "cancel", text = "Cancel" }
  dlg:show()

  if not dlg.data.ok then return currentDirs end

  local result = {}
  for _, d in ipairs(ALL_DIRECTIONS) do
    if dlg.data["dir_" .. d] then result[#result + 1] = d end
  end
  return result
end

-- ─── Create: Step 1 ────────────────────────────────────

function blueprintEditor.showCreateDialog()
  local charName = ""
  local parts = parseList(TEMPLATE_PARTS[TEMPLATE_OPTIONS[1]], "")
  local outfits = {}
  local effects = {}
  local anims = parseList(TEMPLATE_ANIMATIONS, "")
  local directions = {}
  local useDirections = false
  local saveDir = ""

  while true do
    local dlg = Dialog{ title = "Create Character" }

    dlg:combobox{
      id = "template", label = "Template:", options = TEMPLATE_OPTIONS,
      onchange = function()
        local selected = dlg.data.template or "Custom"
        if TEMPLATE_PARTS[selected] then
          parts = parseList(TEMPLATE_PARTS[selected], "")
          anims = selected ~= "Custom" and parseList(TEMPLATE_ANIMATIONS, "") or anims
          dlg:close()
        end
      end,
    }
    dlg:entry{ id = "characterName", label = "Character:", text = charName }

    dlg:separator{ text = "Parts (" .. #parts .. ")" }
    dialogUtils.scrollableList(dlg, "partsList", 340, math.min(56, math.max(28, #parts * 14 + 12)), parts, "(none)")
    dlg:entry{ id = "addPart", label = "Name:", text = "" }
    dlg:button{ id = "addPartBtn", text = "Add Part", onclick = function() dlg:close() end }
    if #parts > 0 then
      dlg:combobox{ id = "removePart", label = "Remove:", options = parts }
      dlg:button{ id = "removePartBtn", text = "Remove Part", onclick = function() dlg:close() end }
    end

    dlg:separator{ text = "Default Outfits (" .. #outfits .. ")" }
    dialogUtils.scrollableList(dlg, "outfitsList", 340, math.min(42, math.max(28, #outfits * 14 + 12)), outfits, "(none)")
    dlg:entry{ id = "addOutfit", label = "Name:", text = "" }
    dlg:button{ id = "addOutfitBtn", text = "Add Outfit", onclick = function() dlg:close() end }
    if #outfits > 0 then
      dlg:combobox{ id = "removeOutfit", label = "Remove:", options = outfits }
      dlg:button{ id = "removeOutfitBtn", text = "Remove Outfit", onclick = function() dlg:close() end }
    end

    dlg:separator{ text = "Default Effects (" .. #effects .. ")" }
    dialogUtils.scrollableList(dlg, "effectsList", 340, math.min(42, math.max(28, #effects * 14 + 12)), effects, "(none)")
    dlg:entry{ id = "addEffect", label = "Name:", text = "" }
    dlg:button{ id = "addEffectBtn", text = "Add Effect", onclick = function() dlg:close() end }
    if #effects > 0 then
      dlg:combobox{ id = "removeEffect", label = "Remove:", options = effects }
      dlg:button{ id = "removeEffectBtn", text = "Remove Effect", onclick = function() dlg:close() end }
    end

    dlg:separator{ text = "Animations (" .. #anims .. ")" }
    dialogUtils.scrollableList(dlg, "animsList", 340, math.min(56, math.max(28, #anims * 14 + 12)), anims, "(none)")
    dlg:entry{ id = "addAnim", label = "Name:", text = "" }
    dlg:button{ id = "addAnimBtn", text = "Add Animation", onclick = function() dlg:close() end }
    if #anims > 0 then
      dlg:combobox{ id = "removeAnim", label = "Remove:", options = anims }
      dlg:button{ id = "removeAnimBtn", text = "Remove Animation", onclick = function() dlg:close() end }
    end

    dlg:separator{ text = "Directions" }
    dlg:check{ id = "useDirections", label = "Include Directions", selected = useDirections }
    if useDirections and #directions > 0 then
      dlg:label{ text = table.concat(directions, ", ") }
    end
    dlg:button{ id = "setupDirsBtn", text = "Setup Directions", onclick = function() dlg:close() end }

    dlg:separator()
    dlg:file{ id = "saveDir", label = "Save In:", filename = saveDir, open = false, save = false, filetypes = {} }
    dlg:button{ id = "next", text = "Next: Per-Part Setup" }
    dlg:button{ id = "createNow", text = "Create With Defaults" }
    dlg:button{ id = "cancel", text = "Cancel" }
    dlg:show()

    charName = trim(dlg.data.characterName or charName)
    saveDir = dlg.data.saveDir or saveDir
    useDirections = dlg.data.useDirections or false

    if dlg.data.setupDirsBtn then
      directions = showDirectionSetup(directions)
      if #directions > 0 then useDirections = true end
    elseif dlg.data.addPartBtn then
      local name = trim(dlg.data.addPart)
      if name ~= "" and not hasString(parts, name) then
        parts[#parts + 1] = name
      end
    elseif dlg.data.removePartBtn then
      local name = dlg.data.removePart
      if name then removeString(parts, name) end
    elseif dlg.data.addOutfitBtn then
      local name = trim(dlg.data.addOutfit)
      if name ~= "" and name ~= "base" and not hasString(outfits, name) then
        outfits[#outfits + 1] = name
      end
    elseif dlg.data.removeOutfitBtn then
      local name = dlg.data.removeOutfit
      if name then removeString(outfits, name) end
    elseif dlg.data.addEffectBtn then
      local name = trim(dlg.data.addEffect)
      if name ~= "" and name ~= "base" and not hasString(effects, name) then
        effects[#effects + 1] = name
      end
    elseif dlg.data.removeEffectBtn then
      local name = dlg.data.removeEffect
      if name then removeString(effects, name) end
    elseif dlg.data.addAnimBtn then
      local name = trim(dlg.data.addAnim)
      if name ~= "" and not hasString(anims, name) then
        anims[#anims + 1] = name
      end
    elseif dlg.data.removeAnimBtn then
      local name = dlg.data.removeAnim
      if name then removeString(anims, name) end
    elseif dlg.data.next or dlg.data.createNow then
      if charName == "" then app.alert("Character name is required.")
      elseif #parts == 0 then app.alert("At least one body part is required.")
      else
        local bodyParts = {}
        for _, partName in ipairs(parts) do
          local variants = {{ id = "variant_base", name = "base", type = "variant", required = true }}
          for _, name in ipairs(outfits) do
            variants[#variants + 1] = { name = name, type = "variant", required = false }
          end
          for _, name in ipairs(effects) do
            variants[#variants + 1] = { name = name, type = "state", required = false }
          end
          bodyParts[#bodyParts + 1] = {
            name = partName, sort_order = #bodyParts + 1,
            slots = { defaultSlot(variants) },
          }
        end
        local finalDirs = useDirections and directions or {}
        local animText = table.concat(anims, ", ")
        if dlg.data.next then
          blueprintEditor._showStep2(charName, bodyParts, animText, saveDir, finalDirs)
        else
          blueprintEditor._finishCreate(charName, bodyParts, animText, saveDir, finalDirs)
        end
        return
      end
    else
      return
    end
  end
end

-- ─── Create: Step 2 (per-part, rebuilds on every action) ─

function blueprintEditor._showStep2(charName, bodyParts, animText, saveDir, directions)
  local selectedName = bodyParts[1] and bodyParts[1].name or ""

  while true do
    local part = findNamedItem(bodyParts, selectedName)
    local partNames = {}
    for _, p in ipairs(bodyParts) do partNames[#partNames + 1] = p.name end

    local outfitNames = part and partVariantNames(part, "variant") or {}
    local effectNames = part and partVariantNames(part, "state") or {}
    local removeOpts = part and partVariantNames(part) or {}

    local title = "Step 2: " .. (part and part.name or "")
    if part then title = title .. " — " .. partSummary(part) end
    local dlg = Dialog{ title = title }

    dlg:combobox{ id = "partSelect", label = "Part:", option = selectedName, options = partNames }
    dlg:button{ id = "switchPart", text = "Switch Part", onclick = function()
      selectedName = dlg.data.partSelect or selectedName; dlg:close()
    end }

    local allVars = {}
    for _, name in ipairs(outfitNames) do allVars[#allVars + 1] = name .. " (outfit)" end
    for _, name in ipairs(effectNames) do allVars[#allVars + 1] = name .. " (effect)" end
    dlg:separator{ text = "Outfits & Effects" }
    dialogUtils.scrollableList(dlg, "variantsList", 300, math.min(56, math.max(28, #allVars * 14 + 12)), allVars, "(base only)")

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
      blueprintEditor._finishCreate(charName, bodyParts, animText, saveDir, directions)
      return
    elseif dlg.data.back then
      blueprintEditor.showCreateDialog()
      return
    elseif not dlg.data.addBtn and not dlg.data.removeBtn and not dlg.data.switchPart then
      return
    end
  end
end

function blueprintEditor._finishCreate(charName, bodyParts, animText, saveDir, directions)
  directions = directions or {}
  local animNames = parseList(animText, "")
  local animations = {}
  if #directions > 0 then
    for _, animName in ipairs(animNames) do
      for _, dir in ipairs(directions) do
        animations[#animations + 1] = { name = animName, direction = dir, group = animName, file = "", status = "missing" }
      end
    end
  else
    for _, animName in ipairs(animNames) do
      animations[#animations + 1] = { name = animName, direction = "", group = "", file = "", status = "missing" }
    end
  end

  local schema = blueprint.normalizeSchema({
    character_name = charName,
    body_parts = bodyParts,
    directions = directions,
    animations = animations,
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

    dialogUtils.scrollableList(dlg, "partsList", 300, math.min(100, math.max(28, #partNames * 14 + 12)), partNames, "(no parts)")

    dlg:separator{ text = "Add" }
    dlg:entry{ id = "newParts", label = "Name:", text = "" }
    dlg:button{ id = "addBtn", text = "Add Part(s)", onclick = function() dlg:close() end }

    if #partNames > 0 then
      local names = {}
      for _, part in ipairs(schema.body_parts or {}) do names[#names + 1] = part.name end
      dlg:separator{ text = "Rename" }
      dlg:combobox{ id = "renamePart", label = "Part:", options = names }
      dlg:entry{ id = "renamePartTo", label = "New Name:", text = "" }
      dlg:button{ id = "renameBtn", text = "Rename Part", onclick = function() dlg:close() end }
      dlg:separator{ text = "Remove" }
      dlg:combobox{ id = "removePart", label = "Part:", options = names }
      dlg:button{ id = "removeBtn", text = "Remove Part", onclick = function() dlg:close() end }
    end

    dlg:separator()
    dlg:button{ id = "back", text = "Back" }
    dlg:show()

    if dlg.data.renameBtn then
      local oldName = dlg.data.renamePart
      local newName = trim(dlg.data.renamePartTo)
      if oldName and newName ~= "" and oldName ~= newName then
        local part = findNamedItem(schema.body_parts, oldName)
        if part and not hasNamedItem(schema.body_parts, newName) then
          part.name = newName
          applyBlueprintSchema(spr, schema)
        end
      end
    elseif dlg.data.addBtn then
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

    local allVariants = {}
    for _, name in ipairs(outfits) do allVariants[#allVariants + 1] = name .. " (outfit)" end
    for _, name in ipairs(effects) do allVariants[#allVariants + 1] = name .. " (effect)" end
    dlg:separator{ text = "Outfits & Effects" }
    dialogUtils.scrollableList(dlg, "variantsList", 320, math.min(70, math.max(28, #allVariants * 14 + 12)), allVariants, "(base only)")

    dlg:entry{ id = "addNames", label = "Add:", text = "" }
    dlg:combobox{ id = "addKind", label = "Kind:", options = { "outfit", "effect" } }
    dlg:button{ id = "addBtn", text = "Add to " .. selectedPartName, onclick = function() dlg:close() end }

    if #removeOpts > 0 then
      dlg:separator{ text = "Rename" }
      dlg:combobox{ id = "renameChoice", label = "Item:", options = removeOpts }
      dlg:entry{ id = "renameToName", label = "New Name:", text = "" }
      dlg:button{ id = "renameBtn", text = "Rename", onclick = function() dlg:close() end }
      dlg:separator{ text = "Remove" }
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
    elseif dlg.data.renameBtn then
      if part then
        local oldName = dlg.data.renameChoice
        local newName = trim(dlg.data.renameToName)
        if oldName and newName ~= "" and oldName ~= newName and newName ~= "base" then
          for _, slot in ipairs(part.slots or {}) do
            local v = findNamedItem(slot.variants, oldName)
            if v and not hasNamedItem(slot.variants, newName) then v.name = newName end
          end
          applyBlueprintSchema(spr, schema)
        end
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
    local groupNames = {}
    local groupSeen = {}
    for _, anim in ipairs(schema.animations or {}) do
      local dir = (anim.direction and anim.direction ~= "") and (" [" .. anim.direction .. "]") or ""
      local grp = (anim.group and anim.group ~= "") and (" {" .. anim.group .. "}") or ""
      animNames[#animNames + 1] = anim.name .. dir
      animLabels[#animLabels + 1] = anim.name .. dir .. grp .. " [" .. (anim.status or "missing") .. "]"
      if anim.group and anim.group ~= "" and not groupSeen[anim.group] then
        groupNames[#groupNames + 1] = anim.group
        groupSeen[anim.group] = true
      end
    end

    local dlg = Dialog{ title = "Edit Animations (" .. #animNames .. ")" }

    dialogUtils.scrollableList(dlg, "animsList", 300, math.min(100, math.max(28, #animLabels * 14 + 12)), animLabels, "(no animations)")

    dlg:separator{ text = "Add" }
    dlg:entry{ id = "newAnims", label = "Name:", text = "" }
    dlg:button{ id = "addBtn", text = "Add Animation(s)", onclick = function() dlg:close() end }

    if #animNames > 0 then
      dlg:separator{ text = "Rename" }
      dlg:combobox{ id = "renameAnim", label = "Animation:", options = animNames }
      dlg:entry{ id = "renameAnimTo", label = "New Name:", text = "" }
      dlg:button{ id = "renameBtn", text = "Rename Animation", onclick = function() dlg:close() end }
      dlg:separator{ text = "Remove" }
      dlg:combobox{ id = "removeAnim", label = "Animation:", options = animNames }
      dlg:button{ id = "removeBtn", text = "Remove Animation", onclick = function() dlg:close() end }

      dlg:separator{ text = "Groups" }
      dlg:combobox{ id = "groupAnim", label = "Animation:", options = animNames }
      local groupOpts = { "(ungrouped)" }
      for _, g in ipairs(groupNames) do groupOpts[#groupOpts + 1] = g end
      dlg:combobox{ id = "groupTarget", label = "Move to:", options = groupOpts }
      dlg:entry{ id = "newGroupName", label = "Or new group:", text = "" }
      dlg:button{ id = "groupBtn", text = "Set Group", onclick = function() dlg:close() end }
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
    elseif dlg.data.renameBtn then
      local oldName = dlg.data.renameAnim
      local newName = trim(dlg.data.renameAnimTo)
      if oldName and newName ~= "" and oldName ~= newName then
        local anim = findNamedItem(schema.animations, oldName)
        if anim and not hasNamedItem(schema.animations, newName) then
          anim.name = newName
          applyBlueprintSchema(spr, schema)
        end
      end
    elseif dlg.data.removeBtn then
      local name = dlg.data.removeAnim
      if name and name ~= "" then
        if app.alert{ title = "Remove", text = "Remove '" .. name .. "'?", buttons = { "Remove", "Cancel" } } == 1 then
          removeNamedItem(schema.animations, name)
          applyBlueprintSchema(spr, schema)
        end
      end
    elseif dlg.data.groupBtn then
      local animLabel = dlg.data.groupAnim
      local targetGroup = dlg.data.groupTarget or ""
      local newGroup = trim(dlg.data.newGroupName)
      if newGroup ~= "" then targetGroup = newGroup end
      if targetGroup == "(ungrouped)" then targetGroup = "" end
      if animLabel then
        for _, anim in ipairs(schema.animations or {}) do
          local dir = (anim.direction and anim.direction ~= "") and (" [" .. anim.direction .. "]") or ""
          if anim.name .. dir == animLabel then
            anim.group = targetGroup
            break
          end
        end
        applyBlueprintSchema(spr, schema)
      end
    else
      blueprintEditor.showEditDialog()
      return
    end
  end
end

-- ─── Edit Animation (modifies cached schema) ───────────

function blueprintEditor.showEditAnimationDialog()
  local spr = app.activeSprite
  if not spr or not blueprint.isAnimation(spr) then
    app.alert("Open a CharacterForge animation first.")
    return
  end

  local data = blueprint.readAnimationData(spr)
  if not data or not data.cached_schema then
    app.alert("No cached schema. Use Link Animation first.")
    return
  end

  local animPath = spr.filename
  local bpRef = data.blueprint_ref or ""
  local bpPath = data.blueprint_path or ""
  if animPath and animPath ~= "" and bpRef ~= "" then
    local dir = app.fs.filePath(animPath)
    if dir and dir ~= "" then
      local candidate = app.fs.joinPath(dir, bpRef)
      if app.fs.isFile(candidate) then bpPath = candidate end
    end
  end
  local hasBlueprintFile = bpPath ~= "" and app.fs.isFile(bpPath)

  local charName = data.character_name or "animation"
  local animName = data.animation_name or ""

  local dlg = Dialog{ title = "Edit Animation: " .. charName .. " / " .. animName }
  dlg:button{ id = "editOutfits", text = "Edit Outfits / Effects", onclick = function() dlg:close() end }
  dlg:button{ id = "editParts", text = "Edit Parts", onclick = function() dlg:close() end }
  if hasBlueprintFile then
    dlg:check{ id = "applyToBlueprint", label = "Apply to blueprint too", selected = false }
  end
  dlg:button{ id = "cancel", text = "Close" }
  dlg:show()

  local applyToBp = hasBlueprintFile and dlg.data.applyToBlueprint

  if dlg.data.editOutfits then
    blueprintEditor._editAnimOutfits(spr, data, applyToBp, bpPath)
  elseif dlg.data.editParts then
    blueprintEditor._editAnimParts(spr, data, applyToBp, bpPath)
  end
end

local function applyAnimSchema(animSprite, data, schema, applyToBp, bpPath)
  local normalized = blueprint.normalizeSchema(schema)
  app.transaction(function()
    blueprint.cacheSchemaInAnimation(animSprite, normalized)
    blueprint.ensureLayerStructure(animSprite, normalized, { rename = false })
  end)

  if applyToBp and bpPath and bpPath ~= "" and app.fs.isFile(bpPath) then
    local animPath = animSprite.filename
    pcall(function()
      app.open(bpPath)
      local bpSpr = app.activeSprite
      if bpSpr and blueprint.isBlueprint(bpSpr) then
        local bpSchema = blueprint.readBlueprintSchema(bpSpr)
        if bpSchema then
          bpSchema.body_parts = normalized.body_parts
          bpSchema.variants = normalized.variants
          applyBlueprintSchema(bpSpr, bpSchema)
        end
      end
      if animPath and animPath ~= "" then app.open(animPath) end
    end)
  end

  return blueprint.readAnimationData(animSprite)
end

function blueprintEditor._editAnimOutfits(animSprite, data, applyToBp, bpPath)
  local schema = data.cached_schema
  local selectedPartName = nil

  while true do
    local partNames = {}
    for _, part in ipairs(schema.body_parts or {}) do partNames[#partNames + 1] = part.name end
    if not selectedPartName or not findNamedItem(schema.body_parts, selectedPartName) then
      selectedPartName = partNames[1] or ""
    end

    local part = findNamedItem(schema.body_parts, selectedPartName)
    local outfits = part and partVariantNames(part, "variant") or {}
    local effects = part and partVariantNames(part, "state") or {}
    local removeOpts = part and partVariantNames(part) or {}

    local title = "Outfits: " .. selectedPartName
    if part then title = title .. " — " .. partSummary(part) end
    local dlg = Dialog{ title = title }

    dlg:combobox{ id = "partSelect", label = "Part:", option = selectedPartName, options = partNames }
    dlg:button{ id = "switchPart", text = "Switch Part", onclick = function()
      selectedPartName = dlg.data.partSelect or selectedPartName; dlg:close()
    end }

    local allVariants = {}
    for _, name in ipairs(outfits) do allVariants[#allVariants + 1] = name .. " (outfit)" end
    for _, name in ipairs(effects) do allVariants[#allVariants + 1] = name .. " (effect)" end
    dlg:separator{ text = "Outfits & Effects" }
    dialogUtils.scrollableList(dlg, "variantsList", 320, math.min(70, math.max(28, #allVariants * 14 + 12)), allVariants, "(base only)")

    dlg:entry{ id = "addNames", label = "Add:", text = "" }
    dlg:combobox{ id = "addKind", label = "Kind:", options = { "outfit", "effect" } }
    dlg:button{ id = "addBtn", text = "Add to " .. selectedPartName, onclick = function() dlg:close() end }

    if #removeOpts > 0 then
      dlg:combobox{ id = "removeChoice", label = "Remove:", options = removeOpts }
      dlg:button{ id = "removeBtn", text = "Remove from " .. selectedPartName, onclick = function() dlg:close() end }
    end

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
        data = applyAnimSchema(animSprite, data, schema, applyToBp, bpPath)
        schema = data.cached_schema
      end
    elseif dlg.data.removeBtn then
      if part then
        local name = dlg.data.removeChoice
        if name and name ~= "" then
          for _, slot in ipairs(part.slots or {}) do removeNamedItem(slot.variants, name) end
          data = applyAnimSchema(animSprite, data, schema, applyToBp, bpPath)
          schema = data.cached_schema
        end
      end
    elseif dlg.data.switchPart then
      -- loop rebuilds
    else
      blueprintEditor.showEditAnimationDialog()
      return
    end
  end
end

function blueprintEditor._editAnimParts(animSprite, data, applyToBp, bpPath)
  while true do
    local schema = data.cached_schema
    local partNames = {}
    for _, part in ipairs(schema.body_parts or {}) do
      partNames[#partNames + 1] = part.name .. " — " .. partSummary(part)
    end
    local partNameList = {}
    for _, part in ipairs(schema.body_parts or {}) do partNameList[#partNameList + 1] = part.name end

    local dlg = Dialog{ title = "Edit Parts (" .. #partNameList .. ")" }
    dialogUtils.scrollableList(dlg, "partsList", 300, math.min(100, math.max(28, #partNames * 14 + 12)), partNames, "(no parts)")

    dlg:separator{ text = "Add" }
    dlg:entry{ id = "newParts", label = "Name:", text = "" }
    dlg:button{ id = "addBtn", text = "Add Part(s)", onclick = function() dlg:close() end }

    if #partNameList > 0 then
      dlg:separator{ text = "Remove" }
      dlg:combobox{ id = "removePart", label = "Part:", options = partNameList }
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
      data = applyAnimSchema(animSprite, data, schema, applyToBp, bpPath)
    elseif dlg.data.removeBtn then
      local name = dlg.data.removePart
      if name and name ~= "" then
        if app.alert{ title = "Remove", text = "Remove '" .. name .. "'?", buttons = { "Remove", "Cancel" } } == 1 then
          removeNamedItem(schema.body_parts, name)
          data = applyAnimSchema(animSprite, data, schema, applyToBp, bpPath)
        end
      end
    else
      blueprintEditor.showEditAnimationDialog()
      return
    end
  end
end

return blueprintEditor
