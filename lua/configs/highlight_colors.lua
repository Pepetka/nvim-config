local highlight_colors = require("nvim-highlight-colors")

local config = {
  render = "background",

  virtual_symbol = "■",
  virtual_symbol_prefix = "",
  virtual_symbol_suffix = " ",
  virtual_symbol_position = "inline",

  enable_hex = true,
  enable_short_hex = true,
  enable_rgb = true,
  enable_hsl = true,
  enable_hsl_without_function = true,
  enable_var_usage = true,
  enable_named_colors = true,
  enable_tailwind = false,

  enable_ansi = false,
  enable_xterm256 = false,
  enable_xtermTrueColor = false,

  exclude_filetypes = {
    "noice",
    "prompt",
    "fzf",
    "NvimTree",
    "mason",
    "blink-cmp-menu",
  },

  exclude_buftypes = {
    "terminal",
  },

  exclude_buffer = function(bufnr)
    return vim.fn.getfsize(vim.api.nvim_buf_get_name(bufnr)) > 1000000
  end,
}
highlight_colors.setup(config)
