local rules = require("dashboard.core.config")
local controller = require("dashboard.controller")
local M = {}

---@class DashboardFixture
---@field adapter DashboardAdapter
---@field api DashboardController
---@field contexts table<integer, DashboardContext>
---@field live table<integer, DashboardSession>
---@field errors string[]
---@field queue DashboardTestAction[]
---@field configured? DashboardConfig
---@field styles DashboardStyles
---@field installs integer
---@field closes integer
---@field writes integer
---@field fail? "create" | "apply" | "configure" | "close"
---@field aliases integer[]
---@field commands string[]

---@return DashboardFixture
function M.new()
  local adapter = {}
  ---@cast adapter DashboardAdapter
  ---@type DashboardFixture
  local state = {
    adapter = adapter,
    api = controller.new(adapter),
    contexts = {},
    live = {},
    errors = {},
    queue = {},
    styles = {},
    installs = 0,
    closes = 0,
    writes = 0,
    aliases = {},
    commands = {},
  }
  local serial = 100

  ---@param operation string
  ---@return nil
  local function fail(operation)
    if state.fail == operation then
      state.fail = nil
      error("injected " .. operation .. " failure")
    end
  end

  ---@param win? integer
  ---@return DashboardContext
  function adapter.context(win)
    if not win or win == 0 then
      win = 1
    end
    state.contexts[win] = state.contexts[win] or { win = win, source_buf = win + 1000, width = 80, height = 40 }
    return rules.copy(state.contexts[win])
  end

  ---@param text string
  ---@return integer
  function adapter.measure(text)
    return #text
  end

  ---@param key string
  ---@return string
  function adapter.normalize_key(key)
    return (key:gsub("<[^>]+>", string.lower))
  end

  ---@param ctx DashboardContext
  ---@param track fun(session: DashboardSession): nil
  ---@return DashboardSession
  function adapter.create(ctx, track)
    fail("create")
    serial = serial + 1
    local session =
      { win = ctx.win, buf = serial, source_buf = ctx.source_buf, document = { lines = {}, spans = {}, targets = {} } }
    state.live[ctx.win] = session
    state.contexts[ctx.win].source_buf = serial
    track(session)
    return session
  end

  ---@param session DashboardSession
  ---@return boolean
  function adapter.valid(session)
    return state.live[session.win] == session
  end

  ---@param session DashboardSession
  ---@param document DashboardDocument
  ---@param selected? DashboardTarget
  ---@return nil
  function adapter.apply(session, document, selected)
    fail("apply")
    state.writes = state.writes + 1
  end

  ---@param session DashboardSession
  ---@param target? DashboardTarget
  ---@return nil
  function adapter.select(session, target) end

  ---@param session DashboardSession
  ---@param restore boolean
  ---@return nil
  function adapter.close(session, restore)
    fail("close")
    state.closes = state.closes + 1
    state.live[session.win] = nil
    state.contexts[session.win].source_buf = session.source_buf
  end

  ---@param options DashboardConfig
  ---@param styles DashboardStyles
  ---@return nil
  function adapter.configure(options, styles)
    fail("configure")
    state.configured, state.styles = options, styles
  end

  ---@param styles DashboardStyles
  ---@return nil
  function adapter.styles(styles)
    state.styles = styles
  end

  ---@param callbacks DashboardCallbacks
  ---@return nil
  function adapter.install(callbacks)
    state.installs = state.installs + 1
  end

  ---@return nil
  function adapter.uninstall()
    state.configured = nil
  end

  ---@return nil
  function adapter.reconcile() end

  ---@return integer[]
  function adapter.aliases()
    local result = state.aliases
    state.aliases = {}
    return result
  end

  ---@param callback DashboardTestAction
  ---@return nil
  function adapter.schedule(callback)
    state.queue[#state.queue + 1] = callback
  end

  ---@param action DashboardRun
  ---@param context DashboardContext
  ---@return nil
  function adapter.run(action, context)
    if type(action) == "function" then
      action(context)
    else
      state.commands[#state.commands + 1] = action
    end
  end

  ---@param message string
  ---@return nil
  function adapter.notify(message)
    state.errors[#state.errors + 1] = message
  end

  return state
end

---@param state DashboardFixture
---@return nil
function M.flush(state)
  local queue = state.queue
  state.queue = {}
  for _, callback in ipairs(queue) do
    callback()
  end
end

return M
