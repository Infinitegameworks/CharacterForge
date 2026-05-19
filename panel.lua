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
local lastValidation = nil
local lastData = nil
local lastSchema = nil
local statusText = "Loading..."
local detailText = ""
local blueprintMissing = false
local selectedSlotFilter = "all"
local slotChipRects = {}
local animRowRects = {}
local variantRowRects = {}
local previewStartY = 68
local scrollOffset = 0
local contentHeight = 0
local isDraggingScrollbar = false
local collapsedGroups = {}
local isDraggingAnim = false
local dragAnimKey = nil
local dragStartY = 0
local dragMouseY = 0
local groupHeaderRects = {}
local hoverAnimRowKey = nil
local hoverVariantRowKey = nil

local LIST_BOTTOM = 236
local FOOTER_Y = 244

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

local function findAnimFile(bpDir, fileName)
  if not bpDir or not fileName or fileName == "" then return false end
  if app.fs.isFile(app.fs.joinPath(bpDir, fileName)) then return true end
  for _, sub in ipairs(app.fs.listFiles(bpDir) or {}) do
    local subPath = app.fs.joinPath(bpDir, sub)
    if app.fs.isDirectory(subPath) then
      if app.fs.isFile(app.fs.joinPath(subPath, fileName)) then return true end
    end
  end
  return false
end

local function blueprintPathForAnimation(sprite, data)
  if not sprite or not data then return nil end
  local ref = data.blueprint_ref or ""
  if sprite.filename and sprite.filename ~= "" and ref ~= "" then
    local dir = app.fs.filePath(sprite.filename)
    if dir and dir ~= "" then
      local path = app.fs.joinPath(dir, ref)
      if app.fs.isFile(path) then return path end
      local parent = app.fs.filePath(dir:sub(1, -2))
      if parent and parent ~= "" and parent ~= dir then
        local parentPath = app.fs.joinPath(parent, ref)
        if app.fs.isFile(parentPath) then return parentPath end
      end
    end
  end
  if data.blueprint_path and data.blueprint_path ~= "" and app.fs.isFile(data.blueprint_path) then
    return data.blueprint_path
  end
  return nil
end


local function updateLabels()
  if not dlg then return end
  dlg:modify{ id = "statusLabel", text = statusText }
  dlg:modify{ id = "detailLabel", text = detailText }
  local multiSlot = false
  if lastSchema then
    local slotNames = blueprint.listSlotNames(lastSchema)
    multiSlot = #slotNames > 1
    local options = { "all" }
    local hasSelection = selectedSlotFilter == "all"
    for _, name in ipairs(slotNames) do
      options[#options + 1] = name
      if name == selectedSlotFilter then hasSelection = true end
    end
    if not hasSelection then selectedSlotFilter = "all" end
    dlg:modify{ id = "slotFilter", options = multiSlot and options or { "all" } }
  else
    selectedSlotFilter = "all"
    dlg:modify{ id = "slotFilter", options = { "all" } }
  end
  dlg:modify{ id = "btnSoloSlot", enabled = multiSlot }
  dlg:modify{ id = "btnHideSlot", enabled = multiSlot }

  local spr = app.activeSprite
  local viewingBlueprint = spr and blueprint.isBlueprint(spr)
  local viewingAnimation = spr and blueprint.isAnimation(spr)
  local viewingUnregistered = spr and not viewingBlueprint and not viewingAnimation

  dlg:modify{ id = "btnEditBlueprint", visible = viewingBlueprint == true }
  dlg:modify{ id = "btnNewAnimation", visible = viewingBlueprint == true }

  local hasBlueprint = lastData ~= nil and not blueprintMissing
  dlg:modify{ id = "btnGoToBlueprint", visible = viewingAnimation == true, enabled = hasBlueprint }
  dlg:modify{ id = "btnRefreshSchema", visible = viewingAnimation == true, enabled = hasBlueprint }
  dlg:modify{ id = "btnEditAnimation", visible = viewingAnimation == true }

  dlg:modify{ id = "btnCreateBlueprint", visible = viewingUnregistered == true or not spr }
  dlg:modify{ id = "btnFromCurrent", visible = viewingUnregistered == true }
  dlg:modify{ id = "btnRegister", visible = viewingUnregistered == true }

  dlg:repaint()
end

local function refreshPanel()
  if not dlg then return end

  local spr = app.activeSprite
  local wasBlueprint = currentSprite and blueprint.isBlueprint(currentSprite)
  local isNowBlueprint = spr and blueprint.isBlueprint(spr)
  if spr ~= currentSprite or wasBlueprint ~= isNowBlueprint then
    scrollOffset = 0
    hoverAnimRowKey = nil
    hoverVariantRowKey = nil
    isDraggingAnim = false
    dragAnimKey = nil
  end
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
    statusText = "Not linked"
    detailText = "Use Link Animation or Blueprint From Current Sprite."
    cachedLayerHash = validator.buildLayerTreeHash(spr)
    updateLabels()
    return
  end

  local data = blueprint.readAnimationData(spr)
  lastData = data
  if not data or not data.cached_schema then
    statusText = "No character definition"
    detailText = "Re-link this animation to a character file."
    updateLabels()
    return
  end

  lastSchema = data.cached_schema
  lastValidation = validator.validate(spr, data.cached_schema)
  cachedLayerHash = validator.buildLayerTreeHash(spr)

  local bpPath = blueprintPathForAnimation(spr, data)
  blueprintMissing = bpPath and not app.fs.isFile(bpPath)

  local animLabel = data.animation_name or "animation"
  if data.animation_direction and data.animation_direction ~= "" then
    animLabel = animLabel .. " [" .. data.animation_direction .. "]"
  end
  statusText = (data.character_name or "character") .. " / " .. animLabel
  if blueprintMissing then
    detailText = "Blueprint not found: " .. (data.blueprint_ref or "?")
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


local function onSiteChange()
  log("onSiteChange isRefreshingCache=" .. tostring(isRefreshingCache)
    .. " active=" .. tostring(app.activeSprite and app.activeSprite.filename or "nil")
    .. " current=" .. tostring(currentSprite and currentSprite.filename or "nil"))
  if isRefreshingCache then log("  BLOCKED"); return end
  local ok, err = pcall(function()
    local spr = app.activeSprite
    if currentSprite and spr then
      pcall(function()
        if blueprint.isAnimation(currentSprite) and blueprint.isBlueprint(spr) then
          local data = blueprint.readAnimationData(currentSprite)
          if data and data.blueprint_ref and data.blueprint_ref ~= "" then
            local bpName = app.fs.fileName(spr.filename or "")
            if bpName == data.blueprint_ref then
              log("  syncing completion to blueprint")
              blueprint.syncCompletionToBlueprint(currentSprite, spr)
              log("  sync done, active=" .. tostring(app.activeSprite and app.activeSprite.filename or "nil"))
            end
          end
        end
      end)
    end
    if spr ~= currentSprite then
      connectSpriteEvents(spr)
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

local function drawProgressDot(gc, x, y, dotColor)
  gc.color = dotColor
  gc:fillRect(Rectangle(x, y, 8, 8))
end

local function animRowKey(anim)
  return tostring(anim.name or "") .. "|" .. tostring(anim.direction or "") .. "|" .. tostring(anim.file or "")
end

local function variantRowKey(partId, slotId, variantId)
  return tostring(partId or "") .. "/" .. tostring(slotId or "") .. "/" .. tostring(variantId or "")
end

local GROUP_HEADER_COLOR = Color{ r = 58, g = 58, b = 58, a = 255 }
local GROUP_ARROW_EXPANDED = "v "
local GROUP_ARROW_COLLAPSED = "> "

local function animStatus(anim, bpDir)
  local fileExists = bpDir and anim.file and anim.file ~= "" and findAnimFile(bpDir, anim.file)
  local label, dotColor
  if fileExists and anim.status == "valid" then
    local dc = anim.done_count or 0
    local tc = anim.total_count or 0
    label = tc > 0 and (tostring(dc) .. "/" .. tostring(tc) .. " done") or "complete"
    dotColor = utils.COLOR_PASS
  elseif fileExists then
    local dc = anim.done_count or 0
    local tc = anim.total_count or 0
    label = tc > 0 and (tostring(dc) .. "/" .. tostring(tc) .. " done") or "started"
    dotColor = tc > 0 and dc > 0 and utils.COLOR_WARN or utils.COLOR_UNKNOWN
  else
    label = "not created"
    dotColor = utils.COLOR_UNKNOWN
  end
  return label, dotColor, fileExists
end

local function buildGroupedAnims(anims)
  local groupOrder = {}
  local groupMap = {}
  local ungrouped = {}

  for _, anim in ipairs(anims) do
    local g = anim.group or ""
    if g ~= "" then
      if not groupMap[g] then
        groupMap[g] = {}
        groupOrder[#groupOrder + 1] = g
      end
      groupMap[g][#groupMap[g] + 1] = anim
    else
      ungrouped[#ungrouped + 1] = anim
    end
  end
  return groupOrder, groupMap, ungrouped
end

local function drawBlueprintProgressView(gc, schema)
  animRowRects = {}
  groupHeaderRects = {}
  if not schema then return end
  local anims = schema.animations or {}
  if #anims == 0 then
    drawText(gc, "No animations defined yet.", 8, previewStartY, utils.COLOR_MUTED)
    return
  end

  local bpDir = nil
  local spr = app.activeSprite
  if spr and spr.filename and spr.filename ~= "" then
    bpDir = app.fs.filePath(spr.filename)
  end

  local started = 0
  local complete = 0
  for _, anim in ipairs(anims) do
    local _, _, fe = animStatus(anim, bpDir)
    if fe then
      started = started + 1
      if anim.status == "valid" then complete = complete + 1 end
    end
  end

  local y = previewStartY
  local sy = y - scrollOffset
  if sy >= previewStartY and sy < LIST_BOTTOM then
    drawText(gc, tostring(started) .. "/" .. tostring(#anims) .. " started, " .. tostring(complete) .. " complete", 8, sy, utils.COLOR_TEXT)
  end
  y = y + 18

  local groupOrder, groupMap, ungrouped = buildGroupedAnims(anims)
  local rowIdx = 0

  local function drawAnimRow(anim, indent)
    local label, dotColor, fileExists = animStatus(anim, bpDir)
    sy = y - scrollOffset
    if sy >= previewStartY - 4 and sy < LIST_BOTTOM then
      local rowKey = animRowKey(anim)
      local hovered = hoverAnimRowKey == rowKey
      local dragging = isDraggingAnim and dragAnimKey == rowKey
      if dragging then
        fillRect(gc, indent, sy - 2, 324 - indent + 8, 14, Color{ r = 80, g = 80, b = 60, a = 255 })
      elseif hovered then
        fillRect(gc, indent, sy - 2, 324 - indent + 8, 14, Color{ r = 64, g = 64, b = 64, a = 255 })
      elseif rowIdx % 2 == 0 then
        fillRect(gc, indent, sy - 2, 324 - indent + 8, 14, Color{ r = 46, g = 46, b = 46, a = 255 })
      end
      drawProgressDot(gc, indent + 4, sy + 1, dotColor)
      local displayName
      local inGroup = (anim.group or "") ~= "" and anim.direction and anim.direction ~= ""
      if inGroup then
        displayName = anim.direction
      else
        displayName = anim.name or "unnamed"
        if anim.direction and anim.direction ~= "" then
          displayName = displayName .. " [" .. anim.direction .. "]"
        end
      end
      drawText(gc, displayName .. ": " .. label, indent + 20, sy, utils.COLOR_TEXT)
      drawText(gc, fileExists and "open" or "create", 286, sy, hovered and utils.COLOR_TEXT or utils.COLOR_MUTED)
      animRowRects[#animRowRects + 1] = {
        key = rowKey,
        name = anim.name or "",
        direction = anim.direction or "",
        group = anim.group or "",
        file = anim.file or "",
        fileExists = fileExists,
        x = indent, y = sy - 2, w = 324 - indent + 8, h = 16,
      }
    end
    rowIdx = rowIdx + 1
    y = y + 16
  end

  for _, groupName in ipairs(groupOrder) do
    local groupAnims = groupMap[groupName]
    local collapsed = collapsedGroups[groupName]
    local gDone = 0
    local gTotal = #groupAnims
    for _, a in ipairs(groupAnims) do
      local _, _, fe = animStatus(a, bpDir)
      if fe and a.status == "valid" then gDone = gDone + 1 end
    end

    sy = y - scrollOffset
    if sy >= previewStartY - 4 and sy < LIST_BOTTOM then
      local dropTarget = isDraggingAnim and dragAnimKey and true or false
      fillRect(gc, 8, sy - 2, 324, 14, dropTarget and Color{ r = 50, g = 58, b = 50, a = 255 } or GROUP_HEADER_COLOR)
      local arrow = collapsed and GROUP_ARROW_COLLAPSED or GROUP_ARROW_EXPANDED
      drawText(gc, arrow .. groupName .. " (" .. gDone .. "/" .. gTotal .. ")", 12, sy, utils.COLOR_TEXT)
      groupHeaderRects[#groupHeaderRects + 1] = {
        name = groupName, x = 8, y = sy - 2, w = 324, h = 16,
      }
    end
    y = y + 16

    if not collapsed then
      for _, anim in ipairs(groupAnims) do
        drawAnimRow(anim, 20)
      end
    end
  end

  for _, anim in ipairs(ungrouped) do
    drawAnimRow(anim, 8)
  end

  contentHeight = y - previewStartY
end

local function readVariantDoneMap(spr, layerStatus)
  local doneMap = {}
  local total = 0
  local done = 0

  for _, part in ipairs(layerStatus) do
    for _, slot in ipairs(part.slots or {}) do
      local baseFrames = slot.base_frames or 0
      for _, variant in ipairs(slot.variants or {}) do
        if variant.absent then goto nextVariant end
        total = total + 1
        if baseFrames > 0 and (variant.frames or 0) == baseFrames then
          doneMap[part.id .. "/" .. slot.id .. "/" .. variant.id] = true
          done = done + 1
        end
        ::nextVariant::
      end
    end
    ::nextPart::
  end
  return doneMap, total, done
end

local function drawAnimationProgressView(gc, result)
  variantRowRects = {}
  if not result then return end
  local layerStatus = result.layer_status or {}
  if #layerStatus == 0 then
    drawText(gc, "No parts to display.", 8, previewStartY, utils.COLOR_MUTED)
    return
  end

  local spr = app.activeSprite
  local doneMap, totalVariants, doneVariants = readVariantDoneMap(spr, layerStatus)

  local y = previewStartY
  local sy = y - scrollOffset
  local summaryColor = (doneVariants == totalVariants and totalVariants > 0) and utils.COLOR_PASS or utils.COLOR_TEXT
  if sy >= previewStartY and sy < LIST_BOTTOM then
    drawText(gc, tostring(doneVariants) .. "/" .. tostring(totalVariants) .. " drawing groups done", 8, sy, summaryColor)
  end
  y = y + 18

  local rowIdx = 0
  for _, part in ipairs(layerStatus) do
    sy = y - scrollOffset
    if part.status == "fail" then
      if sy >= previewStartY - 4 and sy < LIST_BOTTOM then
        drawProgressDot(gc, 8, sy + 1, utils.COLOR_FAIL)
        drawText(gc, part.part .. ": missing", 24, sy, utils.COLOR_FAIL)
      end
      y = y + 14
      goto nextPart2
    end

    if sy >= previewStartY - 4 and sy < LIST_BOTTOM then
      drawText(gc, part.part, 8, sy, utils.COLOR_TEXT)
    end
    y = y + 14

    local hasMultipleSlots = #(part.slots or {}) > 1
    for _, slot in ipairs(part.slots or {}) do
      for _, variant in ipairs(slot.variants or {}) do
        local key = part.id .. "/" .. slot.id .. "/" .. variant.id
        local isDone = doneMap[key]

        local dotColor
        if variant.absent then
          dotColor = utils.COLOR_ABSENT
        elseif variant.status == "fail" then
          dotColor = utils.COLOR_FAIL
        elseif isDone then
          dotColor = utils.COLOR_PASS
        else
          dotColor = utils.COLOR_UNKNOWN
        end

        local label = variant.variant
        if hasMultipleSlots then
          label = slot.slot .. "/" .. label
        end
        if variant.frames > 0 then
          label = label .. " (" .. tostring(variant.frames) .. "f)"
        end
        if variant.absent then
          label = label .. " skipped"
        elseif isDone then
          label = label .. " done"
        end

        sy = y - scrollOffset
        if sy >= previewStartY - 4 and sy < LIST_BOTTOM then
          local key = variantRowKey(part.id, slot.id, variant.id)
          local hovered = hoverVariantRowKey == key
          if hovered then
            fillRect(gc, 16, sy - 2, 316, 14, Color{ r = 64, g = 64, b = 64, a = 255 })
          elseif rowIdx % 2 == 0 then
            fillRect(gc, 16, sy - 2, 316, 14, Color{ r = 46, g = 46, b = 46, a = 255 })
          end
          drawProgressDot(gc, 20, sy + 1, dotColor)
          drawText(gc, label, 36, sy, variant.absent and utils.COLOR_MUTED or utils.COLOR_TEXT)

          if not variant.absent then
            drawText(gc, isDone and "undo" or "done", 294, sy, hovered and utils.COLOR_TEXT or utils.COLOR_MUTED)
            variantRowRects[#variantRowRects + 1] = {
              key = key,
              partId = part.id,
              partName = part.part,
              slotId = slot.id,
              slotName = slot.slot,
              variantId = variant.id,
              variantName = variant.variant,
              x = 16, y = sy - 2, w = 316, h = 16,
            }
          end
        end

        rowIdx = rowIdx + 1
        y = y + 14
      end
    end
    ::nextPart2::
  end
  contentHeight = y - previewStartY

  local issueCount = #(result.errors or {}) + #(result.warnings or {})
  if issueCount > 0 then
    sy = y - scrollOffset + 4
    if sy >= previewStartY and sy < LIST_BOTTOM then
      drawText(gc, tostring(issueCount) .. " issue(s)", 8, sy, utils.COLOR_WARN)
    end
  end
end

local function drawFooterHint(gc)
  local spr = app.activeSprite
  local hint = nil
  if lastSchema and spr and blueprint.isBlueprint(spr) then
    hint = "Click an animation row to open or create."
  elseif lastValidation then
    hint = "Click a drawing row to toggle done."
  end
  if hint then
    fillRect(gc, 0, LIST_BOTTOM, 340, 24, utils.COLOR_BG)
    drawText(gc, hint, 8, FOOTER_Y, utils.COLOR_MUTED)
  end
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
  local slotNames = schema and blueprint.listSlotNames(schema) or {}
  if #slotNames <= 1 then
    previewStartY = 40
    return
  end
  local x = 8
  local y = 40
  x = drawChip(gc, "all", x, y, activeSlotFilter() == "all")
  for _, name in ipairs(slotNames) do
    if x + chipWidth(name) > 332 then
      x = 8
      y = y + 20
    end
    if y > 60 then break end
    x = drawChip(gc, name, x, y, activeSlotFilter() == name)
  end
  previewStartY = y + 28
end

local function variantLabel(variant)
  if variant.type == "state" then return "E" end
  if variant.name == "base" then return "B" end
  return "O"
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

local function showDetailsDialog()
  local detailsDlg = Dialog{ title = "CharacterForge — Details" }

  detailsDlg:canvas{
    id = "detailsCanvas",
    width = 340,
    height = 260,
    onpaint = function(ev)
      local ok2, err2 = pcall(function()
        local gc = ev.context
        gc.color = utils.COLOR_BG
        gc:fillRect(Rectangle(0, 0, 340, 260))

        fillRect(gc, 0, 0, 340, 34, utils.COLOR_PANEL)
        drawText(gc, statusText, 8, 7, utils.COLOR_TEXT)
        drawText(gc, detailText, 8, 22, blueprintMissing and utils.COLOR_WARN or utils.COLOR_MUTED)

        local detailPreviewStartY = 40
        if lastSchema then
          local slotNames = blueprint.listSlotNames(lastSchema)
          if #slotNames > 1 then
            detailPreviewStartY = 68
          end
        end

        local savedStartY = previewStartY
        previewStartY = detailPreviewStartY
        drawSlotChips(gc, lastSchema)

        if not lastValidation then
          if lastSchema and blueprint.isBlueprint(app.activeSprite) then
            drawBlueprintPreview(gc, lastSchema)
          end
          previewStartY = savedStartY
          return
        end

        drawValidationPreview(gc, lastValidation)

        if lastValidation.result == "fail" then
          drawText(gc, "Red cells have issues — fix before strict save.", 8, 242, utils.COLOR_FAIL)
        elseif lastValidation.result == "warn" then
          drawText(gc, "Yellow cells are incomplete or optional.", 8, 242, utils.COLOR_WARN)
        else
          drawText(gc, "All checks pass.", 8, 242, utils.COLOR_PASS)
        end
        previewStartY = savedStartY
      end)
      if not ok2 then log("CF details onPaint error: " .. tostring(err2)) end
    end,
    onmousedown = function(ev)
      local ok2, err2 = pcall(function()
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
            detailsDlg:repaint()
            if dlg then dlg:repaint() end
            return
          end
        end
      end)
      if not ok2 then log("CF details click error: " .. tostring(err2)) end
    end,
  }

  detailsDlg:button{ id = "closeDetails", text = "Close", onclick = function() detailsDlg:close() end }
  detailsDlg:show{ wait = false }
end

local function onPaint(ev)
  local ok, err = pcall(function()
    local gc = ev.context
    local w = 340
    local h = 260
    gc.color = utils.COLOR_BG
    gc:fillRect(Rectangle(0, 0, w, h))

    animRowRects = {}
    variantRowRects = {}

    fillRect(gc, 0, 0, w, 34, utils.COLOR_PANEL)
    drawText(gc, statusText, 8, 7, utils.COLOR_TEXT)
    drawText(gc, detailText, 8, 22, blueprintMissing and utils.COLOR_WARN or utils.COLOR_MUTED)

    previewStartY = 40

    if not lastValidation then
      if lastSchema and blueprint.isBlueprint(app.activeSprite) then
        drawBlueprintProgressView(gc, lastSchema)
      end
    else
      drawAnimationProgressView(gc, lastValidation)
    end

    drawFooterHint(gc)

    local visibleHeight = LIST_BOTTOM - previewStartY
    if contentHeight > visibleHeight then
      local trackX = w - 10
      local trackY = previewStartY
      local trackH = visibleHeight
      local thumbH = math.max(16, math.floor(trackH * visibleHeight / contentHeight))
      local maxScroll = contentHeight - visibleHeight
      local thumbY = trackY + math.floor((trackH - thumbH) * scrollOffset / maxScroll)
      fillRect(gc, trackX, trackY, 8, trackH, Color{ r = 50, g = 50, b = 50, a = 255 })
      fillRect(gc, trackX, thumbY, 8, thumbH, Color{ r = 100, g = 100, b = 100, a = 255 })
    end
  end)
  if not ok then log("CF onPaint error: " .. tostring(err)) end
end

local function onAnimRowClick(rect)
  local spr = app.activeSprite
  if not spr or not spr.filename or spr.filename == "" then return end
  local dir = app.fs.filePath(spr.filename)

  if rect.fileExists and rect.file ~= "" then
    local path = app.fs.joinPath(dir, rect.file)
    if app.fs.isFile(path) then
      app.open(path)
      refreshPanel()
      return
    end
  end

  local confirm = app.alert{
    title = "Create Animation",
    text = "Create '" .. rect.name .. "' animation?",
    buttons = { "Create", "Cancel" },
  }
  if confirm == 1 then
    isRefreshingCache = true
    local created, reason = blueprint.createNextAnimation(spr.filename, rect.name, rect.direction)
    isRefreshingCache = false
    if created then
      connectSpriteEvents(app.activeSprite)
      refreshPanel()
    elseif reason ~= "cancelled" then
      app.alert("Could not create animation.")
    end
  end
end

local function onVariantRowClick(rect)
  local spr = app.activeSprite
  if not spr then return end

  local partLayer = blueprint.findLayerByIdOrName(spr.layers, "part", rect.partId, rect.partName)
  if not partLayer then return end

  local slotObj = { id = rect.slotId, name = rect.slotName }
  local variantObj = { id = rect.variantId, name = rect.variantName }
  local variantLayer = blueprint.findVariantLayer(partLayer, slotObj, variantObj)
  if not variantLayer then return end

  app.activeLayer = variantLayer
end

local function scrollbarHitAndDrag(y)
  local visibleHeight = LIST_BOTTOM - previewStartY
  if contentHeight <= visibleHeight then return false end
  local maxScroll = contentHeight - visibleHeight
  local trackY = previewStartY
  local trackH = visibleHeight
  local ratio = math.max(0, math.min(1, (y - trackY) / trackH))
  scrollOffset = math.floor(ratio * maxScroll)
  if dlg then dlg:repaint() end
  return true
end

local function hitTestRows(x, y)
  local oldAnim = hoverAnimRowKey
  local oldVariant = hoverVariantRowKey
  hoverAnimRowKey = nil
  hoverVariantRowKey = nil

  for _, rect in ipairs(animRowRects or {}) do
    if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
      hoverAnimRowKey = rect.key
      break
    end
  end

  if not hoverAnimRowKey then
    for _, rect in ipairs(variantRowRects or {}) do
      if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
        hoverVariantRowKey = rect.key
        break
      end
    end
  end

  if oldAnim ~= hoverAnimRowKey or oldVariant ~= hoverVariantRowKey then
    if dlg then dlg:repaint() end
  end
end

local function onCanvasMouseDown(ev)
  local ok, err = pcall(function()
    local x = ev.x or 0
    local y = ev.y or 0
    if x >= 326 and contentHeight > (LIST_BOTTOM - previewStartY) then
      isDraggingScrollbar = true
      scrollbarHitAndDrag(y)
      return
    end
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
    for _, rect in ipairs(groupHeaderRects or {}) do
      if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
        collapsedGroups[rect.name] = not collapsedGroups[rect.name]
        if dlg then dlg:repaint() end
        return
      end
    end
    for _, rect in ipairs(animRowRects or {}) do
      if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
        isDraggingAnim = true
        dragAnimKey = rect.key
        dragStartY = y
        dragMouseY = y
        return
      end
    end
    for _, rect in ipairs(variantRowRects or {}) do
      if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
        onVariantRowClick(rect)
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
          app.alert("Open a linked animation first.")
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
          app.alert("Open a linked animation first.")
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
          if absent == nil then app.alert("Select a managed outfit layer first.") end
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

      hoverAnimRowKey = nil
      hoverVariantRowKey = nil
    end
  }

  dlg:canvas{
    id = "statusCanvas",
    width = 340,
    height = 260,
    onpaint = onPaint,
    onmousedown = onCanvasMouseDown,
    onmousemove = function(ev)
      if isDraggingScrollbar then
        scrollbarHitAndDrag(ev.y or 0)
      elseif isDraggingAnim then
        dragMouseY = ev.y or 0
        if dlg then dlg:repaint() end
      else
        hitTestRows(ev.x or 0, ev.y or 0)
      end
    end,
    onmouseup = function(ev)
      log("mouseup isDragging=" .. tostring(isDraggingAnim) .. " dragKey=" .. tostring(dragAnimKey))
      if isDraggingAnim and dragAnimKey then
        local dropY = ev.y or 0
        local dragDistance = math.abs(dropY - dragStartY)

        if dragDistance < 4 then
          for _, rect in ipairs(animRowRects or {}) do
            if rect.key == dragAnimKey then
              isDraggingAnim = false
              dragAnimKey = nil
              onAnimRowClick(rect)
              return
            end
          end
        end

        local droppedOnGroup = nil
        for _, rect in ipairs(groupHeaderRects or {}) do
          if dropY >= rect.y and dropY <= rect.y + rect.h then
            droppedOnGroup = rect.name
            break
          end
        end
        local movedToUngrouped = not droppedOnGroup and dropY >= previewStartY

        if droppedOnGroup or movedToUngrouped then
          local spr = app.activeSprite
          if spr and blueprint.isBlueprint(spr) then
            local schema = blueprint.readBlueprintSchema(spr)
            if schema then
              local draggedAnim = nil
              for _, anim in ipairs(schema.animations or {}) do
                if animRowKey(anim) == dragAnimKey then
                  draggedAnim = anim
                  break
                end
              end

              if draggedAnim then
                local newGroup = droppedOnGroup or ""
                local hasDirection = draggedAnim.direction and draggedAnim.direction ~= ""
                local proceed = true

                if hasDirection and newGroup ~= (draggedAnim.group or "") then
                  local choice = app.alert{
                    title = "Move Direction Group",
                    text = "'" .. draggedAnim.name .. "' has multiple directions.\nMove ALL directions to '" .. (newGroup ~= "" and newGroup or "ungrouped") .. "'?",
                    buttons = { "Move All", "Move This Only", "Cancel" },
                  }
                  if choice == 1 then
                    for _, anim in ipairs(schema.animations or {}) do
                      if anim.name == draggedAnim.name then
                        anim.group = newGroup
                      end
                    end
                    proceed = false
                  elseif choice == 3 then
                    proceed = false
                  end
                end

                if proceed then
                  draggedAnim.group = newGroup
                end

                schema = blueprint.normalizeSchema(schema)
                app.transaction(function()
                  blueprint.writeBlueprintSchema(spr, schema)
                end)
                refreshPanel()
              end
            end
          end
        end
        isDraggingAnim = false
        dragAnimKey = nil
        if dlg then dlg:repaint() end
      end
      isDraggingScrollbar = false
    end,
    onwheel = function(ev)
      local visibleHeight = LIST_BOTTOM - previewStartY
      local maxScroll = math.max(0, contentHeight - visibleHeight)
      scrollOffset = math.max(0, math.min(maxScroll, scrollOffset - (ev.deltaY or 0) * 28))
      if dlg then dlg:repaint() end
    end,
  }
  dlg:button{
    id = "btnDetails",
    text = "Details",
    onclick = function()
      showDetailsDialog()
    end
  }
  dlg:label{ id = "statusLabel", text = "Loading..." }
  dlg:label{ id = "detailLabel", text = "" }

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
    id = "btnGoToBlueprint",
    text = "Go to Blueprint",
    onclick = function()
      local ok, err = pcall(function()
        local spr = app.activeSprite
        if not spr then return end
        local data = lastData
        if not data then return end
        local bpPath = blueprintPathForAnimation(spr, data)
        if bpPath and app.fs.isFile(bpPath) then
          app.open(bpPath)
          refreshPanel()
        else
          app.alert("Blueprint not found: " .. tostring(data.blueprint_ref or ""))
        end
      end)
      if not ok then app.alert("Error: " .. tostring(err)) end
    end
  }
  dlg:button{
    id = "btnRefreshSchema",
    text = "Refresh from Blueprint",
    onclick = function()
      local ok, err = pcall(function()
        local spr = app.activeSprite
        if not spr then return end
        local data = lastData
        if not data then return end
        local animPath = spr.filename
        local bpPath = blueprintPathForAnimation(spr, data)
        if not bpPath or not app.fs.isFile(bpPath) then
          app.alert("Blueprint not found: " .. tostring(data.blueprint_ref or ""))
          return
        end
        isRefreshingCache = true
        app.open(bpPath)
        local freshSchema = blueprint.readBlueprintSchema(app.activeSprite)
        app.open(animPath)
        isRefreshingCache = false
        if freshSchema then
          blueprint.cacheSchemaInAnimation(app.activeSprite, freshSchema)
          app.alert("Schema refreshed from blueprint.")
        else
          app.alert("Could not read blueprint schema.")
        end
        connectSpriteEvents(app.activeSprite)
        refreshPanel()
      end)
      if not ok then
        isRefreshingCache = false
        app.alert("Error: " .. tostring(err))
      end
    end
  }
  dlg:button{
    id = "btnEditAnimation",
    text = "Edit Animation",
    onclick = function()
      runAction(function()
        if _blueprintEditorModule then _blueprintEditorModule.showEditAnimationDialog() end
      end)
    end
  }

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
    id = "btnRegister",
    text = "Link Animation",
    onclick = function()
      runAction(function()
        if _blueprintModule then _blueprintModule.showRegisterDialog() end
      end)
    end
  }

  dlg:separator{ text = "View" }
  dlg:combobox{
    id = "slotFilter",
    label = "Layer Set:",
    options = { "all" },
    onchange = function()
      selectedSlotFilter = dlg.data.slotFilter or "all"
    end,
  }
  dlg:button{
    id = "btnSoloSlot",
    text = "Solo Set",
    onclick = function()
      runAction(function()
        local slotName = selectedSlotName()
        local schema = activeSchema()
        if schema and slotName ~= "all" then
          blueprint.setSlotVisibility(app.activeSprite, schema, slotName, "solo")
        else
          app.alert("Choose a layer set first.")
        end
      end)
    end
  }
  dlg:button{
    id = "btnHideSlot",
    text = "Hide Set",
    onclick = function()
      runAction(function()
        local slotName = selectedSlotName()
        local schema = activeSchema()
        if schema and slotName ~= "all" then
          blueprint.setSlotVisibility(app.activeSprite, schema, slotName, "hide")
        else
          app.alert("Choose a layer set first.")
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
    text = "Solo Outfit",
    onclick = function()
      runAction(function()
        if not blueprint.soloActiveVariant(app.activeSprite) then
          app.alert("Select a managed outfit layer first.")
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
      local spr = app.activeSprite
      if spr then connectSpriteEvents(spr) end
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
