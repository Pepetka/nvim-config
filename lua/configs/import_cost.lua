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

-- Fix race condition: import-cost may try to set extmark in a buffer that no longer exists.
local job = require("import-cost.job")
local orig_render_extmark = job.render_extmark

job.render_extmark = function(bufnr, data, extmark_id)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return 0
  end
  return orig_render_extmark(bufnr, data, extmark_id)
end
