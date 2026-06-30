local bqf = require("bqf")

bqf.setup({
  auto_enable = true,
  magic_window = true,
  auto_resize_height = true,

  preview = {
    auto_preview = true,
    border = "rounded",
    show_title = true,
    show_scroll_bar = true,
    delay_syntax = 50,
    winblend = 0,
    win_height = 15,
    win_vheight = 15,
    wrap = false,
    buf_label = true,
    should_preview_cb = function(bufnr)
      local fname = vim.api.nvim_buf_get_name(bufnr)
      return vim.fn.getfsize(fname) < 100 * 1024
    end,
  },

  func_map = {
    open = "<CR>",
    openc = "o",
    split = "<C-s>",
    vsplit = "<C-v>",
    tab = "t",
    ptoggleitem = "p",
    ptoggleauto = "P",
    pscrollup = "<C-b>",
    pscrolldown = "<C-f>",
    fzffilter = "zf",
  },
})
