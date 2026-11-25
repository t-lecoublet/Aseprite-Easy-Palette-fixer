-- The Easy Palette Fixer window. It stays open: look at the preview, apply,
-- undo with Ctrl+Z, adjust, apply again. Folders are processed one file per
-- timer tick so the window keeps showing progress.
--
-- The logic (settings -> options -> preview / run) is separate from the
-- widgets, so the tests can run it in batch mode, where Aseprite has no UI.

local use = ...
local recolor = use("recolor")
local batch = use("batch")
local palette = use("snapper/palette")
local files = use("files")
local draw = use("draw")
local picker = use("picker")

local M = {}

local TITLE = "Easy Palette Fixer"

-- Settings use these keys; the window shows the labels.
local LABELS = {
  mode = { { "reduce", "Reduce colors" }, { "snap", "Snap to a palette" } },
  source = {
    { "sprite", "Active sprite's palette" },
    { "preset", "Aseprite preset" },
    { "file", "Palette file" },
    { "hex", "Hex colors" },
  },
  match = { { "nearest", "Nearest color" }, { "lightness", "By lightness" } },
  target = {
    { "sprite", "Active sprite (all of it)" },
    { "cels", "Selected cels" },
    { "open", "All open sprites" },
    { "folder", "Images in a folder" },
  },
  output = {
    { "suffix", "Beside: name_snapped" },
    { "folder", 'In a "snapped" subfolder' },
    { "replace", "Replace the originals" },
  },
}

M.DEFAULTS = {
  mode = "reduce",
  maxColors = 32,
  noCap = false,
  threshold = 0.03,
  source = "sprite",
  presetId = "",
  presetPath = "",
  paletteFile = "",
  hexColors = "#081820 #346856 #88c070 #e0f8d0",
  match = "nearest",
  target = "sprite",
  folderFile = "",
  recursive = false,
  output = "suffix",
  live = true,
}

local function labelOf(field, key)
  for _, pair in ipairs(LABELS[field]) do
    if pair[1] == key then
      return pair[2]
    end
  end
  return LABELS[field][1][2]
end

local function keyOf(field, label)
  for _, pair in ipairs(LABELS[field]) do
    if pair[2] == label then
      return pair[1]
    end
  end
  return LABELS[field][1][1]
end

local function labels(field)
  local result = {}
  for i, pair in ipairs(LABELS[field]) do
    result[i] = pair[2]
  end
  return result
end

local function plural(n, word)
  return n .. " " .. word .. (n == 1 and "" or "s")
end

-- Saved settings over the defaults.
function M.settings(saved)
  local settings = {}
  for name, value in pairs(M.DEFAULTS) do
    local stored = saved and saved[name]
    if stored == nil or type(stored) ~= type(value) then
      stored = value
    end
    settings[name] = stored
  end
  return settings
end

-- The palette to snap to. `cache` (optional) keeps palettes read from files
-- between previews; applying reads them again.
function M.paletteFor(settings, cache)
  if settings.source == "sprite" then
    if not app.sprite then
      error("No active sprite to take the palette from.", 0)
    end
    return recolor.spritePalette(app.sprite)
  elseif settings.source == "hex" then
    return palette.parse(settings.hexColors)
  end

  local path, load
  if settings.source == "preset" then
    path = settings.presetPath
    if path == "" then
      error("Choose a palette preset.", 0)
    end
    load = function()
      return palette.unique(recolor.paletteKeys(files.loadPalette(path)))
    end
  else
    path = settings.paletteFile
    if path == "" then
      error("Choose a palette file.", 0)
    end
    load = function()
      return recolor.paletteFromFile(path)
    end
  end
  if not cache then
    return load()
  end
  local id = settings.source .. "|" .. path
  if not cache[id] then
    cache[id] = { pcall(load) }
  end
  if not cache[id][1] then
    error(cache[id][2], 0)
  end
  return cache[id][2]
end

-- What recolor needs, from the settings.
function M.options(settings, cache)
  if settings.mode == "reduce" then
    local maxColors = nil
    if not settings.noCap then
      -- Checked by hand: Aseprite's math.tointeger(2.5) doesn't return nil.
      local n = settings.maxColors
      if type(n) ~= "number" or n % 1 ~= 0 or n < 1 then
        error("Max colors: a whole number from 1.", 0)
      end
      maxColors = math.tointeger(n)
    end
    return { mode = "reduce", maxColors = maxColors, threshold = settings.threshold }
  end
  return { mode = "snap", palette = M.paletteFor(settings, cache), snapMode = settings.match }
end

-- The selected cels of the active sprite, or its active cel.
local function selectedCels()
  local cels = {}
  local range = app.range
  if range and not range.isEmpty then
    for _, cel in ipairs(range.cels) do
      cels[#cels + 1] = cel
    end
  end
  if #cels == 0 and app.cel then
    cels[1] = app.cel
  end
  if #cels == 0 then
    error("No cel selected.", 0)
  end
  return cels
end

-- Sprites and cels the settings point at, for every target but "folder".
local function spriteJobs(target)
  if target == "open" then
    local jobs = {}
    for _, sprite in ipairs(app.sprites) do
      jobs[#jobs + 1] = { sprite = sprite, cels = sprite.cels }
    end
    if #jobs == 0 then
      error("No open sprite.", 0)
    end
    return jobs
  end
  local sprite = app.sprite
  if not sprite then
    error("No active sprite.", 0)
  end
  if target == "cels" then
    return { { sprite = sprite, cels = selectedCels() } }
  end
  return { { sprite = sprite, cels = sprite.cels } }
end

-- What the preview shows: an RGB image, and the colors that decide the
-- mapping (the same ones "Apply" uses). Changes nothing.
function M.previewSource(settings)
  if settings.target == "folder" then
    if settings.folderFile == "" then
      error("Choose an image in the folder to see the preview.", 0)
    end
    local image = recolor.loadRgbImage(settings.folderFile)
    return { image = image, state = recolor.collectImage(image), what = app.fs.fileName(settings.folderFile) }
  end
  local sprite = app.sprite
  if not sprite then
    error("No active sprite.", 0)
  end
  local frame = app.frame and app.frame.frameNumber or 1
  if settings.target == "cels" then
    local cels = selectedCels()
    local shown = app.cel or cels[1]
    -- A tilemap cel holds tile numbers, not colors: show the whole frame.
    local image = shown.layer.isTilemap and recolor.renderFrame(sprite, frame) or recolor.celImage(shown)
    return { image = image, state = recolor.collect(sprite, cels), what = "active cel" }
  end
  return {
    image = recolor.renderFrame(sprite, frame),
    state = recolor.collect(sprite, sprite.cels),
    what = settings.target == "open" and "active sprite" or ("frame " .. frame),
  }
end

-- Before/after images and the result's colors, for a preview source.
function M.preview(source, opts)
  local mapping = recolor.mapping(source.state, opts)
  local targets = recolor.targets(mapping)
  return {
    before = source.image,
    after = recolor.recolorImage(source.image, mapping),
    beforeCount = #source.state.list,
    afterCount = #targets,
    targets = targets,
    what = source.what,
  }
end

-- Recolors open sprites, one undo step per sprite. Returns a one-line summary
-- and the errors of sprites that failed.
function M.applyToSprites(settings, opts)
  local jobs = spriteJobs(settings.target)
  local previous = app.sprite
  local done, failed, cels, notes = {}, {}, 0, {}
  for _, job in ipairs(jobs) do
    app.sprite = job.sprite
    local ok, result = pcall(function()
      local stats
      app.transaction(TITLE, function()
        stats = recolor.processSprite(job.sprite, job.cels, opts)
      end)
      return stats
    end)
    if ok then
      done[#done + 1] = result
      cels = cels + result.changed
      if result.converted then
        notes.converted = true
      end
      if result.skipped > 0 then
        notes.skipped = (notes.skipped or 0) + result.skipped
      end
    elseif #jobs == 1 then
      if previous then
        app.sprite = previous
      end
      error(result, 0)
    else
      failed[#failed + 1] = app.fs.fileName(job.sprite.filename) .. " : " .. tostring(result)
    end
  end
  if previous then
    app.sprite = previous
  end
  app.refresh()

  local summary
  if #jobs == 1 then
    local stats = done[1]
    summary = ("%s → %s, %s changed"):format(
      plural(stats.before, "color"), plural(stats.after, "color"), plural(stats.changed, "cel"))
  else
    summary = ("%d of %d sprites, %s changed"):format(#done, #jobs, plural(cels, "cel"))
  end
  if notes.converted then
    summary = summary .. " (Grayscale converted to RGB)"
  end
  if notes.skipped then
    summary = summary .. (" (%s skipped: locked, tilemap or reference)"):format(plural(notes.skipped, "cel"))
  end
  return summary, failed
end

-- The files a folder run would process.
function M.folderFiles(settings)
  if settings.folderFile == "" then
    error("Choose an image in the folder to process.", 0)
  end
  local dir = app.fs.filePath(settings.folderFile)
  local list = batch.listImages(dir, settings.recursive, settings.output)
  if #list == 0 then
    error("No images in " .. dir, 0)
  end
  return list, dir
end

local IMAGE_TYPES = { "png", "gif", "jpg", "jpeg", "webp", "bmp", "tga", "aseprite", "ase" }
local PALETTE_TYPES = { "hex", "txt", "gpl", "json", "pal", "act", "col", "png", "gif", "jpg", "jpeg", "webp", "bmp", "aseprite", "ase" }

local PAD, CELL = 6, 8
local MAX_STRIP_ROWS = 4

-- Draws up to MAX_STRIP_ROWS rows of colors; says how many didn't fit.
local function paintStrip(gc, keys, x, y, width)
  local perLine = math.max(1, width // CELL)
  local room = perLine * MAX_STRIP_ROWS
  local shown = keys
  if #keys > room then
    shown = { table.unpack(keys, 1, room - perLine // 4) }
  end
  local h = draw.strip(gc, shown, x, y, width, CELL)
  if #shown < #keys then
    gc.color = draw.theme("text")
    local last = (#shown - 1) // perLine
    gc:fillText(("+%d"):format(#keys - #shown), x + (#shown % perLine) * CELL + 4, y + last * CELL - 2)
  end
  return h
end

local current -- the open window, if any

function M.show(saved)
  if current then
    current:close()
  end
  local settings = M.settings(saved)
  local presetId, presetPath = settings.presetId, settings.presetPath
  local dlg
  local batchTimer, previewTimer
  local busy = false -- a folder is being processed
  local paletteCache = {}
  local source -- cached preview source, nil when it must be read again
  local strip = { message = "" } -- the target palette, for the strip canvas
  local shownPreview = { message = "" } -- what the preview canvas draws
  local view = draw.FIT -- the preview's zoom and position, shared by both panels
  local panels = {} -- the panels' rects and image sizes, from the last paint
  local drag -- set while the preview is being dragged
  local siteListener, watched, watchListener

  local function read()
    local data = dlg.data
    return {
      mode = keyOf("mode", data.mode),
      maxColors = data.maxColors,
      noCap = data.noCap,
      threshold = data.threshold,
      source = keyOf("source", data.source),
      presetId = presetId,
      presetPath = presetPath,
      paletteFile = data.paletteFile or "",
      hexColors = data.hexColors,
      match = keyOf("match", data.match),
      target = keyOf("target", data.target),
      folderFile = data.folderFile or "",
      recursive = data.recursive,
      output = keyOf("output", data.output),
      live = data.live,
    }
  end

  local function save()
    if saved then
      for name, value in pairs(read()) do
        saved[name] = value
      end
    end
  end

  local function status(text)
    dlg:modify { id = "status", text = text }
  end

  -- Reads the palette and computes the preview. Runs shortly after the last
  -- change, so typing in a field doesn't recompute at every key.
  local function update()
    local s = read()
    if s.mode == "snap" then
      local ok, keys = pcall(M.paletteFor, s, paletteCache)
      strip = ok and { keys = keys } or { message = tostring(keys) }
    end
    if not s.live then
      shownPreview = { message = "Preview off." }
    else
      local ok, result = pcall(function()
        if not source or source.target ~= s.target or source.file ~= s.folderFile then
          source = M.previewSource(s)
          source.target, source.file = s.target, s.folderFile
        end
        return M.preview(source, M.options(s, paletteCache))
      end)
      shownPreview = ok and result or { message = tostring(result) }
    end
    dlg:repaint()
  end

  local function schedule()
    if not busy and previewTimer then
      previewTimer:stop()
      previewTimer:start()
    end
  end

  -- Follows the active sprite: drawing in it or undoing refreshes the preview.
  local function watch(sprite)
    if sprite == watched then
      return
    end
    if watched and watchListener then
      pcall(function() watched.events:off(watchListener) end)
    end
    watched, watchListener = sprite, nil
    if sprite then
      watchListener = sprite.events:on("change", function()
        source = nil
        schedule()
      end)
    end
  end

  local function refresh()
    local s = read()
    local reduce = s.mode == "reduce"
    for _, id in ipairs({ "reduceSep", "maxColors", "noCap", "threshold" }) do
      dlg:modify { id = id, visible = reduce }
    end
    dlg:modify { id = "maxColors", enabled = not s.noCap }
    for _, id in ipairs({ "paletteSep", "source", "match", "strip" }) do
      dlg:modify { id = id, visible = not reduce }
    end
    dlg:modify { id = "preset", visible = not reduce and s.source == "preset" }
    dlg:modify { id = "paletteFile", visible = not reduce and s.source == "file" }
    dlg:modify { id = "hexColors", visible = not reduce and s.source == "hex" }
    local folder = s.target == "folder"
    for _, id in ipairs({ "folderFile", "recursive", "output" }) do
      dlg:modify { id = id, visible = folder }
    end
    dlg:modify { id = "preview", visible = s.live }
  end

  local function changed()
    refresh()
    schedule()
  end

  local function alertFailures(failed)
    if #failed == 0 then
      return
    end
    local text = { "Errors:" }
    for i = 1, math.min(#failed, 10) do
      text[#text + 1] = failed[i]
    end
    if #failed > 10 then
      text[#text + 1] = ("… and %d more."):format(#failed - 10)
    end
    app.alert { title = TITLE, text = text }
  end

  local function runFolder(s, opts)
    local list, dir = M.folderFiles(s)
    if s.output == "replace" then
      local answer = app.alert {
        title = TITLE,
        text = { ("Replace %d original images in %s?"):format(#list, dir), "This can't be undone." },
        buttons = { "Replace", "Cancel" },
      }
      if answer ~= 1 then
        return
      end
    else
      local existing = 0
      for _, path in ipairs(list) do
        if app.fs.isFile(batch.outputPath(path, s.output)) then
          existing = existing + 1
        end
      end
      if existing > 0 then
        local answer = app.alert {
          title = TITLE,
          text = ("%d result image(s) already exist and will be replaced."):format(existing),
          buttons = { "Continue", "Cancel" },
        }
        if answer ~= 1 then
          return
        end
      end
    end

    opts.output = s.output
    local previous = app.sprite
    local i, done, failed = 0, 0, {}
    busy = true
    dlg:modify { id = "apply", enabled = false }
    status(("0 / %d…"):format(#list))
    batchTimer = Timer {
      interval = 0.01,
      ontick = function()
        i = i + 1
        local path = list[i]
        local ok, err = pcall(batch.processFile, path, opts)
        if ok then
          done = done + 1
        else
          failed[#failed + 1] = app.fs.fileName(path) .. " : " .. tostring(err)
        end
        status(("%d / %d : %s"):format(i, #list, app.fs.fileName(path)))
        if i >= #list then
          batchTimer:stop()
          batchTimer = nil
          if previous then
            pcall(function() app.sprite = previous end)
          end
          busy = false
          dlg:modify { id = "apply", enabled = true }
          status(("%s done, %d failed"):format(plural(done, "image"), #failed))
          alertFailures(failed)
          schedule()
        end
      end,
    }
    batchTimer:start()
  end

  local function apply()
    local s = read()
    save()
    local ok, err = pcall(function()
      local opts = M.options(s)
      if s.target == "folder" then
        runFolder(s, opts)
      else
        local summary, failed = M.applyToSprites(s, opts)
        status(summary)
        alertFailures(failed)
      end
    end)
    if not ok then
      status("")
      app.alert { title = TITLE, text = tostring(err) }
    end
  end

  local function choosePreset()
    local entry = picker.choose(presetId)
    if entry then
      presetId, presetPath = entry.id, entry.path
      dlg:modify { id = "preset", text = presetId }
      schedule()
    end
  end

  local function paintStripCanvas(ev)
    local gc = ev.context
    gc.color = draw.theme("listitem_normal_face")
    gc:fillRect(Rectangle(0, 0, gc.width, gc.height))
    if strip.keys then
      gc.color = draw.theme("text")
      gc:fillText(plural(#strip.keys, "color"), PAD, PAD)
      paintStrip(gc, strip.keys, PAD, PAD + gc:measureText("Ag").height + 3, gc.width - 2 * PAD)
    else
      gc.color = draw.theme("disabled")
      gc:fillText(draw.ellipsize(gc, strip.message or "", gc.width - 2 * PAD), PAD, PAD)
    end
  end

  local function paintPreview(ev)
    local gc = ev.context
    local w, h = gc.width, gc.height
    gc.color = draw.theme("listitem_normal_face")
    gc:fillRect(Rectangle(0, 0, w, h))
    local p = shownPreview
    if not p.before then
      gc.color = draw.theme("disabled")
      gc:fillText(draw.ellipsize(gc, p.message or "", w - 2 * PAD), PAD, PAD)
      return
    end

    local line = gc:measureText("Ag").height
    local inner = w - 2 * PAD
    local perLine = math.max(1, inner // CELL)
    local stripH = math.min(MAX_STRIP_ROWS, math.ceil(#p.targets / perLine)) * CELL
    local panelW = (w - 3 * PAD) // 2
    local top = PAD + line + 4
    local panelH = h - top - PAD - (line + 3 + stripH + PAD)

    local beforeRect = Rectangle(PAD, top, panelW, panelH)
    local afterRect = Rectangle(2 * PAD + panelW, top, panelW, panelH)
    local zoom = view.zoom > 1 and (" · x%d"):format(view.zoom) or ""
    gc.color = draw.theme("text")
    gc:fillText(draw.ellipsize(gc, ("Before · %s · %s%s"):format(plural(p.beforeCount, "color"), p.what, zoom), panelW), PAD, PAD)
    gc:fillText(draw.ellipsize(gc, "After · " .. plural(p.afterCount, "color"), panelW), 2 * PAD + panelW, PAD)
    draw.image(gc, p.before, beforeRect, view)
    draw.image(gc, p.after, afterRect, view)
    panels = {
      { rect = beforeRect, w = p.before.width, h = p.before.height },
      { rect = afterRect, w = p.after.width, h = p.after.height },
    }

    local y = top + panelH + PAD
    gc.color = draw.theme("text")
    gc:fillText("Result colors", PAD, y)
    paintStrip(gc, p.targets, PAD, y + line + 3, inner)
  end

  -- Wheel: zoom under the mouse. Drag: move. Double-click: fit again.
  local function panelAt(x, y)
    for _, panel in ipairs(panels) do
      local r = panel.rect
      if x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height then
        return panel
      end
    end
  end

  local function zoomPreview(ev)
    local panel = panelAt(ev.x, ev.y) or panels[1]
    if panel and ev.deltaY and ev.deltaY ~= 0 then
      view = draw.zoomAt(view, panel.w, panel.h, panel.rect, ev.x, ev.y, ev.deltaY < 0 and 2 or 0.5)
      dlg:repaint()
    end
  end

  local function startDrag(ev)
    local panel = panelAt(ev.x, ev.y)
    if panel then
      drag = { x = ev.x, y = ev.y, view = view, panel = panel }
    end
  end

  local function dragPreview(ev)
    if not drag then
      return
    end
    if ev.button == MouseButton.NONE then -- released outside the preview
      drag = nil
      return
    end
    local panel = drag.panel
    view = draw.pan(drag.view, panel.w, panel.h, panel.rect, ev.x - drag.x, ev.y - drag.y)
    dlg:repaint()
  end

  dlg = Dialog {
    title = TITLE,
    onclose = function()
      if batchTimer then
        batchTimer:stop()
      end
      if previewTimer then
        previewTimer:stop()
      end
      batchTimer, previewTimer = nil, nil
      if siteListener then
        app.events:off(siteListener)
      end
      watch(nil)
      save()
      current = nil
    end,
  }

  dlg:combobox {
    id = "mode", label = "Action",
    option = labelOf("mode", settings.mode), options = labels("mode"),
    onchange = changed,
  }

  dlg:separator { id = "reduceSep", text = "Reduce" }
  dlg:number {
    id = "maxColors", label = "Max colors", text = tostring(settings.maxColors), decimals = 0,
    onchange = schedule,
  }
  dlg:check { id = "noCap", text = "No limit", selected = settings.noCap, onclick = changed }
  dlg:number {
    id = "threshold", label = "Merge threshold", text = tostring(settings.threshold), decimals = 3,
    onchange = schedule,
  }

  dlg:separator { id = "paletteSep", text = "Palette" }
  dlg:combobox {
    id = "source", label = "Palette",
    option = labelOf("source", settings.source), options = labels("source"),
    onchange = changed,
  }
  dlg:button {
    id = "preset", label = "Preset", text = presetId ~= "" and presetId or "Choose…",
    onclick = choosePreset,
  }
  dlg:file {
    id = "paletteFile", label = "File", title = "Choose a palette", open = true, entry = true,
    filename = settings.paletteFile, filetypes = PALETTE_TYPES, onchange = schedule,
  }
  dlg:entry { id = "hexColors", label = "Colors", text = settings.hexColors, onchange = schedule }
  dlg:combobox {
    id = "match", label = "Matching",
    option = labelOf("match", settings.match), options = labels("match"),
    onchange = schedule,
  }
  dlg:canvas { id = "strip", width = 400, height = 52, onpaint = paintStripCanvas }

  dlg:separator { text = "Apply to" }
  dlg:combobox {
    id = "target", label = "Target",
    option = labelOf("target", settings.target), options = labels("target"),
    onchange = changed,
  }
  dlg:file {
    id = "folderFile", label = "An image in the folder", title = "Choose an image in the folder to process",
    open = true, entry = true, filename = settings.folderFile, filetypes = IMAGE_TYPES, onchange = schedule,
  }
  dlg:check { id = "recursive", text = "Include subfolders", selected = settings.recursive }
  dlg:combobox {
    id = "output", label = "Output",
    option = labelOf("output", settings.output), options = labels("output"),
  }

  dlg:separator { text = "Preview (wheel: zoom, drag: move, double-click: fit)" }
  dlg:check { id = "live", text = "Before / after preview", selected = settings.live, onclick = changed }
  dlg:canvas {
    id = "preview", width = 400, height = 300,
    onpaint = paintPreview,
    onwheel = zoomPreview,
    onmousedown = startDrag,
    onmousemove = dragPreview,
    onmouseup = function() drag = nil end,
    ondblclick = function()
      view = draw.FIT
      dlg:repaint()
    end,
  }

  dlg:separator()
  dlg:label { id = "status", text = "" }
  dlg:button { id = "apply", text = "Apply", focus = true, onclick = apply }
  dlg:button { id = "close", text = "Close", onclick = function() dlg:close() end }

  previewTimer = Timer {
    interval = 0.25,
    ontick = function()
      previewTimer:stop()
      update()
    end,
  }
  siteListener = app.events:on("sitechange", function()
    if busy then
      return
    end
    source = nil
    watch(app.sprite)
    schedule()
  end)
  watch(app.sprite)

  refresh()
  current = dlg
  dlg:show { wait = false }
  update()
end

return M
