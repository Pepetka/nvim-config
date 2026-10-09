local source = debug.getinfo(1, "S").source:sub(2)
local directory = source:match("^(.*[/\\])") or "./"
package.path = directory .. "../lua/?.lua;" .. directory .. "?.lua;" .. package.path
local t = require("support")
local config = require("stable_folds.core.config")
local ranges = require("stable_folds.core.ranges")
local levels = require("stable_folds.core.levels")
local tracking = require("stable_folds.core.tracking")
local cache = require("stable_folds.core.cache")
local view = require("stable_folds.core.view")
local host_vim = rawget(_G, "vim")
_G.vim = nil

t.test("defaults and normalization do not mutate caller-owned options", function()
  local filter = function()
    return false
  end
  local opts = { filter = filter }
  local result, messages = config.normalize(opts)
  t.equal(result.filter, filter)
  t.equal(opts.filter, filter)
  t.equal(messages, {})
  t.equal(config.defaults().filter(1), true)
end)

t.test("invalid options and unknown keys produce deterministic diagnostics", function()
  for _, input in ipairs({ false, 1, "bad", { filter = 1 }, { filter = false } }) do
    local result, messages = config.normalize(input)
    t.equal(result.filter(1), true)
    t.equal(#messages, 1)
  end
  local _, messages = config.normalize({ z = true, a = true })
  t.equal(messages, { "stable-folds: unknown option a", "stable-folds: unknown option z" })
  local _, empty = config.normalize()
  t.equal(empty, {})
end)

t.test("integer validation rejects fractions, infinities, NaN and negative values", function()
  t.equal(config.integer(0), true)
  t.equal(config.integer(10), true)
  for _, value in ipairs({ -1, 0.5, math.huge, 0 / 0, "1", false }) do
    t.equal(config.integer(value), false)
  end
end)

t.test("exclusive ends on column zero omit the following line", function()
  t.equal(ranges.bounds({ start_row = 1, start_col = 2, end_row = 4, end_col = 0 }, 6), { start = 2, stop = 4 })
  t.equal(ranges.bounds({ start_row = 1, start_col = 2, end_row = 4, end_col = 1 }, 6), { start = 2, stop = 5 })
  t.equal(ranges.bounds({ start_row = 0, start_col = 0, end_row = 6, end_col = 0 }, 6), { start = 1, stop = 6 })
end)

t.test("invalid, reversed, single-line and out-of-buffer ranges are discarded", function()
  ---@type StableFoldsRawRange[]
  local input = {
    { start_row = -1, start_col = 0, end_row = 2, end_col = 1 },
    { start_row = 0, start_col = -1, end_row = 2, end_col = 1 },
    { start_row = 0, start_col = 0, end_row = math.huge, end_col = 1 },
    { start_row = 0.5, start_col = 0, end_row = 2, end_col = 1 },
    { start_row = 2, start_col = 0, end_row = 1, end_col = 1 },
    { start_row = 0, start_col = 2, end_row = 0, end_col = 1 },
    { start_row = 0, start_col = 0, end_row = 0, end_col = 8 },
    { start_row = 0, start_col = 0, end_row = 1, end_col = 0 },
    { start_row = 8, start_col = 0, end_row = 9, end_col = 1 },
    { start_row = 0, start_col = 0, end_row = 4, end_col = 1 },
  }
  t.equal(ranges.normalize(input, 4), {})
end)

t.test("ranges are deduplicated globally and ordered without mutating input", function()
  local input = {
    { start_row = 2, start_col = 0, end_row = 4, end_col = 1 },
    { start_row = 0, start_col = 0, end_row = 3, end_col = 1 },
    { start_row = 0, start_col = 0, end_row = 5, end_col = 1 },
    { start_row = 2, start_col = 0, end_row = 4, end_col = 1 },
  }
  local original = t.copy(input)
  t.equal(ranges.normalize(input, 6), { { start = 1, stop = 6 }, { start = 1, stop = 4 }, { start = 3, stop = 5 } })
  t.equal(input, original)
end)

t.test("candidate headers are independent of nesting and size limits", function()
  t.equal(ranges.headers({ { start = 1, stop = 6 }, { start = 1, stop = 4 }, { start = 2, stop = 3 } }, { "a", "b" }), {
    { line = 1, header = "a" },
    { line = 2, header = "b" },
  })
end)

t.test("levels keep boundaries, nesting and gaps", function()
  t.equal(
    levels.build({ { start = 1, stop = 4 }, { start = 2, stop = 3 }, { start = 6, stop = 7 } }, 8, 1, 2),
    { ">1", ">2", "2", "1", "0", ">1", "1", "0" }
  )
end)

t.test("foldminlines is strict and foldnestmax clamps deeper starts", function()
  local input = { { start = 1, stop = 4 }, { start = 2, stop = 3 } }
  t.equal(levels.build(input, 5, 2, 1), { ">1", "1", "1", "1", "0" })
  t.equal(levels.build(input, 5, 1, 1), { ">1", "1", "1", "1", "0" })
  t.equal(levels.build(input, 5, 4, 1), { "0", "0", "0", "0", "0" })
  t.equal(levels.build(input, 5, 0, 0), { "0", "0", "0", "0", "0" })
end)

t.test("adjacent captures sharing a boundary start the next fold on that line", function()
  t.equal(
    levels.build({ { start = 1, stop = 3 }, { start = 3, stop = 5 } }, 6, 1, 3),
    { ">1", "1", ">1", "1", "1", "0" }
  )
  t.equal(levels.build({}, 2, 0, 10), { "0", "0" })
end)

t.test("event counts include several captures starting and ending together", function()
  local starts, stops = levels.events({ { start = 1, stop = 4 }, { start = 1, stop = 3 }, { start = 2, stop = 4 } }, 1)
  t.equal(starts, { [1] = 2, [2] = 1 })
  t.equal(stops, { [3] = 1, [4] = 2 })
end)

t.test("inserted duplicate cannot steal the positional identity of the original", function()
  local plan = tracking.match({ { id = 7, header = "same", line = 6, new = false } }, {
    { line = 1, header = "same" },
    { line = 6, header = "same" },
  }, true)
  t.equal(plan, {
    marks = {
      { line = 1, header = "same", new = true },
      { id = 7, line = 6, header = "same", new = false, unchanged = true },
    },
    delete = {},
  })
end)

t.test("formatter recovery reuses unique headers even after a full replacement", function()
  local old = { { id = 1, header = "a", line = 10, new = false }, { id = 2, header = "b", line = 10, new = true } }
  local before = t.copy(old)
  t.equal(tracking.match(old, { { line = 1, header = "b" }, { line = 4, header = "a" } }, true), {
    marks = { { id = 2, line = 1, header = "b", new = true }, { id = 1, line = 4, header = "a", new = false } },
    delete = {},
  })
  t.equal(old, before)
end)

t.test("ambiguous old or new headers never use formatter fallback", function()
  local old = { { id = 1, header = "a", line = 10, new = false }, { id = 2, header = "a", line = 10, new = false } }
  local plan = tracking.match(old, { { line = 1, header = "a" } }, true)
  t.equal(plan.delete, { 1, 2 })
  t.equal(plan.marks, { { line = 1, header = "a", new = true } })
  local another = tracking.match({ old[1] }, { { line = 1, header = "a" }, { line = 3, header = "a" } }, true)
  t.equal(another.delete, { 1 })
end)

t.test("colliding positions with identical headers are treated conservatively", function()
  local plan = tracking.match(
    { { id = 1, header = "a", line = 1, new = false }, { id = 2, header = "a", line = 1, new = false } },
    { { line = 1, header = "a" } },
    false
  )
  t.equal(plan.marks, { { line = 1, header = "a", new = false } })
  t.equal(plan.delete, { 1, 2 })
end)

t.test("removed marks are deleted and new baselines do not auto-open folds", function()
  t.equal(tracking.match({ { id = 1, header = "a", new = false } }, {}, false), { marks = {}, delete = { 1 } })
  t.equal(tracking.match({}, { { line = 1, header = "b" } }, false), {
    marks = { { line = 1, header = "b", new = false } },
    delete = {},
  })
end)

t.test("snapshot identity ignores window options but includes tick, filetype and language", function()
  local context = {
    buf = 1,
    win = 10,
    tick = 1,
    filetype = "lua",
    lang = "lua",
    buftype = "",
    line = 1,
    minlines = 1,
    nestmax = 1,
    foldlevel = 99,
  }
  local signature = cache.signature(context)
  context.minlines, context.nestmax = 5, 2
  t.equal(cache.matches(signature, context), true)
  context.tick = 2
  t.equal(cache.matches(signature, context), false)
  context.tick, context.lang = 1, "other"
  t.equal(cache.matches(signature, context), false)
  context.lang, context.filetype = "lua", "other"
  t.equal(cache.matches(signature, context), false)
  t.equal(cache.matches(nil, context), false)
end)

t.test("view identity includes snapshot, buffer and window fold limits", function()
  local snapshot =
    { tick = 1, filetype = "lua", lang = "lua", line_count = 0, headers = {}, ranges = {}, available = true }
  local context = {
    buf = 1,
    win = 10,
    tick = 1,
    filetype = "lua",
    lang = "lua",
    buftype = "",
    line = 1,
    minlines = 1,
    nestmax = 1,
    foldlevel = 99,
  }
  local view = { buf = 1, snapshot = snapshot, minlines = 1, nestmax = 1, levels = {} }
  t.equal(cache.view_matches(view, snapshot, context), true)
  t.equal(cache.view_matches(view, t.copy(snapshot), context), false)
  context.minlines = 3
  t.equal(cache.view_matches(view, snapshot, context), false)
  context.minlines, context.buf = 1, 2
  t.equal(cache.view_matches(view, snapshot, context), false)
end)

t.test("pre-edit closed states follow identities and ignore invisible or deleted starts", function()
  t.equal(
    tracking.restore({
      { id = 3, line = 6, header = "a", new = false },
      { id = 4, line = 1, header = "b", new = false },
      { id = 5, line = 2, header = "hidden", new = false },
      { id = 6, header = "deleted", new = false },
    }, { [3] = true, [4] = false, [5] = true, [6] = true }, { ">1", "1", "1", "1", "0", ">1" }),
    {
      { line = 1, closed = false },
      { line = 6, closed = true },
    }
  )
  t.equal(tracking.restore({}, nil, {}), {})
end)

t.test("native-state positions account for inserted and replaced row spans without changing marks", function()
  local old = {
    { id = 1, header = "a", line = 1, new = false },
    { id = 2, header = "b", line = 6, new = false },
    { id = 3, header = "missing", new = false },
  }
  local before = t.copy(old)
  local inserted = tracking.shifted(old, { start_row = 0, start_col = 0, old_rows = 0, new_rows = 2 })
  t.equal(inserted[1].line, 1)
  t.equal(inserted[2].line, 8)
  local replaced = tracking.shifted(old, { start_row = 0, start_col = 0, old_rows = 9, new_rows = 10 })
  t.equal(replaced[1].line, 1)
  t.equal(replaced[2].line, 7)
  local body = tracking.shifted(old, { start_row = 1, start_col = 0, old_rows = 1, new_rows = 2 })
  t.equal(body[1].line, 1)
  t.equal(body[2].line, 7)
  t.equal(tracking.shifted(old, nil), old)
  t.equal(old, before)
end)

t.test("window view cache reuses both existing views and shared level arrays", function()
  local snapshot = {
    tick = 1,
    filetype = "lua",
    lang = "lua",
    line_count = 3,
    headers = { { line = 1, header = "a" } },
    ranges = { { start = 1, stop = 3 } },
    available = true,
  }
  local context = {
    buf = 1,
    win = 10,
    tick = 1,
    filetype = "lua",
    lang = "lua",
    buftype = "",
    line = 1,
    minlines = 1,
    nestmax = 1,
    foldlevel = 99,
  }
  local views = {}
  local first = cache.view(snapshot, context, views)
  views[10] = first
  assert(cache.view(snapshot, context, views) == first)
  context.win = 20
  local second = cache.view(snapshot, context, views)
  assert(second.levels == first.levels)
  context.minlines = 3
  local excluded = cache.view(snapshot, context, views)
  t.equal(excluded.levels, { "0", "0", "0" })
  assert(excluded.levels ~= first.levels)
end)

t.test("serialized fold flags preserve explicit open overrides and hidden children", function()
  t.equal(
    view.states({
      "setlocal foldlevel=0",
      "1",
      "sil! normal! zc",
      "1",
      "sil! normal! zo",
      "2",
      "sil! normal! zc",
      "999",
      "call UnsafeFunction()",
    }, {
      { id = 1, header = "outer", line = 1, level = 1, new = false },
      { id = 2, header = "inner", line = 2, level = 2, new = false },
      { id = 3, header = "default", line = 6, level = 1, new = false },
      { id = 4, header = "unrepresented", line = 7, new = false },
    }, 0),
    { false, true, true }
  )
end)

t.test("serialized fold defaults honor depth and preserve explicit closed overrides", function()
  t.equal(
    view.states({ "6", "sil! normal! zc" }, {
      { id = 1, header = "open", line = 1, level = 1, new = false },
      { id = 2, header = "closed", line = 6, level = 1, new = false },
      { id = 3, header = "deep", line = 8, level = 3, new = false },
    }, 2),
    { false, true, true }
  )
end)

t.test("new option defaults preserve existing behavior", function()
  local opts = config.defaults()
  t.equal(opts.new_folds, "open")
  t.equal(opts.include_injections, true)
  t.equal(opts.max_lines, 0)
  t.equal(opts.max_bytes, 0)
  t.equal(opts.notify_errors, true)
end)

t.test("new options normalize without losing false or zero values", function()
  local input =
    { new_folds = "inherit", include_injections = false, max_lines = 10, max_bytes = 0, notify_errors = false }
  local opts, messages = config.normalize(input)
  t.equal(messages, {})
  for key, value in pairs(input) do
    t.equal(opts[key], value)
  end
end)

t.test("invalid enum, boolean and size options fall back independently", function()
  for _, input in ipairs({
    { new_folds = "closed" },
    { new_folds = false },
    { include_injections = 0 },
    { notify_errors = "false" },
    { max_lines = -1 },
    { max_bytes = 0.5 },
    { max_lines = math.huge },
    { max_bytes = 0 / 0 },
  }) do
    local opts, messages = config.normalize(input)
    t.equal(#messages, 1)
    for key in pairs(input) do
      t.equal(opts[key], config.defaults()[key])
    end
  end
end)

t.test("size limits are inclusive, independent and disabled by zero", function()
  local opts = config.defaults()
  t.equal(config.within_limits({ lines = 999, bytes = 999 }, opts), true)
  opts.max_lines, opts.max_bytes = 10, 100
  t.equal(config.within_limits({ lines = 10, bytes = 100 }, opts), true)
  t.equal(config.within_limits({ lines = 11, bytes = 100 }, opts), false)
  t.equal(config.within_limits({ lines = 10, bytes = 101 }, opts), false)
end)

t.test("insertions at a noninitial fold header translate starts and ends together", function()
  local edit = { start_row = 1, start_col = 0, old_rows = 0, new_rows = 2 }
  t.equal(ranges.shift({ { start = 2, stop = 5 }, { start = 7, stop = 9 } }, edit), {
    { start = 4, stop = 7 },
    { start = 9, stop = 11 },
  })
  t.equal(tracking.shifted({ { id = 1, header = "f", line = 2, new = false } }, edit)[1].line, 4)
  edit.start_col = 3
  t.equal(ranges.shift({ { start = 2, stop = 5 } }, edit), { { start = 2, stop = 7 } })
end)

t.test("the first native fold start stays anchored during insertion at buffer start", function()
  t.equal(
    ranges.shift({ { start = 1, stop = 4 }, { start = 6, stop = 9 } }, {
      start_row = 0,
      start_col = 0,
      old_rows = 0,
      new_rows = 2,
    }),
    { { start = 1, stop = 6 }, { start = 8, stop = 11 } }
  )
end)

t.run("stable-folds core")
_G.vim = host_vim
