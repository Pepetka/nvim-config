vim.loader.enable()

local start_time = vim.uv.hrtime()

require("options")
require("mappings")
require("core")
require("plugins")

_G.nvim_startup_ms = (vim.uv.hrtime() - start_time) / 1e6
