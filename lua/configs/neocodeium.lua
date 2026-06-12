local neocodeium = require("neocodeium")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")

local config = {
  enabled = true,
  debounce = true,
  max_lines = 10000,
  silent = true,
  show_label = true,
  single_line = {
    enabled = false,
    label = "...",
  },
  filetypes = {
    help = false,
    gitcommit = false,
    gitrebase = false,
    TelescopePrompt = false,
    noice = false,
    fzf = false,
    NvimTree = false,
    mason = false,
    ["."] = false,
  },
  filter = function(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    return not vim.endswith(name, ".env")
  end,
}
neocodeium.setup(config)

-- ═══════════════════════════════════════════════════════════════
--  Global keymaps
-- ═══════════════════════════════════════════════════════════════
local function opts(desc)
  return map_opts("Neocodeium: " .. desc)
end

map("i", "<A-g>", neocodeium.accept, opts("Accept suggestion"))
map("i", "<A-w>", neocodeium.accept_word, opts("Accept word"))
map("i", "<A-l>", neocodeium.accept_line, opts("Accept line"))
map("i", "<A-j>", neocodeium.cycle_or_complete, opts("Next / complete"))
map("i", "<A-k>", function()
  neocodeium.cycle_or_complete(-1)
end, opts("Previous suggestion"))
map("i", "<A-c>", neocodeium.clear, opts("Clear suggestion"))
