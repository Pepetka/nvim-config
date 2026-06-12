local mason = require("mason")
local mason_lsp = require("mason-lspconfig")

local mason_config = {
  ui = {
    border = "rounded",
    icons = {
      package_installed = "✓",
      package_pending = "➜",
      package_uninstalled = "✗",
    },
  },
}
mason.setup(mason_config)

local mason_lsp_config = {
  ensure_installed = {
    "html",
    "vtsls",
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
  automatic_enable = true,
}
mason_lsp.setup(mason_lsp_config)
