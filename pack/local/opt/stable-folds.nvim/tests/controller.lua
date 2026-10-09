local source = debug.getinfo(1, "S").source:sub(2)
local directory = source:match("^(.*[/\\])") or "./"
package.path = directory .. "../lua/?.lua;" .. directory .. "?.lua;" .. package.path
local t = require("support")
local fixtures = require("fixtures")
local host_vim = rawget(_G, "vim")
_G.vim = nil

t.test("expression works before setup and accepts explicit or implicit lines", function()
  local folds, _, state = fixtures.new()
  t.equal(folds.expr(), ">1")
  state.contexts[10].line = 2
  t.equal(folds.expr(), "1")
  t.equal(folds.expr(5), "0")
  for _, line in ipairs({ 0, -1, 0.5, math.huge, 999 }) do
    t.equal(folds.expr(line), "0")
  end
  t.equal(state.parses, 1)
  t.equal(state.reads, 1)
end)

t.test("two windows with different fold options reuse one tree snapshot", function()
  local folds, _, state = fixtures.new()
  t.equal(folds.expr(1), ">1")
  state.current = 20
  t.equal(folds.expr(1), "0")
  state.current = 10
  t.equal(folds.expr(1), ">1")
  state.contexts[10].nestmax = 0
  t.equal(folds.expr(1), "0")
  t.equal(state.parses, 1)
  t.equal(state.reads, 1)
  t.equal(state.next_id, 2)
end)

t.test("edits reparse once while no-op refresh events use the existing snapshot", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  fixtures.tick(state, 2)
  assert(state.callbacks).changed(1)
  t.equal(state.parses, 2)
  assert(state.callbacks).changed(1)
  t.equal(state.parses, 2)
  folds.refresh()
  t.equal(state.parses, 3)
  t.equal(state.opened[10], {})
end)

t.test("duplicate insertion opens only the new header and retains the old identity", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  state.text[1] = { "first", "a", "b", "end", "", "first", "a", "b", "end", "", "second", "c", "end" }
  state.raw[1] = {
    { start_row = 0, start_col = 0, end_row = 3, end_col = 3 },
    { start_row = 5, start_col = 0, end_row = 8, end_col = 3 },
    { start_row = 10, start_col = 0, end_row = 12, end_col = 3 },
  }
  state.marks[1] = { [1] = 6, [2] = 11 }
  fixtures.tick(state, 2)
  assert(state.callbacks).changed(1)
  t.equal(state.marks[1][1], 6)
  t.equal(state.marks[1][2], 11)
  t.equal(state.marks[1][3], 1)
  t.equal(state.opened[10], { 1 })
  t.equal(state.opened[20], {})
  local opened = state.opened[10]
  assert(state.callbacks).changed(1)
  assert(state.opened[10] == opened)
end)

t.test("all windows receive new fold openings before flags are consumed", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  state.contexts[20].minlines = 1
  state.text[1][5] = "new"
  state.raw[1][#state.raw[1] + 1] = { start_row = 4, start_col = 0, end_row = 7, end_col = 3 }
  fixtures.tick(state, 2)
  assert(state.callbacks).changed(1)
  t.equal(state.opened[10], { 5 })
  t.equal(state.opened[20], { 5 })
end)

t.test("changing window limits does not replace marks or classify folds as new", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  state.contexts[10].minlines = 100
  assert(state.callbacks).changed(1)
  state.contexts[10].minlines = 1
  assert(state.callbacks).changed(1)
  t.equal(state.next_id, 2)
  t.equal(state.opened[10], {})
  t.equal(state.parses, 1)
end)

t.test("language changes clear old marks even without a FileType event", function()
  local folds, _, state = fixtures.new()
  folds.expr(1)
  state.contexts[10].lang = "new_language"
  state.unavailable[1] = true
  t.equal(folds.expr(1), "0")
  t.equal(state.marks[1], {})
  state.contexts[10].lang = "lua"
  state.unavailable[1] = nil
  t.equal(folds.expr(1), ">1")
  t.equal(state.next_id, 4)
  t.equal(state.marks[1][1], nil)
end)

t.test("missing parsers are retried on entry, explicit refresh and TSUpdate", function()
  for _, action in ipairs({ "entered", "refresh", "updated", "attach" }) do
    local folds, _, state = fixtures.new()
    folds.setup()
    state.unavailable[1] = true
    t.equal(folds.expr(1), "0")
    state.unavailable[1] = nil
    t.equal(folds.expr(1), "0")
    if action == "entered" then
      assert(state.callbacks).entered(1)
    elseif action == "updated" then
      assert(state.callbacks).updated()
    elseif action == "attach" then
      folds.attach()
    else
      folds.refresh()
    end
    t.equal(folds.expr(1), ">1")
    t.equal(state.parses, 2)
    t.equal(state.opened[10], {})
  end
end)

t.test("query changes at the same tick are refreshed without auto-opening new folds", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  state.text[1][5] = "new query header"
  state.raw[1][#state.raw[1] + 1] = { start_row = 4, start_col = 0, end_row = 7, end_col = 3 }
  assert(state.callbacks).updated()
  t.equal(folds.expr(5), ">1")
  t.equal(state.opened[10], {})
end)

t.test("filter errors never escape and notifications are deduplicated per revision", function()
  local folds, _, state = fixtures.new()
  folds.setup({
    filter = function()
      error("filter failed")
    end,
  })
  for _ = 1, 20 do
    t.equal(folds.expr(1), "0")
  end
  t.equal(#state.messages, 1)
  t.equal(state.parses, 0)
  fixtures.tick(state, 2)
  t.equal(folds.expr(1), "0")
  t.equal(#state.messages, 2)
  folds.setup()
  t.equal(folds.expr(1), ">1")
end)

t.test("snapshot failures are cached safely and recover after explicit refresh", function()
  for _, failure in ipairs({ "collect", "lines", "apply" }) do
    local folds, _, state = fixtures.new()
    folds.setup()
    ---@cast failure StableFoldsTestFailure
    state.fail = failure
    for _ = 1, 10 do
      t.equal(folds.expr(1), "0")
    end
    t.equal(state.parses, 1)
    t.equal(#state.messages, 1)
    t.equal(state.marks[1], nil)
    state.fail = nil
    folds.refresh()
    t.equal(folds.expr(1), ">1")
    t.equal(state.parses, 2)
  end
end)

t.test("a buffer changed during parsing never publishes a stale snapshot", function()
  local folds, _, state = fixtures.new()
  state.on_collect = function()
    fixtures.tick(state, 2)
  end
  t.equal(folds.expr(1), "0")
  t.equal(state.marks[1], nil)
  state.on_collect = nil
  t.equal(folds.expr(1), ">1")
  t.equal(state.parses, 2)
end)

t.test("special and filtered buffers clear cached identities", function()
  local folds, _, state = fixtures.new()
  folds.expr(1)
  state.contexts[10].buftype = "nofile"
  t.equal(folds.expr(1), "0")
  t.equal(state.marks[1], nil)
  state.contexts[10].buftype = ""
  folds.setup({
    filter = function()
      return false
    end,
  })
  t.equal(folds.expr(1), "0")
  folds.setup()
  t.equal(folds.expr(1), ">1")
end)

t.test("setup replaces options and teardown is repeatable and suspends expressions", function()
  local folds, _, state = fixtures.new()
  folds.setup({
    filter = function()
      return false
    end,
  })
  t.equal(folds.expr(1), "0")
  folds.setup()
  t.equal(folds.expr(1), ">1")
  folds.teardown()
  folds.teardown()
  t.equal(folds.expr(1), "0")
  t.equal(state.callbacks, nil)
  t.equal(state.marks[1], nil)
  local parses = state.parses
  folds.attach()
  folds.refresh()
  t.equal(state.parses, parses)
  folds.setup()
  t.equal(folds.expr(1), ">1")
end)

t.test("setup installation failures roll back callbacks and allow retry", function()
  local folds, _, state = fixtures.new()
  state.fail = "install"
  folds.setup()
  t.equal(state.callbacks, nil)
  t.equal(folds.expr(1), "0")
  t.equal(#state.messages, 1)
  state.fail = nil
  folds.setup()
  t.equal(folds.expr(1), ">1")
end)

t.test("buffer and window cleanup callbacks allow safe reuse", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  assert(state.callbacks).closed(10)
  t.equal(folds.expr(1), ">1")
  t.equal(state.parses, 1)
  assert(state.callbacks).deleted(1)
  t.equal(state.marks[1], nil)
  t.equal(folds.expr(1), ">1")
  t.equal(state.parses, 2)
  assert(state.callbacks).reset(1)
  t.equal(state.parses, 3)
end)

t.test("refresh is protected from recursion and adapter failures", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  state.on_recompute = function()
    folds.refresh()
  end
  folds.refresh()
  t.equal(state.parses, 1)
  state.on_recompute = nil
  state.fail = "windows"
  folds.refresh()
  state.fail = nil
  folds.refresh()
  t.equal(state.parses, 2)
  state.fail = "context"
  t.equal(folds.expr(1), "0")
  state.fail = nil
  t.equal(folds.expr(1), ">1")
end)

t.test("controller instances share no buffers, options or lifecycle", function()
  local first, _, one = fixtures.new()
  local second, _, two = fixtures.new()
  first.setup({
    filter = function()
      return false
    end,
  })
  second.setup()
  t.equal(first.expr(1), "0")
  t.equal(second.expr(1), ">1")
  first.teardown()
  t.equal(second.expr(1), ">1")
  t.equal(one.parses, 0)
  t.equal(two.parses, 1)
end)

t.test("unknown buffer and window ids produce no effects", function()
  local folds, _, state = fixtures.new()
  folds.attach(999)
  folds.refresh(999)
  state.current = 999
  t.equal(folds.expr(1), "0")
  t.equal(state.parses, 0)
end)

t.test("lifecycle changes during collection cannot recreate disposed marks", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  state.on_collect = folds.teardown
  t.equal(folds.expr(1), "0")
  t.equal(state.marks[1], nil)
  t.equal(state.callbacks, nil)
  state.on_collect = nil
  folds.setup()
  t.equal(folds.expr(1), ">1")
end)

t.test("filter reentrancy cannot recurse or resume a disposed controller", function()
  local folds, _, state = fixtures.new()
  folds.setup({
    filter = function()
      t.equal(folds.expr(1), "0")
      folds.teardown()
      return true
    end,
  })
  t.equal(folds.expr(1), "0")
  t.equal(state.parses, 0)
  t.equal(state.marks[1], nil)
  folds.setup()
  t.equal(folds.expr(1), ">1")
end)

t.test("refresh stops applying effects after teardown from a window callback", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  state.on_recompute = folds.teardown
  folds.refresh()
  t.equal(state.opened, {})
  t.equal(state.marks[1], nil)
  t.equal(folds.expr(1), "0")
end)

t.test("pre-edit states follow reordered headers and survive several edits before refresh", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  state.contexts[20].minlines = 1
  state.closed = { [10] = { [1] = true, [2] = false }, [20] = { [1] = false, [2] = true } }
  state.watchers[1]()
  state.closed = { [10] = { [1] = false, [2] = true }, [20] = { [1] = true, [2] = false } }
  state.watchers[1]()
  state.text[1] = { "second", "c", "end", "", "", "first", "a", "b", "end" }
  state.raw[1] = {
    { start_row = 0, start_col = 0, end_row = 2, end_col = 3 },
    { start_row = 5, start_col = 0, end_row = 8, end_col = 3 },
  }
  state.marks[1] = { [1] = 9, [2] = 9 }
  fixtures.tick(state, 2)
  assert(state.callbacks).changed(1)
  t.equal(state.restored[10], { { line = 1, closed = false }, { line = 6, closed = true } })
  t.equal(state.restored[20], { { line = 1, closed = true }, { line = 6, closed = false } })
  local restored = state.restored[10]
  assert(state.callbacks).changed(1)
  assert(state.restored[10] == restored)
end)

t.test("disposed watchers cannot capture state into a later setup", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  local old = state.watchers[1]
  folds.teardown()
  t.equal(state.watchers, {})
  folds.setup()
  folds.expr(1)
  old()
  assert(state.callbacks).changed(1)
  t.equal(state.restored[10], {})
end)

t.test("callbacks retained from an old setup cannot delete newer state", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  local old = assert(state.callbacks)
  folds.setup()
  folds.expr(1)
  old.deleted(1)
  old.reset(1)
  old.updated()
  old.closed(10)
  old.changed(1)
  old.entered(1)
  t.equal(state.parses, 1)
  t.equal(state.marks[1][1], 1)
end)

t.test("transient parse failures retain identities and pending closed states for recovery", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  state.closed[10] = { [1] = true, [2] = false }
  state.fail = "collect"
  folds.refresh()
  t.equal(folds.expr(1), "0")
  t.equal(state.marks[1][1], 1)
  state.fail = nil
  folds.refresh()
  t.equal(state.next_id, 2)
  t.equal(state.restored[10], { { line = 1, closed = true }, { line = 6, closed = false } })
end)

t.test("failed window updates retry pending new-fold openings without repeating successful effects", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  state.contexts[20].minlines = 1
  state.text[1][5] = "new"
  state.raw[1][#state.raw[1] + 1] = { start_row = 4, start_col = 0, end_row = 7, end_col = 3 }
  fixtures.tick(state, 2)
  state.fail = "recompute"
  state.fail_win = 10
  assert(state.callbacks).changed(1)
  t.equal(state.restored[20], { { line = 5, closed = false } })
  local restored_two = state.restored[20]
  state.fail = nil
  assert(state.callbacks).changed(1)
  t.equal(state.restored[10], { { line = 5, closed = false } })
  assert(state.restored[20] == restored_two)
  local restored_one = state.restored[10]
  assert(state.callbacks).changed(1)
  assert(state.restored[10] == restored_one)
end)

t.test("a previously unobservable child is captured when it becomes observable during an edit burst", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  state.watchers[1]()
  state.closed[10] = { [1] = true, [2] = false }
  state.watchers[1]()
  fixtures.tick(state, 2)
  assert(state.callbacks).changed(1)
  t.equal(state.restored[10], { { line = 1, closed = true }, { line = 6, closed = false } })
end)

t.test("refresh queues a different buffer requested during window recomputation", function()
  local folds, _, state = fixtures.new()
  state.contexts[20].buf = 2
  state.text[2], state.raw[2] = t.copy(state.text[1]), t.copy(state.raw[1])
  folds.setup()
  folds.expr(1)
  state.on_recompute = function()
    state.on_recompute = nil
    folds.refresh(2)
  end
  folds.refresh(1)
  t.equal(state.parses, 3)
  assert(state.marks[2])
end)

t.test("refresh queues edits occurring after the current snapshot was collected", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  state.on_recompute = function()
    state.on_recompute = nil
    fixtures.tick(state, 2)
    assert(state.callbacks).changed(1)
  end
  folds.refresh()
  t.equal(state.parses, 3)
  t.equal(folds.expr(1), ">1")
  t.equal(state.parses, 3)
end)

t.test("a forced refresh upgrades a running automatic refresh only once", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  state.on_recompute = function()
    folds.refresh()
  end
  assert(state.callbacks).changed(1)
  t.equal(state.parses, 2)
end)

t.test("teardown discards pending refresh requests", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  state.on_recompute = function()
    fixtures.tick(state, 2)
    assert(state.callbacks).changed(1)
    folds.teardown()
  end
  folds.refresh()
  t.equal(state.parses, 2)
  state.on_recompute = nil
  folds.setup()
  folds.expr(1)
  t.equal(state.parses, 3)
end)

t.test("setup during refresh processes the new generation's pending windows", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  state.on_recompute = function()
    state.on_recompute = nil
    folds.setup()
  end
  folds.refresh()
  t.equal(state.parses, 3)
  assert(state.marks[1])
  t.equal(folds.expr(1), ">1")
end)

t.test("unloaded identities survive reload and wiping clears suspended state", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  state.closed[10] = { [1] = true, [2] = false }
  assert(state.callbacks).unloaded(1)
  t.equal(state.marks[1], nil)
  fixtures.tick(state, 2)
  assert(state.callbacks).reset(1)
  assert(state.callbacks).changed(1)
  t.equal(state.restored[10], { { line = 1, closed = true }, { line = 6, closed = false } })
  assert(state.callbacks).unloaded(1)
  assert(state.callbacks).deleted(1)
  fixtures.tick(state, 3)
  assert(state.callbacks).changed(1)
  t.equal(state.restored[10], {})
end)

t.test("inherited new folds honor independent window foldlevels and retain old flags", function()
  local folds, _, state = fixtures.new()
  state.contexts[20].minlines, state.contexts[20].foldlevel = 1, 0
  folds.setup({ new_folds = "inherit" })
  folds.expr(1)
  state.closed[10] = { [1] = true, [2] = false }
  assert(state.watchers[1])()
  for _, line in ipairs({ "third", "body", "end" }) do
    state.text[1][#state.text[1] + 1] = line
  end
  state.raw[1][3] = { start_row = 8, start_col = 0, end_row = 10, end_col = 3 }
  fixtures.tick(state, 2)
  assert(state.callbacks).changed(1)
  t.equal(state.opened[10], {})
  t.equal(
    state.restored[10],
    { { line = 1, closed = true }, { line = 6, closed = false }, { line = 9, closed = false } }
  )
  t.equal(state.restored[20], { { line = 9, closed = true } })
end)

t.test("oversized buffers skip parsing, copying and watcher attachment until they shrink", function()
  local folds, _, state = fixtures.new()
  folds.setup({ max_lines = 7 })
  for _ = 1, 5 do
    t.equal(folds.expr(1), "0")
  end
  t.equal(state.parses, 0)
  t.equal(state.reads, 0)
  t.equal(state.size_reads, 1)
  t.equal(state.watchers[1], nil)
  state.text[1] = { "first", "a", "b", "end" }
  state.raw[1][2] = nil
  fixtures.tick(state, 2)
  assert(state.callbacks).changed(1)
  t.equal(folds.expr(1), ">1")
  t.equal(state.parses, 1)
  t.equal(state.size_reads, 2)
  assert(state.watchers[1])
end)

t.test("growing past the byte limit clears identities and releases the watcher", function()
  local folds, _, state = fixtures.new()
  folds.setup({ max_bytes = 100 })
  folds.expr(1)
  state.text[1][2] = string.rep("x", 101)
  fixtures.tick(state, 2)
  assert(state.callbacks).changed(1)
  t.equal(folds.expr(1), "0")
  t.equal(state.parses, 1)
  t.equal(state.marks[1], nil)
  t.equal(state.watchers[1], nil)
  folds.setup({ max_bytes = 0 })
  t.equal(folds.expr(1), ">1")
end)

t.test("an explicit refresh rechecks a rejected buffer at an unchanged tick", function()
  local folds, _, state = fixtures.new()
  folds.setup({ max_lines = 1 })
  folds.expr(1)
  folds.refresh()
  t.equal(state.size_reads, 2)
  t.equal(state.parses, 0)
end)

t.test("disabled notifications suppress configuration and runtime errors", function()
  local folds, _, state = fixtures.new()
  ---@diagnostic disable-next-line: assign-type-mismatch
  folds.setup({ notify_errors = false, max_lines = -1 })
  state.fail = "collect"
  t.equal(folds.expr(1), "0")
  t.equal(state.messages, {})
  state.fail = nil
  folds.setup({ notify_errors = true })
  state.fail = "collect"
  folds.refresh()
  t.equal(#state.messages, 1)
end)

t.test("default options avoid measuring buffer size", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  folds.refresh()
  t.equal(state.size_reads, nil)
end)

t.test("unmodified headers do not require mark writes after a body edit or forced refresh", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  t.equal(state.mark_writes, 2)
  state.text[1][2] = "updated body"
  assert(state.watchers[1])()
  fixtures.tick(state, 2)
  assert(state.callbacks).changed(1)
  t.equal(state.mark_writes, 2)
  folds.refresh()
  t.equal(state.mark_writes, 2)
end)

t.test("dynamic filters remain observable outside the native expression batch", function()
  local folds, _, state = fixtures.new()
  state.enabled[20] = false
  local allowed, calls = true, 0
  folds.setup({
    filter = function()
      calls = calls + 1
      return allowed
    end,
  })
  folds.expr(1)
  state.on_recompute = function()
    for _ = 1, 10 do
      t.equal(folds.expr(1), ">1")
    end
  end
  folds.refresh()
  assert(calls < 10, "the filter should run once per window batch")
  allowed = false
  t.equal(folds.expr(1), "0")
end)

t.test("a newly entered window refreshes without rereading positions or reparsing", function()
  local folds, _, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  assert(state.callbacks).changed(1)
  local parses, reads = state.parses, state.position_reads
  state.contexts[30] = t.copy(state.contexts[10])
  state.contexts[30].win = 30
  state.enabled[30] = true
  assert(state.callbacks).entered(1)
  t.equal(state.parses, parses)
  t.equal(state.position_reads, reads)
  t.equal(state.recomputes[30], 1)
  t.equal(state.recomputes[10], 1)
end)

t.test("foldexpr cannot publish stale tree coordinates before the byte callback", function()
  local folds, adapter, state = fixtures.new()
  folds.setup()
  folds.expr(1)
  fixtures.tick(state, 2)
  ---@diagnostic disable-next-line: duplicate-set-field
  adapter.ready = function()
    return false
  end
  state.text[1][1] = "not the old header"
  folds.expr(1)
  t.equal(state.parses, 1)
  t.equal(state.marks[1], { [1] = 1, [2] = 6 })
  ---@diagnostic disable-next-line: duplicate-set-field
  adapter.ready = function()
    return true
  end
  assert(state.callbacks).changed(1)
  t.equal(state.parses, 2)
end)

t.run("stable-folds controller")
_G.vim = host_vim
