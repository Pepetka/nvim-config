-- nvim --clean --headless -i NONE -l tests/diffview.lua
-- Requires installed diffview-plus.nvim; Git fixtures are isolated in a temp directory.
local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path
local support = require("support")
vim.opt.packpath:append(vim.fn.stdpath("data") .. "/site")
vim.o.swapfile, vim.o.hidden = false, true
vim.o.columns, vim.o.lines = 160, 50
vim.cmd.packadd("diffview-plus.nvim")
local api = vim.api
local plugin = require("tab_buffers")
local integration = require("tab_buffers.integrations.diffview")
local line = require("tab_buffers.tabline")
local diffview = require("diffview")
local tests, views, notices = {}, {}, {}
local real_notify = vim.notify
local original_cwd = vim.fn.getcwd()
local fixture = vim.fn.tempname()
vim.fn.mkdir(fixture, "p")
fixture = assert(vim.uv.fs_realpath(fixture))
-- Intentional native API replacement for failure injection.
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(message)
  notices[#notices + 1] = message
end

local equal = support.equal

---@return nil
local function drain()
  for _ = 1, 3 do
    local done = false
    vim.schedule(function()
      done = true
    end)
    assert(vim.wait(1000, function()
      return done
    end, 1))
  end
end

local function git(...)
  local result = vim.system({ "git", "-C", fixture, ... }, { text = true }):wait()
  assert(result.code == 0, result.stderr)
end

local function setup_view_config()
  local hooks = integration.hooks()
  local observe = hooks.view_opened
  hooks.view_opened = function(view)
    views[#views + 1] = view
    observe(view)
  end
  local maps = {
    { "n", "gf", integration.goto_file },
    { "n", "<C-w>gf", integration.goto_file_tab },
  }
  diffview.setup({
    use_icons = false,
    watch_index = false,
    hooks = hooks,
    keymaps = { view = maps, file_panel = maps, file_history_panel = maps },
  })
end

---@return nil
local function reset()
  for _, view in ipairs(views) do
    if api.nvim_tabpage_is_valid(view.tabpage) then
      diffview.close(view.tabpage, { force = true })
    end
  end
  drain()
  views = {}
  line.teardown()
  plugin.teardown()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    vim.bo[buf].modified, vim.bo[buf].bufhidden = false, ""
  end
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  vim.cmd("enew!")
  vim.t.tab_buffers_excluded = nil
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if buf ~= api.nvim_get_current_buf() then
      api.nvim_buf_delete(buf, { force = true })
    end
  end
  git("reset", "--hard", "--quiet", "HEAD")
  vim.fn.writefile({ "staged change" }, fixture .. "/staged.txt")
  git("add", "staged.txt")
  vim.fn.writefile({ "working change" }, fixture .. "/working.txt")
  vim.cmd.cd(fixture)
  setup_view_config()
  plugin.setup()
  notices = {}
end

git("init", "--quiet")
for _, name in ipairs({ "staged.txt", "working.txt", "original.txt", "target.txt" }) do
  vim.fn.writefile({ "base" }, fixture .. "/" .. name)
end
git("add", ".")
git(
  "-c",
  "user.name=tab-buffers test",
  "-c",
  "user.email=tab-buffers@example.invalid",
  "-c",
  "commit.gpgsign=false",
  "-c",
  "core.hooksPath=/dev/null",
  "commit",
  "--quiet",
  "-m",
  "fixture"
)

local function edit(name)
  vim.cmd.edit(vim.fn.fnameescape(fixture .. "/" .. name))
  plugin.refresh()
  return api.nvim_get_current_buf()
end

local function open_view(args)
  diffview.open(args or {})
  local view = views[#views]
  assert(view, "view_opened was not emitted")
  assert(
    vim.wait(10000, function()
      return view.ready and view.files:len() > 0
    end, 10),
    "Diffview file list timed out"
  )
  drain()
  return view
end

local function select_file(view, kind)
  local entry = view.files[kind][1]
  assert(entry, "missing entry: " .. kind)
  view:set_file(entry, true)
  assert(
    vim.wait(10000, function()
      local win = view.cur_layout and view.cur_layout:get_main_win()
      return view.cur_entry == entry
        and win
        and win.id
        and api.nvim_win_is_valid(win.id)
        and win.file
        and win.file:is_valid()
        and api.nvim_win_get_buf(win.id) == win.file.bufnr
        and api.nvim_get_current_win() == win.id
    end, 10),
    "file selection timed out"
  )
  drain()
  return api.nvim_get_current_buf()
end

local function mapping(lhs)
  local value = vim.fn.maparg(lhs, "n", false, true)
  assert(type(value.callback) == "function", "missing callback: " .. lhs)
  return value.callback()
end

local function render()
  drain()
  api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true })
  local labels = require("tab_buffers.tabline.layout").labels(vim.tbl_map(function(buf)
    return { id = buf, name = api.nvim_buf_get_name(buf) }
  end, plugin.buffers()))
  local result = {}
  for highlight, text in line.render():gmatch("%%#TabBuffers(%w+)#%%%d+@[^@]+@(.-)%%X") do
    if highlight ~= "Tab" and highlight ~= "TabActive" then
      local found
      for buf, label in pairs(labels) do
        if text:find(label, 1, true) then
          found = buf
          break
        end
      end
      assert(found, "unexpected rendered buffer: " .. text)
      result[#result + 1] = found
    end
  end
  return result
end

local function test(name, run)
  tests[#tests + 1] = { name = name, run = run }
end

test("staged and working previews stay outside ownership and tabline", function()
  local original = edit("original.txt")
  local normal = api.nvim_get_current_tabpage()
  local view = open_view()
  line.setup()
  assert(integration.is_review(view.tabpage))
  assert(line.render():find("󰊢 ", 1, true), "review tab must have a Diffview indicator")
  local stage = select_file(view, "staged")
  equal(vim.bo[stage].buftype, "acwrite")
  equal(plugin.buffers(view.tabpage), {})
  equal(render(), {})
  local working = select_file(view, "working")
  equal(vim.bo[working].buftype, "")
  equal(vim.bo[working].buflisted, true)
  equal(plugin.owners(working), {})
  equal(plugin.buffers(view.tabpage), {})
  equal(render(), {})
  equal(plugin.buffers(normal), { original })
  equal(vim.bo[original].buflisted, true)
end)

test("manager actions cannot replace diff windows or close a review tab", function()
  edit("original.txt")
  local view = open_view()
  local working = select_file(view, "working")
  local windows = api.nvim_tabpage_list_wins(view.tabpage)
  local before = vim.tbl_map(api.nvim_win_get_buf, windows)
  equal(plugin.next(), nil)
  equal(plugin.add(working), false)
  equal(plugin.close().closed, {})
  equal(plugin.close_others().closed, {})
  equal(plugin.close_many({ working }, { tab = view.tabpage }).closed, {})
  equal(plugin.close_tab().tab_closed, false)
  equal(api.nvim_tabpage_list_wins(view.tabpage), windows)
  equal(vim.tbl_map(api.nvim_win_get_buf, windows), before)
end)

for _, kind in ipairs({ "working", "staged" }) do
  test("gf from " .. kind .. " opens the local file in the previous ordinary tab safely", function()
    local original = edit("original.txt")
    local normal = api.nvim_get_current_tabpage()
    vim.bo[original].bufhidden, vim.bo[original].modified = "wipe", true
    local view = open_view()
    local preview = select_file(view, kind)
    local path = view.cur_entry.absolute_path
    local count = #api.nvim_list_tabpages()
    mapping("gf")
    drain()
    local opened = api.nvim_get_current_buf()
    equal(api.nvim_get_current_tabpage(), normal)
    equal(api.nvim_buf_get_name(opened), path)
    equal(vim.bo[opened].buftype, "")
    equal(plugin.buffers(normal), { original, opened })
    equal(plugin.buffers(view.tabpage), {})
    equal(#api.nvim_list_tabpages(), count)
    equal(api.nvim_buf_is_valid(original), true)
    equal(vim.bo[original].modified, true)
    equal(vim.bo[original].bufhidden, "wipe")
    equal(vim.wo.diff, false)
    equal(vim.wo.winfixbuf, false)
    diffview.close(view.tabpage, { force = false })
    drain()
    equal(api.nvim_buf_is_valid(opened), true)
    equal(plugin.contains(opened, normal), true)
    if kind == "working" then
      equal(preview, opened)
    end
  end)
end

test("gf from the file panel preserves a special-only destination and creates a working split", function()
  local normal = api.nvim_get_current_tabpage()
  local tree = api.nvim_create_buf(false, true)
  api.nvim_set_current_buf(tree)
  local source = api.nvim_get_current_win()
  local view = open_view()
  select_file(view, "staged")
  view.panel:focus()
  view.panel:highlight_file(view.cur_entry)
  mapping("gf")
  drain()
  equal(api.nvim_get_current_tabpage(), normal)
  equal(api.nvim_win_get_buf(source), tree)
  equal(#api.nvim_tabpage_list_wins(normal), 2)
  equal(api.nvim_buf_get_name(0), fixture .. "/staged.txt")
  equal(vim.wo.diff, false)
end)

test("Ctrl-w gf always opens a new managed tab without inheriting diff options", function()
  edit("original.txt")
  local normal = api.nvim_get_current_tabpage()
  local view = open_view()
  select_file(view, "working")
  local count = #api.nvim_list_tabpages()
  mapping("<C-w>gf")
  drain()
  local target = api.nvim_get_current_tabpage()
  assert(target ~= normal and target ~= view.tabpage)
  equal(#api.nvim_list_tabpages(), count + 1)
  equal(plugin.buffers(target), { api.nvim_get_current_buf() })
  equal(vim.wo.diff, false)
  equal(vim.wo.winfixbuf, false)
end)

test("gf creates an ordinary tab if only the review tab remains", function()
  local view = open_view()
  select_file(view, "staged")
  vim.cmd("tabonly!")
  drain()
  equal(#api.nvim_list_tabpages(), 1)
  mapping("gf")
  drain()
  local normal = api.nvim_get_current_tabpage()
  assert(normal ~= view.tabpage)
  equal(#api.nvim_list_tabpages(), 2)
  equal(api.nvim_buf_get_name(0), fixture .. "/staged.txt")
  equal(plugin.buffers(normal), { api.nvim_get_current_buf() })
  equal(vim.wo.diff, false)
end)

test("closing Diffview preserves a normal tab's hidden member and its position", function()
  local working = edit("working.txt")
  local original = edit("original.txt")
  local normal = api.nvim_get_current_tabpage()
  local view = open_view()
  equal(select_file(view, "working"), working)
  diffview.close(nil, { force = false })
  drain()
  equal(api.nvim_get_current_tabpage(), normal)
  equal(api.nvim_buf_is_valid(working), true)
  equal(plugin.buffers(normal), { working, original })
end)

test("native tabclose does not turn reviewed files into owned orphans", function()
  local original = edit("original.txt")
  local normal = api.nvim_get_current_tabpage()
  local view = open_view()
  local working = select_file(view, "working")
  vim.bo[working].modified = true
  vim.cmd("tabclose!")
  drain()
  equal(api.nvim_buf_is_valid(working), true)
  equal(vim.bo[working].modified, true)
  equal(plugin.buffers(normal), { original })
  equal(plugin.owners(working), {})
end)

test("gf skips another Diffview tab when finding an ordinary destination", function()
  edit("original.txt")
  local normal = api.nvim_get_current_tabpage()
  local first = open_view()
  select_file(first, "working")
  local second = open_view({ "--cached" })
  select_file(second, #second.files.working > 0 and "working" or "staged")
  api.nvim_set_current_tabpage(first.tabpage)
  select_file(first, "working")
  mapping("gf")
  drain()
  equal(api.nvim_get_current_tabpage(), normal)
  equal(#api.nvim_list_tabpages(), 3)
  equal(plugin.buffers(first.tabpage), {})
  equal(plugin.buffers(second.tabpage), {})
end)

test("gf from a staged revision opens current working-tree text", function()
  vim.fn.writefile({ "additional working changes" }, fixture .. "/staged.txt")
  edit("original.txt")
  local view = open_view()
  local stage = select_file(view, "staged")
  equal(api.nvim_buf_get_lines(stage, 0, -1, false), { "staged change" })
  mapping("gf")
  equal(api.nvim_buf_get_lines(0, 0, -1, false), { "additional working changes" })
  equal(plugin.owners(stage), {})
end)

test("gf refuses a deleted local file without creating a tab or changing focus", function()
  edit("original.txt")
  local view = open_view()
  select_file(view, "working")
  vim.fn.delete(view.cur_entry.absolute_path)
  local win, count = api.nvim_get_current_win(), #api.nvim_list_tabpages()
  local opened, err = integration.goto_file()
  equal(opened, nil)
  assert(err and err:find("does not exist", 1, true))
  equal(api.nvim_get_current_win(), win)
  equal(#api.nvim_list_tabpages(), count)
  equal(#notices, 1)
end)

test("navigation callback preserves native gf behavior outside Diffview", function()
  vim.fn.writefile({ "target.txt" }, fixture .. "/working.txt")
  local working = edit("working.txt")
  local normal = api.nvim_get_current_tabpage()
  local view = open_view()
  equal(select_file(view, "working"), working)
  api.nvim_set_current_tabpage(normal)
  api.nvim_win_set_cursor(0, { 1, 0 })
  integration.goto_file()
  drain()
  equal(api.nvim_get_current_tabpage(), normal)
  equal(api.nvim_buf_get_name(0), fixture .. "/target.txt")
  equal(plugin.contains(api.nvim_get_current_buf(), normal), true)
end)

test("closing a normal member displayed in Diffview preserves both layouts and reports the reference", function()
  local working = edit("working.txt")
  local normal = api.nvim_get_current_tabpage()
  local view = open_view()
  equal(select_file(view, "working"), working)
  local windows = api.nvim_tabpage_list_wins(view.tabpage)
  local before = vim.tbl_map(api.nvim_win_get_buf, windows)
  api.nvim_set_current_tabpage(normal)
  local report = plugin.close()
  equal(report.closed, {})
  equal(#report.failed, 1)
  equal(plugin.contains(working, normal), true)
  equal(api.nvim_buf_is_valid(working), true)
  equal(vim.tbl_map(api.nvim_win_get_buf, windows), before)
end)

test("file history is also an excluded view and gf opens its local file", function()
  edit("original.txt")
  local normal = api.nvim_get_current_tabpage()
  diffview.file_history(nil, { "working.txt" })
  local view = views[#views]
  assert(view)
  assert(
    vim.wait(10000, function()
      return view.ready
        and #view.panel.entries > 0
        and view.panel:cur_file()
        and view.cur_layout:get_main_win().file:is_valid()
    end, 10),
    "file history timed out"
  )
  api.nvim_set_current_win(view.cur_layout:get_main_win().id)
  drain()
  equal(plugin.buffers(view.tabpage), {})
  mapping("gf")
  drain()
  equal(api.nvim_get_current_tabpage(), normal)
  equal(api.nvim_buf_get_name(0), fixture .. "/working.txt")
  equal(api.nvim_buf_get_lines(0, 0, -1, false), { "working change" })
  equal(plugin.contains(api.nvim_get_current_buf(), normal), true)
end)

test("host Diffview configuration wires exclusion and safe navigation", function()
  local host = root
  for _ = 1, 4 do
    host = vim.fs.dirname(host)
  end
  vim.opt.rtp:append(host)
  local setup = diffview.setup
  -- Intentional interception of the installed dependency during host-config verification.
  ---@diagnostic disable-next-line: duplicate-set-field
  diffview.setup = function(options)
    local observe = options.hooks.view_opened
    options.hooks.view_opened = function(view)
      views[#views + 1] = view
      observe(view)
    end
    options.use_icons, options.watch_index = false, false
    setup(options)
  end
  local ok, err = pcall(dofile, host .. "/lua/configs/diffview.lua")
  diffview.setup = setup
  assert(ok, err)
  edit("original.txt")
  local normal = api.nvim_get_current_tabpage()
  local view = open_view()
  select_file(view, "working")
  equal(plugin.buffers(view.tabpage), {})
  mapping("gf")
  drain()
  equal(api.nvim_get_current_tabpage(), normal)
  equal(api.nvim_buf_get_name(0), fixture .. "/working.txt")
  equal(plugin.contains(api.nvim_get_current_buf(), normal), true)
end)

test("dirty index buffers remain Diffview-owned and guarded by DiffviewClose", function()
  edit("original.txt")
  local view = open_view()
  local stage = select_file(view, "staged")
  vim.bo[stage].modified = true
  equal(plugin.close_many({ stage }, { force = true }).closed, {})
  diffview.close(nil, { force = false })
  drain()
  equal(api.nvim_tabpage_is_valid(view.tabpage), true)
  equal(api.nvim_buf_is_valid(stage), true)
  equal(vim.bo[stage].modified, true)
  equal(plugin.owners(stage), {})
end)

local failed = 0
for _, entry in ipairs(tests) do
  local ok, err = xpcall(function()
    reset()
    entry.run()
  end, debug.traceback)
  if ok then
    print("ok - " .. entry.name)
  else
    failed = failed + 1
    io.stderr:write("FAIL - " .. entry.name .. "\n" .. err .. "\n")
  end
end
reset()
plugin.teardown()
vim.cmd.cd(original_cwd)
vim.fn.delete(fixture, "rf")
vim.notify = real_notify
print(string.format("%d tests, %d failures", #tests, failed))
if failed > 0 then
  vim.cmd("cquit 1")
end
