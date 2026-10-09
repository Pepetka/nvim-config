local copy = require("css_in_js.core.config").copy
local coordinates = require("css_in_js.core.coordinates")
local M = {}

---@param before string
---@return string
function M.placeholder(before)
  local declaration = before:match("[^;{}]*$") or ""
  return declaration:find(":", 1, true) and "0" or ";"
end

---@param host_lines string[]
---@param region CssInJsRegion
---@param host_start_row? integer
---@return string[]
function M.extract(host_lines, region, host_start_row)
  host_start_row = host_start_row or 0
  local lines = {}
  for row = region.start_row, region.end_row do
    local line = assert(host_lines[row - host_start_row + 1])
    local first = row == region.start_row and region.start_col or 0
    local last = row == region.end_row and region.end_col or #line
    lines[#lines + 1] = line:sub(first + 1, last)
  end
  return lines
end

---@param host_lines string[]
---@param region CssInJsRegion
---@param host_start_row? integer
---@return CssInJsDocument
function M.build(host_lines, region, host_start_row)
  host_start_row = host_start_row or 0
  local content = M.extract(host_lines, region, host_start_row)
  local holes = copy(region.substitutions)
  table.sort(holes, function(a, b)
    return a.start_row < b.start_row or (a.start_row == b.start_row and a.start_col < b.start_col)
  end)
  ---@type CssInJsDocument
  local result = {
    lines = { "a{" },
    maps = {},
    host_lines = copy(host_lines),
    host_start_row = host_start_row,
    region = copy(region),
  }
  for index, line in ipairs(content) do
    local row = region.start_row + index - 1
    local base = row == region.start_row and region.start_col or 0
    local pieces, segments = {}, {}
    local consumed, length = 0, 0
    ---@param first integer
    ---@param last integer
    ---@param replacement string
    ---@param masked boolean
    local function append(first, last, replacement, masked)
      pieces[#pieces + 1] = replacement
      segments[#segments + 1] = {
        css_start = length,
        css_end = length + #replacement,
        host_start = base + first,
        host_end = base + last,
        masked = masked,
      }
      length = length + #replacement
    end
    for _, hole in ipairs(holes) do
      if row >= hole.start_row and row <= hole.end_row then
        local first = row == hole.start_row and hole.start_col - base or 0
        local last = row == hole.end_row and hole.end_col - base or #line
        append(consumed, first, line:sub(consumed + 1, first), false)
        local width = assert(coordinates.character(line:sub(first + 1, last), last - first, "utf-16"))
        local replacement = string.rep(" ", width)
        if row == hole.start_row and width > 0 then
          local before_lines = M.extract(host_lines, {
            start_row = region.start_row,
            start_col = region.start_col,
            end_row = hole.start_row,
            end_col = hole.start_col,
            substitutions = {},
          }, host_start_row)
          replacement = M.placeholder(table.concat(before_lines, "\n")) .. replacement:sub(2)
        end
        append(first, last, replacement, true)
        consumed = last
      end
    end
    append(consumed, #line, line:sub(consumed + 1), false)
    result.lines[#result.lines + 1], result.maps[index] = table.concat(pieces), segments
  end
  result.lines[#result.lines + 1] = ";}"
  return result
end

---@param document CssInJsDocument
---@param row integer
---@param col integer
---@param encoding CssInJsEncoding
---@return lsp.Position?
function M.position(document, row, col, encoding)
  local index = row - document.region.start_row + 1
  for _, segment in ipairs(document.maps[index] or {}) do
    if not segment.masked and col >= segment.host_start and col <= segment.host_end then
      local byte = segment.css_start + col - segment.host_start
      local character = coordinates.character(document.lines[index + 1], byte, encoding)
      if character then
        return { line = index, character = character }
      end
    end
  end
end

---@param document CssInJsDocument
---@param position unknown
---@param encoding CssInJsEncoding
---@return lsp.Position? host, lsp.Position? css_byte
local function map_position(document, position, encoding)
  if type(position) ~= "table" or type(position.line) ~= "number" or position.line % 1 ~= 0 then
    return nil
  end
  local segments = document.maps[position.line]
  if not segments then
    return nil
  end
  local byte = coordinates.byte(document.lines[position.line + 1], position.character, encoding)
  if not byte then
    return nil
  end
  for _, segment in ipairs(segments) do
    if not segment.masked and byte >= segment.css_start and byte <= segment.css_end then
      local row = document.region.start_row + position.line - 1
      local host_byte = segment.host_start + byte - segment.css_start
      local character =
        coordinates.character(document.host_lines[row - document.host_start_row + 1], host_byte, encoding)
      if character then
        return { line = row, character = character }, { line = position.line, character = byte }
      end
    end
  end
end

---@param document CssInJsDocument
---@param range unknown
---@param encoding CssInJsEncoding
---@return lsp.Range?
function M.host_range(document, range, encoding)
  if type(range) ~= "table" then
    return nil
  end
  local first, first_byte = map_position(document, range.start, encoding)
  local last, last_byte = map_position(document, range["end"], encoding)
  if not first or not last or not first_byte or not last_byte then
    return nil
  end
  if first.line > last.line or (first.line == last.line and first.character > last.character) then
    return nil
  end
  for row = first_byte.line, last_byte.line do
    local start_col = row == first_byte.line and first_byte.character or 0
    local end_col = row == last_byte.line and last_byte.character or #document.lines[row + 1]
    for _, segment in ipairs(document.maps[row]) do
      if segment.masked and start_col < segment.css_end and end_col > segment.css_start then
        return nil
      end
    end
  end
  return { start = first, ["end"] = last }
end

return M
