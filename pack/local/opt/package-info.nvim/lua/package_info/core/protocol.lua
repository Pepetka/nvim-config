local M = {}
local config = require("package_info.core.config")
local sections = require("package_info.core.manifest").sections
---@param value unknown
---@return boolean
local function object(value)
  return type(value) == "table"
end
---@param value unknown
---@return boolean
local function nonnegative(value)
  return type(value) == "number" and value == value and value >= 0 and value < math.huge
end
---@param value unknown
---@return boolean
local function integer(value)
  return nonnegative(value) and value % 1 == 0
end
---@param value table
---@param keys string[]
---@param kind string
---@return boolean
local function optional(value, keys, kind)
  for _, key in ipairs(keys) do
    if value[key] ~= nil and type(value[key]) ~= kind then
      return false
    end
  end
  return true
end
---@param value unknown
---@return boolean
local function error_kind(value)
  return value == nil
    or value == "timeout"
    or value == "auth"
    or value == "config"
    or value == "not_found"
    or value == "manager"
    or value == "network"
    or value == "metadata"
end
---@param value unknown
---@return PackageInfoInstalled?
function M.installed(value)
  if not object(value) then
    return nil
  end
  if
    value.state ~= nil
    and value.state ~= "installed"
    and value.state ~= "unknown"
    and value.state ~= "not_applicable"
  then
    return nil
  end
  for _, key in ipairs({ "version", "reason" }) do
    if value[key] ~= nil and type(value[key]) ~= "string" then
      return nil
    end
  end
  return value
end
---@param value unknown
---@return PackageInfoInstalled[]?
function M.installed_list(value)
  if not config.list(value) then
    return nil
  end
  ---@cast value table
  for _, item in ipairs(value) do
    if not M.installed(item) then
      return nil
    end
  end
  return value
end
---@param value unknown
---@return PackageInfoComparison?
function M.comparison(value)
  if not object(value) then
    return nil
  end
  if
    value.status ~= "unknown"
    and value.status ~= "current"
    and value.status ~= "update"
    and value.status ~= "major"
    and value.status ~= "unavailable"
  then
    return nil
  end
  for _, key in ipairs({ "wanted", "latest" }) do
    if value[key] ~= nil and type(value[key]) ~= "string" then
      return nil
    end
  end
  if value.status == "update" and not value.wanted or value.status == "major" and not value.latest then
    return nil
  end
  if value.checked_at ~= nil and not nonnegative(value.checked_at) then
    return nil
  end
  return value
end
---@param value unknown
---@return PackageInfoContext?
function M.context(value)
  if not object(value) or type(value.dir) ~= "string" or type(value.root) ~= "string" then
    return nil
  end
  if
    not optional(value, { "error", "marker", "fingerprint", "registry_fingerprint" }, "string")
    or not optional(value, { "pnp", "custom_plugins", "overrides" }, "boolean")
  then
    return nil
  end
  for _, key in ipairs({ "major", "expected_major" }) do
    if value[key] ~= nil and (not integer(value[key]) or value[key] < 1) then
      return nil
    end
  end
  if
    not (value.error ~= nil and value.manager == nil)
    and value.manager ~= "npm"
    and value.manager ~= "yarn"
    and value.manager ~= "pnpm"
  then
    return nil
  end
  if
    type(value.fingerprint) ~= "string"
    or type(value.registry_fingerprint) ~= "string"
    or not config.list(value.dependencies)
  then
    return nil
  end
  for _, dep in ipairs(value.dependencies) do
    if not object(dep) or type(dep.name) ~= "string" or type(dep.spec) ~= "string" or not sections[dep.section] then
      return nil
    end
    if dep.kind ~= "range" and dep.kind ~= "tag" and dep.kind ~= "local" and dep.kind ~= "unsupported" then
      return nil
    end
    for _, key in ipairs({ "target", "range", "reason" }) do
      if dep[key] ~= nil and type(dep[key]) ~= "string" then
        return nil
      end
    end
    if (dep.kind == "range" or dep.kind == "tag") and (type(dep.target) ~= "string" or type(dep.range) ~= "string") then
      return nil
    end
    if dep.installed ~= nil and not M.installed(dep.installed) then
      return nil
    end
    if not optional(dep, { "error", "error_kind" }, "string") or not optional(dep, { "cached" }, "boolean") then
      return nil
    end
    if not error_kind(dep.error_kind) then
      return nil
    end
    if dep.registry_time ~= nil and not nonnegative(dep.registry_time) then
      return nil
    end
    if dep.result ~= nil and not M.comparison(dep.result) then
      return nil
    end
  end
  return value
end
---@param value unknown
---@return PackageInfoConfiguration?
function M.configuration(value)
  if not object(value) then
    return nil
  end
  if not optional(value, { "fallback" }, "boolean") or not optional(value, { "client" }, "string") then
    return nil
  end
  if value.fallback == true and value.client == nil or value.fallback ~= true and type(value.client) == "string" then
    return value
  end
end
---@param value unknown
---@return PackageInfoEvent?
function M.event(value)
  if not object(value) then
    return nil
  end
  if not optional(value, { "complete", "reconfigure" }, "boolean") then
    return nil
  end
  if value.reconfigure == true then
    return value.complete == nil and value.records == nil and value.completed == nil and value.total == nil and value
      or nil
  end
  if value.complete == true and value.records == nil and value.completed == nil and value.total == nil then
    return value
  end
  if
    value.complete == true
    or not config.list(value.records)
    or not integer(value.completed)
    or not integer(value.total)
    or value.completed > value.total
  then
    return nil
  end
  for _, record in ipairs(value.records) do
    if
      not object(record)
      or type(record.name) ~= "string"
      or not sections[record.section]
      or not nonnegative(record.age_ms)
    then
      return nil
    end
    if record.error ~= nil and type(record.error) ~= "string" then
      return nil
    end
    if not optional(record, { "cached" }, "boolean") then
      return nil
    end
    if not error_kind(record.kind) then
      return nil
    end
    if record.result ~= nil and not M.comparison(record.result) then
      return nil
    end
  end
  return value
end
return M
