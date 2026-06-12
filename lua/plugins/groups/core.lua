local add = vim.pack.add

add({
  "https://github.com/nvim-treesitter/nvim-treesitter",
  "https://github.com/mason-org/mason.nvim",
  "https://github.com/mason-org/mason-lspconfig.nvim",
  { src = "https://github.com/saghen/blink.cmp", version = vim.version.range("^1") },
  "https://github.com/stevearc/conform.nvim",
  "https://github.com/mfussenegger/nvim-lint",
})

require("configs.treesitter")
require("configs.mason")
require("configs.lsp")
require("configs.blink_cmp")
require("configs.conform")
require("configs.lint")
