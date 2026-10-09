local config = require("package_info.core.config")
local requests = require("package_info.core.requests")
local registry = require("package_info.core.registry")
local cache = require("package_info.core.cache")
local protocol = require("package_info.core.protocol")
local presentation = require("package_info.core.presentation")
local fast_registry_factory = require("package_info.core.fast_registry")
local filters = require("package_info.core.filters")
local render_queue = require("package_info.core.render_queue")
local Factory = {}
---@param adapter PackageInfoAdapter
---@return PackageInfoController
function Factory.new(adapter)
  local helper, queue = adapter.helper, adapter.queue
  local M = {
    buffers = {},
    cache = {},
    manager_failures = {},
    manager_versions = {},
    config = config.normalize(),
    active = false,
  }
  ---@cast M PackageInfoController
  local fast_registry = fast_registry_factory.new(adapter, function()
    return M.config
  end)
  local now = adapter.now
  ---@type table<integer, PackageInfoAnnotations>
  local rendered = {}
  ---@param buf integer
  ---@param state PackageInfoBuffer
  ---@return boolean
  local function valid(buf, state)
    return M.active and requests.valid(M.buffers[buf], state, adapter.buffer(buf))
  end
  M.renderer = render_queue.new(adapter.schedule, function(buf, state)
    if valid(buf, state) then
      local rows = presentation.annotations(state, M.config.display)
      if not presentation.same_annotations(rendered[buf], rows) then
        adapter.render(buf, rows)
        rendered[buf] = rows
      end
    end
  end, adapter.notify)
  ---@param buf integer
  ---@param state PackageInfoBuffer
  local function render(buf, state)
    if valid(buf, state) then
      M.renderer.request(buf, state)
    end
  end
  ---@param state PackageInfoBuffer
  ---@param method string
  ---@param input table
  ---@param callback PackageInfoReply
  local function request(state, method, input, callback)
    local ticket = helper.request(method, input, callback)
    state.tickets[#state.tickets + 1] = ticket
  end
  ---@param buf integer
  ---@param disabled? boolean
  local function invalidate(buf, disabled)
    M.renderer.cancel(buf)
    rendered[buf] = nil
    local previous = M.buffers[buf]
    M.buffers[buf] = disabled and { disabled = true, lines = {}, tickets = {} } or nil
    if adapter.buffer(buf) ~= nil then
      adapter.clear(buf)
    end
    if previous then
      for _, ticket in ipairs(previous.tickets or {}) do
        helper.cancel(ticket)
      end
      helper.cancel(previous.network_ticket)
      queue.cancel()
    end
  end
  ---@param buf integer
  ---@param state PackageInfoBuffer
  ---@param dep PackageInfoDependency
  ---@param entry PackageInfoCacheEntry
  local function compare(buf, state, dep, entry)
    request(state, "compare", { dep = dep, stdout = entry.stdout }, function(raw, err)
      local result = protocol.comparison(raw)
      if raw ~= nil and not result then
        err = "Registry returned invalid metadata"
      end
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
  ---@param buf integer
  ---@param state PackageInfoBuffer
  ---@param force? boolean
  local function query(buf, state, force)
    local context = assert(state.context)
    local targets, order, missing = {}, {}, {}
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
      local key = registry.metadata_key(context, target)
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
      if cache.fresh(cached, now(), force, M.config.cache) then
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
        timeout = M.config.timeouts.registry,
        cancelled = function()
          return not valid(buf, state)
        end,
        callback = function(result)
          local records = batch and registry.batch_results(result.stdout, names, adapter.decode, adapter.encode) or {}
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
              cache.prune(M.cache, now(), M.config.cache)
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
    cache.prune(M.cache, now(), M.config.cache)
  end
  ---@param buf integer
  ---@param state PackageInfoBuffer
  ---@param force? boolean
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
  ---@param buf integer
  ---@param state PackageInfoBuffer
  ---@param force? boolean
  local function resolve_installed(buf, state, force)
    local context = assert(state.context)
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
        adapter.encode({ dir = context.dir, root = context.root, dependencies = declarations }),
      },
      timeout = M.config.timeouts.manager,
      cancelled = function()
        return not valid(buf, state)
      end,
      callback = function(result)
        local ok, raw_installed = pcall(adapter.decode, result.stdout or "")
        local installed = ok and protocol.installed_list(raw_installed)
        if result.code == 0 and installed then
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
  ---@param buf? integer
  ---@param force? boolean
  function M.refresh(buf, force)
    if not M.active then
      return
    end
    buf = buf or adapter.current().buf
    local host = adapter.buffer(buf)
    if not host or not host.path:match("/package%.json$") then
      return
    end
    if filters.excluded_project(host.path, M.config.exclude.projects) then
      invalidate(buf)
      return
    end
    if M.buffers[buf] and M.buffers[buf].disabled then
      return
    end
    if force then
      helper.retry()
    end
    invalidate(buf)
    if adapter.buffer(buf).modified then
      return
    end
    local host = config.copy(assert(adapter.buffer(buf)))
    local parsed, err
    local parsed_ok
    parsed_ok, parsed, err = pcall(adapter.manifest, buf)
    if not parsed_ok then
      parsed, err = nil, "Cannot parse package manifest"
    end
    local state = {
      path = host.path,
      tick = host.tick,
      lines = parsed and parsed.lines or {},
      tickets = {},
      checked_at = now(),
      error = err,
    }
    M.buffers[buf] = state
    if not valid(buf, state) then
      invalidate(buf)
      return
    end
    if not parsed then
      render(buf, state)
      return
    end
    request(state, "inspect", {
      path = state.path,
      manifest = parsed.text,
      managers = M.config.managers,
      environment_hash = adapter.environment_hash(),
      user_config = adapter.user_config(),
    }, function(raw, error)
      local context = protocol.context(raw)
      if not context and not error then
        error = "Invalid helper context"
      end
      if not valid(buf, state) then
        return
      end
      state.context, state.error = context, error or context and context.error
      if state.error then
        render(buf, state)
        return
      end
      context = assert(context)
      if filters.excluded_project(context.root, M.config.exclude.projects) then
        invalidate(buf)
        return
      end
      context.dependencies = filters.dependencies(context.dependencies, M.config)
      if #context.dependencies == 0 then
        return
      end
      local probe_key = context.dir .. ":" .. context.registry_fingerprint
      local failure = M.manager_failures[probe_key]
      if not force and failure and now() - failure.time < M.config.cache.retry then
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
      if not force and version and now() - version.time < M.config.cache.ttl then
        context.major = version.major
        resolve_installed(buf, state, force)
        return
      end
      if not adapter.executable(context.manager) then
        manager_failed("Package manager " .. context.manager .. " is unavailable")
        return
      end
      queue.submit({
        project = context.root,
        cwd = context.dir,
        command = { context.manager, "--version" },
        timeout = M.config.timeouts.manager,
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
            M.manager_versions[probe_key] = { major = assert(major), time = now() }
            resolve_installed(buf, state, force)
          end
        end,
      })
    end)
  end

  ---@param buf integer
  ---@param disabled? boolean
  function M.invalidate(buf, disabled)
    invalidate(buf, disabled)
  end
  function M.info()
    local cursor = adapter.current()
    adapter.float(presentation.info(M.buffers[cursor.buf], cursor.row, now()), M.config.display.float)
  end
  function M.status()
    adapter.float(
      presentation.status(M.buffers[adapter.current().buf], helper, queue, now(), M.config),
      M.config.display.float
    )
  end
  function M.toggle()
    local buf = adapter.current().buf
    if M.buffers[buf] and M.buffers[buf].disabled then
      M.buffers[buf] = nil
      M.refresh(buf)
    else
      invalidate(buf, true)
    end
  end
  function M.teardown()
    M.active = false
    M.renderer.teardown()
    for buf in pairs(M.buffers) do
      invalidate(buf)
    end
    queue.teardown()
    helper.stop()
    fast_registry.clear()
    M.cache, M.manager_failures, M.manager_versions = {}, {}, {}
    adapter.uninstall()
  end
  ---@param input? PackageInfoOptions
  function M.setup(input)
    M.teardown()
    local messages
    M.config, messages = config.normalize(input)
    helper.configure(M.config)
    queue.configure(M.config.concurrency)
    if adapter.configure then
      adapter.configure(M.config)
    end
    for _, message in ipairs(messages) do
      adapter.notify(message)
    end
    M.active = true
    local ok, err = pcall(adapter.install, M)
    if not ok then
      M.teardown()
      adapter.notify(tostring(err))
    end
  end
  return M
end
return Factory
