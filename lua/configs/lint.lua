local lint = require("lint")
local oxc = require("utils.oxc_config")

local js_family = {
  javascript = true,
  typescript = true,
  javascriptreact = true,
  typescriptreact = true,
  svelte = true,
}

lint.linters_by_ft = {
  javascript = { "eslint_d" },
  typescript = { "eslint_d" },
  javascriptreact = { "eslint_d" },
  typescriptreact = { "eslint_d" },
  svelte = { "eslint_d" },
  python = { "ruff" },
  markdown = { "markdownlint" },
  sh = { "shellcheck" },
  bash = { "shellcheck" },
  zsh = { "shellcheck" },
}

vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "FileType", "InsertLeave", "TextChanged" }, {
  group = vim.api.nvim_create_augroup("NvimLint", { clear = true }),
  callback = function(args)
    local bufname = vim.api.nvim_buf_get_name(args.buf)
    if bufname:match("/node_modules/") then
      return
    end

    local ft = vim.bo[args.buf].filetype
    if ft == "" then
      return
    end
    if js_family[ft] then
      local linters = oxc.has_oxlint_config(bufname) and { "oxlint" } or { "eslint_d" }
      lint.try_lint(linters)
    else
      lint.try_lint()
    end
  end,
})
