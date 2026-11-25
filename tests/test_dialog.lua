-- The window's logic, without the window (batch mode has no UI).

local t = ...
local test, eq, fails = t.test, t.eq, t.fails
local dialog = t.use("dialog")
local fs = app.fs

local function sprite(pixels)
  local s = Sprite(#pixels, 1, ColorMode.RGB)
  local image = Image(#pixels, 1, ColorMode.RGB)
  for x, p in ipairs(pixels) do
    image:drawPixel(x - 1, 0, app.pixelColor.rgba(p[1], p[2], p[3], 255))
  end
  s:newCel(s.layers[1], 1, image, Point(0, 0))
  return s
end

local NOISY = { { 200, 40, 40 }, { 200, 40, 40 }, { 202, 41, 39 }, { 40, 40, 200 } }

test("settings: saved values over the defaults, wrong types ignored", function()
  local s = dialog.settings({ mode = "snap", maxColors = "lots", threshold = 0.05 })
  eq({ s.mode, s.maxColors, s.threshold, s.target }, { "snap", 32, 0.05, "sprite" })
  eq(dialog.settings(nil).output, "suffix")
end)

test("options: reduce validates the color count, snap reads hex colors", function()
  local s = dialog.settings({ maxColors = 12.0 })
  eq(dialog.options(s).maxColors, 12)
  eq(dialog.options(dialog.settings({ noCap = true })).maxColors, nil)
  fails(function() dialog.options(dialog.settings({ maxColors = 2.5 })) end, "whole number")
  local snap = dialog.options(dialog.settings({ mode = "snap", source = "hex", hexColors = "#000 #fff", match = "lightness" }))
  eq({ snap.palette, snap.snapMode }, { { 0x000000, 0xffffff }, "lightness" })
  fails(function() dialog.options(dialog.settings({ mode = "snap", source = "file" })) end, "Choose a palette file")
end)

test("options: the active sprite's palette, without transparent entries", function()
  local s = sprite(NOISY)
  local pal = Palette(3)
  pal:setColor(0, Color { r = 0, g = 0, b = 0, a = 0 })
  pal:setColor(1, Color { r = 8, g = 24, b = 32, a = 255 })
  pal:setColor(2, Color { r = 224, g = 248, b = 208, a = 255 })
  s:setPalette(pal)
  app.sprite = s
  eq(dialog.options(dialog.settings({ mode = "snap", source = "sprite" })).palette, { 0x081820, 0xe0f8d0 })
end)

test("apply to the active sprite: one undo step, a summary", function()
  local s = sprite(NOISY)
  app.sprite = s
  local settings = dialog.settings({ target = "sprite" })
  local summary = dialog.applyToSprites(settings, dialog.options(settings))
  eq(summary, "3 colors → 2 colors, 1 cel changed")
  app.undo()
  eq({ s.cels[1].image.bytes:byte(9, 11) }, { 202, 41, 39 }, "undone")
end)

test("apply to the selected cel only", function()
  local s = sprite(NOISY)
  s:newFrame()
  local second = s:newCel(s.layers[1], 2, s.cels[1].image:clone(), Point(0, 0))
  app.sprite = s
  app.cel = s.cels[1]
  local settings = dialog.settings({ target = "cels" })
  dialog.applyToSprites(settings, dialog.options(settings))
  eq({ s.cels[1].image.bytes:byte(9, 11) }, { 200, 40, 40 }, "selected cel")
  eq({ second.image.bytes:byte(9, 11) }, { 202, 41, 39 }, "other frame")
end)

test("apply to every open sprite", function()
  local a, b = sprite(NOISY), sprite(NOISY)
  app.sprite = a
  local settings = dialog.settings({ target = "open" })
  local summary = dialog.applyToSprites(settings, dialog.options(settings))
  assert(summary:find(("%d of %d sprites"):format(#app.sprites, #app.sprites), 1, true), summary)
  eq({ a.cels[1].image.bytes:byte(9, 11) }, { 200, 40, 40 }, "a")
  eq({ b.cels[1].image.bytes:byte(9, 11) }, { 200, 40, 40 }, "b")
  eq(app.sprite, a, "active sprite kept")
end)

test("folder files: from any image of the folder", function()
  local dir = fs.joinPath(t.tmp, "folder")
  fs.makeDirectory(dir)
  for _, name in ipairs({ "x.png", "y.png" }) do
    local s = sprite(NOISY)
    s:saveCopyAs(fs.joinPath(dir, name))
    s:close()
  end
  local list = dialog.folderFiles(dialog.settings({ target = "folder", folderFile = fs.joinPath(dir, "y.png") }))
  eq(#list, 2)
  fails(function() dialog.folderFiles(dialog.settings({ target = "folder" })) end, "Choose an image in the folder")
end)
