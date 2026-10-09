local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path
vim.o.swapfile = false
vim.o.columns, vim.o.lines = 120, 40
local api = vim.api
local integration = require("cheatsheet.integrations.nvim")
local controller = require("cheatsheet.controller")
local config = require("cheatsheet.core.config")
local layout = require("cheatsheet.core.layout")
local t = require("support")
local source_win = api.nvim_get_current_win()
local original_notify = vim.notify
local notifications = {}
-- Intercept notifications for assertions, restoring the original after the suite.
---@param message string
---@param level? integer
---@return nil
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(message, level)
  notifications[#notifications + 1] = { message = message, level = level }
end

---@param options? CheatsheetConfigPartial
---@return CheatsheetController
local function fixture(options)
  local instance = controller.new(integration.new())
  instance.setup(options)
  return instance
end
---@return integer
local function scratch_count()
  local count = 0
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if vim.bo[buf].filetype == "cheatsheet" then
      count = count + 1
    end
  end
  return count
end
---@generic T
---@param owner table<string, T>
---@param name string
---@param replacement T
---@param fn CheatsheetAction
---@return nil
local function with_fault(owner, name, replacement, fn)
  local original = owner[name]
  owner[name] = replacement
  local ok, err = xpcall(fn, debug.traceback)
  owner[name] = original
  assert(ok, err)
end

t.test("opening-key installation is optional and keeps a useful description", function()
  local instance = fixture({ open_mapping = "<F12>" })
  local map = vim.fn.maparg("<F12>", "n", false, true)
  t.equal(map.desc, "Cheatsheet: Toggle")
  map.callback()
  t.equal(vim.g.cheatsheet_displayed, true)
  map.callback()
  t.equal(vim.g.cheatsheet_displayed, false)
  vim.keymap.del("n", "<F12>")
end)

t.test("installation failure removes partial registrations and permits retry", function()
  local instance = controller.new(integration.new())
  with_fault(vim.keymap, "set", function()
    error("injected mapping error")
  end, function()
    instance.setup({ open_mapping = "<F12>" })
  end)
  t.equal(vim.fn.exists(":Cheatsheet"), 0)
  t.equal(vim.fn.exists("#Cheatsheet"), 0)
  instance.setup({ open_mapping = "<F12>" })
  t.equal(vim.fn.exists(":Cheatsheet"), 2)
  instance.show()
  t.equal(vim.g.cheatsheet_displayed, true)
  instance.hide()
  vim.keymap.del("n", "<F12>")
end)

t.test("all declared border styles open and close, including titleless none", function()
  for _, border in ipairs({ "none", "shadow", "single", "double", "rounded", "solid" }) do
    local instance = fixture({ window = { border = border } })
    instance.show()
    t.equal(vim.g.cheatsheet_displayed, true, border)
    local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
    instance.hide()
    assert(not api.nvim_win_is_valid(win) and not api.nvim_buf_is_valid(buf))
  end
end)

t.test("tiny positive ratios open a one-cell float without leaking", function()
  local instance = fixture({ window = { width = 0.001, height = 0.001 } })
  instance.show()
  local win = api.nvim_get_current_win()
  t.equal(api.nvim_win_get_width(win), 1)
  t.equal(api.nvim_win_get_height(win), 1)
  instance.hide()
  t.equal(scratch_count(), 0)
end)

t.test("empty title is omitted from window configuration", function()
  local instance = fixture({ window = { title = "" } })
  instance.show()
  t.equal(api.nvim_win_get_config(api.nvim_get_current_win()).title, nil)
  instance.hide()
end)

t.test("native leader fallback is backslash when mapleader is unset", function()
  vim.g.mapleader = nil
  local instance = fixture({ exclude = { single_word = false } })
  local source = api.nvim_get_current_buf()
  vim.keymap.set("n", "<leader>zz", function() end, { buffer = source, desc = "Leader action" })
  instance.show()
  local text = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  assert(text:find("<leader> + zz", 1, true))
  instance.hide()
  vim.keymap.del("n", "<leader>zz", { buffer = source })
end)

t.test("failed window creation wipes the already-created buffer", function()
  local instance = fixture()
  local before = #api.nvim_list_bufs()
  with_fault(api, "nvim_open_win", function()
    error("injected open error")
  end, instance.show)
  t.equal(#api.nvim_list_bufs(), before)
  t.equal(scratch_count(), 0)
  t.equal(vim.g.cheatsheet_displayed, false)
  t.equal(notifications[#notifications].level, vim.log.levels.ERROR)
  instance.show()
  t.equal(vim.g.cheatsheet_displayed, true)
  instance.hide()
end)

t.test("failed buffer configuration also cleans its partial allocation", function()
  local instance = fixture()
  local original = api.nvim_set_option_value
  local before = #api.nvim_list_bufs()
  with_fault(api, "nvim_set_option_value", function(name, value, opts)
    if name == "filetype" and value == "cheatsheet" then
      error("injected option error")
    end
    return original(name, value, opts)
  end, instance.show)
  t.equal(#api.nvim_list_bufs(), before)
  t.equal(vim.g.cheatsheet_displayed, false)
  instance.show()
  instance.hide()
end)

t.test("failed window keymap installation disposes both resources", function()
  local instance = fixture()
  local before_windows, before_buffers = #api.nvim_list_wins(), #api.nvim_list_bufs()
  with_fault(vim.keymap, "set", function()
    error("injected keymap error")
  end, instance.show)
  t.equal(#api.nvim_list_wins(), before_windows)
  t.equal(#api.nvim_list_bufs(), before_buffers)
  t.equal(vim.g.cheatsheet_displayed, false)
end)

t.test("partial creation stays owned when cleanup also fails", function()
  local instance = fixture()
  local before = #api.nvim_list_wins()
  with_fault(api, "nvim_win_close", function()
    error("injected close error")
  end, function()
    with_fault(api, "nvim_buf_delete", function()
      error("injected delete error")
    end, function()
      with_fault(vim.keymap, "set", function()
        error("injected keymap error")
      end, instance.show)
    end)
  end)
  t.equal(#api.nvim_list_wins(), before + 1)
  t.equal(scratch_count(), 1)
  instance.hide()
  t.equal(#api.nvim_list_wins(), before)
  t.equal(scratch_count(), 0)
end)

t.test("failed buffer writes during rendering dispose the session", function()
  local instance = fixture()
  with_fault(api, "nvim_buf_set_lines", function()
    error("injected write error")
  end, instance.show)
  t.equal(scratch_count(), 0)
  t.equal(api.nvim_get_current_win(), source_win)
  instance.show()
  instance.hide()
end)

t.test("failed window closure retains ownership for cleanup after the error clears", function()
  local instance = fixture()
  instance.show()
  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  local replacement = api.nvim_create_buf(true, false)
  with_fault(api, "nvim_win_close", function()
    error("injected close error")
  end, function()
    api.nvim_win_set_buf(win, replacement)
  end)
  assert(api.nvim_win_is_valid(win), "fault must leave the window alive")
  assert(not api.nvim_buf_is_valid(buf), "the original scratch buffer must already be wiped")
  instance.hide()
  assert(not api.nvim_win_is_valid(win), "retry must close the remaining owned window")
  assert(api.nvim_buf_is_valid(replacement), "cleanup must not delete an unrelated replacement buffer")
  api.nvim_buf_delete(replacement, { force = true })
  t.equal(scratch_count(), 0)
end)

t.test("highlighting failures restore readonly state before propagating", function()
  local adapter = integration.new()
  local options = config.normalize()
  adapter.install(options, { toggle = function() end, resize = function() end, closed = function() end })
  local size = layout.geometry(options.window, adapter.viewport())
  local actions = { close = function() end, next_mode = function() end, prev_mode = function() end }
  local session = adapter.create(options, api.nvim_get_current_buf(), source_win, actions, size)
  local document = layout.build({}, "n", options, size.width, adapter.measure)
  with_fault(api, "nvim_buf_set_extmark", function()
    error("injected extmark error")
  end, function()
    local ok = pcall(adapter.update, session, size, document, false)
    t.equal(ok, false)
    t.equal(vim.bo[session.buf].modifiable, false)
  end)
  adapter.close(session)
  t.equal(scratch_count(), 0)
end)

t.test("real display-width measurement handles wide characters", function()
  local adapter = integration.new()
  t.equal(adapter.measure("界"), 2)
  t.equal(adapter.measure("é"), 1)
  t.equal(adapter.measure("é"), 1)
end)

t.test("all supported modes read the original buffer-local mappings", function()
  local source = api.nvim_get_current_buf()
  local modes = { "n", "i", "v", "o", "t" }
  for _, mode in ipairs(modes) do
    vim.keymap.set(mode, "zz" .. mode, function() end, { buffer = source, desc = "Mode " .. mode .. " action" })
  end
  local instance = fixture({ modes = modes })
  for _, mode in ipairs(modes) do
    instance.show(mode)
    local text = table.concat(api.nvim_buf_get_lines(0, 0, -1, false), "\n")
    assert(text:find("[" .. mode .. "]", 1, true))
    assert(text:find("Mode " .. mode .. " action", 1, true))
  end
  instance.hide()
  for _, mode in ipairs(modes) do
    vim.keymap.del(mode, "zz" .. mode, { buffer = source })
  end
end)

t.test("an empty source result uses the same layout after resize", function()
  local instance = fixture({ exclude = { patterns = { ".*" } }, modes = { "i" } })
  instance.show()
  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  local function message()
    return table.concat(api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("No mappings for i mode", 1, true)
  end
  assert(message())
  vim.o.columns = 100
  api.nvim_exec_autocmds("VimResized", {})
  assert(vim.wait(200, function()
    return api.nvim_win_get_width(win) == 80
  end))
  assert(message())
  instance.hide()
end)

t.test("description filters, explicit prefixes and custom spacing survive real rendering and resize", function()
  local source = api.nvim_get_current_buf()
  vim.keymap.set("n", "aa", function() end, { buffer = source, desc = "Inline diagnostic: alpha action" })
  vim.keymap.set("n", "bb", function() end, { buffer = source, desc = "Inline diagnostic: beta action" })
  vim.keymap.set("n", "cc", function() end, { buffer = source, desc = "MiniPairs hidden action" })
  local instance = fixture({
    modes = { "n" },
    group_rules = { { pattern = "^Inline diagnostic:", group = "diag", icon = "", prefix = "Inline diagnostic:" } },
    sort_groups = { "diag" },
    exclude = { desc_patterns = { "^MiniPairs" } },
    layout = { key_gap = 1, mapping_spacing = 0, group_spacing = 0 },
  })
  instance.show()
  local win, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  local function check()
    local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = table.concat(lines, "\n")
    assert(not text:find("Inline diagnostic:", 1, true))
    assert(not text:find("MiniPairs", 1, true))
    local alpha, beta
    for row, line in ipairs(lines) do
      if line:find("Alpha action", 1, true) then
        alpha = row - 1
      end
      if line:find("Beta action", 1, true) then
        beta = row - 1
      end
    end
    assert(alpha and beta == alpha + 1, "mapping spacing must be zero")
    local key_end, desc_start
    for _, mark in
      ipairs(
        api.nvim_buf_get_extmarks(
          buf,
          api.nvim_create_namespace("cheatsheet"),
          { alpha, 0 },
          { alpha + 1, 0 },
          { details = true }
        )
      )
    do
      if mark[2] == alpha then
        if mark[4].hl_group == "CheatsheetKey" then
          key_end = mark[4].end_col
        end
        if mark[4].hl_group == "CheatsheetDesc" then
          desc_start = mark[3]
        end
      end
    end
    t.equal(desc_start, key_end + 1)
  end
  check()
  vim.o.columns = 90
  api.nvim_exec_autocmds("VimResized", {})
  assert(vim.wait(200, function()
    return api.nvim_win_get_width(win) == 72
  end))
  t.equal(api.nvim_get_current_buf(), buf)
  check()
  instance.hide()
  for _, key in ipairs({ "aa", "bb", "cc" }) do
    vim.keymap.del("n", key, { buffer = source })
  end
end)

local ok, err = pcall(t.run, "cheatsheet Neovim adapter")
vim.notify = original_notify
assert(ok, err)
