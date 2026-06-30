local map = vim.keymap.set
local map_opts = require("utils.map_opts")
local diagnostic = require("tiny-inline-diagnostic")

diagnostic.setup({
  preset = "modern",
  transparent_cursorline = true,

  options = {
    show_code = true,

    show_source = {
      enabled = false,
      if_many = true,
    },

    add_messages = {
      messages = true,
      display_count = false,
      show_multiple_glyphs = true,
    },

    multilines = {
      enabled = true,
      always_show = false,
    },

    show_related = {
      enabled = true,
      max_count = 3,
    },

    overflow = {
      mode = "wrap",
      padding = 0,
    },

    enable_on_insert = false,
    enable_on_select = false,
    throttle = 20,

    virt_texts = {
      priority = 2048,
    },
  },
})

vim.diagnostic.config({ virtual_text = false })

local function opts(desc)
  return map_opts("Inline diagnostic: " .. desc)
end

map("n", "<leader>id", "<cmd>TinyInlineDiag toggle<cr>", opts("Toggle inline diagnostics"))
map("n", "<leader>ic", "<cmd>TinyInlineDiag toggle_cursor_only<cr>", opts("Toggle cursor-only diagnostics"))
map(
  "n",
  "<leader>ia",
  "<cmd>TinyInlineDiag toggle_all_diags_on_cursorline<cr>",
  opts("Toggle all diagnostics on cursor line")
)
map("n", "<leader>ir", "<cmd>TinyInlineDiag reset<cr>", opts("Reset diagnostic display options"))
