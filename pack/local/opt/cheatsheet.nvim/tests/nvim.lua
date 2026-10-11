local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path
vim.o.swapfile = false
vim.o.columns, vim.o.lines = 120, 40
vim.g.mapleader = " "
local t = require("support")
local api = vim.api
local plugin = require("cheatsheet")
local base_win = api.nvim_get_current_win()
local notifications = {}
local original_notify = vim.notify
-- Intercept notifications for assertions, restoring the original after the suite.
---@param message string
---@param level? integer
---@return nil
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(message, level)
  notifications[#notifications + 1] = { message = message, level = level }
end

---@param buf? integer
---@return string
local function text(buf)
  return table.concat(api.nvim_buf_get_lines(buf or 0, 0, -1, false), "\n")
end
---@param value string
---@param buf? integer
---@return nil
local function contains(value, buf)
  assert(text(buf):find(value, 1, true), "missing " .. value)
end
---@return integer win, integer buf
local function float()
  return api.nvim_get_current_win(), api.nvim_get_current_buf()
end
---@param keys string
---@return nil
local function press(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end
---@param name string
---@param fn fun(source: integer): nil
---@return nil
local function test(name, fn)
  t.test(name, function()
    local before_notifications = #notifications
    plugin.hide()
    api.nvim_set_current_win(base_win)
    local source = api.nvim_create_buf(true, false)
    api.nvim_win_set_buf(base_win, source)
    vim.keymap.set("n", "<leader>zz", function() end, { buffer = source, desc = "Test: Local action" })
    vim.keymap.set("i", "<leader>zz", function() end, { buffer = source, desc = "Test: Local insert" })
    local ok, err = xpcall(function()
      fn(source)
    end, debug.traceback)
    plugin.hide()
    if api.nvim_buf_is_valid(source) then
      api.nvim_buf_delete(source, { force = true })
    end
    assert(ok, err)
    t.equal(#notifications, before_notifications, "unexpected notifications")
  end)
end

t.test("setup is required, registers the command once and keeps host mappings outside the plugin", function()
  plugin.show()
  t.equal(notifications[1].level, vim.log.levels.ERROR)
  ---@type CheatsheetConfigPartial
  local options = {
    modes = { "n", "i" },
    group_rules = { { pattern = "^Test:", group = "tests", icon = "" } },
    sort_groups = { "tests" },
    exclude = { single_word = false },
  }
  plugin.setup(options)
  assert(not package.loaded["utils.map_opts"], "plugin must not load host helpers")
  t.equal(vim.fn.exists(":Cheatsheet"), 2)
  t.equal(vim.fn.maparg("<leader>ch", "n"), "")
  local count = #api.nvim_get_autocmds({ group = "Cheatsheet" })
  plugin.show()
  local win = api.nvim_get_current_win()
  plugin.setup({ modes = { "t" } })
  assert(not api.nvim_win_is_valid(win), "reconfiguration must close the open browser")
  t.equal(#api.nvim_get_autocmds({ group = "Cheatsheet" }), count)
  t.equal(vim.fn.exists(":Cheatsheet"), 2)
  t.equal(#notifications, 1)
  plugin.show()
  contains("[terminal]")
  plugin.hide()
  plugin.setup(options)
  vim.keymap.set("n", "<leader>zz", function() end, { desc = "Test: Global action" })
  vim.keymap.set("i", "<leader>zz", function() end, { desc = "Test: Global insert" })
end)

test("command renders local overrides in an unlisted read-only scratch float", function()
  vim.cmd.Cheatsheet()
  local win, buf = float()
  t.equal(vim.bo[buf].filetype, "cheatsheet")
  t.equal(vim.bo[buf].buftype, "nofile")
  t.equal(vim.bo[buf].bufhidden, "wipe")
  t.equal(vim.bo[buf].buflisted, false)
  t.equal(vim.bo[buf].modifiable, false)
  t.equal(vim.bo[buf].swapfile, false)
  t.equal(vim.wo[win].wrap, false)
  t.equal(api.nvim_win_get_config(win).relative, "editor")
  contains("<leader> + zz", buf)
  contains("Local action", buf)
  assert(not text(buf):find("Global action", 1, true))
end)

test("empty local description still overrides a described global mapping", function(source)
  vim.keymap.set("n", "<leader>zz", function() end, { buffer = source })
  plugin.show()
  assert(not text():find("Global action", 1, true))
  assert(not text():find("<leader> + zz", 1, true))
end)

test("repeated show reuses its resources; mode mappings retain source context", function()
  plugin.show()
  local win, buf = float()
  plugin.show()
  t.equal(float(), win)
  t.equal(api.nvim_get_current_buf(), buf)
  press("<Tab>")
  contains("[insert]")
  contains("Local insert")
  press("<S-Tab>")
  contains("[normal]")
  contains("Local action")
  t.equal(api.nvim_get_current_buf(), buf)
end)

test("buffer-local mappings have descriptions and both close keys work", function()
  for _, close in ipairs({ "q", "<Esc>" }) do
    plugin.show()
    local win, buf = float()
    for _, map in ipairs(api.nvim_buf_get_keymap(buf, "n")) do
      assert(map.desc and map.desc:find("Cheatsheet:", 1, true))
    end
    press(close)
    assert(not api.nvim_win_is_valid(win))
    assert(not api.nvim_buf_is_valid(buf))
    t.equal(plugin.is_open(), false)
  end
end)

test("Unicode extmarks use valid byte ranges and an empty icon leaves the name correctly highlighted", function(source)
  vim.keymap.set("n", "<leader>界", function() end, { buffer = source, desc = "Test: Unicode action" })
  plugin.show()
  local _, buf = float()
  contains("界", buf)
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  local group_row
  for row, line in ipairs(lines) do
    if line == "  tests" then
      group_row = row - 1
    end
  end
  assert(group_row)
  local marks = api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("cheatsheet"), 0, -1, { details = true })
  assert(#marks > 0)
  local named_group = false
  for _, mark in ipairs(marks) do
    local row, col, details = mark[2], mark[3], assert(mark[4])
    local end_col = assert(details.end_col)
    assert(details.end_row == row and end_col <= #lines[row + 1] and end_col > col)
    if row == group_row then
      t.equal(details.hl_group, "CheatsheetGroup")
      t.equal(lines[row + 1]:sub(col + 1, end_col), "tests")
      named_group = true
    end
  end
  assert(named_group)
end)

test("ColorScheme restores cleared highlight links and keeps host definitions", function()
  plugin.show()
  local expected = {
    CheatsheetTitle = "FloatTitle",
    CheatsheetGroup = "Title",
    CheatsheetGroupIcon = "Constant",
    CheatsheetKey = "Special",
    CheatsheetDesc = "NormalFloat",
    CheatsheetSeparator = "WinSeparator",
  }
  vim.cmd.highlight("clear")
  api.nvim_exec_autocmds("ColorScheme", { pattern = "test" })
  for name, link in pairs(expected) do
    t.equal(api.nvim_get_hl(0, { name = name }).link, link)
  end
  api.nvim_set_hl(0, "CheatsheetKey", { fg = "#ff0000" })
  api.nvim_set_hl(0, "CheatsheetDesc", { link = "Comment" })
  api.nvim_exec_autocmds("ColorScheme", { pattern = "test" })
  t.equal(api.nvim_get_hl(0, { name = "CheatsheetKey" }).fg, 0xff0000)
  t.equal(api.nvim_get_hl(0, { name = "CheatsheetDesc" }).link, "Comment")
  vim.cmd.highlight("clear")
  api.nvim_exec_autocmds("ColorScheme", { pattern = "test" })
end)

test("resize preserves IDs, mode, cursor and view", function()
  plugin.show("i")
  local win, buf = float()
  api.nvim_win_set_cursor(win, { 12, 0 })
  api.nvim_win_call(win, function()
    vim.fn.winrestview({ lnum = 12, topline = 5, leftcol = 4 })
  end)
  local before = api.nvim_win_call(win, vim.fn.winsaveview)
  vim.o.columns = 100
  for _ = 1, 3 do
    api.nvim_exec_autocmds("VimResized", {})
  end
  assert(vim.wait(200, function()
    return api.nvim_win_get_width(win) == 80
  end))
  t.equal(float(), win)
  t.equal(api.nvim_get_current_buf(), buf)
  local after = api.nvim_win_call(win, vim.fn.winsaveview)
  t.equal(after.lnum, before.lnum)
  t.equal(after.topline, before.topline)
  t.equal(after.leftcol, before.leftcol)
  contains("[insert]", buf)
  contains("Local insert", buf)
end)

test("resize and show do not take focus from another window", function()
  plugin.show()
  local win, buf = float()
  api.nvim_set_current_win(base_win)
  vim.o.columns = 90
  api.nvim_exec_autocmds("WinResized", {})
  assert(vim.wait(200, function()
    return api.nvim_win_get_width(win) == 72
  end))
  t.equal(api.nvim_get_current_win(), base_win)
  plugin.show("i")
  t.equal(api.nvim_get_current_win(), base_win)
  contains("Local insert", buf)
end)

test("hide restores source focus, wipes the buffer and can be repeated", function()
  plugin.show()
  local win, buf = float()
  plugin.hide()
  plugin.hide()
  t.equal(api.nvim_get_current_win(), base_win)
  assert(not api.nvim_win_is_valid(win))
  assert(not api.nvim_buf_is_valid(buf))
end)

test("external window closure releases the buffer and permits reopening", function()
  plugin.show("i")
  local win, buf = float()
  api.nvim_win_close(win, true)
  t.equal(plugin.is_open(), false)
  assert(not api.nvim_buf_is_valid(buf))
  plugin.toggle()
  contains("[normal]")
  contains("Local action")
end)

test("external buffer wipe closes its owned window", function()
  plugin.show()
  local win, buf = float()
  api.nvim_buf_delete(buf, { force = true })
  assert(not api.nvim_win_is_valid(win))
  assert(not api.nvim_buf_is_valid(buf))
  t.equal(plugin.is_open(), false)
end)

test("unrelated window and buffer removal cannot disturb the browser", function()
  plugin.show()
  local own_win, own_buf = float()
  local foreign_buf = api.nvim_create_buf(false, true)
  vim.bo[foreign_buf].filetype = "cheatsheet"
  vim.bo[foreign_buf].bufhidden = "wipe"
  local foreign_win =
    api.nvim_open_win(foreign_buf, false, { relative = "editor", row = 0, col = 0, width = 10, height = 3 })
  api.nvim_win_close(foreign_win, true)
  t.equal(plugin.is_open(), true)
  assert(api.nvim_win_is_valid(own_win) and api.nvim_buf_is_valid(own_buf))
end)

test("deleting the source buffer falls back to global mappings", function(source)
  -- Neovim can reuse the final unnamed listed buffer instead of wiping its ID.
  local alternate = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(alternate, "cheatsheet-test-alternate")
  plugin.show()
  local _, buf = float()
  api.nvim_set_current_win(base_win)
  api.nvim_buf_delete(source, { force = true })
  assert(not api.nvim_buf_is_valid(source))
  plugin.next_mode()
  contains("Global insert", buf)
  assert(not text(buf):find("Local insert", 1, true))
  api.nvim_buf_delete(alternate, { force = true })
end)

test("closing the source window still permits clean browser closure", function()
  vim.cmd.split()
  local source_win = api.nvim_get_current_win()
  plugin.show()
  local win, buf = float()
  api.nvim_win_close(source_win, true)
  plugin.hide()
  assert(not api.nvim_win_is_valid(win) and not api.nvim_buf_is_valid(buf))
  t.equal(api.nvim_get_current_win(), base_win)
end)

test("toggle on another tab page moves the browser there in one press", function()
  plugin.toggle()
  local first_win = api.nvim_get_current_win()
  vim.cmd("wincmd p")
  vim.cmd.tabnew()
  local tab = api.nvim_get_current_tabpage()
  plugin.toggle()
  assert(not api.nvim_win_is_valid(first_win), "the hidden browser must be closed")
  local win = api.nvim_get_current_win()
  t.equal(api.nvim_win_get_tabpage(win), tab)
  t.equal(api.nvim_win_get_config(win).relative, "editor")
  t.equal(plugin.is_open(), true)
  plugin.toggle()
  t.equal(plugin.is_open(), false)
  vim.cmd.tabclose()
end)

test("command accepts a mode argument and completes configured modes", function()
  vim.cmd.Cheatsheet("i")
  contains("[insert]")
  contains("Local insert")
  vim.cmd.Cheatsheet("n")
  contains("[normal]")
  t.equal(vim.fn.getcompletion("Cheatsheet ", "cmdline"), { "n", "i" })
  t.equal(vim.fn.getcompletion("Cheatsheet i", "cmdline"), { "i" })
  vim.cmd.Cheatsheet()
  t.equal(plugin.is_open(), false)
end)

test("visual mode hides select-only mappings and keeps visual ones with the same key", function(source)
  plugin.setup({
    modes = { "n", "v" },
    group_rules = { { pattern = "^Test:", group = "tests", icon = "" } },
    exclude = { single_word = false },
  })
  vim.keymap.set("x", "zv", function() end, { buffer = source, desc = "Test: Visual only" })
  vim.keymap.set("s", "zv", function() end, { buffer = source, desc = "Test: Select only" })
  vim.keymap.set("s", "zs", function() end, { buffer = source, desc = "Test: Select key" })
  local ok, err = pcall(function()
    plugin.show("v")
    contains("Visual only")
    assert(not text():find("Select only", 1, true))
    assert(not text():find("Select key", 1, true))
    contains("[visual]")
  end)
  plugin.setup({
    modes = { "n", "i" },
    group_rules = { { pattern = "^Test:", group = "tests", icon = "" } },
    sort_groups = { "tests" },
    exclude = { single_word = false },
  })
  assert(ok, err)
end)

test("wide windows render groups in columns and narrow resize returns to one column", function(source)
  for index = 1, 6 do
    vim.keymap.set("n", "zc" .. index, function() end, { buffer = source, desc = "Column action number " .. index })
  end
  local columns = vim.o.columns
  local ok, err = pcall(function()
    vim.o.columns = 200
    plugin.show()
    local win, buf = float()
    ---@return boolean
    local function side_by_side()
      for _, line in ipairs(api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if line:find("tests", 1, true) and line:find("other", 1, true) then
          return true
        end
      end
      return false
    end
    assert(side_by_side(), "groups must share a row in a wide window")
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    for _, mark in
      ipairs(api.nvim_buf_get_extmarks(buf, api.nvim_create_namespace("cheatsheet"), 0, -1, { details = true }))
    do
      local details = assert(mark[4])
      assert(details.end_row == mark[2] and assert(details.end_col) <= #lines[mark[2] + 1])
    end
    api.nvim_win_call(win, function()
      vim.fn.winrestview({ lnum = 5, topline = 3, leftcol = 2 })
    end)
    vim.o.columns = 40
    api.nvim_exec_autocmds("VimResized", {})
    assert(vim.wait(200, function()
      return api.nvim_win_get_width(win) == 32
    end))
    t.equal(float(), win)
    t.equal(api.nvim_get_current_buf(), buf)
    assert(not side_by_side(), "a narrow window must use one column")
    local view = api.nvim_win_call(win, vim.fn.winsaveview)
    t.equal({ view.lnum, view.topline, view.leftcol }, { 1, 1, 0 })
  end)
  vim.o.columns = columns
  assert(ok, err)
end)

test("queued resize callbacks cannot reopen a closed session", function()
  plugin.show()
  vim.o.columns = 80
  api.nvim_exec_autocmds("VimResized", {})
  plugin.hide()
  vim.wait(30, function()
    return false
  end)
  t.equal(plugin.is_open(), false)
  for _, buf in ipairs(api.nvim_list_bufs()) do
    assert(vim.bo[buf].filetype ~= "cheatsheet")
  end
end)

local ok, err = pcall(t.run, "cheatsheet Neovim integration")
plugin.hide()
vim.notify = original_notify
assert(ok, err)
