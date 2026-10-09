local M = {}

---@param ranges StableFoldsRange[]
---@param minlines integer
---@return table<integer, integer>, table<integer, integer>
function M.events(ranges, minlines)
  local starts, stops = {}, {}
  for _, range in ipairs(ranges) do
    if range.stop - range.start + 1 > minlines then
      starts[range.start] = (starts[range.start] or 0) + 1
      stops[range.stop] = (stops[range.stop] or 0) + 1
    end
  end
  return starts, stops
end

---Keep the native expression convention for captures meeting on the same line.
---@param ranges StableFoldsRange[]
---@param count integer
---@param minlines integer
---@param nestmax integer
---@return string[]
function M.build(ranges, count, minlines, nestmax)
  local starts, stops = M.events(ranges, minlines)
  local result, depth, previous_stop = {}, 0, 0
  for line = 1, count do
    local start, stop = starts[line] or 0, stops[line] or 0
    depth = depth - previous_stop + start
    local prefix = ""
    if start > 0 then
      prefix = ">"
      if stop > 0 then
        depth, stop = depth - stop, 0
      end
    end
    if depth > nestmax or nestmax == 0 then
      prefix = ""
    end
    result[line] = prefix .. tostring(math.max(0, math.min(depth, nestmax)))
    previous_stop = stop
  end
  return result
end

return M
