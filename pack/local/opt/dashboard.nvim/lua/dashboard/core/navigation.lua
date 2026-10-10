local M = {}

---@param targets DashboardTarget[]
---@param selected? DashboardTarget
---@return integer?
function M.index(targets, selected)
  if selected then
    for index, target in ipairs(targets) do
      if target.id == selected.id and target.block_id == selected.block_id then
        return index
      end
    end
  end
end

---@param targets DashboardTarget[]
---@param selected? DashboardTarget
---@return DashboardTarget?
function M.preserve(targets, selected)
  return targets[M.index(targets, selected) or 1]
end

---@param targets DashboardTarget[]
---@param selected DashboardTarget?
---@param delta integer
---@param wrap? boolean
---@return DashboardTarget?
function M.move(targets, selected, delta, wrap)
  if #targets > 0 then
    local index = (M.index(targets, selected) or 1) + delta
    if wrap == false then
      return targets[math.max(1, math.min(#targets, index))]
    end
    return targets[(index - 1) % #targets + 1]
  end
end

return M
