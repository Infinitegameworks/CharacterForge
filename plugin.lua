-- CharacterForge - Aseprite Extension

local logFile = io.open(app.fs.joinPath(app.fs.tempPath, "characterforge.log"), "w")
local function log(msg)
  if logFile then
    logFile:write(os.date("%H:%M:%S") .. " " .. msg .. "\n")
    logFile:flush()
  end
end

log("CharacterForge loading...")
log("API version: " .. tostring(app.apiVersion))

local ok, blueprint = pcall(require, 'blueprint')
if not ok then log("ERROR loading blueprint: " .. tostring(blueprint)); blueprint = nil
else log("blueprint loaded OK") end

local ok2, validator = pcall(require, 'validator')
if not ok2 then log("ERROR loading validator: " .. tostring(validator)); validator = nil
else log("validator loaded OK") end

local ok3, panel = pcall(require, 'panel')
if not ok3 then log("ERROR loading panel: " .. tostring(panel)); panel = nil
else log("panel loaded OK") end

local ok4, blueprintEditor = pcall(require, 'blueprint_editor')
if not ok4 then log("ERROR loading blueprint_editor: " .. tostring(blueprintEditor)); blueprintEditor = nil
else log("blueprint_editor loaded OK") end

function init(plugin)
  log("init() called")

  if app.apiVersion < 23 then
    log("API version too old")
    return app.alert("CharacterForge requires Aseprite v1.3-rc3 or later")
  end

  local cmdOk, cmdErr = pcall(function()
    plugin:newCommand{
      id = "cfOpenPanel",
      title = "CharacterForge",
      group = "sprite_properties",
      onclick = function()
        log("cfOpenPanel clicked")
        local ok, err = pcall(function()
          if panel then panel.toggle(blueprint, blueprintEditor) end
        end)
        if not ok then log("ERROR in cfOpenPanel: " .. tostring(err)); app.alert("Error: " .. tostring(err)) end
      end
    }
    log("registered cfOpenPanel")
  end)

  if not cmdOk then
    log("ERROR registering commands: " .. tostring(cmdErr))
  else
    log("all commands registered")
  end

  if blueprint then
    app.events:on("beforecommand", function(ev)
      local ok, err = pcall(function()
        if ev.name ~= "SaveFile" and ev.name ~= "SaveFileAs" and ev.name ~= "SaveFileCopyAs" then
          return
        end
        local spr = app.activeSprite
        if not spr then return end
        if not blueprint.isAnimation(spr) then return end
        local data = blueprint.readAnimationData(spr)
        if not data or not data.cached_schema then return end
        local result = validator.validate(spr, data.cached_schema)
        if result.result == "fail" then
          ev.stopPropagation()
          local msg = "CharacterForge: Cannot save — structural errors:\n\n"
          for _, e in ipairs(result.errors) do
            msg = msg .. "- " .. e .. "\n"
          end
          app.alert(msg)
        end
      end)
      if not ok then log("ERROR in beforecommand: " .. tostring(err)) end
    end)

    app.events:on("aftercommand", function(ev)
      local ok, err = pcall(function()
        if ev.name ~= "SaveFile" and ev.name ~= "SaveFileAs" and ev.name ~= "SaveFileCopyAs" then
          return
        end
        local spr = app.activeSprite
        if not spr then return end
        if not blueprint.isAnimation(spr) then return end
        local data = blueprint.readAnimationData(spr)
        if not data or not data.cached_schema then return end
        local result = validator.validate(spr, data.cached_schema)
        blueprint.writeValidationResult(spr, result)
      end)
      if not ok then log("ERROR in aftercommand: " .. tostring(err)) end
    end)
    log("event handlers wired")
  end

  log("init() complete")
end

function exit(plugin)
  log("exit() called")
  if logFile then logFile:close() end
end
