local M = {}

---Cache only within one document build: display options may change between builds.
---@param measure DashboardMeasure
---@return DashboardMeasure
function M.cached(measure)
  ---@type table<string, integer>
  local widths = {}
  return function(text)
    local width = widths[text]
    if width == nil then
      width = measure(text)
      widths[text] = width
    end
    return width
  end
end

return M
