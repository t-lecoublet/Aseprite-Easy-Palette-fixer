-- Aseprite's palette presets, found the way Aseprite fills its Presets tab:
-- palettes contributed by extensions (built in, then installed), then the
-- files of the data/palettes and user palettes folders, by file title.

local use = ...
local files = use("files")
local recolor = use("recolor")

local fs = app.fs

local M = {}

local function extensionPalettes(dir, found)
  if not fs.isDirectory(dir) then
    return
  end
  for _, name in ipairs(fs.listFiles(dir)) do
    local folder = fs.joinPath(dir, name)
    local manifest = fs.joinPath(folder, "package.json")
    if fs.isFile(manifest) then
      pcall(function()
        local list = json.decode(files.readText(manifest)).contributes.palettes
        for i = 1, #list do
          local entry = list[i]
          if type(entry.id) == "string" and type(entry.path) == "string" then
            found[entry.id] = fs.joinPath(folder, (entry.path:gsub("^%./", "")))
          end
        end
      end)
    end
  end
end

local function folderPalettes(dir, found)
  if not fs.isDirectory(dir) then
    return
  end
  for _, name in ipairs(fs.listFiles(dir)) do
    local path = fs.joinPath(dir, name)
    -- Aseprite skips the default palette too.
    if fs.isFile(path) and name ~= "default.ase" and name ~= "default.gpl" then
      found[fs.fileTitle(name)] = path
    end
  end
end

-- { { id, path } } sorted by name, like the Presets tab.
function M.find()
  local found = {}
  local data = fs.joinPath(fs.filePath(fs.appPath), "data")
  extensionPalettes(fs.joinPath(data, "extensions"), found)
  extensionPalettes(fs.joinPath(fs.userConfigPath, "extensions"), found)
  folderPalettes(fs.joinPath(data, "palettes"), found)
  folderPalettes(fs.joinPath(fs.userConfigPath, "palettes"), found)
  local list = {}
  for id, path in pairs(found) do
    list[#list + 1] = { id = id, path = path }
  end
  table.sort(list, function(a, b)
    local x, y = a.id:lower(), b.id:lower()
    if x ~= y then
      return x < y
    end
    return a.id < b.id
  end)
  return list
end

-- A preset's colors (keys), or nil when its file can't be read. Cached.
local cache = {}
function M.colors(path)
  if cache[path] == nil then
    local ok, keys = pcall(function()
      return recolor.paletteKeys(files.loadPalette(path))
    end)
    cache[path] = ok and keys or false
  end
  return cache[path] or nil
end

return M
