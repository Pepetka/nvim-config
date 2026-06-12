local better_escape = require("better_escape")

local config = {
  timeout = 200,
  mappings = {
    i = {
      j = { k = "<Esc>", j = "<Esc>" },
      k = { j = "<Esc>" },
    },
    c = {
      j = { k = "<C-c>", j = "<C-c>" },
    },
    t = {
      j = { k = "<C-\\><C-n>" },
    },
    v = {
      j = { k = "<Esc>" },
    },
    s = {
      j = { k = "<Esc>" },
    },
  },
}
better_escape.setup(config)
