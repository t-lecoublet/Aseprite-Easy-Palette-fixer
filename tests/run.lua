-- Runs the tests inside Aseprite (its Lua and API), without the UI:
--   python3 tests/run.py
-- which calls: Aseprite -b --script-param root=<extension> --script-param tests=<tests> --script tests/run.lua

local root, testsDir = app.params.root, app.params.tests
local use = dofile(app.fs.joinPath(root, "loader.lua"))(root)

local count, failures = 0, 0
local function test(name, fn)
  count = count + 1
  local ok, err = xpcall(fn, debug and debug.traceback or tostring)
  if ok then
    print("ok    " .. name)
  else
    failures = failures + 1
    print("FAIL  " .. name .. "\n      " .. tostring(err):gsub("\n", "\n      "))
  end
end

local function show(value)
  if type(value) ~= "table" then
    return tostring(value)
  end
  local parts = {}
  for i, item in ipairs(value) do
    parts[i] = show(item)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if not same(a[i], b[i]) then
      return false
    end
  end
  return true
end

local function eq(actual, expected, what)
  if not same(actual, expected) then
    error((what or "value") .. ": expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end

local function fails(fn, fragment)
  local ok, err = pcall(fn)
  if ok then
    error("expected an error containing \"" .. fragment .. "\"", 2)
  end
  if not tostring(err):find(fragment, 1, true) then
    error("expected an error containing \"" .. fragment .. "\", got: " .. tostring(err), 2)
  end
end

local t = { use = use, test = test, eq = eq, fails = fails, show = show, tmp = app.params.tmp }
for _, file in ipairs({ "test_snapper.lua", "test_aseprite.lua", "test_dialog.lua", "test_preview.lua", "test_draw.lua" }) do
  assert(loadfile(app.fs.joinPath(testsDir, file)))(t)
end
print(("RESULT %d tests, %d failures"):format(count, failures))
