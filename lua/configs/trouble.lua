local trouble = require("trouble")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")

trouble.setup({
  auto_close = false,
  auto_open = false,
  auto_preview = true,
  auto_refresh = true,
  focus = true,
  follow = true,
  indent_guides = true,
  max_items = 200,
  multiline = true,
  pinned = false,
  warn_no_results = true,

  win = {
    type = "split",
    position = "bottom",
    height = 12,
  },

  preview = {
    type = "main",
    scratch = true,
  },

  modes = {
    diagnostics_buffer = {
      mode = "diagnostics",
      filter = { buf = 0 },
    },
  },

  keys = {
    ["?"] = "help",
    q = "close",
    o = "jump_close",
    ["<cr>"] = "jump",
    ["<c-s>"] = "jump_split",
    ["<c-v>"] = "jump_vsplit",
    ["}"] = "next",
    ["{"] = "prev",
    dd = "delete",
    p = "preview",
    P = "toggle_preview",
  },
})

local function opts(desc)
  return map_opts("Trouble: " .. desc)
end

map("n", "<leader>qd", "<Cmd>Trouble diagnostics_buffer toggle<CR>", opts("Buffer diagnostics"))
map("n", "<leader>qx", "<Cmd>Trouble diagnostics toggle<CR>", opts("Diagnostics"))
map("n", "<leader>qs", "<Cmd>Trouble symbols toggle focus=false<CR>", opts("Symbols"))
map("n", "<leader>ql", "<Cmd>Trouble lsp toggle focus=false win.position=right<CR>", opts("LSP"))
map("n", "<leader>qq", "<Cmd>Trouble qflist toggle<CR>", opts("Quickfix"))
map("n", "<leader>qL", "<Cmd>Trouble loclist toggle<CR>", opts("Location list"))
