local preview = require("livepreview.config")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")

local config = {
  port = 5500,
  browser = "default",
  dynamic_root = false,
  sync_scroll = false,
  picker = "fzf-lua",
  address = "127.0.0.1",
}
preview.set(config)

-- ═══════════════════════════════════════════════════════════════
--  Global keymaps
-- ═══════════════════════════════════════════════════════════════
local function opts(desc)
  return map_opts("General: " .. desc)
end

map("n", "<leader>mp", "<Cmd>LivePreview start<CR>", opts("Start preview"))
map("n", "<leader>mP", "<Cmd>LivePreview close<CR>", opts("Close preview"))
map("n", "<leader>mf", "<Cmd>LivePreview pick<CR>", opts("Pick file to preview"))
