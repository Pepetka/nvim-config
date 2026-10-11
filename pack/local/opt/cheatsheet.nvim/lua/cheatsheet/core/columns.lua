local M = {}

---@param content_width integer
---@param target integer Preferred column width in cells.
---@param gap integer
---@param limit integer Maximum number of columns.
---@return integer
function M.count(content_width, target, gap, limit)
  local fit = math.floor((content_width + gap) / math.max(1, target + gap))
  return math.max(1, math.min(limit, fit))
end

---@param content_width integer
---@param count integer
---@param gap integer
---@return integer
function M.width(content_width, count, gap)
  return math.max(1, math.floor((content_width - gap * (count - 1)) / count))
end

---Split items into contiguous nonempty ranges minimizing the largest cost.
---Ties keep earlier columns fuller.
---@param items integer
---@param count integer
---@param cost CheatsheetCost
---@return CheatsheetRange[]
function M.partition(items, count, cost)
  count = math.min(count, items)
  if count < 1 then
    return {}
  end
  ---@type table<integer, integer>
  local memo = {}
  ---@param first integer
  ---@param last integer
  ---@return integer
  local function range_cost(first, last)
    local key = first * (items + 1) + last
    if memo[key] == nil then
      memo[key] = cost(first, last)
    end
    return memo[key]
  end
  ---@type integer[][]
  local best, start = { {} }, { {} }
  for last = count == 1 and items or 1, items do
    best[1][last], start[1][last] = range_cost(1, last), 1
  end
  for column = 2, count do
    best[column], start[column] = {}, {}
    -- The final column must end at the last item.
    for last = column == count and items or column, items do
      for first = column, last do
        local value = math.max(best[column - 1][first - 1], range_cost(first, last))
        if best[column][last] == nil or value <= best[column][last] then
          best[column][last], start[column][last] = value, first
        end
      end
    end
  end
  local result, last = {}, items
  for column = count, 1, -1 do
    local first = start[column][last]
    table.insert(result, 1, { first = first, last = last })
    last = first - 1
  end
  return result
end

---@param blocks CheatsheetDocument[]
---@param spacing integer Blank lines between blocks.
---@return CheatsheetDocument
function M.stack(blocks, spacing)
  ---@type CheatsheetDocument
  local result = { lines = {}, spans = {} }
  for index, block in ipairs(blocks) do
    if index > 1 then
      for _ = 1, spacing do
        result.lines[#result.lines + 1] = ""
      end
    end
    local offset = #result.lines
    for _, line in ipairs(block.lines) do
      result.lines[#result.lines + 1] = line
    end
    for _, span in ipairs(block.spans) do
      result.spans[#result.spans + 1] = {
        row = span.row + offset,
        start_col = span.start_col,
        end_col = span.end_col,
        hl_group = span.hl_group,
      }
    end
  end
  return result
end

---Join columns side by side; rows end after their last nonempty segment.
---@param columns CheatsheetDocument[]
---@param width integer Column width in cells.
---@param gap integer
---@param left integer Left padding.
---@param measure CheatsheetMeasure
---@return CheatsheetDocument
function M.compose(columns, width, gap, left, measure)
  ---@type CheatsheetDocument
  local result = { lines = {}, spans = {} }
  local height = 0
  ---@type table<integer, CheatsheetSpan[]>[]
  local rows = {}
  for index, column in ipairs(columns) do
    height = math.max(height, #column.lines)
    rows[index] = {}
    for _, span in ipairs(column.spans) do
      local list = rows[index][span.row] or {}
      list[#list + 1] = span
      rows[index][span.row] = list
    end
  end
  for row = 0, height - 1 do
    local last = 0
    for index, column in ipairs(columns) do
      if (column.lines[row + 1] or "") ~= "" then
        last = index
      end
    end
    local line = string.rep(" ", left)
    for index = 1, last do
      local text = columns[index].lines[row + 1] or ""
      for _, span in ipairs(rows[index][row] or {}) do
        result.spans[#result.spans + 1] = {
          row = row,
          start_col = #line + span.start_col,
          end_col = #line + span.end_col,
          hl_group = span.hl_group,
        }
      end
      line = line .. text
      if index < last then
        line = line .. string.rep(" ", math.max(0, width - measure(text)) + gap)
      end
    end
    result.lines[#result.lines + 1] = line
  end
  return result
end

return M
