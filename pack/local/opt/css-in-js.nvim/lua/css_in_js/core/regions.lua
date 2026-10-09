local config = require("css_in_js.core.config")
local default_filetypes = config.normalize().filetypes
local M = {}

---@param ar integer
---@param ac integer
---@param br integer
---@param bc integer
---@return boolean
function M.before(ar, ac, br, bc)
  return ar < br or (ar == br and ac < bc)
end

---@param region CssInJsRegion
---@param row integer
---@param col integer
---@param inclusive_end? boolean
---@return boolean
function M.contains(region, row, col, inclusive_end)
  return not M.before(row, col, region.start_row, region.start_col)
    and (
      M.before(row, col, region.end_row, region.end_col)
      or (inclusive_end == true and row == region.end_row and col == region.end_col)
    )
end

---@param region CssInJsRegion
---@param row integer
---@param col integer
---@return boolean
function M.active(region, row, col)
  if not config.integer(row) or not config.integer(col) or not M.contains(region, row, col, true) then
    return false
  end
  for _, substitution in ipairs(region.substitutions) do
    if M.contains(substitution, row, col) then
      return false
    end
  end
  return true
end

---@param filetype string
---@param buftype string
---@param filetypes? string[]
---@return boolean
function M.supports(filetype, buftype, filetypes)
  if buftype ~= "" then
    return false
  end
  filetypes = filetypes or default_filetypes
  for _, supported in ipairs(filetypes) do
    if filetype == supported then
      return true
    end
  end
  return false
end

return M
