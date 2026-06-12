local todo = require("todo-comments")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")
local theme_colors = require("utils.colors")

local colors = {
  FIX = theme_colors.error,
  TODO = theme_colors.focus,
  HACK = theme_colors.warning,
  WARN = theme_colors.alert,
  PERF = theme_colors.special,
  NOTE = theme_colors.success,
  TEST = theme_colors.experimental,
  REVIEW = theme_colors.accent,
}

local config = {
  signs = true,
  sign_priority = 8,

  keywords = {
    FIX = { icon = " ", color = colors.FIX, alt = { "FIXME", "BUG", "FIXIT", "ISSUE" } },
    TODO = { icon = " ", color = colors.TODO },
    HACK = { icon = " ", color = colors.HACK },
    WARN = { icon = " ", color = colors.WARN, alt = { "WARNING", "XXX" } },
    PERF = { icon = " ", color = colors.PERF, alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" } },
    NOTE = { icon = " ", color = colors.NOTE, alt = { "INFO" } },
    TEST = { icon = "⏲ ", color = colors.TEST, alt = { "TESTING", "PASSED", "FAILED" } },
    REVIEW = { icon = " ", color = colors.REVIEW },
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
}
todo.setup(config)

-- ═══════════════════════════════════════════════════════════════
--  Global keymaps
-- ═══════════════════════════════════════════════════════════════
local function opts(desc)
  return map_opts("Todo: " .. desc)
end

map("n", "<leader>qf", "<Cmd>TodoFzfLua<CR>", opts("Find todos (fzf)"))
map("n", "<leader>qt", "<Cmd>Trouble todo toggle<CR>", opts("Find todos (Trouble)"))
