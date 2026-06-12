local tokyonight = require("tokyonight")
local colors = require("utils.colors")

local config = {
  transparent = true,
  styles = {
    sidebars = "transparent",
    floats = "transparent",
  },
}
tokyonight.setup(config)

local function setup_nvim_tree_highlights()
  -- Transparent background for the tree sidebar.
  vim.api.nvim_set_hl(0, "NvimTreeNormal", { bg = "none", fg = colors.fg })
  vim.api.nvim_set_hl(0, "NvimTreeNormalNC", { bg = "none", fg = colors.fg })
  vim.api.nvim_set_hl(0, "NvimTreeEndOfBuffer", { bg = "none", fg = colors.bg })
  vim.api.nvim_set_hl(0, "NvimTreeWinSeparator", { bg = "none", fg = colors.gutter })

  -- Cursor / selection.
  vim.api.nvim_set_hl(0, "NvimTreeCursorLine", { bg = colors.surface })
  vim.api.nvim_set_hl(0, "NvimTreeCursorColumn", { bg = colors.surface })

  -- Opened files / folders.
  vim.api.nvim_set_hl(0, "NvimTreeOpenedFile", { fg = colors.accent, bold = true })
  vim.api.nvim_set_hl(0, "NvimTreeOpenedFolderName", { fg = colors.focus, bold = true })

  -- Folder / root.
  vim.api.nvim_set_hl(0, "NvimTreeFolderName", { fg = colors.focus })
  vim.api.nvim_set_hl(0, "NvimTreeFolderIcon", { fg = colors.muted })
  vim.api.nvim_set_hl(0, "NvimTreeRootFolder", { fg = colors.muted, bold = true })

  -- Git / modified status.
  vim.api.nvim_set_hl(0, "NvimTreeFileDirty", { fg = colors.warning })
  vim.api.nvim_set_hl(0, "NvimTreeFileNew", { fg = colors.success })
  vim.api.nvim_set_hl(0, "NvimTreeFileDeleted", { fg = colors.error })
  vim.api.nvim_set_hl(0, "NvimTreeGitDirty", { fg = colors.warning })
  vim.api.nvim_set_hl(0, "NvimTreeGitNew", { fg = colors.success })
  vim.api.nvim_set_hl(0, "NvimTreeGitDeleted", { fg = colors.error })
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("TokyonightTransparent", { clear = true }),
  callback = function()
    local transparent_groups = {
      "Normal",
      "NormalNC",
      "SignColumn",
      "StatusLine",
      "StatusLineNC",
      "WinSeparator",
      "VertSplit",
      "LineNr",
      "CursorLineNr",
    }
    for _, group in ipairs(transparent_groups) do
      vim.api.nvim_set_hl(0, group, { bg = "none" })
    end
    vim.api.nvim_set_hl(0, "CursorLine", { bg = colors.surface })
    vim.api.nvim_set_hl(0, "Pmenu", { bg = "none", fg = colors.fg })
    vim.api.nvim_set_hl(0, "PmenuSel", { bg = colors.bg_visual, fg = colors.fg, bold = true })
    vim.api.nvim_set_hl(0, "PmenuSbar", { bg = "none" })
    vim.api.nvim_set_hl(0, "PmenuThumb", { bg = colors.gutter })
    vim.api.nvim_set_hl(0, "FloatBorder", { bg = "none", fg = colors.focus })

    setup_nvim_tree_highlights()
  end,
})
vim.cmd.colorscheme("tokyonight")
