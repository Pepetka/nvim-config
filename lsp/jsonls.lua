local config = {
  cmd = { "vscode-json-language-server", "--stdio" },
  filetypes = { "json", "jsonc" },
  root_markers = { "package.json", ".git" },
  init_options = {
    provideFormatter = true,
  },
  settings = {
    json = {
      validate = { enable = true },
      format = { enable = true },
      schemaDownload = { enable = true },
      colorDecorators = { enable = true },
      maxItemsComputed = 5000,
    },
  },
}

return config
