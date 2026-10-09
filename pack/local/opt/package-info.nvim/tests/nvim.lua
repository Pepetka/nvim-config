-- Run from the plugin root: nvim --clean --headless -i NONE -l tests/nvim.lua
local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(plugin_root)
vim.opt.rtp:append(vim.env.PACKAGE_INFO_TEST_PARSER_RTP or vim.fn.stdpath("data") .. "/site")
local function check(value, message)
  assert(value, message)
end
local adapter = require("package_info.integrations.nvim").new()
local helper = adapter.helper
helper.runtime = vim.env.PACKAGE_INFO_TEST_RUNTIME or helper.runtime
if vim.uv.fs_stat(helper.runtime .. "/node_modules/semver") then
  vim.fn.writefile(
    { vim.fn.sha256(table.concat(vim.fn.readfile(helper.source .. "/package-lock.json", "b"), "\n")) },
    helper.runtime .. "/installed-lock",
    "b"
  )
end
local real_system = vim.system
local pending, commands, concurrent, peak, per_project = {}, {}, 0, 0, {}
local info
local faults = {}
local metadata = vim.json.encode({ versions = { "1.0.0", "1.2.0", "2.0.0" }, ["dist-tags"] = { latest = "2.0.0" } })
---@diagnostic disable-next-line: duplicate-set-field
vim.system = function(command, options, callback)
  if command[1] == "node" or command[2] == "ci" then
    return real_system(command, options, callback)
  end
  table.insert(commands, command)
  check(options.env.COREPACK_ENABLE_NETWORK == "0", "Corepack networking must be disabled")
  check(options.timeout == (command[2] == "--version" and 5000 or 15000), "wrong process timeout")
  concurrent = concurrent + 1
  peak = math.max(peak, concurrent)
  per_project[options.cwd] = (per_project[options.cwd] or 0) + 1
  check(concurrent <= 4 and per_project[options.cwd] <= 2, "process limits exceeded")
  local process = { killed = false }
  function process:kill()
    self.killed = true
  end
  table.insert(pending, { command = command, callback = callback, cwd = options.cwd, process = process })
  return process
end
local function respond(entry, override)
  concurrent = concurrent - 1
  per_project[entry.cwd] = per_project[entry.cwd] - 1
  local result = override
    or (entry.command[2] == "--version" and faults.manager)
    or faults[entry.command[1] == "yarn" and entry.command[4] or entry.command[3]]
    or {
      code = 0,
      stdout = entry.command[2] == "--version" and (entry.command[1] == "yarn" and "4.18.0\n" or "11.19.0\n")
        or metadata,
      stderr = "",
    }
  if entry.process.killed then
    result = { code = 143, signal = 15 }
  end
  entry.callback(result)
end
local function settle()
  check(
    vim.wait(10000, function()
      while #pending > 0 do
        respond(table.remove(pending, 1))
      end
      return adapter.queue.active == 0
        and next(helper.pending) == nil
        and helper.state == "ready"
        and info.renderer.pending() == 0
    end, 10),
    "test timed out: " .. (helper.error or helper.state)
  )
end
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local function fixture(name, deps, manager)
  local dir = root .. "/" .. name
  vim.fn.mkdir(dir, "p")
  if manager then
    info.config.managers[vim.uv.fs_realpath(dir)] = manager
  end
  local data = { dependencies = deps, devDependencies = { example = "^2" }, overrides = { example = "1" } }
  vim.fn.writefile(vim.split(vim.json.encode(data), "\n"), dir .. "/package.json")
  for pkg in pairs(deps) do
    vim.fn.mkdir(dir .. "/node_modules/" .. pkg, "p")
    vim.fn.writefile(
      { vim.json.encode({ name = pkg, version = "1.0.0" }) },
      dir .. "/node_modules/" .. pkg .. "/package.json"
    )
  end
  vim.cmd.edit(vim.fn.fnameescape(dir .. "/package.json"))
  return vim.api.nvim_get_current_buf()
end
info = require("package_info.controller").new(adapter)
info.setup({ fast_registry = false })
local first = fixture("first", { example = "^1", another = "^1", third = "^1", fourth = "^1" })
settle()
local state = info.buffers[first]
check(state and not state.error, "initial lookup failed")
check(#state.context.dependencies == 5, "section identities lost")
check(state.context.dependencies[1].result ~= nil, "comparison missing")
check(#vim.api.nvim_buf_get_extmarks(first, adapter.namespace, 0, -1, {}) > 0, "no annotations")
local network_count = #commands
info.refresh(first)
settle()
check(#commands == network_count, "cache did not avoid registry requests")
-- Declarations and installed versions are inspected again; registry versions are reusable across range edits.
local manifest_file = vim.api.nvim_buf_get_name(first)
local manifest_data = vim.json.decode(table.concat(vim.fn.readfile(manifest_file), "\n"))
manifest_data.dependencies.example = "^2"
vim.fn.writefile({ vim.json.encode(manifest_data) }, manifest_file)
vim.cmd.edit({ args = { manifest_file }, bang = true })
info.refresh(first)
settle()
check(#commands == network_count, "a range edit repeated CLI registry requests")
local range_checked = false
for _, dep in ipairs(info.buffers[first].context.dependencies) do
  if dep.name == "example" and dep.section == "dependencies" then
    check(dep.result.wanted == "2.0.0", "reused metadata retained the old range comparison")
    range_checked = true
  end
end
check(range_checked, "edited declaration missing")
-- Registry configuration changes must still invalidate reused CLI metadata.
vim.fn.writefile({ "registry=https://registry.example.test" }, vim.fs.dirname(manifest_file) .. "/.npmrc")
info.refresh(first)
settle()
check(#commands > network_count, "registry configuration change reused CLI metadata")
network_count = #commands
info.refresh(first, true)
settle()
check(#commands > network_count + 1, "forced refresh did not bypass cache")
-- Changing text must immediately hide results, and old responses must not restore them.
info.refresh(first, true)
check(
  vim.wait(3000, function()
    return #pending > 0
  end, 10),
  "no pending process"
)
vim.api.nvim_buf_set_lines(first, 0, -1, false, { '{ "dependencies": { "example": "^9" } }' })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = first })
settle()
check(#vim.api.nvim_buf_get_extmarks(first, adapter.namespace, 0, -1, {}) == 0, "stale results reappeared")
check(info.buffers[first] == nil, "edited buffer retained old state")
-- Unsaved invalid JSON produces no requests. Duplicate keys are rejected by Tree-sitter mapping.
local count = #commands
info.refresh(first)
check(#commands == count, "unsaved edits triggered registry requests")
vim.bo[first].modified = false
vim.api.nvim_buf_set_lines(first, 0, -1, false, { '{ "dependencies": { "x": "1", "x": "2" } }' })
vim.bo[first].modified = false
info.refresh(first)
check(info.buffers[first].context == nil, "duplicate declaration accepted")
-- Nested overrides cannot steal dependency line mappings.
vim.api.nvim_buf_set_lines(first, 0, -1, false, {
  "{",
  '  "dependencies": { "example": "^1" },',
  '  "devDependencies": { "example": "^2" },',
  '  "overrides": { "example": "^3" }',
  "}",
})
vim.bo[first].modified = false
local parsed = assert(adapter.manifest(first))
check(
  parsed.lines["dependencies:example"] == 1 and parsed.lines["devDependencies:example"] == 2,
  "wrong Tree-sitter mapping"
)
-- An authentication error must preserve successful dependencies and use retry backoff.
info.refresh(first, true)
check(
  vim.wait(3000, function()
    return #pending > 0
  end, 10),
  "version lookup not queued"
)
respond(table.remove(pending, 1))
check(
  vim.wait(3000, function()
    return #pending > 0
  end, 10),
  "registry lookup not queued"
)
respond(table.remove(pending, 1), { code = 1, stderr = "401 Unauthorized SECRET", stdout = "" })
settle()
check(info.buffers[first].error == "Registry authentication failed", "auth error not classified or credential leak")
network_count = #commands
info.refresh(first)
settle()
check(#commands == network_count, "failure backoff not respected")
info.refresh(first, true)
settle()
check(not info.buffers[first].error, "forced retry did not recover")
-- Closing and toggling buffers cancel outstanding requests.
info.refresh(first, true)
check(
  vim.wait(3000, function()
    return #pending > 0
  end, 10),
  "toggle test request missing"
)
vim.cmd.PackageInfoToggle()
settle()
check(info.buffers[first].disabled, "toggle did not disable")
vim.api.nvim_exec_autocmds("BufEnter", { buffer = first })
check(info.buffers[first].disabled, "BufEnter undid toggle")
vim.cmd.PackageInfoToggle()
settle()
info.refresh(first, true)
check(
  vim.wait(3000, function()
    return #pending > 0
  end, 10),
  "close test request missing"
)
vim.api.nvim_buf_delete(first, { force = true })
settle()
check(info.buffers[first] == nil, "closed buffer retained state")
-- Four total processes, two per project, including simultaneous manifests.
local second = fixture("second", { a = "^1", b = "^1", c = "^1" })
local third = fixture("third", { a = "^1", b = "^1", c = "^1" })
check(
  vim.wait(3000, function()
    return #pending == 2
  end, 10),
  "simultaneous manager lookups missing"
)
respond(table.remove(pending, 1))
respond(table.remove(pending, 1))
check(
  vim.wait(3000, function()
    return concurrent == 4
  end, 10),
  "simultaneous registry requests missing"
)
settle()
check(peak == 4, "global queue was not exercised")
vim.api.nvim_set_current_buf(second)
local function close_preview()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      vim.api.nvim_win_close(win, true)
    end
  end
end
vim.cmd.PackageInfoStatus()
close_preview()
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.cmd.PackageInfo()
close_preview()
vim.api.nvim_set_hl(0, "PackageInfoUpdate", {})
vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "package-info-test" })
check(
  vim.api.nvim_get_hl(0, { name = "PackageInfoUpdate", link = true }).link == "DiagnosticInfo",
  "theme callback failed"
)
local registry = require("package_info.core.registry")
check(registry.error({ code = 124 }) == "timeout", "timeout classification")
check(registry.error({ code = 1, stderr = "Environment variable not found" }) == "config", "config classification")
check(registry.error({ code = 1, stderr = "404 not found" }) == "not_found", "404 classification")
check(registry.compatible({ manager = "yarn", expected_major = 4 }, "1.22.22") == nil, "wrong manager major accepted")
check(registry.command({ manager = "yarn", major = 1 }, "example")[2] == "info", "Yarn Classic adapter")
check(registry.command({ manager = "yarn", major = 4 }, "example")[2] == "npm", "Yarn Modern adapter")
-- A failing dependency must not remove successful comparisons, including on timeout.
faults.bad = { code = 124, stdout = "", stderr = "" }
local partial = fixture("partial", { bad = "^1", good = "^1" })
check(
  vim.wait(3000, function()
    return #pending > 0
  end, 10),
  "partial result manager missing"
)
respond(table.remove(pending, 1))
check(
  vim.wait(3000, function()
    return #pending > 0
  end, 10),
  "partial result registry missing"
)
while #pending > 0 do
  local entry = table.remove(pending, 1)
  respond(entry, entry.command[3] == "bad" and { code = 124, stdout = "", stderr = "" } or nil)
end
settle()
local successful, failed
for _, dep in ipairs(info.buffers[partial].context.dependencies) do
  if dep.name == "good" then
    successful = dep.result
  end
  if dep.name == "bad" then
    failed = dep.error_kind
  end
end
check(successful and failed == "timeout", "partial timeout hid successful metadata")
faults.bad = nil
local unavailable = fixture("unavailable", { missing_version = "^9" })
settle()
local unavailable_result
for _, dep in ipairs(info.buffers[unavailable].context.dependencies) do
  if dep.name == "missing_version" then
    unavailable_result = dep.result
  end
end
unavailable_result = assert(unavailable_result)
check(
  unavailable_result.status == "unavailable" and unavailable_result.wanted == nil,
  "unavailable range was not explicit"
)
vim.cmd.PackageInfo()
close_preview()
-- Infrastructure failures also back off, and a forced refresh retries them.
faults.manager = { code = 1, stdout = "Usage Error: Environment variable not found (TOKEN)", stderr = "" }
local broken_manager = fixture("broken-manager", { example = "^1" })
settle()
check(info.buffers[broken_manager].error:find("configuration"), "manager configuration failure lost")
local before_retry = #commands
info.refresh(broken_manager)
settle()
check(#commands == before_retry, "manager failure did not back off")
faults.manager = nil
info.refresh(broken_manager, true)
settle()
check(not info.buffers[broken_manager].error, "forced manager retry failed")
-- Modern Yarn batches names while keeping partial successes and retrying missing records individually.
faults.bad = { code = 1, stdout = "", stderr = "404 not found" }
local batched = fixture(
  "batched",
  { a = "^1", b = "^1", bad = "^1", c = "^1", d = "^1", e = "^1", f = "^1", g = "^1", h = "^1" },
  "yarn@4"
)
check(
  vim.wait(3000, function()
    return #pending > 0
  end, 10),
  "Yarn manager check missing"
)
respond(table.remove(pending, 1))
check(
  vim.wait(3000, function()
    return #pending == 2
  end, 10),
  "Yarn batches missing"
)
local batch_count, batch_successes = 0, 0
while #pending > 0 do
  local entry = table.remove(pending, 1)
  local names, records = {}, {}
  for index = 4, #entry.command do
    if entry.command[index] == "--fields" then
      break
    end
    table.insert(names, entry.command[index])
    if entry.command[index] ~= "bad" then
      local data = vim.json.decode(metadata)
      data.name = entry.command[index]
      table.insert(records, vim.json.encode(data))
      batch_successes = batch_successes + 1
    end
  end
  check(#names <= 8 and #names > 1, "unexpected batch size")
  batch_count = batch_count + 1
  respond(entry, { code = 1, stdout = table.concat(records, "\n"), stderr = "404 not found" })
end
settle()
check(
  batch_count == 2 and batch_successes == 9,
  "Yarn batch coverage incomplete: " .. batch_count .. "/" .. batch_successes
)
for _, dep in ipairs(info.buffers[batched].context.dependencies) do
  if dep.name == "bad" then
    check(dep.error_kind == "not_found", "batch error attribution lost")
  else
    check(dep.result ~= nil, "batch failure hid a successful dependency")
  end
end
faults.bad = nil
local cached_batch_count = #commands
info.refresh(batched)
settle()
check(#commands == cached_batch_count, "batch results were not cached by package")
-- Killing the persistent helper must expose the failure and permit a restart.
vim.fn.jobstop(helper.job)
check(
  vim.wait(3000, function()
    return helper.state == "failed"
  end, 10),
  "helper crash not detected"
)
info.refresh(second, true)
settle()
check(info.buffers[second].context ~= nil and helper.state == "ready", "helper did not restart")
helper.stop()
vim.system = real_system
vim.fn.delete(root, "rf")
print("package-info: Neovim integration tests passed")
vim.cmd("qa!")
