local scrollbar = require("scrollbar")
local theme_highlights = require("utils.theme_highlights")

theme_highlights.register("scrollbar", function(c)
  return {
    ScrollbarHandleSource = { bg = c.muted },
    ScrollbarCursorSource = { fg = c.accent },
    ScrollbarSearchSource = { fg = c.warning },
    ScrollbarErrorSource = { fg = c.error },
    ScrollbarWarnSource = { fg = c.warning },
    ScrollbarInfoSource = { fg = c.info },
    ScrollbarHintSource = { fg = c.palette.hint },
    ScrollbarMiscSource = { fg = c.palette.purple },
    ScrollbarGitAddSource = { fg = c.success },
    ScrollbarGitChangeSource = { fg = c.warning },
    ScrollbarGitDeleteSource = { fg = c.error },
  }
end)

scrollbar.setup({
  show = true,
  show_in_active_only = false,
  set_highlights = true,
  folds = 1000,
  max_lines = 10000,
  hide_if_all_visible = true,
  throttle_ms = 100,
  handle = {
    text = " ",
    blend = 30,
    highlight = "ScrollbarHandleSource",
    hide_if_all_visible = true,
  },
  marks = {
    Cursor = { text = "•", highlight = "ScrollbarCursorSource" },
    Search = { text = { "-", "=" }, highlight = "ScrollbarSearchSource" },
    Error = { text = { "-", "=" }, highlight = "ScrollbarErrorSource" },
    Warn = { text = { "-", "=" }, highlight = "ScrollbarWarnSource" },
    Info = { text = { "-", "=" }, highlight = "ScrollbarInfoSource" },
    Hint = { text = { "-", "=" }, highlight = "ScrollbarHintSource" },
    Misc = { text = { "-", "=" }, highlight = "ScrollbarMiscSource" },
    GitAdd = { text = "┆", highlight = "ScrollbarGitAddSource" },
    GitChange = { text = "┆", highlight = "ScrollbarGitChangeSource" },
    GitDelete = { text = "▁", highlight = "ScrollbarGitDeleteSource" },
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
})
