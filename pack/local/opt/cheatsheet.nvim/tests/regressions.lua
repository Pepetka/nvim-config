local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path
vim.o.swapfile = false
vim.o.columns, vim.o.lines = 120, 40
vim.g.mapleader = " "
local t = require("support")
local api = vim.api
local plugin = require("cheatsheet")
plugin.setup({
  modes = { "n", "i" },
  group_rules = { { pattern = "^Test:", group = "tests", icon = "ICON " } },
  exclude = { single_word = false, no_desc = false, newline = false },
  icons = { enabled = false },
})
local source = api.nvim_get_current_buf()
vim.keymap.set("n", "zz", function() end, { buffer = source, desc = "Test: Local normal" })
vim.keymap.set("i", "zz", function() end, { buffer = source, desc = "Test: Local insert" })
vim.keymap.set("n", "zy", function() end, { buffer = source, desc = "Rename symbol" })
vim.keymap.set("n", "zx", function() end, { buffer = source })
vim.keymap.set("n", "zw", function() end, { buffer = source, desc = "Test: First\nsecond line" })

---@return string
local function text()
  return table.concat(api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

---@param value string
---@return nil
local function contains(value)
  assert(text():find(value, 1, true), "missing " .. value)
end

t.test("allowed multiline descriptions render safely", function()
  local ok, err = pcall(plugin.show, "n")
  vim.keymap.del("n", "zw", { buffer = source })
  assert(ok, err)
  contains("First second line")
end)

-- Keep the remaining failures independent of the old multiline-rendering crash.
t.test("ordinary descriptions retain their first word", function()
  plugin.hide()
  plugin.show("n")
  contains("Rename symbol")
end)
t.test("no_desc=false includes mappings without descriptions", function()
  contains("zx")
end)
t.test("icons.enabled=false hides icons", function()
  assert(not text():find("ICON", 1, true))
end)
t.test("mode switching retains source-buffer mappings", function()
  plugin.next_mode()
  contains("Local insert")
end)
t.test("resize retains window, buffer and source mappings", function()
  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  api.nvim_exec_autocmds("VimResized", {})
  vim.wait(100, function()
    return api.nvim_win_get_width(win) == 96
  end)
  t.equal(api.nvim_get_current_win(), win)
  t.equal(api.nvim_get_current_buf(), buf)
  contains("Local insert")
end)
t.test("unrelated cheatsheet filetype cannot reset ownership", function()
  local owned = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "cheatsheet"
  vim.bo[buf].bufhidden = "wipe"
  local win = api.nvim_open_win(buf, false, { relative = "editor", row = 0, col = 0, width = 10, height = 3 })
  api.nvim_win_close(win, true)
  t.equal(vim.g.cheatsheet_displayed, true)
  plugin.hide()
  assert(not api.nvim_win_is_valid(owned))
end)
plugin.hide()
t.run("cheatsheet regressions")
