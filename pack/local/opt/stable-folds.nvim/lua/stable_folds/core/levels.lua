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

local plain, opening = {}, {}

---@param depth integer
---@param start boolean
---@return string
local function label(depth, start)
  local cache = start and opening or plain
  local value = cache[depth]
  if not value then
    value = (start and ">" or "") .. depth
    cache[depth] = value
  end
  return value
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
    if start > 0 and stop > 0 then
      depth, stop = depth - stop, 0
    end
    local visible = start > 0 and depth <= nestmax and nestmax ~= 0
    result[line] = label(math.max(0, math.min(depth, nestmax)), visible)
    previous_stop = stop
  end
  return result
end

return M
