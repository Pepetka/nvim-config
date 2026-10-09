local M = {}

---Reserve every positional match before considering formatter recovery. Otherwise
---an inserted duplicate can steal the identity of an original header further down.
---@param old StableFoldsPosition[]
---@param headers StableFoldsHeader[]
---@param new_folds boolean Whether unmatched starts came from an edit to an existing snapshot.
---@return StableFoldsMarkPlan
function M.match(old, headers, new_folds)
  ---@type table<integer, StableFoldsPosition[]>
  local positions = {}
  ---@type table<string, integer>
  local old_counts, new_counts = {}, {}
  ---@type table<string, StableFoldsPosition>
  local unique = {}
  for _, mark in ipairs(old) do
    old_counts[mark.header] = (old_counts[mark.header] or 0) + 1
    unique[mark.header] = mark
    if mark.line then
      positions[mark.line] = positions[mark.line] or {}
      table.insert(positions[mark.line], mark)
    end
  end
  for _, header in ipairs(headers) do
    new_counts[header.header] = (new_counts[header.header] or 0) + 1
  end
  ---@type table<integer, boolean>
  local used = {}
  ---@type table<integer, StableFoldsPosition>
  local selected = {}
  for index, header in ipairs(headers) do
    local candidate, count = nil, 0
    for _, mark in ipairs(positions[header.line] or {}) do
      if mark.header == header.header then
        candidate, count = mark, count + 1
      end
    end
    if count == 1 and candidate then
      selected[index], used[candidate.id] = candidate, true
    end
  end
  ---@type StableFoldsMarkPlan
  local plan = { marks = {}, delete = {} }
  for index, header in ipairs(headers) do
    local mark = selected[index]
    if not mark and old_counts[header.header] == 1 and new_counts[header.header] == 1 then
      local candidate = unique[header.header]
      if candidate and not used[candidate.id] then
        mark, used[candidate.id] = candidate, true
      end
    end
    plan.marks[#plan.marks + 1] = {
      line = header.line,
      header = header.header,
      id = mark and mark.id or nil,
      new = mark and mark.new or (mark == nil and new_folds),
      unchanged = mark ~= nil and mark.line == header.line or nil,
    }
  end
  for _, mark in ipairs(old) do
    if not used[mark.id] then
      plan.delete[#plan.delete + 1] = mark.id
    end
  end
  return plan
end

---Native folds shift before on_bytes; extmarks shift after it. Translate the
---old header positions to query the still-existing native manual state.
---@param positions StableFoldsPosition[]
---@param edit? StableFoldsEdit
---@return StableFoldsPosition[]
function M.shifted(positions, edit)
  if not edit or edit.new_rows == edit.old_rows then
    return positions
  end
  local result = {}
  for _, mark in ipairs(positions) do
    local line = mark.line
    local boundary = edit.start_row + 1
    if line and (line > boundary or (line == boundary and line > 1 and edit.start_col == 0)) then
      line = math.max(edit.start_row + 1, line + edit.new_rows - edit.old_rows)
    end
    result[#result + 1] = { id = mark.id, header = mark.header, new = mark.new, line = line, old_line = mark.line }
  end
  return result
end

---Map pre-edit window state to the current visible starts by stable identity.
---@param positions StableFoldsPosition[]
---@param states? table<integer, boolean>
---@param levels string[]
---@return StableFoldsFoldState[]
function M.restore(positions, states, levels)
  local result = {}
  for _, mark in ipairs(positions) do
    local closed = states and states[mark.id]
    if closed ~= nil and mark.line and (levels[mark.line] or ""):sub(1, 1) == ">" then
      result[#result + 1] = { line = mark.line, closed = closed }
    end
  end
  table.sort(result, function(a, b)
    return a.line < b.line
  end)
  return result
end

return M
