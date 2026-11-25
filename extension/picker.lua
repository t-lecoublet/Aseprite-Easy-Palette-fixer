-- A palette preset picker like Aseprite's Presets tab: a search field and a
-- list of names with their colors. Click to select, double-click (or
-- "Choose") to pick. Scroll with the wheel or the bar on the right.

local use = ...
local presets = use("presets")
local draw = use("draw")

local M = {}

local PAD, CELL, BAR = 6, 8, 10

-- Shows the picker (modal). Returns the chosen { id, path }, or nil.
function M.choose(currentId)
  local all = presets.find()
  local shown = all
  local selected, chosen
  local scroll, dragging = 0, false
  local rows, total = {}, 0 -- layout of `shown`: { y, h, line } in list coordinates
  local laidOutFor -- canvas width the layout was computed for
  local width, height = 460, 380 -- the canvas size, updated on paint
  local reveal = true -- scroll to the current preset on the first paint
  local dlg

  for _, entry in ipairs(all) do
    if entry.id == currentId then
      selected = entry
    end
  end

  local function layout(gc)
    local inner = gc.width - BAR - 2 * PAD
    local line = gc:measureText("Ag").height
    rows, total = {}, 0
    for i, entry in ipairs(shown) do
      local keys = presets.colors(entry.path) or {}
      local h = PAD + line + 3 + math.max(CELL, draw.stripHeight(#keys, inner, CELL)) + PAD
      rows[i] = { y = total, h = h, line = line }
      total = total + h
    end
    laidOutFor = gc.width
  end

  local function clampScroll()
    scroll = math.max(0, math.min(scroll, total - height))
  end

  local function rowAt(y)
    for i, row in ipairs(rows) do
      if y >= row.y and y < row.y + row.h then
        return i
      end
    end
  end

  local function scrollBarTo(y)
    if total > height then
      scroll = (y / height) * (total - height)
      clampScroll()
    end
  end

  local function paint(ev)
    local gc = ev.context
    width, height = gc.width, gc.height
    if laidOutFor ~= gc.width then
      layout(gc)
    end
    if reveal then
      reveal = false
      for i, entry in ipairs(shown) do
        if entry == selected then
          scroll = rows[i].y - (height - rows[i].h) // 2
        end
      end
    end
    clampScroll()
    local inner = gc.width - BAR - 2 * PAD

    gc.color = draw.theme("listitem_normal_face")
    gc:fillRect(Rectangle(0, 0, gc.width, gc.height))
    for i, entry in ipairs(shown) do
      local row = rows[i]
      local top = row.y - scroll
      if top + row.h >= 0 and top < gc.height then
        local isSelected = selected == entry
        if isSelected then
          gc.color = draw.theme("listitem_selected_face")
          gc:fillRect(Rectangle(0, top, gc.width - BAR, row.h))
        end
        gc.color = draw.theme(isSelected and "listitem_selected_text" or "listitem_normal_text")
        local keys = presets.colors(entry.path)
        local name = entry.id .. (keys and ("  (" .. #keys .. ")") or "  (unreadable)")
        gc:fillText(draw.ellipsize(gc, name, inner), PAD, top + PAD)
        if keys then
          draw.strip(gc, keys, PAD, top + PAD + row.line + 3, inner, CELL)
        end
      end
    end
    if #shown == 0 then
      gc.color = draw.theme("disabled")
      gc:fillText("No preset matches.", PAD, PAD)
    end

    gc.color = draw.theme("face")
    gc:fillRect(Rectangle(gc.width - BAR, 0, BAR, gc.height))
    if total > gc.height then
      local thumb = math.max(20, gc.height * gc.height // total)
      local y = (gc.height - thumb) * scroll // math.max(1, total - gc.height)
      gc.color = draw.theme("disabled")
      gc:fillRect(Rectangle(gc.width - BAR + 2, y, BAR - 4, thumb))
    end
  end

  local function filter()
    local query = (dlg.data.search or ""):lower()
    shown = {}
    for _, entry in ipairs(all) do
      if query == "" or entry.id:lower():find(query, 1, true) then
        shown[#shown + 1] = entry
      end
    end
    scroll, laidOutFor = 0, nil
    dlg:repaint()
  end

  local function pick()
    if selected then
      chosen = selected
      dlg:close()
    end
  end

  dlg = Dialog { title = "Palette presets" }
  dlg:entry { id = "search", label = "Search", text = "", onchange = filter }
  dlg:canvas {
    id = "list",
    width = width,
    height = height,
    onpaint = paint,
    onwheel = function(ev)
      scroll = scroll + ev.deltaY * 40
      clampScroll()
      dlg:repaint()
    end,
    onmousedown = function(ev)
      if ev.x >= width - BAR then
        dragging = true
        scrollBarTo(ev.y)
      else
        local i = rowAt(ev.y + scroll)
        if i then
          selected = shown[i]
        end
      end
      dlg:repaint()
    end,
    onmousemove = function(ev)
      if dragging then
        scrollBarTo(ev.y)
        dlg:repaint()
      end
    end,
    onmouseup = function()
      dragging = false
    end,
    ondblclick = function(ev)
      local i = rowAt(ev.y + scroll)
      if i then
        selected = shown[i]
        pick()
      end
    end,
  }
  dlg:button { text = "Choose", focus = true, onclick = pick }
  dlg:button { text = "Cancel", onclick = function() dlg:close() end }
  dlg:show { wait = true }
  return chosen
end

return M
