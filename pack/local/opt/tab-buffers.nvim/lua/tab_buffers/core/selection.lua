local validation = require("tab_buffers.core.validation")
local lists = require("tab_buffers.core.lists")
local integer, id, buffer_list = validation.integer, validation.id, validation.buffer_list
local copy, index_of, clamp = lists.copy, lists.index_of, lists.clamp
local M = {}

---@param model TabBuffersCore
---@param tabs table<integer, integer[]>
---@return nil
function M.install(model, tabs)
  function model:targets(tab, mode, pivot)
    id(tab, "tab")
    local modes = { one = true, all = true, others = true, left = true, right = true }
    assert(type(mode) == "string" and modes[mode], "unknown target mode")
    if pivot ~= nil then
      id(pivot, "pivot")
    end
    local buffers = tabs[tab] or {}
    if mode == "all" then
      return copy(buffers)
    end
    local current = index_of(buffers, pivot)
    if not current then
      return {}
    end
    local result = {}
    for i, buf in ipairs(buffers) do
      if
        (mode == "one" and i == current)
        or (mode == "others" and i ~= current)
        or (mode == "left" and i < current)
        or (mode == "right" and i > current)
      then
        result[#result + 1] = buf
      end
    end
    return result
  end

  ---Produce a snapshot, not an executable transaction. Recheck owners before
  ---performing external deletion, then detach only successful targets.
  function model:plan_close(tab, buffers)
    id(tab, "tab")
    local selected = {}
    for _, buf in ipairs(buffer_list(buffers)) do
      selected[buf] = true
    end
    ---@type TabBuffersClosePlan
    local plan = { buffers = {}, shared = {}, exclusive = {}, remaining = {} }
    for _, buf in ipairs(tabs[tab] or {}) do
      if selected[buf] then
        plan.buffers[#plan.buffers + 1] = buf
        local owners = #self:owners(buf) > 1 and plan.shared or plan.exclusive
        owners[#owners + 1] = buf
      else
        plan.remaining[#plan.remaining + 1] = buf
      end
    end
    return plan
  end
end

---@param buffers integer[]
---@param selected table<integer, boolean>
---@return integer[]
function M.selected(buffers, selected)
  local result = {}
  for _, buf in ipairs(buffers) do
    if selected[buf] then
      result[#result + 1] = buf
    end
  end
  return result
end

return M
