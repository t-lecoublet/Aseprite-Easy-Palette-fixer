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

-- Zoom and pan. A view is { zoom, cx, cy }: zoom 1 fits the image in its
-- panel; cx, cy is the image point shown at the panel's center, as fractions
-- of the image size, so panels of different resolutions show the same area.
M.FIT = { zoom = 1, cx = 0.5, cy = 0.5 }
M.MAX_ZOOM = 64

local function fitScale(w, h, rect)
  local scale = math.min(rect.width / w, rect.height / h)
  if scale >= 1 then
    scale = math.floor(scale)
  end
  return scale
end

-- Where a w x h image lands in `rect` for `view`: { scale, x, y } (the
-- screen position of its top-left corner), and the view's center clamped so
-- the image never leaves empty space on a side it could cover.
function M.transform(w, h, rect, view)
  local scale = fitScale(w, h, rect) * view.zoom
  if scale >= 1 then
    scale = math.floor(scale + 1e-6) -- whole numbers keep pixels crisp
  end
  local function center(fraction, size, room)
    if size * scale <= room then
      return size / 2
    end
    local half = room / 2 / scale
    return math.min(math.max(fraction * size, half), size - half)
  end
  local cx, cy = center(view.cx, w, rect.width), center(view.cy, h, rect.height)
  return {
    scale = scale,
    x = rect.x + rect.width / 2 - cx * scale,
    y = rect.y + rect.height / 2 - cy * scale,
    cx = cx / w,
    cy = cy / h,
  }
end

-- The view zoomed by `factor`, keeping the image point under (mx, my) still.
function M.zoomAt(view, w, h, rect, mx, my, factor)
  local t = M.transform(w, h, rect, view)
  local u, v = (mx - t.x) / t.scale / w, (my - t.y) / t.scale / h
  local zoom = math.min(math.max(view.zoom * factor, 1), M.MAX_ZOOM)
  local s = M.transform(w, h, rect, { zoom = zoom, cx = 0.5, cy = 0.5 }).scale
  local moved = {
    zoom = zoom,
    cx = u - (mx - (rect.x + rect.width / 2)) / (w * s),
    cy = v - (my - (rect.y + rect.height / 2)) / (h * s),
  }
  local clamped = M.transform(w, h, rect, moved)
  moved.cx, moved.cy = clamped.cx, clamped.cy
  return moved
end

-- `start` moved by (dx, dy) screen pixels, as when dragging.
function M.pan(start, w, h, rect, dx, dy)
  local t = M.transform(w, h, rect, start)
  local moved = { zoom = start.zoom, cx = t.cx - dx / (t.scale * w), cy = t.cy - dy / (t.scale * h) }
  local clamped = M.transform(w, h, rect, moved)
  moved.cx, moved.cy = clamped.cx, clamped.cy
  return moved
end

-- Draws `image` in `rect` (clipped to it) for `view`, over a checkerboard.
-- Returns the transform, to draw overlays at image coordinates.
function M.image(gc, image, rect, view)
  local w, h = image.width, image.height
  local t = M.transform(w, h, rect, view or M.FIT)
  local x0 = math.max(0, math.floor((rect.x - t.x) / t.scale))
  local y0 = math.max(0, math.floor((rect.y - t.y) / t.scale))
  local x1 = math.min(w, math.ceil((rect.x + rect.width - t.x) / t.scale))
  local y1 = math.min(h, math.ceil((rect.y + rect.height - t.y) / t.scale))
  if x1 <= x0 or y1 <= y0 then
    return t
  end
  local left, top = math.floor(t.x + x0 * t.scale + 0.5), math.floor(t.y + y0 * t.scale + 0.5)
  local dst = Rectangle(left, top,
    math.max(1, math.floor(t.x + x1 * t.scale + 0.5) - left),
    math.max(1, math.floor(t.y + y1 * t.scale + 0.5) - top))
  gc:save()
  gc:beginPath()
  gc:rect(rect)
  gc:clip()
  M.checker(gc, dst:intersect(rect))
  gc:drawImage(image, Rectangle(x0, y0, x1 - x0, y1 - y0), dst)
  gc:restore()
  return t
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
