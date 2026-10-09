local M = {}

---Decode fold flags from Neovim's view serialization without executing its script.
---@param lines string[]
---@param positions StableFoldsPosition[]
---@param foldlevel integer
---@return table<integer, boolean>
function M.states(lines, positions, foldlevel)
  ---@type table<integer, boolean>
  local overrides = {}
  local line
  for _, text in ipairs(lines) do
    local number = text:match("^(%d+)$")
    if number then
      line = tonumber(number)
    elseif line then
      local operation = text:match("^sil! normal! z([co])$")
      if operation then
        overrides[line] = operation == "c"
      end
    end
  end
  local result = {}
  for _, mark in ipairs(positions) do
    if mark.line and mark.level then
      local closed = overrides[mark.line]
      if closed == nil then
        closed = mark.level > foldlevel
      end
      result[mark.id] = closed
    end
  end
  return result
end

return M
