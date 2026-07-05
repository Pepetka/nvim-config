local M = {}

M.oxfmt_configs = {
  ".oxfmtrc.json",
  ".oxfmtrc.jsonc",
  "oxfmt.config.ts",
  "oxfmt.config.js",
  "oxfmt.config.mjs",
  "oxfmt.config.cjs",
}

M.oxlint_configs = {
  ".oxlintrc.json",
  "oxlint.config.ts",
  "oxlint.config.js",
  "oxlint.config.mjs",
  "oxlint.config.cjs",
}

function M.has_oxfmt_config(bufnr)
  return vim.fs.find(M.oxfmt_configs, { path = vim.api.nvim_buf_get_name(bufnr), upward = true })[1] ~= nil
end

function M.has_oxlint_config(bufname)
  return vim.fs.find(M.oxlint_configs, { path = bufname, upward = true })[1] ~= nil
end

return M
