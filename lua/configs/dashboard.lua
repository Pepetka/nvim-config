local dashboard = require("dashboard")
local dashboard_utils = require("utils.dashboard")
local pad = require("utils.pad")

local theme_highlights = require("utils.theme_highlights")
local seasonal_color = dashboard_utils.get_seasonal_highlight()

theme_highlights.register("dashboard", function(c)
  return {
    DashboardHeader = { fg = c.palette[seasonal_color or "blue"], bold = seasonal_color and true or nil },
    DashboardDesc = { fg = c.muted },
    DashboardIcon = { fg = c.muted },
    DashboardKey = { fg = c.muted },
    DashboardFooter = { fg = c.error },
  }
end)

-- Hide chrome before rendering; dashboard itself saves/restores the user's
-- options. Native statusline refreshes can reveal it again on ColorScheme.
local function hide_dashboard_ui()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "dashboard" and vim.api.nvim_win_get_config(win).relative == "" then
      vim.o.laststatus = 0
      vim.o.showtabline = 0
      vim.o.winbar = ""
      return
    end
  end
end

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("DashboardUI", { clear = true }),
  pattern = "dashboard",
  callback = hide_dashboard_ui,
})
theme_highlights.on_refresh("dashboard", hide_dashboard_ui, 10)

local header = dashboard_utils.get_header()
local center = {
  { action = "FzfLua files", desc = pad(" Find file", 34, "right"), icon = " ", key = "f" },
  { action = "FzfLua oldfiles", desc = pad(" Recent files", 34, "right"), icon = " ", key = "r" },
  { action = "FzfLua live_grep", desc = pad(" Find text", 34, "right"), icon = "󰺮 ", key = "g" },
  { action = "NvimTreeToggle", desc = pad(" File tree", 34, "right"), icon = "󰙅 ", key = "e" },
  { action = "q", desc = pad(" Quit", 34, "right"), icon = " ", key = "q" },
}
-- Dashboard serializes this function when closing its buffer. Keep it free of
-- captured locals so the cached version can run when :Dashboard reopens it.
local function footer()
  return require("utils.dashboard").footer()
end

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
