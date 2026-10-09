local M = {}

-- string.find does not validate unreachable suffixes (e.g. "^Git:["). Walk
-- syntax without matching so invalid patterns are diagnosed during setup.
---@param pattern string
---@param index integer
---@return integer?
local function class_end(pattern, index)
  index = index + 1
  if pattern:sub(index, index) == "^" then
    index = index + 1
  end
  repeat
    if pattern:sub(index, index) == "%" then
      index = index + 1
    end
    index = index + 1
  until index > #pattern or pattern:sub(index, index) == "]"
  if pattern:sub(index, index) == "]" then
    return index
  end
end

---@param pattern unknown
---@return boolean
function M.valid(pattern)
  if type(pattern) ~= "string" then
    return false
  end
  ---@type integer[]
  local stack = {}
  ---@type ("position" | "open" | "closed")[]
  local captures = {}
  local index = 1
  while index <= #pattern do
    local char = pattern:sub(index, index)
    if char == "[" then
      local ending = class_end(pattern, index)
      if not ending then
        return false
      end
      index = ending
    elseif char == "%" then
      index = index + 1
      local escaped = pattern:sub(index, index)
      if escaped == "" then
        return false
      elseif escaped == "b" then
        if index + 2 > #pattern then
          return false
        end
        index = index + 2
      elseif escaped == "f" then
        if pattern:sub(index + 1, index + 1) ~= "[" then
          return false
        end
        local ending = class_end(pattern, index + 1)
        if not ending then
          return false
        end
        index = ending
      elseif escaped:match("%d") and captures[tonumber(escaped)] ~= "closed" then
        return false
      end
    elseif char == "(" then
      if #captures == 32 then
        return false
      end
      local capture = #captures + 1
      if pattern:sub(index + 1, index + 1) == ")" then
        captures[capture] = "position"
        index = index + 1
      else
        captures[capture] = "open"
        stack[#stack + 1] = capture
      end
    elseif char == ")" then
      local capture = table.remove(stack)
      if not capture then
        return false
      end
      captures[capture] = "closed"
    end
    index = index + 1
  end
  return #stack == 0
end

return M
