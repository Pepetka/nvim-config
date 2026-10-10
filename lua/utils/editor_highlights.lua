local M = {}

---Preserve attributes while removing backgrounds from the editor chrome.
---@param colors table
---@param base? table<string, vim.api.keyset.highlight>
---@return table<string, vim.api.keyset.highlight>
function M.get(colors, base)
  local groups = {}
  for _, name in ipairs({
    "Normal",
    "NormalNC",
    "SignColumn",
    "StatusLine",
    "StatusLineNC",
    "WinSeparator",
    "VertSplit",
    "LineNr",
    "CursorLineNr",
  }) do
    local highlight = base and vim.deepcopy(base[name] or {})
      or vim.api.nvim_get_hl(0, { name = name, link = false, create = false })
    highlight.bg = "NONE"
    highlight.ctermbg = nil
    groups[name] = highlight
  end
  groups.CursorLine = { bg = colors.surface }
  groups.Pmenu = { bg = "NONE", fg = colors.fg }
  groups.PmenuSel = { bg = colors.bg_visual, fg = colors.fg, bold = true }
  groups.PmenuSbar = { bg = "NONE" }
  groups.PmenuThumb = { bg = colors.gutter }
  groups.FloatBorder = { bg = "NONE", fg = colors.focus }
  return groups
end

return M
