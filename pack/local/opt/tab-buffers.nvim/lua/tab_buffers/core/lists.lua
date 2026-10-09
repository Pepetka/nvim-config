local M = {}

---@generic T
---@param value T
---@return T
function M.copy(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for key, item in pairs(value) do
    result[key] = M.copy(item)
  end
  return result
end

---@param a unknown
---@param b unknown
---@return boolean
function M.equal(a, b)
  if a == b then
    return true
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  for key, value in pairs(a) do
    if not M.equal(value, b[key]) then
      return false
    end
  end
  for key in pairs(b) do
    if a[key] == nil then
      return false
    end
  end
  return true
end

---@param list integer[]
---@param value? integer
---@return integer?
function M.index_of(list, value)
  for index, item in ipairs(list) do
    if item == value then
      return index
    end
  end
end

---@param value integer
---@param maximum integer
---@return integer
function M.clamp(value, maximum)
  return math.max(1, math.min(value, maximum))
end

---@generic T
---@param first T
---@param second table
---@return T
function M.merge(first, second)
  local result = M.copy(first)
  for key, value in pairs(second) do
    result[key] = value
  end
  return result
end

return M
