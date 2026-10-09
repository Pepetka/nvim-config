local M = {}

---@param current integer
---@param tabs integer[]
---@param managed fun(tab: integer): boolean
---@return integer?
function M.destination(current, tabs, managed)
  if managed(current) then
    return current
  end
  for _, tab in ipairs(tabs) do
    if managed(tab) then
      return tab
    end
  end
end

---@param known integer[]
---@param snapshots table<integer, integer[]>
---@return integer[]
function M.candidates(known, snapshots)
  local seen, result = {}, {}
  for _, tab in ipairs(known) do
    seen[tab] = true
    result[#result + 1] = tab
  end
  for tab in pairs(snapshots) do
    if not seen[tab] then
      result[#result + 1] = tab
    end
  end
  table.sort(result)
  return result
end

return M
