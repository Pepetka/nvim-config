local integer = require("stable_folds.core.config").integer
local M = {}

---Convert exclusive Tree-sitter coordinates to an inclusive multiline fold.
---@param range StableFoldsRawRange
---@param count integer
---@return StableFoldsRange?
function M.bounds(range, count)
  if
    not integer(range.start_row)
    or not integer(range.start_col)
    or not integer(range.end_row)
    or not integer(range.end_col)
    or range.end_row < range.start_row
    or (range.end_row == range.start_row and range.end_col <= range.start_col)
  then
    return nil
  end
  local first = range.start_row + 1
  local last = range.end_row + (range.end_col == 0 and 0 or 1)
  if first < 1 or first > count or last > count or last <= first then
    return nil
  end
  return { start = first, stop = last }
end

---@param input StableFoldsRawRange[]
---@param count integer
---@return StableFoldsRange[]
function M.normalize(input, count)
  local result, seen = {}, {}
  for _, raw in ipairs(input) do
    local range = M.bounds(raw, count)
    if range then
      local key = range.start .. ":" .. range.stop
      if not seen[key] then
        seen[key] = true
        result[#result + 1] = range
      end
    end
  end
  table.sort(result, function(a, b)
    return a.start < b.start or (a.start == b.start and a.stop > b.stop)
  end)
  return result
end

---Track all candidate headers, independently of a window's fold options.
---@param ranges StableFoldsRange[]
---@param lines string[]
---@return StableFoldsHeader[]
function M.headers(ranges, lines)
  local result, seen = {}, {}
  for _, range in ipairs(ranges) do
    if not seen[range.start] then
      seen[range.start] = true
      result[#result + 1] = { line = range.start, header = lines[range.start] }
    end
  end
  return result
end

---Translate the frozen native fold tree while on_bytes inspects its flags.
---@param input StableFoldsRange[]
---@param edit StableFoldsEdit
---@return StableFoldsRange[]
function M.shift(input, edit)
  local delta, boundary = edit.new_rows - edit.old_rows, edit.start_row + 1
  if delta == 0 then
    return input
  end
  local result = {}
  for _, range in ipairs(input) do
    local first, last = range.start, range.stop
    if first > boundary or (first == boundary and first > 1 and edit.start_col == 0) then
      first = math.max(boundary, first + delta)
    end
    if last >= boundary then
      last = math.max(first, last + delta)
    end
    if last > first then
      result[#result + 1] = { start = first, stop = last }
    end
  end
  return result
end

return M
