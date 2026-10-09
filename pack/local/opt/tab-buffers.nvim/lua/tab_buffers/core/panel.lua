local layout = require("tab_buffers.core.layout")
local lists = require("tab_buffers.core.lists")
local config_rules = require("tab_buffers.core.config")
local M = {}

---@param snapshot TabBuffersPanelSnapshot
---@param config TabBuffersTablineConfig
---@return integer
function M.visibility(snapshot, config)
  if config.visibility == "never" or config_rules.contains(config.hide_filetypes, snapshot.filetype) then
    return 0
  end
  return (config.visibility == "always" or #snapshot.entries > 1 or #snapshot.tabs > 1) and 2 or 0
end

---@param windows TabBuffersSidebar[]
---@param columns integer
---@param height integer
---@param filetypes string[]
---@return integer left, integer right
function M.offsets(windows, columns, height, filetypes)
  local left, right = 0, 0
  for _, win in ipairs(windows) do
    if win.ordinary and config_rules.contains(filetypes, win.filetype) and win.height >= height - 1 then
      if win.column == 0 then
        left = math.max(left, win.width + 1)
      elseif win.column + win.width >= columns then
        right = math.max(right, win.width + 1)
      end
    end
  end
  return left, right
end

---@param snapshot TabBuffersPanelSnapshot
---@param config TabBuffersTablineConfig
---@param previous table<integer, integer>
---@param serial integer
---@param metrics TabBuffersTextMetrics
---@param prepared_labels? table<integer, string>
---@return TabBuffersPanelDocument
function M.build(snapshot, config, previous, serial, metrics, prepared_labels)
  local last_active = lists.copy(previous)
  local next_target, cached, visibility = serial, "", 0
  ---@param item TabBuffersPanelItem
  ---@param map table<integer, TabBuffersPanelItem>
  ---@return string
  local function segment(item, map)
    next_target = next_target + 1
    map[next_target] = item
    local text = item.text:gsub("%%", "%%%%")
    local border = item.text:sub(1, #"│")
    if border == "│" or border == "▎" then
      text = "%#TabBuffers"
        .. (item.active and "ActiveBorder" or "Border")
        .. "#"
        .. border
        .. "%#TabBuffers"
        .. item.highlight
        .. "#"
        .. text:sub(#border + 1)
    end
    return string.format(
      "%%#TabBuffers%s#%%%d@v:lua.require'tab_buffers.tabline'.click@%s%%X",
      item.highlight,
      next_target,
      text
    )
  end

  ---@param items TabBuffersPanelItem[]
  ---@param before? string
  ---@param after? string
  ---@param map table<integer, TabBuffersPanelItem>
  ---@return string
  local function block(items, before, after, map)
    local result = { "%#TabBuffersOverflow#", before or "" }
    for _, item in ipairs(items) do
      result[#result + 1] = segment(item, map)
    end
    result[#result + 1] = "%#TabBuffersOverflow#" .. (after or "")
    return table.concat(result)
  end

  ---@param items TabBuffersTextItem[]
  ---@param before? string
  ---@param after? string
  ---@return integer
  local function width(items, before, after)
    local total = metrics.measure(before or "") + metrics.measure(after or "")
    for _, item in ipairs(items) do
      total = total + metrics.measure(item.text)
    end
    return total
  end

  ---@return TabBuffersPanelDocument
  local function build()
    local tab = snapshot.tab
    local members, tabs = {}, snapshot.tabs
    local active, visible, entries = snapshot.active, snapshot.visible, snapshot.entries
    for _, entry in ipairs(entries) do
      members[#members + 1] = entry.id
    end
    ---@param buf integer
    ---@return boolean
    local function contains(buf)
      return lists.index_of(members, buf) ~= nil
    end
    if active then
      last_active[tab] = active
    elseif last_active[tab] and contains(last_active[tab]) then
      active = last_active[tab]
    else
      for _, buf in ipairs(members) do
        if visible[buf] then
          active = buf
          break
        end
      end
      active = active or members[1]
      last_active[tab] = active
    end
    for saved in pairs(last_active) do
      if not lists.index_of(tabs, saved) then
        last_active[saved] = nil
      end
    end
    visibility = M.visibility(snapshot, config)
    local labels, anchor = prepared_labels or layout.clipped_labels(entries, config.max_name_length, metrics), 1
    ---@type TabBuffersPanelItem[]
    local items = {}
    for index, entry in ipairs(entries) do
      local icon = ""
      if config.icons then
        icon = entry.icon
      end
      local selected = entry.id == active
      if selected then
        anchor = index
      end
      items[#items + 1] = {
        kind = "buffer",
        id = entry.id,
        tab = tab,
        active = selected,
        highlight = selected and "Active" or visible[entry.id] and "Visible" or "Buffer",
        text = (selected and "▎ " or "│ ")
          .. (icon ~= "" and icon .. " " or "")
          .. labels[entry.id]
          .. (entry.modified and " ●" or "")
          .. " ",
      }
    end
    local tab_anchor = 1
    ---@type TabBuffersPanelItem[]
    local tab_items = {}
    if #tabs > 1 then
      for index, handle in ipairs(tabs) do
        local selected = handle == tab
        if selected then
          tab_anchor = index
        end
        tab_items[#tab_items + 1] = {
          kind = "tab",
          tab = handle,
          active = selected,
          highlight = selected and "TabActive" or "Tab",
          text = (selected and "▎ " or "│ ") .. (snapshot.reviews[handle] and "󰊢 " or "") .. index .. " ",
        }
      end
    end
    local left, right = snapshot.left, snapshot.right
    left = math.min(left, math.max(0, snapshot.columns - 1))
    right = math.min(right, math.max(0, snapshot.columns - left - 1))
    local padding = math.min(config.padding, math.floor(math.max(0, snapshot.columns - left - right - 1) / 2))
    left, right = left + padding, right + padding
    local available = math.max(0, snapshot.columns - left - right)
    local tab_budget =
      math.min(available - (#items > 0 and 1 or 0), math.max(4, math.floor(available * config.tab_width_ratio)))
    local fitted_tabs, tb, ta = layout.fit(tab_items, tab_anchor, tab_budget, metrics)
    local tab_width = width(fitted_tabs, tb, ta)
    local fitted, before, after = layout.fit(items, anchor, available - tab_width, metrics)
    local map = {}
    cached = "%#TabBuffersOffset#"
      .. string.rep(" ", left)
      .. block(fitted, before, after, map)
      .. "%#TabBuffersFill#%="
      .. block(fitted_tabs, tb, ta, map)
      .. "%#TabBuffersOffset#"
      .. string.rep(" ", right)
    return {
      text = cached,
      targets = map,
      last_active = last_active,
      visibility = visibility,
      next_target = next_target,
    }
  end

  return build()
end

return M
