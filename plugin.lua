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

  if blueprint and blueprint.setPreferences then
    blueprint.setPreferences(plugin.preferences)
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

    plugin:newCommand{
      id = "cfCreateBlueprint",
      title = "CharacterForge: New Blueprint",
      group = "sprite_properties",
      onclick = function()
        local ok, err = pcall(function()
          if blueprintEditor then blueprintEditor.showCreateDialog() end
        end)
        if not ok then log("ERROR in cfCreateBlueprint: " .. tostring(err)); app.alert("Error: " .. tostring(err)) end
      end
    }

    plugin:newCommand{
      id = "cfBlueprintFromCurrent",
      title = "CharacterForge: Blueprint From Current Sprite",
      group = "sprite_properties",
      onclick = function()
        local ok, err = pcall(function()
          if blueprint then blueprint.showCreateFromCurrentDialog() end
        end)
        if not ok then log("ERROR in cfBlueprintFromCurrent: " .. tostring(err)); app.alert("Error: " .. tostring(err)) end
      end,
      onenabled = function()
        return app.activeSprite ~= nil
      end
    }

    plugin:newCommand{
      id = "cfEditBlueprint",
      title = "CharacterForge: Edit Blueprint",
      group = "sprite_properties",
      onclick = function()
        local ok, err = pcall(function()
          if blueprintEditor then blueprintEditor.showEditDialog() end
        end)
        if not ok then log("ERROR in cfEditBlueprint: " .. tostring(err)); app.alert("Error: " .. tostring(err)) end
      end,
      onenabled = function()
        return app.activeSprite ~= nil and blueprint and blueprint.isBlueprint(app.activeSprite)
      end
    }

    plugin:newCommand{
      id = "cfNewAnimation",
      title = "CharacterForge: New Animation",
      group = "sprite_properties",
      onclick = function()
        local ok, err = pcall(function()
          if blueprint then blueprint.showNewAnimationDialog() end
        end)
        if not ok then log("ERROR in cfNewAnimation: " .. tostring(err)); app.alert("Error: " .. tostring(err)) end
      end
    }

    plugin:newCommand{
      id = "cfRegisterAnimation",
      title = "CharacterForge: Register Animation",
      group = "sprite_properties",
      onclick = function()
        local ok, err = pcall(function()
          if blueprint then blueprint.showRegisterDialog() end
        end)
        if not ok then log("ERROR in cfRegisterAnimation: " .. tostring(err)); app.alert("Error: " .. tostring(err)) end
      end,
      onenabled = function()
        return app.activeSprite ~= nil
      end
    }

    plugin:newCommand{
      id = "cfToggleSaveMode",
      title = "CharacterForge: Toggle Strict Save",
      group = "sprite_properties",
      onclick = function()
        local ok, err = pcall(function()
          if blueprint then
            local mode = blueprint.toggleSaveMode()
            app.alert("CharacterForge save mode: " .. (mode == "block" and "strict blocking" or "warn only"))
          end
        end)
        if not ok then log("ERROR in cfToggleSaveMode: " .. tostring(err)); app.alert("Error: " .. tostring(err)) end
      end
    }

    plugin:newCommand{
      id = "cfSoloPart",
      title = "CharacterForge: Solo Active Part",
      group = "sprite_properties",
      onclick = function()
        local ok, err = pcall(function()
          if blueprint and not blueprint.soloActivePart(app.activeSprite) then
            app.alert("Select a layer inside a managed body part first.")
          end
        end)
        if not ok then log("ERROR in cfSoloPart: " .. tostring(err)); app.alert("Error: " .. tostring(err)) end
      end,
      onenabled = function() return app.activeSprite ~= nil end
    }

    plugin:newCommand{
      id = "cfSoloVariant",
      title = "CharacterForge: Solo Active Variant",
      group = "sprite_properties",
      onclick = function()
        local ok, err = pcall(function()
          if blueprint and not blueprint.soloActiveVariant(app.activeSprite) then
            app.alert("Select a managed variant layer first.")
          end
        end)
        if not ok then log("ERROR in cfSoloVariant: " .. tostring(err)); app.alert("Error: " .. tostring(err)) end
      end,
      onenabled = function() return app.activeSprite ~= nil end
    }

    plugin:newCommand{
      id = "cfShowAllManaged",
      title = "CharacterForge: Show All Managed Layers",
      group = "sprite_properties",
      onclick = function()
        local ok, err = pcall(function()
          if blueprint then blueprint.showAllManagedLayers(app.activeSprite) end
        end)
        if not ok then log("ERROR in cfShowAllManaged: " .. tostring(err)); app.alert("Error: " .. tostring(err)) end
      end,
      onenabled = function() return app.activeSprite ~= nil end
    }
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
        if result.result == "fail" and blueprint.getSaveMode and blueprint.getSaveMode() == "block" then
          ev.stopPropagation()
          local msg = "CharacterForge: Cannot save - structural errors:\n\n"
          for _, e in ipairs(result.errors) do
            msg = msg .. "- " .. e .. "\n"
          end
          msg = msg .. "\nUse CharacterForge: Toggle Strict Save to switch to warn-only mode."
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
  if panel and panel.close then
    pcall(panel.close)
  end
  if logFile then logFile:close() end
end
