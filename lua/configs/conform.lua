local conform = require("conform")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")
local oxc = require("utils.oxc_config")

local function js_formatters(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local has_oxfmt = oxc.has_oxfmt_config(bufnr)
  local has_oxlint = oxc.has_oxlint_config(bufname)

  if has_oxfmt and has_oxlint then
    return { "oxlint", "oxfmt" }
  end
  if has_oxfmt then
    return { "eslint_d", "oxfmt" }
  end
  if has_oxlint then
    return { "oxlint", "prettierd" }
  end
  return { "eslint_d", "prettierd" }
end

local function prettier_formatter(bufnr)
  return oxc.has_oxfmt_config(bufnr) and { "oxfmt" } or { "prettierd" }
end

local formatters_by_ft = {
  lua = { "stylua" },
  go = { "goimports", "gofumpt" },
  python = { "ruff_format", "black", stop_after_first = true },
  css = prettier_formatter,
  scss = prettier_formatter,
  html = prettier_formatter,
  json = function(bufnr)
    return oxc.has_oxfmt_config(bufnr) and { "oxfmt" } or { "jq", "prettierd", stop_after_first = true }
  end,
  jsonc = prettier_formatter,
  yaml = prettier_formatter,
  markdown = prettier_formatter,
  sh = { "shfmt" },
  bash = { "shfmt" },
  zsh = { "shfmt" },
  ["_"] = { "trim_whitespace" },
}
for _, ft in ipairs(oxc.js_filetypes) do
  formatters_by_ft[ft] = js_formatters
end

conform.setup({
  formatters_by_ft = formatters_by_ft,

  default_format_opts = {
    lsp_format = "fallback",
    timeout_ms = 500,
  },

  format_on_save = function(bufnr)
    if vim.b[bufnr].bigfile then
      return
    end
    if vim.bo[bufnr].filetype == "sql" then
      return
    end
    if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
      return
    end
    return { timeout_ms = 500, lsp_format = "fallback" }
  end,

  formatters = {
    shfmt = {
      prepend_args = { "-i", "2" },
    },
  },

  notify_on_error = true,
  notify_no_formatters = false,
})

vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"

map({ "n", "v" }, "<leader>lf", function()
  conform.format({ async = true })
end, map_opts("Edit: Format buffer"))

vim.api.nvim_create_user_command("FormatDisable", function(opts)
  if opts.bang then
    vim.b.disable_autoformat = true
  else
    vim.g.disable_autoformat = true
  end
  vim.notify("Autoformat disabled" .. (opts.bang and " (buffer)" or " (global)"), vim.log.levels.WARN)
end, { desc = "Disable autoformat-on-save", bang = true })

vim.api.nvim_create_user_command("FormatEnable", function(opts)
  if opts.bang then
    vim.b.disable_autoformat = false
  else
    vim.g.disable_autoformat = false
  end
  vim.notify("Autoformat enabled" .. (opts.bang and " (buffer)" or " (global)"), vim.log.levels.INFO)
end, { desc = "Re-enable autoformat-on-save", bang = true })

vim.api.nvim_create_user_command("FormatStatus", function()
  local bufnr = vim.api.nvim_get_current_buf()
  local reason
  if vim.b[bufnr].bigfile then
    reason = "big file"
  elseif vim.bo[bufnr].filetype == "sql" then
    reason = "SQL buffer"
  elseif vim.g.disable_autoformat then
    reason = "disabled globally"
  elseif vim.b[bufnr].disable_autoformat then
    reason = "disabled for this buffer"
  end

  local configured = {}
  for _, name in ipairs(conform.list_formatters_for_buffer(bufnr)) do
    local info = conform.get_formatter_info(name, bufnr)
    configured[#configured + 1] = name
      .. (info.available and "" or " (unavailable: " .. (info.available_msg or "unknown") .. ")")
  end
  local active, lsp = conform.list_formatters_to_run(bufnr)
  local names = vim.tbl_map(function(info)
    return info.name
  end, active)
  if lsp then
    names[#names + 1] = "LSP"
  end

  vim.notify(
    string.format(
      "Autoformat: %s\nConfigured: %s\nAvailable for this buffer: %s",
      reason or "enabled",
      #configured > 0 and table.concat(configured, ", ") or "none",
      #names > 0 and table.concat(names, ", ") or "none"
    ),
    vim.log.levels.INFO
  )
end, { desc = "Show formatting status for the current buffer" })

map("n", "<leader>lF", "<cmd>FormatStatus<cr>", map_opts("Edit: Show formatting status"))
