local bufferline = require("bufferline")

local config = {
  highlights = {
    fill = { bg = "none" },
    background = { bg = "none" },
    buffer_selected = { bg = "none", bold = true, italic = false },
    buffer_visible = { bg = "none" },
    separator = { bg = "none" },
    separator_selected = { bg = "none" },
    separator_visible = { bg = "none" },
    modified = { bg = "none" },
    modified_selected = { bg = "none" },
    modified_visible = { bg = "none" },
    indicator_selected = { bg = "none" },
    indicator_visible = { bg = "none" },
  },
  options = {
    mode = "buffers",
    numbers = "none",
    left_mouse_command = "buffer %d",
    middle_mouse_command = nil,
    indicator = { style = "icon", icon = "▎" },
    modified_icon = "●",
    left_trunc_marker = "",
    right_trunc_marker = "",
    max_name_length = 18,
    max_prefix_length = 15,
    tab_size = 18,
    offsets = {
      {
        filetype = "NvimTree",
        text = "",
        highlight = "Directory",
        text_align = "left",
        separator = true,
      },
      {
        filetype = "nvim-undotree",
        text = "Undo tree",
        highlight = "Directory",
        text_align = "left",
        separator = true,
      },
    },
    color_icons = true,
    show_buffer_icons = true,
    show_buffer_close_icons = false,
    show_close_icon = false,
    show_tab_indicators = true,
    separator_style = "thin",
    enforce_regular_tabs = false,
    always_show_bufferline = false,
    sort_by = "id",
    custom_filter = function(buf_number)
      local excluded = { "terminal", "qf", "help", "prompt" }
      for _, ft in ipairs(excluded) do
        if vim.bo[buf_number].filetype == ft then
          return false
        end
      end
      return true
    end,
  },
}
bufferline.setup(config)
