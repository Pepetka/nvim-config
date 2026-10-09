local M = {}

---@param modes CheatsheetMode[]
---@param mode unknown
---@return integer?
function M.index(modes, mode)
  for index, candidate in ipairs(modes) do
    if candidate == mode then
      return index
    end
  end
end

---@param modes CheatsheetMode[]
---@param mode unknown
---@param direction integer
---@return CheatsheetMode
function M.cycle(modes, mode, direction)
  local index = M.index(modes, mode) or 1
  return modes[(index - 1 + direction) % #modes + 1]
end

return M
