local config = {
  package_manager = "npm",
  filetypes = {
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
    "svelte",
  },
  format = {
    byte_format = "%.1fb",
    kb_format = "%.1fk",
    virtual_text = "%s (gzipped: %s)",
  },
  highlight = "Comment",
}
vim.g.import_cost = config
