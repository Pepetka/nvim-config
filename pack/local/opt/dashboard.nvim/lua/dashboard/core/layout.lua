local blocks = require("dashboard.core.blocks")
local key_rules = require("dashboard.core.keys")
local M = {}

---@param available integer
---@param used integer
---@param alignment DashboardAlign | DashboardVerticalAlign
---@param round_up? boolean Prefer the right cell for an indivisible inner horizontal margin.
---@return integer
function M.offset(available, used, alignment, round_up)
  local spare = math.max(0, available - used)
  if alignment == "center" then
    return round_up and math.ceil(spare / 2) or math.floor(spare / 2)
  end
  return (alignment == "right" or alignment == "bottom") and spare or 0
end

---@param fragments DashboardDocument[]
---@param measure DashboardMeasure
---@return integer
function M.content_width(fragments, measure)
  local width = 0
  for _, fragment in ipairs(fragments) do
    for _, line in ipairs(fragment.lines) do
      width = math.max(width, measure(line))
    end
  end
  return width
end

---@param document DashboardDocument
---@param count integer
---@return nil
function M.gap(document, count)
  for _ = 1, count do
    document.lines[#document.lines + 1] = ""
  end
end

---@param fragments DashboardDocument[]
---@param ids string[]
---@param context DashboardContext
---@param options DashboardLayout
---@param measure DashboardMeasure
---@param normalize_key? DashboardKeyNormalizer
---@param extra? DashboardComposeOptions
---@return DashboardDocument
function M.compose(fragments, ids, context, options, measure, normalize_key, extra)
  local result = blocks.empty()
  local width = M.content_width(fragments, measure)
  local left = M.offset(context.width, width, options.horizontal)
  normalize_key = normalize_key or key_rules.normalize
  extra = extra or {}
  local keys = key_rules.reserved(extra.navigation or key_rules.defaults(), normalize_key)
  for index, fragment in ipairs(fragments) do
    if #fragment.lines > 0 then
      local block_layout = extra.block_layouts and extra.block_layouts[index] or {}
      if #result.lines > 0 then
        M.gap(result, options.gap)
      end
      M.gap(result, block_layout.gap_before or 0)
      local base = #result.lines
      local offsets = {}
      for row, line in ipairs(fragment.lines) do
        -- Round the shared origin once so odd/even window widths cannot shift blocks relative to each other.
        local padding = math.max(
          0,
          left
            + M.offset(width, measure(line), block_layout.align or options.horizontal, true)
            + (block_layout.offset_x or 0)
        )
        offsets[row] = padding
        result.lines[#result.lines + 1] = string.rep(" ", padding) .. line
      end
      for _, span in ipairs(fragment.spans) do
        local shift = offsets[span.row + 1]
        blocks.span(result, base + span.row, shift + span.start_col, shift + span.end_col, span.style)
      end
      for _, target in ipairs(fragment.targets) do
        if target.key then
          key_rules.claim(keys, target.key, normalize_key, "duplicate or reserved action key")
        end
        result.targets[#result.targets + 1] = {
          id = target.id,
          block_id = ids[index],
          row = base + target.row,
          col = offsets[target.row + 1] + target.col,
          key = target.key,
          run = target.run,
        }
      end
      M.gap(result, block_layout.gap_after or 0)
    end
  end
  if #result.lines == 0 then
    result.lines = { "" }
    return result
  end
  local top = M.offset(math.max(1, context.height - options.bottom_padding), #result.lines, options.vertical)
  if top == 0 then
    return result
  end
  local lines = {}
  for _ = 1, top do
    lines[#lines + 1] = ""
  end
  for _, line in ipairs(result.lines) do
    lines[#lines + 1] = line
  end
  result.lines = lines
  for _, span in ipairs(result.spans) do
    span.row = span.row + top
  end
  for _, target in ipairs(result.targets) do
    target.row = target.row + top
  end
  return result
end

return M
