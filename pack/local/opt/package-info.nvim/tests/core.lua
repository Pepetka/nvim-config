local directory = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "./"
package.path = directory .. "../lua/?.lua;" .. directory .. "?.lua;" .. package.path
local t = require("support")
local config = require("package_info.core.config")
local cache = require("package_info.core.cache")
local manifest = require("package_info.core.manifest")
local registry = require("package_info.core.registry")
local requests = require("package_info.core.requests")
local protocol = require("package_info.core.protocol")
local presentation = require("package_info.core.presentation")
local fixtures = require("fixtures")
local filters = require("package_info.core.filters")
local render_queue = require("package_info.core.render_queue")
local saved = rawget(_G, "vim")
_G.vim = nil

t.test("annotation updates retain the first render and coalesce bursts without delaying the deadline", function()
  local timers, applied = {}, {}
  local queue = render_queue.new(function(delay, callback)
    t.equal(delay, 16)
    local timer = { callback = callback, cancelled = false }
    timers[#timers + 1] = timer
    return function()
      timer.cancelled = true
    end
  end, function(buf, state)
    applied[#applied + 1] = { buf, state.error }
  end, function()
    error("unexpected render error")
  end)
  local state = { lines = {}, tickets = {}, error = "initial" }
  queue.request(1, state)
  t.equal(applied, { { 1, "initial" } })
  for index = 1, 50 do
    state.error = tostring(index)
    queue.request(1, state)
  end
  t.equal(#timers, 1)
  t.equal(queue.pending(), 1)
  timers[1].callback()
  t.equal(applied, { { 1, "initial" }, { 1, "50" } })
  t.equal(queue.pending(), 0)
  queue.request(1, state)
  local late = timers[2]
  queue.cancel(1)
  assert(late.cancelled)
  local replacement = { lines = {}, tickets = {}, error = "replacement" }
  queue.request(1, replacement)
  late.callback()
  t.equal(applied[3], { 1, "replacement" })
  t.equal(#applied, 3)
  queue.request(1, replacement)
  queue.request(2, state)
  queue.request(2, state)
  queue.teardown()
  for _, timer in ipairs(timers) do
    timer.callback()
  end
  t.equal(#applied, 4)
  t.equal(queue.pending(), 0)
end)
t.test("annotation snapshots compare both text and highlight without depending on map order", function()
  local rows = { [0] = { { "text", "Comment" } }, [2] = { { "other", "PackageInfoUpdate" } } }
  assert(presentation.same_annotations(rows, t.copy(rows)))
  assert(not presentation.same_annotations(rows, { [0] = { { "text", "PackageInfoError" } }, [2] = rows[2] }))
  assert(not presentation.same_annotations(rows, { [0] = rows[0] }))
  assert(not presentation.same_annotations(nil, {}))
  assert(presentation.same_annotations({}, {}))
end)
t.test("CLI metadata identity ignores declarations but changes with registry and manager context", function()
  local context = {
    dir = "/a:b",
    root = "/root",
    manager = "npm",
    major = 11,
    fingerprint = "manifest1",
    registry_fingerprint = "registry1",
    dependencies = {},
  }
  local key = registry.metadata_key(context, "a")
  context.fingerprint = "manifest2"
  t.equal(registry.metadata_key(context, "a"), key)
  for field, value in pairs({
    dir = "/other",
    root = "/workspace",
    manager = "pnpm",
    major = 10,
    registry_fingerprint = "registry2",
  }) do
    local changed = t.copy(context)
    changed[field] = value
    assert(registry.metadata_key(changed, "a") ~= key, field)
  end
  assert(registry.metadata_key(context, "b") ~= key)
end)

t.test("nested options preserve defaults, replace empty lists and copy caller values", function()
  local input = {
    auto_refresh = false,
    sections = {},
    exclude = { packages = { "@private/*" } },
    timeouts = { registry = 25000 },
    cache = { ttl = 0, memory_limit = 0, disk = false },
    display = { icons = { installed = "" }, float = { max_width = 70 } },
  }
  local options, errors = config.normalize(input)
  t.equal(errors, {})
  t.equal(options.auto_refresh, { on_enter = false, on_save = false })
  t.equal(options.sections, {})
  t.equal(options.timeouts.manager, 5000)
  t.equal(options.timeouts.registry, 25000)
  t.equal(options.display.icons.update, "󰚰")
  input.exclude.packages[1] = "changed"
  t.equal(options.exclude.packages, { "@private/*" })
  t.equal(config.normalize().sections, config.defaults().sections)
  local invalid, warnings = config.normalize({
    timeouts = { registry = 0, helper = 17 },
    concurrency = { http = -1 },
    exclude = { projects = { "relative" } },
    display = { virt_text_pos = "unknown", float = { max_width = math.huge } },
    cache = { ttl = 0 / 0 },
    misspelled = true,
  })
  t.equal(#warnings, 7)
  t.equal(invalid.timeouts.helper, 17)
  t.equal(invalid.timeouts.registry, 15000)
end)
t.test("filters match package names and aliases, select sections and respect project boundaries", function()
  local deps = {
    { name = "a", spec = "^1", section = "dependencies", kind = "range", target = "a", range = "^1" },
    {
      name = "alias",
      spec = "npm:@private/lib@^1",
      section = "dependencies",
      kind = "range",
      target = "@private/lib",
      range = "^1",
    },
    { name = "b", spec = "^1", section = "devDependencies", kind = "range", target = "b", range = "^1" },
  }
  local options = config.normalize({ sections = { "dependencies" }, exclude = { packages = { "@private/*" } } })
  t.equal(filters.dependencies(deps, options), { deps[1] })
  options.sections = {}
  t.equal(filters.dependencies(deps, options), {})
  assert(filters.matches("a.b", "a.?"))
  assert(not filters.matches("axb", "a.b"))
  assert(filters.excluded_project("/project/package.json", { "/project/" }))
  assert(not filters.excluded_project("/projects/package.json", { "/project" }))
  assert(filters.excluded_project("/any/package.json", { "/" }))
end)
t.test("display filters statuses and supports text icons and annotation disabling", function()
  local state = {
    lines = { ["dependencies:a"] = 0 },
    tickets = {},
    error = "failure",
    context = {
      dir = "/tmp",
      root = "/tmp",
      manager = "npm",
      fingerprint = "a",
      registry_fingerprint = "a",
      dependencies = {
        {
          name = "a",
          spec = "^1",
          section = "dependencies",
          kind = "range",
          installed = { version = "1.0.0" },
          result = { status = "update", wanted = "1.1.0" },
        },
      },
    },
  }
  local options =
    config.normalize({ display = { statuses = { "installed" }, prefix = " | ", icons = { installed = "" } } })
  t.equal(presentation.annotations(state, options.display), { [0] = { { " | 1.0.0", "Comment" } } })
  options.display.enabled = false
  t.equal(presentation.annotations(state, options.display), {})
end)
t.test("custom cache lifetime, backoff and zero limits take effect", function()
  local options = config.normalize({ cache = { ttl = 10, retry = 2, cli_limit = 0 } }).cache
  assert(cache.fresh({ time = 0, stdout = "metadata" }, 9, false, options))
  assert(not cache.fresh({ time = 0, stdout = "metadata" }, 10, false, options))
  assert(not cache.fresh({ time = 0, error = "error" }, 2, false, options))
  local values = { a = { time = 0, stdout = "metadata" } }
  cache.prune(values, 1, options)
  t.equal(values, {})
end)

t.test("protocol validates optional context fields even in error responses", function()
  ---@type table<string, unknown>
  local context =
    { dir = "/tmp", root = "/tmp", manager = "npm", fingerprint = "a", registry_fingerprint = "a", dependencies = {} }
  for key, value in pairs({
    major = {},
    expected_major = 0,
    marker = false,
    pnp = "yes",
    overrides = {},
    custom_plugins = 1,
  }) do
    local invalid = config.copy(context)
    invalid[key] = value
    assert(not protocol.context(invalid), key)
    invalid.error = "safe failure"
    assert(not protocol.context(invalid), key .. " with error")
  end
  for _, value in ipairs({ -1, 1.5, math.huge, 0 / 0 }) do
    local invalid = config.copy(context)
    invalid.major = value
    assert(not protocol.context(invalid))
  end
  local failed = config.copy(context)
  failed.manager, failed.error = nil, "Conflicting lockfiles"
  local validated = assert(protocol.context(failed))
  local instance, _, _, adapter = fixtures.controller()
  assert(presentation.status({ context = validated, lines = {}, tickets = {} }, adapter.helper, adapter.queue, 0))
  instance.teardown()
end)
t.test("protocol rejects malformed progress, enums, flags and timestamps", function()
  local event =
    { records = { { name = "a", section = "dependencies", age_ms = 0, cached = false } }, completed = 1, total = 1 }
  assert(protocol.event(event))
  for _, value in ipairs({ -1, 1.5, math.huge, 0 / 0 }) do
    local invalid = config.copy(event)
    invalid.completed = value
    assert(not protocol.event(invalid))
  end
  for key, value in pairs({ section = "other", age_ms = -1, cached = "yes", kind = "invalid" }) do
    local invalid = config.copy(event)
    invalid.records[1][key] = value
    assert(not protocol.event(invalid), key)
  end
  assert(not protocol.event({ records = {}, completed = 2, total = 1 }))
  assert(not protocol.event({ complete = true, records = {} }))
  assert(protocol.event({ reconfigure = true }))
  assert(not protocol.event({ reconfigure = true, complete = true }))
  assert(not protocol.configuration({ fallback = "yes", client = "client" }))
  assert(not protocol.configuration({ fallback = true, client = "client" }))
  assert(not protocol.comparison({ status = "current", checked_at = math.huge }))
end)

t.test("options replace old overrides and never share caller/default tables", function()
  local input = { managers = { ["/tmp/project"] = "yarn@4" }, fast_registry = false }
  local normalized, messages = config.normalize(input)
  t.equal(messages, {})
  assert(not normalized.fast_registry)
  input.managers["/tmp/project"] = "npm"
  t.equal(normalized.managers["/tmp/project"], "yarn@4")
  t.equal(config.normalize({ managers = {} }).managers, {})
  t.equal(config.normalize().managers, {})
end)
for _, input in ipairs({
  false,
  { managers = false },
  { managers = { ["relative"] = "yarn@4" } },
  { managers = { ["/absolute"] = "invalid" } },
  { fast_registry = "true" },
}) do
  t.test("invalid configuration " .. tostring(input), function()
    local _, messages = config.normalize(input)
    assert(#messages > 0)
  end)
end
t.test("cache observes TTL, error backoff, force and future clocks", function()
  assert(cache.fresh({ time = 0, stdout = "valid" }, cache.ttl - 1))
  assert(not cache.fresh({ time = 0, stdout = "valid" }, cache.ttl))
  assert(not cache.fresh({ time = 0, error = "error" }, cache.retry))
  assert(not cache.fresh({ time = 1 }, 0))
  assert(not cache.fresh({ time = 0 }, 1, true))
  assert(not cache.fresh(nil, 1))
end)
t.test("cache eviction removes the oldest entries rather than iteration order", function()
  local values = {}
  for index = 1, 1002 do
    values[tostring(index)] = { time = index }
  end
  cache.prune(values, 1002)
  assert(not values["1"] and not values["2"] and values["1002"])
end)
t.test("manifest rejects nested duplicates and keeps section identities", function()
  local facts = {
    { object = "root", key = "dependencies", kind = "object", top = true, row = 0 },
    { object = "dependencies", key = "a", kind = "string", section = "dependencies", row = 1 },
    { object = "dev", key = "a", kind = "string", section = "devDependencies", row = 2 },
  }
  t.equal(manifest.validate(facts), { ["dependencies:a"] = 1, ["devDependencies:a"] = 2 })
  facts[#facts + 1] = { object = "nested", key = "duplicate", kind = "string", row = 3 }
  facts[#facts + 1] = { object = "nested", key = "duplicate", kind = "string", row = 4 }
  t.equal(manifest.validate(facts), nil)
  t.equal(manifest.validate({ { object = "root", key = "dependencies", kind = "array", top = true, row = 0 } }), nil)
end)
t.test("commands cover npm pnpm and both Yarn families", function()
  t.equal(registry.command({ manager = "npm" }, "a"), { "npm", "view", "a", "versions", "dist-tags", "--json" })
  t.equal(registry.command({ manager = "pnpm" }, "a")[1], "pnpm")
  t.equal(registry.command({ manager = "yarn", major = 1 }, "a"), { "yarn", "info", "a", "--json" })
  t.equal(registry.batch_command({ manager = "npm" }, { "a" }), nil)
  t.equal(
    registry.batch_command({ manager = "yarn", major = 4 }, { "a", "b" }),
    { "yarn", "npm", "info", "a", "b", "--fields", "name,versions,dist-tags", "--json" }
  )
  t.equal(registry.compatible({ manager = "yarn", expected_major = 4 }, "1.22.22"), nil)
  t.equal(registry.compatible({ manager = "npm" }, "6.0.0"), nil)
  t.equal(registry.compatible({ manager = "pnpm" }, "10.0.0"), 10)
end)
for _, case in ipairs({
  { code = 124, kind = "timeout" },
  { code = 1, stderr = "401 SECRET", kind = "auth" },
  { code = 1, stderr = "usage error SECRET", kind = "config" },
  { code = 1, stderr = "404 SECRET", kind = "not_found" },
  { code = 1, stderr = "Corepack SECRET", kind = "manager" },
  { code = 1, stderr = "SECRET", kind = "network" },
}) do
  t.test("sanitized process error " .. case.kind, function()
    local kind, message = registry.error(case)
    t.equal(kind, case.kind)
    assert(not message:find("SECRET"))
  end)
end
t.test("invalidated buffers cannot render stale results", function()
  local state = { path = "/a/package.json", tick = 1, lines = {}, tickets = {} }
  local host = { path = state.path, tick = 1, modified = false }
  assert(requests.valid(state, state, host))
  host.modified = true
  assert(not requests.valid(state, state, host))
  host.modified = false
  host.tick = 2
  assert(not requests.valid(state, state, host))
  assert(not requests.valid({ lines = {}, tickets = {} }, state, host))
end)
t.test("protocol and presentation reject malformed success and preserve installed annotations", function()
  assert(not protocol.installed({ version = 42 }))
  assert(not protocol.installed({ reason = {} }))
  assert(not protocol.installed_list({ [2] = { version = "1.0.0" } }))
  assert(not protocol.installed_list({ unexpected = {} }))
  t.equal(protocol.installed_list({ { state = "installed", version = "1.0.0" } }), {
    { state = "installed", version = "1.0.0" },
  })
  assert(not protocol.comparison({ status = "update" }))
  assert(not protocol.configuration(true))
  assert(not protocol.event({ records = {}, completed = "invalid", total = 0 }))
  assert(not protocol.context({ dir = "/tmp", root = "/tmp", dependencies = {} }))
  local state = {
    lines = { ["dependencies:a"] = 1 },
    tickets = {},
    context = {
      dir = "/tmp",
      root = "/tmp",
      manager = "npm",
      fingerprint = "a",
      registry_fingerprint = "a",
      dependencies = {
        {
          name = "a",
          spec = "^1",
          section = "dependencies",
          kind = "range",
          installed = {
            state = "installed",
            version = "1.0.0",
          },
        },
      },
    },
  }
  t.equal(presentation.annotations(state)[1], { { "  󰏖 1.0.0", "Comment" } })
  assert(presentation.info(state, 1, 0)[1]:find("a"))
  t.equal(#presentation.info(nil, 0, 0), 1)
end)
local ok, err = pcall(t.run, "package-info pure core")
_G.vim = saved
assert(ok, err)
