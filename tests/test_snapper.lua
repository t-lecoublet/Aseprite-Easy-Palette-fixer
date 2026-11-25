-- The original's tests (tests/colors.rs in spritefusion-palette-snapper), run
-- on Aseprite sprites through recolor.processSprite.

local t = ...
local test, eq, fails = t.test, t.eq, t.fails
local palette = t.use("snapper/palette")
local recolor = t.use("recolor")

local GAME_BOY = { 0x081820, 0x346856, 0x88c070, 0xe0f8d0 }

-- A one-row RGB sprite from { r, g, b, a } pixels.
local function row(pixels)
  local sprite = Sprite(#pixels, 1, ColorMode.RGB)
  local image = Image(#pixels, 1, ColorMode.RGB)
  for x, p in ipairs(pixels) do
    image:drawPixel(x - 1, 0, app.pixelColor.rgba(p[1], p[2], p[3], p[4]))
  end
  sprite:newCel(sprite.layers[1], 1, image, Point(0, 0))
  return sprite
end

local function raw(sprite)
  return { sprite.cels[1].image.bytes:byte(1, -1) }
end

local function colorsOf(sprite)
  local set, n = {}, 0
  for quad in sprite.cels[1].image.bytes:gmatch("....") do
    local r, g, b, a = quad:byte(1, 4)
    if a > 0 then
      local key = (r << 16) | (g << 8) | b
      if not set[key] then
        set[key] = true
        n = n + 1
      end
    end
  end
  return set, n
end

local function reduce(sprite, maxColors, threshold)
  recolor.processSprite(sprite, sprite.cels, { mode = "reduce", maxColors = maxColors, threshold = threshold })
  return sprite
end

local function snap(sprite, pal, mode)
  recolor.processSprite(sprite, sprite.cels, { mode = "snap", palette = pal, snapMode = mode })
  return sprite
end

local function ramp()
  local pixels = {}
  for i = 0, 59 do
    pixels[#pixels + 1] = { (i * 4) % 256, (255 - i * 4) % 256, (i * 37) % 256, 255 }
  end
  return row(pixels)
end

test("hex colors in any separator, short and long forms, repeats dropped", function()
  eq(palette.parse("#081820, 346856\n88C070 #abc #081820"), { 0x081820, 0x346856, 0x88c070, 0xaabbcc })
  eq(palette.parse("e0f8d0\n#000\n0x346856"), { 0xe0f8d0, 0x000000, 0x346856 })
end)

test("Lospec .hex, Paint.NET .txt, GIMP .gpl, JSON", function()
  eq(palette.parse("081820\n346856\n88c070\ne0f8d0\n"), GAME_BOY)
  local two = { 0x081820, 0x346856 }
  eq(palette.parse(";paint.net Palette File\n;Colors: 2\nFF081820\nFF346856\n"), two)
  eq(palette.parse("GIMP Palette\nName: gb\nColumns: 4\n#\n  8  24  32\tdarkest\n 52 104  86\n"), two)
  eq(palette.parse('{"name": "Decaf Bad Face", "author": "", "colors": ["081820", "346856"]}'), two)
  eq(palette.parse('["#081820", "#346856"]'), two)
end)

test("rejects what isn't a color, empty palettes and more than 256 colors", function()
  fails(function() palette.parse("#12345") end, "is not a hex color")
  fails(function() palette.parse("#081820 green") end, '"green" is not a hex color')
  fails(function() palette.parse("") end, "has no colors")
  local many = {}
  for i = 0, 256 do
    many[#many + 1] = ("#%06x"):format(i)
  end
  fails(function() palette.parse(table.concat(many, "\n")) end, "at most 256")
end)

test("noise merges into the most frequent color, never into an average", function()
  local noisy = reduce(row({
    { 200, 40, 40, 255 }, { 200, 40, 40, 255 }, { 202, 41, 39, 255 }, { 40, 40, 200, 255 }, { 40, 200, 40, 255 },
  }), 32, 0.03)
  eq({ table.unpack(raw(noisy), 9, 12) }, { 200, 40, 40, 255 }, "pixel 2")
  eq(select(2, colorsOf(noisy)), 3, "colors")
end)

test("at most 32 colors by default, any number with maxColors, no cap with nil", function()
  eq(select(2, colorsOf(reduce(ramp(), 32, 0.03))), 32)
  eq(select(2, colorsOf(reduce(ramp(), 8, 0.03))), 8)
  eq(select(2, colorsOf(reduce(ramp(), nil, 0.0))), 60)
  assert(select(2, colorsOf(reduce(ramp(), nil, 0.03))) > 32)
  local all = colorsOf(ramp())
  for key in pairs(colorsOf(reduce(ramp(), 8, 0.03))) do
    assert(all[key], "a reduced color that wasn't drawn")
  end
end)

test("threshold sets how close colors must be to merge", function()
  local function greys()
    return row({ { 100, 100, 100, 255 }, { 100, 100, 100, 255 }, { 104, 104, 104, 255 } })
  end
  eq(select(2, colorsOf(reduce(greys(), 32, 0.03))), 1)
  eq(select(2, colorsOf(reduce(greys(), 32, 0.0))), 2)
end)

test("transparent pixels and alpha stay as they are", function()
  local image = reduce(row({ { 200, 40, 40, 255 }, { 202, 41, 39, 128 }, { 9, 9, 9, 0 } }), 32, 0.03)
  eq(raw(image), { 200, 40, 40, 255, 200, 40, 40, 128, 9, 9, 9, 0 })
end)

test("rejects bad options", function()
  fails(function() reduce(ramp(), 0, 0.03) end, "Max colors")
  fails(function() reduce(ramp(), 8, -1.0) end, "Threshold")
  fails(function() reduce(ramp(), 8, 0 / 0) end, "Threshold")
end)

test("nearest: every opaque pixel becomes its nearest palette color; alpha and transparent pixels stay", function()
  local snapped = snap(row({ { 10, 20, 30, 255 }, { 140, 190, 110, 200 }, { 255, 0, 0, 0 } }), GAME_BOY, "nearest")
  eq(raw(snapped), { 8, 24, 32, 255, 136, 192, 112, 200, 255, 0, 0, 0 })
end)

test("a patch drawn in one color stays one color, even halfway between two palette colors", function()
  local patch = row({
    { 96, 96, 96, 255 }, { 102, 102, 102, 255 }, { 96, 96, 96, 255 }, { 102, 102, 102, 255 }, { 96, 96, 96, 255 },
  })
  eq(select(2, colorsOf(snap(patch, { 0x000000, 0xffffff }, "nearest"))), 1)
end)

test("lightness keeps a sprite's light and dark steps on another palette", function()
  local function red()
    return row({ { 150, 20, 20, 255 }, { 180, 30, 30, 255 }, { 210, 50, 50, 255 }, { 235, 75, 75, 255 } })
  end
  local steps = {}
  for quad in snap(red(), GAME_BOY, "lightness").cels[1].image.bytes:gmatch("....") do
    local r, g, b = quad:byte(1, 3)
    steps[#steps + 1] = (r << 16) | (g << 8) | b
  end
  eq(steps, GAME_BOY)
  assert(select(2, colorsOf(snap(red(), GAME_BOY, "nearest"))) < 4)
end)

test("a palette file's text gives the same result, empty palettes are rejected", function()
  eq(raw(snap(ramp(), palette.parse("081820\n346856\n88c070\ne0f8d0\n"), "nearest")), raw(snap(ramp(), GAME_BOY, "nearest")))
  fails(function() snap(ramp(), {}, "nearest") end, "has no colors")
end)

test("an image with no opaque pixels comes back as it was", function()
  eq(raw(snap(row({ { 1, 2, 3, 0 } }), GAME_BOY, "lightness")), { 1, 2, 3, 0 })
end)

test("a palette from an image of swatches, in reading order", function()
  local image = Image(4, 2, ColorMode.RGB)
  local px = {
    { 8, 24, 32, 255 }, { 52, 104, 86, 255 }, { 136, 192, 112, 255 }, { 224, 248, 208, 255 },
    { 8, 24, 32, 255 }, { 52, 104, 86, 255 }, { 0, 0, 0, 0 }, { 0, 0, 0, 0 },
  }
  for i, p in ipairs(px) do
    image:drawPixel((i - 1) % 4, (i - 1) // 4, app.pixelColor.rgba(p[1], p[2], p[3], p[4]))
  end
  local path = app.fs.joinPath(t.tmp, "swatches.png")
  image:saveAs(path)
  eq(recolor.paletteFromFile(path), GAME_BOY)
end)
