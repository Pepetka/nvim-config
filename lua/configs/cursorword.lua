local cursorword = require("mini.cursorword")
local theme_highlights = require("utils.theme_highlights")

local function set_cursorword_highlights()
  local c = require("utils.colors")
  vim.api.nvim_set_hl(0, "MiniCursorword", { bg = c.gutter, underline = false })
  vim.api.nvim_set_hl(0, "MiniCursorwordCurrent", {})
end

cursorword.setup({ delay = 100 })

set_cursorword_highlights()
theme_highlights.register("cursorword", set_cursorword_highlights)

return {
  set_highlights = set_cursorword_highlights,
}
