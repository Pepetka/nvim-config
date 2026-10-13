local M = {}

---@param context PackageInfoContext
---@param target string
---@return string
function M.metadata_key(context, target)
  local parts = {}
  for _, value in ipairs({
    context.manager,
    tostring(assert(context.major)),
    context.registry_fingerprint,
    target,
  }) do
    parts[#parts + 1] = #value .. ":" .. value
  end
  return table.concat(parts)
end

---@param context {manager: PackageInfoManager, major?: integer, expected_major?: integer}
---@param name string
---@return string[]
function M.command(context, name)
  if context.manager == "yarn" then
    if context.major == 1 then
      return { "yarn", "info", name, "--json" }
    end
    return { "yarn", "npm", "info", name, "--fields", "versions,dist-tags", "--json" }
  end
  return { context.manager, "view", name, "versions", "dist-tags", "--json" }
end

---@param context {manager: PackageInfoManager, major?: integer, expected_major?: integer}
---@param names string[]
---@return string[]?
function M.batch_command(context, names)
  if context.manager ~= "yarn" or context.major == 1 then
    return nil
  end
  local command = { "yarn", "npm", "info" }
  for _, name in ipairs(names) do
    command[#command + 1] = name
  end
  for _, argument in ipairs({ "--fields", "name,versions,dist-tags", "--json" }) do
    command[#command + 1] = argument
  end
  return command
end

-- A failed batch may still contain successful records. Match names rather than output order.
---@param stdout? string
---@param names string[]
---@param decode fun(text: string): unknown
---@param encode fun(value: table): string
---@return table<string, string>
function M.batch_results(stdout, names, decode, encode)
  local wanted, results = {}, {}
  for _, name in ipairs(names) do
    wanted[name] = true
  end
  for line in (stdout or ""):gmatch("[^\n]+") do
    local ok, value = pcall(decode, line)
    if
      ok
      and type(value) == "table"
      and wanted[value.name]
      and type(value.versions) == "table"
      and type(value["dist-tags"]) == "table"
    then
      results[value.name] = encode({ versions = value.versions, ["dist-tags"] = value["dist-tags"] })
    end
  end
  return results
end

---@param result PackageInfoProcessResult
---@return PackageInfoErrorKind, string
function M.error(result)
  if result.code == 124 or result.signal == 15 or result.signal == 9 then
    return "timeout", "Registry request timed out"
  end
  local lines = {}
  for line in ((result.stderr or "") .. "\n" .. (result.stdout or "")):gmatch("[^\n]+") do
    -- npm log paths contain timestamps that can look like HTTP status codes.
    if not line:find("complete log of this run", 1, true) and not line:find("_logs/", 1, true) then
      lines[#lines + 1] = line:lower()
    end
  end
  local message = " " .. table.concat(lines, " ") .. " "
  ---@param patterns string[]
  ---@return boolean
  local function has(patterns)
    for _, pattern in ipairs(patterns) do
      if message:find(pattern) then
        return true
      end
    end
    return false
  end
  if has({ "corepack", "network access disabled", "cannot start package manager" }) then
    return "manager", "Package manager could not be started (Corepack downloads are disabled)"
  elseif has({ "environment variable not found" }) then
    return "config", "Package manager configuration failed; check required environment variables and rc files"
  elseif has({ "%f[%w]e40[13]%f[%W]", "%f[%d]40[13]%f[%D]", "unauthorized", "forbidden", "authentication" }) then
    return "auth", "Registry authentication failed"
  elseif has({ "%f[%w]e404%f[%W]", "%f[%d]404%f[%D]", "not found", "yn0035" }) then
    return "not_found", "Package not found or access denied by the registry"
  elseif has({ "usage error" }) then
    return "config", "Package manager configuration failed; check required environment variables and rc files"
  end
  return "network", "Registry request failed; check network and manager configuration"
end

---@param context {manager: PackageInfoManager, major?: integer, expected_major?: integer}
---@param stdout? string
---@return integer?, string?
function M.compatible(context, stdout)
  local major = tonumber((stdout or ""):match("(%d+)%.%d+%.%d+"))
  if not major then
    return nil, "Cannot determine package manager version"
  end
  if context.expected_major and context.expected_major ~= major then
    return nil, "Package manager major differs from packageManager declaration"
  end
  if
    context.manager == "yarn" and (major < 1 or major > 4)
    or context.manager == "npm" and major < 7
    or context.manager == "pnpm" and major < 7
  then
    return nil, "Unsupported package manager version"
  end
  return major
end

return M
