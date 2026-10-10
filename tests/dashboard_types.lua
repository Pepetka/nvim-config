-- Check the dashboard's host configuration as well as its local plugin contracts.
local root = vim.fn.getcwd()
local server = vim.env.LUA_LS or vim.fn.exepath("lua-language-server")
if server == "" then
  server = vim.fn.stdpath("data") .. "/mason/bin/lua-language-server"
end
assert(vim.fn.executable(server) == 1, "Lua Language Server is required; set LUA_LS to its executable")
local temporary = vim.fn.tempname()
local workspace = temporary .. "/workspace"
local files = {
  "lua/configs/dashboard.lua",
  "lua/utils/dashboard.lua",
  "lua/utils/pad.lua",
  "lua/utils/colors.lua",
  "lua/utils/map_opts.lua",
}
for _, path in ipairs(files) do
  local target = workspace .. "/" .. path
  vim.fn.mkdir(vim.fs.dirname(target), "p")
  vim.fn.writefile(vim.fn.readfile(root .. "/" .. path), target)
end
local settings = {
  runtime = { version = "LuaJIT", path = { "lua/?.lua", "lua/?/init.lua" } },
  workspace = {
    library = { assert(vim.env.VIMRUNTIME) .. "/lua", root .. "/pack/local/opt/dashboard.nvim/lua" },
    checkThirdParty = false,
  },
  diagnostics = { globals = { "vim" } },
}
local config_path = temporary .. "/config.json"
vim.fn.writefile({ vim.json.encode(settings) }, config_path)
local result = vim
  .system({
    server,
    "--check=" .. workspace,
    "--configpath=" .. config_path,
    "--logpath=" .. temporary .. "/logs",
    "--metapath=" .. temporary .. "/meta",
    "--checklevel=Warning",
  }, { text = true })
  :wait()
vim.fn.delete(temporary, "rf")
for _, output in ipairs({ result.stdout or "", result.stderr or "" }) do
  if output ~= "" then
    io.stdout:write(output)
  end
end
assert(result.code == 0, "dashboard host LuaLS type check failed")
