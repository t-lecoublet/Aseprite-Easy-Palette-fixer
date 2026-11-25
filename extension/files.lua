-- Every file read and write of the extension goes through this module.
-- Aseprite asks the user for file access once per Lua file that touches the
-- disk, so keeping them here means a single permission prompt.

local M = {}

-- Formats with a single frame: opened with oneFrame so Aseprite never asks
-- whether numbered files (walk01.png, walk02.png...) are an animation.
local SINGLE_FRAME = { png = true, jpg = true, jpeg = true, bmp = true, tga = true }

function M.openSprite(path)
  local ext = app.fs.fileExtension(path):lower()
  local sprite = Sprite { fromFile = path, oneFrame = SINGLE_FRAME[ext] or nil }
  if not sprite then
    error("Can't open " .. path, 0)
  end
  return sprite
end

function M.saveCopy(sprite, path)
  sprite:saveCopyAs(path)
end

-- The first frame, flattened.
function M.loadImage(path)
  local image = Image { fromFile = path }
  if not image then
    error("Can't open the image " .. path, 0)
  end
  return image
end

function M.loadPalette(path)
  local pal = Palette { fromFile = path }
  if not pal then
    error("Can't read the palette " .. path, 0)
  end
  return pal
end

function M.readText(path)
  local file, err = io.open(path, "rb")
  if not file then
    error("Can't read " .. path .. ": " .. tostring(err), 0)
  end
  local text = file:read("a")
  file:close()
  return text
end

return M
