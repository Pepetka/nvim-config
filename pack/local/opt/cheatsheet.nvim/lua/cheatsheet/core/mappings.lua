local M = {}

---@param value string
---@return string
local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param value string
---@param patterns string[]
---@return boolean
local function matches_any(value, patterns)
  for _, pattern in ipairs(patterns) do
    if value:find(pattern) then
      return true
    end
  end
  return false
end

---Local mappings override global mappings before any display filters are applied.
---@param global CheatsheetRawMapping[]
---@param local_mappings CheatsheetRawMapping[]
---@param mode CheatsheetMode
---@return CheatsheetMapping[]
function M.merge(global, local_mappings, mode)
  ---@type table<string, CheatsheetMapping>
  local by_lhs = {}
  for _, source in ipairs({ global, local_mappings }) do
    for _, mapping in ipairs(source) do
      if type(mapping.lhs) == "string" and mapping.lhs ~= "" then
        by_lhs[mapping.lhs] = { lhs = mapping.lhs, desc = mapping.desc or "", mode = mode }
      end
    end
  end
  local result = {}
  for _, mapping in pairs(by_lhs) do
    result[#result + 1] = mapping
  end
  table.sort(result, function(a, b)
    return a.lhs < b.lhs
  end)
  return result
end

---@param mapping CheatsheetDisplayMapping
---@param exclude CheatsheetExcludeConfig
---@return boolean
function M.accept(mapping, exclude)
  local desc = trim(mapping.desc)
  if (exclude.no_desc and desc == "") or (exclude.newline and mapping.desc:find("[\r\n]")) then
    return false
  end
  local _, words = desc:gsub("%S+", "")
  if exclude.single_word and words < 2 then
    return false
  end
  return not matches_any(mapping.lhs, exclude.patterns) and not matches_any(desc, exclude.desc_patterns)
end

---@param lhs string
---@param leader string
---@return string
function M.format_lhs(lhs, leader)
  if leader ~= "" and lhs:sub(1, #leader) == leader then
    return "<leader> + " .. lhs:sub(#leader + 1)
  end
  return lhs
end

---@param desc string
---@param config CheatsheetConfig
---@return string name, string? icon, number priority, string? prefix
function M.select_group(desc, config)
  for index, rule in ipairs(config.group_rules) do
    if desc:find(rule.pattern) then
      return rule.group, rule.icon, index, rule.prefix
    end
  end
  return config.default_group.name, config.default_group.icon, math.huge
end

---@param desc string
---@param matched boolean
---@param prefix? string Explicit literal prefix; an empty string disables removal.
---@return string
function M.description(desc, matched, prefix)
  desc = trim(desc:gsub("[\r\n]+", " "))
  if matched then
    if prefix == nil then
      prefix = desc:match("^(%S+:)%s") or desc:match("^(%S+:)$")
    end
    if prefix and prefix ~= "" and desc:sub(1, #prefix) == prefix then
      desc = trim(desc:sub(#prefix + 1)):gsub("^%l", string.upper)
    end
  end
  return desc
end

---@param icon string?
---@param config CheatsheetConfig
---@return string
function M.icon(icon, config)
  if not config.icons.enabled then
    return ""
  end
  if icon == nil then
    return config.icons.default
  end
  return icon
end

---@param groups CheatsheetGroup[]
---@param config CheatsheetConfig
---@return CheatsheetGroup[]
function M.sort(groups, config)
  local result = {}
  for _, group in ipairs(groups) do
    ---@type CheatsheetGroup
    local sorted = { name = group.name, icon = group.icon, mappings = {} }
    for _, mapping in ipairs(group.mappings) do
      sorted.mappings[#sorted.mappings + 1] = { lhs = mapping.lhs, desc = mapping.desc, mode = mapping.mode }
    end
    result[#result + 1] = sorted
  end
  ---@type table<string, integer>
  local priority = {}
  for index, name in ipairs(config.sort_groups) do
    priority[name] = index
  end
  table.sort(result, function(a, b)
    local left, right = priority[a.name] or math.huge, priority[b.name] or math.huge
    if left ~= right then
      return left < right
    end
    return a.name < b.name
  end)
  for _, group in ipairs(result) do
    table.sort(group.mappings, function(a, b)
      if config.sort_keys == "desc" and a.desc ~= b.desc then
        return a.desc < b.desc
      end
      return a.lhs < b.lhs
    end)
  end
  return result
end

---@param global CheatsheetRawMapping[]
---@param local_mappings CheatsheetRawMapping[]
---@param config CheatsheetConfig
---@param context CheatsheetMappingContext
---@return CheatsheetGroup[]
function M.build(global, local_mappings, config, context)
  ---@type table<string, boolean>
  local excluded = {}
  ---@type table<string, CheatsheetGroup>
  local by_name = {}
  ---@type table<string, number>
  local priorities = {}
  for _, name in ipairs(config.exclude.groups) do
    excluded[name] = true
  end
  for _, mapping in ipairs(M.merge(global, local_mappings, context.mode)) do
    if M.accept(mapping, config.exclude) then
      local desc = trim(mapping.desc)
      local name, icon, priority, prefix = M.select_group(desc, config)
      if not excluded[name] then
        local group = by_name[name]
        if not group then
          group = { name = name, icon = M.icon(icon, config), mappings = {} }
          by_name[name], priorities[name] = group, priority
        elseif priority < priorities[name] then
          group.icon, priorities[name] = M.icon(icon, config), priority
        end
        group.mappings[#group.mappings + 1] = {
          lhs = M.format_lhs(mapping.lhs, context.leader),
          desc = M.description(desc, priority ~= math.huge, prefix),
          mode = context.mode,
        }
      end
    end
  end
  local groups = {}
  for _, group in pairs(by_name) do
    groups[#groups + 1] = group
  end
  return M.sort(groups, config)
end

return M
