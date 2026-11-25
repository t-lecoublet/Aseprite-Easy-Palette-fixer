-- Easy Palette Fixer
-- Reduces a sprite's colors or snaps it to a palette: a Lua port of Sprite
-- Fusion's Palette Snapper (MIT), for open sprites and whole folders.
--
-- Aseprite calls init() at startup, and exit() when it closes or the
-- extension is disabled.

function init(plugin)
  local use = dofile(app.fs.joinPath(plugin.path, "loader.lua"))(plugin.path)
  local dialog = use("dialog")

  -- "Easy Palette Fixer..." in the Sprite menu, under "Color Mode".
  plugin:newCommand {
    id = "EasyPaletteFixer",
    title = "Easy Palette Fixer...",
    group = "sprite_color",
    onclick = function()
      dialog.show(plugin.preferences)
    end,
  }
end

function exit(plugin)
end
