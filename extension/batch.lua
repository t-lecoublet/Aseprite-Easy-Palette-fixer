-- Recolors image files on disk: opens each one as a sprite, recolors every
-- cel, saves a copy and closes it.

local use = ...
local recolor = use("recolor")
local files = use("files")

local fs = app.fs

local M = {}

-- Lossy formats would bring stray colors back: their results are saved as PNG.
local TO_PNG = { jpg = true, jpeg = true, webp = true }

M.OUTPUT_FOLDER = "snapped"
M.OUTPUT_SUFFIX = "_snapped"

-- output: "suffix" (name_snapped.ext beside it), "folder" (snapped/name.ext)
-- or "replace" (overwrites; JPEG and WebP still become PNG beside them).
function M.outputPath(path, output)
  local dir, title, ext = fs.filePath(path), fs.fileTitle(path), fs.fileExtension(path)
  if TO_PNG[ext:lower()] then
    ext = "png"
  end
  if output == "folder" then
    return fs.joinPath(fs.joinPath(dir, M.OUTPUT_FOLDER), title .. "." .. ext)
  elseif output == "replace" then
    return fs.joinPath(dir, title .. "." .. ext)
  end
  return fs.joinPath(dir, title .. M.OUTPUT_SUFFIX .. "." .. ext)
end

-- Image files of a folder (and its subfolders when recursive), sorted, without
-- the outputs of a previous run.
function M.listImages(dir, recursive, output)
  local files = {}
  local function walk(folder)
    local names = fs.listFiles(folder)
    table.sort(names, function(a, b)
      return a:lower() < b:lower()
    end)
    for _, name in ipairs(names) do
      local path = fs.joinPath(folder, name)
      if fs.isDirectory(path) then
        if recursive and not (output == "folder" and name == M.OUTPUT_FOLDER) then
          walk(path)
        end
      elseif recolor.IMAGE_EXTENSIONS[fs.fileExtension(name):lower()] then
        local previous = output == "suffix" and fs.fileTitle(name):sub(-#M.OUTPUT_SUFFIX) == M.OUTPUT_SUFFIX
        if not previous then
          files[#files + 1] = path
        end
      end
    end
  end
  walk(dir)
  return files
end

-- Opens, recolors and saves one file. Returns the stats of recolor.processSprite
-- plus the output path.
function M.processFile(path, opts)
  local sprite = files.openSprite(path)
  local ok, result = pcall(function()
    local stats = recolor.processSprite(sprite, sprite.cels, opts)
    local out = M.outputPath(path, opts.output)
    if opts.output == "folder" then
      fs.makeDirectory(fs.filePath(out))
    end
    files.saveCopy(sprite, out)
    stats.output = out
    return stats
  end)
  sprite:close()
  if not ok then
    error(result, 0)
  end
  return result
end

return M
