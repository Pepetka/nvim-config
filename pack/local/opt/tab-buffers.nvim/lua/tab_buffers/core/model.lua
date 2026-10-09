local validation = require("tab_buffers.core.validation")
local lists = require("tab_buffers.core.lists")
local integer, id = validation.integer, validation.id
local copy, index_of, clamp = lists.copy, lists.index_of, lists.clamp
local ordering = require("tab_buffers.core.ordering")
local selection = require("tab_buffers.core.selection")
local M = {}

---Create an isolated ownership model. IDs are opaque positive integers.
---No methods consult Neovim or retain caller-owned lists.
---@return TabBuffersCore
function M.new()
  ---@type table<integer, integer[]>
  local tabs = {}
  ---@type table<integer, table<integer, boolean>>
  local memberships = {}
  ---@type table<integer, table<integer, boolean>>
  local ownership = {}
  local model = {}
  ---@cast model TabBuffersCore
  local sorting = false

  ---@return nil
  local function writable()
    assert(not sorting, "model cannot be changed by a sort comparator")
  end

  ---@param tab integer
  ---@param ordered integer[]
  ---@return boolean
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
    tabs[tab], memberships[tab] = {}, {}
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
    return memberships[tab] ~= nil and memberships[tab][buf] == true
  end

  function model:owners(buf)
    id(buf, "buf")
    local result = {}
    for tab in pairs(ownership[buf] or {}) do
      result[#result + 1] = tab
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
    memberships[tab][buf] = true
    ownership[buf] = ownership[buf] or {}
    ownership[buf][tab] = true
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
    memberships[tab][buf] = nil
    ownership[buf][tab] = nil
    local orphan = next(ownership[buf]) == nil
    if orphan then
      ownership[buf] = nil
    end
    return true, orphan
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
    tabs[tab], memberships[tab] = nil, nil
    local orphans = {}
    for _, buf in ipairs(buffers) do
      ownership[buf][tab] = nil
      if next(ownership[buf]) == nil then
        ownership[buf] = nil
        orphans[#orphans + 1] = buf
      end
    end
    return { buffers = buffers, orphans = orphans }
  end

  ordering.install(model, tabs, writable, set_order, function(value)
    sorting = value
  end)
  selection.install(model, tabs)
  return model
end

return M
