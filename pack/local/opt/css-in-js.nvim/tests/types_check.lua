---Run LuaLS diagnostics against this plugin, including test fixtures, with native Neovim API types.
local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
local server = vim.env.LUA_LS or vim.fn.exepath("lua-language-server")
if server == "" then
  server = vim.fn.stdpath("data") .. "/mason/bin/lua-language-server"
end
assert(vim.fn.executable(server) == 1, "Lua Language Server is required; set LUA_LS to its executable")
local runtime = assert(vim.env.VIMRUNTIME)
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
local config_path = temporary .. "/config.json"
local settings = {
  runtime = { version = "LuaJIT", path = { "lua/?.lua", "lua/?/init.lua", "tests/?.lua" } },
  workspace = { library = { runtime .. "/lua" }, checkThirdParty = false },
  diagnostics = { globals = { "vim" } },
}
vim.fn.writefile({ vim.json.encode(settings) }, config_path)
local result = vim
  .system({
    server,
    "--check=" .. root,
    "--configpath=" .. config_path,
    "--logpath=" .. temporary .. "/logs",
    "--metapath=" .. temporary .. "/meta",
    "--checklevel=Warning",
  }, { text = true })
  :wait()
vim.fn.delete(temporary, "rf")
if result.stdout and result.stdout ~= "" then
  io.stdout:write(result.stdout)
end
if result.stderr and result.stderr ~= "" then
  io.stderr:write(result.stderr)
end
assert(result.code == 0, "css-in-js LuaLS type check failed")
