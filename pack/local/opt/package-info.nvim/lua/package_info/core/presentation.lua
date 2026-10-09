local M = {}
---@param a? PackageInfoAnnotations
---@param b PackageInfoAnnotations
---@return boolean
function M.same_annotations(a, b)
  if not a then
    return false
  end
  for row, chunks in pairs(a) do
    local other = b[row]
    if not other or #chunks ~= #other then
      return false
    end
    for index, chunk in ipairs(chunks) do
      if chunk[1] ~= other[index][1] or chunk[2] ~= other[index][2] then
        return false
      end
    end
  end
  for row in pairs(b) do
    if not a[row] then
      return false
    end
  end
  return true
end
---@param state PackageInfoBuffer
---@param options? PackageInfoDisplay
---@return table<integer, PackageInfoChunk[]>
function M.annotations(state, options)
  options = options or require("package_info.core.config").defaults().display
  local rows = {}
  if not options.enabled then
    return rows
  end
  local visible = {}
  for _, status in ipairs(options.statuses) do
    visible[status] = true
  end
  ---@param icon string
  ---@param text string
  ---@return string
  local function format_label(icon, text)
    return icon == "" and text or icon .. " " .. text
  end
  for _, dep in ipairs(state.context and state.context.dependencies or {}) do
    local row = state.lines[dep.section .. ":" .. dep.name]
    local result = dep.result or {}
    local label, highlight
    if result.status == "update" and visible.update then
      label, highlight = format_label(options.icons.update, result.wanted), "PackageInfoUpdate"
    elseif result.status == "major" and visible.major then
      label, highlight = format_label(options.icons.update, "latest " .. result.latest), "PackageInfoLatest"
    elseif result.status == "unavailable" and visible.unavailable then
      label, highlight = format_label(options.icons.error, "unavailable"), "PackageInfoError"
    elseif dep.error_kind == "not_found" and visible.not_found then
      label, highlight = format_label(options.icons.error, "registry/access"), "PackageInfoError"
    elseif dep.kind == "unsupported" and visible.unsupported then
      label, highlight = format_label(options.icons.error, "unsupported"), "Comment"
    end
    if not label and visible.installed and dep.installed and dep.installed.version then
      label, highlight = format_label(options.icons.installed, dep.installed.version), "Comment"
    end
    if row and label then
      rows[row] = rows[row] or {}
      table.insert(rows[row], { options.prefix .. label, highlight })
    end
  end
  if state.error and visible.error then
    rows[0] = rows[0] or {}
    table.insert(rows[0], { options.prefix .. format_label(options.icons.error, state.error), "PackageInfoError" })
  end
  return rows
end
---@param state? PackageInfoBuffer
---@param row integer
---@param now number
---@return string[]
function M.info(state, row, now)
  local lines = {}
  for _, dep in ipairs(state and state.context and state.context.dependencies or {}) do
    if assert(state).lines[dep.section .. ":" .. dep.name] == row then
      local installed, result = dep.installed or {}, dep.result or {}
      local details = {
        "**" .. dep.name .. "** (" .. dep.section .. ")",
        "Declared: `" .. dep.spec .. "`",
        "Registry package: `" .. (dep.target or dep.name) .. "`",
        "Installed: "
          .. (installed.version or ("unknown — " .. (installed.reason or "local/unsupported declaration"))),
        "Wanted: " .. (result.wanted or "unavailable"),
        "Latest tag: " .. (result.latest or "unavailable"),
        "Registry cache age: "
          .. (dep.registry_time and math.floor((now - dep.registry_time) / 1000) .. "s" or "unknown"),
        "Status: "
          .. (
            dep.error
            or dep.reason
            or (dep.kind == "local" and "local dependency")
            or result.status
            or assert(state).error
            or "checking"
          ),
        "",
      }
      for _, line in ipairs(details) do
        lines[#lines + 1] = line
      end
    end
  end
  if #lines == 0 then
    lines = { "No dependency at the cursor. " .. (state and state.error or "Run :PackageInfoStatus for details.") }
  elseif state and state.context and state.context.overrides then
    table.insert(lines, "Overrides/resolutions exist; available versions do not predict the next install result.")
  end
  return lines
end
---@param state? PackageInfoBuffer
---@param helper PackageInfoHelper
---@param queue PackageInfoQueue
---@param now number
---@return string[]
---@param config? PackageInfoConfig
function M.status(state, helper, queue, now, config)
  config = config or require("package_info.core.config").defaults()
  local context = state and state.context or {}
  local lines = {
    "Helper: " .. helper.state .. (helper.error and " — " .. helper.error or ""),
    "Manager: " .. (context.manager or "unknown") .. (context.major and " " .. context.major or ""),
    "Package: " .. (context.dir or "unknown"),
    "Workspace: " .. (context.root or "unknown"),
    "Annotations: " .. (config.display.enabled and not (state and state.disabled) and "enabled" or "disabled"),
    "Automatic checks: enter=" .. tostring(config.auto_refresh.on_enter) .. ", save=" .. tostring(
      config.auto_refresh.on_save
    ),
    "Last check started: "
      .. (state and state.checked_at and math.floor((now - state.checked_at) / 1000) .. "s ago" or "never"),
    "Registry backend: " .. (state and state.backend or "preparing"),
    "Registry progress: "
      .. (state and state.network and state.network.completed .. "/" .. state.network.total or "unknown"),
    "Processes: " .. queue.active .. " active, " .. #queue.waiting .. " queued",
    "Error: " .. (state and state.error or "none"),
  }
  for _, dep in ipairs(context.dependencies or {}) do
    if dep.error then
      table.insert(lines, dep.name .. ": " .. dep.error)
    end
  end
  return lines
end
return M
