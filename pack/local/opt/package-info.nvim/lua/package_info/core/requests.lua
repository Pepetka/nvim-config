local M = {}
---@param current? PackageInfoBuffer
---@param state PackageInfoBuffer
---@param buffer? PackageInfoHost
---@return boolean
function M.valid(current, state, buffer)
  return buffer ~= nil
    and current == state
    and not state.disabled
    and not buffer.modified
    and buffer.tick == state.tick
    and buffer.path == state.path
end
return M
