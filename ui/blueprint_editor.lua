local blueprint = require("blueprint")

local blueprintEditor = {}

function blueprintEditor.showCreateDialog()
  local bodyParts = {}
  local variants = { { name = "base", type = "equipment", required = true } }
  local animations = {}

  local dlg = Dialog{ title = "Create Character Blueprint" }

  dlg:entry{ id = "characterName", label = "Character Name:", text = "" }
  dlg:separator{ text = "Body Parts" }
  dlg:entry{ id = "newPartName", label = "Part Name:", text = "" }
  dlg:button{
    id = "addPart",
    text = "Add Part",
    onclick = function()
      local name = dlg.data.newPartName
      if name and name ~= "" then
        table.insert(bodyParts, { name = name, sort_order = #bodyParts + 1 })
        local options = {}
        for _, p in ipairs(bodyParts) do
          table.insert(options, p.name)
        end
        dlg:modify{ id = "partsList", options = options }
        dlg:modify{ id = "newPartName", text = "" }
      end
    end
  }
  dlg:combobox{ id = "partsList", label = "Current Parts:", options = {} }
  dlg:button{
    id = "removePart",
    text = "Remove Selected",
    onclick = function()
      local selected = dlg.data.partsList
      if selected and selected ~= "" then
        for i, p in ipairs(bodyParts) do
          if p.name == selected then
            table.remove(bodyParts, i)
            break
          end
        end
        local options = {}
        for _, p in ipairs(bodyParts) do
          table.insert(options, p.name)
        end
        dlg:modify{ id = "partsList", options = options }
      end
    end
  }

  dlg:separator{ text = "Variants" }
  dlg:entry{ id = "newVariantName", label = "Variant Name:", text = "" }
  dlg:combobox{ id = "variantType", label = "Type:", options = { "equipment", "state" } }
  dlg:button{
    id = "addVariant",
    text = "Add Variant",
    onclick = function()
      local name = dlg.data.newVariantName
      local vtype = dlg.data.variantType
      if name and name ~= "" and name ~= "base" then
        table.insert(variants, { name = name, type = vtype, required = false })
        local options = {}
        for _, v in ipairs(variants) do
          table.insert(options, v.name .. " (" .. v.type .. ")")
        end
        dlg:modify{ id = "variantsList", options = options }
        dlg:modify{ id = "newVariantName", text = "" }
      end
    end
  }
  dlg:combobox{ id = "variantsList", label = "Current Variants:", options = { "base (equipment)" } }
  dlg:button{
    id = "removeVariant",
    text = "Remove Selected",
    onclick = function()
      local selected = dlg.data.variantsList
      if selected and not string.find(selected, "^base") then
        for i, v in ipairs(variants) do
          local display = v.name .. " (" .. v.type .. ")"
          if display == selected then
            table.remove(variants, i)
            break
          end
        end
        local options = {}
        for _, v in ipairs(variants) do
          table.insert(options, v.name .. " (" .. v.type .. ")")
        end
        dlg:modify{ id = "variantsList", options = options }
      end
    end
  }

  dlg:separator{ text = "Expected Animations" }
  dlg:entry{ id = "newAnimName", label = "Animation Name:", text = "" }
  dlg:button{
    id = "addAnim",
    text = "Add Animation",
    onclick = function()
      local name = dlg.data.newAnimName
      if name and name ~= "" then
        table.insert(animations, { name = name, file = "", status = "missing" })
        local options = {}
        for _, a in ipairs(animations) do
          table.insert(options, a.name)
        end
        dlg:modify{ id = "animsList", options = options }
        dlg:modify{ id = "newAnimName", text = "" }
      end
    end
  }
  dlg:combobox{ id = "animsList", label = "Current Animations:", options = {} }
  dlg:button{
    id = "removeAnim",
    text = "Remove Selected",
    onclick = function()
      local selected = dlg.data.animsList
      if selected and selected ~= "" then
        for i, a in ipairs(animations) do
          if a.name == selected then
            table.remove(animations, i)
            break
          end
        end
        local options = {}
        for _, a in ipairs(animations) do
          table.insert(options, a.name)
        end
        dlg:modify{ id = "animsList", options = options }
      end
    end
  }

  dlg:separator()
  dlg:file{ id = "saveDir", label = "Save Directory:", filename = "", open = false, save = false,
            filetypes = {} }
  dlg:button{ id = "create", text = "Create Blueprint" }
  dlg:button{ id = "cancel", text = "Cancel" }

  dlg:show()

  if dlg.data.create then
    local charName = dlg.data.characterName
    if not charName or charName == "" then
      app.alert("Character name is required.")
      return
    end
    if #bodyParts == 0 then
      app.alert("At least one body part is required.")
      return
    end

    local spr = Sprite(64, 64, ColorMode.RGB)
    spr.filename = charName .. "_blueprint.ase"

    for _, part in ipairs(bodyParts) do
      local partGroup = spr:newGroup()
      partGroup.name = part.name

      for _, variant in ipairs(variants) do
        local varGroup = spr:newGroup()
        varGroup.name = variant.name
        varGroup.parent = partGroup
      end
    end

    if spr.layers[1] and spr.layers[1].name == "Layer 1" then
      spr:deleteLayer(spr.layers[1])
    end

    local schema = {
      character_name = charName,
      body_parts = bodyParts,
      variants = variants,
      animations = animations,
    }
    blueprint.writeBlueprintSchema(spr, schema)

    local saveDir = dlg.data.saveDir
    if saveDir and saveDir ~= "" then
      local dir = app.fs.filePath(saveDir)
      if dir == "" then dir = saveDir end
      app.fs.makeAllDirectories(dir)
      local path = app.fs.joinPath(dir, charName .. "_blueprint.ase")
      spr:saveAs(path)
    end

    app.alert("Blueprint created: " .. charName)
  end
end

return blueprintEditor
