local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.env.PACKAGE_INFO_TEST_PARSER_RTP or vim.fn.stdpath("data") .. "/site")
package.path = root .. "/tests/?.lua;" .. package.path
local t = require("support")
local factory = require("package_info.controller")
local nvim = require("package_info.integrations.nvim")
local treesitter = require("package_info.integrations.treesitter")

t.test("automatic enter/save checks can be disabled independently while commands remain available", function()
  local instance = factory.new(nvim.new())
  instance.setup({ auto_refresh = { on_enter = false, on_save = true } })
  local calls = 0
  ---@diagnostic disable-next-line: duplicate-set-field
  instance.refresh = function()
    calls = calls + 1
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "/tmp/package-info-auto-options/package.json")
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
  t.equal(calls, 0)
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
  t.equal(calls, 1)
  instance.setup({ auto_refresh = false })
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
  t.equal(calls, 1)
  vim.cmd.PackageInfoRefresh()
  t.equal(calls, 2)
  instance.teardown()
  vim.api.nvim_buf_delete(buf, { force = true })
end)
t.test("native display forwards annotation position and floating window settings", function()
  local adapter = nvim.new()
  local instance = factory.new(adapter)
  instance.setup({
    display = {
      virt_text_pos = "right_align",
      float = { border = "single", focusable = false, max_width = 40, max_height = 5 },
    },
  })
  local buf = vim.api.nvim_create_buf(false, true)
  adapter.render(buf, { [0] = { { "test", "Comment" } } })
  local marks = vim.api.nvim_buf_get_extmarks(buf, adapter.namespace, 0, -1, { details = true })
  t.equal(marks[1][4].virt_text_pos, "right_align")
  local preview = vim.lsp.util.open_floating_preview
  ---@type vim.lsp.util.open_floating_preview.Opts?
  local captured
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.lsp.util.open_floating_preview = function(_, _, options)
    captured = options
    return 0, 0
  end
  local ok, err = pcall(instance.info)
  vim.lsp.util.open_floating_preview = preview
  assert(ok, err)
  t.equal(captured, { border = "single", focusable = false, max_width = 40, max_height = 5 })
  instance.teardown()
  vim.api.nvim_buf_delete(buf, { force = true })
end)
t.test("native helper startup forwards HTTP and cache policies", function()
  local adapter = require("package_info.integrations.runtime").new()
  adapter.configure(require("package_info.core.config").normalize({
    timeouts = { registry = 123 },
    concurrency = { http = 3 },
    cache = { disk = false, ttl = 42 },
  }))
  local start = vim.fn.jobstart
  ---@type string[]?
  local command
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.jobstart = function(value)
    command = value
    return 1
  end
  local ok, err = pcall(adapter.start, "/runtime", function() end, function() end)
  vim.fn.jobstart = start
  assert(ok, err)
  t.equal(assert(command)[3], "--options")
  local values = vim.json.decode(assert(command)[4])
  t.equal(values.timeout, 123)
  t.equal(values.globalLimit, 3)
  t.equal(values.ttl, 42)
  t.equal(values.disk, false)
end)

t.test("native bootstrap ignores a process response after stop", function()
  local runtime = require("package_info.integrations.runtime").new()
  local system = vim.system
  ---@type fun(result: vim.SystemCompleted)?
  local response
  local killed = false
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(_, _, callback)
    response = callback
    return {
      kill = function()
        killed = true
      end,
    }
  end
  local calls = 0
  local ok, err = pcall(function()
    runtime.bootstrap("/missing-source", "/unused-runtime", function()
      calls = calls + 1
    end)
    runtime.stop()
    assert(response)({ code = 0, signal = 0, stdout = "v24.0.0", stderr = "" })
    vim.wait(50, function()
      return calls > 0
    end)
    t.equal(calls, 0)
    assert(killed)
  end)
  vim.system = system
  assert(ok, err)
end)

t.test("native parsing rejects duplicate keys in nested objects", function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '{"dependencies":{"a":"^1"},"overrides":{"b":"1","b":"2"}}' })
  t.equal(treesitter.parse(buf), nil)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '{"dependencies":{"a":"^1"},"devDependencies":{"a":"^2"}}' })
  local parsed = assert(treesitter.parse(buf))
  t.equal(parsed.lines, { ["dependencies:a"] = 0, ["devDependencies:a"] = 0 })
  vim.api.nvim_buf_delete(buf, { force = true })
end)
t.test("setup clears overrides and installs one owned set of registrations", function()
  local adapter = nvim.new()
  local instance = factory.new(adapter)
  instance.setup({ managers = { ["/tmp/project"] = "yarn@4" } })
  instance.setup({ managers = {} })
  t.equal(instance.config.managers, {})
  assert(vim.api.nvim_get_commands({}).PackageInfo)
  vim.api.nvim_exec_autocmds("ColorScheme", {})
  t.equal(vim.api.nvim_get_hl(0, { name = "PackageInfoUpdate" }).link, "DiagnosticInfo")
  instance.teardown()
  instance.teardown()
  assert(not vim.api.nvim_get_commands({}).PackageInfo)
end)
t.test("teardown respects foreign commands and other adapter owners", function()
  local a, b = factory.new(nvim.new()), factory.new(nvim.new())
  a.setup()
  b.setup()
  a.teardown()
  assert(vim.api.nvim_get_commands({}).PackageInfo)
  vim.api.nvim_create_user_command("PackageInfoStatus", function() end, { force = true })
  local foreign = vim.api.nvim_get_commands({}).PackageInfoStatus.definition
  b.teardown()
  t.equal(vim.api.nvim_get_commands({}).PackageInfoStatus.definition, foreign)
  vim.api.nvim_del_user_command("PackageInfoStatus")
end)
t.test("teardown before setup and after foreign replacement preserves Vimscript commands", function()
  local instance = factory.new(nvim.new())
  vim.api.nvim_create_user_command("PackageInfo", "echo 1", {})
  instance.teardown()
  t.equal(vim.api.nvim_get_commands({}).PackageInfo.definition, "echo 1")
  instance.setup()
  vim.api.nvim_create_user_command("PackageInfo", "echo 2", { force = true })
  instance.teardown()
  instance.teardown()
  t.equal(vim.api.nvim_get_commands({}).PackageInfo.definition, "echo 2")
  vim.api.nvim_del_user_command("PackageInfo")
end)
t.test("partial registration failure rolls back and permits a setup retry", function()
  local instance = factory.new(nvim.new())
  local create = vim.api.nvim_create_user_command
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_create_user_command = function()
    error("registration failure")
  end
  local notify = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function() end
  instance.setup()
  vim.api.nvim_create_user_command = create
  vim.notify = notify
  assert(not instance.active)
  instance.setup()
  assert(instance.active)
  instance.teardown()
end)
t.test("public facade exposes only supported operations and restores after teardown", function()
  local public = require("package_info")
  assert(type(public.setup) == "function" and type(public.teardown) == "function")
  assert(public.buffers == nil and public.cache == nil)
  public.setup()
  public.teardown()
  public.setup()
  public.teardown()
end)
t.run("package-info native adapters")
