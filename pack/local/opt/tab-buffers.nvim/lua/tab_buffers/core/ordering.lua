local validation = require("tab_buffers.core.validation")
local lists = require("tab_buffers.core.lists")
local integer, id, buffer_list = validation.integer, validation.id, validation.buffer_list
local copy, index_of, clamp = lists.copy, lists.index_of, lists.clamp
local M = {}

---@param model TabBuffersCore
---@param tabs table<integer, integer[]>
---@param writable fun(): nil
---@param set_order fun(tab: integer, ordered: integer[]): boolean
---@param set_sorting fun(value: boolean): nil
---@return nil
function M.install(model, tabs, writable, set_order, set_sorting)
  function model:move_to(tab, buf, index)
    writable()
    id(tab, "tab")
    id(buf, "buf")
    integer(index, "index")
    local buffers = tabs[tab] or {}
    local current = index_of(buffers, buf)
    if not current then
      return false
    end
    local destination = clamp(index, #buffers)
    if destination == current then
      return false
    end
    local ordered = copy(buffers)
    table.remove(ordered, current)
    table.insert(ordered, destination, buf)
    return set_order(tab, ordered)
  end

  function model:move(tab, buf, offset)
    writable()
    id(tab, "tab")
    id(buf, "buf")
    integer(offset, "offset")
    local current = index_of(tabs[tab] or {}, buf)
    if not current then
      return false
    end
    return self:move_to(tab, buf, current + offset)
  end

  function model:reorder(tab, buffers)
    writable()
    id(tab, "tab")
    local ordered = buffer_list(buffers)
    local seen = {}
    for _, buf in ipairs(ordered) do
      assert(not seen[buf], "reorder contains duplicate buffers")
      seen[buf] = true
    end
    local previous = tabs[tab]
    if not previous then
      return false
    end
    assert(#ordered == #previous, "reorder must contain exactly the tab's buffers")
    for _, buf in ipairs(previous) do
      assert(seen[buf], "reorder must contain exactly the tab's buffers")
    end
    return set_order(tab, ordered)
  end

  function model:sort(tab, less)
    writable()
    id(tab, "tab")
    assert(type(less) == "function", "less must be a function")
    local buffers = tabs[tab] or {}
    if #buffers < 2 then
      return false
    end
    local ranked = {}
    for i, buf in ipairs(buffers) do
      ranked[i] = { buf = buf, index = i }
    end
    -- Sort a private copy, and forbid comparator callbacks from changing this model.
    set_sorting(true)
    local ok, err = pcall(table.sort, ranked, function(a, b)
      if less(a.buf, b.buf) then
        return true
      end
      if less(b.buf, a.buf) then
        return false
      end
      return a.index < b.index
    end)
    set_sorting(false)
    if not ok then
      error(err, 0)
    end
    local ordered = {}
    for i, item in ipairs(ranked) do
      ordered[i] = item.buf
    end
    return set_order(tab, ordered)
  end

  function model:neighbor(tab, buf, offset, wrap)
    id(tab, "tab")
    id(buf, "buf")
    integer(offset, "offset")
    assert(wrap == nil or type(wrap) == "boolean", "wrap must be a boolean")
    local buffers = tabs[tab] or {}
    local current = index_of(buffers, buf)
    if not current then
      return nil
    end
    local destination = current + offset
    if wrap ~= false then
      -- Reduce first so large offsets cannot round away the starting position.
      destination = ((current - 1 + (offset % #buffers)) % #buffers) + 1
    end
    return buffers[destination]
  end

  function model:replacement(tab, buf)
    return self:neighbor(tab, buf, 1, false) or self:neighbor(tab, buf, -1, false)
  end
end

return M
