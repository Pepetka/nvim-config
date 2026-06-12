local colors = require("utils.colors")
local cursorword = require("mini.cursorword")

local config = {
  delay = 100,
}
cursorword.setup(config)

vim.api.nvim_set_hl(0, "MiniCursorword", { bg = colors.gutter, underline = false })
vim.api.nvim_set_hl(0, "MiniCursorwordCurrent", {})
