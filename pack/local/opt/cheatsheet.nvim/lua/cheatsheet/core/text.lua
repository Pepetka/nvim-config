local M = {}

---UTF-8 characters; bytes outside a valid sequence are kept as single characters.
---@param text string
---@return string[]
function M.chars(text)
  local result, index = {}, 1
  while index <= #text do
    local char = text:match("^[\194-\244][\128-\191]+", index) or text:sub(index, index)
    result[#result + 1] = char
    index = index + #char
  end
  return result
end

---The longest prefix that fits the width in cells.
---@param text string
---@param width integer
---@param measure CheatsheetMeasure
---@return string
function M.clip(text, width, measure)
  local result, used = "", 0
  for _, char in ipairs(M.chars(text)) do
    used = used + measure(char)
    if used > width then
      break
    end
    result = result .. char
  end
  return result
end

---Split a word wider than the limit by characters; a wide character is never split.
---@param word string
---@param width integer
---@param measure CheatsheetMeasure
---@return string[]
local function split_word(word, width, measure)
  local parts, current, used = {}, "", 0
  for _, char in ipairs(M.chars(word)) do
    local cells = measure(char)
    if used > 0 and used + cells > width then
      parts[#parts + 1], current, used = current, "", 0
    end
    current, used = current .. char, used + cells
  end
  parts[#parts + 1] = current
  return parts
end

---Greedy word wrap by screen cells; repeated whitespace collapses into single spaces.
---@param text string
---@param width integer Positive cell width.
---@param measure CheatsheetMeasure
---@return string[]
function M.wrap(text, width, measure)
  local lines, current, used = {}, "", 0
  for word in text:gmatch("%S+") do
    local cells = measure(word)
    if used > 0 and used + 1 + cells <= width then
      current, used = current .. " " .. word, used + 1 + cells
    else
      if used > 0 then
        lines[#lines + 1] = current
      end
      current, used = word, cells
      if cells > width then
        local parts = split_word(word, width, measure)
        for index = 1, #parts - 1 do
          lines[#lines + 1] = parts[index]
        end
        current = parts[#parts]
        used = measure(current)
      end
    end
  end
  lines[#lines + 1] = current
  return lines
end

return M
