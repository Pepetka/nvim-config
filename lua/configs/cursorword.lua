local cursorword = require("mini.cursorword")
local theme_highlights = require("utils.theme_highlights")

cursorword.setup({ delay = 100 })
theme_highlights.register("cursorword", function(c)
  return {
    MiniCursorword = { bg = c.gutter, underline = false },
    MiniCursorwordCurrent = {},
  }
end)
