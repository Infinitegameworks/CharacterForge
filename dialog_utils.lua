local utils = require 'utils'

local dialogUtils = {}

local ROW_HEIGHT = 14
local PADDING = 6
local TEXT_COLOR = Color{ r = 220, g = 220, b = 220, a = 255 }
local MUTED_COLOR = Color{ r = 150, g = 150, b = 150, a = 255 }
local BG_COLOR = Color{ r = 40, g = 40, b = 40, a = 255 }
local STRIPE_COLOR = Color{ r = 50, g = 50, b = 50, a = 255 }
local SCROLLBAR_TRACK = Color{ r = 55, g = 55, b = 55, a = 255 }
local SCROLLBAR_THUMB = Color{ r = 100, g = 100, b = 100, a = 255 }

function dialogUtils.scrollableList(dlg, id, width, height, items, emptyText)
  local scrollOffset = 0
  local contentHeight = #items * ROW_HEIGHT
  local visibleHeight = height - PADDING * 2

  dlg:canvas{
    id = id,
    width = width,
    height = height,
    onpaint = function(ev)
      local gc = ev.context
      gc.color = BG_COLOR
      gc:fillRect(Rectangle(0, 0, width, height))

      if #items == 0 then
        gc.color = MUTED_COLOR
        gc:fillText(emptyText or "(none)", PADDING, PADDING)
        return
      end

      for i, item in ipairs(items) do
        local y = PADDING + (i - 1) * ROW_HEIGHT - scrollOffset
        if y >= -ROW_HEIGHT and y < height then
          if (i - 1) % 2 == 0 then
            gc.color = STRIPE_COLOR
            gc:fillRect(Rectangle(PADDING, y, width - PADDING * 2 - 10, ROW_HEIGHT))
          end
          gc.color = TEXT_COLOR
          local text = type(item) == "table" and (item.label or item.name or tostring(item)) or tostring(item)
          gc:fillText(text, PADDING + 4, y + 2)
        end
      end

      if contentHeight > visibleHeight then
        local trackX = width - 8
        local trackH = height - PADDING * 2
        local thumbH = math.max(12, math.floor(trackH * visibleHeight / contentHeight))
        local maxScroll = contentHeight - visibleHeight
        local thumbY = PADDING + math.floor((trackH - thumbH) * scrollOffset / math.max(1, maxScroll))
        gc.color = SCROLLBAR_TRACK
        gc:fillRect(Rectangle(trackX, PADDING, 6, trackH))
        gc.color = SCROLLBAR_THUMB
        gc:fillRect(Rectangle(trackX, thumbY, 6, thumbH))
      end
    end,
    onwheel = function(ev)
      local maxScroll = math.max(0, contentHeight - visibleHeight)
      scrollOffset = math.max(0, math.min(maxScroll, scrollOffset - (ev.deltaY or 0) * ROW_HEIGHT * 2))
      dlg:repaint()
    end,
  }
end

function dialogUtils.truncateAlert(title, lines, maxLines)
  maxLines = maxLines or 3
  if #lines <= maxLines then
    app.alert{ title = title, text = table.concat(lines, "\n") }
    return
  end

  local shown = {}
  for i = 1, maxLines do shown[i] = lines[i] end
  shown[#shown + 1] = "... and " .. (#lines - maxLines) .. " more"
  app.alert{ title = title, text = table.concat(shown, "\n") }
end

return dialogUtils
