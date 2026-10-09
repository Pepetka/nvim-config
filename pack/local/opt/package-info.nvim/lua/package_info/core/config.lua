local M = {}
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
---@return boolean
function M.list(value)
  if type(value) ~= "table" then
    return false
  end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end
    count = count + 1
  end
  for index = 1, count do
    if value[index] == nil then
      return false
    end
  end
  return true
end
---@param value unknown
---@return boolean
local function positive(value)
  return type(value) == "number" and value % 1 == 0 and value > 0 and value <= 2147483647
end
---@param value unknown
---@return boolean
local function nonnegative(value)
  return value == 0 or positive(value)
end
---@param value unknown
---@return boolean
local function boolean(value)
  return type(value) == "boolean"
end
---@param value unknown
---@return boolean
local function string(value)
  return type(value) == "string"
end
---@param allowed string[]
---@return fun(value: unknown): boolean
local function choice(allowed)
  return function(value)
    for _, candidate in ipairs(allowed) do
      if candidate == value then
        return true
      end
    end
    return false
  end
end
---@param item fun(value: unknown): boolean
---@return fun(value: unknown): boolean
local function list_of(item)
  return function(value)
    if not M.list(value) then
      return false
    end
    for _, entry in ipairs(value) do
      if not item(entry) then
        return false
      end
    end
    return true
  end
end
---@param target table
---@param input table
---@param rules table
---@param path string
---@param errors string[]
local function merge(target, input, rules, path, errors)
  for key, value in pairs(input) do
    local rule = rules[key]
    local name = path .. tostring(key)
    if rule == nil then
      errors[#errors + 1] = "package-info: unknown option " .. name .. ", ignoring"
    elseif type(rule) == "function" then
      if rule(value) then
        target[key] = M.copy(value)
      else
        errors[#errors + 1] = "package-info: invalid " .. name .. ", using default"
      end
    elseif type(value) ~= "table" then
      errors[#errors + 1] = "package-info: invalid " .. name .. ", using default"
    else
      merge(target[key], value, rule, name .. ".", errors)
    end
  end
end
---@return PackageInfoConfig
function M.defaults()
  return {
    managers = {},
    fast_registry = true,
    auto_refresh = { on_enter = true, on_save = true },
    sections = { "dependencies", "devDependencies", "optionalDependencies", "peerDependencies" },
    exclude = { packages = {}, projects = {} },
    timeouts = { registry = 15000, manager = 5000, helper = 5000, bootstrap = 120000 },
    concurrency = { http = 32, http_per_project = 16, cli = 4, cli_per_project = 2 },
    cache = {
      ttl = 900000,
      retry = 30000,
      memory_limit = 2000,
      cli_limit = 1000,
      disk = true,
      disk_limit = 2000,
      cleanup_interval = 60000,
      client_ttl = 900000,
      client_limit = 128,
    },
    display = {
      enabled = true,
      statuses = { "installed", "update", "major", "unavailable", "not_found", "unsupported", "error" },
      icons = { installed = "󰏖", update = "󰚰", error = "󰂡" },
      prefix = "  ",
      virt_text_pos = "eol",
      float = { border = "rounded", focusable = true },
    },
  }
end
---@param input? unknown
---@return PackageInfoConfig, string[]
function M.normalize(input)
  ---@type PackageInfoConfig
  local result = M.defaults()
  local errors = {}
  if input == nil then
    return result, errors
  end
  if type(input) ~= "table" then
    return result, { "package-info: invalid options, using defaults" }
  end
  if input.fast_registry ~= nil then
    if type(input.fast_registry) == "boolean" then
      result.fast_registry = input.fast_registry
    else
      errors[#errors + 1] = "package-info: invalid fast_registry, using default"
    end
  end
  if input.managers ~= nil then
    if type(input.managers) ~= "table" then
      errors[#errors + 1] = "package-info: invalid managers, using default"
    else
      for path, manager in pairs(input.managers) do
        if
          type(path) == "string"
          and path:sub(1, 1) == "/"
          and type(manager) == "string"
          and (
            manager == "npm"
            or manager == "yarn"
            or manager == "pnpm"
            or manager:match("^npm@%d+[%.%d]*$")
            or manager:match("^yarn@%d+[%.%d]*$")
            or manager:match("^pnpm@%d+[%.%d]*$")
          )
        then
          result.managers[path] = manager
        else
          errors[#errors + 1] = "package-info: invalid manager override, ignoring entry"
        end
      end
    end
  end
  local extra = {}
  for key, value in pairs(input) do
    if key ~= "managers" and key ~= "fast_registry" then
      extra[key] = value
    end
  end
  if type(extra.auto_refresh) == "boolean" then
    extra.auto_refresh = { on_enter = extra.auto_refresh, on_save = extra.auto_refresh }
  end
  local function pattern(value)
    return type(value) == "string" and value ~= ""
  end
  merge(result, extra, {
    auto_refresh = { on_enter = boolean, on_save = boolean },
    sections = list_of(choice({ "dependencies", "devDependencies", "optionalDependencies", "peerDependencies" })),
    exclude = {
      packages = list_of(pattern),
      projects = list_of(function(value)
        return type(value) == "string" and value:sub(1, 1) == "/"
      end),
    },
    timeouts = { registry = positive, manager = positive, helper = positive, bootstrap = positive },
    concurrency = { http = positive, http_per_project = positive, cli = positive, cli_per_project = positive },
    cache = {
      ttl = nonnegative,
      retry = nonnegative,
      memory_limit = nonnegative,
      cli_limit = nonnegative,
      disk = boolean,
      disk_limit = nonnegative,
      cleanup_interval = nonnegative,
      client_ttl = positive,
      client_limit = positive,
    },
    display = {
      enabled = boolean,
      statuses = list_of(
        choice({ "installed", "update", "major", "unavailable", "not_found", "unsupported", "error" })
      ),
      icons = { installed = string, update = string, error = string },
      prefix = string,
      virt_text_pos = choice({ "eol", "eol_right_align", "right_align" }),
      float = {
        border = choice({ "none", "single", "double", "rounded", "solid", "shadow" }),
        focusable = boolean,
        max_width = positive,
        max_height = positive,
      },
    },
  }, "", errors)
  return result, errors
end
return M
