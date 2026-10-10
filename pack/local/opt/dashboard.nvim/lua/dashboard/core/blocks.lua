local rules = require("dashboard.core.config")
local M = {}

---@param line string
---@param col integer
---@return nil
local function byte_boundary(line, col)
  local byte = line:byte(col + 1)
  assert(byte == nil or byte < 128 or byte >= 192, "byte offset must be on a character boundary")
end

---@return DashboardDocument
function M.empty()
  return { lines = {}, spans = {}, targets = {} }
end

---@param document DashboardDocument
---@param row integer
---@param start_col integer
---@param end_col integer
---@param style string
---@return nil
function M.span(document, row, start_col, end_col, style)
  if end_col > start_col then
    document.spans[#document.spans + 1] = { row = row, start_col = start_col, end_col = end_col, style = style }
  end
end

---@param lines string[]
---@param style string
---@return DashboardDocument
function M.text(lines, style)
  rules.list(lines, "text lines")
  local result = M.empty()
  for _, line in ipairs(lines) do
    rules.display_text(line, "text line")
    result.lines[#result.lines + 1] = line
    M.span(result, #result.lines - 1, 0, #line, style)
  end
  return result
end

---@param items DashboardItem[]
---@param minimum integer
---@param measure DashboardMeasure
---@return integer
function M.label_width(items, minimum, measure)
  local width = minimum
  for _, item in ipairs(items) do
    width = math.max(width, measure(item.label))
  end
  return width
end

---@param item DashboardItem
---@param width integer
---@param measure DashboardMeasure
---@return string, integer, integer
function M.action_line(item, width, measure)
  local prefix = item.icon and item.icon ~= "" and (item.icon .. " ") or ""
  local label = item.label .. string.rep(" ", math.max(0, width - measure(item.label)))
  local suffix = item.key and ("  [" .. item.key .. "]") or ""
  return prefix .. label .. suffix, #prefix, #prefix + #label
end

---@param items DashboardItem[]
---@param minimum integer
---@param spacing integer
---@param measure DashboardMeasure
---@return DashboardDocument
function M.actions(items, minimum, spacing, measure)
  rules.items(items)
  local result = M.empty()
  local width = M.label_width(items, minimum, measure)
  for index, item in ipairs(items) do
    if index > 1 then
      for _ = 1, spacing do
        result.lines[#result.lines + 1] = ""
      end
    end
    local line, label_start, label_end = M.action_line(item, width, measure)
    local row = #result.lines
    result.lines[#result.lines + 1] = line
    M.span(result, row, 0, math.max(0, label_start - 1), "Icon")
    M.span(result, row, label_start, label_end, "Text")
    M.span(result, row, label_end, #line, "Key")
    result.targets[#result.targets + 1] = { id = item.id, row = row, col = label_start, key = item.key, run = item.run }
  end
  return result
end

---@param document DashboardDocument
---@return DashboardDocument
function M.validate(document)
  rules.fields(document, { lines = true, spans = true, targets = true }, "document")
  rules.list(document.lines, "document.lines")
  rules.list(document.spans, "document.spans")
  rules.list(document.targets, "document.targets")
  for _, line in ipairs(document.lines) do
    rules.display_text(line, "document line")
  end
  local ids = {}
  for _, span in ipairs(document.spans) do
    rules.fields(span, { row = true, start_col = true, end_col = true, style = true }, "span")
    rules.integer(span.row, "span.row")
    rules.integer(span.start_col, "span.start_col")
    rules.integer(span.end_col, "span.end_col")
    rules.id(span.style, "span.style")
    assert(
      document.lines[span.row + 1] and span.end_col <= #document.lines[span.row + 1] and span.start_col <= span.end_col,
      "span outside document"
    )
    byte_boundary(document.lines[span.row + 1], span.start_col)
    byte_boundary(document.lines[span.row + 1], span.end_col)
  end
  for _, target in ipairs(document.targets) do
    rules.fields(target, { id = true, block_id = true, row = true, col = true, key = true, run = true }, "target")
    rules.id(target.id, "target.id")
    assert(not ids[target.id], "duplicate target id")
    ids[target.id] = true
    rules.integer(target.row, "target.row")
    rules.integer(target.col, "target.col")
    assert(document.lines[target.row + 1] and target.col <= #document.lines[target.row + 1], "target outside document")
    byte_boundary(document.lines[target.row + 1], target.col)
    if target.key ~= nil then
      rules.text(target.key, "target.key")
      assert(target.key ~= "", "empty target key")
    end
    assert(type(target.run) == "string" or type(target.run) == "function", "invalid target action")
  end
  return rules.copy(document)
end

return M
