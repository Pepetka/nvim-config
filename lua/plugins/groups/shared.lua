local add = vim.pack.add

add({
  "https://github.com/nvim-tree/nvim-web-devicons",
  "https://github.com/nvim-lua/plenary.nvim",
  "https://github.com/MunifTanjim/nui.nvim",
  "https://github.com/rafamadriz/friendly-snippets",
  "https://github.com/folke/tokyonight.nvim",
  "https://github.com/folke/lazydev.nvim",
})

require("configs.lazydev")
require("configs.theme")
