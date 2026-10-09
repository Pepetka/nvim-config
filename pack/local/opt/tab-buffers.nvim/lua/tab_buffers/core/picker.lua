local M = {}

---@param selected string[]
---@param contains fun(buf: integer): boolean
---@return integer[]
function M.selected(selected, contains)
  local result, seen = {}, {}
  for _, entry in ipairs(selected) do
    local buf = tonumber(entry:match("^%[(%d+)%]"))
    if buf and buf > 0 and buf < math.huge and buf % 1 == 0 and not seen[buf] and contains(buf) then
      seen[buf] = true
      result[#result + 1] = buf
    end
  end
  return result
end

return M
