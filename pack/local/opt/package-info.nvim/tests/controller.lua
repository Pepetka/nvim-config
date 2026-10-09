local directory = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "./"
package.path = directory .. "../lua/?.lua;" .. directory .. "?.lua;" .. package.path
local t = require("support")
local fixtures = require("fixtures")
local queue_factory = require("package_info.core.queue")
local saved = rawget(_G, "vim")
_G.vim = nil

t.test("streamed results share one redraw and unchanged annotations skip native writes", function()
  local instance, state, transport, _, advance = fixtures.controller()
  instance.setup({ fast_registry = true })
  assert(state.parse).lines = { ["dependencies:a"] = 0, ["dependencies:b"] = 1 }
  instance.refresh()
  local receive = assert(transport.receive)
  receive({
    id = 1,
    result = {
      dir = "/tmp/project",
      root = "/tmp/project",
      manager = "npm",
      fingerprint = "a",
      registry_fingerprint = "r",
      dependencies = {
        {
          name = "a",
          section = "dependencies",
          spec = "^1",
          kind = "range",
          target = "a",
          range = "^1",
          installed = {
            version = "1.0.0",
          },
        },
        {
          name = "b",
          section = "dependencies",
          spec = "^1",
          kind = "range",
          target = "b",
          range = "^1",
          installed = {
            version = "1.0.0",
          },
        },
      },
    },
  })
  t.equal(state.renders, 1)
  receive({ id = 2, result = { client = "test" } })
  for index, name in ipairs({ "a", "b" }) do
    receive({
      id = 3,
      done = false,
      result = {
        records = {
          {
            name = name,
            section = "dependencies",
            age_ms = 0,
            cached = false,
            result = {
              status = "update",
              wanted = "1.2.0",
            },
          },
        },
        completed = index,
        total = 2,
      },
    })
  end
  t.equal(state.renders, 1)
  t.equal(instance.renderer.pending(), 1)
  advance(15)
  t.equal(state.renders, 1)
  advance(1)
  t.equal(state.renders, 2)
  t.equal(
    state.annotations,
    { [0] = { { "  󰚰 1.2.0", "PackageInfoUpdate" } }, [1] = { { "  󰚰 1.2.0", "PackageInfoUpdate" } } }
  )
  receive({ id = 3, result = { complete = true } })
  advance(16)
  t.equal(state.renders, 2)
  instance.teardown()
end)
t.test("queued annotation updates cannot restore edited, replaced, disabled or stopped buffers", function()
  for _, action in ipairs({ "edit", "refresh", "toggle", "teardown" }) do
    local instance, state, transport, _, advance = fixtures.controller()
    instance.refresh()
    assert(transport.receive)({
      id = 1,
      result = {
        dir = "/tmp",
        root = "/tmp",
        manager = "npm",
        fingerprint = "a",
        registry_fingerprint = "r",
        dependencies = {
          { name = "a", section = "dependencies", spec = "^1", kind = "range", target = "a", range = "^1" },
        },
      },
    })
    assert(instance.renderer.pending() > 0)
    local before = state.renders
    if action == "edit" then
      assert(state.host).tick = 2
    elseif action == "refresh" then
      instance.refresh()
    elseif action == "toggle" then
      instance.toggle()
    else
      instance.teardown()
    end
    advance(16)
    t.equal(state.renders, before, action)
    instance.teardown()
  end
end)

t.test("custom helper deadline and retry backoff govern pending requests", function()
  local helper, state, advance = fixtures.helper()
  helper.configure(require("package_info.core.config").normalize({ timeouts = { helper = 7 }, cache = { retry = 3 } }))
  local calls = 0
  helper.request("inspect", {}, function()
    calls = calls + 1
  end)
  advance(6)
  t.equal(calls, 0)
  advance(1)
  t.equal(calls, 1)
  assert(state.sent[2].method == "cancel")
  assert(state.exit)()
  helper.ensure(function(ok)
    assert(not ok)
  end)
  t.equal(state.starts, 1)
  advance(3)
  helper.ensure(function(ok)
    assert(ok)
  end)
  t.equal(state.starts, 2)
  helper.stop()
end)
t.test("custom CLI limits constrain global and project process counts", function()
  local callbacks = {}
  local queue = queue_factory.new(function(_, callback)
    callbacks[#callbacks + 1] = callback
    return { kill = function() end }
  end, function() end)
  queue.configure(
    require("package_info.core.config").normalize({ concurrency = { cli = 2, cli_per_project = 1 } }).concurrency
  )
  for _, project in ipairs({ "a", "a", "b", "c" }) do
    queue.submit({
      project = project,
      cwd = project,
      command = { "test" },
      cancelled = function()
        return false
      end,
      callback = function() end,
    })
  end
  t.equal(queue.active, 2)
  t.equal(queue.projects.a, 1)
  t.equal(queue.projects.b, 1)
  callbacks[1]({ code = 0 })
  t.equal(queue.active, 2)
  t.equal(queue.projects.a, 1)
  queue.teardown()
end)
t.test("excluded projects start no helper and selected sections filter registry declarations", function()
  local instance, _, transport = fixtures.controller()
  instance.setup({ exclude = { projects = { "/tmp/project" } } })
  instance.refresh()
  t.equal(transport.sent, {})
  instance.setup({ fast_registry = false, sections = { "dependencies" }, exclude = { packages = { "@private/*" } } })
  instance.refresh()
  assert(transport.receive)({
    id = 1,
    result = {
      dir = "/tmp/project",
      root = "/tmp/project",
      manager = "npm",
      fingerprint = "a",
      registry_fingerprint = "a",
      dependencies = {
        {
          name = "alias",
          spec = "npm:@private/pkg@^1",
          section = "dependencies",
          kind = "range",
          target = "@private/pkg",
          range = "^1",
        },
        { name = "dev", spec = "^1", section = "devDependencies", kind = "range", target = "dev", range = "^1" },
      },
    },
  })
  t.equal(instance.buffers[1].context.dependencies, {})
  t.equal(#transport.sent, 1)
  instance.teardown()
end)

t.test("an evicted helper client is configured again without failing the buffer check", function()
  local instance, state, transport = fixtures.controller()
  instance.setup({ fast_registry = true })
  instance.refresh()
  local receive = assert(transport.receive)
  receive({
    id = 1,
    result = {
      dir = "/tmp/project",
      root = "/tmp/project",
      manager = "npm",
      fingerprint = "manifest",
      registry_fingerprint = "registry",
      pnp = false,
      custom_plugins = false,
      overrides = false,
      dependencies = {
        {
          name = "a",
          spec = "^1",
          section = "dependencies",
          kind = "range",
          target = "a",
          range = "^1",
          installed = { state = "installed", version = "1.0.0" },
        },
      },
    },
  })
  t.equal(transport.sent[2].method, "configure")
  receive({ id = 2, result = { client = "old" } })
  t.equal(transport.sent[3].method, "check")
  receive({ id = 3, result = { reconfigure = true } })
  t.equal(transport.sent[4].method, "configure")
  receive({ id = 4, result = { client = "new" } })
  t.equal(transport.sent[5].input.client, "new")
  receive({
    id = 5,
    result = {
      records = {
        {
          name = "a",
          section = "dependencies",
          age_ms = 0,
          cached = false,
          result = { status = "current", wanted = "1.0.0", latest = "1.0.0" },
        },
      },
      completed = 1,
      total = 1,
    },
    done = false,
  })
  receive({ id = 5, result = { complete = true } })
  t.equal(instance.buffers[1].error, nil)
  t.equal(instance.buffers[1].network_ticket, nil)
  assert(state.renders > 0)
  local context = assert(instance.buffers[1].context)
  instance.refresh()
  receive({ id = 6, result = context })
  t.equal(transport.sent[7].method, "check")
  receive({ id = 7, result = { reconfigure = true } })
  receive({ id = 8, result = { client = "third" } })
  receive({ id = 9, result = { reconfigure = true } })
  t.equal(instance.buffers[1].backend, "manager CLI (registry client unavailable)")
  t.equal(transport.sent[10].method, "compare")
  instance.teardown()
end)

t.test("stopping during bootstrap ignores late success and failure", function()
  for _, error_message in ipairs({ false, "late error" }) do
    local helper, state = fixtures.helper()
    state.hold = true
    local calls = 0
    helper.ensure(function()
      calls = calls + 1
    end)
    local startup = assert(state.bootstrap)
    helper.stop()
    startup(error_message or nil)
    t.equal(helper.state, "idle")
    t.equal(state.starts, 0)
    t.equal(calls, 1)
  end
end)
t.test("a new helper generation ignores callbacks from the old process", function()
  local helper, state = fixtures.helper()
  helper.ensure(function() end)
  local old_exit = assert(state.exit)
  helper.stop()
  helper.ensure(function() end)
  old_exit()
  t.equal(helper.state, "ready")
  t.equal(state.starts, 2)
end)
t.test("streaming requests complete once and stop their timers", function()
  local helper, state, advance = fixtures.helper()
  local calls = 0
  local ticket = helper.request("check", {}, function()
    calls = calls + 1
  end)
  local receive = assert(state.receive)
  receive({ id = ticket.id, result = {}, done = false })
  t.equal(calls, 1)
  receive({ id = ticket.id, result = {}, done = true })
  receive({ id = ticket.id, result = {} })
  advance(5001)
  t.equal(calls, 2)
  t.equal(helper.pending, {})
  assert(state.timers[1].cancelled)
end)
t.test("timeout, cancellation and send failures leave no pending requests", function()
  local helper, state, advance = fixtures.helper()
  local calls = 0
  helper.request("inspect", {}, function(_, err)
    assert(err)
    calls = calls + 1
  end)
  advance(5000)
  t.equal(calls, 1)
  t.equal(helper.pending, {})
  local ticket = helper.request("inspect", {}, function()
    calls = calls + 1
  end)
  helper.cancel(ticket)
  advance(5000)
  t.equal(calls, 1)
  state.fail_send = true
  helper.request("inspect", {}, function(_, err)
    assert(err)
    calls = calls + 1
  end)
  t.equal(calls, 2)
  t.equal(helper.pending, {})
end)
t.test("cancelled bootstrap waiters are released without launching requests", function()
  local helper, state = fixtures.helper()
  state.hold = true
  local ticket = helper.request("inspect", {}, function()
    error("cancelled callback")
  end)
  helper.cancel(ticket)
  t.equal(helper.waiting, {})
  assert(state.bootstrap)()
  t.equal(state.sent, {})
end)
t.test("one failing callback cannot lose other helper responses", function()
  local helper, state = fixtures.helper()
  local calls = 0
  local a = helper.request("inspect", {}, function()
    error("callback failure")
  end)
  local b = helper.request("inspect", {}, function()
    calls = calls + 1
  end)
  assert(state.receive)({ id = a.id, result = {} })
  assert(state.receive)({ id = b.id, result = {} })
  t.equal(calls, 1)
  t.equal(#state.notifications, 1)
  t.equal(helper.pending, {})
end)
t.test("queue is safe for synchronous completion and spawn failure", function()
  local calls = 0
  local queue = queue_factory.new(function(_, callback)
    callback({ code = 0 })
    return { kill = function() end }
  end, function() end)
  local task = {
    project = "a",
    cwd = "a",
    command = { "test" },
    cancelled = function()
      return false
    end,
    callback = function()
      calls = calls + 1
    end,
  }
  queue.submit(task)
  t.equal(queue.active, 0)
  t.equal(queue.jobs, {})
  local failed = queue_factory.new(function()
    error("spawn failure")
  end, function() end)
  failed.submit(task)
  t.equal(failed.active, 0)
  t.equal(calls, 2)
end)
t.test("queue releases slots and continues after a callback throws", function()
  local callbacks = {}
  local errors = 0
  local queue = queue_factory.new(function(_, callback)
    callbacks[#callbacks + 1] = callback
    return { kill = function() end }
  end, function()
    errors = errors + 1
  end)
  for index = 1, 6 do
    queue.submit({
      project = tostring(index),
      cwd = "a",
      command = { "test" },
      cancelled = function()
        return false
      end,
      callback = function()
        if index == 1 then
          error("callback failure")
        end
      end,
    })
  end
  t.equal(queue.active, 4)
  t.equal(#callbacks, 4)
  callbacks[1]({ code = 0 })
  t.equal(#callbacks, 5)
  t.equal(errors, 1)
  queue.teardown()
  for _, callback in ipairs(callbacks) do
    callback({ code = 0 })
  end
  t.equal(queue.active, 0)
  t.equal(queue.jobs, {})
  t.equal(queue.waiting, {})
end)
t.test("controller setup replaces options, cancels pending work and reinstalls", function()
  local instance, _, transport = fixtures.controller()
  instance.setup({ managers = { ["/tmp/project"] = "yarn@4" } })
  instance.refresh()
  local receive = assert(transport.receive)
  instance.setup({ managers = {} })
  receive({ id = 1, result = {} })
  t.equal(instance.config.managers, {})
  t.equal(instance.buffers, {})
  instance.teardown()
  instance.teardown()
  assert(not instance.active)
  instance.setup()
  assert(instance.active)
end)
t.test("editing, renaming and disabling buffers invalidate helper replies", function()
  for _, action in ipairs({ "edit", "rename", "disable", "close" }) do
    local instance, state, transport = fixtures.controller()
    instance.refresh()
    local receive = assert(transport.receive)
    if action == "edit" then
      assert(state.host).tick = 2
    elseif action == "rename" then
      assert(state.host).path = "/different/package.json"
    elseif action == "close" then
      state.host = nil
    else
      instance.toggle()
    end
    receive({
      id = 1,
      result = {
        dir = "/tmp",
        root = "/tmp",
        manager = "npm",
        fingerprint = "a",
        registry_fingerprint = "a",
        dependencies = {},
      },
    })
    t.equal(state.renders, 0)
    instance.teardown()
  end
end)
t.test("host changes while parsing discard the captured manifest", function()
  local instance, state, transport = fixtures.controller()
  state.after_parse = function()
    assert(state.host).tick = 2
  end
  instance.refresh()
  t.equal(transport.sent, {})
end)
t.test("malformed helper contexts render a safe error instead of crashing", function()
  local instance, state, transport = fixtures.controller()
  instance.refresh()
  assert(transport.receive)({ id = 1, result = true })
  t.equal(instance.buffers[1].error, "Invalid helper context")
  t.equal(state.renders, 1)
  instance.info()
  instance.status()
  assert(#state.floated > 0)
end)
t.test("manifest adapter exceptions become a safe error without starting requests", function()
  local instance, state, transport = fixtures.controller()
  state.after_parse = function()
    error("private registry token")
  end
  instance.refresh()
  t.equal(instance.buffers[1].error, "Cannot parse package manifest")
  t.equal(transport.sent, {})
end)
t.test("cancellation retains process slots until the native exit callback", function()
  local callbacks = {}
  local cancelled = false
  local kills = 0
  local queue = queue_factory.new(function(_, callback)
    callbacks[#callbacks + 1] = callback
    return {
      kill = function()
        kills = kills + 1
      end,
    }
  end, function() end)
  for _ = 1, 3 do
    queue.submit({
      project = "same",
      cwd = "same",
      command = { "test" },
      cancelled = function()
        return cancelled
      end,
      callback = function()
        error("cancelled callback")
      end,
    })
  end
  t.equal(queue.active, 2)
  cancelled = true
  queue.cancel()
  queue.cancel()
  t.equal(queue.active, 2)
  t.equal(kills, 2)
  for _, callback in ipairs(callbacks) do
    callback({ code = 143, signal = 15 })
  end
  t.equal(queue.active, 0)
  t.equal(queue.waiting, {})
end)
local ok, err = pcall(t.run, "package-info controllers without vim")
_G.vim = saved
assert(ok, err)
