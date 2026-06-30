local add = vim.pack.add

add({
  "https://github.com/nvim-tree/nvim-tree.lua",
  "https://github.com/ibhagwan/fzf-lua",
  "https://codeberg.org/andyg/leap.nvim",
  "https://github.com/christoomey/vim-tmux-navigator",
  "https://github.com/lewis6991/gitsigns.nvim",
  "https://github.com/dlyongemallo/diffview-plus.nvim",
  "https://github.com/akinsho/toggleterm.nvim",
  "https://github.com/folke/trouble.nvim",
  "https://github.com/rachartier/tiny-inline-diagnostic.nvim",
  "https://github.com/kevinhwang91/nvim-bqf",
  "https://github.com/kevinhwang91/nvim-hlslens",
  "https://github.com/folke/todo-comments.nvim",
  "https://github.com/max397574/better-escape.nvim",
  "https://github.com/nvim-mini/mini.ai",
  "https://github.com/nvim-mini/mini.pairs",
  "https://github.com/kylechui/nvim-surround",
  "https://github.com/windwp/nvim-ts-autotag",
  "https://github.com/folke/ts-comments.nvim",
  "https://github.com/nvim-mini/mini.cursorword",
  -- "https://github.com/milanglacier/minuet-ai.nvim",
  -- "https://github.com/monkoose/neocodeium",
  "https://github.com/Exafunction/windsurf.nvim",
  "https://github.com/tiagovla/scope.nvim",
  "https://github.com/mfussenegger/nvim-dap",
  { src = "https://github.com/igorlfs/nvim-dap-view", version = vim.version.range("1.*") },
})

require("configs.tree")
require("configs.fzf_lua")
require("configs.leap")
require("configs.gitsigns")
require("configs.diffview")
require("configs.toggleterm")
require("configs.trouble")
require("configs.tiny_inline_diagnostic")
require("configs.bqf")
require("configs.hlslens")
require("configs.todo_comments")
require("configs.better_escape")
require("configs.pairs")
require("configs.surround")
require("configs.autotag")
require("configs.ts_comments")
require("configs.cursorword")
require("configs.ai")
-- require("configs.minuet")
-- require("configs.neocodeium")
require("configs.windsurf")
require("configs.scope")
require("configs.dap")
require("configs.dap_view")
