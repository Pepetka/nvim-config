local tokyonight = require("tokyonight")
local colors = require("utils.colors")
local theme_highlights = require("utils.theme_highlights")

local THEME_MODE_FILE = vim.fn.expand("~/.config/theme/mode")

local function read_mode_file()
  local file = io.open(THEME_MODE_FILE, "r")
  if not file then
    return "dark"
  end
  local content = file:read("*line") or "dark"
  file:close()
  return vim.trim(content)
end

local function apply_theme(mode)
  -- Only manual modes are supported; default to dark.
  if mode == "light" then
    vim.api.nvim_set_option_value("background", "light", {})
  else
    vim.api.nvim_set_option_value("background", "dark", {})
  end
  vim.cmd.colorscheme("tokyonight")
end

local function watch_theme_change()
  local handle = vim.uv.new_fs_event()
  if not handle then
    return
  end

  local mode_basename = vim.fn.fnamemodify(THEME_MODE_FILE, ":t")
  local theme_dir = vim.fn.fnamemodify(THEME_MODE_FILE, ":h")

  local function restart_watcher()
    if handle then
      vim.uv.fs_event_stop(handle)
    end
    watch_theme_change()
  end

  vim.uv.fs_event_start(
    handle,
    theme_dir,
    {},
    vim.schedule_wrap(function(err, filename)
      if err then
        restart_watcher()
        return
      end

      -- Ignore events for other files in the theme directory.
      if filename and filename ~= "" and filename ~= mode_basename then
        return
      end

      local mode = read_mode_file()
      apply_theme(mode)
    end)
  )
end

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

tokyonight.setup({
  style = "moon",
  light_style = "day",
  transparent = true,
  styles = {
    sidebars = "transparent",
    floats = "transparent",
  },
})

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

    -- Rebuild lualine with the new theme colors if it has already been loaded.
    if package.loaded["configs.lualine"] then
      local lualine = require("configs.lualine")
      if lualine.setup then
        lualine.setup()

        -- lualine.setup() resets laststatus for global statusline, but dashboard
        -- expects it hidden. Re-hide the dashboard UI if it is currently visible.
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          local buf = vim.api.nvim_win_get_buf(win)
          if vim.api.nvim_get_option_value("filetype", { buf = buf }) == "dashboard" then
            vim.opt.laststatus = 0
            break
          end
        end
      end
    end

    -- Update plugin highlights that cache colors at setup time.
    theme_highlights.apply_all()
  end,
})

-- Apply the theme stored in the mode file on startup.
apply_theme(read_mode_file())

-- Watch for external theme changes (e.g. from the `theme` shell command).
watch_theme_change()
