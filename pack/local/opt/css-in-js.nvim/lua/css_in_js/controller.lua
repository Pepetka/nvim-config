local config = require("css_in_js.core.config")
local regions = require("css_in_js.core.regions")
local document = require("css_in_js.core.document")
local completion = require("css_in_js.core.completion")
local requests = require("css_in_js.core.requests")
local M = {}

---@param adapter CssInJsAdapter
---@return CssInJsController
function M.new(adapter)
  local options = config.normalize()
  local active, installed = true, false
  ---@type table<integer, CssInJsEntry>
  local entries = {}
  local controller = {}

  ---@return CssInJsConfig
  function controller.configuration()
    return config.copy(options)
  end

  ---@param err unknown
  local function report(err)
    adapter.notify("css-in-js: " .. tostring(err))
  end

  ---@param entry CssInJsEntry
  local function cancel_jobs(entry)
    for _, job in pairs(entry.jobs) do
      job.cancel()
    end
  end

  ---@param buf integer
  function controller.deleted(buf)
    local entry = entries[buf]
    if not entry then
      return
    end
    cancel_jobs(entry)
    local ok, err = pcall(adapter.close, entry.allocation)
    if ok or not adapter.valid(entry.allocation) then
      entries[buf] = nil
    end
    if not ok then
      report(err)
    end
  end

  function controller.teardown()
    active = false
    for buf in pairs(entries) do
      controller.deleted(buf)
    end
    local ok, err = pcall(adapter.uninstall)
    installed = false
    if not ok then
      report(err)
    end
  end

  ---@param value? CssInJsOptions
  function controller.setup(value)
    local next_options, messages = config.normalize(value)
    controller.teardown()
    options = next_options
    for _, message in ipairs(messages) do
      adapter.notify(message)
    end
    local ok, err = pcall(adapter.install, options, controller.deleted)
    if not ok then
      pcall(adapter.uninstall)
      report(err)
      return
    end
    active, installed = true, true
  end

  ---@param buf integer
  ---@return boolean
  function controller.supports_buffer(buf)
    if not active then
      return false
    end
    local info = adapter.buffer(buf)
    if not info or not regions.supports(info.filetype, info.buftype, options.filetypes) then
      return false
    end
    local ok, accepted = pcall(options.filter, buf)
    if not ok then
      report(accepted)
    end
    return ok and accepted == true
  end

  ---@param buf integer
  ---@param row integer
  ---@param col integer
  ---@return CssInJsRegion?
  function controller.context(buf, row, col)
    if not controller.supports_buffer(buf) or not config.integer(row) or not config.integer(col) then
      return nil
    end
    local entry = entries[buf]
    local snapshot = entry and entry.document
    local info = adapter.buffer(buf)
    if
      snapshot
      and info
      and entry.filetype == info.filetype
      and entry.tick == adapter.tick(buf)
      and regions.contains(snapshot.region, row, col, true)
    then
      return regions.active(snapshot.region, row, col) and config.copy(snapshot.region) or nil
    end
    local ok, region = pcall(adapter.extract, buf, row, col)
    if not ok then
      report(region)
      return nil
    end
    if region and regions.active(region, row, col) then
      return region
    end
  end

  ---@param buf integer
  ---@return boolean
  function controller.ready(buf)
    local entry = entries[buf]
    if
      not active
      or not entry
      or not entry.available
      or not adapter.valid(entry.allocation)
      or not entry.allocation.client_id
    then
      return false
    end
    local client = adapter.client(entry.allocation.client_id)
    return client ~= nil and client.initialized and not client.stopped and client.completion
  end

  ---@param buf integer
  ---@return CssInJsEntry?
  local function acquire(buf)
    local entry = entries[buf]
    if entry and entry.allocation.client_id then
      local client = adapter.client(entry.allocation.client_id)
      if adapter.valid(entry.allocation) and client and not client.stopped then
        return entry
      end
      controller.deleted(buf)
      if entries[buf] then
        return nil
      end
    elseif entry then
      controller.deleted(buf)
      if entries[buf] then
        return nil
      end
    end
    if not installed then
      adapter.install(options, controller.deleted)
      installed = true
    end
    local allocation, err = adapter.create(buf)
    entry = { allocation = allocation, version = 0, jobs = {}, available = false }
    entries[buf] = entry
    if err or not allocation.client_id or not adapter.valid(allocation) then
      controller.deleted(buf)
      if err then
        report(err)
      end
      return nil
    end
    return entry
  end

  ---@param ctx CssInJsContext
  ---@param method CssInJsMethod
  ---@param callback fun(result: unknown, snapshot: CssInJsDocument?, client: CssInJsClient?): nil
  ---@return CssInJsCancel?
  local function request(ctx, method, callback)
    local captured_tick = adapter.tick(ctx.bufnr)
    local captured_info = adapter.buffer(ctx.bufnr)
    local captured_filetype = captured_info and captured_info.filetype
    local region = controller.context(ctx.bufnr, ctx.cursor[1] - 1, ctx.cursor[2])
    if not region then
      callback(nil)
      return nil
    end
    local entry
    local ok, err = pcall(function()
      entry = acquire(ctx.bufnr)
    end)
    if not ok or not entry then
      if not ok then
        controller.deleted(ctx.bufnr)
        report(err)
      end
      callback(nil)
      return nil
    end
    ---@cast entry CssInJsEntry
    ---@return boolean
    local function host_unchanged()
      local info = adapter.buffer(ctx.bufnr)
      return info ~= nil and info.filetype == captured_filetype and adapter.tick(ctx.bufnr) == captured_tick
    end
    local snapshot
    local prepared = false
    ok, err = pcall(function()
      if not host_unchanged() then
        return
      end
      local tick = captured_tick
      local previous = entry.document
      local changed = not previous
        or entry.tick ~= tick
        or entry.filetype ~= captured_filetype
        or previous.region.start_row ~= region.start_row
        or previous.region.start_col ~= region.start_col
        or previous.region.end_row ~= region.end_row
        or previous.region.end_col ~= region.end_col
      if not changed then
        snapshot = previous
        prepared = true
        return
      end
      snapshot =
        document.build(adapter.lines(ctx.bufnr, region.start_row, region.end_row + 1), region, region.start_row)
      if not host_unchanged() then
        return
      end
      cancel_jobs(entry)
      entry.version = entry.version + 1
      if not previous or table.concat(previous.lines, "\n") ~= table.concat(snapshot.lines, "\n") then
        adapter.write(entry.allocation, snapshot.lines)
      end
      if not host_unchanged() then
        entry.document = nil
        return
      end
      entry.document, entry.tick, entry.filetype = snapshot, tick, captured_filetype
      prepared = true
    end)
    if not ok then
      controller.deleted(ctx.bufnr)
      report(err)
      callback(nil)
      return nil
    end
    if not prepared then
      cancel_jobs(entry)
      entry.available = false
      callback(nil)
      return nil
    end
    snapshot = assert(snapshot)
    local previous = entry.jobs[method]
    if previous then
      previous.cancel()
    end
    ---@type CssInJsJob
    local job = {
      done = false,
      deadline = adapter.now() + options.request_timeout_ms,
      version = entry.version,
      tick = assert(entry.tick),
      cancel = function() end,
    }
    entry.jobs[method] = job

    ---@param cancel_request boolean
    local function finish(cancel_request)
      if job.done then
        return
      end
      job.done = true
      if job.timer then
        job.timer()
        job.timer = nil
      end
      if cancel_request and job.request_id then
        pcall(adapter.cancel, entry.allocation, job.request_id)
      end
      if entry.jobs[method] == job then
        entry.jobs[method] = nil
      end
    end
    function job.cancel()
      finish(true)
    end

    ---@param result unknown
    ---@param client? CssInJsClient
    local function deliver(result, client)
      if job.done then
        return
      end
      finish(false)
      if method == "textDocument/completion" then
        entry.available = completion.valid_response(result) and client ~= nil
      end
      callback(result, snapshot, client)
    end

    ---@type CssInJsCancel
    local safe_step
    ---@return nil
    local function step()
      if job.done then
        return
      end
      local client = entry.allocation.client_id and adapter.client(entry.allocation.client_id) or nil
      local state = requests.state(job, adapter.now(), adapter.tick(ctx.bufnr), entry.version, client)
      if not adapter.valid(entry.allocation) or state == "stale" or state == "timeout" then
        finish(true)
        if method == "textDocument/completion" then
          entry.available = false
        end
        callback(nil)
        return
      end
      if state == "wait" then
        job.timer =
          adapter.schedule(math.max(0, math.min(options.poll_interval_ms, job.deadline - adapter.now())), safe_step)
        return
      end
      if state == "done" then
        return
      end
      client = assert(client)
      if
        not (
          method == "textDocument/completion" and client.completion or method == "textDocument/hover" and client.hover
        )
      then
        deliver(nil)
        return
      end
      local position = document.position(snapshot, ctx.cursor[1] - 1, ctx.cursor[2], client.encoding)
      if not position then
        deliver(nil)
        return
      end
      local params = { textDocument = { uri = adapter.uri(entry.allocation) }, position = position }
      if method == "textDocument/completion" then
        params.context = { triggerKind = 1 }
      end
      job.timer = adapter.schedule(math.max(0, job.deadline - adapter.now()), safe_step)
      local success, id = pcall(adapter.request, entry.allocation, method, params, function(error_value, result)
        if job.done then
          return
        end
        local handled, failure = pcall(function()
          local current = adapter.client(assert(entry.allocation.client_id))
          local response_state = requests.state(job, adapter.now(), adapter.tick(ctx.bufnr), entry.version, current)
          if error_value or response_state ~= "ready" or not adapter.valid(entry.allocation) then
            deliver(nil)
          else
            deliver(result, current)
          end
        end)
        if not handled then
          report(failure)
          deliver(nil)
        end
      end)
      if not success then
        report(id)
        deliver(nil)
      elseif not id then
        deliver(nil)
      elseif not job.done then
        job.request_id = id
      end
    end
    safe_step = function()
      local success, failure = pcall(step)
      if not success then
        report(failure)
        deliver(nil)
      end
    end
    safe_step()
    return job.cancel
  end

  ---@param ctx CssInJsContext
  ---@param callback fun(response: CssInJsResponse): nil
  ---@return CssInJsCancel?
  function controller.complete(ctx, callback)
    ctx = requests.context(ctx)
    return request(ctx, "textDocument/completion", function(result, snapshot, client)
      if not snapshot or not client then
        callback(completion.empty())
        return
      end
      local ok, response = pcall(completion.response, result, snapshot, client, ctx.cursor[2])
      if not ok then
        local entry = entries[ctx.bufnr]
        if entry then
          entry.available = false
        end
        report(response)
        callback(completion.empty())
      else
        callback(response)
      end
    end)
  end

  ---@return CssInJsCancel?
  function controller.hover()
    local ctx = requests.context(adapter.current())
    if not controller.context(ctx.bufnr, ctx.cursor[1] - 1, ctx.cursor[2]) then
      adapter.fallback_hover()
      return nil
    end
    return request(ctx, "textDocument/hover", function(result)
      local current = adapter.current()
      if current.bufnr ~= ctx.bufnr or current.cursor[1] ~= ctx.cursor[1] or current.cursor[2] ~= ctx.cursor[2] then
        return
      end
      if type(result) ~= "table" then
        result = nil
      end
      ---@cast result lsp.Hover?
      adapter.show_hover(result)
    end)
  end

  return controller
end

return M
