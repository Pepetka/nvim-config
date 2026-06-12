local scrollbar = require("scrollbar")
local colors = require("utils.colors")

local config = {
  show = true,
  show_in_active_only = false,
  set_highlights = true,
  folds = 1000,
  max_lines = 10000,
  hide_if_all_visible = true,
  throttle_ms = 100,
  handle = {
    text = " ",
    color = colors.surface,
    blend = 30,
    highlight = "CursorColumn",
    hide_if_all_visible = true,
  },
  marks = {
    Cursor = { text = "•", color = colors.accent },
    Search = { text = { "-", "=" }, color = colors.warning },
    Error = { text = { "-", "=" }, color = colors.error },
    Warn = { text = { "-", "=" }, color = colors.warning },
    Info = { text = { "-", "=" }, color = colors.info },
    Hint = { text = { "-", "=" }, color = colors.palette.hint },
    Misc = { text = { "-", "=" }, color = colors.palette.purple },
    GitAdd = { text = "┆", color = colors.success },
    GitChange = { text = "┆", color = colors.warning },
    GitDelete = { text = "▁", color = colors.error },
  },
  excluded_filetypes = {
    "prompt",
    "TelescopePrompt",
    "noice",
    "NvimTree",
  },
  handlers = {
    cursor = true,
    diagnostic = true,
    gitsigns = true,
    handle = true,
    search = true,
    ale = false,
  },
}
scrollbar.setup(config)
