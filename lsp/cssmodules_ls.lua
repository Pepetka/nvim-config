local config = {
  cmd = { "cssmodules-language-server" },
  filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
  root_markers = { "package.json" },
  init_options = {
    camelCase = "dashes",
  },
}

return config
