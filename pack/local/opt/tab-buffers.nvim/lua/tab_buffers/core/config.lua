local lists = require("tab_buffers.core.lists")
local validation = require("tab_buffers.core.validation")
local M = {}

---@param values string[]
---@param value string
---@return boolean
function M.contains(values, value)
  for _, item in ipairs(values) do
    if item == value then
      return true
    end
  end
  return false
end

---@param value unknown
---@param name string
---@return string[]
local function strings(value, name)
  assert(type(value) == "table", name .. " must be a list")
  local count = 0
  for key in pairs(value) do
    validation.id(key, name .. " index")
    count = count + 1
  end
  local result = {}
  for index = 1, count do
    assert(type(value[index]) == "string", name .. " must contain filetypes")
    result[index] = value[index]
  end
  return result
end

---@param opts? unknown
---@return TabBuffersConfig
function M.behavior(opts)
  assert(opts == nil or type(opts) == "table", "options must be a table")
  local config = lists.merge({
    close_empty_tab = true,
    wrap = true,
    replacement = "right",
    bootstrap_hidden_buffers = true,
  }, opts or {})
  for _, name in ipairs({ "close_empty_tab", "wrap", "bootstrap_hidden_buffers" }) do
    assert(type(config[name]) == "boolean", name .. " must be a boolean")
  end
  assert(
    config.replacement == "right" or config.replacement == "left" or config.replacement == "last_used",
    "invalid replacement policy"
  )
  for _, name in ipairs({ "buffer_filter", "tab_filter" }) do
    assert(config[name] == nil or type(config[name]) == "function", name .. " must be a function")
  end
  return config
end

---@param opts? unknown
---@return TabBuffersTablineConfig
function M.normalize(opts)
  assert(opts == nil or type(opts) == "table", "options must be a table")
  local config = lists.merge({
    visibility = "auto",
    tab_width_ratio = 1 / 3,
    icons = true,
    max_name_length = 30,
    padding = 0,
    offsets = {},
    hide_filetypes = {},
    highlights = {},
  }, opts or {})
  assert(
    config.visibility == "auto" or config.visibility == "always" or config.visibility == "never",
    "invalid visibility"
  )
  assert(
    type(config.tab_width_ratio) == "number" and config.tab_width_ratio > 0 and config.tab_width_ratio <= 1,
    "tab_width_ratio must be in (0, 1]"
  )
  validation.id(config.max_name_length, "max_name_length")
  validation.integer(config.padding, "padding")
  assert(config.padding >= 0, "padding must be a nonnegative integer")
  assert(type(config.icons) == "boolean", "icons must be a boolean")
  config.offsets = strings(config.offsets, "offsets")
  config.hide_filetypes = strings(config.hide_filetypes, "hide_filetypes")
  assert(
    type(config.highlights) == "table" or type(config.highlights) == "function",
    "highlights must be a table or callback"
  )
  if type(config.highlights) == "table" then
    config.highlights = lists.copy(config.highlights)
  end
  return config
end

---@param value unknown
---@return TabBuffersHighlights
function M.highlights(value)
  assert(type(value) == "table", "highlights callback must return a table")
  for name, style in pairs(value) do
    assert(type(name) == "string" and type(style) == "table", "highlights must map names to style tables")
  end
  return lists.copy(value)
end

return M
