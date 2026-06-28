local M = {}

local palette_cache = { style = nil, palette = nil }

local function get_palette()
  local ok_tn, tokyonight = pcall(require, "tokyonight")
  if not ok_tn then
    return {}
  end

  -- tokyonight.load() records the active style per background.
  -- Use that instead of the configured default style so light/day is returned
  -- when the user switches to a light background.
  local style = tokyonight.styles and tokyonight.styles[vim.o.background]
    or (vim.o.background == "light" and "day" or "moon")

  if palette_cache.style == style then
    return palette_cache.palette
  end

  local ok_colors, colors_mod = pcall(require, "tokyonight.colors")
  if not ok_colors then
    return {}
  end

  local palette = colors_mod.setup({ style = style })
  palette_cache.style = style
  palette_cache.palette = palette
  return palette
end

setmetatable(M, {
  __index = function(_, key)
    local palette = get_palette()
    if not palette then
      return nil
    end

    if key == "palette" then
      return palette
    end

    -- Semantic aliases. Keep this list small and meaningful.
    -- For raw tokyonight colors use colors.palette.<name>.
    local aliases = {
      fg = palette.fg,
      bg = palette.bg,
      bg_visual = palette.bg_visual,

      error = palette.error,
      warning = palette.warning,
      info = palette.info,
      success = palette.green,

      muted = palette.comment,
      subtle = palette.dark3,
      surface = palette.bg_highlight,
      gutter = palette.fg_gutter,

      accent = palette.cyan,
      focus = palette.blue,
      alert = palette.orange,
      special = palette.magenta,
      test = palette.magenta2,
    }

    return aliases[key]
  end,
})

return M
