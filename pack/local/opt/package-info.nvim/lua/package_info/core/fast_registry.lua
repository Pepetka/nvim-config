local protocol = require("package_info.core.protocol")
local Factory = {}
---@param adapter PackageInfoAdapter
---@param get_config? fun(): PackageInfoConfig
---@return PackageInfoFastRegistry
function Factory.new(adapter, get_config)
  get_config = get_config or require("package_info.core.config").defaults
  local helper, queue = adapter.helper, adapter.queue
  local M = { clients = {} }
  ---@cast M PackageInfoFastRegistry

  function M.check(buf, state, force, valid, render, fallback)
    local config = get_config()
    local function request(method, input, callback)
      local ticket = helper.request(method, input, callback)
      state.tickets[#state.tickets + 1] = ticket
    end
    local context = assert(state.context)
    local key = context.dir .. ":" .. context.manager .. ":" .. context.major .. ":" .. context.registry_fingerprint
    local function alive()
      return valid(buf, state)
    end
    local function start(client)
      if not alive() then
        return
      end
      state.backend = "parallel registry"
      state.network = { completed = 0, total = 0 }
      local declarations = {}
      for _, dep in ipairs(context.dependencies) do
        declarations[dep.section .. ":" .. dep.name] = dep
      end
      state.network_ticket = helper.request(
        "check",
        { client = client, context = context, force = force },
        function(raw, err, done)
          local event = protocol.event(raw)
          if raw ~= nil and not event then
            err = "Invalid helper event"
          end
          if not alive() then
            return
          end
          if event and event.reconfigure and done and not err then
            M.clients[key] = nil
            state.network_ticket = nil
            state.client_retries = (state.client_retries or 0) + 1
            if state.client_retries > 1 then
              state.backend = "manager CLI (registry client unavailable)"
              fallback()
            else
              M.check(buf, state, force, valid, render, fallback)
            end
            return
          end
          if event and event.reconfigure then
            err = "Invalid helper event"
          end
          if err then
            state.error = "Parallel registry check failed; refresh to retry"
          elseif event then
            if event.records then
              for _, record in ipairs(event.records) do
                local dep = declarations[record.section .. ":" .. record.name]
                if dep then
                  dep.result, dep.error, dep.error_kind = record.result, record.error, record.kind
                  dep.registry_time = adapter.now() - record.age_ms
                  dep.cached = record.cached
                  if record.error and record.kind ~= "not_found" then
                    state.error = record.error
                  end
                end
              end
              state.network.completed, state.network.total = assert(event.completed), assert(event.total)
            end
          end
          if done or err then
            state.network_ticket = nil
          end
          render(buf, state)
        end,
        {
          timeout = math.min(
            2147483647,
            math.max(
              2 * config.timeouts.registry,
              config.timeouts.helper,
              #context.dependencies * config.timeouts.registry + 2 * config.timeouts.helper
            )
          ),
        }
      )
    end
    local cached = M.clients[key]
    if cached and cached.job == helper.job and adapter.now() - cached.time < config.cache.client_ttl and not force then
      start(M.clients[key].client)
      return
    end
    local exports, commands = {}, {}
    if context.manager == "yarn" and context.major > 1 then
      commands.config = { "yarn", "config", "--json" }
    elseif context.manager == "yarn" then
      commands.config = { "yarn", "config", "list", "--json" }
    elseif context.manager == "pnpm" then
      commands.config = { "pnpm", "config", "list", "--json" }
    end
    local remaining = 0
    for _ in pairs(commands) do
      remaining = remaining + 1
    end
    local failed = false
    local function configure()
      if not alive() then
        return
      end
      if failed then
        state.backend = "manager CLI (configuration compatibility)"
        fallback()
        return
      end
      request(
        "configure",
        { context = context, npm_path = adapter.npm_path(), environment = adapter.environment(), exports = exports },
        function(raw, err)
          local result = protocol.configuration(raw)
          if not alive() then
            return
          end
          if err or not result or result.fallback then
            state.backend = "manager CLI (configuration compatibility)"
            fallback()
          else
            M.clients[key] = { client = assert(result.client), job = helper.job, time = adapter.now() }
            start(assert(result.client))
          end
        end
      )
    end
    if remaining == 0 then
      configure()
      return
    end
    local submit
    submit = function(name, command)
      queue.submit({
        project = context.root,
        cwd = context.dir,
        command = command,
        timeout = config.timeouts.manager,
        cancelled = function()
          return not alive()
        end,
        callback = function(result)
          if result.code == 0 then
            exports[name] = result.stdout
            if name == "config" and context.manager == "yarn" and context.major > 1 then
              local settings = {}
              for line in (result.stdout or ""):gmatch("[^\n]+") do
                local ok, value = pcall(adapter.decode, line)
                if ok and type(value) == "table" and value.key then
                  settings[value.key] = value
                end
              end
              for _, field in ipairs({ "npmAuthToken", "npmAuthIdent", "npmScopes", "npmRegistries", "networkSettings" }) do
                local setting = settings[field]
                local configured = not setting
                  or type(setting.source) == "string" and setting.source ~= "" and setting.source ~= "<default>"
                  or setting.effective ~= nil
                    and setting.effective ~= adapter.null
                    and (type(setting.effective) ~= "table" or next(setting.effective) ~= nil)
                if configured then
                  remaining = remaining + 1
                  submit(field, { "yarn", "config", "get", field, "--json", "--no-redacted" })
                end
              end
            end
          else
            failed = true
          end
          remaining = remaining - 1
          if remaining == 0 then
            configure()
          end
        end,
      })
    end
    for name, command in pairs(commands) do
      submit(name, command)
    end
  end

  function M.clear()
    M.clients = {}
  end
  return M
end
return Factory
