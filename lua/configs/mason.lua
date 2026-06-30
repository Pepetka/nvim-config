local mason = require("mason")
local mason_lsp = require("mason-lspconfig")

local ts_lsp = vim.g.ts_lsp or "vtsls"

mason.setup({
  ui = {
    border = "rounded",
    icons = {
      package_installed = "✓",
      package_pending = "➜",
      package_uninstalled = "✗",
    },
  },
})

mason_lsp.setup({
  ensure_installed = {
    "html",
    ts_lsp,
    "gopls",
    "cssls",
    "jsonls",
    "lua_ls",
    "svelte",
    "prismals",
    "tailwindcss",
    "cssmodules_ls",
    "css_variables",
  },
  automatic_enable = {
    exclude = ts_lsp == "vtsls" and { "tsgo" } or { "vtsls" },
  },
})
