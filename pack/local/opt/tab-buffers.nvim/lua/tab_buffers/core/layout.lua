local lists = require("tab_buffers.core.lists")
local M = {}

---@param text string
---@return string
function M.clean(text)
  return (text:gsub("[%c]", " "))
end

---Shorten from the left using screen cells, keeping combining marks with their base.
---@param text string
---@param width integer
---@param metrics TabBuffersTextMetrics
---@return string
function M.clip(text, width, metrics)
  if width <= 0 then
    return ""
  end
  if metrics.measure(text) <= width then
    return text
  end
  local ellipsis_width = metrics.measure("…")
  if width < ellipsis_width then
    return ""
  end
  local count = metrics.length(text)
  -- ASCII suffix widths are monotone; retain exact sequential behavior for Unicode
  -- grapheme sequences, whose widths can change when their leading base is removed.
  if not text:find("[\128-\255]") then
    local first, last = 1, count
    while first < last do
      local middle = math.floor((first + last) / 2)
      if metrics.measure(metrics.suffix(text, middle)) <= width - ellipsis_width then
        last = middle
      else
        first = middle + 1
      end
    end
    return "…" .. metrics.suffix(text, first)
  end
  for first = 1, count do
    local suffix = metrics.suffix(text, first)
    if metrics.measure(suffix) <= width - ellipsis_width then
      return "…" .. suffix
    end
  end
  return "…"
end

---Minimal distinct path suffixes; entries have id and name fields.
---@param entries TabBuffersLabelEntry[]
---@return table<integer, string>
function M.labels(entries)
  local paths, counts, labels, suffixes = {}, {}, {}, {}
  for _, entry in ipairs(entries) do
    local path = M.clean(entry.name)
    paths[entry.id] = path
    suffixes[path] = (suffixes[path] or 0) + 1
    for position in path:gmatch("()/") do
      local suffix = path:sub(position + 1)
      suffixes[suffix] = (suffixes[suffix] or 0) + 1
    end
    local name = path == "" and "[No Name]" or path:match("[^/]+$") or path
    counts[name] = (counts[name] or 0) + 1
  end
  for _, entry in ipairs(entries) do
    local path = paths[entry.id]
    local name = path == "" and "[No Name]" or path:match("[^/]+$") or path
    if counts[name] > 1 then
      if path == "" then
        name = name .. " " .. entry.id
      else
        local parts = {}
        for part in path:gmatch("[^/]+") do
          parts[#parts + 1] = part
        end
        for length = 2, #parts do
          local candidate = table.concat(parts, "/", #parts - length + 1)
          local unique = suffixes[candidate] == 1
          name = candidate
          if unique then
            break
          end
        end
      end
    end
    labels[entry.id] = name
  end
  -- Identical sanitized paths and labels resembling unnamed placeholders still need distinct IDs.
  while true do
    local collisions, changed = {}, false
    for _, name in pairs(labels) do
      collisions[name] = (collisions[name] or 0) + 1
    end
    for id, name in pairs(labels) do
      if collisions[name] > 1 then
        labels[id], changed = name .. " [" .. id .. "]", true
      end
    end
    if not changed then
      break
    end
  end
  return labels
end

---Keep clipped labels distinct whenever the available width can hold the ID marker.
---@param entries TabBuffersLabelEntry[]
---@param width integer
---@param metrics TabBuffersTextMetrics
---@return table<integer, string>
function M.clipped_labels(entries, width, metrics)
  local labels, clipped, counts = M.labels(entries), {}, {}
  for id, name in pairs(labels) do
    clipped[id] = M.clip(name, width, metrics)
    counts[clipped[id]] = (counts[clipped[id]] or 0) + 1
  end
  -- Use IDs for the entire set when clipping collides, so a real filename cannot
  -- imitate the marker assigned to another entry.
  for _, count in pairs(counts) do
    if count > 1 then
      for id, name in pairs(labels) do
        local marker = "[" .. id .. "]"
        local room = width - metrics.measure(marker)
        clipped[id] = room >= 0 and M.clip(name, room, metrics) .. marker or M.clip(marker, width, metrics)
      end
      break
    end
  end
  return clipped
end

---Fit a contiguous range around the anchor, reserving cells for hidden-side markers.
---@generic T: TabBuffersTextItem
---@param items T[]
---@param anchor? integer
---@param width integer
---@param metrics TabBuffersTextMetrics
---@return T[] items, string? before, string? after
function M.fit(items, anchor, width, metrics)
  local source = items
  ---@cast source TabBuffersTextItem[]
  if #items == 0 or width <= 0 then
    return {}, nil, nil
  end
  anchor = math.max(1, math.min(anchor or 1, #items))
  local first, last = anchor, anchor
  local used = metrics.measure(source[anchor].text)
  ---@param left integer
  ---@param right integer
  ---@return string?, string?
  local function markers(left, right)
    return left > 1 and "«" .. (left - 1) .. " " or nil, right < #items and " " .. (#items - right) .. "»" or nil
  end
  ---@param before? string
  ---@param after? string
  ---@return integer
  local function marker_width(before, after)
    return metrics.measure(before or "") + metrics.measure(after or "")
  end
  ---@param left integer
  ---@param right integer
  ---@param cells integer
  ---@return integer
  local function needed(left, right, cells)
    return cells + marker_width(markers(left, right))
  end
  while true do
    local expanded = false
    if first > 1 then
      local extra = metrics.measure(source[first - 1].text)
      if needed(first - 1, last, used + extra) <= width then
        first, used, expanded = first - 1, used + extra, true
      end
    end
    if last < #items then
      local extra = metrics.measure(source[last + 1].text)
      if needed(first, last + 1, used + extra) <= width then
        last, used, expanded = last + 1, used + extra, true
      end
    end
    if not expanded then
      break
    end
  end
  local before, after = markers(first, last)
  -- Compact arrows remain visible when counts would crowd out the active label.
  if width < 3 + marker_width(before, after) then
    before, after = before and "«" or nil, after and "»" or nil
  end
  if width < 1 + marker_width(before, after) then
    before, after = nil, nil
  end
  local room = width - marker_width(before, after)
  local result = {}
  for index = first, last do
    local item = lists.copy(items[index])
    if first == last then
      item.text = M.clip(item.text, room, metrics)
      ---@type string?
      local border = source[index].text:sub(1, #"│")
      border = (border == "│" or border == "▎") and border or nil
      -- Keep the boundary visible even when the item itself needs shortening.
      if border and room > metrics.measure(border) then
        item.text = border .. M.clip(source[index].text:sub(#border + 1), room - metrics.measure(border), metrics)
      end
    end
    result[#result + 1] = item
  end
  return result, before, after
end

return M
