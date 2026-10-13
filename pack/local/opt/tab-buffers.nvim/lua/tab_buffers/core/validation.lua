local M = {}

---@param value unknown
---@param name string
---@param positive? boolean
---@return nil
function M.integer(value, name, positive)
  assert(
    type(value) == "number" and value > -math.huge and value < math.huge and value == math.floor(value),
    name .. " must be a finite integer"
  )
  assert(not positive or value > 0, name .. " must be positive")
end

---@param value unknown
---@param name string
---@return nil
function M.id(value, name)
  M.integer(value, name, true)
end

---@param value unknown
---@return integer[]
function M.buffer_list(value)
  assert(type(value) == "table", "buffers must be a dense list")
  local count = 0
  for key in pairs(value) do
    M.id(key, "list index")
    count = count + 1
  end
  local result = {}
  for i = 1, count do
    assert(value[i] ~= nil, "buffers must be a dense list")
    M.id(value[i], "buf")
    result[i] = value[i]
  end
  return result
end

---Reject misspelled option names instead of silently falling back to defaults.
---@param value table
---@param known table<string, boolean>
---@param kind string
---@return nil
function M.known(value, known, kind)
  for key in pairs(value) do
    assert(known[key], "unknown " .. kind .. ": " .. tostring(key))
  end
end

local option_names = { tab = true, buf = true, win = true, index = true, force = true, wrap = true, split = true }

---@param opts? unknown
---@return TabBuffersOptions
function M.options(opts)
  assert(opts == nil or type(opts) == "table", "opts must be a table")
  opts = opts or {}
  M.known(opts, option_names, "option")
  for _, key in ipairs({ "tab", "buf", "win" }) do
    if opts[key] ~= nil then
      M.id(opts[key], key)
    end
  end
  if opts.index ~= nil then
    M.integer(opts.index, "index")
  end
  for _, key in ipairs({ "force", "wrap" }) do
    assert(opts[key] == nil or type(opts[key]) == "boolean", key .. " must be a boolean")
  end
  local result = {}
  for key, value in pairs(opts) do
    result[key] = value
  end
  return result
end

return M
