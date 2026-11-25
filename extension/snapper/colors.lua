-- Made by Sprite Fusion: https://www.spritefusion.com
-- MIT License. Copyright (c) 2026 Hugo Duprez.
-- Keep this notice in copies and adaptations of this file.
--
-- Lua port of src/colors.rs and merge_colors (src/palette.rs) from
-- spritefusion-palette-snapper, for Easy Palette Fixer.
--
-- Works on color counts, not on pixels: a list of { key = 0xRRGGBB, count = n }
-- in the order the colors were first seen. Results are tables key -> key.

local use = ...
local oklab = use("snapper/oklab")

local distance = oklab.distance
local floor = math.floor
local huge = math.huge

local M = {}

M.DEFAULT_THRESHOLD = 0.03
M.DEFAULT_MAX_COLORS = 32
local SNAP_MERGE = 0.03
-- Distinct 8-bit colors are always much further apart than this in OKLab,
-- so below it nothing can merge and the search is skipped.
local NO_MERGE_BELOW = 1e-5

-- Adds l, a, b (OKLab) to each color, once.
function M.withLab(colors)
  for _, color in ipairs(colors) do
    if not color.l then
      color.l, color.a, color.b = oklab.toOklab(color.key)
    end
  end
  return colors
end

-- Similar colors (within threshold) merge into the one that appears most often,
-- then the closest keep merging until at most maxColors remain (nil: no cap).
-- Gives the same result as the original, with two speedups:
--   * a grid of threshold-sized cells, so each color is only compared with
--     the clusters next to it;
--   * a merged cluster keeps the color of its biggest side, so distances never
--     change: each cluster remembers its nearest neighbor instead of comparing
--     every pair again after each merge.
function M.merge(colors, threshold, maxColors)
  M.withLab(colors)
  local n = #colors

  -- Most frequent first; ties keep their first-seen order (Rust's stable sort).
  local order = {}
  for i = 1, n do
    order[i] = i
  end
  table.sort(order, function(x, y)
    local cx, cy = colors[x].count, colors[y].count
    if cx ~= cy then
      return cx > cy
    end
    return x < y
  end)

  -- Clusters as parallel arrays, indexed by creation order.
  local cKey, cL, cA, cB, cCount = {}, {}, {}, {}, {}
  local clusterOf = {}
  local k = 0

  local grid, cell
  if threshold >= NO_MERGE_BELOW then
    grid = {}
    -- A little over threshold, so two colors within threshold are never more
    -- than one cell apart, even with rounding.
    cell = threshold * 1.000001
  end

  for _, i in ipairs(order) do
    local color = colors[i]
    local l, a, b = color.l, color.a, color.b
    local best, bestD = nil, huge
    local gx, gy, gz
    if grid then
      gx, gy, gz = floor(l / cell), floor(a / cell), floor(b / cell)
      for x = gx - 1, gx + 1 do
        local plane = grid[x]
        if plane then
          for y = gy - 1, gy + 1 do
            local row = plane[y]
            if row then
              for z = gz - 1, gz + 1 do
                local list = row[z]
                if list then
                  for _, at in ipairs(list) do
                    local d = distance(l, a, b, cL[at], cA[at], cB[at])
                    -- Ties go to the oldest cluster, as in the original.
                    if d < bestD or (d == bestD and at < best) then
                      best, bestD = at, d
                    end
                  end
                end
              end
            end
          end
        end
      end
    end

    if best and bestD <= threshold then
      cCount[best] = cCount[best] + color.count
      clusterOf[i] = best
    else
      k = k + 1
      cKey[k], cL[k], cA[k], cB[k], cCount[k] = color.key, l, a, b, color.count
      clusterOf[i] = k
      if grid then
        local plane = grid[gx]
        if not plane then
          plane = {}
          grid[gx] = plane
        end
        local row = plane[gy]
        if not row then
          row = {}
          plane[gy] = row
        end
        local list = row[gz]
        if not list then
          list = {}
          row[gz] = list
        end
        list[#list + 1] = k
      end
    end
  end

  -- Then the closest pair keeps merging until at most maxColors remain.
  local parent = {}
  if maxColors and k > maxColors then
    local alive, nn, nnD = {}, {}, {}
    for i = 1, k do
      alive[i] = true
    end
    local function nearest(i)
      local l, a, b = cL[i], cA[i], cB[i]
      local best, bestD = nil, huge
      for j = 1, k do
        if j ~= i and alive[j] then
          local d = distance(l, a, b, cL[j], cA[j], cB[j])
          if d < bestD then
            best, bestD = j, d
          end
        end
      end
      nn[i], nnD[i] = best, bestD
    end
    for i = 1, k do
      nearest(i)
    end

    local remaining = k
    while remaining > maxColors do
      -- The closest pair; ties go to the lowest (i, j), as in the original.
      local pa, pb, pd = nil, nil, huge
      for i = 1, k do
        if alive[i] and nnD[i] <= pd then
          local j = nn[i]
          local a, b = i, j
          if j < i then
            a, b = j, i
          end
          if pa == nil or nnD[i] < pd or a < pa or (a == pa and b < pb) then
            pa, pb, pd = a, b, nnD[i]
          end
        end
      end
      local keep, drop = pa, pb
      if cCount[pb] > cCount[pa] then
        keep, drop = pb, pa
      end
      cCount[keep] = cCount[keep] + cCount[drop]
      alive[drop] = false
      parent[drop] = keep
      remaining = remaining - 1
      for i = 1, k do
        if alive[i] and nn[i] == drop then
          nearest(i)
        end
      end
    end
  end

  local rootOf = {}
  local function root(i)
    local path = {}
    while not rootOf[i] and parent[i] do
      path[#path + 1] = i
      i = parent[i]
    end
    local r = rootOf[i] or i
    for _, at in ipairs(path) do
      rootOf[at] = r
    end
    return r
  end

  local replacement = {}
  for i = 1, n do
    replacement[colors[i].key] = cKey[root(clusterOf[i])]
  end
  return replacement
end

-- Fewer colors, without a palette. Every color left is one that was drawn.
function M.reduce(colors, maxColors, threshold)
  if maxColors ~= nil and (math.type(maxColors) ~= "integer" or maxColors < 1) then
    error("Max colors is a whole number from 1; got " .. tostring(maxColors) .. ".", 0)
  end
  if type(threshold) ~= "number" or threshold ~= threshold or threshold < 0 or threshold == huge then
    error("Threshold is a distance from 0; got " .. tostring(threshold) .. ".", 0)
  end
  return M.merge(colors, threshold, maxColors)
end

local function lightnessQuantile(colors, quantile)
  local sorted, total = {}, 0
  for i, color in ipairs(colors) do
    sorted[i] = color
    total = total + color.count
  end
  table.sort(sorted, function(x, y)
    return x.l < y.l
  end)
  local seen = 0
  for _, color in ipairs(sorted) do
    seen = seen + color.count
    if seen >= quantile * total then
      return color.l
    end
  end
  return sorted[#sorted] and sorted[#sorted].l or 0
end

-- Every color becomes one of the palette's (a list of keys, 1 to 256 distinct):
--   "nearest": the palette color closest to it (OKLab);
--   "lightness": the sprite's lightness range (2nd to 98th percentile of its
--   pixels) is stretched over the palette's, and each color takes the palette
--   color closest in lightness.
function M.snap(colors, palette, mode)
  if mode ~= "nearest" and mode ~= "lightness" then
    error("Unknown mode: " .. tostring(mode), 0)
  end
  local swatches, seen = {}, {}
  for _, key in ipairs(palette) do
    if not seen[key] then
      seen[key] = true
      local l, a, b = oklab.toOklab(key)
      swatches[#swatches + 1] = { key = key, l = l, a = a, b = b }
    end
  end
  if #swatches == 0 then
    error("The palette has no colors.", 0)
  end
  if #swatches > 256 then
    error("A palette has at most 256 colors; this one has " .. #swatches .. ".", 0)
  end
  if #colors == 0 then
    return {}
  end

  M.withLab(colors)
  local low = lightnessQuantile(colors, 0.02)
  local high = lightnessQuantile(colors, 0.98)
  local paletteLow, paletteHigh = huge, -huge
  for _, swatch in ipairs(swatches) do
    paletteLow = math.min(paletteLow, swatch.l)
    paletteHigh = math.max(paletteHigh, swatch.l)
  end
  local function stretched(lightness)
    if high > low then
      local clamped = math.min(math.max(lightness, low), high)
      return paletteLow + ((clamped - low) / (high - low)) * (paletteHigh - paletteLow)
    end
    return lightness
  end

  local merged = M.merge(colors, SNAP_MERGE, nil)
  local chosen = {}
  local function swatchFor(key)
    local found = chosen[key]
    if found then
      return found
    end
    local l, a, b = oklab.toOklab(key)
    local target = stretched(l)
    local best, bestD = 1, huge
    for at, swatch in ipairs(swatches) do
      local d
      if mode == "lightness" then
        d = math.abs(target - swatch.l)
      else
        d = distance(l, a, b, swatch.l, swatch.a, swatch.b)
      end
      if d < bestD then
        best, bestD = at, d
      end
    end
    found = swatches[best].key
    chosen[key] = found
    return found
  end

  local mapping = {}
  for _, color in ipairs(colors) do
    mapping[color.key] = swatchFor(merged[color.key])
  end
  return mapping
end

return M
