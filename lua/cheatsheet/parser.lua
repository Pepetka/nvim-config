local cheatsheet_config = require("cheatsheet.config")

---@class CheatsheetRawMapping
---@field lhs string
---@field rhs string
---@field desc? string
---@field mode CheatsheetMode
---@field buffer? integer
---@field noremap boolean
---@field silent boolean

---@class CheatsheetMapping
---@field lhs string
---@field desc string
---@field mode CheatsheetMode

---@class CheatsheetGroup
---@field name string
---@field icon string
---@field mappings CheatsheetMapping[]

local utils = {}

function utils.word_count(str)
  local _, count = str:gsub("%S+", "")
  return count
end

function utils.capitalize(str)
  return str:gsub("^%l", string.upper)
end

function utils.remove_first_word(str)
  return str:gsub("^%S+%s*", ""):gsub("^%s*", "")
end

function utils.trim(str)
  return str:gsub("^%s+", ""):gsub("%s+$", "")
end

function utils.format_lhs(lhs)
  local leader = vim.g.mapleader or " "
  if leader ~= "" and lhs:sub(1, #leader) == leader then
    lhs = "<leader> + " .. lhs:sub(#leader + 1)
  end
  return lhs
end

local M = {}

---@param mode CheatsheetMode
---@return CheatsheetRawMapping[]
function M.collect(mode)
  ---@type table<string, CheatsheetRawMapping>
  local by_lhs = {}

  for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
    mapping.mode = mode
    by_lhs[mapping.lhs] = mapping
  end

  for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
    mapping.mode = mode
    by_lhs[mapping.lhs] = mapping
  end

  ---@type CheatsheetRawMapping[]
  local result = {}
  for _, mapping in pairs(by_lhs) do
    table.insert(result, mapping)
  end

  return result
end

---@param mappings CheatsheetRawMapping[]
---@return CheatsheetMapping[]
function M.filter(mappings)
  local opts = cheatsheet_config.options
  ---@type CheatsheetMapping[]
  local result = {}

  for _, mapping in ipairs(mappings) do
    local lhs = mapping.lhs
    local desc = utils.trim(mapping.desc or "")

    if not lhs or lhs == "" then
      goto continue
    end

    if desc == "" then
      goto continue
    end

    if opts.exclude.no_desc and desc == "" then
      goto continue
    end

    if opts.exclude.newline and desc:find("\n") then
      goto continue
    end

    if opts.exclude.single_word and utils.word_count(desc) < 2 then
      goto continue
    end

    if lhs:find("<Plug>") then
      goto continue
    end

    local skip_by_pattern = false
    for _, pattern in ipairs(opts.exclude.patterns or {}) do
      if lhs:find(pattern) then
        skip_by_pattern = true
        break
      end
    end
    if skip_by_pattern then
      goto continue
    end

    lhs = utils.format_lhs(lhs)

    ---@type CheatsheetMapping
    local item = {
      lhs = lhs,
      desc = desc,
      mode = mapping.mode,
    }
    table.insert(result, item)

    ::continue::
  end

  return result
end

---@param mappings CheatsheetMapping[]
---@return table<string, CheatsheetGroup>
function M.group(mappings)
  local opts = cheatsheet_config.options
  ---@type table<string, CheatsheetGroup>
  local groups = {}
  ---@type table<string, boolean>
  local excluded_groups = {}

  for _, name in ipairs(opts.exclude.groups or {}) do
    excluded_groups[name] = true
  end

  for _, mapping in ipairs(mappings) do
    ---@type string | nil
    local desc = mapping.desc
    ---@type string
    local group_name = opts.default_group.name
    ---@type string
    local icon = opts.default_group.icon

    for _, rule in ipairs(opts.group_rules or {}) do
      if desc and desc:find(rule.pattern) then
        group_name = rule.group
        icon = rule.icon
        break
      end
    end

    if excluded_groups[group_name] then
      goto continue
    end

    local clean_desc = utils.remove_first_word(desc)
    clean_desc = utils.capitalize(clean_desc)
    clean_desc = utils.trim(clean_desc)

    if not groups[group_name] then
      groups[group_name] = {
        name = group_name,
        icon = icon,
        mappings = {},
      }
    end

    ---@type CheatsheetMapping
    local group_mapping = {
      lhs = mapping.lhs,
      desc = clean_desc,
      mode = mapping.mode,
    }
    table.insert(groups[group_name].mappings, group_mapping)

    ::continue::
  end

  return groups
end

---@param groups_map table<string, CheatsheetGroup>
---@return CheatsheetGroup[]
function M.sort(groups_map)
  local opts = cheatsheet_config.options
  local sort_groups = opts.sort_groups or {}
  ---@type table<string, number>
  local group_priority = {}

  for index, name in ipairs(sort_groups) do
    group_priority[name] = index
  end

  ---@type CheatsheetGroup[]
  local groups = {}
  for _, group in pairs(groups_map) do
    table.insert(groups, group)
  end

  table.sort(groups, function(a, b)
    local priority_a = group_priority[a.name] or math.huge
    local priority_b = group_priority[b.name] or math.huge

    if priority_a ~= priority_b then
      return priority_a < priority_b
    end

    return a.name < b.name
  end)

  for _, group in ipairs(groups) do
    if opts.sort_keys == "desc" then
      table.sort(group.mappings, function(a, b)
        return a.desc < b.desc
      end)
    else
      table.sort(group.mappings, function(a, b)
        return a.lhs < b.lhs
      end)
    end
  end

  return groups
end

---@param mode string
---@return CheatsheetGroup[]
function M.parse(mode)
  if not cheatsheet_config.options then
    vim.notify("cheatsheet: setup() must be called before parse()", vim.log.levels.ERROR)
    return {}
  end

  local mappings = M.collect(mode)
  mappings = M.filter(mappings)
  local groups_map = M.group(mappings)
  return M.sort(groups_map)
end

return M
