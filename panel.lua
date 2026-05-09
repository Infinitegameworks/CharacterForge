local blueprint = require 'blueprint'
local validator = require 'validator'
local utils = require 'utils'

local function log(msg)
  local f = io.open(app.fs.joinPath(app.fs.tempPath, "characterforge.log"), "a")
  if f then f:write(os.date("%H:%M:%S") .. " [panel] " .. msg .. "\n"); f:flush(); f:close() end
end

local panel = {}

local dlg = nil
local currentSprite = nil
local cachedLayerHash = ""
local debounceTimer = nil
local isRefreshingCache = false
local lastCheckedFilename = nil
local lastValidation = nil
local lastData = nil
local lastSchema = nil
local statusText = "Loading..."
local detailText = ""
local blueprintMissing = false
local selectedSlotFilter = "all"
local slotChipRects = {}
local previewStartY = 68

local spriteChangeHandler = nil
local spriteLayerNameHandler = nil
local siteChangeHandler = nil

local _blueprintModule = nil
local _blueprintEditorModule = nil
local activeSchema = nil

local function disconnectSpriteEvents()
  if currentSprite and spriteChangeHandler then
    currentSprite.events:off(spriteChangeHandler)
    spriteChangeHandler = nil
  end
  if currentSprite and spriteLayerNameHandler then
    currentSprite.events:off(spriteLayerNameHandler)
    spriteLayerNameHandler = nil
  end
end

local function schemaSignature(schema)
  if not schema then return "" end
  local normalized = blueprint.normalizeSchema(schema)
  local parts = {}
  for _, part in ipairs(normalized.body_parts or {}) do
    parts[#parts + 1] = "P:" .. part.id .. ":" .. part.name
    for _, slot in ipairs(part.slots or {}) do
      parts[#parts + 1] = "S:" .. slot.id .. ":" .. slot.name
      for _, variant in ipairs(slot.variants or {}) do
        parts[#parts + 1] = "V:" .. variant.id .. ":" .. variant.name .. ":" .. tostring(variant.required)
      end
    end
  end
  return table.concat(parts, "|")
end

local function blueprintPathForAnimation(sprite, data)
  if not sprite or not data or not data.blueprint_ref or data.blueprint_ref == "" then return nil end
  if not sprite.filename or sprite.filename == "" then return nil end
  local dir = app.fs.filePath(sprite.filename)
  if not dir or dir == "" then return nil end
  return app.fs.joinPath(dir, data.blueprint_ref)
end

local function updateLabels()
  if not dlg then return end
  dlg:modify{ id = "statusLabel", text = statusText }
  dlg:modify{ id = "detailLabel", text = detailText }
  if lastSchema then
    local options = { "all" }
    local hasSelection = selectedSlotFilter == "all"
    for _, name in ipairs(blueprint.listSlotNames(lastSchema)) do
      options[#options + 1] = name
      if name == selectedSlotFilter then hasSelection = true end
    end
    if not hasSelection then selectedSlotFilter = "all" end
    dlg:modify{ id = "slotFilter", options = options }
  else
    selectedSlotFilter = "all"
    dlg:modify{ id = "slotFilter", options = { "all" } }
  end
  dlg:repaint()
end

local function refreshPanel()
  if not dlg then return end

  local spr = app.activeSprite
  currentSprite = spr
  lastValidation = nil
  lastData = nil
  lastSchema = nil
  blueprintMissing = false

  if not spr then
    statusText = "No sprite open"
    detailText = "Open a sprite or create a blueprint."
    updateLabels()
    return
  end

  if blueprint.isBlueprint(spr) then
    local schema = blueprint.readBlueprintSchema(spr)
    lastSchema = schema
    local partCount = #(schema.body_parts or {})
    local animCount = #(schema.animations or {})
    statusText = (schema.character_name or "Blueprint") .. " blueprint"
    detailText = tostring(partCount) .. " part(s), " .. tostring(animCount) .. " expected animation(s)"
    cachedLayerHash = validator.buildLayerTreeHash(spr)
    updateLabels()
    return
  end

  if not blueprint.isAnimation(spr) then
    statusText = "Not registered"
    detailText = "Use Register Animation or Blueprint From Current Sprite."
    cachedLayerHash = validator.buildLayerTreeHash(spr)
    updateLabels()
    return
  end

  local data = blueprint.readAnimationData(spr)
  lastData = data
  if not data or not data.cached_schema then
    statusText = "No cached schema"
    detailText = "Re-register this animation to a blueprint."
    updateLabels()
    return
  end

  lastSchema = data.cached_schema
  lastValidation = validator.validate(spr, data.cached_schema)
  cachedLayerHash = validator.buildLayerTreeHash(spr)

  local bpPath = blueprintPathForAnimation(spr, data)
  blueprintMissing = bpPath and not app.fs.isFile(bpPath)

  statusText = (data.character_name or "character") .. " / " .. (data.animation_name or "animation")
  if blueprintMissing then
    detailText = "Blueprint missing; validating from cached schema."
  elseif lastValidation.result == "fail" then
    detailText = tostring(#lastValidation.errors) .. " error(s); save may be blocked."
  elseif lastValidation.result == "warn" then
    detailText = tostring(#lastValidation.warnings) .. " warning(s)."
  else
    detailText = "All checks pass."
  end

  updateLabels()
end

local function onSpriteChange(ev)
  local ok, err = pcall(function()
    if debounceTimer then debounceTimer:stop() end
    debounceTimer = Timer{
      interval = 0.5,
      ontick = function()
        debounceTimer:stop()
        if not currentSprite then return end
        local newHash = validator.buildLayerTreeHash(currentSprite)
        if newHash ~= cachedLayerHash then refreshPanel() end
      end
    }
    debounceTimer:start()
  end)
  if not ok then log("CF onSpriteChange error: " .. tostring(err)) end
end

local function onLayerName(ev)
  local ok, err = pcall(refreshPanel)
  if not ok then log("CF onLayerName error: " .. tostring(err)) end
end

local function connectSpriteEvents(sprite)
  disconnectSpriteEvents()
  currentSprite = sprite
  if not sprite then return end
  spriteChangeHandler = sprite.events:on("change", onSpriteChange)
  spriteLayerNameHandler = sprite.events:on("layername", onLayerName)
end

local function checkSchemaFreshness(spr)
  if not spr or not spr.filename or spr.filename == "" then return end
  if spr.filename == lastCheckedFilename then return end
  lastCheckedFilename = spr.filename

  if not blueprint.isAnimation(spr) then return end
  local data = blueprint.readAnimationData(spr)
  local bpPath = blueprintPathForAnimation(spr, data)
  if not bpPath or not app.fs.isFile(bpPath) then return end

  isRefreshingCache = true
  local bpSprite = app.open(bpPath)
  isRefreshingCache = false

  if not bpSprite then return end
  local schema = blueprint.readBlueprintSchema(bpSprite)
  bpSprite:close()
  if not schema then return end

  if schemaSignature(data.cached_schema) ~= schemaSignature(schema) then
    local accept = app.alert{
      title = "CharacterForge",
      text = "Blueprint schema has changed. Accept the new requirements for this animation?",
      buttons = { "Accept", "Dismiss" },
    }
    if accept == 1 then
      blueprint.cacheSchemaInAnimation(spr, schema)
    end
  end
end

local function onSiteChange()
  if isRefreshingCache then return end
  local ok, err = pcall(function()
    local spr = app.activeSprite
    if spr ~= currentSprite then
      connectSpriteEvents(spr)
      if spr then checkSchemaFreshness(spr) end
    end
    refreshPanel()
  end)
  if not ok then log("CF onSiteChange error: " .. tostring(err)) end
end

local function drawText(gc, text, x, y, color)
  gc.color = color or utils.COLOR_TEXT
  gc:fillText(text, x, y)
end

local function fillRect(gc, x, y, w, h, color)
  gc.color = color
  gc:fillRect(Rectangle(x, y, w, h))
end

local function drawStatusDot(gc, x, y, status)
  gc.color = utils.statusColor(status)
  gc:fillRect(Rectangle(x, y, 8, 8))
end

local function drawVariantCell(gc, x, y, variant)
  local color = utils.statusColor(variant.status)
  if variant.frames == 0 and variant.status == "pass" then color = utils.COLOR_UNKNOWN end
  gc.color = color
  gc:fillRect(Rectangle(x, y, 10, 10))
end

local function activeSlotFilter()
  return selectedSlotFilter or "all"
end

local function shouldDrawSlot(name)
  local filter = activeSlotFilter()
  return filter == "all" or filter == name
end

local function chipWidth(name)
  return math.max(38, (#tostring(name) * 6) + 18)
end

local function drawChip(gc, name, x, y, active)
  local w = chipWidth(name)
  fillRect(gc, x, y, w, 16, active and utils.COLOR_PANEL or utils.COLOR_BG)
  gc.color = active and utils.COLOR_PASS or utils.COLOR_UNKNOWN
  gc:strokeRect(Rectangle(x, y, w, 16))
  drawText(gc, name, x + 7, y + 3, active and utils.COLOR_TEXT or utils.COLOR_MUTED)
  slotChipRects[#slotChipRects + 1] = { name = name, x = x, y = y, w = w, h = 16 }
  return x + w + 6
end

local function drawSlotChips(gc, schema)
  slotChipRects = {}
  local x = 8
  local y = 40
  x = drawChip(gc, "all", x, y, activeSlotFilter() == "all")
  if schema then
    for _, name in ipairs(blueprint.listSlotNames(schema)) do
      if x + chipWidth(name) > 332 then
        x = 8
        y = y + 20
      end
      if y > 60 then break end
      x = drawChip(gc, name, x, y, activeSlotFilter() == name)
    end
  end
  previewStartY = y + 28
end

local function variantLabel(variant)
  if variant.type == "state" then return "S" end
  if variant.name == "base" then return "B" end
  return "V"
end

local function drawBlueprintPreview(gc, schema)
  local y = previewStartY
  local row = 0
  for _, part in ipairs(schema.body_parts or {}) do
    local drewPart = false
    for _, slot in ipairs(part.slots or {}) do
      if shouldDrawSlot(slot.name) then
        if not drewPart then
          fillRect(gc, 8, y - 2, 324, 14, row % 2 == 0 and Color{ r = 46, g = 46, b = 46, a = 255 } or utils.COLOR_BG)
          drawStatusDot(gc, 12, y + 1, "pass")
          drawText(gc, part.name, 28, y, utils.COLOR_TEXT)
          y = y + 16
          row = row + 1
          drewPart = true
        end

        drawText(gc, slot.name, 28, y, utils.COLOR_MUTED)
        local x = 112
        for _, variant in ipairs(slot.variants or {}) do
          fillRect(gc, x, y + 1, 12, 12, variant.type == "state" and utils.COLOR_ABSENT or (variant.required and utils.COLOR_PASS or utils.COLOR_UNKNOWN))
          drawText(gc, variantLabel(variant), x + 3, y + 2, utils.COLOR_BG)
          x = x + 15
          if x > 320 then break end
        end
        y = y + 14
        if y > 230 then
          drawText(gc, "More rows hidden by panel size.", 8, 238, utils.COLOR_WARN)
          return
        end
      end
    end
  end
end

local function drawValidationPreview(gc, result)
  local y = previewStartY
  for _, part in ipairs(result.layer_status or {}) do
    local partDrawn = false
    for _, slot in ipairs(part.slots or {}) do
      if shouldDrawSlot(slot.slot) then
        if not partDrawn then
          drawStatusDot(gc, 12, y + 3, part.status)
          drawText(gc, part.part .. " (" .. tostring(part.base_frames or 0) .. "f)", 28, y, utils.COLOR_TEXT)
          y = y + 16
          partDrawn = true
        end

        drawText(gc, slot.slot, 28, y, utils.COLOR_MUTED)
        local x = 112
        for _, variant in ipairs(slot.variants or {}) do
          drawVariantCell(gc, x, y + 1, variant)
          drawText(gc, variantLabel(variant), x + 3, y + 2, utils.COLOR_BG)
          x = x + 15
          if x > 320 then break end
        end
        y = y + 14
        if y > 230 then
          drawText(gc, "More rows hidden by panel size.", 8, 238, utils.COLOR_WARN)
          return
        end
      end
    end
  end
end

local function onPaint(ev)
  local ok, err = pcall(function()
    local gc = ev.context
    local w = 340
    local h = 260
    gc.color = utils.COLOR_BG
    gc:fillRect(Rectangle(0, 0, w, h))

    fillRect(gc, 0, 0, w, 34, utils.COLOR_PANEL)
    drawText(gc, statusText, 8, 7, utils.COLOR_TEXT)
    drawText(gc, detailText, 8, 22, blueprintMissing and utils.COLOR_WARN or utils.COLOR_MUTED)
    drawSlotChips(gc, lastSchema)

    if not lastValidation then
      if lastSchema and blueprint.isBlueprint(app.activeSprite) then
        drawBlueprintPreview(gc, lastSchema)
      end
      return
    end

    drawValidationPreview(gc, lastValidation)

    if lastValidation.result == "fail" then
      drawText(gc, "Red cells need repair before strict save.", 8, h - 18, utils.COLOR_FAIL)
    elseif lastValidation.result == "warn" then
      drawText(gc, "Yellow cells are incomplete or optional.", 8, h - 18, utils.COLOR_WARN)
    else
      drawText(gc, "Green means the structure is ready.", 8, h - 18, utils.COLOR_PASS)
    end
  end)
  if not ok then log("CF onPaint error: " .. tostring(err)) end
end

local function onCanvasMouseDown(ev)
  local ok, err = pcall(function()
    local x = ev.x or 0
    local y = ev.y or 0
    for _, rect in ipairs(slotChipRects or {}) do
      if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
        selectedSlotFilter = rect.name
        local schema = activeSchema()
        if schema then
          if rect.name == "all" then
            blueprint.setSlotVisibility(app.activeSprite, schema, "all", "all")
          else
            blueprint.setSlotVisibility(app.activeSprite, schema, rect.name, "solo")
          end
        end
        refreshPanel()
        return
      end
    end
  end)
  if not ok then log("CF canvas click error: " .. tostring(err)) end
end

local function runAction(fn)
  local ok, err = pcall(function()
    fn()
    refreshPanel()
  end)
  if not ok then app.alert("Error: " .. tostring(err)) end
end

local function activeAnimationSchema()
  local spr = app.activeSprite
  if not spr or not blueprint.isAnimation(spr) then return nil end
  local data = blueprint.readAnimationData(spr)
  return data and data.cached_schema or nil
end

activeSchema = function()
  local spr = app.activeSprite
  if not spr then return nil end
  if blueprint.isBlueprint(spr) then return blueprint.readBlueprintSchema(spr) end
  return activeAnimationSchema()
end

local function selectedSlotName()
  local value = dlg and dlg.data.slotFilter or selectedSlotFilter
  if not value or value == "" then return "all" end
  selectedSlotFilter = value
  return value
end

local function showSettingsDialog()
  local settings = Dialog{ title = "CharacterForge Settings" }

  settings:separator{ text = "Repair" }
  settings:button{
    id = "btnFixMissing",
    text = "Create Missing",
    onclick = function()
      runAction(function()
        local schema = activeAnimationSchema()
        if schema then
          app.transaction(function()
            blueprint.ensureLayerStructure(app.activeSprite, schema, { rename = true })
          end)
        else
          app.alert("Open a registered animation first.")
        end
      end)
    end
  }
  settings:button{
    id = "btnSyncFrames",
    text = "Sync Frames",
    onclick = function()
      runAction(function()
        local schema = activeAnimationSchema()
        if schema then
          app.transaction(function()
            blueprint.syncVariantFrames(app.activeSprite, schema)
          end)
        else
          app.alert("Open a registered animation first.")
        end
      end)
    end
  }
  settings:button{
    id = "btnAbsent",
    text = "Toggle Absent",
    onclick = function()
      runAction(function()
        app.transaction(function()
          local absent = blueprint.toggleActiveVariantAbsent()
          if absent == nil then app.alert("Select a managed variant layer first.") end
        end)
      end)
    end
  }

  settings:separator{ text = "Save" }
  settings:label{
    id = "saveMode",
    text = "Mode: " .. (blueprint.getSaveMode() == "block" and "strict blocking" or "warn only"),
  }
  settings:button{
    id = "btnSaveMode",
    text = "Toggle Strict Save",
    onclick = function()
      local mode = blueprint.toggleSaveMode()
      settings:modify{
        id = "saveMode",
        text = "Mode: " .. (mode == "block" and "strict blocking" or "warn only"),
      }
    end
  }

  settings:separator()
  settings:button{ id = "close", text = "Close", onclick = function() settings:close() end }
  settings:show{ wait = false }
end

function panel.toggle(blueprintMod, blueprintEditorMod)
  if blueprintMod then _blueprintModule = blueprintMod end
  if blueprintEditorMod then _blueprintEditorModule = blueprintEditorMod end

  if dlg then panel.close() else panel.open() end
end

function panel.open()
  if dlg then return end

  dlg = Dialog{
    title = "CharacterForge",
    onclose = function()
      disconnectSpriteEvents()
      if debounceTimer then
        debounceTimer:stop()
        debounceTimer = nil
      end
      if siteChangeHandler then
        app.events:off(siteChangeHandler)
        siteChangeHandler = nil
      end
      dlg = nil
      currentSprite = nil
      lastValidation = nil
      lastData = nil
      lastSchema = nil
      lastCheckedFilename = nil
    end
  }

  dlg:canvas{
    id = "statusCanvas",
    width = 340,
    height = 260,
    onpaint = onPaint,
    onmousedown = onCanvasMouseDown,
  }
  dlg:label{ id = "statusLabel", text = "Loading..." }
  dlg:label{ id = "detailLabel", text = "" }

  dlg:separator{ text = "Create" }
  dlg:button{
    id = "btnCreateBlueprint",
    text = "New Blueprint",
    onclick = function()
      runAction(function()
        if _blueprintEditorModule then _blueprintEditorModule.showCreateDialog() end
      end)
    end
  }
  dlg:button{
    id = "btnFromCurrent",
    text = "Blueprint From Current",
    onclick = function()
      runAction(function()
        if _blueprintModule then _blueprintModule.showCreateFromCurrentDialog() end
      end)
    end
  }
  dlg:button{
    id = "btnEditBlueprint",
    text = "Edit Blueprint",
    onclick = function()
      runAction(function()
        if _blueprintEditorModule then _blueprintEditorModule.showEditDialog() end
      end)
    end
  }
  dlg:button{
    id = "btnNewAnimation",
    text = "New Animation",
    onclick = function()
      runAction(function()
        if _blueprintModule then _blueprintModule.showNewAnimationDialog() end
      end)
    end
  }
  dlg:button{
    id = "btnRegister",
    text = "Register Animation",
    onclick = function()
      runAction(function()
        if _blueprintModule then _blueprintModule.showRegisterDialog() end
      end)
    end
  }

  dlg:separator{ text = "View" }
  dlg:combobox{
    id = "slotFilter",
    label = "Slot:",
    options = { "all" },
    onchange = function()
      selectedSlotFilter = dlg.data.slotFilter or "all"
    end,
  }
  dlg:button{
    id = "btnSoloSlot",
    text = "Solo Slot",
    onclick = function()
      runAction(function()
        local slotName = selectedSlotName()
        local schema = activeSchema()
        if schema and slotName ~= "all" then
          blueprint.setSlotVisibility(app.activeSprite, schema, slotName, "solo")
        else
          app.alert("Choose a slot first.")
        end
      end)
    end
  }
  dlg:button{
    id = "btnHideSlot",
    text = "Hide Slot",
    onclick = function()
      runAction(function()
        local slotName = selectedSlotName()
        local schema = activeSchema()
        if schema and slotName ~= "all" then
          blueprint.setSlotVisibility(app.activeSprite, schema, slotName, "hide")
        else
          app.alert("Choose a slot first.")
        end
      end)
    end
  }
  dlg:button{
    id = "btnSoloPart",
    text = "Solo Part",
    onclick = function()
      runAction(function()
        if not blueprint.soloActivePart(app.activeSprite) then
          app.alert("Select a layer inside a managed body part first.")
        end
      end)
    end
  }
  dlg:button{
    id = "btnSoloVariant",
    text = "Solo Variant",
    onclick = function()
      runAction(function()
        if not blueprint.soloActiveVariant(app.activeSprite) then
          app.alert("Select a managed variant layer first.")
        end
      end)
    end
  }
  dlg:button{
    id = "btnShowAll",
    text = "Show All",
    onclick = function()
      runAction(function() blueprint.showAllManagedLayers(app.activeSprite) end)
    end
  }

  dlg:separator()
  dlg:button{
    id = "btnSettings",
    text = "Settings",
    onclick = function()
      showSettingsDialog()
    end
  }
  dlg:button{
    id = "btnRefresh",
    text = "Refresh",
    onclick = function()
      lastCheckedFilename = nil
      local spr = app.activeSprite
      if spr then
        connectSpriteEvents(spr)
        checkSchemaFreshness(spr)
      end
      refreshPanel()
    end
  }

  dlg:show{ wait = false }

  siteChangeHandler = app.events:on("sitechange", onSiteChange)
  connectSpriteEvents(app.activeSprite)
  refreshPanel()
end

function panel.close()
  if dlg then dlg:close() end
end

return panel
