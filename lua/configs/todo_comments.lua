local todo = require("todo-comments")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")
local theme_highlights = require("utils.theme_highlights")

theme_highlights.register("todo_comments", function(c)
  return {
    TodoColorError = { fg = c.error },
    TodoColorWarning = { fg = c.warning },
    TodoColorAlert = { fg = c.alert },
    TodoColorFocus = { fg = c.focus },
    TodoColorSpecial = { fg = c.special },
    TodoColorSuccess = { fg = c.success },
    TodoColorAccent = { fg = c.accent },
    TodoColorTest = { fg = c.test },
    TodoColorDefault = { fg = c.fg },
  }
end)

todo.setup({
  signs = true,
  sign_priority = 8,

  keywords = {
    FIX = { icon = " ", color = "error", alt = { "FIXME", "BUG", "FIXIT", "ISSUE" } },
    TODO = { icon = " ", color = "focus" },
    HACK = { icon = " ", color = "warning" },
    WARN = { icon = " ", color = "alert", alt = { "WARNING", "XXX" } },
    PERF = { icon = " ", color = "special", alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" } },
    NOTE = { icon = " ", color = "success", alt = { "INFO" } },
    TEST = { icon = "⏲ ", color = "test", alt = { "TESTING", "PASSED", "FAILED" } },
    REVIEW = { icon = " ", color = "accent" },
  },

  colors = {
    error = { "TodoColorError" },
    warning = { "TodoColorWarning" },
    alert = { "TodoColorAlert" },
    focus = { "TodoColorFocus" },
    special = { "TodoColorSpecial" },
    success = { "TodoColorSuccess" },
    accent = { "TodoColorAccent" },
    test = { "TodoColorTest" },
    default = { "TodoColorDefault" },
  },

  gui_style = {
    fg = "NONE",
    bg = "BOLD",
  },

  merge_keywords = true,

  highlight = {
    multiline = true,
    multiline_pattern = "^.",
    multiline_context = 10,
    before = "",
    keyword = "bg",
    after = "",
    pattern = [[.*<(KEYWORDS)\s*:]],
    comments_only = true,
    max_line_len = 400,
    exclude = {
      "help",
      "noice",
      "prompt",
      "fzf",
      "NvimTree",
      "mason",
    },
  },

  search = {
    command = "rg",
    args = {
      "--color=never",
      "--no-heading",
      "--with-filename",
      "--line-number",
      "--column",
    },
    pattern = [[\b(KEYWORDS):]],
  },
})

-- ═══════════════════════════════════════════════════════════════
--  Global keymaps
-- ═══════════════════════════════════════════════════════════════
local function opts(desc)
  return map_opts("FZF: " .. desc)
end

map("n", "<leader>qf", "<Cmd>TodoFzfLua<CR>", opts("Find todos"))
map("n", "<leader>qt", "<Cmd>Trouble todo toggle<CR>", opts("Find todos (Trouble)"))
