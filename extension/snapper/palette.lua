-- Made by Sprite Fusion: https://www.spritefusion.com
-- MIT License. Copyright (c) 2026 Hugo Duprez.
-- Keep this notice in copies and adaptations of this file.
--
-- Lua port of the palette readers in src/palette.rs from
-- spritefusion-palette-snapper, for Easy Palette Fixer.
-- Palettes are lists of color keys (0xRRGGBB).

local use = ...
local colors = use("snapper/colors")

local M = {}

M.MAX_COLORS = 256

-- "#abc", "aabbcc", "0xAABBCC", "FFaabbcc" (Paint.NET), "aabbccFF" -> key, or nil.
local function normalizeHex(token)
  local digits = token
  if digits:sub(1, 1) == "#" then
    digits = digits:sub(2)
  elseif digits:sub(1, 2) == "0x" or digits:sub(1, 2) == "0X" then
    digits = digits:sub(3)
  end
  if digits == "" or digits:find("[^%x]") then
    return nil
  end
  digits = digits:lower()
  if #digits == 3 then
    digits = digits:gsub(".", "%0%0")
  elseif #digits == 8 then
    if digits:sub(7, 8) == "ff" then
      digits = digits:sub(1, 6)
    elseif digits:sub(1, 2) == "ff" then
      digits = digits:sub(3)
    else
      return nil
    end
  end
  if #digits ~= 6 then
    return nil
  end
  return tonumber(digits, 16)
end

local function lines(text)
  local result = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    result[#result + 1] = line:gsub("\r$", "")
  end
  return result
end

-- Aseprite's json.decode returns userdata that indexes like a table.
local function isContainer(value)
  local kind = type(value)
  return kind == "table" or kind == "userdata"
end

-- A JSON array of hex colors, or an object with a "colors" (or "colours") array.
local function jsonColors(text)
  local first = text:match("^%s*(.)")
  if (first ~= "[" and first ~= "{") or not isContainer(json) then
    return nil
  end
  local ok, value = pcall(json.decode, text)
  if not ok or not isContainer(value) then
    return nil
  end
  local list = value
  if first == "{" then
    list = value.colors
    if not isContainer(list) then
      list = value.colours
    end
  end
  if not isContainer(list) then
    return nil
  end
  local entries = {}
  for i = 1, #list do
    if type(list[i]) ~= "string" then
      return nil
    end
    entries[i] = list[i]
  end
  return entries
end

-- A GIMP .gpl line: "R G B name".
local function gimpColor(line)
  local r, g, b, rest = line:match("^%s*(%d+)%s+(%d+)%s+(%d+)(.*)$")
  if not r or #r > 3 or #g > 3 or #b > 3 then
    return nil
  end
  if rest ~= "" and not rest:find("^%s") then
    return nil
  end
  local function channel(digits)
    return math.min(tonumber(digits), 255)
  end
  return (channel(r) << 16) | (channel(g) << 8) | channel(b)
end

-- Colors in order, repeats dropped. Fails when empty or over 256.
function M.unique(keys)
  local result, seen = {}, {}
  for _, key in ipairs(keys) do
    if not seen[key] then
      seen[key] = true
      result[#result + 1] = key
    end
  end
  if #result == 0 then
    error("The palette has no colors.", 0)
  end
  if #result > M.MAX_COLORS then
    error("A palette has at most " .. M.MAX_COLORS .. " colors; this one has " .. #result .. ".", 0)
  end
  return result
end

-- A palette from text:
--   hex colors separated by anything ("#081820, 346856 88C070"), short forms included;
--   Lospec .hex, Paint.NET .txt ("FFRRGGBB" lines, ";" comments), GIMP .gpl;
--   JSON: an array of hex colors, or an object with a "colors" array (Lospec .json).
function M.parse(text)
  local keys = {}
  local entries = jsonColors(text)
  if entries then
    for _, entry in ipairs(entries) do
      local key = normalizeHex(entry:match("^%s*(.-)%s*$"))
      if not key then
        error('"' .. entry .. '" is not a hex color.', 0)
      end
      keys[#keys + 1] = key
    end
  elseif text:match("^%s*(............)") and text:match("^%s*(............)"):lower() == "gimp palette" then
    for _, line in ipairs(lines(text)) do
      keys[#keys + 1] = gimpColor(line)
    end
  else
    local kept = {}
    for _, line in ipairs(lines(text)) do
      kept[#kept + 1] = line:gsub(";.*$", "")
    end
    for token in table.concat(kept, "\n"):gmatch("#?%w+") do
      local key = normalizeHex(token)
      if not key then
        error('"' .. token .. '" is not a hex color.', 0)
      end
      keys[#keys + 1] = key
    end
  end
  return M.unique(keys)
end

-- A palette from an image of its swatches (Lospec's PNGs, a screenshot), given
-- its colors counted on pixels with alpha >= 128, in reading order.
-- An image with more than 256 colors (a photo, a JPEG) has many near-identical
-- ones: those within 0.04 merge, and colors on under 0.1% of the pixels are dropped.
function M.fromImageColors(imageColors)
  if #imageColors == 0 then
    error("The image has no opaque pixels.", 0)
  end
  if #imageColors <= M.MAX_COLORS then
    local keys = {}
    for i, color in ipairs(imageColors) do
      keys[i] = color.key
    end
    return keys
  end
  local replacement = colors.merge(imageColors, 0.04, nil)
  local total, counts = 0, {}
  for _, color in ipairs(imageColors) do
    total = total + color.count
    local into = replacement[color.key]
    counts[into] = (counts[into] or 0) + color.count
  end
  local kept = {}
  for _, color in ipairs(imageColors) do
    if (counts[color.key] or 0) >= total * 0.001 then
      kept[#kept + 1] = color.key
    end
  end
  if #kept == 0 or #kept > M.MAX_COLORS then
    error("The image has " .. #kept .. " distinct colors; a palette has 1 to " .. M.MAX_COLORS .. ".", 0)
  end
  return kept
end

return M
