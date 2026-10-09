local patterns = require("cheatsheet.core.patterns")
local M = {}

---@generic T
---@param value T
---@return T
local function copy(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for key, item in pairs(value) do
    result[key] = copy(item)
  end
  return result
end

---@param values string[]
---@return CheatsheetValidator
local function enum(values)
  return function(value)
    for _, candidate in ipairs(values) do
      if value == candidate then
        return true
      end
    end
    return false
  end
end

---@param value unknown
---@return boolean
local function text(value)
  return type(value) == "string" and not value:find("[\r\n]")
end

---@param value unknown
---@return boolean
local function nonempty(value)
  return text(value) and value:find("%S") ~= nil
end

---@param value unknown
---@return boolean
local function boolean(value)
  return type(value) == "boolean"
end

---@param value unknown
---@return boolean
local function ratio(value)
  return type(value) == "number" and value > 0 and value <= 1
end

---@param value unknown
---@return boolean
local function integer(value)
  return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

---@param value unknown
---@return boolean
local function positive_integer(value)
  return integer(value) and value > 0
end

---@param value unknown
---@param predicate CheatsheetValidator
---@param unique? boolean
---@return boolean
local function list(value, predicate, unique)
  if type(value) ~= "table" then
    return false
  end
  local count = 0
  for key in pairs(value) do
    if not positive_integer(key) then
      return false
    end
    count = count + 1
  end
  local seen = {}
  for index = 1, count do
    local item = value[index]
    if item == nil or not predicate(item) or (unique and seen[item]) then
      return false
    end
    if unique then
      seen[item] = true
    end
  end
  return true
end

---@param value unknown
---@return boolean
local function strings(value)
  return list(value, nonempty, true)
end

---@param value unknown
---@return boolean
local function pattern(value)
  return patterns.valid(value)
end

---@param value unknown
---@return boolean
local function rule(value)
  return type(value) == "table"
    and pattern(value.pattern)
    and nonempty(value.group)
    and (value.icon == nil or text(value.icon))
    and (value.prefix == nil or text(value.prefix))
end

---@type CheatsheetConfig
local defaults = {
  window = {
    width = 0.8,
    height = 0.8,
    title = "Cheatsheet",
    title_pos = "left",
    border = "rounded",
    zindex = 50,
    padding = { left = 2, right = 2, top = 1, bottom = 1 },
  },
  modes = { "n", "i", "v", "o", "t" },
  group_rules = {},
  default_group = { name = "other" },
  exclude = {
    no_desc = true,
    patterns = { "^<Plug>" },
    desc_patterns = { "^Lua function" },
    single_word = true,
    newline = true,
    groups = {},
  },
  icons = { enabled = true, default = "󰌌 " },
  sort_groups = {},
  sort_keys = "alphanum",
  group_align = "left",
  mode_align = "right",
  group_underline = true,
  layout = { key_gap = 4, mapping_spacing = 1, group_spacing = 2 },
  mappings = { close = { "q" }, next_mode = "<tab>", prev_mode = "<S-Tab>" },
}

local align = enum({ "left", "center", "right" })
local valid_mode = enum({ "n", "i", "v", "o", "t" })
---@alias CheatsheetValidator fun(value: unknown): boolean
---@class CheatsheetSchema: table<string, CheatsheetValidator | CheatsheetSchema>

---@type CheatsheetSchema
local schema = {
  window = {
    width = ratio,
    height = ratio,
    title = text,
    title_pos = align,
    border = enum({ "none", "single", "double", "rounded", "solid", "shadow" }),
    zindex = positive_integer,
    padding = { left = integer, right = integer, top = integer, bottom = integer },
  },
  modes = function(value)
    return list(value, valid_mode, true) and #value > 0
  end,
  default_group = { name = nonempty, icon = text },
  exclude = { no_desc = boolean, single_word = boolean, newline = boolean, groups = strings },
  icons = { enabled = boolean, default = text },
  sort_groups = strings,
  sort_keys = enum({ "alphanum", "desc" }),
  group_align = align,
  mode_align = align,
  group_underline = boolean,
  layout = { key_gap = integer, mapping_spacing = integer, group_spacing = integer },
  mappings = { close = strings, next_mode = nonempty, prev_mode = nonempty },
  open_mapping = nonempty,
}

---@param messages string[]
---@param path string
---@param action string
---@return nil
local function warning(messages, path, action)
  messages[#messages + 1] = "cheatsheet: invalid " .. path .. ", " .. action
end

---@param input table<string, unknown>
---@param output table<string, unknown>
---@param fields CheatsheetSchema
---@param messages string[]
---@param prefix string
---@return nil
local function normalize_fields(input, output, fields, messages, prefix)
  for key, validator in pairs(fields) do
    local value = input[key]
    local path = prefix .. key
    if value ~= nil then
      if type(validator) == "table" then
        if type(value) == "table" then
          normalize_fields(value, output[key], validator, messages, path .. ".")
        else
          warning(messages, path, "using default")
        end
      elseif validator(value) then
        output[key] = copy(value)
      else
        warning(messages, path, "using default")
      end
    end
  end
end

---@generic T
---@param value unknown
---@param predicate CheatsheetValidator
---@param messages string[]
---@param path string
---@param fallback T[]
---@return T[]
local function normalize_list(value, predicate, messages, path, fallback)
  if value == nil then
    return copy(fallback)
  end
  if not list(value, function()
    return true
  end) then
    warning(messages, path, "using default")
    return copy(fallback)
  end
  local result = {}
  for index, item in ipairs(value) do
    if predicate(item) then
      -- The predicate establishes the element type at this untrusted-input boundary.
      result[#result + 1] = copy(item)
    else
      warning(messages, path .. "[" .. index .. "]", "skipping entry")
    end
  end
  return result
end

---@return CheatsheetConfig
function M.defaults()
  return copy(defaults)
end

---Normalize caller-owned options without changing inputs or shared defaults.
---@param opts? unknown Untrusted input; public setup accepts CheatsheetConfigPartial.
---@return CheatsheetConfig config, string[] diagnostics
function M.normalize(opts)
  local result, messages = M.defaults(), {}
  if opts == nil then
    opts = {}
  elseif type(opts) ~= "table" then
    warning(messages, "options", "using defaults")
    opts = {}
  end
  normalize_fields(opts, result, schema, messages, "")
  result.group_rules = normalize_list(opts.group_rules, rule, messages, "group_rules", defaults.group_rules)
  local exclude = type(opts.exclude) == "table" and opts.exclude or {}
  result.exclude.patterns =
    normalize_list(exclude.patterns, pattern, messages, "exclude.patterns", defaults.exclude.patterns)
  result.exclude.desc_patterns =
    normalize_list(exclude.desc_patterns, pattern, messages, "exclude.desc_patterns", defaults.exclude.desc_patterns)
  -- The fallback is resolved by the mappings layer; an explicit empty icon is meaningful.
  table.sort(messages)
  return result, messages
end

return M
