local ts = require("nvim-treesitter")
local api = vim.api

local parsers = {
  "bash",
  "c",
  "css",
  "go",
  "html",
  "javascript",
  "json",
  "lua",
  "markdown",
  "markdown_inline",
  "prisma",
  "python",
  "regex",
  "rust",
  "styled",
  "svelte",
  "toml",
  "tsx",
  "typescript",
  "vim",
  "xml",
  "vimdoc",
  "yaml",
}

local ts_config = {
  install_dir = vim.fn.stdpath("data") .. "/site",
}
ts.setup(ts_config)

ts.install(parsers)

local ts_filetypes = {
  "bash",
  "c",
  "css",
  "go",
  "html",
  "javascript",
  "javascriptreact",
  "json",
  "lua",
  "markdown",
  "prisma",
  "python",
  "rust",
  "sh",
  "styled",
  "svelte",
  "toml",
  "typescript",
  "typescriptreact",
  "vim",
  "yaml",
  "zsh",
}

api.nvim_create_autocmd("FileType", {
  group = api.nvim_create_augroup("TreesitterSetup", { clear = true }),
  pattern = ts_filetypes,
  callback = function(args)
    if vim.bo[args.buf].buftype ~= "" or vim.b[args.buf].bigfile then
      return
    end

    local lang = vim.treesitter.language.get_lang(args.match) or args.match

    if not vim.treesitter.language.add(lang) then
      return
    end

    vim.treesitter.start(args.buf, lang)

    require("stable_folds").attach()
    vim.wo[0][0].foldminlines = 4
  end,
})

vim.treesitter.language.register("bash", { "sh", "zsh" })
vim.treesitter.language.register("tsx", { "typescriptreact" })
