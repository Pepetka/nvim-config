local helper_factory = require("package_info.core.helper")
local queue_factory = require("package_info.core.queue")
local controller_factory = require("package_info.controller")
local M = {}

---@class PackageInfoTestTimer
---@field at number
---@field callback PackageInfoCancel
---@field cancelled boolean

---@class PackageInfoTestHelper
---@field now number
---@field hold boolean
---@field starts integer
---@field stops integer
---@field sent table[]
---@field timers PackageInfoTestTimer[]
---@field notifications string[]
---@field bootstrap? PackageInfoBootstrapCallback
---@field receive? PackageInfoResponse
---@field exit? PackageInfoCancel
---@field fail_send? boolean

---@return PackageInfoHelper
---@return PackageInfoTestHelper
---@return fun(delay: number): nil
function M.helper()
  ---@type PackageInfoTestHelper
  local state = { now = 0, hold = false, starts = 0, stops = 0, sent = {}, timers = {}, notifications = {} }
  ---@type PackageInfoHelperAdapter
  local adapter = {
    source = "test-source",
    runtime = "test-runtime",
    now = function()
      return state.now
    end,
    notify = function(message)
      state.notifications[#state.notifications + 1] = message
    end,
    bootstrap = function(_, _, callback)
      state.bootstrap = callback
      if not state.hold then
        callback()
      end
    end,
    start = function(_, receive, exit)
      state.receive = receive
      state.exit = exit
      state.starts = state.starts + 1
      return state.starts
    end,
    stop = function()
      state.stops = state.stops + 1
    end,
    send = function(_, message)
      if state.fail_send then
        error("send failure")
      end
      state.sent[#state.sent + 1] = message
    end,
    schedule = function(delay, callback)
      local timer = { at = state.now + delay, callback = callback, cancelled = false }
      state.timers[#state.timers + 1] = timer
      return function()
        timer.cancelled = true
      end
    end,
  }
  return helper_factory.new(adapter),
    state,
    function(delay)
      state.now = state.now + delay
      for _, timer in ipairs(state.timers) do
        if not timer.cancelled and timer.at <= state.now then
          timer.cancelled = true
          timer.callback()
        end
      end
    end
end

---@class PackageInfoTestController
---@field host? PackageInfoHost
---@field renders integer
---@field annotations PackageInfoAnnotations
---@field cleared integer
---@field installed integer
---@field notifications string[]
---@field parse? PackageInfoManifest
---@field parse_error? string
---@field after_parse? PackageInfoCancel
---@field floated string[]

---@return PackageInfoController
---@return PackageInfoTestController
---@return PackageInfoTestHelper
---@return PackageInfoAdapter
---@return fun(delay: number): nil
function M.controller()
  local helper, transport, advance = M.helper()
  ---@type PackageInfoTestController
  local state = {
    host = { path = "/tmp/project/package.json", tick = 1, modified = false },
    renders = 0,
    annotations = {},
    cleared = 0,
    installed = 0,
    notifications = {},
    parse = { text = '{"dependencies":{}}', lines = {} },
    floated = {},
  }
  ---@type PackageInfoAdapter
  local adapter = {
    schedule = function(delay, callback)
      local timer = { at = transport.now + delay, callback = callback, cancelled = false }
      transport.timers[#transport.timers + 1] = timer
      return function()
        timer.cancelled = true
      end
    end,
    namespace = 1,
    helper = helper,
    queue = queue_factory.new(function(_, callback)
      callback({ code = 0, stdout = "11.0.0", stderr = "" })
      return { kill = function() end }
    end, function(message)
      state.notifications[#state.notifications + 1] = message
    end),
    now = function()
      return transport.now
    end,
    current = function()
      return { buf = 1, row = 0 }
    end,
    buffer = function()
      return state.host
    end,
    executable = function()
      return true
    end,
    environment = function()
      return {}
    end,
    npm_path = function()
      return "npm"
    end,
    user_config = function()
      return nil
    end,
    environment_hash = function()
      return "environment"
    end,
    encode = function()
      return "{}"
    end,
    decode = function()
      return {}
    end,
    manifest = function()
      if state.after_parse then
        state.after_parse()
      end
      return state.parse, state.parse_error
    end,
    notify = function(message)
      state.notifications[#state.notifications + 1] = message
    end,
    clear = function()
      state.cleared = state.cleared + 1
    end,
    render = function(_, rows)
      state.renders = state.renders + 1
      state.annotations = rows
    end,
    float = function(lines)
      state.floated = lines
    end,
    install = function()
      state.installed = state.installed + 1
    end,
    uninstall = function()
      state.installed = 0
    end,
  }
  local instance = controller_factory.new(adapter)
  instance.setup({ fast_registry = false })
  return instance, state, transport, adapter, advance
end
return M
