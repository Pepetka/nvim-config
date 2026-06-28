local scrollbar = require("scrollbar")
local theme_highlights = require("utils.theme_highlights")

local function set_scrollbar_highlights()
  local c = require("utils.colors")
  vim.api.nvim_set_hl(0, "ScrollbarHandleSource", { bg = c.muted })
  vim.api.nvim_set_hl(0, "ScrollbarCursorSource", { fg = c.accent })
  vim.api.nvim_set_hl(0, "ScrollbarSearchSource", { fg = c.warning })
  vim.api.nvim_set_hl(0, "ScrollbarErrorSource", { fg = c.error })
  vim.api.nvim_set_hl(0, "ScrollbarWarnSource", { fg = c.warning })
  vim.api.nvim_set_hl(0, "ScrollbarInfoSource", { fg = c.info })
  vim.api.nvim_set_hl(0, "ScrollbarHintSource", { fg = c.palette.hint })
  vim.api.nvim_set_hl(0, "ScrollbarMiscSource", { fg = c.palette.purple })
  vim.api.nvim_set_hl(0, "ScrollbarGitAddSource", { fg = c.success })
  vim.api.nvim_set_hl(0, "ScrollbarGitChangeSource", { fg = c.warning })
  vim.api.nvim_set_hl(0, "ScrollbarGitDeleteSource", { fg = c.error })
end

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
}

set_scrollbar_highlights()
scrollbar.setup(config)
theme_highlights.register("scrollbar", set_scrollbar_highlights)

return {
  set_highlights = set_scrollbar_highlights,
}
