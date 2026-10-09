local lists = require("tab_buffers.core.lists")
local M = {}

---@return TabBuffersResult
function M.result()
  return { closed = {}, failed = {}, tab_closed = false }
end

---@param owners integer
---@param modified boolean
---@param force? boolean
---@param foreign_window boolean
---@return string?
function M.blocker(owners, modified, force, foreign_window)
  if owners ~= 1 then
    return nil
  end
  if modified and not force then
    return "unsaved changes"
  end
  if foreign_window then
    return "buffer is still displayed in an unmanaged window"
  end
end

---@param buffers integer[]
---@param buf integer
---@param excluded table<integer, boolean>
---@param eligible fun(buf: integer): boolean
---@param policy? TabBuffersReplacement
---@param history? integer[] Most recently focused first.
---@return integer?
function M.replacement(buffers, buf, excluded, eligible, policy, history)
  local pivot = lists.index_of(buffers, buf)
  if not pivot then
    return nil
  end
  ---@param candidate integer
  ---@return boolean
  local function permitted(candidate)
    return candidate ~= buf and not excluded[candidate] and eligible(candidate)
  end
  if policy == "last_used" then
    for _, candidate in ipairs(history or {}) do
      if lists.index_of(buffers, candidate) and permitted(candidate) then
        return candidate
      end
    end
  end
  ---@param first integer
  ---@param last integer
  ---@param step integer
  ---@return integer?
  local function neighbor(first, last, step)
    for i = first, last, step do
      if permitted(buffers[i]) then
        return buffers[i]
      end
    end
  end
  if policy == "left" then
    return neighbor(pivot - 1, 1, -1) or neighbor(pivot + 1, #buffers, 1)
  end
  return neighbor(pivot + 1, #buffers, 1) or neighbor(pivot - 1, 1, -1)
end

---Preserve a committed close report if subsequent observation fails.
---@param value unknown
---@param message string
---@return boolean
function M.record_error(value, message)
  if type(value) ~= "table" or type(value.closed) ~= "table" or type(value.failed) ~= "table" then
    return false
  end
  value.error = value.error and tostring(value.error) .. "\n" .. message or message
  return true
end

return M
