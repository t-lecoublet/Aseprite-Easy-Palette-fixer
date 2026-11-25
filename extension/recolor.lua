-- Applies the Palette Snapper port to Aseprite sprites, in three steps:
--   collect: count the colors of some cels (or images), changing nothing;
--   mapping: compute old color -> new color with snapper/colors;
--   write:   recolor the cels (or, for the preview, a copy of an image).
--
-- Pixels are read and written through Image.bytes, with string.gmatch and
-- string.gsub doing the per-pixel loops in C: much faster than getPixel.

local use = ...
local oklab = use("snapper/oklab")
local colors = use("snapper/colors")
local palette = use("snapper/palette")
local files = use("files")

local key = oklab.key
local channels = oklab.channels

local M = {}

M.IMAGE_EXTENSIONS = {
  png = true, gif = true, jpg = true, jpeg = true, webp = true,
  bmp = true, tga = true, aseprite = true, ase = true,
}

-- Counts each distinct 4-byte RGBA pixel, keeping first-seen order.
local function countQuads(bytes, quads, order)
  for quad in bytes:gmatch("....") do
    local n = quads[quad]
    if n then
      quads[quad] = n + 1
    else
      quads[quad] = 1
      order[#order + 1] = quad
    end
  end
end

-- Color counts ({ key, count } in first-seen order) from RGBA quads.
local function colorsFromQuads(quads, order, minAlpha)
  local list, index = {}, {}
  for _, quad in ipairs(order) do
    local r, g, b, a = quad:byte(1, 4)
    if a >= minAlpha then
      local k = key(r, g, b)
      local at = index[k]
      if at then
        list[at].count = list[at].count + quads[quad]
      else
        list[#list + 1] = { key = k, count = quads[quad] }
        index[k] = #list
      end
    end
  end
  return list
end

-- Grayscale (value, alpha) pixels as RGBA.
local function grayToRgba(bytes)
  return (bytes:gsub("(.)(.)", "%1%1%1%2"))
end

-- An image's pixels as RGBA bytes, whatever its color mode. `pal` resolves
-- indexed pixels; out-of-range indices and `transparent` become transparent.
local function rgbaBytes(image, pal, transparent)
  if image.colorMode == ColorMode.RGB then
    return image.bytes
  elseif image.colorMode == ColorMode.GRAY then
    return grayToRgba(image.bytes)
  end
  local quadOf = {}
  for index = 0, 255 do
    local quad = "\0\0\0\0"
    if index < #pal and index ~= transparent then
      local c = pal:getColor(index)
      quad = string.char(c.red, c.green, c.blue, c.alpha)
    end
    quadOf[string.char(index)] = quad
  end
  return (image.bytes:gsub(".", quadOf))
end

local function distinctTargets(mapping)
  local seen, n = {}, 0
  for _, target in pairs(mapping) do
    if not seen[target] then
      seen[target] = true
      n = n + 1
    end
  end
  return n
end

-- Cels that can be recolored: skips tilemaps, reference and locked layers, and
-- linked cels already listed (they share one image).
function M.editableCels(cels)
  local result, seen, skipped = {}, {}, 0
  for _, cel in ipairs(cels) do
    local layer = cel.layer
    if layer.isTilemap or layer.isReference or not layer.isEditable then
      skipped = skipped + 1
    else
      local id = cel.image.id
      if not seen[id] then
        seen[id] = true
        result[#result + 1] = cel
      end
    end
  end
  return result, skipped
end

-- Colors of RGBA byte strings (alpha >= 1).
local function rgbState(byteStrings)
  local quads, order = {}, {}
  for _, bytes in ipairs(byteStrings) do
    countQuads(bytes, quads, order)
  end
  return { kind = "rgb", bytes = byteStrings, order = order, list = colorsFromQuads(quads, order, 1) }
end

-- Indexed: colors come from the palette. On a background layer the
-- transparent index is an ordinary opaque color.
local function indexedState(sprite, cels)
  if #sprite.palettes > 1 then
    error("Sprites with several palettes (one per frame) aren't supported yet.", 0)
  end
  local pal = sprite.palettes[1]
  local transparent = sprite.transparentColor
  local keyOf = { [false] = {}, [true] = {} }
  for index = 0, 255 do
    local k = false
    if index < #pal then
      local c = pal:getColor(index)
      if c.alpha > 0 then
        k = key(c.red, c.green, c.blue)
      end
    end
    keyOf[true][string.char(index)] = k
    keyOf[false][string.char(index)] = index ~= transparent and k
  end

  local list, at, bytes = {}, {}, {}
  for i, cel in ipairs(cels) do
    local lookup = keyOf[cel.layer.isBackground]
    bytes[i] = cel.image.bytes
    for ch in bytes[i]:gmatch(".") do
      local k = lookup[ch]
      if k then
        local pos = at[k]
        if pos then
          list[pos].count = list[pos].count + 1
        else
          list[#list + 1] = { key = k, count = 1 }
          at[k] = #list
        end
      end
    end
  end
  return { kind = "indexed", sprite = sprite, palette = pal, keyOf = keyOf, bytes = bytes, list = list }
end

-- Reads the colors of the editable cels among `cels`, changing nothing.
-- One state covers all of them: they get a single mapping.
function M.collect(sprite, cels)
  local editable, skipped = M.editableCels(cels)
  local state
  if sprite.colorMode == ColorMode.INDEXED then
    state = indexedState(sprite, editable)
  else
    local byteStrings = {}
    for i, cel in ipairs(editable) do
      byteStrings[i] = rgbaBytes(cel.image)
    end
    state = rgbState(byteStrings)
    state.gray = sprite.colorMode == ColorMode.GRAY
  end
  state.cels, state.skipped = editable, skipped
  return state
end

-- Colors of a single image (a file's first frame, for the folder preview).
function M.collectImage(image, pal)
  return rgbState({ rgbaBytes(image, pal) })
end

-- opts: { mode = "reduce", maxColors = n|nil, threshold = t }
--    or { mode = "snap", palette = { keys }, snapMode = "nearest"|"lightness" }
function M.mapping(state, opts)
  if opts.mode == "reduce" then
    return colors.reduce(state.list, opts.maxColors, opts.threshold)
  end
  return colors.snap(state.list, opts.palette, opts.snapMode)
end

-- The new colors, darkest first.
function M.targets(mapping)
  local seen, keys = {}, {}
  for _, target in pairs(mapping) do
    if not seen[target] then
      seen[target] = true
      keys[#keys + 1] = target
    end
  end
  local lightness = {}
  for _, k in ipairs(keys) do
    lightness[k] = oklab.toOklab(k)
  end
  table.sort(keys, function(a, b)
    if lightness[a] ~= lightness[b] then
      return lightness[a] < lightness[b]
    end
    return a < b
  end)
  return keys
end

-- RGBA quad -> recolored quad, for the quads that change.
local function quadReplacements(order, mapping)
  local replace = {}
  for _, quad in ipairs(order) do
    local r, g, b, a = quad:byte(1, 4)
    if a > 0 then
      local from = key(r, g, b)
      local to = mapping[from]
      if to and to ~= from then
        local tr, tg, tb = channels(to)
        replace[quad] = string.char(tr, tg, tb, a)
      end
    end
  end
  return replace
end

local function replaceCelImage(cel, bytes)
  local image = cel.image:clone()
  image.bytes = bytes
  cel.image = image
end

-- Writes the mapping into the cels of the state. Returns how many changed.
function M.write(state, mapping)
  if state.gray then
    error("Convert Grayscale sprites to RGB before changing them.", 0)
  end
  local changed = 0
  if state.kind == "rgb" then
    local replace = quadReplacements(state.order, mapping)
    if next(replace) then
      for i, cel in ipairs(state.cels) do
        local recolored = state.bytes[i]:gsub("....", replace)
        if recolored ~= state.bytes[i] then
          replaceCelImage(cel, recolored)
          changed = changed + 1
        end
      end
    end
    return changed
  end

  -- Indexed: remap each pixel to the index of its new color, added to the
  -- palette when it isn't there yet.
  local pal, transparent = state.palette, state.sprite.transparentColor
  local indexOf = {}
  for i = #pal - 1, 0, -1 do
    local c = pal:getColor(i)
    if i ~= transparent and c.alpha > 0 then
      indexOf[key(c.red, c.green, c.blue)] = i
    end
  end
  local function indexFor(k)
    local i = indexOf[k]
    if not i then
      if #pal >= 256 then
        error("The sprite's palette is full (256 colors): the new colors can't be added.", 0)
      end
      i = #pal
      pal:resize(i + 1)
      local r, g, b = channels(k)
      pal:setColor(i, Color { r = r, g = g, b = b, a = 255 })
      indexOf[k] = i
    end
    return i
  end

  for i, cel in ipairs(state.cels) do
    local lookup = state.keyOf[cel.layer.isBackground]
    local replace = {}
    for index = 0, 255 do
      local ch = string.char(index)
      local from = lookup[ch]
      local to = from and mapping[from]
      if to and to ~= from then
        replace[ch] = string.char(indexFor(to))
      end
    end
    if next(replace) then
      local recolored = state.bytes[i]:gsub(".", replace)
      if recolored ~= state.bytes[i] then
        replaceCelImage(cel, recolored)
        changed = changed + 1
      end
    end
  end
  return changed
end

-- Recolors the given cels of one sprite together (one mapping for all of them).
-- Grayscale sprites are converted to RGB first, since the result can have color.
-- Returns { before, after, cels, changed, skipped, converted }.
function M.processSprite(sprite, cels, opts)
  local converted = false
  if sprite.colorMode == ColorMode.GRAY then
    app.sprite = sprite
    app.command.ChangePixelFormat { format = "rgb" }
    converted = true
  end
  local state = M.collect(sprite, cels)
  local mapping = M.mapping(state, opts)
  local changed = M.write(state, mapping)
  return {
    before = #state.list,
    after = distinctTargets(mapping),
    cels = #state.cels,
    changed = changed,
    skipped = state.skipped,
    converted = converted,
  }
end

-- A frame of a sprite, flattened into an RGB image (for the preview).
function M.renderFrame(sprite, frame)
  local image = Image(sprite.width, sprite.height, ColorMode.RGB)
  image:drawSprite(sprite, frame)
  return image
end

-- A cel's own image as RGB (for the preview of selected cels).
function M.celImage(cel)
  local sprite, image = cel.sprite, cel.image
  local transparent = nil
  if sprite.colorMode == ColorMode.INDEXED and not cel.layer.isBackground then
    transparent = sprite.transparentColor
  end
  local rgb = Image(image.width, image.height, ColorMode.RGB)
  rgb.bytes = rgbaBytes(image, sprite.palettes[1], transparent)
  return rgb
end

-- A recolored copy of an RGB image (for the preview). Colors the mapping
-- doesn't know (blends of overlapping layers) stay as they are.
function M.recolorImage(image, mapping)
  local bytes = image.bytes
  local quads, order = {}, {}
  countQuads(bytes, quads, order)
  local result = image:clone()
  result.bytes = bytes:gsub("....", quadReplacements(order, mapping))
  return result
end

-- A file's first frame as an RGB image (for the folder preview).
function M.loadRgbImage(path)
  local image = files.loadImage(path)
  if image.colorMode == ColorMode.RGB then
    return image
  end
  local pal = image.colorMode == ColorMode.INDEXED and files.loadPalette(path)
  local rgb = Image(image.width, image.height, ColorMode.RGB)
  rgb.bytes = rgbaBytes(image, pal)
  return rgb
end

-- Keys of a palette's colors, in order, without fully transparent entries.
function M.paletteKeys(pal)
  local keys = {}
  for i = 0, #pal - 1 do
    local c = pal:getColor(i)
    if c.alpha > 0 then
      keys[#keys + 1] = key(c.red, c.green, c.blue)
    end
  end
  return keys
end

-- The sprite's own palette (frame 1).
function M.spritePalette(sprite)
  return palette.unique(M.paletteKeys(sprite.palettes[1]))
end

-- A palette from a file: an image of swatches, a palette Aseprite reads
-- (.pal, .act, .col, .ase), or text (Lospec .hex, Paint.NET .txt, GIMP .gpl, JSON).
function M.paletteFromFile(path)
  local ext = app.fs.fileExtension(path):lower()
  if M.IMAGE_EXTENSIONS[ext] and ext ~= "aseprite" and ext ~= "ase" then
    local image = M.loadRgbImage(path)
    local quads, order = {}, {}
    countQuads(image.bytes, quads, order)
    return palette.fromImageColors(colorsFromQuads(quads, order, 128))
  end
  if ext == "pal" or ext == "act" or ext == "col" or ext == "aseprite" or ext == "ase" then
    return palette.unique(M.paletteKeys(files.loadPalette(path)))
  end
  return palette.parse(files.readText(path))
end

return M
