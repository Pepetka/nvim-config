local M = {}

---Bounded display-width cache. The caller replaces it when display options change.
---@param native TabBuffersTextMetrics
---@param limit? integer
---@return TabBuffersTextMetrics
function M.new(native, limit)
  local maximum, count = limit or 1024, 0
  ---@type table<string, integer>
  local widths = {}
  return {
    length = native.length,
    suffix = native.suffix,
    measure = function(text)
      local width = widths[text]
      if width == nil then
        width = native.measure(text)
        if count >= maximum then
          widths, count = {}, 0
        end
        widths[text], count = width, count + 1
      end
      return width
    end,
  }
end

return M
