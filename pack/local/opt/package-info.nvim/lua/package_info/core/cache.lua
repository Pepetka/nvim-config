local M = { ttl = 15 * 60 * 1000, retry = 30000 }
---@param entry? PackageInfoCacheEntry
---@param now number
---@param force? boolean
---@param options? PackageInfoCacheConfig
---@return boolean
function M.fresh(entry, now, force, options)
  options = options or require("package_info.core.config").defaults().cache
  return not force
    and entry ~= nil
    and now >= entry.time
    and now - entry.time < (entry.error and options.retry or options.ttl)
end
---@param values table<string, PackageInfoCacheEntry>
---@param now number
---@param options? PackageInfoCacheConfig
function M.prune(values, now, options)
  options = options or require("package_info.core.config").defaults().cache
  local keys = {}
  for key, entry in pairs(values) do
    if not M.fresh(entry, now, false, options) then
      values[key] = nil
    else
      keys[#keys + 1] = key
    end
  end
  table.sort(keys, function(a, b)
    return values[a].time < values[b].time
  end)
  for index = 1, #keys - options.cli_limit do
    values[keys[index]] = nil
  end
end
return M
