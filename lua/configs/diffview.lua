local diffview = require("diffview")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")
local tab_buffers = require("tab_buffers.integrations.diffview")

diffview.setup({
  use_icons = true,
  watch_index = true,
  hooks = tab_buffers.hooks(),

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
      { "n", "gf", tab_buffers.goto_file, map_opts("Git: Open file in previous ordinary tab") },
      { "n", "<C-w>gf", tab_buffers.goto_file_tab, map_opts("Git: Open file in new tab") },
      { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Git: Close diffview" } },
    },
    file_panel = {
      { "n", "gf", tab_buffers.goto_file, map_opts("Git: Open file in previous ordinary tab") },
      { "n", "<C-w>gf", tab_buffers.goto_file_tab, map_opts("Git: Open file in new tab") },
      { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Git: Close diffview" } },
    },
    file_history_panel = {
      { "n", "gf", tab_buffers.goto_file, map_opts("Git: Open file in previous ordinary tab") },
      { "n", "<C-w>gf", tab_buffers.goto_file_tab, map_opts("Git: Open file in new tab") },
      { "n", "q", "<cmd>DiffviewClose<cr>", { desc = "Git: Close diffview" } },
    },
  },
})

local function opts(desc)
  return map_opts("Git: " .. desc)
end

map("n", "<leader>go", "<cmd>DiffviewOpen<cr>", opts("Open diffview"))
