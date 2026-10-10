local rules = require("dashboard.core.config")
local M = {}

---@param input DashboardStyles
---@return DashboardStyles
function M.resolve(input)
  assert(type(input) == "table", "highlights must return a table")
  ---@type DashboardStyles
  local result = {
    Header = { link = "Title" },
    Text = { link = "Comment" },
    Icon = { link = "Comment" },
    Key = { link = "Special" },
    Footer = { link = "Comment" },
    Selected = { link = "CursorLine" },
  }
  for role, value in pairs(input) do
    rules.id(role, "highlight role")
    assert(type(value) == "table", "highlight definition must be a table")
    -- An override replaces the role: a default link must not swallow explicit colors.
    result[role] = rules.copy(value)
  end
  return result
end

return M
