local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
vim.o.swapfile = false
local api = vim.api
local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end

vim.g.mapleader = " "
vim.o.columns, vim.o.lines = 120, 40
local plugin = require("cheatsheet")
local parser = require("cheatsheet.parser")
plugin.setup({
  modes = { "n", "i" },
  group_rules = { { pattern = "^Test:", group = "tests", icon = "" } },
  sort_groups = { "tests" },
  exclude = { single_word = false },
})
assert(not package.loaded["utils.map_opts"], "plugin must not load host helpers")
equal(vim.fn.exists(":Cheatsheet"), 2)
equal(vim.fn.maparg("<leader>ch", "n"), "")
vim.keymap.set("n", "<leader>zz", function() end, { desc = "Test: Global action" })
vim.keymap.set("n", "<leader>zz", function() end, { buffer = 0, desc = "Test: Local action" })
local mappings = parser.collect("n")
local matches = vim.tbl_filter(function(item)
  return item.lhs == " zz"
end, mappings)
equal(#matches, 1)
equal(matches[1].desc, "Test: Local action")
local groups = parser.parse("n")
equal(groups[1].name, "tests")
equal(groups[1].mappings[1].lhs, "<leader> + zz")
equal(groups[1].mappings[1].desc, "Local action")
local source = api.nvim_get_current_win()
vim.cmd.Cheatsheet()
local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
equal(vim.bo[buf].filetype, "cheatsheet")
assert(api.nvim_win_get_config(win).relative == "editor")
assert(table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("Local action", 1, true))
assert(#api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("cheatsheet"), 0, -1, {}) > 0)
plugin.next_mode()
assert(api.nvim_buf_get_lines(buf, 0, -1, false)[2]:find("[i]", 1, true))
plugin.prev_mode()
api.nvim_exec_autocmds("ColorScheme", { pattern = "test" })
equal(api.nvim_get_hl(0, { name = "CheatsheetTitle" }).link, "FloatTitle")
vim.o.columns = 100
api.nvim_exec_autocmds("VimResized", {})
win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
equal(api.nvim_win_get_width(win), 80)
equal(vim.bo[buf].filetype, "cheatsheet")
plugin.hide()
equal(api.nvim_get_current_win(), source)
assert(not api.nvim_win_is_valid(win))
assert(not api.nvim_buf_is_valid(buf), "closing must dispose the scratch buffer")
plugin.show()
win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
api.nvim_win_close(win, true)
assert(not vim.g.cheatsheet_displayed)
assert(not api.nvim_buf_is_valid(buf), "external window closure must dispose the scratch buffer")
plugin.toggle()
plugin.toggle()
print("cheatsheet: Neovim tests passed")
