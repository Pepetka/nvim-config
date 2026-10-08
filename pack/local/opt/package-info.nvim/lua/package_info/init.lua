local helper = require("package_info.helper")
local queue = require("package_info.queue")
local manifest = require("package_info.manifest")
local registry = require("package_info.registry")
local fast_registry = require("package_info.fast_registry")
local M = {
  buffers = {},
  cache = {},
  manager_failures = {},
  manager_versions = {},
  config = { managers = {}, fast_registry = true },
}
M.namespace = vim.api.nvim_create_namespace("package-info")
local TTL, RETRY = 15 * 60 * 1000, 30000
local function now()
  return vim.uv.hrtime() / 1000000
end
local function environment_hash()
  local environment = vim.fn.environ()
  local names = vim.tbl_keys(environment)
  table.sort(names)
  local values = {}
  for _, name in ipairs(names) do
    table.insert(values, { name, environment[name] })
  end
  return vim.fn.sha256(vim.json.encode(values))
end
local function valid(buf, state)
  return vim.api.nvim_buf_is_valid(buf)
    and M.buffers[buf] == state
    and not state.disabled
    and vim.api.nvim_buf_get_changedtick(buf) == state.tick
    and vim.api.nvim_buf_get_name(buf) == state.path
    and not vim.bo[buf].modified
end
local function render(buf, state)
  if not valid(buf, state) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)
  local rows = {}
  for _, dep in ipairs(state.context and state.context.dependencies or {}) do
    local row = state.lines[dep.section .. ":" .. dep.name]
    local result = dep.result or {}
    local label, highlight
    if result.status == "update" then
      label, highlight = "󰚰 " .. result.wanted, "PackageInfoUpdate"
    elseif result.status == "major" then
      label, highlight = "󰚰 latest " .. result.latest, "PackageInfoLatest"
    elseif result.status == "unavailable" then
      label, highlight = "󰂡 unavailable", "PackageInfoError"
    elseif dep.error_kind == "not_found" then
      label, highlight = "󰂡 registry/access", "PackageInfoError"
    elseif dep.kind == "unsupported" then
      label, highlight = "󰂡 unsupported", "Comment"
    end
    if not label and dep.installed and dep.installed.version then
      label, highlight = "󰏖 " .. dep.installed.version, "Comment"
    end
    if row and label then
      rows[row] = rows[row] or {}
      table.insert(rows[row], { "  " .. label, highlight })
    end
  end
  if state.error then
    rows[0] = rows[0] or {}
    table.insert(rows[0], { "  󰂡 " .. state.error, "PackageInfoError" })
  end
  for row, chunks in pairs(rows) do
    vim.api.nvim_buf_set_extmark(buf, M.namespace, row, 0, { virt_text = chunks, virt_text_pos = "eol" })
  end
end
local function invalidate(buf, disabled)
  local previous = M.buffers[buf]
  M.buffers[buf] = disabled and { disabled = true } or nil
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, M.namespace, 0, -1)
  end
  if previous then
    helper.cancel(previous.network_ticket)
    queue.cancel()
  end
end
local function compare(buf, state, dep, entry)
  helper.request("compare", { dep = dep, stdout = entry.stdout }, function(result, err)
    if not valid(buf, state) then
      return
    end
    dep.result, dep.error = result, err
    dep.registry_time = entry.time
    if err then
      entry.stdout, entry.error, entry.kind = nil, err, "metadata"
      dep.error_kind = "metadata"
      state.error = "Registry returned invalid metadata; see :PackageInfo"
    end
    render(buf, state)
  end)
end
local function query(buf, state, force)
  local context, targets, order, missing = state.context, {}, {}, {}
  for _, dep in ipairs(context.dependencies) do
    if dep.target then
      if not targets[dep.target] then
        targets[dep.target] = {}
        table.insert(order, dep.target)
      end
      table.insert(targets[dep.target], dep)
    end
  end
  for _, target in ipairs(order) do
    local deps = targets[target]
    local key = context.root
      .. ":"
      .. context.dir
      .. ":"
      .. context.manager
      .. ":"
      .. context.major
      .. ":"
      .. context.fingerprint
      .. ":"
      .. target
    local cached = M.cache[key]
    local function accept(entry)
      if not valid(buf, state) then
        return
      end
      for _, dep in ipairs(deps) do
        if entry.stdout then
          compare(buf, state, dep, entry)
        else
          dep.error, dep.error_kind = entry.error, entry.kind
          if entry.kind ~= "not_found" then
            state.error = entry.error
          end
        end
      end
      render(buf, state)
    end
    if not force and cached and now() - cached.time < (cached.error and RETRY or TTL) then
      accept(cached)
    else
      table.insert(missing, { target = target, key = key, accept = accept })
    end
  end
  local function dispatch(items, batch)
    local names = {}
    for _, item in ipairs(items) do
      table.insert(names, item.target)
    end
    local command = batch and registry.batch_command(context, names) or registry.command(context, names[1])
    queue.submit({
      project = context.root,
      cwd = context.dir,
      command = command,
      cancelled = function()
        return not valid(buf, state)
      end,
      callback = function(result)
        local records = batch and registry.batch_results(result.stdout, names) or {}
        for _, item in ipairs(items) do
          local stdout
          if batch then
            stdout = records[item.target]
          elseif result.code == 0 then
            stdout = result.stdout
          end
          if batch and not stdout and result.code ~= 124 and result.signal ~= 15 and result.signal ~= 9 then
            -- Yarn aborts on the first error. Retry unresolved names separately using the same manager/rc.
            dispatch({ item }, false)
          else
            local entry = { time = now() }
            if stdout then
              entry.stdout = stdout
            else
              entry.kind, entry.error = registry.error(result)
            end
            M.cache[item.key] = entry
            item.accept(entry)
          end
        end
      end,
    })
  end
  if context.manager == "yarn" and context.major > 1 then
    local groups = {}
    for _, item in ipairs(missing) do
      local scope = item.target:match("^@([^/]+)/") or ""
      groups[scope] = groups[scope] or {}
      table.insert(groups[scope], item)
    end
    for _, items in pairs(groups) do
      for index = 1, #items, 8 do
        local batch = {}
        for offset = index, math.min(index + 7, #items) do
          table.insert(batch, items[offset])
        end
        dispatch(batch, #batch > 1)
      end
    end
  else
    for _, item in ipairs(missing) do
      dispatch({ item }, false)
    end
  end
  local size = 0
  for key, entry in pairs(M.cache) do
    size = size + 1
    if now() - entry.time > TTL or size > 1000 then
      M.cache[key] = nil
    end
  end
end
local function check_registry(buf, state, force)
  if M.config.fast_registry then
    fast_registry.check(buf, state, force, valid, render, function()
      query(buf, state, force)
    end)
  else
    state.backend = "manager CLI"
    query(buf, state, force)
  end
end
local function resolve_installed(buf, state, force)
  local context = state.context
  if not context.pnp then
    check_registry(buf, state, force)
    return
  end
  local declarations = {}
  for _, dep in ipairs(context.dependencies) do
    table.insert(declarations, { name = dep.name, target = dep.target })
  end
  queue.submit({
    project = context.root,
    cwd = context.dir,
    command = {
      "yarn",
      "node",
      helper.runtime .. "/index.cjs",
      "--pnp",
      vim.json.encode({ dir = context.dir, root = context.root, dependencies = declarations }),
    },
    timeout = 5000,
    cancelled = function()
      return not valid(buf, state)
    end,
    callback = function(result)
      local ok, installed = pcall(vim.json.decode, result.stdout or "")
      if result.code == 0 and ok and type(installed) == "table" then
        for index, dep in ipairs(context.dependencies) do
          dep.installed = installed[index] or { state = "unknown", reason = "PnP lookup unavailable" }
        end
      else
        state.error = "PnP installed version lookup failed"
      end
      render(buf, state)
      check_registry(buf, state, force)
    end,
  })
end
function M.refresh(buf, force)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) or vim.fs.basename(vim.api.nvim_buf_get_name(buf)) ~= "package.json" then
    return
  end
  if M.buffers[buf] and M.buffers[buf].disabled then
    return
  end
  if force then
    helper.retry()
  end
  invalidate(buf)
  if vim.bo[buf].modified then
    return
  end
  local parsed, err = manifest.parse(buf)
  local state = {
    path = vim.api.nvim_buf_get_name(buf),
    tick = vim.api.nvim_buf_get_changedtick(buf),
    lines = parsed and parsed.lines or {},
    checked_at = now(),
    error = err,
  }
  M.buffers[buf] = state
  if not parsed then
    render(buf, state)
    return
  end
  helper.request("inspect", {
    path = state.path,
    manifest = parsed.text,
    managers = M.config.managers,
    environment_hash = environment_hash(),
    user_config = vim.env.NPM_CONFIG_USERCONFIG or vim.env.npm_config_userconfig,
  }, function(context, error)
    if not valid(buf, state) then
      return
    end
    state.context, state.error = context, error or context and context.error
    if state.error then
      render(buf, state)
      return
    end
    if #context.dependencies == 0 then
      return
    end
    local probe_key = context.dir .. ":" .. context.registry_fingerprint
    local failure = M.manager_failures[probe_key]
    if not force and failure and now() - failure.time < RETRY then
      state.error = failure.error
      render(buf, state)
      return
    end
    local function manager_failed(message)
      M.manager_failures[probe_key] = { time = now(), error = message }
      state.error = message
      render(buf, state)
    end
    render(buf, state)
    local version = M.manager_versions[probe_key]
    if not force and version and now() - version.time < TTL then
      context.major = version.major
      resolve_installed(buf, state, force)
      return
    end
    if vim.fn.executable(context.manager) == 0 then
      manager_failed("Package manager " .. context.manager .. " is unavailable")
      return
    end
    queue.submit({
      project = context.root,
      cwd = context.dir,
      command = { context.manager, "--version" },
      timeout = 5000,
      cancelled = function()
        return not valid(buf, state)
      end,
      callback = function(result)
        local major, version_error = registry.compatible(context, result.stdout)
        if result.code ~= 0 then
          local _, message = registry.error(result)
          version_error = message
        end
        context.major = major
        if version_error then
          manager_failed(version_error)
        else
          M.manager_failures[probe_key] = nil
          M.manager_versions[probe_key] = { major = major, time = now() }
          resolve_installed(buf, state, force)
        end
      end,
    })
  end)
end
local function float(lines)
  vim.lsp.util.open_floating_preview(lines, "markdown", { border = "rounded", focusable = true })
end
function M.info()
  local state = M.buffers[vim.api.nvim_get_current_buf()]
  local row, lines = vim.api.nvim_win_get_cursor(0)[1] - 1, {}
  for _, dep in ipairs(state and state.context and state.context.dependencies or {}) do
    if state.lines[dep.section .. ":" .. dep.name] == row then
      local installed, result = dep.installed or {}, dep.result or {}
      vim.list_extend(lines, {
        "**" .. dep.name .. "** (" .. dep.section .. ")",
        "Declared: `" .. dep.spec .. "`",
        "Registry package: `" .. (dep.target or dep.name) .. "`",
        "Installed: " .. (installed.version or "unknown — " .. (installed.reason or "local/unsupported declaration")),
        "Wanted: " .. (result.wanted or "unavailable"),
        "Latest tag: " .. (result.latest or "unavailable"),
        "Registry cache age: "
          .. (dep.registry_time and math.floor((now() - dep.registry_time) / 1000) .. "s" or "unknown"),
        "Status: "
          .. (
            dep.error
            or dep.reason
            or (dep.kind == "local" and "local dependency")
            or result.status
            or state.error
            or "checking"
          ),
        "",
      })
    end
  end
  if #lines == 0 then
    lines = { "No dependency at the cursor. " .. (state and state.error or "Run :PackageInfoStatus for details.") }
  elseif state.context.overrides then
    table.insert(lines, "Overrides/resolutions exist; available versions do not predict the next install result.")
  end
  float(lines)
end
function M.status()
  local state = M.buffers[vim.api.nvim_get_current_buf()]
  local context = state and state.context or {}
  local lines = {
    "Helper: " .. helper.state .. (helper.error and " — " .. helper.error or ""),
    "Manager: " .. (context.manager or "unknown") .. (context.major and " " .. context.major or ""),
    "Package: " .. (context.dir or "unknown"),
    "Workspace: " .. (context.root or "unknown"),
    "Annotations/automatic checks: " .. (state and state.disabled and "disabled" or "enabled"),
    "Last check started: "
      .. (state and state.checked_at and math.floor((now() - state.checked_at) / 1000) .. "s ago" or "never"),
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
  float(lines)
end
function M.setup(config)
  M.config = vim.tbl_deep_extend("force", M.config, config or {})
  local function highlights()
    vim.api.nvim_set_hl(0, "PackageInfoUpdate", { link = "DiagnosticInfo" })
    vim.api.nvim_set_hl(0, "PackageInfoLatest", { link = "DiagnosticWarn" })
    vim.api.nvim_set_hl(0, "PackageInfoError", { link = "DiagnosticError" })
  end
  highlights()
  local group = vim.api.nvim_create_augroup("package-info", { clear = true })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = {
      "package.json",
      "package-lock.json",
      "npm-shrinkwrap.json",
      "yarn.lock",
      "pnpm-lock.yaml",
      "pnpm-workspace.yaml",
      ".npmrc",
      ".yarnrc",
      ".yarnrc.yml",
      ".pnp.cjs",
    },
    callback = function(event)
      local directory = vim.fs.dirname(vim.api.nvim_buf_get_name(event.buf))
      for buf, state in pairs(M.buffers) do
        if buf ~= event.buf and state.path and state.path:sub(1, #directory + 1) == directory .. "/" then
          invalidate(buf, state.disabled)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    pattern = "package.json",
    callback = function(event)
      M.refresh(event.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufUnload", "BufWipeout", "BufFilePost" }, {
    group = group,
    callback = function(event)
      local state = M.buffers[event.buf]
      if
        state
        and (
          event.event ~= "TextChanged" and event.event ~= "TextChangedI"
          or vim.api.nvim_buf_get_changedtick(event.buf) ~= state.tick
          or vim.bo[event.buf].modified
        )
      then
        invalidate(event.buf, state.disabled)
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, state in pairs(M.buffers) do
        helper.cancel(state.network_ticket)
      end
      M.buffers = {}
      queue.cancel()
      helper.stop()
    end,
  })
  local commands = {
    PackageInfo = { callback = M.info },
    PackageInfoStatus = { callback = M.status },
    PackageInfoRefresh = {
      callback = function(args)
        M.refresh(nil, args.bang)
      end,
      bang = true,
    },
    PackageInfoToggle = {
      callback = function()
        local buf = vim.api.nvim_get_current_buf()
        local state = M.buffers[buf]
        if state and state.disabled then
          M.buffers[buf] = nil
          M.refresh(buf)
        else
          invalidate(buf, true)
        end
      end,
    },
  }
  for name, command in pairs(commands) do
    vim.api.nvim_create_user_command(name, command.callback, { bang = command.bang or false, force = true })
  end
end
return M
