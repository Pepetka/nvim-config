local M = {}

---@param context PackageInfoContext
---@param target string
---@return string
function M.metadata_key(context, target)
  local parts = {}
  for _, value in ipairs({
    context.root,
    context.dir,
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
  local message = ((result.stderr or "") .. " " .. (result.stdout or "")):lower()
  if result.code == 124 or result.signal == 15 or result.signal == 9 then
    return "timeout", "Registry request timed out"
  elseif
    message:find("401", 1, true)
    or message:find("403", 1, true)
    or message:find("authentication", 1, true)
    or message:find("unauthorized", 1, true)
  then
    return "auth", "Registry authentication failed"
  elseif message:find("environment variable not found", 1, true) or message:find("usage error", 1, true) then
    return "config", "Package manager configuration failed; check required environment variables and rc files"
  elseif message:find("404", 1, true) or message:find("not found", 1, true) or message:find("yn0035", 1, true) then
    return "not_found", "Package not found or access denied by the registry"
  elseif message:find("corepack", 1, true) or message:find("cannot start", 1, true) then
    return "manager", "Package manager is unavailable (Corepack downloads are disabled)"
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
