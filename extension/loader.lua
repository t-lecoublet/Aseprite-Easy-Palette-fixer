-- Loads the extension's modules from its folder. Each module receives `use` as
-- its first argument (...), so modules load each other without `require`,
-- whose package.path is shared with every other script and extension.
return function(root)
  local loaded = {}
  local function use(name)
    local module = loaded[name]
    if module == nil then
      local chunk = assert(loadfile(app.fs.joinPath(root, name .. ".lua")))
      module = chunk(use)
      loaded[name] = module
    end
    return module
  end
  return use
end
