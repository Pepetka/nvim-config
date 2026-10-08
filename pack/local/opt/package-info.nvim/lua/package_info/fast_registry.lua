local helper = require("package_info.helper")
local queue = require("package_info.queue")
local M = { clients = {} }
local TTL = 15 * 60 * 1000

function M.check(buf, state, force, valid, render, fallback)
  local context = state.context
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
      function(event, err, done)
        if not alive() then
          return
        end
        if err then
          state.error = "Parallel registry check failed; refresh to retry"
        elseif event then
          if event.records then
            for _, record in ipairs(event.records) do
              local dep = declarations[record.section .. ":" .. record.name]
              if dep then
                dep.result, dep.error, dep.error_kind = record.result, record.error, record.kind
                dep.registry_time = vim.uv.hrtime() / 1000000 - record.age_ms
                dep.cached = record.cached
                if record.error and record.kind ~= "not_found" then
                  state.error = record.error
                end
              end
            end
            state.network.completed, state.network.total = event.completed, event.total
          end
        end
        if done or err then
          state.network_ticket = nil
        end
        render(buf, state)
      end,
      { timeout = math.max(30000, #context.dependencies * 15000 + 10000) }
    )
  end
  local cached = M.clients[key]
  if cached and cached.job == helper.job and vim.uv.hrtime() / 1000000 - cached.time < TTL and not force then
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
  local remaining = vim.tbl_count(commands)
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
    helper.request(
      "configure",
      { context = context, npm_path = vim.fn.exepath("npm"), environment = vim.fn.environ(), exports = exports },
      function(result, err)
        if not alive() then
          return
        end
        if err or not result or result.fallback then
          state.backend = "manager CLI (configuration compatibility)"
          fallback()
        else
          M.clients[key] = { client = result.client, job = helper.job, time = vim.uv.hrtime() / 1000000 }
          start(result.client)
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
      timeout = 5000,
      cancelled = function()
        return not alive()
      end,
      callback = function(result)
        if result.code == 0 then
          exports[name] = result.stdout
          if name == "config" and context.manager == "yarn" and context.major > 1 then
            local settings = {}
            for line in (result.stdout or ""):gmatch("[^\n]+") do
              local ok, value = pcall(vim.json.decode, line)
              if ok and type(value) == "table" and value.key then
                settings[value.key] = value
              end
            end
            for _, field in ipairs({ "npmAuthToken", "npmAuthIdent", "npmScopes", "npmRegistries", "networkSettings" }) do
              local setting = settings[field]
              local configured = not setting
                or type(setting.source) == "string" and setting.source ~= "" and setting.source ~= "<default>"
                or setting.effective ~= nil
                  and setting.effective ~= vim.NIL
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

return M
