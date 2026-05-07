local blueprint = require("blueprint")
local validator = require("validator")
local utils = require("ui.utils")

local panel = {}

local dlg = nil
local currentSprite = nil
local cachedLayerHash = ""
local debounceTimer = nil
local isRefreshingCache = false

local spriteChangeHandler = nil
local spriteLayerNameHandler = nil
local siteChangeHandler = nil

local lastValidation = nil

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

local function runValidation()
  if not currentSprite then
    lastValidation = nil
    return
  end

  if not blueprint.isAnimation(currentSprite) then
    lastValidation = nil
    return
  end

  local data = blueprint.readAnimationData(currentSprite)
  if not data or not data.cached_schema then
    lastValidation = nil
    return
  end

  lastValidation = validator.validate(currentSprite, data.cached_schema)
  cachedLayerHash = validator.buildLayerTreeHash(currentSprite)

  if dlg then
    dlg:repaint()
  end
end

local function onSpriteChange(ev)
  if debounceTimer then
    debounceTimer:stop()
  end
  debounceTimer = Timer{
    interval = 0.5,
    ontick = function(timer)
      timer:stop()
      local newHash = validator.buildLayerTreeHash(currentSprite)
      if newHash ~= cachedLayerHash then
        runValidation()
      end
    end
  }
  debounceTimer:start()
end

local function onLayerName(ev)
  runValidation()
end

local function connectSpriteEvents(sprite)
  disconnectSpriteEvents()
  currentSprite = sprite
  if not sprite then return end

  spriteChangeHandler = sprite.events:on("change", onSpriteChange)
  spriteLayerNameHandler = sprite.events:on("layername", onLayerName)
end

local lastCheckedFilename = nil

local function checkSchemaFreshness(spr)
  if not spr or not spr.filename then return end
  if spr.filename == lastCheckedFilename then return end

  lastCheckedFilename = spr.filename

  if not blueprint.isAnimation(spr) then return end

  local data = blueprint.readAnimationData(spr)
  if not data or not data.blueprint_ref or data.blueprint_ref == "" then return end

  local sprDir = app.fs.filePath(spr.filename)
  local bpPath = app.fs.joinPath(sprDir, data.blueprint_ref)

  if not app.fs.isFile(bpPath) then return end

  isRefreshingCache = true
  local bpSprite = app.open(bpPath)
  isRefreshingCache = false

  if not bpSprite then return end

  local schema = blueprint.readBlueprintSchema(bpSprite)
  bpSprite:close()

  if not schema then return end

  local cachedTimestamp = 0
  if data.cached_schema and data.cached_schema.cache_timestamp then
    cachedTimestamp = data.cached_schema.cache_timestamp
  end

  local needsRefresh = false
  if cachedTimestamp == 0 then
    needsRefresh = true
  else
    local cachedParts = data.cached_schema and data.cached_schema.body_parts or {}
    local cachedVariants = data.cached_schema and data.cached_schema.variants or {}
    if #cachedParts ~= #(schema.body_parts or {}) or #cachedVariants ~= #(schema.variants or {}) then
      needsRefresh = true
    else
      for i, part in ipairs(schema.body_parts or {}) do
        if not cachedParts[i] or cachedParts[i].name ~= part.name then
          needsRefresh = true
          break
        end
      end
      if not needsRefresh then
        for i, v in ipairs(schema.variants or {}) do
          if not cachedVariants[i] or cachedVariants[i].name ~= v.name then
            needsRefresh = true
            break
          end
        end
      end
    end
  end

  if needsRefresh then
    local diff = #(schema.body_parts or {}) - #(data.cached_schema and data.cached_schema.body_parts or {})
    local msg = "Blueprint updated"
    if diff > 0 then
      msg = msg .. " — " .. diff .. " new requirement(s) detected"
    elseif diff < 0 then
      msg = msg .. " — " .. math.abs(diff) .. " requirement(s) removed"
    else
      msg = msg .. " — structure changed"
    end
    msg = msg .. ". Accept update?"

    local accept = app.alert{
      title = "CharacterForge",
      text = msg,
      buttons = { "Accept", "Dismiss" }
    }
    if accept == 1 then
      blueprint.cacheSchemaInAnimation(spr, schema)
    end
  end
end

local function onSiteChange()
  if isRefreshingCache then return end

  local spr = app.activeSprite
  if spr ~= currentSprite then
    connectSpriteEvents(spr)
    checkSchemaFreshness(spr)
    runValidation()
  end
end

local function onPaint(ev)
  local gc = ev.context
  local bounds = gc.width and { width = gc.width, height = gc.height }
    or { width = 200, height = 150 }

  gc:drawThemeRect("sunken_normal", Rectangle(0, 0, bounds.width, bounds.height))

  if not currentSprite then
    gc.color = utils.COLOR_TEXT
    gc:fillText("No sprite open", 8, 8)
    return
  end

  if not blueprint.isAnimation(currentSprite) then
    gc.color = utils.COLOR_TEXT
    gc:fillText("Not a CharacterForge animation", 8, 8)
    return
  end

  local data = blueprint.readAnimationData(currentSprite)
  if not data then
    gc.color = utils.COLOR_TEXT
    gc:fillText("No animation data", 8, 8)
    return
  end

  local y = 4
  gc.color = utils.COLOR_TEXT
  gc:fillText(data.character_name .. " / " .. data.animation_name, 8, y)
  y = y + 16

  if not data.cached_schema then
    gc.color = utils.COLOR_WARN
    gc:fillText("No cached schema — register to a blueprint", 8, y)
    return
  end

  if not lastValidation then
    runValidation()
  end

  if lastValidation then
    for _, ls in ipairs(lastValidation.layer_status or {}) do
      local color = utils.COLOR_PASS
      local hasErrors = false
      for _, err in ipairs(lastValidation.errors or {}) do
        if string.find(err, ls.part, 1, true) then
          color = utils.COLOR_FAIL
          hasErrors = true
          break
        end
      end
      if not hasErrors then
        for _, warn in ipairs(lastValidation.warnings or {}) do
          if string.find(warn, ls.part, 1, true) then
            color = utils.COLOR_WARN
            break
          end
        end
      end

      gc.color = color
      gc:fillRect(Rectangle(8, y + 2, 8, 8))
      gc.color = utils.COLOR_TEXT
      gc:fillText(ls.part .. " (" .. ls.base_frames .. "f)", 20, y)
      y = y + 14
    end

    if #lastValidation.errors > 0 then
      y = y + 4
      gc.color = utils.COLOR_FAIL
      gc:fillText(#lastValidation.errors .. " error(s)", 8, y)
    elseif #lastValidation.warnings > 0 then
      y = y + 4
      gc.color = utils.COLOR_WARN
      gc:fillText(#lastValidation.warnings .. " warning(s)", 8, y)
    else
      y = y + 4
      gc.color = utils.COLOR_PASS
      gc:fillText("All checks pass", 8, y)
    end
  end

  y = y + 16
  if data.blueprint_ref and data.blueprint_ref ~= "" then
    local bpPath = app.fs.joinPath(app.fs.filePath(currentSprite.filename), data.blueprint_ref)
    if not app.fs.isFile(bpPath) then
      gc.color = utils.COLOR_WARN
      gc:fillText("Blueprint not found — using cached schema", 8, y)
    end
  end
end

function panel.toggle()
  if dlg then
    panel.close()
  else
    panel.open()
  end
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
    end
  }

  dlg:canvas{
    id = "statusCanvas",
    width = 220,
    height = 180,
    onpaint = onPaint,
  }

  dlg:show{ wait = false }

  siteChangeHandler = app.events:on("sitechange", onSiteChange)
  connectSpriteEvents(app.activeSprite)
  runValidation()
end

function panel.close()
  if dlg then
    dlg:close()
  end
end

panel.isRefreshingCache = isRefreshingCache

return panel
