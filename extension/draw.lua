-- Drawing helpers for the dialog canvases: theme colors, palette strips,
-- transparency checkerboard, images scaled to fit.

local use = ...
local oklab = use("snapper/oklab")

local M = {}

local fallback = {
  text = Color { r = 230, g = 230, b = 230 },
  disabled = Color { r = 140, g = 140, b = 140 },
  face = Color { r = 60, g = 60, b = 60 },
  listitem_normal_text = Color { r = 230, g = 230, b = 230 },
  listitem_normal_face = Color { r = 45, g = 45, b = 45 },
  listitem_selected_text = Color { r = 255, g = 255, b = 255 },
  listitem_selected_face = Color { r = 90, g = 90, b = 100 },
}

-- A color of the current Aseprite theme.
function M.theme(name)
  local ok, c = pcall(function()
    return app.theme.color[name]
  end)
  if ok and c then
    return c
  end
  return fallback[name] or fallback.text
end

local function keyColor(key)
  local r, g, b = oklab.channels(key)
  return Color { r = r, g = g, b = b, a = 255 }
end

-- How tall a strip of `count` colors is, wrapped in `width`.
function M.stripHeight(count, width, cell)
  if count == 0 then
    return 0
  end
  local perLine = math.max(1, width // cell)
  return math.ceil(count / perLine) * cell
end

-- Palette colors as a row of squares, wrapping at `width`. Returns the height.
function M.strip(gc, keys, x, y, width, cell)
  local perLine = math.max(1, width // cell)
  for i, k in ipairs(keys) do
    local col, row = (i - 1) % perLine, (i - 1) // perLine
    gc.color = keyColor(k)
    gc:fillRect(Rectangle(x + col * cell, y + row * cell, cell, cell))
  end
  return M.stripHeight(#keys, width, cell)
end

-- A light/dark checkerboard, as behind transparent pixels.
function M.checker(gc, rect, size)
  size = size or 6
  local light, dark = Color { r = 140, g = 140, b = 140 }, Color { r = 100, g = 100, b = 100 }
  gc.color = light
  gc:fillRect(rect)
  gc.color = dark
  for y = 0, rect.height - 1, size do
    for x = ((y // size) % 2) * size, rect.width - 1, size * 2 do
      gc:fillRect(Rectangle(rect.x + x, rect.y + y, math.min(size, rect.width - x), math.min(size, rect.height - y)))
    end
  end
end

-- Where an image of w*h lands in `rect`: whole-number zoom when it fits
-- (crisp pixels), otherwise shrunk to fit; centered.
function M.fit(w, h, rect)
  local scale = math.min(rect.width / w, rect.height / h)
  if scale >= 1 then
    scale = math.floor(scale)
  end
  local dw, dh = math.max(1, math.floor(w * scale)), math.max(1, math.floor(h * scale))
  return Rectangle(rect.x + (rect.width - dw) // 2, rect.y + (rect.height - dh) // 2, dw, dh)
end

function M.image(gc, image, rect)
  local target = M.fit(image.width, image.height, rect)
  M.checker(gc, target)
  gc:drawImage(image, Rectangle(0, 0, image.width, image.height), target)
end

-- Text cut with "…" to fit in `width`.
function M.ellipsize(gc, text, width)
  if gc:measureText(text).width <= width then
    return text
  end
  while #text > 0 and gc:measureText(text .. "…").width > width do
    text = text:sub(1, -2)
    -- Don't leave half of a UTF-8 character.
    while #text > 0 and text:byte(-1) >= 0x80 and text:byte(-1) < 0xC0 do
      text = text:sub(1, -2)
    end
    if #text > 0 and text:byte(-1) >= 0xC0 then
      text = text:sub(1, -2)
    end
  end
  return text .. "…"
end

return M
