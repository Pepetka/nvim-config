local source = debug.getinfo(1, "S").source:sub(2)
local directory = source:match("^(.*[/\\])") or "./"
package.path = directory .. "../lua/?.lua;" .. directory .. "?.lua;" .. package.path
local controller = require("cheatsheet.controller")
local t = require("support")
local host_vim = rawget(_G, "vim")
_G.vim = nil

---@param options? CheatsheetConfigPartial
---@param skip_setup? boolean
---@return CheatsheetController, CheatsheetTestState
local function fixture(options, skip_setup)
  ---@type CheatsheetTestState
  local state =
    { created = 0, closed = 0, updates = 0, installed = 0, messages = {}, columns = 120, lines = 40, current_buf = 10 }
  local adapter = {}
  ---@param message string
  ---@param level CheatsheetLogLevel
  ---@return nil
  function adapter.notify(message, level)
    state.messages[#state.messages + 1] = { message = message, level = level }
  end
  ---@param value boolean
  ---@return nil
  function adapter.displayed(value)
    state.displayed = value
  end
  ---@param config CheatsheetConfig
  ---@param callbacks CheatsheetCallbacks
  ---@return nil
  function adapter.install(config, callbacks)
    if state.fail_install then
      error("install failed")
    end
    state.installed = state.installed + 1
    state.options, state.callbacks = config, callbacks
  end
  ---@return integer, integer
  function adapter.source()
    return state.current_buf, 20
  end
  ---@return CheatsheetViewport
  function adapter.viewport()
    if state.fail_viewport then
      error("viewport failed")
    end
    return { columns = state.columns, lines = state.lines }
  end
  ---@return string
  function adapter.leader()
    return " "
  end
  ---@param text string
  ---@return integer
  function adapter.measure(text)
    return #text
  end
  ---@param session CheatsheetSession
  ---@return boolean
  function adapter.valid(session)
    ---@cast session CheatsheetTestSession
    return session.alive and session.win ~= nil and session.buf ~= nil
  end
  ---@param session CheatsheetSession
  ---@return boolean
  function adapter.exists(session)
    ---@cast session CheatsheetTestSession
    return session.alive and (session.win ~= nil or session.buf ~= nil)
  end
  ---@param mode CheatsheetMode
  ---@param source_buf integer
  ---@return CheatsheetRawMapping[], CheatsheetRawMapping[]
  function adapter.collect(mode, source_buf)
    if state.fail_collect then
      error("collect failed")
    end
    t.equal(source_buf, 10)
    state.collected_mode = mode
    local local_mappings = state.source_deleted and {} or { { lhs = "xx", desc = "Test: Local " .. mode } }
    return { { lhs = "xx", desc = "Test: Global " .. mode } }, local_mappings
  end
  ---@param config CheatsheetConfig
  ---@param source_buf integer
  ---@param source_win integer
  ---@param actions CheatsheetActions
  ---@param size CheatsheetGeometry
  ---@return CheatsheetTestSession, string?
  function adapter.create(config, source_buf, source_win, actions, size)
    if state.fail_create then
      error("create failed")
    end
    state.created = state.created + 1
    state.session = {
      win = 200 + state.created,
      buf = 100 + state.created,
      source_buf = source_buf,
      source_win = source_win,
      alive = true,
      options = config,
    }
    state.current_buf = assert(state.session).buf
    state.actions, state.size = actions, size
    if state.partial_create then
      return state.session, "creation failed after allocation"
    end
    return state.session
  end
  ---@param session CheatsheetSession
  ---@param size CheatsheetGeometry
  ---@param document CheatsheetDocument
  ---@param reset boolean
  ---@return nil
  function adapter.update(session, size, document, reset)
    if state.fail_update then
      error("update failed")
    end
    state.updates = state.updates + 1
    state.size, state.document, state.reset = size, document, reset
    if state.reenter then
      state.reenter()
    end
  end
  ---@param session CheatsheetSession
  ---@return nil
  function adapter.close(session)
    if state.fail_close then
      error("close failed")
    end
    state.closed = state.closed + 1
    ---@cast session CheatsheetTestSession
    session.alive = false
    state.current_buf = 10
    if state.on_close then
      state.on_close(session)
    end
  end
  local instance = controller.new(adapter)
  if not skip_setup then
    instance.setup(options or { modes = { "n", "i" }, group_rules = { { pattern = "^Test:", group = "test" } } })
  end
  return instance, state
end

---@param state CheatsheetTestState
---@param text string
---@return nil
local function contains(state, text)
  assert(table.concat(assert(state.document).lines, "\n"):find(text, 1, true), "missing " .. text)
end

t.test("all public opening operations require setup; hide and resize are safe", function()
  local instance, state = fixture(nil, true)
  instance.show()
  instance.toggle()
  instance.next_mode()
  instance.prev_mode()
  instance.hide()
  instance.resize()
  t.equal(state.created, 0)
  t.equal(#state.messages, 4)
  t.equal(state.displayed, false)
end)

t.test("setup validates once and subsequent setup keeps the original config", function()
  local instance, state = fixture({ modes = {} })
  t.equal(assert(state.options).modes, { "n", "i", "v", "o", "t" })
  instance.setup({ modes = { "i" } })
  t.equal(state.installed, 1)
  t.equal(state.messages[#state.messages].level, "WARN")
end)

t.test("failed installation reports an error and permits a clean retry", function()
  local instance, state = fixture(nil, true)
  state.fail_install = true
  instance.setup()
  t.equal(state.messages[1].level, "ERROR")
  state.fail_install = false
  instance.setup()
  instance.show()
  t.equal(state.installed, 1)
  t.equal(state.displayed, true)
end)

t.test("source context is captured once and reused across show and mode changes", function()
  local instance, state = fixture()
  instance.show()
  contains(state, "Local n")
  instance.next_mode()
  contains(state, "Local i")
  instance.show("n")
  t.equal(state.created, 1)
  t.equal(state.updates, 3)
  t.equal(assert(state.session).source_buf, 10)
  t.equal(state.displayed, true)
  t.equal(state.reset, true)
end)

t.test("invalid or unconfigured modes do not change an open session", function()
  local instance, state = fixture()
  -- Negative tests deliberately bypass the public API type contract.
  ---@diagnostic disable-next-line: param-type-mismatch
  instance.show("bad")
  ---@diagnostic disable-next-line: param-type-mismatch
  instance.show(false)
  t.equal(state.created, 0)
  instance.show("i")
  instance.show("v")
  t.equal(state.created, 1)
  t.equal(state.updates, 1)
  contains(state, "Local i")
  t.equal(state.messages[#state.messages].level, "ERROR")
end)

t.test("mode switching wraps and can open a closed browser", function()
  local instance, state = fixture()
  instance.prev_mode()
  contains(state, "Local i")
  instance.next_mode()
  contains(state, "Local n")
  instance.next_mode()
  contains(state, "Local i")
end)

t.test("resize preserves the session and mode, does not reset the view and skips identical geometry", function()
  local instance, state = fixture()
  instance.show("i")
  local session = assert(state.session)
  instance.resize()
  t.equal(state.updates, 1)
  state.columns = 100
  instance.resize()
  t.equal(state.session, session)
  t.equal(state.created, 1)
  t.equal(state.updates, 2)
  t.equal(assert(state.size).width, 80)
  t.equal(state.reset, false)
  contains(state, "Local i")
end)

t.test("hide is idempotent and reopening resets to the first mode", function()
  local instance, state = fixture()
  instance.show("i")
  instance.hide()
  instance.hide()
  t.equal(state.closed, 1)
  t.equal(state.displayed, false)
  instance.show()
  contains(state, "Local n")
  t.equal(state.created, 2)
end)

t.test("toggle uses owned resources, not a mutable displayed flag", function()
  local instance, state = fixture()
  state.displayed = true
  instance.toggle()
  t.equal(state.created, 1)
  state.displayed = false
  instance.toggle()
  t.equal(state.closed, 1)
end)

t.test("foreign closure is ignored; own closure disposes the counterpart", function()
  local instance, state = fixture()
  instance.show("i")
  instance.closed("win", 999)
  instance.closed("buf", 999)
  t.equal(state.closed, 0)
  instance.closed("win", assert(state.session).win)
  t.equal(state.closed, 1)
  t.equal(assert(state.session).win, nil)
  t.equal(state.displayed, false)
  instance.show()
  instance.closed("buf", assert(state.session).buf)
  t.equal(state.closed, 2)
  t.equal(assert(state.session).buf, nil)
end)

t.test("cleanup callbacks cannot recursively close the same session", function()
  local instance, state = fixture()
  instance.show()
  state.on_close = function(session)
    instance.closed("win", session.win)
    instance.closed("buf", session.buf)
  end
  instance.hide()
  t.equal(state.closed, 1)
end)

t.test("a vanished source buffer falls back to global mappings", function()
  local instance, state = fixture()
  instance.show()
  state.source_deleted = true
  instance.next_mode()
  contains(state, "Global i")
  assert(not table.concat(assert(state.document).lines):find("Local", 1, true))
end)

t.test("invalid owned resources are cleaned on resize or reopening", function()
  local instance, state = fixture()
  instance.show()
  assert(state.session).alive = false
  instance.resize()
  t.equal(state.closed, 1)
  t.equal(state.displayed, false)
  instance.show()
  assert(state.session).alive = false
  instance.show()
  t.equal(state.created, 3)
  t.equal(state.closed, 2)
end)

---@type CheatsheetTestFailure[]
local opening_failures = { "fail_create", "fail_collect", "fail_update", "fail_viewport" }
for _, failure in ipairs(opening_failures) do
  t.test("opening failure " .. failure .. " cleans up and permits reopening", function()
    local instance, state = fixture()
    state[failure] = true
    instance.show()
    t.equal(state.displayed, false)
    t.equal(state.closed, (failure == "fail_create" or failure == "fail_viewport") and 0 or 1)
    t.equal(state.messages[#state.messages].level, "ERROR")
    state[failure] = false
    instance.show()
    t.equal(state.displayed, true)
  end)
end

t.test("redraw failures dispose the session and are reported", function()
  ---@type CheatsheetTestFailure[]
  local redraw_failures = { "fail_collect", "fail_update", "fail_viewport" }
  for _, failure in ipairs(redraw_failures) do
    local instance, state = fixture()
    instance.show()
    state.columns, state[failure] = 100, true
    instance.resize()
    t.equal(state.displayed, false)
    t.equal(state.closed, 1)
    t.equal(state.messages[#state.messages].level, "ERROR")
  end
end)

t.test("failed closure retains a live session, its mode and a retry path", function()
  local instance, state = fixture()
  instance.show("i")
  state.fail_close = true
  instance.hide()
  t.equal(state.displayed, true)
  instance.next_mode()
  contains(state, "Local n")
  state.fail_close = false
  instance.hide()
  t.equal(state.displayed, false)
end)

t.test("partial cleanup failure retains remaining resources without rendering a broken session", function()
  local instance, state = fixture()
  instance.show()
  assert(state.session).buf = nil
  state.fail_close = true
  instance.hide()
  t.equal(state.displayed, false)
  instance.show()
  instance.toggle()
  t.equal(state.created, 1)
  t.equal(state.updates, 1)
  state.fail_close = false
  instance.hide()
  t.equal(state.closed, 1)
  instance.show()
  t.equal(state.created, 2)
end)

t.test("partial creation transfers ownership even when its initial cleanup fails", function()
  local instance, state = fixture()
  state.partial_create, state.fail_close = true, true
  instance.show()
  t.equal(state.created, 1)
  t.equal(state.updates, 0)
  t.equal(state.displayed, true)
  state.fail_close = false
  instance.hide()
  t.equal(state.closed, 1)
  t.equal(state.displayed, false)
end)

t.test("reentrant render and resize requests do not recurse", function()
  local instance, state = fixture()
  state.reenter = function()
    instance.show()
    instance.resize()
  end
  instance.show()
  t.equal(state.updates, 1)
end)

t.test("controller instances own independent configuration and sessions", function()
  local first, a = fixture()
  local second, b = fixture({ modes = { "i" } })
  first.show()
  second.show()
  t.equal(a.collected_mode, "n")
  t.equal(b.collected_mode, "i")
  first.hide()
  t.equal(b.displayed, true)
end)

local ok, err = pcall(t.run, "cheatsheet controller (without vim)")
_G.vim = host_vim
assert(ok, err)
