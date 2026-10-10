local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path
local t = require("support")
local adapter = require("dashboard.integrations.nvim").new()
local plugin = require("dashboard.controller").new(adapter)
local base = vim.api.nvim_get_current_win()
local errors = {}
---@param message string
---@return nil
function adapter.notify(message)
  errors[#errors + 1] = message
end

---@return DashboardOptions
local function options()
  return {
    autostart = false,
    layout = { vertical = "top" },
    blocks = {
      {
        id = "menu",
        type = "actions",
        items = { { id = "open", label = "Original", key = "f", run = "let g:dashboard_adapter = 1" } },
      },
    },
  }
end

---@return integer
local function reset()
  plugin.teardown()
  vim.api.nvim_set_current_win(base)
  vim.cmd("silent only!")
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(base, buf)
  vim.o.laststatus, vim.o.showtabline = 3, 2
  return buf
end

t.test("native mapping failure rolls back text, mappings, styles and config", function()
  reset()
  plugin.setup(options())
  plugin.show()
  local buf = vim.api.nvim_get_current_buf()
  local before = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local opts = options()
  opts.blocks = { { id = "title", type = "text", lines = { "Replacement" } } }
  opts.highlights = { Text = { fg = "#123456" } }
  opts.map_opts = function()
    error("mapping builder failed")
  end
  plugin.setup(opts)
  t.equal(#errors, 1)
  t.equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), before)
  vim.api.nvim_feedkeys("f", "xt", false)
  t.equal(vim.g.dashboard_adapter, 1)
  plugin.refresh()
  t.equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), before)
end)

t.test("first render failure releases scratch buffer and restores UI", function()
  local source = reset()
  plugin.setup({
    autostart = false,
    blocks = {
      {
        id = "bad",
        type = "custom",
        render = function()
          error("provider failed")
        end,
      },
    },
  })
  plugin.show()
  t.equal(#errors, 2)
  t.equal(vim.api.nvim_get_current_buf(), source)
  t.equal({ vim.o.laststatus, vim.o.showtabline }, { 3, 2 })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    assert(vim.bo[buf].filetype ~= "dashboard")
  end
end)

t.test("modified source is preserved without writing or changing contents", function()
  local source = reset()
  vim.o.hidden = true
  vim.api.nvim_buf_set_lines(source, 0, -1, false, { "unsaved work" })
  plugin.setup(options())
  plugin.show()
  plugin.hide()
  t.equal(vim.api.nvim_get_current_buf(), source)
  t.equal(vim.api.nvim_buf_get_lines(source, 0, -1, false), { "unsaved work" })
  assert(vim.bo[source].modified)
  t.equal(#errors, 2)
end)

t.test("changing dimensions recomputes layout and preserves selected action", function()
  reset()
  plugin.setup(options())
  plugin.show()
  vim.cmd.vsplit()
  assert(vim.wait(500, function()
    return vim.bo.filetype == "dashboard" and vim.api.nvim_get_current_buf() ~= vim.api.nvim_win_get_buf(base)
  end))
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, 20)
  vim.api.nvim_exec_autocmds("WinResized", {})
  vim.wait(30)
  t.equal(vim.bo.filetype, "dashboard")
  vim.api.nvim_feedkeys("f", "xt", false)
  t.equal(vim.g.dashboard_adapter, 1)
  t.equal(#errors, 2)
end)

t.test("failed setup registration leaves an existing unrelated command intact", function()
  reset()
  local called = false
  vim.api.nvim_create_user_command("Dashboard", function()
    called = true
  end, {})
  plugin.setup(options())
  t.equal(#errors, 3)
  vim.cmd.Dashboard()
  assert(called)
  assert(not pcall(vim.api.nvim_get_autocmds, { group = "Dashboard" }))
  vim.api.nvim_del_user_command("Dashboard")
  plugin.setup(options())
  plugin.show()
  t.equal(vim.bo.filetype, "dashboard")
end)

t.test("same-size text replacement recreates all highlight ranges", function()
  reset()
  local word = "Alpha"
  plugin.setup({
    autostart = false,
    layout = { horizontal = "left", vertical = "top" },
    blocks = {
      {
        id = "title",
        type = "text",
        lines = function()
          return { word, "Fixed" }
        end,
        style = "Header",
      },
    },
  })
  plugin.show()
  local ns = vim.api.nvim_get_namespaces().Dashboard
  word = "Bravo"
  plugin.refresh()
  local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
  t.equal(#marks, 2)
  for index, mark in ipairs(marks) do
    t.equal({ mark[2], mark[3], mark[4].end_row, mark[4].end_col }, { index - 1, 0, index - 1, 5 })
    t.equal(mark[4].hl_group, "DashboardHeader")
  end
end)

t.test("native key aliases cannot override navigation or duplicate another action", function()
  reset()
  local before = #errors
  for _, key in ipairs({ "<Enter>", "<Return>", "<Char-106>", "<Char-107>", "<Char-102>" }) do
    plugin.setup({
      autostart = false,
      blocks = {
        {
          id = "menu",
          type = "actions",
          items = {
            { id = "one", label = "One", key = "f", run = "" },
            { id = "two", label = "Two", key = key, run = "" },
          },
        },
      },
    })
    local source = vim.api.nvim_get_current_buf()
    plugin.show()
    t.equal(vim.api.nvim_get_current_buf(), source)
    assert(errors[#errors]:find("duplicate or reserved", 1, true))
  end
  t.equal(#errors, before + 5)
end)

t.test("invalid returned highlight color restores last successful palette after ColorScheme", function()
  reset()
  local bad = false
  plugin.setup({
    autostart = false,
    highlights = function()
      return { Header = { fg = bad and "INVALID_DASHBOARD_COLOR" or "#123456" } }
    end,
  })
  local before = #errors
  bad = true
  vim.cmd.colorscheme("default")
  t.equal(vim.api.nvim_get_hl(0, { name = "DashboardHeader" }).fg, 0x123456)
  t.equal(#errors, before + 1)
end)

t.test("native resources survive failed cleanup of an initial creation failure for retry", function()
  local source = reset()
  plugin.setup(options())
  local create, close = adapter.create, adapter.close
  adapter.create = function(ctx, track)
    create(ctx, track)
    error("failed after allocation")
  end
  local first = true
  adapter.close = function(session, restore)
    if first then
      first = false
      error("cleanup failed")
    end
    close(session, restore)
  end
  plugin.show()
  local scratch = vim.api.nvim_get_current_buf()
  assert(scratch ~= source)
  plugin.hide()
  t.equal(vim.api.nvim_get_current_buf(), source)
  assert(not vim.api.nvim_buf_is_valid(scratch))
  adapter.create, adapter.close = create, close
end)

t.test("unchanged mappings survive refresh while actions and setup still update", function()
  reset()
  local count = 0
  local opts = options()
  local action = "let g:dashboard_adapter = 1"
  opts.blocks[1].items = function()
    return { { id = "open", label = "Original", key = "f", run = action } }
  end
  opts.map_opts = function(description, values)
    count = count + 1
    return vim.tbl_extend("force", { desc = description, silent = true }, values or {})
  end
  plugin.setup(opts)
  plugin.show()
  local before = count
  plugin.refresh()
  t.equal(count, before)
  -- Replacing the callback for the same identity does not require a new mapping.
  action = "let g:dashboard_adapter = 2"
  plugin.refresh()
  t.equal(count, before)
  vim.api.nvim_feedkeys("f", "xt", false)
  t.equal(vim.g.dashboard_adapter, 2)
  plugin.setup(opts)
  assert(count > before, "setup must reapply mapping options even with the same builder")
  before = count
  plugin.refresh()
  t.equal(count, before)
  vim.api.nvim_feedkeys("f", "xt", false)
  t.equal(vim.g.dashboard_adapter, 2)
end)

t.test("resize skips unchanged geometry and explicit refresh still invokes providers", function()
  reset()
  local calls = 0
  plugin.setup({
    autostart = false,
    blocks = {
      {
        id = "title",
        type = "text",
        lines = function()
          calls = calls + 1
          return { "Hello" }
        end,
      },
    },
  })
  plugin.show()
  vim.wait(30)
  local before = calls
  vim.api.nvim_exec_autocmds("WinResized", {})
  vim.wait(30)
  t.equal(calls, before)
  vim.cmd.vsplit()
  vim.wait(30)
  before = calls
  vim.api.nvim_win_set_width(0, 20)
  vim.api.nvim_exec_autocmds("WinResized", {})
  vim.wait(30)
  assert(calls > before)
  before = calls
  plugin.refresh(vim.api.nvim_get_current_win())
  t.equal(calls, before + 1)
end)

t.test("ordinary editor events do not schedule dashboard work when no sessions remain", function()
  reset()
  plugin.setup(options())
  plugin.show()
  plugin.hide()
  vim.wait(30)
  local schedule = adapter.schedule
  local calls = 0
  adapter.schedule = function(callback)
    calls = calls + 1
    schedule(callback)
  end
  vim.api.nvim_exec_autocmds("BufEnter", {})
  vim.api.nvim_exec_autocmds("WinEnter", {})
  vim.wait(30)
  t.equal(calls, 0)
  adapter.schedule = schedule
end)

t.test("navigation aliases are rejected during setup before changing an existing screen", function()
  reset()
  plugin.setup(options())
  plugin.show()
  local buf = vim.api.nvim_get_current_buf()
  local before = #errors
  local opts = options()
  opts.navigation = { keys = { next = { "<Return>" } } }
  opts.chrome = { hide_statusline = false }
  plugin.setup(opts)
  t.equal(#errors, before + 1)
  assert(errors[#errors]:find("duplicate navigation key", 1, true))
  t.equal(vim.api.nvim_get_current_buf(), buf)
  t.equal(vim.o.laststatus, 0)
  vim.api.nvim_feedkeys("f", "xt", false)
  t.equal(vim.g.dashboard_adapter, 1)
end)

t.test("stable chrome reconciliation avoids writes and still repairs external changes", function()
  reset()
  plugin.setup(options())
  plugin.show()
  local set_option = vim.api.nvim_set_option_value
  local writes = 0
  -- Temporarily instrument native calls; restore the API even if an assertion fails.
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_set_option_value = function(name, value, opts)
    writes = writes + 1
    set_option(name, value, opts)
  end
  local ok, err = pcall(function()
    adapter.reconcile()
    adapter.reconcile()
    t.equal(writes, 0)
    set_option("winbar", "external", { win = base })
    adapter.reconcile()
    t.equal(writes, 1)
    t.equal(vim.api.nvim_get_option_value("winbar", { win = base }), "")
    plugin.hide()
    writes = 0
    vim.api.nvim_exec_autocmds("OptionSet", { pattern = "winbar" })
    t.equal(writes, 0)
  end)
  vim.api.nvim_set_option_value = set_option
  assert(ok, err)
end)

t.test("alias lookup reads each unowned ordinary window buffer once", function()
  reset()
  plugin.setup(options())
  plugin.show()
  for _ = 1, 2 do
    vim.cmd("noautocmd vsplit")
    plugin.show()
  end
  local clones = {}
  for _ = 1, 2 do
    vim.cmd("noautocmd vsplit")
    clones[#clones + 1] = vim.api.nvim_get_current_win()
  end
  vim.cmd("noautocmd vsplit")
  vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(true, false))
  local floating = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 10,
    height = 2,
  })
  local get_buf = vim.api.nvim_win_get_buf
  local reads = 0
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.api.nvim_win_get_buf = function(win)
    reads = reads + 1
    return get_buf(win)
  end
  local ok, result = pcall(adapter.aliases)
  vim.api.nvim_win_get_buf = get_buf
  vim.api.nvim_win_close(floating, true)
  assert(ok, result)
  table.sort(result)
  table.sort(clones)
  t.equal(result, clones)
  t.equal(reads, 3)
end)

t.run("Dashboard adapter")
plugin.teardown()
