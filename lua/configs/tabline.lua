require("tab_buffers.tabline").setup({
  highlights = function()
    local colors = require("utils.colors")
    return {
      Buffer = { fg = colors.palette.fg_dark or colors.fg },
      Visible = { fg = colors.fg },
      Active = { fg = colors.accent },
      Tab = { fg = colors.palette.fg_dark or colors.fg },
      TabActive = { fg = colors.focus },
      Border = { fg = colors.palette.fg_dark or colors.fg },
      ActiveBorder = { fg = colors.error },
      Overflow = { fg = colors.warning },
    }
  end,
  icons = true,
  max_name_length = 30,
  padding = 2,
  offsets = { "NvimTree", "nvim-undotree" },
  hide_filetypes = { "dashboard" },
})
