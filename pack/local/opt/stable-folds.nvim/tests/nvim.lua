local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
vim.o.swapfile = false
local api = vim.api
local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end
-- Use installed parsers and bundled queries without loading the host config.
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/site")
vim.opt.packpath:append(vim.fn.stdpath("data") .. "/site")
vim.cmd.packadd("nvim-treesitter")

local folds = require("stable_folds")
folds.setup()
folds.setup()
equal(#api.nvim_get_autocmds({ group = "SynchronousFolds" }), 5)
vim.wo.foldminlines = 1
vim.wo.foldnestmax = 1
vim.wo.foldlevel = 99
folds.attach()
equal(vim.wo.foldexpr, folds.foldexpr)
local buf = api.nvim_get_current_buf()
vim.bo[buf].filetype = "lua"
local first = { "local function first()", "  local a = 1", "  return a", "end" }
local second = { "local function second()", "  local b = 2", "  return b", "end" }
local lines = vim.list_extend(vim.deepcopy(first), { "" })
vim.list_extend(lines, second)
api.nvim_buf_set_lines(buf, 0, -1, false, lines)
equal(folds.expr(1), ">1")
equal(folds.expr(2), "1")
equal(folds.expr(5), "0")
equal(folds.expr(6), ">1")
vim.cmd("1foldclose")
equal(vim.fn.foldclosed(1), 1)
api.nvim_buf_set_lines(buf, 0, 0, false, { "-- inserted above a closed fold", "" })
api.nvim_exec_autocmds("TextChanged", { buffer = buf })
equal(folds.expr(1), "0")
equal(folds.expr(3), ">1")
equal(vim.fn.foldclosed(3), 3)
equal(vim.fn.foldclosed(8), -1)
-- A full formatter replacement keeps an unchanged closed header.
lines = api.nvim_buf_get_lines(buf, 0, -1, false)
lines[4] = "  local a = 42"
api.nvim_buf_set_lines(buf, 0, -1, false, lines)
api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
equal(vim.fn.foldclosed(3), 3)
-- New folds should not inherit a closed neighbour's state.
api.nvim_buf_set_lines(buf, 0, 0, false, vim.list_extend(vim.deepcopy(second), { "" }))
api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
equal(folds.expr(1), ">1")
equal(vim.fn.foldclosed(1), -1)
equal(vim.fn.foldclosed(8), 8)
-- No parser, special buffers and caller filters safely produce zero levels.
vim.bo[buf].filetype = "missing_parser_for_test"
equal(folds.expr(1), "0")
vim.bo[buf].filetype = "lua"
folds.setup({
  filter = function()
    return false
  end,
})
equal(folds.expr(1), "0")
folds.setup()
vim.bo[buf].buftype = "nofile"
equal(folds.expr(1), "0")
vim.bo[buf].buftype = ""
api.nvim_exec_autocmds("BufUnload", { buffer = buf })
equal(#api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("StableFoldStarts"), 0, -1, {}), 0)
print("stable-folds: Neovim tests passed")
