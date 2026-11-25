-- Run by tests/parity.py: recolors each case's input with the port and
-- compares it with the Rust CLI's output, pixel for pixel.

local root = app.params.root
local use = dofile(app.fs.joinPath(root, "loader.lua"))(root)
local recolor = use("recolor")
local palette = use("snapper/palette")

-- The first frame as RGBA bytes on the full canvas.
local function render(sprite)
  if sprite.colorMode ~= ColorMode.RGB then
    app.activeSprite = sprite
    app.command.ChangePixelFormat { format = "rgb" }
  end
  local image = Image(sprite.width, sprite.height, ColorMode.RGB)
  image:drawSprite(sprite, 1)
  return image.bytes, sprite.width
end

local file = assert(io.open(app.params.cases, "rb"))
local cases = json.decode(file:read("a"))
file:close()

local different = 0
for i = 1, #cases do
  local case = cases[i]
  local ok, err = pcall(function()
    local o = case.opts
    local opts = {
      mode = o.mode,
      maxColors = o.maxColors and math.tointeger(o.maxColors) or nil,
      threshold = o.threshold or 0.03,
      palette = o.palette and palette.parse(o.palette),
      snapMode = o.snapMode or "nearest",
    }
    -- "maxColors": null in the JSON means no cap; absent means the default.
    local hasKey = false
    for k in pairs(o) do
      if k == "maxColors" then
        hasKey = true
      end
    end
    if o.mode == "reduce" and not hasKey then
      opts.maxColors = 32
    end

    local sprite = Sprite { fromFile = case.input, oneFrame = true }
    local started = os.clock()
    local stats = recolor.processSprite(sprite, sprite.cels, opts)
    local elapsed = os.clock() - started
    local mine, width = render(sprite)
    sprite:close()

    local rust = Sprite { fromFile = case.rust, oneFrame = true }
    local theirs = render(rust)
    rust:close()

    local mismatches, first = 0, nil
    for p = 1, #mine, 4 do
      local a, b = mine:sub(p, p + 3), theirs:sub(p, p + 3)
      if a ~= b and not (a:byte(4) == 0 and b:byte(4) == 0) then
        mismatches = mismatches + 1
        if not first then
          local n = (p - 1) // 4
          first = ("(%d,%d) port %s vs rust %s"):format(n % width, n // width,
            table.concat({ a:byte(1, 4) }, ","), table.concat({ b:byte(1, 4) }, ","))
        end
      end
    end
    local line = ("%-38s %6d -> %3d colors  %6.2fs"):format(case.name, stats.before, stats.after, elapsed)
    if mismatches == 0 then
      print("same  " .. line)
    else
      different = different + 1
      print("DIFF  " .. line .. ("  %d pixels differ, first %s"):format(mismatches, first))
    end
  end)
  if not ok then
    different = different + 1
    print("ERROR " .. case.name .. ": " .. tostring(err))
  end
end
print(("RESULT %d cases, %d different"):format(#cases, different))
