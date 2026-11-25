-- Presets, palettes for the strip, and the before/after preview.

local t = ...
local test, eq, fails = t.test, t.eq, t.fails
local dialog = t.use("dialog")
local presets = t.use("presets")
local recolor = t.use("recolor")
local fs = app.fs

local NOISY = { { 200, 40, 40 }, { 200, 40, 40 }, { 202, 41, 39 }, { 40, 40, 200 } }

local function sprite(pixels)
  local s = Sprite(#pixels, 1, ColorMode.RGB)
  local image = Image(#pixels, 1, ColorMode.RGB)
  for x, p in ipairs(pixels) do
    image:drawPixel(x - 1, 0, app.pixelColor.rgba(p[1], p[2], p[3], 255))
  end
  s:newCel(s.layers[1], 1, image, Point(0, 0))
  return s
end

local function find(list, id)
  for _, entry in ipairs(list) do
    if entry.id == id then
      return entry
    end
  end
end

test("presets: Aseprite's built-in palettes, sorted by name, with their colors", function()
  local list = presets.find()
  assert(#list > 50, "only " .. #list .. " presets")
  for i = 2, #list do
    assert(list[i - 1].id:lower() <= list[i].id:lower(), "not sorted at " .. list[i].id)
  end
  local aap = find(list, "AAP-64")
  assert(aap, "AAP-64 missing")
  eq(#presets.colors(aap.path), 64, "AAP-64 colors")
  assert(not find(list, "default"), "the default palette is skipped, like Aseprite does")
end)

test("paletteFor: a preset, read once with a cache", function()
  local aap = find(presets.find(), "AAP-64")
  local settings = dialog.settings({ mode = "snap", source = "preset", presetId = aap.id, presetPath = aap.path })
  local cache = {}
  eq(#dialog.paletteFor(settings, cache), 64)
  eq(#dialog.paletteFor(settings, cache), 64)
  fails(function() dialog.paletteFor(dialog.settings({ mode = "snap", source = "preset" })) end, "Choose a palette preset")
end)

test("preview of the active sprite: before, after and the result's colors, nothing changed", function()
  local s = sprite(NOISY)
  app.sprite = s
  local settings = dialog.settings({ target = "sprite" })
  local before = s.cels[1].image.bytes
  local p = dialog.preview(dialog.previewSource(settings), dialog.options(settings))
  eq({ p.beforeCount, p.afterCount }, { 3, 2 })
  eq({ p.after.bytes:byte(9, 12) }, { 200, 40, 40, 255 }, "after")
  eq({ p.before.bytes:byte(9, 12) }, { 202, 41, 39, 255 }, "before")
  eq(p.targets, { 0x2828c8, 0xc82828 }, "result colors, darkest first")
  eq(s.cels[1].image.bytes, before, "sprite untouched")
end)

test("preview of an indexed sprite renders its colors", function()
  local s = Sprite(2, 1, ColorMode.INDEXED)
  local pal = Palette(3)
  pal:setColor(0, Color { r = 0, g = 0, b = 0, a = 255 })
  pal:setColor(1, Color { r = 10, g = 20, b = 30, a = 255 })
  pal:setColor(2, Color { r = 230, g = 240, b = 200, a = 255 })
  s:setPalette(pal)
  local image = Image(2, 1, ColorMode.INDEXED)
  image:drawPixel(0, 0, 0) -- the transparent index
  image:drawPixel(1, 0, 2)
  s:newCel(s.layers[1], 1, image, Point(0, 0))
  app.sprite = s
  app.cel = s.cels[1]
  local settings = dialog.settings({ mode = "snap", source = "hex", hexColors = "#081820 #e0f8d0", target = "cels" })
  local p = dialog.preview(dialog.previewSource(settings), dialog.options(settings))
  eq({ p.before.bytes:byte(1, 8) }, { 0, 0, 0, 0, 230, 240, 200, 255 }, "before")
  eq({ p.after.bytes:byte(5, 8) }, { 224, 248, 208, 255 }, "after")
end)

test("preview of a folder shows the chosen image", function()
  local dir = fs.joinPath(t.tmp, "preview")
  fs.makeDirectory(dir)
  local s = sprite(NOISY)
  local path = fs.joinPath(dir, "p.png")
  s:saveCopyAs(path)
  s:close()
  local settings = dialog.settings({ target = "folder", folderFile = path, maxColors = 1 })
  local p = dialog.preview(dialog.previewSource(settings), dialog.options(settings))
  eq({ p.beforeCount, p.afterCount, p.what }, { 3, 1, "p.png" })
  fails(function() dialog.previewSource(dialog.settings({ target = "folder" })) end, "Choose an image")
end)
