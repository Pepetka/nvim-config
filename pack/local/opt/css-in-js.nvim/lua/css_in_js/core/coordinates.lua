local integer = require("css_in_js.core.config").integer
local M = {}
local minimums = { [2] = 128, [3] = 2048, [4] = 65536 }

---Decode one Unicode scalar, rejecting malformed sequences rather than splitting a character.
---@param text string
---@param index integer One-based byte index.
---@return integer? next_index, integer? scalar
function M.decode(text, index)
  local a = text:byte(index)
  if not a then
    return nil
  end
  if a < 128 then
    return index + 1, a
  end
  local size = a >= 194 and a <= 223 and 2 or a >= 224 and a <= 239 and 3 or a >= 240 and a <= 244 and 4
  if not size or index + size - 1 > #text then
    return nil
  end
  local scalar = a % (2 ^ (7 - size))
  for offset = 1, size - 1 do
    local byte = text:byte(index + offset)
    if byte < 128 or byte > 191 then
      return nil
    end
    scalar = scalar * 64 + byte - 128
  end
  if scalar < minimums[size] or scalar > 1114111 or (scalar >= 55296 and scalar <= 57343) then
    return nil
  end
  return index + size, scalar
end

---@param scalar integer
---@param bytes integer
---@param encoding CssInJsEncoding
---@return integer
local function units(scalar, bytes, encoding)
  return encoding == "utf-8" and bytes or encoding == "utf-16" and (scalar > 65535 and 2 or 1) or 1
end

---@param text string
---@param byte_col integer
---@param encoding CssInJsEncoding
---@return integer?
function M.character(text, byte_col, encoding)
  if not integer(byte_col) or byte_col > #text then
    return nil
  end
  local index, count = 1, 0
  while index <= byte_col do
    local next_index, scalar = M.decode(text, index)
    if not next_index or next_index - 1 > byte_col then
      return nil
    end
    count = count + units(assert(scalar), next_index - index, encoding)
    index = next_index
  end
  return count
end

---@param text string
---@param character integer
---@param encoding CssInJsEncoding
---@return integer?
function M.byte(text, character, encoding)
  if not integer(character) then
    return nil
  end
  local index, count = 1, 0
  while count < character do
    local next_index, scalar = M.decode(text, index)
    if not next_index then
      return nil
    end
    count = count + units(assert(scalar), next_index - index, encoding)
    index = next_index
  end
  return count == character and index - 1 or nil
end

return M
