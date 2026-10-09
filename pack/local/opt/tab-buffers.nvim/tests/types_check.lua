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
local libraries = { runtime .. "/lua" }
local seen = {}
local paths = vim.o.packpath .. "," .. vim.fn.stdpath("data") .. "/site"
for _, name in ipairs({ "fzf-lua", "diffview-plus.nvim", "diffview.nvim", "nvim-web-devicons" }) do
  for _, kind in ipairs({ "opt", "start" }) do
    for _, directory in ipairs(vim.fn.globpath(paths, "pack/*/" .. kind .. "/" .. name .. "/lua", false, true)) do
      if not seen[directory] then
        libraries[#libraries + 1] = directory
        seen[directory] = true
      end
    end
  end
end
print("Checking all plugin modules and tests with " .. (#libraries - 1) .. " installed dependency libraries")
local settings = {
  runtime = { version = "LuaJIT", path = { "lua/?.lua", "lua/?/init.lua", "tests/?.lua" } },
  workspace = { library = libraries, checkThirdParty = false },
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
assert(result.code == 0, "tab-buffers LuaLS type check failed")
