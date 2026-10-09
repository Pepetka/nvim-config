local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/site")
vim.opt.packpath:append(vim.fn.stdpath("data") .. "/site")
vim.cmd.packadd("nvim-treesitter")
package.path = root .. "/tests/?.lua;" .. package.path
vim.o.swapfile = false
local t = require("support")
local api = vim.api
---@type table<string, integer>
local metrics = {}
local integration = require("stable_folds.integrations.nvim")
local original_adapter = integration.new
---@return StableFoldsAdapter
---@diagnostic disable-next-line: duplicate-set-field
function integration.new()
  local adapter = original_adapter()
  local context, positions, recompute = adapter.context, adapter.positions, adapter.recompute
  ---@param win? integer
  ---@return StableFoldsContext?
  adapter.context = function(win)
    metrics.context = (metrics.context or 0) + 1
    return context(win)
  end
  ---@param buf integer
  ---@param marks StableFoldsMark[]
  ---@return StableFoldsPosition[]
  adapter.positions = function(buf, marks)
    metrics.positions = (metrics.positions or 0) + 1
    return positions(buf, marks)
  end
  ---@param win integer
  adapter.recompute = function(win)
    metrics.recompute = (metrics.recompute or 0) + 1
    recompute(win)
  end
  return adapter
end
local treesitter = require("stable_folds.integrations.treesitter")
local original_collect, collected = treesitter.collect, 0
---@param buf integer
---@param lang? string
---@param include_injections? boolean
---@return StableFoldsRawRange[]?
---@diagnostic disable-next-line: duplicate-set-field
function treesitter.collect(buf, lang, include_injections)
  collected = collected + 1
  return original_collect(buf, lang, include_injections)
end
local folds = require("stable_folds")
local namespace = api.nvim_create_namespace("StableFoldStarts")
local first = { "local function first()", "  local a = 1", "  return a", "end" }
local second = { "local function second()", "  local b = 2", "  return b", "end" }

---@param lines? string[]
---@param foldlevel? integer
---@return integer, integer
local function fixture(lines, foldlevel)
  folds.teardown()
  vim.cmd("silent only")
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "lua"
  vim.wo.foldminlines = 1
  vim.wo.foldnestmax = 1
  vim.wo.foldlevel = foldlevel or 99
  lines = lines or vim.list_extend(vim.list_extend(vim.deepcopy(first), { "" }), second)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  folds.setup()
  folds.attach()
  return buf, api.nvim_get_current_win()
end

---@param buf integer
---@return integer
local function mark_count(buf)
  return #api.nvim_buf_get_extmarks(buf, namespace, 0, -1, {})
end

---@param name string
---@param run StableFoldsAction
local function test(name, run)
  t.test(name, function()
    local ok, err = xpcall(run, debug.traceback)
    folds.teardown()
    assert(ok, err)
  end)
end

test("fold boundaries, gaps and repeated setup", function()
  local buf = fixture()
  folds.setup()
  folds.setup()
  t.equal(#api.nvim_get_autocmds({ group = "SynchronousFolds" }), 15)
  t.equal(vim.wo.foldexpr, folds.foldexpr)
  t.equal(folds.expr(1), ">1")
  t.equal(folds.expr(2), "1")
  t.equal(folds.expr(5), "0")
  t.equal(folds.expr(6), ">1")
  t.equal(mark_count(buf), 2)
end)

test("edits above closed folds preserve their moved state", function()
  local buf = fixture()
  vim.cmd("1foldclose")
  api.nvim_buf_set_lines(buf, 0, 0, false, { "-- inserted above a closed fold", "" })
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  t.equal(folds.expr(1), "0")
  t.equal(folds.expr(3), ">1")
  t.equal(vim.fn.foldclosed(3), 3)
  t.equal(vim.fn.foldclosed(8), -1)
end)

test("formatter replacements preserve unique unchanged headers", function()
  local buf = fixture()
  vim.cmd("1foldclose")
  local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  lines[2] = "  local a = 42"
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
  t.equal(vim.fn.foldclosed(1), 1)
  t.equal(vim.fn.foldclosed(6), -1)
  t.equal(mark_count(buf), 2)
end)

test("new neighboring folds remain open", function()
  local buf = fixture()
  vim.cmd("1foldclose")
  api.nvim_buf_set_lines(buf, 0, 0, false, vim.list_extend(vim.deepcopy(second), { "" }))
  api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
  t.equal(vim.fn.foldclosed(1), -1)
  t.equal(vim.fn.foldclosed(6), 6)
end)

test("inserted identical header cannot inherit the original closed identity", function()
  local buf = fixture(first)
  vim.cmd("1foldclose")
  api.nvim_buf_set_lines(buf, 0, 0, false, vim.list_extend(vim.deepcopy(first), { "" }))
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  t.equal(vim.fn.foldclosed(1), -1)
  t.equal(vim.fn.foldclosed(6), 6)
  t.equal(mark_count(buf), 2)
end)

test("different window limits share one parse and retain independent closed states", function()
  local buf, one = fixture()
  vim.cmd("1foldclose")
  collected = 0
  vim.cmd.vsplit()
  local two = api.nvim_get_current_win()
  vim.wo.foldminlines = 5
  t.equal(folds.expr(1), "0")
  api.nvim_set_current_win(one)
  t.equal(folds.expr(1), ">1")
  t.equal(vim.fn.foldclosed(1), 1)
  api.nvim_set_current_win(two)
  vim.wo.foldminlines = 1
  vim.cmd("normal! zR")
  api.nvim_set_current_win(one)
  t.equal(vim.fn.foldclosed(1), 1)
  api.nvim_buf_set_lines(buf, 0, 0, false, { "-- shift", "" })
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  t.equal(vim.fn.foldclosed(3), 3)
  api.nvim_set_current_win(two)
  t.equal(vim.fn.foldclosed(3), -1)
  t.equal(collected, 1)
end)

test("nested fold levels react to window options without losing header identities", function()
  local buf = fixture({
    "local function outer()",
    "  local function inner()",
    "    return 1",
    "  end",
    "  return inner()",
    "end",
  })
  t.equal(folds.expr(2), "1")
  vim.wo.foldnestmax = 2
  t.equal(folds.expr(2), ">2")
  vim.wo.foldminlines = 4
  t.equal(folds.expr(2), "1")
  vim.wo.foldminlines = 1
  t.equal(folds.expr(2), ">2")
  t.equal(mark_count(buf), 2)
end)

test("initial folds still honor caller-owned foldlevel", function()
  fixture(first, 0)
  t.equal(vim.fn.foldclosed(1), 1)
end)

test("language alias changes leave no orphan extmarks", function()
  local buf = fixture()
  vim.treesitter.language.register("stable_folds_missing_parser", "lua")
  local ok, err = xpcall(function()
    t.equal(folds.expr(1), "0")
    t.equal(mark_count(buf), 0)
  end, debug.traceback)
  vim.treesitter.language.register("lua", "lua")
  assert(ok, err)
  t.equal(folds.expr(1), ">1")
  t.equal(mark_count(buf), 2)
end)

test("parser availability at an unchanged tick can be explicitly refreshed", function()
  fixture()
  local original = vim.treesitter.get_parser
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.treesitter.get_parser = function()
    return nil, "parser unavailable"
  end
  folds.refresh()
  t.equal(folds.expr(1), "0")
  vim.treesitter.get_parser = original
  t.equal(folds.expr(1), "0")
  folds.refresh()
  t.equal(folds.expr(1), ">1")
end)

test("query changes at the same tick are picked up by TSUpdate", function()
  fixture()
  local query_files = vim.treesitter.query.get_files("lua", "folds")
  local content = {}
  for _, file in ipairs(query_files) do
    content[#content + 1] = table.concat(vim.fn.readfile(file), "\n")
  end
  vim.treesitter.query.set("lua", "folds", "")
  api.nvim_exec_autocmds("User", { pattern = "TSUpdate" })
  t.equal(folds.expr(1), "0")
  vim.treesitter.query.set("lua", "folds", table.concat(content, "\n"))
  t.equal(folds.expr(1), "0")
  api.nvim_exec_autocmds("User", { pattern = "TSUpdate" })
  t.equal(folds.expr(1), ">1")
end)

test("parser errors return zero, report once and recover", function()
  fixture()
  vim.cmd("1foldclose")
  local parser = assert(vim.treesitter.get_parser(0, "lua"))
  local original_parse, original_notify = parser.parse, vim.notify
  local messages = {}
  parser.parse = function()
    error("synthetic parser failure")
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(message)
    messages[#messages + 1] = message
  end
  local ok, err = xpcall(function()
    folds.refresh()
    for _ = 1, 10 do
      t.equal(folds.expr(1), "0")
    end
    parser.parse = original_parse
    assert(vim.wait(1000, function()
      return #messages > 0
    end))
    t.equal(#messages, 1)
  end, debug.traceback)
  parser.parse, vim.notify = original_parse, original_notify
  assert(ok, err)
  folds.refresh()
  t.equal(folds.expr(1), ">1")
  t.equal(vim.fn.foldclosed(1), 1)
end)

test("missing parsers, filtered buffers and special buffers produce zero", function()
  local buf = fixture()
  vim.bo[buf].filetype = "missing_parser_for_test"
  t.equal(folds.expr(1), "0")
  vim.bo[buf].filetype = "lua"
  folds.setup({
    filter = function()
      return false
    end,
  })
  t.equal(folds.expr(1), "0")
  t.equal(mark_count(buf), 0)
  folds.setup()
  vim.bo[buf].buftype = "nofile"
  t.equal(folds.expr(1), "0")
  vim.bo[buf].buftype = ""
  t.equal(folds.expr(1), ">1")
end)

test("deleted captures, buffer unloading and teardown release all marks", function()
  local buf = fixture()
  api.nvim_buf_set_lines(buf, 0, -1, false, { "local a = 1" })
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  t.equal(mark_count(buf), 0)
  api.nvim_buf_set_lines(buf, 0, -1, false, first)
  folds.refresh()
  t.equal(mark_count(buf), 1)
  api.nvim_buf_delete(buf, { unload = true, force = true })
  t.equal(mark_count(buf), 0)
  local fresh = fixture()
  folds.teardown()
  folds.teardown()
  t.equal(mark_count(fresh), 0)
  t.equal(folds.expr(1), "0")
  t.equal(vim.wo.foldexpr, folds.foldexpr)
  t.equal(vim.wo.foldmethod, "expr")
  folds.setup()
  folds.attach()
  t.equal(folds.expr(1), ">1")
end)

test("reordering unique headers moves each window's closed state with the original fold", function()
  local buf, one = fixture()
  vim.cmd("1foldclose")
  vim.cmd.vsplit()
  local two = api.nvim_get_current_win()
  vim.cmd("normal! zR")
  vim.cmd("6foldclose")
  api.nvim_buf_set_lines(buf, 0, -1, false, vim.list_extend(vim.list_extend(vim.deepcopy(second), { "" }), first))
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  t.equal(vim.fn.foldclosed(1), 1)
  t.equal(vim.fn.foldclosed(6), -1)
  api.nvim_set_current_win(one)
  t.equal(vim.fn.foldclosed(1), -1)
  t.equal(vim.fn.foldclosed(6), 6)
  api.nvim_set_current_win(two)
end)

test("formatter line-count changes preserve a later closed header", function()
  local buf = fixture()
  vim.cmd("6foldclose")
  local formatted = vim.deepcopy(first)
  table.insert(formatted, 2, "  -- additional formatter line")
  api.nvim_buf_set_lines(buf, 0, -1, false, vim.list_extend(vim.list_extend(formatted, { "" }), second))
  api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
  t.equal(vim.fn.foldclosed(1), -1)
  t.equal(vim.fn.foldclosed(7), 7)
end)

test("an inherited closed fold in an untouched split survives edits", function()
  local buf, one = fixture()
  vim.cmd("1foldclose")
  vim.cmd.vsplit()
  local two = api.nvim_get_current_win()
  api.nvim_buf_set_lines(buf, 0, 0, false, { "-- shifted", "" })
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  t.equal(vim.fn.foldclosed(3), 3)
  api.nvim_set_current_win(one)
  t.equal(vim.fn.foldclosed(3), 3)
  api.nvim_set_current_win(two)
end)

test("new outer folds do not erase a known closed child's state", function()
  local buf = fixture(first)
  vim.wo.foldnestmax = 2
  vim.cmd("1foldclose")
  api.nvim_buf_set_lines(buf, 0, 0, false, { "do" })
  api.nvim_buf_set_lines(buf, -1, -1, false, { "end" })
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  t.equal(vim.fn.foldclosed(1), -1)
  t.equal(vim.fn.foldclosed(2), 2)
end)

test("editing above a closed outer fold retains native hidden-child state", function()
  local buf = fixture({
    "local function outer()",
    "  local function inner()",
    "    return 1",
    "  end",
    "  return inner()",
    "end",
  })
  vim.wo.foldnestmax = 2
  folds.refresh()
  vim.cmd("2foldclose")
  vim.cmd("1foldclose")
  api.nvim_buf_set_lines(buf, 0, 0, false, { "-- shift", "" })
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  t.equal(vim.fn.foldclosed(3), 3)
  vim.cmd("3foldopen")
  t.equal(vim.fn.foldclosed(4), 4)
end)

test("a new ancestor preserves closed states hidden inside an existing closed fold", function()
  local buf = fixture({
    "local function outer()",
    "  local function inner()",
    "    return 1",
    "  end",
    "  return inner()",
    "end",
  })
  vim.wo.foldnestmax = 3
  folds.refresh()
  vim.cmd("2foldclose")
  vim.cmd("1foldclose")
  api.nvim_buf_set_lines(buf, 0, 0, false, { "do" })
  api.nvim_buf_set_lines(buf, -1, -1, false, { "end" })
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  t.equal(vim.fn.foldclosed(1), -1)
  t.equal(vim.fn.foldclosed(2), 2)
  vim.cmd("2foldopen")
  t.equal(vim.fn.foldclosed(3), 3)
end)

test("whole-buffer shrink preserves the surviving fold's closed state", function()
  for _, closed in ipairs({ 1, 6 }) do
    local buf = fixture()
    vim.cmd(closed .. "foldclose")
    api.nvim_buf_set_lines(buf, 0, -1, false, second)
    api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    t.equal(vim.fn.foldclosed(1), closed == 6 and 1 or -1)
  end
end)

test("repeated setup immediately applies an excluding filter to existing windows", function()
  fixture()
  vim.cmd("1foldclose")
  vim.cmd.vsplit()
  local two = api.nvim_get_current_win()
  folds.setup({
    filter = function()
      return false
    end,
  })
  for _, win in ipairs(api.nvim_list_wins()) do
    api.nvim_set_current_win(win)
    t.equal(vim.fn.foldclosed(1), -1)
  end
  api.nvim_set_current_win(two)
  folds.setup()
  t.equal(vim.fn.foldlevel(1), 1)
end)

test("edit and checktime reloads preserve independent window states and reordered identities", function()
  local autoread = vim.o.autoread
  vim.o.autoread = true
  ---@type { command: string, reordered: boolean }[]
  local cases = {
    { command = "edit!", reordered = false },
    { command = "edit!", reordered = true },
    { command = "checktime", reordered = false },
    { command = "checktime", reordered = true },
  }
  for _, case in ipairs(cases) do
    local reordered = case.reordered
    folds.teardown()
    vim.cmd("silent only")
    local path = vim.fn.tempname() .. ".lua"
    local lines = vim.list_extend(vim.list_extend(vim.deepcopy(first), { "" }), second)
    vim.fn.writefile(lines, path)
    local ok, err = xpcall(function()
      vim.cmd.edit(path)
      vim.bo.filetype = "lua"
      vim.wo.foldminlines, vim.wo.foldnestmax, vim.wo.foldlevel = 1, 1, 99
      folds.setup()
      folds.attach()
      local one = api.nvim_get_current_win()
      vim.cmd("1foldclose")
      vim.cmd.vsplit()
      vim.cmd("normal! zR")
      vim.cmd("6foldclose")
      if reordered then
        vim.fn.writefile(vim.list_extend(vim.list_extend(vim.deepcopy(second), { "" }), first), path)
      end
      if case.command == "checktime" then
        assert(vim.uv.fs_utime(path, os.time() + 2, os.time() + 2))
      end
      vim.cmd(case.command)
      t.equal(
        vim.fn.foldclosed(reordered and 1 or 6),
        reordered and 1 or 6,
        case.command .. ": reordered=" .. tostring(reordered)
      )
      t.equal(vim.fn.foldclosed(reordered and 6 or 1), -1)
      api.nvim_set_current_win(one)
      t.equal(vim.fn.foldclosed(reordered and 6 or 1), reordered and 6 or 1)
      t.equal(vim.fn.foldclosed(reordered and 1 or 6), -1)
      -- A new split between reloads must join the next ownership snapshot.
      vim.cmd.vsplit()
      assert(vim.uv.fs_utime(path, os.time() + 4, os.time() + 4))
      vim.cmd.checktime()
      t.equal(vim.wo.foldexpr, folds.foldexpr)
      t.equal(vim.fn.foldclosed(reordered and 6 or 1), reordered and 6 or 1)
      -- Reload must not disable the watcher used by subsequent edits.
      api.nvim_buf_set_lines(0, 0, 0, false, { "-- shifted", "" })
      api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
      t.equal(vim.fn.foldclosed(reordered and 8 or 3), reordered and 8 or 3)
    end, debug.traceback)
    vim.fn.delete(path)
    if not ok then
      vim.o.autoread = autoread
    end
    assert(ok, err)
  end
  vim.o.autoread = autoread
end)

test("checktime preserves manually opened parents with closed children at foldlevel zero", function()
  folds.teardown()
  vim.cmd("silent only")
  local path, autoread, viewoptions = vim.fn.tempname() .. ".lua", vim.o.autoread, vim.o.viewoptions
  vim.fn.writefile({
    "local function outer()",
    "  local function inner()",
    "    return 1",
    "  end",
    "  return inner()",
    "end",
  }, path)
  local ok, err = xpcall(function()
    vim.o.autoread = true
    vim.cmd.edit(path)
    vim.bo.filetype = "lua"
    vim.wo.foldminlines, vim.wo.foldnestmax, vim.wo.foldlevel = 1, 3, 0
    folds.setup()
    folds.attach()
    vim.cmd("1foldopen")
    t.equal(vim.fn.foldclosed(1), -1)
    t.equal(vim.fn.foldclosed(2), 2)
    assert(vim.uv.fs_utime(path, os.time() + 2, os.time() + 2))
    vim.cmd.checktime()
    t.equal(vim.fn.foldclosed(1), -1)
    t.equal(vim.fn.foldclosed(2), 2)
    t.equal(vim.o.viewoptions, viewoptions)
  end, debug.traceback)
  vim.o.autoread = autoread
  vim.fn.delete(path)
  assert(ok, err)
end)

test("new folds inherit foldlevel while existing manually closed folds retain their state", function()
  for _, foldlevel in ipairs({ 0, 99 }) do
    local buf = fixture(first, foldlevel)
    folds.setup({ new_folds = "inherit" })
    vim.cmd("1foldclose")
    api.nvim_buf_set_lines(buf, 0, 0, false, vim.list_extend(vim.deepcopy(second), { "" }))
    api.nvim_exec_autocmds("TextChanged", { buffer = buf })
    t.equal(vim.fn.foldclosed(1), foldlevel == 0 and 1 or -1)
    t.equal(vim.fn.foldclosed(6), 6)
  end
end)

test("line limits stop parsing and release marks when the buffer grows", function()
  local buf = fixture(first)
  collected = 0
  folds.setup({ max_lines = 4 })
  t.equal(collected, 1)
  t.equal(vim.fn.foldlevel(1), 1)
  api.nvim_buf_set_lines(buf, -1, -1, false, { "-- exceeds the limit" })
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  t.equal(collected, 1)
  t.equal(vim.fn.foldlevel(1), 0)
  t.equal(mark_count(buf), 0)
  api.nvim_buf_set_lines(buf, -2, -1, false, {})
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  t.equal(collected, 2)
  t.equal(vim.fn.foldlevel(1), 1)
end)

test("three windows share mark reads and skip all redundant native refreshes", function()
  local buf = fixture()
  vim.cmd("1foldclose")
  vim.cmd.vsplit()
  vim.cmd.vsplit()
  metrics, collected = {}, 0
  api.nvim_buf_set_lines(buf, 1, 2, false, { "  local a = 42" })
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  t.equal(metrics.positions, 2)
  t.equal(metrics.recompute, 3)
  assert(metrics.context <= 24, "foldexpr must reuse its evaluation context")
  t.equal(collected, 1)
  metrics, collected = {}, 0
  for _, event in ipairs({ "TextChanged", "InsertLeave", "BufWritePost" }) do
    api.nvim_exec_autocmds(event, { buffer = buf })
  end
  t.equal(metrics.positions, nil)
  t.equal(metrics.recompute, nil)
  t.equal(collected, 0)
  for _, win in ipairs(api.nvim_list_wins()) do
    api.nvim_set_current_win(win)
    t.equal(vim.fn.foldclosed(1), 1)
  end
end)

t.run("stable-folds Neovim")
