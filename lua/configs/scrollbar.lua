local scrollbar = require("scrollbar")
local theme_highlights = require("utils.theme_highlights")

theme_highlights.register("scrollbar", function(c)
  return {
    ScrollbarThumb = { bg = c.muted, blend = 30 },
    ScrollbarCursor = { fg = c.accent },
    ScrollbarSearch = { fg = c.warning },
    ScrollbarError = { fg = c.error },
    ScrollbarWarn = { fg = c.warning },
    ScrollbarInfo = { fg = c.info },
    ScrollbarHint = { fg = c.palette.hint },
    ScrollbarMisc = { fg = c.palette.purple },
    ScrollbarGitAdd = { fg = c.success },
    ScrollbarGitChange = { fg = c.warning },
    ScrollbarGitDelete = { fg = c.error },
  }
end)

scrollbar.setup({
  set_highlights = true,
  scrollbar = {
    show = true,
    visibility = "all",
    unit = "screenline",
    max_lines = 10000,
    hide_if_all_visible = true,
    throttle_ms = 100,
    layout = { columns = { { "thumb", "marks" } } },
    thumb = {
      text = " ",
      blend = 30,
      hide_if_all_visible = true,
    },
  },
  marks = {
    Cursor = { text = "•" },
    Search = { text = { "-", "=" } },
    Error = { text = { "-", "=" } },
    Warn = { text = { "-", "=" } },
    Info = { text = { "-", "=" } },
    Hint = { text = { "-", "=" } },
    Misc = { text = { "-", "=" } },
    GitAdd = { text = "┆" },
    GitChange = { text = "┆" },
    GitDelete = { text = "▁" },
  },
  exclude = {
    filetypes = {
      prompt = true,
      TelescopePrompt = true,
      noice = true,
      NvimTree = true,
    },
  },
  providers = {
    cursor = true,
    diagnostic = true,
    gitsigns = true,
    search = true,
    marks = false,
    ale = false,
  },
})

-- v2 b39443d misses fold commands and fold-column clicks: https://github.com/petertriho/nvim-scrollbar/pull/117
local left_mouse = vim.keycode("<LeftMouse>")
local fold_prefix = false
vim.on_key(function(key)
  local win
  if fold_prefix and key:find("^[aAcCoOmMrRxXvniNdDE]$") then
    win = vim.api.nvim_get_current_win()
  elseif key == left_mouse then
    local mouse = vim.fn.getmousepos()
    local info = vim.fn.getwininfo(mouse.winid)[1]
    if info and mouse.wincol <= info.textoff then
      win = mouse.winid
    end
  end
  fold_prefix = not fold_prefix and key == "z" and vim.api.nvim_get_mode().mode == "n"
  if win then
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(win) then
        require("scrollbar.layout").clear_screen_cache(win)
        require("scrollbar.scheduler").invalidate_window(win)
      end
    end)
  end
end, vim.api.nvim_create_namespace("ScrollbarFolds"))
