local folds = require("stable_folds")

folds.setup({
  filter = function(buf)
    return not vim.b[buf].bigfile
  end,
})

vim.opt.foldmethod = "expr"
vim.opt.foldexpr = folds.foldexpr
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
vim.opt.foldnestmax = 1
vim.opt.foldminlines = 4
vim.opt.foldcolumn = "2"
vim.opt.foldtext = ""
