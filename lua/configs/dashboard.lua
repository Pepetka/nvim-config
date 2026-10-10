local content = require("utils.dashboard")
local season = content.season(content.calendar_date())

---@type DashboardOptions
local options = {
  blocks = {
    { id = "header", type = "text", lines = content.header(season), style = "Header" },
    {
      id = "menu",
      type = "actions",
      layout = { align = "left" },
      label_width = 35,
      spacing = 1,
      items = {
        { id = "files", label = " Find file", icon = "", key = "f", run = "FzfLua files" },
        { id = "recent", label = " Recent files", icon = "", key = "r", run = "FzfLua oldfiles" },
        { id = "grep", label = " Find text", icon = "󰺮", key = "g", run = "FzfLua live_grep" },
        { id = "tree", label = " File tree", icon = "󰙅", key = "e", run = "NvimTreeToggle" },
        { id = "quit", label = " Quit", icon = "", key = "q", run = "q" },
      },
    },
    { id = "footer", type = "text", style = "Footer", lines = content.footer },
  },
  layout = { gap = 1, bottom_padding = 4 },
  highlights = function()
    local colors = require("utils.colors")
    return {
      Header = { fg = colors.palette[season and season.color or "blue"], bold = season ~= nil },
      Text = { fg = colors.muted },
      Icon = { fg = colors.muted },
      Key = { fg = colors.muted },
      Footer = { fg = colors.error },
    }
  end,
  map_opts = require("utils.map_opts"),
}

require("dashboard").setup(options)
