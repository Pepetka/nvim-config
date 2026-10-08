local M = {}

function M.clean(text)
  return text:gsub("[%c]", " ")
end

---Shorten from the left using screen cells, keeping combining marks with their base.
function M.clip(text, width)
  if width <= 0 then
    return ""
  end
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  local count = vim.fn.strchars(text, true)
  for first = 1, count do
    local suffix = vim.fn.strcharpart(text, first, count, true)
    if vim.fn.strdisplaywidth(suffix) <= width - 1 then
      return "…" .. suffix
    end
  end
  return "…"
end

---Minimal distinct path suffixes; entries have id and name fields.
function M.labels(entries)
  local labels, counts = {}, {}
  for _, entry in ipairs(entries) do
    local name = entry.name == "" and "[No Name]" or vim.fs.basename(entry.name)
    counts[name] = (counts[name] or 0) + 1
  end
  for _, entry in ipairs(entries) do
    local name = entry.name == "" and "[No Name]" or vim.fs.basename(entry.name)
    if counts[name] > 1 then
      if entry.name == "" then
        name = name .. " " .. entry.id
      else
        local parts = vim.split(entry.name, "/", { trimempty = true })
        for length = 2, #parts do
          local candidate = table.concat(parts, "/", #parts - length + 1)
          local unique = true
          for _, other in ipairs(entries) do
            if
              other.id ~= entry.id and (other.name == candidate or other.name:sub(-#candidate - 1) == "/" .. candidate)
            then
              unique = false
              break
            end
          end
          name = candidate
          if unique then
            break
          end
        end
      end
    end
    labels[entry.id] = M.clean(name)
  end
  return labels
end

---Fit a contiguous range around the anchor, reserving cells for hidden-side markers.
---@return table[] items, string? before, string? after
function M.fit(items, anchor, width)
  if #items == 0 or width <= 0 then
    return {}, nil, nil
  end
  anchor = math.max(1, math.min(anchor or 1, #items))
  local first, last = anchor, anchor
  local used = vim.fn.strdisplaywidth(items[anchor].text)
  local function markers(left, right)
    return left > 1 and "«" .. (left - 1) .. " " or nil, right < #items and " " .. (#items - right) .. "»" or nil
  end
  local function marker_width(before, after)
    return vim.fn.strdisplaywidth(before or "") + vim.fn.strdisplaywidth(after or "")
  end
  local function needed(left, right, cells)
    return cells + marker_width(markers(left, right))
  end
  while true do
    local expanded = false
    if first > 1 then
      local extra = vim.fn.strdisplaywidth(items[first - 1].text)
      if needed(first - 1, last, used + extra) <= width then
        first, used, expanded = first - 1, used + extra, true
      end
    end
    if last < #items then
      local extra = vim.fn.strdisplaywidth(items[last + 1].text)
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
    local item = vim.tbl_extend("force", {}, items[index])
    if first == last then
      item.text = M.clip(item.text, room)
      local border = items[index].text:sub(1, #"│")
      border = (border == "│" or border == "▎") and border or nil
      -- Keep the boundary visible even when the item itself needs shortening.
      if border and room > 1 then
        item.text = border .. M.clip(items[index].text:sub(#border + 1), room - 1)
      end
    end
    result[#result + 1] = item
  end
  return result, before, after
end

return M
