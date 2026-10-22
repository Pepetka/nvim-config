local root = vim.fn.getcwd()
local server = vim.env.LUA_LS or vim.fn.exepath("lua-language-server")
if server == "" then
  server = vim.fn.stdpath("data") .. "/mason/bin/lua-language-server"
end
assert(vim.fn.executable(server) == 1, "Lua Language Server is required; set LUA_LS to its executable")

local settings = dofile(root .. "/lsp/lua_ls.lua").settings.Lua
local libraries = { assert(vim.env.VIMRUNTIME) .. "/lua" }
local paths = vim.o.packpath .. "," .. vim.fn.stdpath("data") .. "/site"
local seen = {}
for _, kind in ipairs({ "opt", "start" }) do
  for _, directory in ipairs(vim.fn.globpath(paths, "pack/*/" .. kind .. "/*/lua", false, true)) do
    if not vim.fs.relpath(root, directory) and not seen[directory] then
      libraries[#libraries + 1] = directory
      seen[directory] = true
    end
  end
end
settings.workspace.library = libraries
settings.workspace.maxPreload = 10000

local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
local config_path = temporary .. "/config.json"
vim.fn.writefile({ vim.json.encode(settings) }, config_path)
local result = vim
  .system({
    server,
    "--check=" .. root,
    "--configpath=" .. config_path,
    "--logpath=" .. temporary .. "/logs",
    "--metapath=" .. temporary .. "/meta",
    "--checklevel=Information",
  }, { text = true })
  :wait()
vim.fn.delete(temporary, "rf")
if result.code ~= 0 then
  for _, output in ipairs({ result.stdout or "", result.stderr or "" }) do
    if output ~= "" then
      io.stdout:write(output)
    end
  end
end
assert(result.code == 0, "Config LuaLS type check failed")
print("Config LuaLS type check passed")
