local add = vim.pack.add

add({
  "https://github.com/nvim-lualine/lualine.nvim",
  "https://github.com/akinsho/bufferline.nvim",
  "https://github.com/nvimdev/dashboard-nvim",
  "https://github.com/brenoprata10/nvim-highlight-colors",
  "https://github.com/folke/noice.nvim",
  "https://github.com/petertriho/nvim-scrollbar",
  "https://github.com/folke/snacks.nvim",
})

require("configs.noice")
require("configs.snacks")
require("configs.lualine")
require("configs.bufferline")
require("configs.highlight_colors")
require("configs.dashboard")
require("configs.scrollbar")
require("configs.cheatsheet")
