local folds = require("stable_folds")

---@type StableFoldsOptions
local options = {
  new_folds = "open",
  include_injections = true,
  max_lines = 0,
  max_bytes = 0,
  notify_errors = true,
  filter = function(buf)
    return not vim.b[buf].bigfile
  end,
}

folds.setup(options)

vim.opt.foldmethod = "expr"
vim.opt.foldexpr = folds.foldexpr
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
vim.opt.foldnestmax = 1
vim.opt.foldminlines = 4
vim.opt.foldcolumn = "2"
vim.opt.foldtext = ""
