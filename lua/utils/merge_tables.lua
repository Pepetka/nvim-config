---Merge two tables. When `array` is true, scalar values are treated as single-element arrays.
---@overload fun<K, V>(t1: table<K, V>, t2: table<K, V>): table<K, V>
---@overload fun<T>(t1: T[] | T, t2: T[] | T, array: true): T[]
---@generic K, V
---@param t1 table<K, V> | any
---@param t2 table<K, V> | any
---@param array? boolean
---@return table<K, V> | any[]
local merge_tables = function(t1, t2, array)
  if array then
    local result = {}
    if type(t1) == "table" then
      for _, v in ipairs(t1) do
        table.insert(result, v)
      end
    else
      table.insert(result, t1)
    end
    if type(t2) == "table" then
      for _, v in ipairs(t2) do
        table.insert(result, v)
      end
    else
      table.insert(result, t2)
    end
    return result
  end

  if type(t1) == "table" and type(t2) == "table" then
    local result = {}
    for k, v in pairs(t1) do
      result[k] = v
    end
    for k, v in pairs(t2) do
      result[k] = v
    end
    return result
  end

  return {}
end

return merge_tables
