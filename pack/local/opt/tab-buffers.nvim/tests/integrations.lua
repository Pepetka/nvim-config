-- nvim --clean --headless -i NONE -l tests/integrations.lua
-- Requires the installed fzf-lua and fzf; never installs dependencies.
local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
vim.opt.packpath:append(vim.fn.stdpath("data") .. "/site")
vim.o.swapfile = false
vim.o.columns, vim.o.lines = 160, 50
vim.cmd.packadd("fzf-lua")
local api = vim.api
local plugin = require("tab_buffers")
local line = require("tab_buffers.tabline")
local picker = require("tab_buffers.integrations.fzf")
local fzf = require("fzf-lua")
local fzf_bin = vim.fn.exepath("fzf")
assert(fzf_bin ~= "", "integration tests require fzf on PATH")
local original_exec = fzf.fzf_exec
local notify = vim.notify
local tests, notices, sequence = {}, {}, 0
vim.notify = function(message)
  notices[#notices + 1] = message
end

local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end

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

local function file(name)
  sequence = sequence + 1
  local buf = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(buf, "/private/tmp/tab-buffers-integrations/" .. sequence .. "/" .. (name or "file.lua"))
  api.nvim_buf_set_lines(buf, 0, -1, false, { "content" })
  vim.bo[buf].modified = false
  return buf
end

local function show(buf)
  api.nvim_set_current_buf(buf)
  drain()
end

local function reset()
  fzf.fzf_exec = original_exec
  fzf.win.close()
  line.teardown()
  plugin.teardown()
  vim.o.hidden, vim.o.confirm = true, false
  for _, buf in ipairs(api.nvim_list_bufs()) do
    vim.bo[buf].modified, vim.bo[buf].bufhidden = false, ""
  end
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_config(win).relative ~= "" then
      api.nvim_win_close(win, true)
    end
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
  fzf.setup({ { "fzf-native", "hide" }, fzf_bin = fzf_bin })
  drain()
  notices = {}
end

local function test(name, fn)
  tests[#tests + 1] = { name = name, run = fn }
end

local function line_entries()
  drain()
  local result = {}
  for highlight, token, text in line.render():gmatch("%%#TabBuffers(%w+)#%%(%d+)@[^@]+@(.-)%%X") do
    if highlight ~= "Tab" and highlight ~= "TabActive" then
      result[#result + 1] = { token = tonumber(token), text = text:gsub("%%%%", "%%") }
    end
  end
  return result
end

local function render()
  api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true })
  local labels = require("tab_buffers.tabline.layout").labels(vim.tbl_map(function(buf)
    return { id = buf, name = api.nvim_buf_get_name(buf) }
  end, plugin.buffers()))
  local result = {}
  for _, entry in ipairs(line_entries()) do
    local found
    for buf, label in pairs(labels) do
      if entry.text:find(label, 1, true) then
        found = buf
        break
      end
    end
    assert(found, "unexpected rendered buffer: " .. entry.text)
    result[#result + 1] = found
  end
  return result
end

local function capture_line()
  line.setup({ icons = false })
  local function click(buf, button)
    local labels = require("tab_buffers.tabline.layout").labels(vim.tbl_map(function(id)
      return { id = id, name = api.nvim_buf_get_name(id) }
    end, plugin.buffers()))
    for _, entry in ipairs(line_entries()) do
      if labels[buf] and entry.text:find(labels[buf], 1, true) then
        line.click(entry.token, 1, button, "    ")
        return
      end
    end
  end
  return {
    left_mouse_command = function(buf)
      click(buf, "l")
    end,
    close_command = function(buf)
      click(buf, "m")
    end,
    right_mouse_command = function() end,
  }
end

local function capture_picker()
  local contents, options
  fzf.fzf_exec = function(generator, opts)
    contents, options = generator, opts
  end
  picker.buffers({ file_icons = false })
  fzf.fzf_exec = original_exec
  local function entries()
    local rows, done = {}, false
    contents(function(row)
      if row then
        rows[#rows + 1] = row
      else
        done = true
      end
    end)
    assert(vim.wait(1000, function()
      return done
    end, 1))
    return rows
  end
  return entries, options, contents
end

local function ids(entries)
  return vim.tbl_map(function(entry)
    return tonumber(entry:match("^%[(%d+)%]"))
  end, entries)
end

test("excluded review tabs have no tabline or scoped picker entries", function()
  local a = file("ordinary.lua")
  show(a)
  plugin.setup()
  local normal = api.nvim_get_current_tabpage()
  vim.cmd.tabnew()
  local preview = file("review.lua")
  show(preview)
  vim.t.tab_buffers_excluded = true
  api.nvim_exec_autocmds("User", { pattern = "TabBuffersContextChanged", modeline = false })
  drain()
  line.setup({})
  equal(render(), {})
  local entries = capture_picker()
  equal(entries(), {})
  api.nvim_set_current_tabpage(normal)
  equal(render(), { a })
  entries = capture_picker()
  equal(ids(entries()), { a })
  equal(plugin.owners(preview), {})
end)

test("tabline renders independent orders and hidden shared members in each tab", function()
  local a, b, c = file("a.lua"), file("b.lua"), file("c.lua")
  show(a)
  plugin.setup()
  local first = api.nvim_get_current_tabpage()
  vim.cmd("tabnew")
  show(c)
  plugin.add(a)
  local second = api.nvim_get_current_tabpage()
  plugin.reorder({ c, a })
  line.setup({ icons = false })
  equal(render(), { c, a })
  api.nvim_set_current_tabpage(first)
  plugin.reorder({ b, a, c })
  equal(render(), { b, a, c })
  plugin.move_to(1, { buf = a })
  equal(render(), { a, b, c })
  api.nvim_set_current_tabpage(second)
  equal(render(), { c, a })
  plugin.sort("name")
  equal(render(), { a, c })
end)

test("tabline visibility counts scoped buffers and real tabs", function()
  local a = file()
  show(a)
  plugin.setup()
  line.setup()
  equal(render(), { a })
  equal(vim.o.showtabline, 0)
  local unowned = file()
  drain()
  equal(vim.o.showtabline, 0)
  plugin.add(unowned)
  render()
  equal(vim.o.showtabline, 2)
  plugin.close({ buf = unowned })
  render()
  equal(vim.o.showtabline, 0)
  vim.cmd("tabnew")
  render()
  equal(vim.o.showtabline, 2)
end)

test("tabline callbacks preserve the source tab and use safe membership closure", function()
  local a, b = file(), file()
  show(a)
  plugin.setup()
  local first = api.nvim_get_current_tabpage()
  local options = capture_line()
  vim.cmd("tabnew")
  show(b)
  local second = api.nvim_get_current_tabpage()
  api.nvim_set_current_tabpage(first)
  options.close_command(b)
  api.nvim_set_current_tabpage(second)
  drain()
  equal(plugin.contains(b, first), false)
  equal(plugin.contains(b, second), true)
  equal(api.nvim_buf_is_valid(b), true)
  vim.bo[b].modified = true
  options.close_command(b)
  drain()
  equal(plugin.contains(b, second), true)
  equal(#notices, 1)
  options.right_mouse_command(a) -- foreign in this tab: no-op.
  drain()
  equal(plugin.contains(a, first), true)
end)

test("tabline selection from a tree preserves the tree and stale clicks do nothing", function()
  local a, b = file(), file()
  show(a)
  plugin.setup()
  local options = capture_line()
  local tree = api.nvim_create_buf(false, true)
  api.nvim_set_current_buf(tree)
  local source = api.nvim_get_current_win()
  options.left_mouse_command(b)
  drain()
  equal(api.nvim_win_get_buf(source), tree)
  equal(api.nvim_get_current_buf(), b)
  options.left_mouse_command(a)
  plugin.close({ buf = a })
  drain()
  equal(api.nvim_get_current_buf(), b)
end)

test("tabline setup is repeatable and teardown cancels clicks and restores configuration", function()
  local a, b = file(), file()
  show(a)
  plugin.setup()
  local old_line, old_visibility = vim.o.tabline, vim.o.showtabline
  local options = capture_line()
  local count = #api.nvim_get_autocmds({ group = "TabBuffersTabline" })
  line.setup({ icons = false })
  equal(#api.nvim_get_autocmds({ group = "TabBuffersTabline" }), count)
  options.close_command(b)
  line.teardown()
  drain()
  equal(api.nvim_buf_is_valid(b), true)
  equal(vim.o.tabline, old_line)
  equal(vim.o.showtabline, old_visibility)
  equal(line.teardown(), false)
end)

test("fzf contents match model order, include unnamed buffers and rebuild for the current tab", function()
  local a, b = file("a [123].lua"), file("b.lua")
  show(a)
  plugin.setup()
  plugin.reorder({ b, a })
  local entries, options = capture_picker()
  equal(ids(entries()), { b, a })
  equal(options.no_hide, true)
  equal(options.fzf_opts["--header-lines"], 0)
  plugin.move_to(1, { buf = a })
  equal(ids(entries()), { a, b })
  vim.cmd("tabnew")
  local unnamed = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(unnamed, 0, -1, false, { "draft" })
  local rows = entries()
  equal(ids(rows), { unnamed })
  assert(rows[1]:find("[No Name]", 1, true))
  assert(rows[1]:find("+", 1, true))
end)

test("fzf actions use the captured tab and reject detached or expired selections", function()
  local a, b = file(), file()
  show(a)
  plugin.setup()
  local first = api.nvim_get_current_tabpage()
  local entries, options = capture_picker()
  local rows = entries()
  vim.cmd("tabnew")
  show(a)
  local second = api.nvim_get_current_tabpage()
  options.actions["ctrl-x"].fn(rows)
  equal(api.nvim_tabpage_is_valid(first), false)
  equal(plugin.owners(a), { second })
  equal(api.nvim_buf_is_valid(b), false)
  options.actions.default(rows)
  equal(api.nvim_get_current_tabpage(), second)
  equal(api.nvim_get_current_buf(), a)
  equal(ids(entries()), { a })
end)

for _, key in ipairs({ "default", "ctrl-s", "ctrl-v" }) do
  test("fzf " .. key .. " opens into working windows and preserves the tree", function()
    local a = file()
    show(a)
    plugin.setup()
    local tree = api.nvim_create_buf(false, true)
    api.nvim_set_current_buf(tree)
    local source = api.nvim_get_current_win()
    local entries, options = capture_picker()
    options.actions[key](entries())
    equal(api.nvim_get_current_buf(), a)
    equal(api.nvim_win_get_buf(source), tree)
    equal(#api.nvim_tabpage_list_wins(0), 2)
  end)
end

test("fzf multi-close uses one report and never discards modified exclusive text", function()
  local a, b, c = file(), file(), file()
  show(a)
  plugin.setup()
  local entries, options = capture_picker()
  local rows = entries()
  vim.bo[b].modified = true
  options.actions["ctrl-x"].fn(rows)
  equal(plugin.buffers(), { b })
  equal(api.nvim_buf_is_valid(a), false)
  equal(api.nvim_buf_is_valid(c), false)
  equal(ids(entries()), { b })
  equal(#notices, 1)
  equal(options.actions["ctrl-x"].reload, true)
end)

test("fzf contents can be requested from a fast callback", function()
  local a = file()
  show(a)
  plugin.setup()
  local _, _, contents = capture_picker()
  local rows, done, was_fast = {}, false, false
  local timer = vim.uv.new_timer()
  timer:start(0, 0, function()
    was_fast = vim.in_fast_event()
    timer:stop()
    timer:close()
    contents(function(row)
      if row then
        rows[#rows + 1] = row
      else
        done = true
      end
    end)
  end)
  assert(vim.wait(1000, function()
    return done
  end, 1))
  equal(was_fast, true)
  equal(ids(rows), { a })
end)

test("real fzf launch and resume rebuild the current tab and execute scoped actions", function()
  local a, b = file("first.lua"), file("second.lua")
  show(a)
  plugin.setup()
  picker.buffers({
    previewer = false,
    file_icons = false,
    query = "second.lua",
    fzf_opts = { ["--filter"] = "second.lua" },
  })
  assert(
    vim.wait(10000, function()
      return api.nvim_get_current_buf() == b
    end, 10),
    "fzf selection timed out"
  )
  vim.cmd("tabnew")
  local c = file("second.lua")
  show(c)
  local d = file("third.lua")
  show(d)
  local second = api.nvim_get_current_tabpage()
  fzf.resume()
  assert(
    vim.wait(10000, function()
      return api.nvim_get_current_buf() == c
    end, 10),
    "fzf resume timed out"
  )
  equal(api.nvim_get_current_tabpage(), second)
  equal(api.nvim_get_current_buf(), c)
  equal(plugin.buffers(second), { c, d })
  equal(fzf.get_last_query(), "second.lua")
end)

test("real fzf preview reads the hidden buffer and Enter preserves destructive bufhidden", function()
  local a, b = file("first.lua"), file("second.lua")
  api.nvim_buf_set_lines(b, 0, -1, false, { "actual preview content" })
  vim.bo[b].modified = false
  show(a)
  plugin.setup()
  vim.bo[a].bufhidden, vim.bo[a].modified = "wipe", true
  picker.buffers({ file_icons = false, query = "second" })
  local channel
  assert(
    vim.wait(10000, function()
      local preview = false
      for _, win in ipairs(api.nvim_list_wins()) do
        if api.nvim_win_get_config(win).relative ~= "" then
          local buf = api.nvim_win_get_buf(win)
          if vim.bo[buf].buftype == "terminal" then
            channel = vim.bo[buf].channel
          elseif vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), { "actual preview content" }) then
            preview = true
          end
        end
      end
      return channel and preview
    end, 10),
    "buffer preview timed out"
  )
  api.nvim_chan_send(channel, "\r")
  assert(
    vim.wait(10000, function()
      return api.nvim_get_current_buf() == b
    end, 10),
    "Enter timed out"
  )
  equal(api.nvim_buf_is_valid(a), true)
  equal(vim.bo[a].modified, true)
  equal(vim.bo[a].bufhidden, "wipe")
end)

test("real fzf Ctrl-X safely deletes and reloads while the picker stays open", function()
  local a, b = file("first.lua"), file("second.lua")
  show(a)
  plugin.setup()
  picker.buffers({ previewer = false, file_icons = false, query = "second" })
  local channel, popup, terminal
  assert(
    vim.wait(10000, function()
      for _, win in ipairs(api.nvim_list_wins()) do
        local buf = api.nvim_win_get_buf(win)
        if api.nvim_win_get_config(win).relative ~= "" and vim.bo[buf].buftype == "terminal" then
          channel, popup, terminal = vim.bo[buf].channel, win, buf
          return true
        end
      end
      return false
    end, 10),
    "fzf popup timed out"
  )
  assert(
    vim.wait(10000, function()
      return table.concat(api.nvim_buf_get_lines(terminal, 0, -1, false), "\n"):find("second.lua", 1, true)
    end, 10),
    "initial results timed out"
  )
  api.nvim_chan_send(channel, "\24")
  assert(
    vim.wait(10000, function()
      return not api.nvim_buf_is_valid(b)
    end, 10),
    "Ctrl-X timed out"
  )
  equal(plugin.buffers(), { a })
  equal(api.nvim_win_is_valid(popup), true)
  -- The reloaded list contains a; clear the query and select it.
  api.nvim_chan_send(channel, "\21")
  assert(
    vim.wait(10000, function()
      return table.concat(api.nvim_buf_get_lines(terminal, 0, -1, false), "\n"):find("first.lua", 1, true)
    end, 10),
    "reloaded results timed out"
  )
  api.nvim_chan_send(channel, "\r")
  assert(
    vim.wait(10000, function()
      return api.nvim_get_current_buf() == a
    end, 10),
    "reload selection timed out"
  )
  equal(api.nvim_buf_is_valid(a), true)
end)

test("host buffer mappings delegate to the scoped API and preserve order", function()
  local host = root
  for _ = 1, 4 do
    host = vim.fs.dirname(host)
  end
  if vim.fn.filereadable(host .. "/lua/configs/tab_buffers.lua") == 0 then
    return -- Standalone checkouts do not include personal configuration.
  end
  vim.opt.rtp:prepend(host)
  dofile(host .. "/lua/mappings.lua")
  dofile(host .. "/lua/configs/tab_buffers.lua")
  local a, b = file(), file()
  show(a)
  plugin.add(b)
  local function mapping(lhs)
    local value = vim.fn.maparg(lhs, "n", false, true)
    assert(type(value.callback) == "function" and #value.desc > 0, "missing described callback: " .. lhs)
    value.callback()
  end
  mapping("<Tab>")
  equal(api.nvim_get_current_buf(), b)
  mapping("<leader>bh")
  equal(plugin.buffers(), { b, a })
  mapping("<S-Tab>")
  equal(api.nvim_get_current_buf(), a)
  mapping("<leader>bl")
  equal(plugin.buffers(), { b, a })
  mapping("<leader>cx")
  equal(plugin.buffers(), { a })
  mapping("<leader>x")
  equal(plugin.buffers(), {})
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
vim.notify = notify
print(string.format("%d tests, %d failures", #tests, failed))
if failed > 0 then
  vim.cmd("cquit 1")
end
