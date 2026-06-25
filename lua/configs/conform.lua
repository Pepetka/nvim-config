local conform = require("conform")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")

local config = {
  formatters_by_ft = {
    lua = { "stylua" },
    go = { "goimports", "gofmt", stop_after_first = true },
    python = { "ruff_format", "black", stop_after_first = true },
    javascript = { "eslint_d", "prettierd", stop_after_first = false },
    typescript = { "eslint_d", "prettierd", stop_after_first = false },
    javascriptreact = { "eslint_d", "prettierd", stop_after_first = false },
    typescriptreact = { "eslint_d", "prettierd", stop_after_first = false },
    svelte = { "eslint_d", "prettierd", stop_after_first = false },
    css = { "prettierd" },
    scss = { "prettierd" },
    html = { "prettierd" },
    json = { "jq", "prettierd", stop_after_first = true },
    jsonc = { "prettierd" },
    yaml = { "prettierd" },
    markdown = { "prettierd" },
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
    prettierd = {
      condition = function(_, ctx)
        return vim.fs.find({
          ".prettierrc",
          ".prettierrc.json",
          ".prettierrc.yaml",
          ".prettierrc.yml",
          ".prettierrc.js",
          ".prettierrc.cjs",
          ".prettierrc.mjs",
          "prettier.config.js",
          "prettier.config.cjs",
          "prettier.config.mjs",
        }, { path = ctx.filename, upward = true })[1]
      end,
    },
    prettier = {
      condition = function(_, ctx)
        return vim.fs.find({
          ".prettierrc",
          ".prettierrc.json",
          ".prettierrc.yaml",
          ".prettierrc.yml",
          ".prettierrc.js",
          ".prettierrc.cjs",
          ".prettierrc.mjs",
          "prettier.config.js",
          "prettier.config.cjs",
          "prettier.config.mjs",
        }, { path = ctx.filename, upward = true })[1]
      end,
    },
    shfmt = {
      prepend_args = { "-i", "2" },
    },
  },

  notify_on_error = true,
  notify_no_formatters = false,
}
conform.setup(config)

vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"

-- ═══════════════════════════════════════════════════════════════
--  Keymaps
-- ═══════════════════════════════════════════════════════════════
map({ "n", "v" }, "<leader>lf", function()
  conform.format({ async = true })
end, map_opts("Edit: Format buffer"))

-- ═══════════════════════════════════════════════════════════════
--  User commands
-- ═══════════════════════════════════════════════════════════════
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
