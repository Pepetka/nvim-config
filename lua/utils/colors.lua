local ok, tokyonight = pcall(require, "tokyonight.colors")
local palette = ok and tokyonight.setup() or {}

---Semantic color aliases for use across the config.
---Swapping the colorscheme only requires updating this file.
local colors = {
  fg = palette.fg or "#c0caf5",
  bg = palette.bg or "#1a1b26",
  bg_visual = palette.bg_visual or "#283457",

  error = palette.red or "#ff757f",
  warning = palette.yellow or "#ffc777",
  info = palette.blue or "#82aaff",
  success = palette.green or "#c3e88d",

  muted = palette.comment or "#636da6",
  subtle = palette.dark3 or "#545c7e",
  surface = palette.bg_highlight or "#2f334d",
  gutter = palette.fg_gutter or "#3b4261",

  accent = palette.cyan or "#86e1fc",
  focus = palette.blue or "#82aaff",

  alert = palette.orange or "#ff9e64",
  special = palette.magenta or "#bb9af7",
  experimental = palette.magenta2 or "#ff007c",

  -- Raw theme palette for special cases.
  palette = palette,
}
return colors
