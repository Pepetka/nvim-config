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

---@param modes CheatsheetMode[]
---@param current CheatsheetMode
---@return string
function M.mode_label(modes, current)
  local parts = {}
  for _, mode in ipairs(modes) do
    parts[#parts + 1] = mode == current and "[" .. mode .. "] " or " " .. mode .. "  "
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
  local pad = config.window.padding
  local content_width = math.max(1, width - pad.left - pad.right)
  ---@param text string
  ---@return integer
  local function append(text)
    local row = #result.lines
    result.lines[#result.lines + 1] = text
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

  if #groups == 0 then
    local message = "No mappings for " .. mode .. " mode"
    row = append(string.rep(" ", pad.left) .. message)
    span(result, row, pad.left, pad.left + #message, "CheatsheetDesc")
  end
  local key_width = M.key_width(groups, measure)
  for group_index, group in ipairs(groups) do
    local header = group.icon .. group.name
    offset = M.offset(config.group_align, content_width, measure(header), pad.left)
    row = append(string.rep(" ", offset) .. header)
    span(result, row, offset, offset + #group.icon, "CheatsheetGroupIcon")
    span(result, row, offset + #group.icon, offset + #header, "CheatsheetGroup")
    if config.group_underline then
      local separator = string.rep("─", content_width)
      row = append(string.rep(" ", pad.left) .. separator)
      span(result, row, pad.left, pad.left + #separator, "CheatsheetSeparator")
    else
      blanks(1)
    end
    for index, mapping in ipairs(group.mappings) do
      local line, start_col, end_col, desc_col =
        M.mapping_line(mapping, key_width, pad.left, measure, config.layout.key_gap)
      row = append(line)
      span(result, row, start_col, end_col, "CheatsheetKey")
      span(result, row, desc_col, #line, "CheatsheetDesc")
      if index < #group.mappings then
        blanks(config.layout.mapping_spacing)
      end
    end
    if group_index < #groups then
      blanks(config.layout.group_spacing)
    end
  end
  blanks(pad.bottom)
  return result
end

return M
