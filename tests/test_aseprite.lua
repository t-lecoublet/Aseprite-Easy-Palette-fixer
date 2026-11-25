-- What the original doesn't have: color modes, layers, linked cels, undo, files.

local t = ...
local test, eq = t.test, t.eq
local recolor = t.use("recolor")
local batch = t.use("batch")
local fs = app.fs

local GAME_BOY = { 0x081820, 0x346856, 0x88c070, 0xe0f8d0 }
local REDUCE = { mode = "reduce", maxColors = 32, threshold = 0.03 }

local function rgbaBytes(sprite, cel)
  return { (cel or sprite.cels[1]).image.bytes:byte(1, -1) }
end

local function rgbSprite(pixels)
  local sprite = Sprite(#pixels, 1, ColorMode.RGB)
  local image = Image(#pixels, 1, ColorMode.RGB)
  for x, p in ipairs(pixels) do
    image:drawPixel(x - 1, 0, app.pixelColor.rgba(p[1], p[2], p[3], p[4] or 255))
  end
  sprite:newCel(sprite.layers[1], 1, image, Point(0, 0))
  return sprite
end

local NOISY = { { 200, 40, 40 }, { 200, 40, 40 }, { 202, 41, 39 }, { 40, 40, 200 } }

test("indexed: noise is remapped to the index of the color it merges into", function()
  local sprite = Sprite(4, 1, ColorMode.INDEXED)
  local pal = Palette(5)
  pal:setColor(0, Color { r = 0, g = 0, b = 0, a = 0 })
  for i, p in ipairs(NOISY) do
    pal:setColor(i, Color { r = p[1], g = p[2], b = p[3], a = 255 })
  end
  sprite:setPalette(pal)
  local image = Image(4, 1, ColorMode.INDEXED)
  for x = 0, 3 do
    image:drawPixel(x, 0, x + 1)
  end
  sprite:newCel(sprite.layers[1], 1, image, Point(0, 0))
  local stats = recolor.processSprite(sprite, sprite.cels, REDUCE)
  eq(rgbaBytes(sprite), { 1, 2, 1, 4 }, "indices")
  eq(#sprite.palettes[1], 5, "palette size")
  -- Indices 1 and 2 hold the same color: 3 distinct colors.
  eq({ stats.before, stats.after }, { 3, 2 }, "colors before/after")
end)

test("indexed: snapping to another palette adds its colors to the sprite palette", function()
  local sprite = Sprite(2, 1, ColorMode.INDEXED)
  local pal = Palette(3)
  pal:setColor(0, Color { r = 0, g = 0, b = 0, a = 0 })
  pal:setColor(1, Color { r = 10, g = 20, b = 30, a = 255 })
  pal:setColor(2, Color { r = 230, g = 240, b = 200, a = 255 })
  sprite:setPalette(pal)
  local image = Image(2, 1, ColorMode.INDEXED)
  image:drawPixel(0, 0, 1)
  image:drawPixel(1, 0, 2)
  sprite:newCel(sprite.layers[1], 1, image, Point(0, 0))
  recolor.processSprite(sprite, sprite.cels, { mode = "snap", palette = GAME_BOY, snapMode = "nearest" })
  local result = sprite.palettes[1]
  local colors = {}
  for _, index in ipairs(rgbaBytes(sprite)) do
    local c = result:getColor(index)
    colors[#colors + 1] = (c.red << 16) | (c.green << 8) | c.blue
  end
  eq(colors, { 0x081820, 0xe0f8d0 })
end)

test("grayscale sprites are converted to RGB first", function()
  local sprite = Sprite(2, 1, ColorMode.GRAY)
  local image = Image(2, 1, ColorMode.GRAY)
  image:drawPixel(0, 0, app.pixelColor.graya(20, 255))
  image:drawPixel(1, 0, app.pixelColor.graya(230, 255))
  sprite:newCel(sprite.layers[1], 1, image, Point(0, 0))
  local stats = recolor.processSprite(sprite, sprite.cels, { mode = "snap", palette = GAME_BOY, snapMode = "nearest" })
  eq(stats.converted, true, "converted")
  eq(sprite.colorMode, ColorMode.RGB, "color mode")
  eq(rgbaBytes(sprite), { 8, 24, 32, 255, 224, 248, 208, 255 })
end)

test("all cels share one mapping; linked cels are recolored once, both frames change", function()
  local sprite = rgbSprite(NOISY)
  sprite.layers[1].isContinuous = true -- new frames get linked cels
  sprite:newFrame()
  local linked = sprite.cels[2]
  eq(linked.image.id, sprite.cels[1].image.id, "frames share one image")
  local stats = recolor.processSprite(sprite, sprite.cels, REDUCE)
  eq(stats.cels, 1, "cels recolored")
  eq(rgbaBytes(sprite, sprite.cels[2]), rgbaBytes(sprite, sprite.cels[1]), "both frames")
  eq({ table.unpack(rgbaBytes(sprite), 9, 12) }, { 200, 40, 40, 255 })
end)

test("locked layers are left alone", function()
  local sprite = rgbSprite(NOISY)
  sprite.layers[1].isEditable = false
  local before = rgbaBytes(sprite)
  local stats = recolor.processSprite(sprite, sprite.cels, REDUCE)
  eq(stats.skipped, 1, "skipped")
  eq(rgbaBytes(sprite), before)
end)

test("one undo step restores the sprite", function()
  local sprite = rgbSprite(NOISY)
  local before = rgbaBytes(sprite)
  app.activeSprite = sprite
  app.transaction("Easy Palette Fixer", function()
    recolor.processSprite(sprite, sprite.cels, REDUCE)
  end)
  local after = rgbaBytes(sprite)
  assert(after[9] == 200, "recolored")
  app.undo()
  eq(rgbaBytes(sprite), before, "after undo")
end)

test("batch: outputs beside the originals, in a subfolder, or over them; previous outputs are skipped", function()
  -- makeAllDirectories fails on \\wsl.localhost\ paths; makeDirectory works.
  local dir = fs.joinPath(t.tmp, "batch")
  fs.makeDirectory(dir)
  fs.makeDirectory(fs.joinPath(dir, "sub"))
  for _, name in ipairs({ "a.png", "b.jpg", "sub\\c.png", "a_snapped.png", "notes.txt" }) do
    local path = fs.joinPath(dir, name)
    if name:match("%.txt$") then
      local f = io.open(path, "w")
      f:write("x")
      f:close()
    else
      local sprite = rgbSprite(NOISY)
      sprite:saveCopyAs(path)
      sprite:close()
    end
  end
  local function names(list)
    local result = {}
    for i, path in ipairs(list) do
      result[i] = fs.fileName(path)
    end
    return result
  end
  eq(names(batch.listImages(dir, false, "suffix")), { "a.png", "b.jpg" }, "suffix, flat")
  eq(names(batch.listImages(dir, true, "suffix")), { "a.png", "b.jpg", "c.png" }, "suffix, recursive")
  eq(names(batch.listImages(dir, false, "folder")), { "a.png", "a_snapped.png", "b.jpg" }, "folder")

  local original = fs.joinPath(dir, "a.png")
  local stats = batch.processFile(original, { mode = "reduce", maxColors = 32, threshold = 0.03, output = "suffix" })
  eq(fs.fileName(stats.output), "a_snapped.png", "suffix output")
  eq(fs.fileName(batch.processFile(fs.joinPath(dir, "b.jpg"), { mode = "reduce", maxColors = 4, threshold = 0.03, output = "folder" }).output), "b.png", "jpeg to png in folder")
  assert(fs.isFile(fs.joinPath(fs.joinPath(dir, "snapped"), "b.png")), "snapped/b.png exists")

  local function firstPixels(path)
    local image = Image { fromFile = path }
    return { image.bytes:byte(1, 12) }
  end
  eq(firstPixels(original), { 200, 40, 40, 255, 200, 40, 40, 255, 202, 41, 39, 255 }, "original untouched")
  eq(firstPixels(stats.output), { 200, 40, 40, 255, 200, 40, 40, 255, 200, 40, 40, 255 }, "output recolored")
end)

test("batch: no sprite is left open", function()
  local open = #app.sprites
  local path = fs.joinPath(fs.joinPath(t.tmp, "batch"), "a.png")
  batch.processFile(path, { mode = "reduce", maxColors = 32, threshold = 0.03, output = "suffix" })
  eq(#app.sprites, open)
end)
