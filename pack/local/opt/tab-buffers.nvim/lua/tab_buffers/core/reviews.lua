local M = {}

---@return TabBuffersReviews
function M.new()
  ---@type table<integer, TabBuffersReviewRecord>
  local records = {}
  local registry = {}
  ---@cast registry TabBuffersReviews

  function registry.get(tab)
    local record = records[tab]
    return record and record.view or nil
  end

  function registry.observe(tab, view, original)
    local previous = records[tab]
    local record = { view = view, original = original, owned = original ~= true }
    if previous then
      record.original, record.owned = previous.original, previous.owned
    end
    records[tab] = record
    return original ~= true
  end

  function registry.close(tab, view, current)
    local record = records[tab]
    if not record or record.view ~= view then
      return false, current
    end
    records[tab] = nil
    if record.owned and current == true then
      return true, record.original
    end
    return false, current
  end

  function registry.prune(valid)
    for tab in pairs(records) do
      if not valid(tab) then
        records[tab] = nil
      end
    end
  end

  return registry
end

---@param tabs integer[]
---@param previous? integer
---@param available fun(tab: integer): boolean
---@return integer?
function M.destination(tabs, previous, available)
  if previous and available(previous) then
    return previous
  end
  for _, tab in ipairs(tabs) do
    if available(tab) then
      return tab
    end
  end
end

return M
