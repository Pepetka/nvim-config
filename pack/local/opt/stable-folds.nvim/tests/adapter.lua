local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/site")
vim.opt.packpath:append(vim.fn.stdpath("data") .. "/site")
vim.cmd.packadd("nvim-treesitter")
package.path = root .. "/tests/?.lua;" .. package.path
vim.o.swapfile = false
local t = require("support")
local integration = require("stable_folds.integrations.nvim")
local treesitter = require("stable_folds.integrations.treesitter")
local ranges = require("stable_folds.core.ranges")
local api = vim.api

---@param lang string
---@param name string
local function restore_query(lang, name)
  local content = {}
  for _, file in ipairs(vim.treesitter.query.get_files(lang, name)) do
    content[#content + 1] = table.concat(vim.fn.readfile(file), "\n")
  end
  vim.treesitter.query.set(lang, name, table.concat(content, "\n"))
end

---@param lines? string[]
---@return integer
local function buffer(lines)
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "lua"
  api.nvim_buf_set_lines(buf, 0, -1, false, lines or { "local function f()", "  local a = 1", "  return a", "end" })
  return buf
end

---@return StableFoldsCallbacks, string[]
local function callbacks()
  local events = {}
  return {
    reading = function(buf)
      events[#events + 1] = "reading:" .. buf
    end,
    unloaded = function(buf)
      events[#events + 1] = "unloaded:" .. buf
    end,
    changed = function(buf)
      events[#events + 1] = "changed:" .. buf
    end,
    entered = function(buf)
      events[#events + 1] = "entered:" .. buf
    end,
    reset = function(buf)
      events[#events + 1] = "reset:" .. buf
    end,
    deleted = function(buf)
      events[#events + 1] = "deleted:" .. buf
    end,
    closed = function(win)
      events[#events + 1] = "closed:" .. win
    end,
    updated = function()
      events[#events + 1] = "updated"
    end,
  },
    events
end

t.test("native contexts resolve current, explicit and invalid windows and buffers", function()
  local adapter = integration.new()
  local buf = buffer()
  local win = api.nvim_get_current_win()
  local context = assert(adapter.context())
  t.equal(context.buf, buf)
  t.equal(context.win, win)
  t.equal(context.lang, "lua")
  t.equal(context.tick, api.nvim_buf_get_changedtick(buf))
  t.equal(adapter.context(0), context)
  t.equal(adapter.context(win), context)
  t.equal(adapter.context(-1), nil)
  t.equal(adapter.buffer(0), buf)
  t.equal(adapter.buffer(-1), nil)
  t.equal(adapter.lines(buf)[1], "local function f()")
  adapter.uninstall()
end)

t.test("native extmark transactions move and remove only owned identities", function()
  local first, second = integration.new(), integration.new()
  local buf = buffer()
  local one = first.apply_marks(buf, { marks = { { line = 1, header = "f", new = false } }, delete = {} })
  local two = second.apply_marks(buf, { marks = { { line = 1, header = "f", new = false } }, delete = {} })
  api.nvim_buf_set_lines(buf, 0, 0, false, { "-- shifted" })
  t.equal(first.positions(buf, one)[1].line, 2)
  first.clear(buf)
  t.equal(first.positions(buf, one)[1].line, nil)
  t.equal(second.positions(buf, two)[1].line, 2)
  second.apply_marks(buf, { marks = {}, delete = { two[1].id } })
  t.equal(second.positions(buf, two)[1].line, nil)
  first.uninstall()
  second.uninstall()
end)

t.test("uninstall removes marks even when the controller did not explicitly clear", function()
  local adapter = integration.new()
  local buf = buffer()
  local marks = adapter.apply_marks(buf, { marks = { { line = 1, header = "f", new = true } }, delete = {} })
  adapter.uninstall()
  adapter.uninstall()
  t.equal(adapter.positions(buf, marks)[1].line, nil)
  api.nvim_buf_delete(buf, { force = true })
  adapter.clear(buf)
end)

t.test("repeated registration does not multiply handlers and instances are independent", function()
  local first, second = integration.new(), integration.new()
  local one, events = callbacks()
  local two, other = callbacks()
  local buf = buffer()
  first.install(one)
  first.install(one)
  second.install(two)
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  t.equal(events, { "changed:" .. buf })
  t.equal(other, { "changed:" .. buf })
  first.uninstall()
  api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
  t.equal(#events, 1)
  t.equal(#other, 2)
  second.uninstall()
end)

t.test("callbacks dispatch window, buffer, query and option lifecycle events", function()
  local adapter = integration.new()
  local handler, events = callbacks()
  local buf = buffer()
  adapter.install(handler)
  for _, event in ipairs({
    "TextChanged",
    "TextChangedI",
    "TextChangedP",
    "InsertLeave",
    "BufWritePost",
    "BufReadPre",
    "BufReadPost",
    "BufWinEnter",
    "FileType",
    "BufUnload",
    "BufWipeout",
  }) do
    api.nvim_exec_autocmds(event, { buffer = buf })
  end
  api.nvim_exec_autocmds("WinClosed", { pattern = "123" })
  api.nvim_exec_autocmds("OptionSet", { pattern = "foldminlines" })
  api.nvim_exec_autocmds("OptionSet", { pattern = "foldnestmax" })
  api.nvim_exec_autocmds("User", { pattern = "TSUpdate" })
  t.equal(events, {
    "changed:" .. buf,
    "changed:" .. buf,
    "changed:" .. buf,
    "changed:" .. buf,
    "changed:" .. buf,
    "reading:" .. buf,
    "changed:" .. buf,
    "entered:" .. buf,
    "reset:" .. buf,
    "unloaded:" .. buf,
    "deleted:" .. buf,
    "closed:123",
    "changed:" .. buf,
    "changed:" .. buf,
    "updated",
  })
  adapter.uninstall()
end)

t.test("uninstall preserves foreign handlers added to the same group", function()
  local adapter = integration.new()
  local handler = callbacks()
  adapter.install(handler)
  local group
  for name in pairs(api.nvim_get_namespaces()) do
    if name:match("^StableFoldStarts") then
      -- Namespace suffix and augroup suffix belong to the same adapter instance.
      local suffix = name:sub(#"StableFoldStarts" + 1)
      local ok, entries = pcall(api.nvim_get_autocmds, { group = "SynchronousFolds" .. suffix })
      if ok and #entries > 0 then
        group = entries[1].group
      end
    end
  end
  assert(group)
  local calls = 0
  local foreign = api.nvim_create_autocmd("User", {
    group = group,
    pattern = "ForeignFoldTest",
    callback = function()
      calls = calls + 1
    end,
  })
  adapter.uninstall()
  api.nvim_exec_autocmds("User", { pattern = "ForeignFoldTest" })
  t.equal(calls, 1)
  api.nvim_del_autocmd(foreign)
  api.nvim_del_augroup_by_id(group)
end)

t.test("registration failure rolls back every already-created handler", function()
  local adapter = integration.new()
  local handler, events = callbacks()
  local original, count = api.nvim_create_autocmd, 0
  ---@diagnostic disable-next-line: duplicate-set-field
  api.nvim_create_autocmd = function(...)
    count = count + 1
    if count == 3 then
      error("registration failed")
    end
    return original(...)
  end
  local ok = pcall(adapter.install, handler)
  api.nvim_create_autocmd = original
  t.equal(ok, false)
  api.nvim_exec_autocmds("TextChanged", { buffer = buffer() })
  t.equal(events, {})
  adapter.install(handler)
  adapter.uninstall()
end)

t.test("Tree-sitter extraction returns plain ranges and handles missing languages", function()
  local buf = buffer()
  t.equal(ranges.normalize(assert(treesitter.collect(buf, "lua")), 4), { { start = 1, stop = 4 } })
  t.equal(ranges.normalize(assert(treesitter.collect(buf, "lua", false)), 4), { { start = 1, stop = 4 } })
  t.equal(treesitter.collect(buf, nil), nil)
  t.equal(treesitter.collect(buf, "stable_folds_missing_parser"), nil)
end)

t.test("fold queries respect metadata offsets and quantified captures", function()
  local buf = buffer({ "local a = 1", "local b = 2", "local c = 3", "local d = 4" })
  vim.treesitter.query.set("lua", "folds", "((chunk (variable_declaration)+ @fold) (#offset! @fold 0 0 0 0))")
  local result = ranges.normalize(assert(treesitter.collect(buf, "lua")), 4)
  t.equal(result, { { start = 1, stop = 4 } })
  vim.treesitter.query.set("lua", "folds", "((chunk) @fold (#offset! @fold 1 0 -1 0))")
  result = ranges.normalize(assert(treesitter.collect(buf, "lua")), 4)
  t.equal(result, { { start = 2, stop = 3 } })
  restore_query("lua", "folds")
end)

t.test("injected language folds are collected together with the host tree", function()
  vim.treesitter.query.set(
    "lua",
    "injections",
    [[
    ((string content: (string_content) @injection.content)
      (#set! injection.language "json"))
  ]]
  )
  vim.treesitter.query.set("json", "folds", "(object) @fold")
  local buf = buffer({ "local json = [[{", '  "a": {', '    "b": 1', "  }", "}]]" })
  local result = ranges.normalize(assert(treesitter.collect(buf, "lua")), 5)
  t.equal(result, { { start = 1, stop = 5 }, { start = 2, stop = 4 } })
  -- Previously parsed injections must also be excluded when the option changes.
  local host_only = ranges.normalize(assert(treesitter.collect(buf, "lua", false)), 5)
  t.equal(host_only, {})
  restore_query("lua", "injections")
  restore_query("json", "folds")
end)

t.test("buffer watchers run before extmarks shift and can be replaced or cancelled", function()
  local adapter = integration.new()
  local buf = buffer()
  local parser = assert(vim.treesitter.get_parser(buf, "lua"))
  parser:parse(true)
  local marks = adapter.apply_marks(buf, { marks = { { line = 1, header = "f", new = false } }, delete = {} })
  local observed = {}
  local first = adapter.watch(buf, function()
    observed[#observed + 1] = assert(adapter.positions(buf, marks)[1].line)
  end)
  api.nvim_buf_set_lines(buf, 0, 0, false, { "-- shifted" })
  t.equal(observed, { 1 })
  t.equal(adapter.positions(buf, marks)[1].line, 2)
  local second = adapter.watch(buf, function()
    observed[#observed + 1] = 99
  end)
  first()
  api.nvim_buf_set_lines(buf, 0, 0, false, { "-- shifted again" })
  t.equal(observed, { 1, 99 })
  second()
  api.nvim_buf_set_lines(buf, 0, 0, false, { "-- cancelled" })
  t.equal(observed, { 1, 99 })
  adapter.watch(buf, function()
    observed[#observed + 1] = 100
  end)
  adapter.uninstall()
  api.nvim_buf_set_lines(buf, 0, 0, false, { "-- uninstalled" })
  t.equal(observed, { 1, 99 })
  -- Cancelling the fold listener must not detach Neovim's Tree-sitter listener.
  assert(vim.treesitter.get_parser(buf, "lua") == parser)
  t.equal(parser:is_valid(), false)
  t.equal(#parser:parse(true), 1)
end)

t.test("buffer watch failures leave no unusable watcher registration", function()
  local adapter = integration.new()
  local invalid = api.nvim_create_buf(true, false)
  api.nvim_buf_delete(invalid, { force = true })
  t.equal(pcall(adapter.watch, invalid, function() end), false)
  t.equal(pcall(adapter.watch, invalid, function() end), false)
  local buf = buffer()
  local calls = 0
  adapter.watch(buf, function()
    calls = calls + 1
  end)
  api.nvim_buf_set_lines(buf, 0, 0, false, { "-- edit" })
  t.equal(calls, 1)
  adapter.uninstall()
end)

t.test("closed-state inspection includes hidden children and restores options, folds and cursor", function()
  local adapter = integration.new()
  buffer({ "outer", "inner", "content", "end inner", "content", "end outer" })
  vim.wo.foldmethod = "manual"
  vim.wo.foldminlines = 1
  vim.wo.foldnestmax = 3
  vim.wo.foldlevel = 99
  vim.cmd("1,6fold")
  vim.cmd("normal! zR")
  vim.cmd("2,4fold")
  vim.cmd("normal! zR")
  vim.cmd("2foldclose")
  vim.cmd("1foldclose")
  local win = api.nvim_get_current_win()
  local cursor, view = api.nvim_win_get_cursor(win), vim.fn.winsaveview()
  local states = adapter.closed(win, {
    { id = 1, header = "outer", line = 1, new = false },
    { id = 2, header = "inner", line = 2, new = false },
  })
  t.equal(states, { true, true })
  t.equal(vim.wo.foldmethod, "manual")
  t.equal(api.nvim_win_get_cursor(win), cursor)
  t.equal(vim.fn.winsaveview(), view)
  t.equal(vim.fn.foldclosed(1), 1)
  vim.cmd("1foldopen")
  t.equal(vim.fn.foldclosed(2), 2)
  adapter.uninstall()
end)

t.test("failed closed-state inspection restores temporarily opened folds", function()
  local adapter = integration.new()
  buffer({ "outer", "inner", "content", "end inner", "content", "end outer" })
  vim.wo.foldmethod = "manual"
  vim.wo.foldnestmax = 3
  vim.cmd("1,6fold")
  vim.cmd("normal! zR")
  vim.cmd("2,4fold")
  vim.cmd("normal! zR")
  vim.cmd("2foldclose")
  vim.cmd("1foldclose")
  local original, count = vim.fn.foldclosed, 0
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.foldclosed = function(line)
    count = count + 1
    if count == 2 then
      error("cannot inspect fold")
    end
    return original(line)
  end
  local ok = pcall(adapter.closed, api.nvim_get_current_win(), {
    { id = 1, header = "outer", line = 1, new = false },
    { id = 2, header = "inner", line = 2, new = false },
  })
  vim.fn.foldclosed = original
  t.equal(ok, false)
  t.equal(vim.wo.foldmethod, "manual")
  t.equal(vim.fn.foldclosed(1), 1)
  vim.cmd("1foldopen")
  t.equal(vim.fn.foldclosed(2), 2)
  adapter.uninstall()
end)

t.test("coincident header positions observe the same state before temporary opening", function()
  local adapter = integration.new()
  buffer()
  vim.wo.foldmethod, vim.wo.foldminlines, vim.wo.foldlevel = "manual", 1, 99
  vim.cmd("1,4fold")
  vim.cmd("1foldclose")
  t.equal(
    adapter.closed(api.nvim_get_current_win(), {
      { id = 1, header = "removed", line = 1, new = false },
      { id = 2, header = "surviving", line = 1, new = false },
    }),
    { true, true }
  )
  t.equal(vim.fn.foldclosed(1), 1)
  adapter.uninstall()
end)

t.test("state inspection reports cleanup errors after restoring folds and method", function()
  local adapter = integration.new()
  buffer()
  vim.wo.foldmethod, vim.wo.foldminlines, vim.wo.foldlevel = "manual", 1, 99
  vim.cmd("1,4fold")
  vim.cmd("1foldclose")
  local original = vim.fn.winrestview
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.winrestview = function()
    error("cannot restore view")
  end
  local ok, err = pcall(adapter.closed, api.nvim_get_current_win(), {
    { id = 1, header = "fold", line = 1, new = false },
  })
  vim.fn.winrestview = original
  t.equal(ok, false)
  assert(tostring(err):find("cannot restore view", 1, true))
  t.equal(vim.wo.foldmethod, "manual")
  t.equal(vim.fn.foldclosed(1), 1)
  adapter.uninstall()
end)

t.test("state inspection rejects an ancestor that cannot be opened", function()
  local adapter = integration.new()
  buffer()
  vim.wo.foldmethod, vim.wo.foldminlines, vim.wo.foldlevel = "manual", 1, 99
  vim.cmd("1,4fold")
  vim.cmd("1foldclose")
  local original = vim.fn.foldclosed
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.foldclosed = function()
    return 1
  end
  local ok, err = pcall(adapter.closed, api.nvim_get_current_win(), {
    { id = 1, header = "child", line = 2, new = false },
  })
  vim.fn.foldclosed = original
  t.equal(ok, false)
  assert(tostring(err):find("cannot expose hidden fold", 1, true))
  t.equal(vim.fn.foldclosed(1), 1)
  adapter.uninstall()
end)

t.test("fold restoration failures do not skip method and view cleanup", function()
  local adapter = integration.new()
  buffer()
  vim.wo.foldmethod, vim.wo.foldminlines, vim.wo.foldlevel = "manual", 1, 99
  vim.cmd("1,4fold")
  vim.cmd("1foldclose")
  local close, restore_view = vim.cmd.foldclose, vim.fn.winrestview
  local view_restored = false
  ---@param ... unknown
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.cmd.foldclose = function(...)
    error("cannot restore fold")
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.winrestview = function(view)
    view_restored = true
    restore_view(view)
  end
  local ok, err = pcall(adapter.closed, api.nvim_get_current_win(), {
    { id = 1, header = "fold", line = 1, new = false },
  })
  vim.cmd.foldclose, vim.fn.winrestview = close, restore_view
  t.equal(ok, false)
  assert(tostring(err):find("cannot restore fold", 1, true))
  t.equal(vim.wo.foldmethod, "manual")
  t.equal(view_restored, true)
  adapter.uninstall()
end)

t.test("size measurement counts UTF-8 bytes and line terminators", function()
  local adapter = integration.new()
  local lines = { "привет", "🙂", "" }
  local buf = buffer(lines)
  t.equal(adapter.size(buf), { lines = 3, bytes = #lines[1] + #lines[2] + 3 })
  adapter.uninstall()
end)

t.test("header reads include only unique starts and group consecutive rows", function()
  local adapter = integration.new()
  local buf = buffer({ "first", "second", "body", "body", "last", "body" })
  local original = api.nvim_buf_get_lines
  local reads = {}
  ---@param target integer
  ---@param first integer
  ---@param last integer
  ---@param strict boolean
  ---@return string[]
  ---@diagnostic disable-next-line: duplicate-set-field
  api.nvim_buf_get_lines = function(target, first, last, strict)
    reads[#reads + 1] = { first, last }
    return original(target, first, last, strict)
  end
  local ok, result = pcall(adapter.headers, buf, {
    { start = 1, stop = 6 },
    { start = 1, stop = 4 },
    { start = 2, stop = 4 },
    { start = 5, stop = 6 },
  })
  api.nvim_buf_get_lines = original
  assert(ok, result)
  t.equal(result, { { line = 1, header = "first" }, { line = 2, header = "second" }, { line = 5, header = "last" } })
  t.equal(reads, { { 0, 2 }, { 4, 5 } })
  adapter.uninstall()
end)

t.test("extmark transactions skip existing marks already at the requested row", function()
  local adapter = integration.new()
  local buf = buffer()
  local marks = adapter.apply_marks(buf, { marks = { { line = 1, header = "f", new = false } }, delete = {} })
  local original, writes = api.nvim_buf_set_extmark, 0
  ---@param target integer
  ---@param row integer
  ---@param col integer
  ---@param ns integer
  ---@param opts vim.api.keyset.set_extmark
  ---@return integer
  ---@diagnostic disable-next-line: duplicate-set-field
  api.nvim_buf_set_extmark = function(target, ns, row, col, opts)
    writes = writes + 1
    return original(target, ns, row, col, opts)
  end
  local ok, err = pcall(function()
    adapter.apply_marks(buf, {
      marks = { { id = marks[1].id, line = 1, header = "f", new = false, unchanged = true } },
      delete = {},
    })
    t.equal(writes, 0)
    adapter.apply_marks(buf, { marks = { { id = marks[1].id, line = 2, header = "f", new = false } }, delete = {} })
    t.equal(writes, 1)
    t.equal(adapter.positions(buf, marks)[1].line, 2)
  end)
  api.nvim_buf_set_extmark = original
  assert(ok, err)
  adapter.uninstall()
end)

t.run("stable-folds adapter")
