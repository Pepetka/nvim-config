local columns = require("cheatsheet.core.columns")
local modes = require("cheatsheet.core.modes")
local text = require("cheatsheet.core.text")
local M = {}

---The float's dimensions include only its content; reserve cells for its border.
---@param window CheatsheetWindowConfig
---@param viewport CheatsheetViewport
---@return CheatsheetGeometry
function M.geometry(window, viewport)
  local horizontal, vertical = 0, 0
  if window.border == "shadow" then
    horizontal, vertical = 1, 1
  elseif window.border ~= "none" then
    horizontal, vertical = 2, 2
  end
  local columns, lines = math.max(1, viewport.columns), math.max(1, viewport.lines)
  local width = math.max(1, math.min(math.floor(columns * window.width), columns - horizontal))
  local height = math.max(1, math.min(math.floor(lines * window.height), lines - vertical))
  return {
    width = width,
    height = height,
    row = math.max(0, math.floor((lines - height - vertical) / 2)),
    col = math.max(0, math.floor((columns - width - horizontal) / 2)),
  }
end

---@param align CheatsheetGroupAlign
---@param width integer
---@param text_width integer
---@param padding integer
---@return integer
function M.offset(align, width, text_width, padding)
  local remaining = math.max(0, width - text_width)
  if align == "right" then
    return padding + remaining
  elseif align == "center" then
    return padding + math.floor(remaining / 2)
  end
  return padding
end

---@param configured CheatsheetMode[]
---@param current CheatsheetMode
---@return string
function M.mode_label(configured, current)
  local parts = {}
  for _, mode in ipairs(configured) do
    local name = modes.names[mode]
    parts[#parts + 1] = mode == current and "[" .. name .. "] " or " " .. name .. "  "
  end
  return table.concat(parts)
end

---@param groups { mappings: { lhs: string }[] }[]
---@param measure CheatsheetMeasure
---@return integer
function M.key_width(groups, measure)
  local width = 0
  for _, group in ipairs(groups) do
    for _, mapping in ipairs(group.mappings) do
      width = math.max(width, measure(mapping.lhs))
    end
  end
  return width
end

---@param gap integer
---@param mapping CheatsheetDisplayMapping
---@param width integer
---@param left integer
---@param measure CheatsheetMeasure
---@return string text, integer start_col, integer end_col, integer desc_col
function M.mapping_line(mapping, width, left, measure, gap)
  local key = mapping.lhs .. string.rep(" ", math.max(0, width - measure(mapping.lhs)))
  local start_col, end_col = left, left + #key
  local text = string.rep(" ", left) .. key .. string.rep(" ", gap) .. mapping.desc
  return text, start_col, end_col, end_col + gap
end

---@param result CheatsheetDocument
---@param row integer
---@param start_col integer
---@param end_col integer
---@param group CheatsheetHighlight
---@return nil
local function span(result, row, start_col, end_col, group)
  if end_col > start_col then
    result.spans[#result.spans + 1] = { row = row, start_col = start_col, end_col = end_col, hl_group = group }
  end
end

-- Wrapped descriptions per measure, mapping and width; reused by heights and rendering.
---@type table<CheatsheetMeasure, table<CheatsheetDisplayMapping, table<string, string[]>>>
local wrapped = setmetatable({}, { __mode = "k" })

---@param groups CheatsheetDisplayGroup[]
---@param range CheatsheetRange
---@return CheatsheetDisplayGroup[]
local function slice(groups, range)
  local result = {}
  for index = range.first, range.last do
    result[#result + 1] = groups[index]
  end
  return result
end

---@param key_width integer
---@param gap integer
---@param width integer
---@param wrap boolean
---@return integer?
local function description_width(key_width, gap, width, wrap)
  return wrap and math.max(1, width - key_width - gap) or nil
end

---Preferred column width: the widest unwrapped line, capped by max_column_width but never
---narrower than any group header or the key column with one description cell.
---@param groups CheatsheetDisplayGroup[]
---@param config CheatsheetConfig
---@param measure CheatsheetMeasure
---@return integer
function M.column_target(groups, config, measure)
  local gap = config.layout.key_gap
  local headers, keys, natural = 0, 0, 0
  for _, group in ipairs(groups) do
    local key = M.key_width({ group }, measure)
    headers = math.max(headers, measure(group.icon .. group.name))
    keys = math.max(keys, key + gap + 1)
    for _, mapping in ipairs(group.mappings) do
      natural = math.max(natural, key + gap + measure(mapping.desc))
    end
  end
  local lower = math.max(headers, keys)
  return math.max(lower, math.min(math.max(natural, headers), config.layout.max_column_width))
end

---@param mapping CheatsheetDisplayMapping
---@param desc_width? integer Wrap width for descriptions; nil keeps one line.
---@param measure CheatsheetMeasure
---@return string[]
local function descriptions(mapping, desc_width, measure)
  if not desc_width then
    return { mapping.desc }
  end
  local by_mapping = wrapped[measure] or setmetatable({}, { __mode = "k" })
  wrapped[measure] = by_mapping
  local by_width = by_mapping[mapping] or {}
  by_mapping[mapping] = by_width
  local key = desc_width .. "\0" .. mapping.desc
  by_width[key] = by_width[key] or text.wrap(mapping.desc, desc_width, measure)
  return by_width[key]
end

---Clip lines wider than the column and their spans so composed columns stay aligned.
---@param document CheatsheetDocument
---@param width integer
---@param measure CheatsheetMeasure
---@return CheatsheetDocument
function M.fit(document, width, measure)
  ---@type CheatsheetDocument
  local result = { lines = {}, spans = {} }
  for index, line in ipairs(document.lines) do
    result.lines[index] = measure(line) > width and text.clip(line, width, measure) or line
  end
  for _, item in ipairs(document.spans) do
    local length = #result.lines[item.row + 1]
    span(result, item.row, item.start_col, math.min(item.end_col, length), item.hl_group)
  end
  return result
end

---Lines of one mapping; continuation lines are indented under the description column.
---@param mapping CheatsheetDisplayMapping
---@param key_width integer
---@param gap integer
---@param desc_width? integer
---@param measure CheatsheetMeasure
---@return CheatsheetDocument
function M.mapping_lines(mapping, key_width, gap, desc_width, measure)
  ---@type CheatsheetDocument
  local result = { lines = {}, spans = {} }
  local parts = descriptions(mapping, desc_width, measure)
  local line, start_col, end_col, desc_col =
    M.mapping_line({ lhs = mapping.lhs, desc = parts[1] }, key_width, 0, measure, gap)
  result.lines[1] = line
  span(result, 0, start_col, end_col, "CheatsheetKey")
  span(result, 0, desc_col, #line, "CheatsheetDesc")
  local indent = string.rep(" ", key_width + gap)
  for index = 2, #parts do
    result.lines[index] = indent .. parts[index]
    span(result, index - 1, #indent, #result.lines[index], "CheatsheetDesc")
  end
  return result
end

---One group in coordinates relative to its column.
---@param group CheatsheetDisplayGroup
---@param key_width integer
---@param width integer Column width in cells.
---@param config CheatsheetConfig
---@param measure CheatsheetMeasure
---@param desc_width? integer
---@return CheatsheetDocument
function M.block(group, key_width, width, config, measure, desc_width)
  ---@type CheatsheetDocument
  local head = { lines = {}, spans = {} }
  local header = group.icon .. group.name
  local offset = M.offset(config.group_align, width, measure(header), 0)
  head.lines[1] = string.rep(" ", offset) .. header
  span(head, 0, offset, offset + #group.icon, "CheatsheetGroupIcon")
  span(head, 0, offset + #group.icon, offset + #header, "CheatsheetGroup")
  if config.group_underline then
    -- The box character is ambiguous-width; repeat it by cells rather than characters.
    head.lines[2] = string.rep("─", math.floor(width / math.max(1, measure("─"))))
    span(head, 1, 0, #head.lines[2], "CheatsheetSeparator")
  else
    head.lines[2] = ""
  end
  local rows = {}
  for _, mapping in ipairs(group.mappings) do
    rows[#rows + 1] = M.mapping_lines(mapping, key_width, config.layout.key_gap, desc_width, measure)
  end
  return columns.stack({ head, columns.stack(rows, config.layout.mapping_spacing) }, 0)
end

---Height of M.block without building its lines.
---@param group CheatsheetDisplayGroup
---@param config CheatsheetConfig
---@param measure CheatsheetMeasure
---@param desc_width? integer
---@return integer
function M.block_height(group, config, measure, desc_width)
  local height = 2 + config.layout.mapping_spacing * math.max(0, #group.mappings - 1)
  for _, mapping in ipairs(group.mappings) do
    height = height + #descriptions(mapping, desc_width, measure)
  end
  return height
end

---Height of a column holding a range of groups with the range's own key width.
---@param groups CheatsheetDisplayGroup[]
---@param range CheatsheetRange
---@param width integer
---@param config CheatsheetConfig
---@param measure CheatsheetMeasure
---@param wrap boolean
---@return integer
function M.column_height(groups, range, width, config, measure, wrap)
  local members = slice(groups, range)
  local desc_width = description_width(M.key_width(members, measure), config.layout.key_gap, width, wrap)
  local height = config.layout.group_spacing * (#members - 1)
  for _, group in ipairs(members) do
    height = height + M.block_height(group, config, measure, desc_width)
  end
  return height
end

---@param groups CheatsheetDisplayGroup[]
---@param range CheatsheetRange
---@param width integer
---@param config CheatsheetConfig
---@param measure CheatsheetMeasure
---@param wrap boolean
---@return CheatsheetDocument
function M.column(groups, range, width, config, measure, wrap)
  local members = slice(groups, range)
  local key_width = M.key_width(members, measure)
  local desc_width = description_width(key_width, config.layout.key_gap, width, wrap)
  local blocks = {}
  for _, group in ipairs(members) do
    blocks[#blocks + 1] = M.block(group, key_width, width, config, measure, desc_width)
  end
  local document = columns.stack(blocks, config.layout.group_spacing)
  return wrap and M.fit(document, width, measure) or document
end

---Measure screen cells through an injected function, but emit byte offsets for extmarks.
---@param groups CheatsheetDisplayGroup[]
---@param mode CheatsheetMode
---@param config CheatsheetConfig
---@param width integer
---@param measure CheatsheetMeasure
---@return CheatsheetDocument
function M.build(groups, mode, config, width, measure)
  ---@type CheatsheetDocument
  local result = { lines = {}, spans = {} }
  local pad, layout = config.window.padding, config.layout
  local content_width = math.max(1, width - pad.left - pad.right)
  ---@param line string
  ---@return integer
  local function append(line)
    local row = #result.lines
    result.lines[#result.lines + 1] = line
    return row
  end
  ---@param count integer
  ---@return nil
  local function blanks(count)
    for _ = 1, count do
      append(string.rep(" ", pad.left))
    end
  end
  blanks(pad.top)
  local label = M.mode_label(config.modes, mode)
  local offset = M.offset(config.mode_align, content_width, measure(label), pad.left)
  local row = append(string.rep(" ", offset) .. label)
  span(result, row, offset, offset + #label, "CheatsheetTitle")
  blanks(1)

  local count = 1
  if #groups == 0 then
    local message = "No mappings for " .. modes.names[mode] .. " mode"
    row = append(string.rep(" ", pad.left) .. message)
    span(result, row, pad.left, pad.left + #message, "CheatsheetDesc")
  else
    local limit = math.min(layout.max_columns, #groups)
    count = columns.count(content_width, M.column_target(groups, config, measure), layout.column_gap, limit)
    local column_width = columns.width(content_width, count, layout.column_gap)
    local wrap = count > 1
    local ranges = { { first = 1, last = #groups } }
    if wrap then
      ranges = columns.partition(#groups, count, function(first, last)
        return M.column_height(groups, { first = first, last = last }, column_width, config, measure, wrap)
      end)
    end
    local documents = {}
    for _, range in ipairs(ranges) do
      documents[#documents + 1] = M.column(groups, range, column_width, config, measure, wrap)
    end
    result =
      columns.stack({ result, columns.compose(documents, column_width, layout.column_gap, pad.left, measure) }, 0)
  end
  blanks(pad.bottom)
  result.columns = count
  return result
end

return M
