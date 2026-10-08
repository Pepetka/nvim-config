local plugin_root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(plugin_root)
vim.opt.rtp:append(vim.env.PACKAGE_INFO_TEST_PARSER_RTP or vim.fn.stdpath("data") .. "/site")
local helper = require("package_info.helper")
helper.runtime = vim.env.PACKAGE_INFO_TEST_RUNTIME or helper.runtime
local source = plugin_root
local url
local server = vim.fn.jobstart({ "node", source .. "/tests/server.cjs" }, {
  on_stdout = function(_, lines)
    for _, line in ipairs(lines) do
      if line:match("^http://") then
        url = line
      end
    end
  end,
})
assert(server > 0 and vim.wait(3000, function()
  return url ~= nil
end, 10), "fixture server did not start")
local real_system = vim.system
local manager_calls = 0
local real_mode = vim.env.PACKAGE_INFO_REAL_MANAGER or (vim.env.PACKAGE_INFO_REAL_YARN == "1" and "yarn")
local manager = real_mode == "yarn1" and "yarn" or real_mode or "yarn"
local config = {
  npmRegistryServer = url .. "/public",
  enableStrictSsl = true,
  npmScopes = { private = { npmRegistryServer = url .. "/private", npmAuthToken = "FIXTURE_TOKEN" } },
}
vim.system = function(command, options, callback)
  if command[1] ~= manager then
    return real_system(command, options, callback)
  end
  manager_calls = manager_calls + 1
  if real_mode then
    return real_system(command, options, callback)
  end
  local cancelled = false
  vim.schedule(function()
    local stdout
    if command[2] == "--version" then
      stdout = "4.18.0"
    elseif command[3] == "get" then
      stdout = vim.json.encode(config[command[4]] or vim.NIL)
    else
      stdout = vim.json.encode({ key = "npmRegistryServer", effective = config.npmRegistryServer })
        .. "\n"
        .. vim.json.encode({ key = "enableStrictSsl", effective = true })
        .. "\n"
        .. vim.json.encode({ key = "unsafeHttpWhitelist", effective = { "127.0.0.1" } })
      for _, field in ipairs({ "npmAuthToken", "npmAuthIdent", "npmScopes", "npmRegistries", "networkSettings" }) do
        stdout = stdout
          .. "\n"
          .. vim.json.encode({ key = field, source = field == "npmScopes" and "fixture.yml" or "<default>" })
      end
    end
    callback(cancelled and { code = 143, stdout = "", stderr = "" } or { code = 0, stdout = stdout, stderr = "" })
  end)
  return {
    kill = function()
      cancelled = true
    end,
  }
end
local info = require("package_info")
info.setup()
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local function write_config()
  if not real_mode or real_mode == "yarn" then
    local native_config = vim.deepcopy(config)
    native_config.nodeLinker = "node-modules"
    native_config.unsafeHttpWhitelist = { "127.0.0.1" }
    vim.fn.writefile({ vim.json.encode(native_config) }, root .. "/.yarnrc.yml")
  elseif real_mode then
    vim.fn.writefile({
      "registry=" .. url .. "/public/",
      "@private:registry=" .. url .. "/private/",
      url:gsub("^http:", "") .. "/private/:_authToken=" .. config.npmScopes.private.npmAuthToken,
    }, root .. "/.npmrc")
    if real_mode == "yarn1" then
      vim.fn.writefile({ 'registry "' .. url .. '/public/"' }, root .. "/.yarnrc")
    end
  end
end
local function fixture()
  local data = {
    packageManager = ({ npm = "npm@11.19.0", pnpm = "pnpm@10.23.0", yarn1 = "yarn@1.22.22" })[real_mode]
      or "yarn@4.18.0",
    dependencies = { good = "^1", slow = "^1", ["@private/good"] = "^1", missing = "^1" },
    devDependencies = { good = "^2" },
  }
  vim.fn.writefile({ vim.json.encode(data) }, root .. "/package.json")
  write_config()
  for name in pairs(data.dependencies) do
    vim.fn.mkdir(root .. "/node_modules/" .. name, "p")
    vim.fn.writefile(
      { vim.json.encode({ name = name, version = "1.0.0" }) },
      root .. "/node_modules/" .. name .. "/package.json"
    )
  end
  vim.cmd.edit(root .. "/package.json")
  return vim.api.nvim_get_current_buf()
end
local function settle(buf)
  assert(
    vim.wait(10000, function()
      local state = info.buffers[buf]
      if not state or not state.context then
        return false
      end
      for _, dep in ipairs(state.context.dependencies) do
        if dep.target and not dep.result and not dep.error then
          return false
        end
      end
      return state.network_ticket == nil
    end, 10),
    "network test timed out"
  )
end
local buf = fixture()
assert(
  vim.wait(5000, function()
    local s = info.buffers[buf]
    return s and s.context ~= nil
  end, 10),
  "inspection missing"
)
assert(#vim.api.nvim_buf_get_extmarks(buf, info.namespace, 0, -1, {}) > 0, "installed versions waited for network")
settle(buf)
local state = info.buffers[buf]
assert(state.backend == "parallel registry")
local expected_calls = real_mode == "npm" and 1 or (real_mode == "pnpm" or real_mode == "yarn1") and 2 or 3
assert(manager_calls == expected_calls, "default settings launched unnecessary manager config readers")
for _, dep in ipairs(state.context.dependencies) do
  if dep.name == "missing" then
    assert(dep.error_kind == "not_found" and not dep.error:find("SECRET"))
  else
    assert(dep.result ~= nil, dep.error)
    if dep.section == "dependencies" then
      assert(dep.result.wanted == "1.2.0")
    else
      assert(dep.result.wanted == "2.0.0")
    end
  end
end
local calls = manager_calls
info.refresh(buf)
settle(buf)
assert(manager_calls == calls, "repeat check launched another manager")
for _, dep in ipairs(info.buffers[buf].context.dependencies) do
  assert(dep.cached)
end
-- Changing a range must recompute wanted without fetching all metadata or reading the manager config again.
local data = vim.json.decode(table.concat(vim.fn.readfile(root .. "/package.json"), "\n"))
data.dependencies.good = "^2"
vim.fn.writefile({ vim.json.encode(data) }, root .. "/package.json")
vim.cmd.edit({ args = { root .. "/package.json" }, bang = true })
info.refresh(buf)
settle(buf)
assert(manager_calls == calls, "a range edit invalidated the manager configuration")
for _, dep in ipairs(info.buffers[buf].context.dependencies) do
  assert(dep.cached, "a range edit discarded registry metadata")
  if dep.name == "good" then
    assert(dep.result.wanted == "2.0.0", "cached metadata retained the previous comparison")
  end
end
-- Updating credentials must recreate the client and must not reuse successful metadata under the old token.
local fingerprint = info.buffers[buf].context.registry_fingerprint
config.npmScopes.private.npmAuthToken = "INVALID_FIXTURE_TOKEN"
write_config()
info.refresh(buf)
settle(buf)
state = info.buffers[buf]
assert(state.context.registry_fingerprint ~= fingerprint, "saved auth configuration was ignored")
assert(state.error == "Registry authentication failed", "old credentials or cached metadata hid the new auth error")
for _, dep in ipairs(state.context.dependencies) do
  if dep.name == "@private/good" then
    assert(dep.error_kind == "auth" and dep.result == nil and not dep.cached)
    assert(
      not dep.error:find("FIXTURE_TOKEN") and not dep.error:find("SYNTHETIC_SECRET"),
      "raw credentials/error leaked"
    )
  elseif dep.name ~= "missing" then
    assert(dep.result ~= nil, "private auth failure removed successful public dependencies")
  end
end
calls = manager_calls
info.refresh(buf)
settle(buf)
assert(manager_calls == calls, "auth backoff reloaded manager configuration")
for _, dep in ipairs(info.buffers[buf].context.dependencies) do
  assert(dep.cached, "auth backoff sent another registry request")
end
config.npmScopes.private.npmAuthToken = "FIXTURE_TOKEN"
write_config()
info.refresh(buf)
settle(buf)
assert(not info.buffers[buf].error, "restoring credentials did not invalidate auth backoff")
-- Streaming callbacks after an edit cannot restore old annotations.
info.refresh(buf, true)
assert(
  vim.wait(5000, function()
    return info.buffers[buf].network_ticket ~= nil
  end, 10),
  "network request missing"
)
local ticket = info.buffers[buf].network_ticket
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "{" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
assert(ticket.cancelled and not helper.pending[ticket.id])
vim.wait(500)
assert(#vim.api.nvim_buf_get_extmarks(buf, info.namespace, 0, -1, {}) == 0, "cancelled results reappeared")
vim.bo[buf].modified = false
vim.cmd.edit({ args = { root .. "/package.json" }, bang = true })
info.refresh(buf)
settle(buf)
-- A helper restart must recreate clients and read the persistent metadata cache.
vim.fn.jobstop(helper.job)
assert(vim.wait(3000, function()
  return helper.state == "failed"
end, 10))
helper.retry()
info.refresh(buf)
settle(buf)
assert(info.buffers[buf].backend == "parallel registry", "restarted helper kept an obsolete client")
for _, dep in ipairs(info.buffers[buf].context.dependencies) do
  if dep.name ~= "missing" then
    assert(dep.cached, "helper restart discarded persisted version metadata")
  end
end
info.refresh(buf, true)
settle(buf)
for _, dep in ipairs(info.buffers[buf].context.dependencies) do
  assert(not dep.cached, "forced refresh reused persisted registry metadata")
end
helper.stop()
vim.fn.jobstop(server)
vim.system = real_system
vim.fn.delete(root, "rf")
print("package-info: parallel Neovim integration tests passed")
vim.cmd("qa!")
