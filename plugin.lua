local blueprint = require("blueprint")
local validator = require("validator")
local panel = require("ui.panel")
local blueprintEditor = require("ui.blueprint_editor")

local beforeCommandHandler
local afterCommandHandler

function init(plugin)
  if app.apiVersion < 23 then
    return app.alert("CharacterForge requires Aseprite v1.3-rc3 or later")
  end

  plugin:newMenuGroup{
    id = "characterForge",
    title = "CharacterForge",
    group = "sprite_properties"
  }

  plugin:newCommand{
    id = "createBlueprint",
    title = "Create Blueprint...",
    group = "characterForge",
    onclick = function()
      blueprintEditor.showCreateDialog()
    end,
    onenabled = function()
      return true
    end
  }

  plugin:newCommand{
    id = "newAnimationFromBlueprint",
    title = "New Animation from Blueprint...",
    group = "characterForge",
    onclick = function()
      blueprint.showNewAnimationDialog()
    end,
    onenabled = function()
      return true
    end
  }

  plugin:newCommand{
    id = "registerAnimation",
    title = "Register Animation...",
    group = "characterForge",
    onclick = function()
      blueprint.showRegisterDialog()
    end,
    onenabled = function()
      return app.activeSprite ~= nil
    end
  }

  plugin:newCommand{
    id = "validationPanel",
    title = "Validation Panel",
    group = "characterForge",
    onclick = function()
      panel.toggle()
    end,
    onenabled = function()
      return app.activeSprite ~= nil
    end
  }

  beforeCommandHandler = function(ev)
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
      local msg = "CharacterForge: Cannot save — structural errors found:\n\n"
      for _, err in ipairs(result.errors) do
        msg = msg .. "• " .. err .. "\n"
      end
      app.alert(msg)
    end
  end

  afterCommandHandler = function(ev)
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
  end

  app.events:on("beforecommand", beforeCommandHandler)
  app.events:on("aftercommand", afterCommandHandler)
end

function exit(plugin)
  panel.close()
end
