local dashboard = require("dashboard")
local dashboard_utils = require("utils.dashboard")
local pad = require("utils.pad")

local seasonal_color_name = dashboard_utils.get_seasonal_highlight()

local function setup_highlights()
  local colors = require("utils.colors")

  if seasonal_color_name then
    vim.api.nvim_set_hl(0, "DashboardHeader", { fg = colors.palette[seasonal_color_name], bold = true })
  end

  vim.api.nvim_set_hl(0, "DashboardDesc", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "DashboardIcon", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "DashboardKey", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "DashboardFooter", { fg = colors.error })
end

setup_highlights()

local header = dashboard_utils.get_header()
local center = {
  { action = "FzfLua files", desc = pad(" Find file", 34, "right"), icon = " ", key = "f" },
  { action = "FzfLua oldfiles", desc = pad(" Recent files", 34, "right"), icon = " ", key = "r" },
  { action = "FzfLua live_grep", desc = pad(" Find text", 34, "right"), icon = "󰺮 ", key = "g" },
  { action = "NvimTreeToggle", desc = pad(" File tree", 34, "right"), icon = "󰙅 ", key = "e" },
  { action = "q", desc = pad(" Quit", 34, "right"), icon = " ", key = "q" },
}
local footer = dashboard_utils.footer

dashboard.setup({
  theme = "doom",
  hide = {
    statusline = true,
    tabline = true,
    winbar = true,
  },
  config = {
    header = header,
    center = center,
    footer = footer,
    vertical_center = true,
  },
})
setup_highlights()

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("DashboardHighlights", { clear = true }),
  callback = setup_highlights,
})

return {
  setup_highlights = setup_highlights,
}
