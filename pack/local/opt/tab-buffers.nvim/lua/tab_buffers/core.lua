local M = {}

local function integer(value, name)
  assert(
    type(value) == "number" and value > -math.huge and value < math.huge and value == math.floor(value),
    name .. " must be a finite integer"
  )
end

local function id(value, name)
  integer(value, name)
  assert(value > 0, name .. " must be positive")
end

local function copy(list)
  local result = {}
  for i, value in ipairs(list) do
    result[i] = value
  end
  return result
end

local function index_of(list, value)
  for i, item in ipairs(list) do
    if item == value then
      return i
    end
  end
end

local function clamp(value, maximum)
  return math.max(1, math.min(value, maximum))
end

local function buffer_list(value)
  assert(type(value) == "table", "buffers must be a dense list")
  local count = 0
  for key in pairs(value) do
    id(key, "list index")
    count = count + 1
  end
  local result = {}
  for i = 1, count do
    id(value[i], "buf")
    result[i] = value[i]
  end
  return result
end

---@class TabBuffersCore
---@field ensure_tab fun(self: TabBuffersCore, tab: integer): boolean
---@field tabs fun(self: TabBuffersCore): integer[]
---@field buffers fun(self: TabBuffersCore, tab: integer): integer[]
---@field contains fun(self: TabBuffersCore, tab: integer, buf: integer): boolean
---@field owners fun(self: TabBuffersCore, buf: integer): integer[]
---@field attach fun(self: TabBuffersCore, tab: integer, buf: integer, index?: integer): boolean
---@field detach fun(self: TabBuffersCore, tab: integer, buf: integer): boolean, boolean
---@field transfer fun(self: TabBuffersCore, from: integer, to: integer, buf: integer, index?: integer): boolean
---@field forget_buffer fun(self: TabBuffersCore, buf: integer): integer[]
---@field remove_tab fun(self: TabBuffersCore, tab: integer): TabBuffersRemovedTab
---@field move_to fun(self: TabBuffersCore, tab: integer, buf: integer, index: integer): boolean
---@field move fun(self: TabBuffersCore, tab: integer, buf: integer, offset: integer): boolean
---@field reorder fun(self: TabBuffersCore, tab: integer, buffers: integer[]): boolean
---@field sort fun(self: TabBuffersCore, tab: integer, less: fun(a: integer, b: integer): boolean): boolean
---@field neighbor fun(self: TabBuffersCore, tab: integer, buf: integer, offset: integer, wrap?: boolean): integer?
---@field replacement fun(self: TabBuffersCore, tab: integer, buf: integer): integer?
---@field targets fun(self: TabBuffersCore, tab: integer, mode: TabBuffersTargetMode, pivot?: integer): integer[]
---@field plan_close fun(self: TabBuffersCore, tab: integer, buffers: integer[]): TabBuffersClosePlan

---@alias TabBuffersTargetMode "one"|"all"|"others"|"left"|"right"

---@class TabBuffersClosePlan
---@field buffers integer[] Selected members, deduplicated and in tab order.
---@field shared integer[] Selected buffers that also belong to another tab.
---@field exclusive integer[] Selected buffers whose only owner is this tab.
---@field remaining integer[] Unselected buffers in tab order.

---@class TabBuffersRemovedTab
---@field buffers integer[] Previous buffers in tab order.
---@field orphans integer[] Buffers with no remaining owners, in previous tab order.

---Create an isolated ownership model. IDs are opaque positive integers.
---No methods consult Neovim or retain caller-owned lists.
---@return TabBuffersCore
function M.new()
  ---@type table<integer, integer[]>
  local tabs = {}
  local model = {}
  local sorting = false

  local function writable()
    assert(not sorting, "model cannot be changed by a sort comparator")
  end

  local function set_order(tab, ordered)
    local previous = tabs[tab]
    for i, buf in ipairs(ordered) do
      if previous[i] ~= buf then
        tabs[tab] = ordered
        return true
      end
    end
    return false
  end

  function model:ensure_tab(tab)
    writable()
    id(tab, "tab")
    if tabs[tab] then
      return false
    end
    tabs[tab] = {}
    return true
  end

  function model:tabs()
    local result = {}
    for tab in pairs(tabs) do
      result[#result + 1] = tab
    end
    table.sort(result)
    return result
  end

  function model:buffers(tab)
    id(tab, "tab")
    return copy(tabs[tab] or {})
  end

  function model:contains(tab, buf)
    id(tab, "tab")
    id(buf, "buf")
    return index_of(tabs[tab] or {}, buf) ~= nil
  end

  function model:owners(buf)
    id(buf, "buf")
    local result = {}
    for tab, buffers in pairs(tabs) do
      if index_of(buffers, buf) then
        result[#result + 1] = tab
      end
    end
    table.sort(result)
    return result
  end

  function model:attach(tab, buf, index)
    writable()
    id(tab, "tab")
    id(buf, "buf")
    if index ~= nil then
      integer(index, "index")
    end
    if self:contains(tab, buf) then
      return false
    end
    self:ensure_tab(tab)
    local buffers = tabs[tab]
    table.insert(buffers, clamp(index or (#buffers + 1), #buffers + 1), buf)
    return true
  end

  function model:detach(tab, buf)
    writable()
    id(tab, "tab")
    id(buf, "buf")
    local buffers = tabs[tab] or {}
    local index = index_of(buffers, buf)
    if not index then
      return false, false
    end
    table.remove(buffers, index)
    return true, #self:owners(buf) == 0
  end

  function model:transfer(from, to, buf, index)
    writable()
    id(from, "from")
    id(to, "to")
    id(buf, "buf")
    if index ~= nil then
      integer(index, "index")
    end
    if from == to or not self:contains(from, buf) then
      return false
    end
    self:attach(to, buf, index)
    self:detach(from, buf)
    return true
  end

  function model:forget_buffer(buf)
    writable()
    id(buf, "buf")
    local affected = self:owners(buf)
    for _, tab in ipairs(affected) do
      self:detach(tab, buf)
    end
    return affected
  end

  function model:remove_tab(tab)
    writable()
    id(tab, "tab")
    local buffers = self:buffers(tab)
    tabs[tab] = nil
    local orphans = {}
    for _, buf in ipairs(buffers) do
      if #self:owners(buf) == 0 then
        orphans[#orphans + 1] = buf
      end
    end
    return { buffers = buffers, orphans = orphans }
  end

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
    sorting = true
    local ok, err = pcall(table.sort, ranked, function(a, b)
      if less(a.buf, b.buf) then
        return true
      end
      if less(b.buf, a.buf) then
        return false
      end
      return a.index < b.index
    end)
    sorting = false
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

  function model:targets(tab, mode, pivot)
    id(tab, "tab")
    local modes = { one = true, all = true, others = true, left = true, right = true }
    assert(type(mode) == "string" and modes[mode], "unknown target mode")
    if pivot ~= nil then
      id(pivot, "pivot")
    end
    local buffers = tabs[tab] or {}
    if mode == "all" then
      return copy(buffers)
    end
    local current = index_of(buffers, pivot)
    if not current then
      return {}
    end
    local result = {}
    for i, buf in ipairs(buffers) do
      if
        (mode == "one" and i == current)
        or (mode == "others" and i ~= current)
        or (mode == "left" and i < current)
        or (mode == "right" and i > current)
      then
        result[#result + 1] = buf
      end
    end
    return result
  end

  ---Produce a snapshot, not an executable transaction. Recheck owners before
  ---performing external deletion, then detach only successful targets.
  function model:plan_close(tab, buffers)
    id(tab, "tab")
    local selected = {}
    for _, buf in ipairs(buffer_list(buffers)) do
      selected[buf] = true
    end
    ---@type TabBuffersClosePlan
    local plan = { buffers = {}, shared = {}, exclusive = {}, remaining = {} }
    for _, buf in ipairs(tabs[tab] or {}) do
      if selected[buf] then
        plan.buffers[#plan.buffers + 1] = buf
        local owners = #self:owners(buf) > 1 and plan.shared or plan.exclusive
        owners[#owners + 1] = buf
      else
        plan.remaining[#plan.remaining + 1] = buf
      end
    end
    return plan
  end

  return model
end

return M
