local keys = require("dashboard.core.keys")
local M = {}
local block_fields = {
  text = { id = true, type = true, enabled = true, layout = true, lines = true, style = true },
  actions = { id = true, type = true, enabled = true, layout = true, items = true, label_width = true, spacing = true },
  custom = { id = true, type = true, enabled = true, layout = true, render = true },
}

---@generic T
---@param value T
---@return T
function M.copy(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for key, item in pairs(value) do
    result[key] = M.copy(item)
  end
  return result
end

---@param value unknown
---@param name string
---@return nil
function M.integer(value, name)
  assert(
    type(value) == "number" and value >= 0 and value < math.huge and value % 1 == 0,
    name .. " must be a nonnegative integer"
  )
end

---@param value unknown
---@param name string
---@return nil
function M.signed_integer(value, name)
  assert(type(value) == "number" and math.abs(value) < math.huge and value % 1 == 0, name .. " must be an integer")
end

---@param value unknown
---@param allowed table<string, boolean>
---@param name string
---@return nil
function M.fields(value, allowed, name)
  assert(type(value) == "table", name .. " must be a table")
  for key in pairs(value) do
    assert(allowed[key], "unknown " .. name .. " option: " .. tostring(key))
  end
end

---@param value unknown
---@param name string
---@return nil
function M.alignment(value, name)
  assert(value == "left" or value == "center" or value == "right", "invalid " .. name .. " alignment")
end

---@param options? DashboardBlockLayout
---@return nil
function M.block_layout(options)
  if options == nil then
    return
  end
  M.fields(options, { align = true, offset_x = true, gap_before = true, gap_after = true }, "block.layout")
  if options.align ~= nil then
    M.alignment(options.align, "block.layout")
  end
  M.signed_integer(options.offset_x == nil and 0 or options.offset_x, "block.layout.offset_x")
  M.integer(options.gap_before == nil and 0 or options.gap_before, "block.layout.gap_before")
  M.integer(options.gap_after == nil and 0 or options.gap_after, "block.layout.gap_after")
end

---@param options? DashboardNavigationOptions
---@return DashboardNavigation
function M.navigation(options)
  M.fields(options == nil and {} or options, { keys = true, wrap = true, highlight_selected = true }, "navigation")
  local input = options or {}
  M.fields(input.keys == nil and {} or input.keys, { next = true, previous = true, activate = true }, "navigation.keys")
  local result = keys.defaults()
  for _, role in ipairs({ "next", "previous", "activate" }) do
    local list = input.keys and input.keys[role]
    if list ~= nil then
      M.list(list, "navigation.keys." .. role)
      for _, key in ipairs(list) do
        M.text(key, "navigation key")
        assert(key ~= "", "navigation key must not be empty")
      end
      result[role] = M.copy(list)
    end
  end
  for _, name in ipairs({ "wrap", "highlight_selected" }) do
    assert(input[name] == nil or type(input[name]) == "boolean", "navigation." .. name .. " must be boolean")
  end
  return { keys = result, wrap = input.wrap ~= false, highlight_selected = input.highlight_selected == true }
end

---@param options? { hide_statusline?: boolean, hide_tabline?: boolean, hide_winbar?: boolean }
---@param fallback boolean
---@return DashboardChrome
function M.chrome(options, fallback)
  M.fields(
    options == nil and {} or options,
    { hide_statusline = true, hide_tabline = true, hide_winbar = true },
    "chrome"
  )
  ---@type DashboardChrome
  local result = { hide_statusline = fallback, hide_tabline = fallback, hide_winbar = fallback }
  for key, value in pairs(options or {}) do
    assert(type(value) == "boolean", "chrome." .. key .. " must be boolean")
    result[key] = value
  end
  return result
end

---@param value unknown
---@param name string
---@return nil
function M.text(value, name)
  assert(type(value) == "string" and not value:find("[\r\n%z]"), name .. " must be a single-line string")
end

---@param value unknown
---@param name string
---@return nil
function M.display_text(value, name)
  M.text(value, name)
  ---@cast value string
  assert(not value:find("\t", 1, true), name .. " must use spaces instead of tabs")
end

---@param value unknown
---@param name string
---@return nil
function M.list(value, name)
  assert(type(value) == "table", name .. " must be a list")
  local count = 0
  for key in pairs(value) do
    count = count + 1
    assert(type(key) == "number" and key >= 1 and key % 1 == 0, name .. " must be a list")
  end
  assert(count == #value, name .. " must be contiguous")
  for index = 1, count do
    assert(rawget(value, index) ~= nil, name .. " must be contiguous")
  end
end

---@param value unknown
---@param name string
---@return nil
function M.id(value, name)
  assert(type(value) == "string" and value:match("^[%w_%-]+$"), name .. " must be a nonempty identifier")
end

---@param items DashboardItem[]
---@return nil
function M.items(items)
  M.list(items, "items")
  local ids = {}
  for _, item in ipairs(items) do
    M.fields(item, { id = true, label = true, icon = true, key = true, run = true }, "item")
    M.id(item.id, "item.id")
    assert(not ids[item.id], "duplicate item id: " .. item.id)
    ids[item.id] = true
    M.display_text(item.label, "item.label")
    if item.icon ~= nil then
      M.display_text(item.icon, "item.icon")
    end
    if item.key ~= nil then
      M.text(item.key, "item.key")
      assert(item.key ~= "", "item.key must not be empty")
    end
    assert(type(item.run) == "string" or type(item.run) == "function", "item.run must be a command or function")
  end
end

---@param block DashboardBlock
---@return nil
function M.block(block)
  assert(type(block) == "table", "block must be a table")
  local allowed = block_fields[block.type]
  assert(allowed, "unknown block type: " .. tostring(block.type))
  M.fields(block, allowed, "block")
  M.id(block.id, "block.id")
  assert(
    block.enabled == nil or type(block.enabled) == "boolean" or type(block.enabled) == "function",
    "block.enabled must be boolean or a provider"
  )
  M.block_layout(block.layout)
  if block.type == "text" then
    local lines = block.lines
    if type(lines) == "table" then
      M.list(lines, "block.lines")
      for _, line in ipairs(lines) do
        M.display_text(line, "line")
      end
    else
      assert(type(lines) == "function", "block.lines must be a list or provider")
    end
    if block.style ~= nil then
      M.id(block.style, "block.style")
    end
  elseif block.type == "actions" then
    local items = block.items
    if type(items) == "table" then
      M.items(items)
    else
      assert(type(items) == "function", "block.items must be a list or provider")
    end
    M.integer(block.spacing == nil and 1 or block.spacing, "block.spacing")
    M.integer(block.label_width == nil and 0 or block.label_width, "block.label_width")
  elseif block.type == "custom" then
    assert(type(block.render) == "function", "custom block requires render")
  else
    error("unknown block type: " .. tostring(block.type))
  end
end

---@param options? unknown
---@return DashboardConfig
function M.normalize(options)
  assert(options == nil or type(options) == "table", "options must be a table")
  ---@cast options DashboardOptions?
  local input = M.copy(options or {})
  local allowed = {
    blocks = true,
    layout = true,
    highlights = true,
    autostart = true,
    hide_chrome = true,
    chrome = true,
    navigation = true,
    map_opts = true,
  }
  for key in pairs(input) do
    assert(allowed[key], "unknown dashboard option: " .. tostring(key))
  end
  assert(input.blocks == nil or type(input.blocks) == "table", "blocks must be a list")
  local blocks = input.blocks or {}
  M.list(blocks, "blocks")
  local ids = {}
  for _, block in ipairs(blocks) do
    M.block(block)
    assert(not ids[block.id], "duplicate block id: " .. block.id)
    ids[block.id] = true
  end
  assert(input.layout == nil or type(input.layout) == "table", "layout must be a table")
  local layout = input.layout or {}
  local horizontal = layout.horizontal == nil and "center" or layout.horizontal
  local vertical = layout.vertical == nil and "center" or layout.vertical
  local layout_keys = { horizontal = true, vertical = true, gap = true, bottom_padding = true }
  for key in pairs(layout) do
    assert(layout_keys[key], "unknown layout option: " .. tostring(key))
  end
  M.alignment(horizontal, "horizontal")
  assert(vertical == "top" or vertical == "center" or vertical == "bottom", "invalid vertical alignment")
  M.integer(layout.gap == nil and 0 or layout.gap, "layout.gap")
  M.integer(layout.bottom_padding == nil and 0 or layout.bottom_padding, "layout.bottom_padding")
  for _, name in ipairs({ "autostart", "hide_chrome" }) do
    assert(input[name] == nil or type(input[name]) == "boolean", name .. " must be boolean")
  end
  assert(
    input.highlights == nil or type(input.highlights) == "table" or type(input.highlights) == "function",
    "invalid highlights"
  )
  assert(input.map_opts == nil or type(input.map_opts) == "function", "map_opts must be a function")
  return {
    blocks = blocks,
    layout = {
      horizontal = horizontal,
      vertical = vertical,
      gap = layout.gap or 0,
      bottom_padding = layout.bottom_padding or 0,
    },
    highlights = input.highlights or {},
    autostart = input.autostart ~= false,
    hide_chrome = input.hide_chrome ~= false,
    chrome = M.chrome(input.chrome, input.hide_chrome ~= false),
    navigation = M.navigation(input.navigation),
    map_opts = input.map_opts,
  }
end

return M
