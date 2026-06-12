local toggleterm = require("toggleterm")

local config = {
  direction = "float",
  open_mapping = [[<c-f>]],
  start_in_insert = true,
  insert_mappings = true,
  terminal_mappings = true,
  close_on_exit = true,
  shell = vim.o.shell,
  float_opts = {
    border = "rounded",
    width = function()
      return math.floor(vim.o.columns * 0.7)
    end,
    height = function()
      return math.floor(vim.o.lines * 0.5)
    end,
  },
}
toggleterm.setup(config)
