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

conform.setup({
  formatters_by_ft = {
    lua = { "stylua" },
    go = { "goimports", "gofmt", stop_after_first = true },
    python = { "ruff_format", "black", stop_after_first = true },
    javascript = js_formatters,
    typescript = js_formatters,
    javascriptreact = js_formatters,
    typescriptreact = js_formatters,
    svelte = js_formatters,
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
  },

  default_format_opts = {
    lsp_format = "fallback",
    timeout_ms = 500,
  },

  format_on_save = function(bufnr)
    local ignore_filetypes = { "sql" }
    if vim.tbl_contains(ignore_filetypes, vim.bo[bufnr].filetype) then
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

vim.api.nvim_create_user_command("FormatEnable", function()
  vim.b.disable_autoformat = false
  vim.g.disable_autoformat = false
  vim.notify("Autoformat enabled", vim.log.levels.INFO)
end, { desc = "Re-enable autoformat-on-save" })
