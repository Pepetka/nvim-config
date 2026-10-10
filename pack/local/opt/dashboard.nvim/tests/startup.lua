local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
package.path = root .. "/tests/?.lua;" .. package.path
local t = require("support")
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
vim.fn.writefile({ "file content" }, temporary .. "/file.txt")

---@param arguments string[]
---@param environment? table<string, string>
---@return string
local function embedded(arguments, environment)
  local command = { vim.v.progpath, "--embed", "-u", root .. "/tests/startup_init.lua", "-i", "NONE", "-n" }
  vim.list_extend(command, arguments)
  local child = vim.fn.jobstart(command, {
    rpc = true,
    env = vim.tbl_extend(
      "force",
      { XDG_STATE_HOME = temporary .. "/state", XDG_CACHE_HOME = temporary .. "/cache" },
      environment or {}
    ),
  })
  assert(child > 0)
  local ok, result = pcall(function()
    vim.rpcrequest(child, "nvim_ui_attach", 120, 50, { rgb = true })
    return vim.rpcrequest(child, "nvim_exec_lua", "vim.wait(40); return vim.bo.filetype", {})
  end)
  vim.fn.jobstop(child)
  vim.fn.jobwait({ child }, 1000)
  assert(ok, result)
  ---@cast result string
  return result
end

t.test("empty interactive startup opens dashboard", function()
  t.equal(embedded({}), "dashboard")
end)

t.test("file argument preserves the file buffer", function()
  assert(embedded({ temporary .. "/file.txt" }) ~= "dashboard")
end)

t.test("directory argument does not open dashboard", function()
  assert(embedded({ temporary }) ~= "dashboard")
end)

t.test("autostart false preserves the empty buffer", function()
  assert(embedded({}, { DASHBOARD_TEST_AUTOSTART = "0" }) ~= "dashboard")
end)

t.test("modified startup content is never replaced", function()
  assert(embedded({}, { DASHBOARD_TEST_MODIFIED = "1" }) ~= "dashboard")
end)

---@param arguments string[]
---@param input? string
---@return nil
local function headless(arguments, input)
  local command = { vim.v.progpath, "--headless", "-u", root .. "/tests/startup_init.lua", "-i", "NONE", "-n" }
  vim.list_extend(command, arguments)
  vim.list_extend(
    command,
    { "-c", "lua assert(vim.bo.filetype ~= 'dashboard'); assert(vim.fn.exists(':Dashboard') == 2)", "-c", "qa!" }
  )
  local result =
    vim.system(command, { text = true, stdin = input, env = { XDG_STATE_HOME = temporary .. "/state" } }):wait(3000)
  assert(result.code == 0, result.stderr)
end

t.test("headless startup never opens dashboard", function()
  headless({})
end)
t.test("stdin startup is preserved", function()
  headless({ "-" }, "stdin content\n")
end)

local ok, err = pcall(t.run, "Dashboard startup")
vim.fn.delete(temporary, "rf")
assert(ok, err)
