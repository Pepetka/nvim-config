local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path
local t = require("support")
local api = vim.api
local plugin = require("dashboard")
local errors = {}
local original_notify = vim.notify
---@param message string
---@param level? integer
---@return nil
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(message, level)
  errors[#errors + 1] = message
end
local base_win = api.nvim_get_current_win()

---@param keys string
---@return nil
local function press(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

---@param needle string
---@param buf? integer
---@return nil
local function contains(needle, buf)
  local text = table.concat(api.nvim_buf_get_lines(buf or 0, 0, -1, false), "\n")
  assert(text:find(needle, 1, true), "missing " .. needle)
end

---@param fn fun(source: integer): nil
---@return nil
local function isolated(fn)
  plugin.teardown()
  api.nvim_set_current_win(base_win)
  vim.cmd("silent only!")
  local source = api.nvim_create_buf(true, false)
  api.nvim_win_set_buf(base_win, source)
  vim.o.laststatus, vim.o.showtabline = 3, 2
  vim.wo.number, vim.wo.wrap, vim.wo.winbar = true, true, "source"
  local before = #errors
  fn(source)
  plugin.teardown()
  vim.wait(20)
  t.equal(#errors, before, "unexpected dashboard error")
end

---@param name string
---@param fn fun(source: integer): nil
---@return nil
local function test(name, fn)
  t.test(name, function()
    isolated(fn)
  end)
end

---@return DashboardOptions
local function options()
  return {
    autostart = false,
    blocks = {
      { id = "title", type = "text", lines = { "Hello" }, style = "Header" },
      {
        id = "menu",
        type = "actions",
        items = {
          { id = "one", label = "One", key = "f", run = "let g:dashboard_action = 1" },
          { id = "two", label = "Two", key = "s", run = "let g:dashboard_action = 2" },
        },
      },
    },
  }
end

test("public API, scratch options, panels and original buffer", function(source)
  plugin.setup(options())
  assert(vim.fn.exists(":Dashboard") == 2)
  vim.cmd.Dashboard()
  local buf = api.nvim_get_current_buf()
  assert(buf ~= source)
  t.equal(vim.bo.filetype, "dashboard")
  t.equal(vim.bo.buftype, "nofile")
  t.equal(vim.bo.buflisted, false)
  t.equal(vim.bo.modifiable, false)
  t.equal(vim.bo.swapfile, false)
  t.equal({ vim.o.laststatus, vim.o.showtabline, vim.wo.winbar }, { 0, 0, "" })
  assert(not package.loaded["utils.map_opts"], "autonomous plugin loaded host helpers")
  contains("Hello")
  assert(#api.nvim_buf_get_extmarks(buf, api.nvim_get_namespaces().Dashboard, 0, -1, { details = true }) > 0)
  plugin.hide()
  t.equal(api.nvim_get_current_buf(), source)
  assert(not api.nvim_buf_is_valid(buf))
  t.equal(
    { vim.o.laststatus, vim.o.showtabline, vim.wo.winbar, vim.wo.number, vim.wo.wrap },
    { 3, 2, "source", true, true }
  )
end)

test("actual navigation, Enter and direct keys", function()
  plugin.setup(options())
  plugin.show()
  press("j<CR>")
  t.equal(vim.g.dashboard_action, 2)
  press("j<CR>")
  t.equal(vim.g.dashboard_action, 1)
  press("k<CR>")
  t.equal(vim.g.dashboard_action, 2)
  press("f")
  t.equal(vim.g.dashboard_action, 1)
end)

test("an action keeps focus in the window it opens", function()
  local opened
  plugin.setup({
    autostart = false,
    blocks = {
      {
        id = "menu",
        type = "actions",
        items = {
          {
            id = "split",
            label = "Split",
            key = "s",
            run = function()
              vim.cmd.vnew()
              opened = api.nvim_get_current_win()
            end,
          },
        },
      },
    },
  })
  plugin.show()
  press("s")
  t.equal(api.nvim_get_current_win(), opened)
end)

test("repeated show and setup preserve buffer and selected identity", function()
  plugin.setup(options())
  plugin.show()
  press("j")
  local buf = api.nvim_get_current_buf()
  local group_size = #api.nvim_get_autocmds({ group = "Dashboard" })
  plugin.show()
  plugin.setup(options())
  t.equal(api.nvim_get_current_buf(), buf)
  t.equal(#api.nvim_get_autocmds({ group = "Dashboard" }), group_size)
  press("<CR>")
  t.equal(vim.g.dashboard_action, 2)
end)

test("native split creates independent geometry and restores original options", function(source)
  plugin.setup(options())
  plugin.show()
  local first_buf = api.nvim_get_current_buf()
  vim.cmd.vsplit()
  local second = api.nvim_get_current_win()
  assert(vim.wait(500, function()
    return api.nvim_get_current_buf() ~= first_buf
  end))
  local second_buf = api.nvim_get_current_buf()
  t.equal(vim.bo.filetype, "dashboard")
  assert(second_buf ~= first_buf)
  press("j")
  api.nvim_set_current_win(base_win)
  press("<CR>")
  t.equal(vim.g.dashboard_action, 1)
  api.nvim_set_current_win(second)
  plugin.hide()
  t.equal(api.nvim_get_current_buf(), source)
  t.equal(vim.wo.number, true)
  t.equal(vim.o.laststatus, 0)
  api.nvim_set_current_win(base_win)
  plugin.hide()
  t.equal(vim.o.laststatus, 3)
end)

test("native resize preserves relative block alignment across even and odd widths", function()
  plugin.setup({
    autostart = false,
    layout = { vertical = "top" },
    blocks = {
      { id = "header", type = "text", lines = { "------" }, style = "Header" },
      { id = "menu", type = "actions", items = { { id = "go", label = "abcde", run = "" } } },
      { id = "footer", type = "text", lines = { "------" }, style = "Footer" },
    },
  })
  plugin.show()
  vim.cmd.vsplit()
  vim.wait(30)
  local win = api.nvim_get_current_win()
  for _, width in ipairs({ 40, 41, 40 }) do
    api.nvim_win_set_width(win, width)
    api.nvim_exec_autocmds("WinResized", {})
    vim.wait(30)
    t.equal(api.nvim_win_get_width(win), width)
    local lines = api.nvim_buf_get_lines(0, 0, -1, false)
    t.equal(lines, { "                 ------", "                  abcde", "                 ------" })
    t.equal(api.nvim_win_get_cursor(win), { 2, 18 })
  end
end)

test("leaving dashboard restores chrome and window options without returning to source", function()
  plugin.setup(options())
  plugin.show()
  vim.cmd.enew()
  local replacement = api.nvim_get_current_buf()
  vim.wait(30)
  assert(vim.bo.filetype ~= "dashboard")
  t.equal(vim.o.laststatus, 3)
  t.equal(vim.wo.number, true)
  plugin.hide()
  t.equal(api.nvim_get_current_buf(), replacement)
end)

test("switching tabs restores and hides panels for the current tab", function()
  plugin.setup(options())
  plugin.show()
  vim.cmd.tabnew()
  vim.wait(30)
  t.equal(vim.o.laststatus, 3)
  vim.cmd.tabprevious()
  vim.wait(30)
  t.equal(vim.o.laststatus, 0)
  vim.cmd.tabnext()
  vim.cmd.tabclose()
end)

test("ColorScheme updates styles without invoking content providers", function()
  local calls, color = 0, "#112233"
  local opts = options()
  opts.blocks = {
    {
      id = "title",
      type = "text",
      lines = function()
        calls = calls + 1
        return { "Stable" }
      end,
    },
  }
  opts.highlights = function()
    return { Text = { fg = color } }
  end
  plugin.setup(opts)
  plugin.show()
  local buf, tick, before = api.nvim_get_current_buf(), vim.b.changedtick, calls
  color = "#445566"
  vim.cmd.colorscheme("default")
  vim.wait(30)
  t.equal(api.nvim_get_hl(0, { name = "DashboardText", link = false }).fg, tonumber("445566", 16))
  t.equal(calls, before)
  t.equal(vim.b[buf].changedtick, tick)
  t.equal(vim.o.laststatus, 0)
end)

test("later native theme consumer cannot expose chrome", function()
  plugin.setup(options())
  plugin.show()
  local native = api.nvim_create_autocmd("ColorScheme", {
    callback = function()
      vim.o.laststatus = 3
      vim.o.showtabline = 2
    end,
  })
  vim.cmd.colorscheme("default")
  vim.wait(30)
  api.nvim_del_autocmd(native)
  t.equal({ vim.o.laststatus, vim.o.showtabline }, { 0, 0 })
end)

test("explicit refresh retains cursor and skips identical line writes", function()
  plugin.setup(options())
  plugin.show()
  press("j")
  local tick = vim.b.changedtick
  plugin.refresh()
  t.equal(vim.b.changedtick, tick)
  press("<CR>")
  t.equal(vim.g.dashboard_action, 2)
end)

test("external buffer wipe and window closure clean only owned resources", function(source)
  plugin.setup(options())
  plugin.show()
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_delete(buf, { force = true })
  vim.wait(30)
  t.equal(vim.o.laststatus, 3)
  assert(api.nvim_buf_is_valid(source))
  plugin.show()
  vim.cmd.vsplit()
  vim.wait(30)
  local second_buf = api.nvim_get_current_buf()
  vim.cmd.close()
  vim.wait(30)
  assert(not api.nvim_buf_is_valid(second_buf))
  t.equal(vim.o.laststatus, 0)
end)

test("deleted source falls back to an ordinary buffer", function(source)
  plugin.setup(options())
  plugin.show()
  api.nvim_buf_delete(source, { force = true })
  plugin.hide()
  t.equal(vim.bo.buftype, "")
  t.equal(vim.bo.filetype, "")
end)

test("custom block and closure survive reopening", function()
  local executions = 0
  plugin.setup({
    autostart = false,
    highlights = { Project = { fg = "#123456" } },
    blocks = {
      {
        id = "project",
        type = "custom",
        render = function()
          return {
            lines = { "Project" },
            spans = { { row = 0, start_col = 0, end_col = 7, style = "Project" } },
            targets = {
              {
                id = "open",
                row = 0,
                col = 0,
                key = "p",
                run = function()
                  executions = executions + 1
                end,
              },
            },
          }
        end,
      },
    },
  })
  plugin.show()
  press("p")
  plugin.hide()
  plugin.show()
  press("<CR>")
  t.equal(executions, 2)
  t.equal(api.nvim_get_hl(0, { name = "DashboardProject", link = false }).fg, tonumber("123456", 16))
end)

test("hide_chrome false and config replacement restore chrome immediately", function()
  plugin.setup(options())
  plugin.show()
  local opts = options()
  opts.hide_chrome = false
  plugin.setup(opts)
  t.equal({ vim.o.laststatus, vim.o.showtabline, vim.wo.winbar }, { 3, 2, "source" })
  local lines = api.nvim_buf_get_lines(0, 0, -1, false)
  local expected_top = math.floor((api.nvim_win_get_height(0) - 4) / 2)
  t.equal(lines[expected_top + 1]:gsub("^%s+", ""), "Hello")
end)

test("split adopted after parent closes before scheduled cleanup", function(source)
  plugin.setup(options())
  plugin.show()
  local parent_buf = api.nvim_get_current_buf()
  vim.cmd.vsplit()
  local child = api.nvim_get_current_win()
  api.nvim_win_close(base_win, false)
  assert(vim.wait(500, function()
    return api.nvim_get_current_buf() ~= parent_buf
  end))
  t.equal(vim.bo.filetype, "dashboard")
  plugin.hide()
  t.equal(api.nvim_get_current_buf(), source)
  -- Keep the shared test harness's base window alive for subsequent cases.
  base_win = child
end)

test("teardown cancels queued resize and removes commands and handlers", function()
  plugin.setup(options())
  plugin.show()
  api.nvim_exec_autocmds("VimResized", {})
  plugin.teardown()
  vim.wait(30)
  t.equal(vim.fn.exists(":Dashboard"), 0)
  t.equal(vim.o.laststatus, 3)
  assert(not pcall(api.nvim_get_autocmds, { group = "Dashboard" }))
  plugin.teardown()
  plugin.setup(options())
  plugin.show()
  t.equal(vim.bo.filetype, "dashboard")
end)

test("teardown before split adoption restores both windows", function(source)
  plugin.setup(options())
  plugin.show()
  vim.cmd.vsplit()
  local child = api.nvim_get_current_win()
  plugin.teardown()
  vim.wait(30)
  t.equal(api.nvim_get_current_buf(), source)
  t.equal(vim.wo.number, true)
  t.equal(vim.o.laststatus, 3)
  api.nvim_set_current_win(base_win)
  t.equal(api.nvim_get_current_buf(), source)
  t.equal(vim.wo.number, true)
  api.nvim_win_close(child, false)
end)

test("configured navigation keys, counts and nonwrapping movement work through actual mappings", function()
  local opts = options()
  opts.navigation = { wrap = false, keys = { next = { "n" }, previous = { "p" }, activate = { "<Space>" } } }
  plugin.setup(opts)
  plugin.show()
  t.equal(vim.fn.maparg("j", "n", false, true), {})
  press("3n")
  press("<Space>")
  t.equal(vim.g.dashboard_action, 2)
  press("n")
  press("<Space>")
  t.equal(vim.g.dashboard_action, 2)
  press("2p")
  press("<Space>")
  t.equal(vim.g.dashboard_action, 1)
  opts.navigation.keys.next = {}
  opts.blocks[2].items[1].key = "j"
  plugin.setup(opts)
  press("j")
  t.equal(vim.g.dashboard_action, 1)
end)

test("selected role follows navigation and disappears when disabled", function()
  local opts = options()
  local color, calls = "#123456", 0
  opts.blocks[1].lines = function()
    calls = calls + 1
    return { "Hello" }
  end
  opts.navigation = { highlight_selected = true }
  opts.highlights = function()
    return { Selected = { bg = color } }
  end
  plugin.setup(opts)
  plugin.show()
  local ns = api.nvim_get_namespaces().DashboardSelection
  local marks = api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
  t.equal(#marks, 1)
  t.equal(marks[1][2], api.nvim_win_get_cursor(0)[1] - 1)
  t.equal(marks[1][4].hl_group, "DashboardSelected")
  t.equal(api.nvim_get_hl(0, { name = "DashboardSelected", link = false }).bg, 0x123456)
  local row = marks[1][2]
  press("j")
  marks = api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
  assert(marks[1][2] > row)
  t.equal(marks[1][2], api.nvim_win_get_cursor(0)[1] - 1)
  local tick, before = api.nvim_buf_get_changedtick(0), calls
  color = "#654321"
  api.nvim_exec_autocmds("ColorScheme", {})
  t.equal(api.nvim_buf_get_changedtick(0), tick)
  t.equal(calls, before)
  t.equal(api.nvim_get_hl(0, { name = "DashboardSelected", link = false }).bg, 0x654321)
  plugin.refresh()
  t.equal(api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })[1][2], marks[1][2])
  opts.navigation.highlight_selected = false
  plugin.setup(opts)
  t.equal(api.nvim_buf_get_extmarks(0, ns, 0, -1, {}), {})
end)

test("chrome controls each panel independently and captures newly hidden values", function(source)
  local opts = options()
  plugin.setup(opts)
  plugin.show()
  opts.chrome = { hide_statusline = false }
  plugin.setup(opts)
  t.equal({ vim.o.laststatus, vim.o.showtabline, vim.wo.winbar }, { 3, 0, "" })
  vim.o.laststatus = 2
  t.equal(vim.o.laststatus, 2)
  opts.chrome = { hide_tabline = false, hide_winbar = false }
  plugin.setup(opts)
  t.equal({ vim.o.laststatus, vim.o.showtabline, vim.wo.winbar }, { 0, 2, "source" })
  plugin.hide()
  t.equal(api.nvim_get_current_buf(), source)
  t.equal({ vim.o.laststatus, vim.o.showtabline, vim.wo.winbar }, { 2, 2, "source" })
end)

test("visible panels accept changes while another panel is hidden", function()
  local opts = options()
  opts.hide_chrome = false
  opts.chrome = { hide_tabline = true }
  plugin.setup(opts)
  plugin.show()
  t.equal({ vim.o.laststatus, vim.o.showtabline, vim.wo.winbar }, { 3, 0, "source" })
  vim.o.laststatus = 2
  vim.wo.winbar = "during"
  t.equal({ vim.o.laststatus, vim.o.showtabline, vim.wo.winbar }, { 2, 0, "during" })
  opts.chrome.hide_winbar = true
  plugin.setup(opts)
  t.equal(vim.wo.winbar, "")
  opts.chrome.hide_winbar = false
  plugin.setup(opts)
  t.equal(vim.wo.winbar, "during")
  plugin.hide()
  t.equal({ vim.o.laststatus, vim.o.showtabline, vim.wo.winbar }, { 2, 2, "source" })
end)

test("hiding actions removes their keys and moves selection to a remaining target", function()
  local visible = true
  plugin.setup({
    autostart = false,
    blocks = {
      {
        id = "first",
        type = "actions",
        items = { { id = "a", label = "A", key = "f", run = "let g:dashboard_action = 1" } },
      },
      {
        id = "second",
        type = "actions",
        enabled = function()
          return visible
        end,
        items = function()
          assert(visible, "hidden action provider was called")
          return { { id = "b", label = "B", key = "s", run = "let g:dashboard_action = 2" } }
        end,
      },
    },
  })
  plugin.show()
  press("j")
  visible = false
  plugin.refresh()
  t.equal(vim.fn.maparg("s", "n", false, true), {})
  press("<CR>")
  t.equal(vim.g.dashboard_action, 1)
  visible = true
  plugin.refresh()
  press("s")
  t.equal(vim.g.dashboard_action, 2)
end)

test("custom block offsets keep Unicode selection and highlight byte columns consistent", function()
  plugin.setup({
    autostart = false,
    layout = { horizontal = "left", vertical = "top" },
    navigation = { highlight_selected = true },
    blocks = {
      {
        id = "custom",
        type = "custom",
        layout = { offset_x = 2, gap_before = 1 },
        render = function()
          return {
            lines = { "ёж" },
            spans = { { row = 0, start_col = 0, end_col = 4, style = "Text" } },
            targets = { { id = "go", row = 0, col = 0, run = "" } },
          }
        end,
      },
    },
  })
  plugin.show()
  t.equal(api.nvim_buf_get_lines(0, 0, -1, false), { "", "  ёж" })
  t.equal(api.nvim_win_get_cursor(0), { 2, 2 })
  for _, name in ipairs({ "Dashboard", "DashboardSelection" }) do
    local marks = api.nvim_buf_get_extmarks(0, api.nvim_get_namespaces()[name], 0, -1, { details = true })
    t.equal(#marks, 1)
    t.equal({ marks[1][2], marks[1][3], marks[1][4].end_col }, { 1, 2, 6 })
  end
end)

t.run("Dashboard Neovim")
plugin.teardown()
vim.notify = original_notify
