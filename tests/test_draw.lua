-- The preview's zoom and pan, and drawing a zoomed image (on an image's
-- graphics context, since batch mode has no window).

local t = ...
local test, eq = t.test, t.eq
local draw = t.use("draw")

local RECT = Rectangle(10, 20, 100, 50)

-- Rounded to 1e-9, for float results.
local function r(values)
  local out = {}
  for i, v in ipairs(values) do
    out[i] = math.floor(v * 1e9 + 0.5) / 1e9
  end
  return out
end

test("transform: fit, whole-number zoom, centered", function()
  local f = draw.transform(10, 5, RECT, draw.FIT)
  eq({ f.scale, f.x, f.y }, { 10, 10, 20 }, "fit 10x5 in 100x50")
  local z = draw.transform(10, 5, RECT, { zoom = 2, cx = 0.5, cy = 0.5 })
  eq({ z.scale, z.x, z.y }, { 20, -40, -5 }, "x2 around the center")
  local small = draw.transform(1000, 500, RECT, draw.FIT)
  eq(small.scale, 0.1, "big images shrink")
end)

test("transform: the center is kept inside the image", function()
  local z = draw.transform(10, 5, RECT, { zoom = 2, cx = 0, cy = 1 })
  eq({ z.cx, z.cy, z.x, z.y }, { 0.25, 0.75, 10, -30 }, "left and bottom edges stay on the panel's")
end)

test("zoomAt keeps the point under the mouse still; zoom is limited", function()
  local view = draw.zoomAt(draw.FIT, 10, 5, RECT, 30, 30, 2) -- image point (2, 1)
  local z = draw.transform(10, 5, RECT, view)
  eq(r({ view.zoom, (30 - z.x) / z.scale, (30 - z.y) / z.scale }), { 2, 2.0, 1.0 })
  eq(draw.zoomAt(draw.FIT, 10, 5, RECT, 30, 30, 0.5).zoom, 1, "not below fit")
  eq(draw.zoomAt({ zoom = 64, cx = 0.5, cy = 0.5 }, 10, 5, RECT, 30, 30, 2).zoom, draw.MAX_ZOOM)
end)

test("pan moves the view with the mouse, within the image", function()
  local start = { zoom = 2, cx = 0.5, cy = 0.5 }
  local moved = draw.pan(start, 10, 5, RECT, 20, 0) -- 20 screen px = 1 image px at x20
  eq(r({ moved.cx, moved.cy }), { 0.4, 0.5 })
  eq(draw.pan(start, 10, 5, RECT, 1000, 0).cx, 0.25, "stops at the left edge")
end)

test("image: draws only what's visible, zoomed, clipped to its panel", function()
  local source = Image(4, 4, ColorMode.RGB)
  source:clear(app.pixelColor.rgba(0, 0, 255, 255))
  source:drawPixel(0, 0, app.pixelColor.rgba(255, 0, 0, 255))
  local canvas = Image(40, 40, ColorMode.RGB)
  local gc = canvas.context
  if not gc then
    return -- no graphics context in this Aseprite
  end
  -- Zoomed x2 on the top-left corner: the red pixel fills 20x20 screen pixels.
  draw.image(gc, source, Rectangle(0, 0, 40, 40), { zoom = 2, cx = 0, cy = 0 })
  local function at(x, y)
    local c = canvas:getPixel(x, y)
    return { app.pixelColor.rgbaR(c), app.pixelColor.rgbaG(c), app.pixelColor.rgbaB(c) }
  end
  eq(at(5, 5), { 255, 0, 0 }, "red, zoomed")
  eq(at(19, 5), { 255, 0, 0 }, "crisp: still red at the edge")
  eq(at(20, 5), { 0, 0, 255 }, "crisp: blue right after")
  eq(at(25, 5), { 0, 0, 255 }, "blue next to it")
  eq(at(35, 35), { 0, 0, 255 }, "the view reaches the panel's corner")
end)
