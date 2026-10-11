local M = {}

---@type table<CheatsheetMode, string>
M.names = { n = "normal", i = "insert", v = "visual", o = "operator", t = "terminal" }

-- Raw keymap modes: " " is :map (n/v/o), "!" is :map! (i/c), "v" covers visual and select.
---@type table<CheatsheetMode, string>
local raw_modes = { n = "[ n]", i = "[!i]", v = "[ vx]", o = "[ o]", t = "t" }

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

---Whether a raw keymap mode applies to a mode; select-only mappings do not apply to visual mode.
---@param raw? string
---@param mode CheatsheetMode
---@return boolean
function M.covers(raw, mode)
  return raw == nil or raw:find(raw_modes[mode]) ~= nil
end

return M
