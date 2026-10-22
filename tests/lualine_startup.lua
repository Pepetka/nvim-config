-- Run: NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -n -l tests/lualine_startup.lua
local root = vim.fn.getcwd()
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary .. "/theme", "p")
assert(vim.uv.fs_symlink(root, temporary .. "/nvim", { dir = true }))
vim.fn.writefile({ "sample startup row" }, temporary .. "/startup.txt")
local child, buffer

local function check(mode)
  vim.fn.writefile({ mode }, temporary .. "/theme/mode")
  buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buffer)
  local chunks, exit_code = {}, nil
  child = vim.fn.jobstart({
    vim.v.progpath,
    "-u",
    root .. "/init.lua",
    "-i",
    "NONE",
    "-n",
    "--cmd",
    "lua package.loaded['configs.windsurf'] = true",
    temporary .. "/startup.txt",
  }, {
    term = true,
    env = {
      XDG_CONFIG_HOME = temporary,
      XDG_CACHE_HOME = temporary .. "/cache",
      XDG_STATE_HOME = temporary .. "/state",
      NVIM_LOG_FILE = "/dev/null",
      TERM = "tmux-256color",
    },
    on_stdout = function(_, lines)
      chunks[#chunks + 1] = table.concat(lines, "\n")
    end,
    on_exit = function(_, code)
      exit_code = code
    end,
  })
  assert(child > 0, "Could not start the native TUI")
  vim.fn.jobresize(child, 120, 40)
  local ready = vim.wait(10000, function()
    local output = table.concat(chunks)
    return exit_code ~= nil
      or (output:find("sample startup row", 1, true) ~= nil and output:find("NORMAL", 1, true) ~= nil)
  end, 5)
  assert(ready and exit_code == nil, "Native TUI did not render the file and lualine")
  local output = table.concat(chunks)
  assert(
    not output:find("\27[48;2;0;0;0m", 1, true),
    "Native TUI painted a black startup band before the file appeared (" .. mode .. ")"
  )
  vim.fn.jobstop(child)
  vim.fn.jobwait({ child }, 1000)
  child = nil
  vim.api.nvim_buf_delete(buffer, { force = true })
  buffer = nil
  print("Lualine native TUI startup passed (" .. mode .. "): no black band before the first file frame")
end

local ok, err = xpcall(function()
  check("dark")
  check("light")
end, debug.traceback)
if child then
  vim.fn.jobstop(child)
  vim.fn.jobwait({ child }, 1000)
end
if buffer and vim.api.nvim_buf_is_valid(buffer) then
  vim.api.nvim_buf_delete(buffer, { force = true })
end
vim.fn.delete(temporary, "rf")
assert(ok, err)
