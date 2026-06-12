local diffview = require("diffview")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")

local config = {
  use_icons = true,
  watch_index = true,

  view = {
    default = {
      layout = "diff2_horizontal",
      disable_diagnostics = false,
      winbar_info = false,
    },
    merge_tool = {
      layout = "diff3_horizontal",
      disable_diagnostics = true,
      winbar_info = true,
    },
    file_history = {
      layout = "diff2_horizontal",
      disable_diagnostics = false,
      winbar_info = false,
    },
  },

  file_panel = {
    listing_style = "tree",
    tree_options = {
      flatten_dirs = true,
      folder_statuses = "only_folded",
    },
    win_config = {
      position = "left",
      width = 35,
    },
  },

  file_history_panel = {
    win_config = {
      position = "bottom",
      height = 16,
    },
  },

  keymaps = {
    disable_defaults = false,
    view = {
      { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Diffview: Close" } },
    },
    file_panel = {
      { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Diffview: Close" } },
    },
    file_history_panel = {
      { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Diffview: Close" } },
    },
  },
}

diffview.setup(config)

-- ═══════════════════════════════════════════════════════════════
--  Global keymaps
-- ═══════════════════════════════════════════════════════════════
local function opts(desc)
  return map_opts("Diffview: " .. desc)
end

map("n", "<leader>go", "<cmd>DiffviewOpen<cr>", opts("Open"))
