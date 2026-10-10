local tokyonight = require("tokyonight")
local colors = require("utils.colors")
local highlights = require("utils.theme_highlights")
local sync = require("utils.theme_sync")

highlights.register("editor", require("utils.editor_highlights").get)
tokyonight.setup({
  style = "moon",
  light_style = "day",
  transparent = true,
  terminal_colors = false,
  styles = {
    sidebars = "transparent",
    floats = "transparent",
  },
  on_colors = colors.update,
  on_highlights = highlights.extend,
})

local function apply_theme(mode)
  local expected = mode == "light" and "tokyonight-day" or "tokyonight-moon"
  if vim.o.background ~= mode then
    -- Neovim reloads the active colorscheme when background changes.
    vim.o.background = mode
  end
  if vim.g.colors_name ~= expected then
    vim.cmd.colorscheme("tokyonight")
  end
end

local config_home = vim.env.XDG_CONFIG_HOME
if not config_home or config_home == "" then
  config_home = vim.fn.expand("~/.config")
end
local mode_file = config_home .. "/theme/mode"

-- Missing/invalid state retains the terminal's native background detection.
apply_theme(sync.read_mode(mode_file) or vim.o.background)
-- Also support adopting an already-loaded TokyoNight and re-sourcing this file
-- without forcing another ColorScheme event.
if not colors.ready() then
  colors.update(require("tokyonight.colors").setup({ style = vim.o.background == "light" and "day" or "moon" }))
end
highlights.apply_all()
highlights.refresh()
sync.watch(mode_file, apply_theme)
vim.api.nvim_create_autocmd("VimLeavePre", {
  group = vim.api.nvim_create_augroup("SystemThemeLifecycle", { clear = true }),
  callback = sync.stop,
})
