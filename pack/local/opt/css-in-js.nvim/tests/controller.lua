local directory = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "./"
package.path = directory .. "../lua/?.lua;" .. directory .. "?.lua;" .. package.path
local t = require("support")
local controller = require("css_in_js.controller")
local blink = require("css_in_js.integrations.blink")
local document = require("css_in_js.core.document")
local host_vim = rawget(_G, "vim")
_G.vim = nil

---@return CssInJsController
---@return CssInJsTestState
---@return CssInJsContext
---@return fun(ms: integer): nil
---@return CssInJsAdapter
local function fixture()
  ---@type CssInJsTestState
  local state = {
    time = 0,
    tick = 1,
    filetype = "typescriptreact",
    buftype = "",
    text = { "css`color: red;`" },
    region = { start_row = 0, start_col = 4, end_row = 0, end_col = 15, substitutions = {} },
    cursor = { 1, 4 },
    client = {
      id = 1,
      name = "css_in_js",
      initialized = true,
      stopped = false,
      encoding = "utf-16",
      completion = true,
      hover = true,
    },
    valid = false,
    writes = 0,
    creates = 0,
    closes = 0,
    cancelled = {},
    timers = {},
    replies = {},
    messages = {},
    fallback = 0,
    hovers = 0,
  }
  ---@type CssInJsAdapter
  local adapter = {
    current = function()
      return { bufnr = 10, cursor = state.cursor, line = state.text[1] }
    end,
    buffer = function()
      return state.tick and { filetype = state.filetype, buftype = state.buftype } or nil
    end,
    tick = function()
      return state.tick
    end,
    extract = function()
      if state.fail_extract then
        error("extract failed")
      end
      return state.region
    end,
    lines = function(_, first_row, last_row)
      local lines = {}
      for row = first_row, last_row - 1 do
        lines[#lines + 1] = state.text[row + 1]
      end
      return lines
    end,
    client = function()
      return state.client
    end,
    client_name = function()
      return state.client.name
    end,
    create = function()
      state.creates = state.creates + 1
      if state.fail_create then
        error("create failed")
      end
      if state.unavailable then
        return {}
      end
      state.valid = true
      return { buf = 20, client_id = 1 }, state.partial and "partial creation" or nil
    end,
    valid = function()
      return state.valid
    end,
    close = function()
      if state.fail_close then
        error("close failed")
      end
      state.closes = state.closes + 1
      state.valid = false
    end,
    write = function()
      if state.fail_write then
        error("write failed")
      end
      state.writes = state.writes + 1
    end,
    uri = function()
      return "test://css"
    end,
    request = function(_, _, _, callback)
      if state.fail_request then
        error("request failed")
      end
      state.replies[#state.replies + 1] = callback
      if state.sync then
        callback(nil, { items = { { label = "red" } } })
      end
      return #state.replies
    end,
    cancel = function(_, id)
      state.cancelled[#state.cancelled + 1] = id
    end,
    now = function()
      return state.time
    end,
    schedule = function(delay, callback)
      local timer = { at = state.time + delay, run = callback, cancelled = false }
      state.timers[#state.timers + 1] = timer
      return function()
        timer.cancelled = true
      end
    end,
    install = function(_, deleted)
      if state.fail_install then
        error("install failed")
      end
      state.deleted = deleted
    end,
    uninstall = function()
      state.deleted = nil
    end,
    fallback_hover = function()
      state.fallback = state.fallback + 1
    end,
    show_hover = function(result)
      state.hovers = state.hovers + 1
      state.hover_result = result
    end,
    notify = function(message)
      state.messages[#state.messages + 1] = message
    end,
  }
  ---@param ms integer
  local function advance(ms)
    state.time = state.time + ms
    local timers = state.timers
    state.timers = {}
    for _, timer in ipairs(timers) do
      if not timer.cancelled then
        if timer.at <= state.time then
          timer.run()
        else
          state.timers[#state.timers + 1] = timer
        end
      end
    end
  end
  local instance = controller.new(adapter)
  instance.setup()
  return instance, state, adapter.current(), advance, adapter
end

---@param response CssInJsResponse
local function empty(response)
  t.equal(response.items, {})
end

t.test("completion captures a snapshot and writes once", function()
  local instance, state, ctx = fixture()
  local count = 0
  instance.complete(ctx, function(response)
    count = count + 1
    t.equal(response.items[1].label, "red")
  end)
  state.replies[1](nil, { items = { { label = "red" } } })
  state.replies[1](nil, { items = { { label = "red" } } })
  t.equal(count, 1)
  assert(instance.ready(10))
  instance.complete(ctx, empty)
  t.equal(state.creates, 1)
  t.equal(state.writes, 1)
end)
t.test("cancel is idempotent and late responses are ignored", function()
  local instance, state, ctx = fixture()
  local calls = 0
  local cancel = assert(instance.complete(ctx, function()
    calls = calls + 1
  end))
  cancel()
  cancel()
  state.replies[1](nil, { items = {} })
  t.equal(calls, 0)
  t.equal(state.cancelled, { 1 })
end)
t.test("same-kind requests supersede earlier requests", function()
  local instance, state, ctx = fixture()
  local calls = 0
  instance.complete(ctx, function()
    calls = calls + 1
  end)
  instance.complete(ctx, empty)
  state.replies[1](nil, { items = {} })
  t.equal(calls, 0)
  t.equal(state.cancelled, { 1 })
end)
t.test("different template at the same changedtick invalidates the prior reply", function()
  local instance, state, ctx = fixture()
  local calls = 0
  state.text = { "css`color: red;`; css`padding: 1px;`" }
  instance.complete(ctx, function()
    calls = calls + 1
  end)
  state.region = { start_row = 0, start_col = 21, end_row = 0, end_col = 34, substitutions = {} }
  ctx.cursor = { 1, 21 }
  instance.complete(ctx, empty)
  state.replies[1](nil, { items = { { label = "old" } } })
  t.equal(calls, 0)
  t.equal(state.cancelled, { 1 })
  t.equal(state.writes, 2)
end)
t.test("host edits discard replies with one empty result", function()
  local instance, state, ctx = fixture()
  local calls = 0
  instance.complete(ctx, function(response)
    empty(response)
    calls = calls + 1
  end)
  state.tick = 2
  state.replies[1](nil, { items = { { label = "old" } } })
  t.equal(calls, 1)
end)
t.test("initialization is polled and a request is sent when ready", function()
  local instance, state, ctx, advance = fixture()
  state.client.initialized = false
  instance.complete(ctx, empty)
  t.equal(#state.replies, 0)
  advance(20)
  t.equal(#state.replies, 0)
  state.client.initialized = true
  advance(20)
  t.equal(#state.replies, 1)
end)
t.test("initialization timeout completes once", function()
  local instance, state, ctx, advance = fixture()
  local calls = 0
  state.client.initialized = false
  instance.complete(ctx, function(response)
    empty(response)
    calls = calls + 1
  end)
  advance(5000)
  advance(5000)
  t.equal(calls, 1)
  t.equal(#state.replies, 0)
end)
t.test("in-flight timeout cancels the client request", function()
  local instance, state, ctx, advance = fixture()
  local calls = 0
  instance.complete(ctx, function(response)
    empty(response)
    calls = calls + 1
  end)
  advance(5000)
  state.replies[1](nil, { items = {} })
  t.equal(calls, 1)
  t.equal(state.cancelled, { 1 })
end)
t.test("deletion cancels replies and timers before disposing resources", function()
  local instance, state, ctx, advance = fixture()
  local calls = 0
  instance.complete(ctx, function()
    calls = calls + 1
  end)
  assert(state.deleted)(10)
  state.replies[1](nil, { items = {} })
  advance(5000)
  t.equal(calls, 0)
  t.equal(state.closes, 1)
  assert(not instance.ready(10))
end)
t.test("teardown is idempotent; setup reactivates existing sources", function()
  local instance, state, ctx = fixture()
  instance.complete(ctx, empty)
  instance.teardown()
  instance.teardown()
  assert(not instance.supports_buffer(10))
  instance.complete(ctx, empty)
  t.equal(state.creates, 1)
  instance.setup()
  instance.complete(ctx, empty)
  t.equal(state.creates, 2)
end)
t.test("setup replaces configuration and cancels previous requests", function()
  local instance, state, ctx = fixture()
  local calls = 0
  instance.complete(ctx, function()
    calls = calls + 1
  end)
  instance.setup({
    filter = function()
      return false
    end,
  })
  state.replies[1](nil, { items = {} })
  t.equal(calls, 0)
  assert(not instance.supports_buffer(10))
  t.equal(state.closes, 1)
end)
t.test("caller filter and extraction exceptions are contained", function()
  local instance, state = fixture()
  instance.setup({
    filter = function()
      error("filter failed")
    end,
  })
  t.equal(instance.supports_buffer(10), false)
  assert(#state.messages > 0)
  instance.setup()
  state.fail_extract = true
  t.equal(instance.context(10, 0, 4), nil)
end)
t.test("unsupported deleted and special buffers return false", function()
  local instance, state = fixture()
  state.filetype = "css"
  t.equal(instance.supports_buffer(10), false)
  state.filetype = "typescript"
  state.buftype = "nofile"
  t.equal(instance.supports_buffer(10), false)
  state.tick = nil
  t.equal(instance.supports_buffer(10), false)
end)
---@type ("fail_create" | "fail_write" | "fail_request")[]
local failures = { "fail_create", "fail_write", "fail_request" }
for _, failure in ipairs(failures) do
  t.test("failure " .. failure .. " returns empty and permits retry", function()
    local instance, state, ctx = fixture()
    state[failure] = true
    local calls = 0
    instance.complete(ctx, function(response)
      empty(response)
      calls = calls + 1
    end)
    t.equal(calls, 1)
    state[failure] = false
    instance.complete(ctx, empty)
    assert(state.valid)
  end)
end
t.test("partial creation transfers ownership for cleanup", function()
  local instance, state, ctx = fixture()
  state.partial = true
  instance.complete(ctx, empty)
  t.equal(state.closes, 1)
  assert(not state.valid)
end)
t.test("cleanup failure retains ownership for a retry", function()
  local instance, state, ctx = fixture()
  instance.complete(ctx, empty)
  state.fail_close = true
  instance.teardown()
  t.equal(state.closes, 0)
  assert(state.valid)
  state.fail_close = false
  instance.teardown()
  t.equal(state.closes, 1)
end)
t.test("failed installation can be retried", function()
  local instance, state = fixture()
  state.fail_install = true
  instance.setup()
  assert(not instance.supports_buffer(10))
  state.fail_install = false
  instance.setup()
  assert(instance.supports_buffer(10))
end)
t.test("synchronous replies complete once", function()
  local instance, state, ctx, advance = fixture()
  state.sync = true
  local calls = 0
  instance.complete(ctx, function()
    calls = calls + 1
  end)
  advance(5000)
  t.equal(calls, 1)
end)
t.test("stopped client and unsupported methods fail safely", function()
  local instance, state, ctx = fixture()
  state.client.completion = false
  local calls = 0
  instance.complete(ctx, function(response)
    empty(response)
    calls = calls + 1
  end)
  t.equal(calls, 1)
  state.client.completion = true
  instance.complete(ctx, empty)
  state.client.stopped = true
  state.replies[1](nil, { items = {} })
  assert(not instance.ready(10))
end)
t.test("hover falls back outside CSS and ignores moved cursors", function()
  local instance, state = fixture()
  state.cursor = { 1, 0 }
  instance.hover()
  t.equal(state.fallback, 1)
  state.cursor = { 1, 4 }
  instance.hover()
  state.cursor = { 1, 5 }
  state.replies[1](nil, { contents = "docs" })
  t.equal(state.hovers, 0)
end)
t.test("hover and completion share a snapshot without cancelling each other", function()
  local instance, state, ctx = fixture()
  instance.complete(ctx, empty)
  instance.hover()
  state.replies[2](nil, { contents = "docs" })
  t.equal(state.hover_result.contents, "docs")
  t.equal(state.cancelled, {})
end)
t.test("independent controllers have independent documents and settings", function()
  local first, a, ctx = fixture()
  local second, b = fixture()
  first.complete(ctx, empty)
  second.complete(ctx, empty)
  first.teardown()
  assert(not a.valid and b.valid)
  assert(second.supports_buffer(10))
end)
t.test("request context is captured before caller mutation", function()
  local instance, state, ctx = fixture()
  instance.complete(ctx, function(response)
    t.equal(response.items[1].cursor_column, 4)
  end)
  ctx.cursor[2] = 9
  state.replies[1](nil, { items = { { label = "red" } } })
end)
t.test("failed response restores TS fallback availability", function()
  local instance, state, ctx = fixture()
  instance.complete(ctx, function() end)
  state.replies[1](nil, { items = {} })
  assert(instance.ready(10))
  instance.complete(ctx, empty)
  state.replies[2]("server failed", nil)
  assert(not instance.ready(10))
end)
t.test("host edit during allocation discards the captured region", function()
  local instance, state, ctx, _, adapter = fixture()
  local create = adapter.create
  adapter.create = function(buf)
    local allocation, failure = create(buf)
    state.text = { "let longer = true; /* no CSS template */" }
    state.tick = 2
    return allocation, failure
  end
  local calls = 0
  instance.complete(ctx, function(response)
    empty(response)
    calls = calls + 1
  end)
  t.equal(calls, 1)
  t.equal(#state.replies, 0)
  t.equal(state.writes, 0)
  assert(not instance.ready(10))
end)
t.test("host edits during extraction and document preparation are discarded", function()
  for _, phase in ipairs({ "extract", "lines", "write" }) do
    local instance, state, ctx, _, adapter = fixture()
    if phase == "extract" then
      adapter.extract = function()
        state.tick = 2
        return state.region
      end
    elseif phase == "lines" then
      adapter.lines = function()
        state.tick = 2
        return state.text
      end
    else
      adapter.write = function()
        state.tick = 2
      end
    end
    local calls = 0
    instance.complete(ctx, function(response)
      empty(response)
      calls = calls + 1
    end)
    t.equal(calls, 1)
    t.equal(#state.replies, 0)
    assert(not instance.ready(10))
  end
end)
for _, result in ipairs({
  true,
  "invalid",
  { items = false },
  { items = { [2] = { label = "red" } } },
  { items = {}, isIncomplete = "invalid" },
  { items = {}, itemDefaults = false },
}) do
  t.test("malformed reply preserves TS fallback " .. tostring(result), function()
    local instance, state, ctx = fixture()
    instance.complete(ctx, function() end)
    state.replies[1](nil, { items = {} })
    assert(instance.ready(10))
    instance.complete(ctx, empty)
    state.replies[2](nil, result)
    assert(not instance.ready(10))
  end)
end
t.test("asynchronous lookup failure is contained and completes once", function()
  local instance, state, ctx, advance, adapter = fixture()
  local calls = 0
  instance.complete(ctx, function(response)
    empty(response)
    calls = calls + 1
  end)
  adapter.client = function()
    error("lookup failed")
  end
  state.replies[1](nil, { items = {} })
  state.replies[1](nil, { items = {} })
  advance(5000)
  t.equal(calls, 1)
  assert(#state.messages > 0)
  assert(state.timers[1] == nil)
end)
t.test("configured deadline covers both server initialization and response waiting", function()
  for _, initialized in ipairs({ false, true }) do
    local instance, state, ctx, advance = fixture()
    instance.setup({ request_timeout_ms = 90, poll_interval_ms = 200 })
    state.client.initialized = initialized
    local calls = 0
    instance.complete(ctx, function(response)
      empty(response)
      calls = calls + 1
    end)
    t.equal(state.timers[1].at, 90)
    advance(89)
    t.equal(calls, 0)
    advance(1)
    t.equal(calls, 1)
    t.equal(state.timers, {})
    if initialized then
      t.equal(state.cancelled, { 1 })
    else
      t.equal(state.replies, {})
    end
  end
end)
t.test("configured polling interval sends immediately after initialization is observed", function()
  local instance, state, ctx, advance = fixture()
  instance.setup({ request_timeout_ms = 100, poll_interval_ms = 30 })
  state.client.initialized = false
  instance.complete(ctx, empty)
  advance(29)
  t.equal(state.replies, {})
  state.client.initialized = true
  advance(1)
  t.equal(#state.replies, 1)
  state.replies[1](nil, { items = {} })
end)
t.test("configured filetypes replace the defaults and still apply the user filter", function()
  local instance, state = fixture()
  instance.setup({ filetypes = { "custom_ts" } })
  assert(not instance.supports_buffer(1))
  state.filetype = "custom_ts"
  assert(instance.supports_buffer(1))
  instance.setup({
    filetypes = { "custom_ts" },
    filter = function()
      return false
    end,
  })
  assert(not instance.supports_buffer(1))
  instance.setup()
  assert(not instance.supports_buffer(1))
  state.filetype = "typescriptreact"
  assert(instance.supports_buffer(1))
end)
t.test("existing Blink sources use current configuration without exposing mutable settings", function()
  local instance, state, ctx, _, adapter = fixture()
  local source = blink.new(instance, adapter)
  local input = { trigger_characters = { ":" }, suppressed_lsp_clients = { "custom_ts" } }
  instance.setup(input)
  input.trigger_characters[1] = "mutated"
  local triggers = source:get_trigger_characters()
  t.equal(triggers, { ":" })
  triggers[1] = "mutated"
  t.equal(source:get_trigger_characters(), { ":" })
  adapter.client_name = function(id)
    return id == 2 and "custom_ts" or "vtsls"
  end
  local items = { { label = "css" }, { label = "custom", client_id = 2 }, { label = "ts", client_id = 3 } }
  t.equal(blink.filter(instance, adapter, ctx, items), items)
  instance.complete(ctx, empty)
  state.replies[1](nil, { items = {} })
  t.equal(blink.filter(instance, adapter, ctx, items), { items[1], items[3] })
  local exposed = instance.configuration()
  exposed.suppressed_lsp_clients[1] = "vtsls"
  t.equal(blink.filter(instance, adapter, ctx, items), { items[1], items[3] })
  instance.setup({ trigger_characters = {}, suppressed_lsp_clients = {} })
  t.equal(source:get_trigger_characters(), {})
  instance.complete(ctx, empty)
  state.replies[2](nil, { items = {} })
  t.equal(blink.filter(instance, adapter, ctx, items), items)
  instance.setup()
  t.equal(source:get_trigger_characters(), { ":", "-", " " })
end)
t.test("unchanged completion and hover reuse extraction and the immutable snapshot", function()
  local instance, state, ctx, _, adapter = fixture()
  local reads, extractions, builds = 0, 0, 0
  local read, extract = adapter.lines, adapter.extract
  adapter.lines = function(buf, first, last)
    reads = reads + 1
    return read(buf, first, last)
  end
  adapter.extract = function(buf, row, col)
    extractions = extractions + 1
    return extract(buf, row, col)
  end
  local build = document.build
  ---@diagnostic disable-next-line: duplicate-set-field
  document.build = function(lines, region_value, first_row)
    builds = builds + 1
    return build(lines, region_value, first_row)
  end
  local ok, err = xpcall(function()
    instance.complete(ctx, empty)
    state.replies[1](nil, { items = {} })
    ctx.cursor[2], state.cursor[2] = 7, 7
    instance.complete(ctx, empty)
    state.replies[2](nil, { items = {} })
    instance.hover()
    state.replies[3](nil, { contents = "CSS" })
    t.equal({ reads, extractions, builds, state.writes }, { 1, 1, 1, 1 })
    local exposed = assert(instance.context(10, 0, 7))
    exposed.start_col = 999
    instance.complete(ctx, empty)
    state.replies[4](nil, { items = {} })
    t.equal({ reads, extractions, builds, state.writes }, { 1, 1, 1, 1 })
    state.tick = 2
    instance.complete(ctx, empty)
    state.replies[5](nil, { items = {} })
    t.equal({ reads, extractions, builds, state.writes }, { 2, 2, 2, 1 })
    instance.teardown()
  end, debug.traceback)
  document.build = build
  assert(ok, err)
end)
t.test("reads are bounded by template rows and edits retain absolute host coordinates", function()
  local instance, state, ctx, _, adapter = fixture()
  state.text = { "header", "header", "css`color: red;`", "footer", "footer" }
  state.region = { start_row = 2, start_col = 4, end_row = 2, end_col = 15, substitutions = {} }
  ctx.cursor = { 3, 4 }
  local read = adapter.lines
  adapter.lines = function(buf, first, last)
    t.equal({ first, last }, { 2, 3 })
    return read(buf, first, last)
  end
  instance.complete(ctx, function(response)
    t.equal(response.items[1].textEdit.range, {
      start = { line = 2, character = 4 },
      ["end"] = { line = 2, character = 9 },
    })
  end)
  state.replies[1](nil, {
    items = {
      {
        label = "color",
        textEdit = {
          newText = "color",
          range = {
            start = { line = 1, character = 0 },
            ["end"] = { line = 1, character = 5 },
          },
        },
      },
    },
  })
end)
t.test("cached context rejects substitutions and still applies mutable buffer filters", function()
  local instance, state, ctx, _, adapter = fixture()
  state.text = { "css`color: ${value};`" }
  state.region.end_col = #state.text[1] - 1
  state.region.substitutions = { { start_row = 0, start_col = 11, end_row = 0, end_col = 19, substitutions = {} } }
  local extractions = 0
  local extract = adapter.extract
  adapter.extract = function(buf, row, col)
    extractions = extractions + 1
    return extract(buf, row, col)
  end
  local allowed = true
  instance.setup({
    filter = function()
      return allowed
    end,
  })
  instance.complete(ctx, empty)
  state.replies[1](nil, { items = {} })
  ctx.cursor[2] = 13
  instance.complete(ctx, empty)
  t.equal(extractions, 1)
  t.equal(#state.replies, 1)
  ctx.cursor[2] = 4
  allowed = false
  instance.complete(ctx, empty)
  t.equal(extractions, 1)
  t.equal(#state.replies, 1)
end)
t.test("discarded allocations and setup rebuild snapshots at the same host tick", function()
  local instance, state, ctx, _, adapter = fixture()
  local reads = 0
  local read = adapter.lines
  adapter.lines = function(buf, first, last)
    reads = reads + 1
    return read(buf, first, last)
  end
  instance.complete(ctx, empty)
  state.replies[1](nil, { items = {} })
  state.valid = false
  instance.complete(ctx, empty)
  state.replies[2](nil, { items = {} })
  t.equal(reads, 2)
  instance.setup()
  instance.complete(ctx, empty)
  state.replies[3](nil, { items = {} })
  t.equal(reads, 3)
end)
t.test("filetype changes invalidate cached regions and snapshots without a host edit", function()
  local instance, state, ctx, _, adapter = fixture()
  local reads, extractions = 0, 0
  local read, extract = adapter.lines, adapter.extract
  adapter.lines = function(buf, first, last)
    reads = reads + 1
    return read(buf, first, last)
  end
  adapter.extract = function(buf, row, col)
    extractions = extractions + 1
    return extract(buf, row, col)
  end
  instance.complete(ctx, empty)
  state.replies[1](nil, { items = {} })
  state.filetype = "javascript"
  instance.complete(ctx, empty)
  state.replies[2](nil, { items = {} })
  t.equal({ reads, extractions }, { 2, 2 })
  t.equal(state.tick, 1)
end)
local ok, err = pcall(t.run, "css-in-js controller (without vim)")
_G.vim = host_vim
assert(ok, err)
