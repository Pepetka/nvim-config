local dv = require("dap-view")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")

dv.setup({
  winbar = {
    show = true,
    sections = { "watches", "scopes", "exceptions", "breakpoints", "threads", "repl", "console" },
    default_section = "scopes",
    show_keymap_hints = true,
  },
  windows = {
    size = 0.25,
    position = "below",
    terminal = {
      size = 0.5,
      position = "left",
    },
  },
  virtual_text = {
    enabled = true,
    position = "inline",
  },
  auto_toggle = true,
  follow_tab = false,
  switchbuf = "usetab,uselast",
})

local function opts(desc)
  return map_opts("DAP: " .. desc, { noremap = false })
end

map("n", "<leader>dv", function()
  dv.toggle()
end, opts("Toggle dap-view"))

map("n", "<leader>dw", function()
  dv.add_expr()
end, opts("Add watch expression"))
