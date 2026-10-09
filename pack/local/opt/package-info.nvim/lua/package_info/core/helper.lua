local M = {}
---@param adapter PackageInfoHelperAdapter
---@return PackageInfoHelper
function M.new(adapter)
  local helper =
    { pending = {}, waiting = {}, next_id = 0, state = "idle", runtime = adapter.runtime, source = adapter.source }
  ---@cast helper PackageInfoHelper
  local generation = 0
  local config = require("package_info.core.config").defaults()
  function helper.configure(options)
    config = require("package_info.core.config").copy(options)
    if adapter.configure then
      adapter.configure(config)
    end
  end
  ---@param callback function
  ---@param ... unknown
  local function call(callback, ...)
    local ok, err = pcall(callback, ...)
    if not ok then
      adapter.notify(tostring(err))
    end
  end
  ---@param ticket PackageInfoTicket
  local function clear_timer(ticket)
    if ticket.timer then
      ticket.timer()
      ticket.timer = nil
    end
  end
  ---@param message string
  local function fail(message)
    helper.state, helper.error, helper.failed_at = "failed", message, adapter.now()
    local waiting, pending = helper.waiting, helper.pending
    helper.waiting, helper.pending = {}, {}
    for _, callback in ipairs(waiting) do
      call(callback, nil, message)
    end
    for _, entry in pairs(pending) do
      clear_timer(entry.ticket)
      call(entry.callback, nil, message, true)
    end
  end
  ---@param epoch integer
  local function start(epoch)
    if epoch ~= generation then
      return
    end
    local job
    local ok, result = pcall(adapter.start, helper.runtime, function(response)
      if epoch ~= generation or type(response) ~= "table" or type(response.id) ~= "number" then
        return
      end
      if response.error ~= nil and type(response.error) ~= "string" then
        return
      end
      if response.done ~= nil and type(response.done) ~= "boolean" then
        return
      end
      local entry = helper.pending[response.id]
      if not entry then
        return
      end
      local done = response.done ~= false
      if done then
        helper.pending[response.id] = nil
        clear_timer(entry.ticket)
      end
      call(entry.callback, response.result, response.error, done)
    end, function()
      if epoch == generation and helper.job == job then
        helper.job = nil
        fail("Node helper stopped; refresh to restart")
      end
    end)
    if not ok or result <= 0 then
      fail("Cannot start Node helper")
      return
    end
    job = result
    helper.job, helper.state, helper.error = job, "ready", nil
    local waiting = helper.waiting
    helper.waiting = {}
    for _, callback in ipairs(waiting) do
      call(callback, true)
    end
  end
  function helper.ensure(callback)
    if helper.state == "ready" then
      call(callback, true)
      return
    end
    if helper.state == "failed" and helper.failed_at and adapter.now() - helper.failed_at < config.cache.retry then
      call(callback, nil, helper.error)
      return
    end
    helper.waiting[#helper.waiting + 1] = callback
    if helper.state == "starting" or helper.state == "installing" then
      return
    end
    helper.state = "starting"
    generation = generation + 1
    local epoch = generation
    local ok, err = pcall(adapter.bootstrap, helper.source, helper.runtime, function(error_message)
      if epoch ~= generation then
        return
      end
      if error_message then
        fail(error_message)
      else
        start(epoch)
      end
    end)
    if not ok then
      fail(tostring(err))
    end
  end
  function helper.retry()
    helper.failed_at = nil
  end
  function helper.request(method, input, callback, options)
    ---@type PackageInfoTicket
    local ticket = {}
    local wait
    wait = function(ok, err)
      if ticket.cancelled then
        return
      end
      if not ok then
        call(callback, nil, err, true)
        return
      end
      helper.next_id = helper.next_id + 1
      local id = helper.next_id
      ticket.id = id
      helper.pending[id] = { callback = callback, ticket = ticket }
      local sent = pcall(adapter.send, assert(helper.job), { id = id, method = method, input = input })
      if not sent then
        helper.pending[id] = nil
        call(callback, nil, "Cannot send helper request", true)
        return
      end
      if helper.pending[id] then
        ticket.timer = adapter.schedule(options and options.timeout or config.timeouts.helper, function()
          if helper.pending[id] then
            helper.cancel(ticket)
            call(callback, nil, "Node helper request timed out", true)
          end
        end)
      end
    end
    ticket.wait = wait
    helper.ensure(wait)
    return ticket
  end
  function helper.cancel(ticket)
    if not ticket then
      return
    end
    ticket.cancelled = true
    clear_timer(ticket)
    for index = #helper.waiting, 1, -1 do
      if helper.waiting[index] == ticket.wait then
        table.remove(helper.waiting, index)
      end
    end
    if ticket.id and helper.pending[ticket.id] then
      helper.pending[ticket.id] = nil
      if helper.job then
        pcall(adapter.send, helper.job, { method = "cancel", input = { id = ticket.id } })
      end
    end
  end
  function helper.stop()
    generation = generation + 1
    local job = helper.job
    helper.job = nil
    adapter.stop(job)
    fail("Node helper stopped")
    helper.state, helper.error, helper.failed_at = "idle", nil, nil
  end
  return helper
end
return M
