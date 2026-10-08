-- Run with LuaJIT or nvim --clean --headless -i NONE -l tests/core.lua.
local source = debug.getinfo(1, "S").source:sub(2)
local test_dir = source:match("^(.*[/\\])") or "./"
package.path = test_dir .. "../lua/?.lua;" .. package.path

-- Neovim's module searcher itself needs vim; load before disabling its globals.
local core = require("tab_buffers.core")
-- Exercise every core method without Neovim globals, even under the headless runner.
local host_vim = rawget(_G, "vim")
_G.vim = nil
local tests = {}

local function equal(actual, expected, path)
  path = path or "result"
  assert(type(actual) == type(expected), path .. ": types differ")
  if type(expected) ~= "table" then
    assert(actual == expected, path .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    return
  end
  for key, value in pairs(expected) do
    equal(actual[key], value, path .. "." .. tostring(key))
  end
  for key in pairs(actual) do
    assert(expected[key] ~= nil, path .. ": unexpected key " .. tostring(key))
  end
end

local function snapshot(model)
  local result = {}
  for _, tab in ipairs(model:tabs()) do
    result[tab] = model:buffers(tab)
  end
  return result
end

local function raises(fn, pattern)
  local ok, err = pcall(fn)
  assert(not ok, "expected an error")
  if pattern then
    assert(tostring(err):find(pattern, 1, true), "unexpected error: " .. tostring(err))
  end
end

local function test(name, fn)
  tests[#tests + 1] = { name = name, run = fn }
end

local function fixture()
  local model = core.new()
  for _, buf in ipairs({ 10, 20, 30, 40 }) do
    model:attach(1, buf)
  end
  model:attach(2, 30)
  model:attach(2, 50)
  return model
end

test("empty queries do not create tabs", function()
  local model = core.new()
  equal(model:tabs(), {})
  equal(model:buffers(1), {})
  equal(model:owners(10), {})
  equal(model:contains(1, 10), false)
  equal(model:tabs(), {})
end)

test("tab creation is idempotent and IDs are sorted", function()
  local model = core.new()
  equal(model:ensure_tab(40), true)
  equal(model:ensure_tab(2), true)
  equal(model:ensure_tab(40), false)
  equal(model:tabs(), { 2, 40 })
  equal(model:buffers(40), {})
end)

test("attach preserves order and ignores duplicate membership", function()
  local model = core.new()
  equal(model:attach(5, 30), true)
  model:attach(5, 10)
  equal(model:attach(5, 30, 2), false)
  equal(model:buffers(5), { 30, 10 })
end)

test("insertion positions are clamped", function()
  local model = core.new()
  model:attach(1, 10, 100)
  model:attach(1, 20, -10)
  model:attach(1, 30, 2)
  model:attach(1, 40, 100)
  equal(model:buffers(1), { 20, 30, 10, 40 })
end)

test("shared buffers have independent positions and sorted owners", function()
  local model = core.new()
  model:attach(50, 10)
  model:attach(3, 20)
  model:attach(3, 10)
  equal(model:owners(10), { 3, 50 })
  equal(model:buffers(3), { 20, 10 })
  equal(model:buffers(50), { 10 })
end)

test("returned lists cannot change membership", function()
  local model = fixture()
  local before = snapshot(model)
  model:tabs()[1] = 900
  model:buffers(1)[1] = 900
  model:owners(30)[1] = 900
  equal(snapshot(model), before)
end)

test("model instances are independent", function()
  local first, second = core.new(), core.new()
  first:attach(1, 10)
  second:attach(1, 20)
  first:detach(1, 10)
  equal(second:buffers(1), { 20 })
end)

test("detach reports shared and orphaned buffers and retains empty tabs", function()
  local model = fixture()
  equal({ model:detach(1, 30) }, { true, false })
  equal(model:owners(30), { 2 })
  equal({ model:detach(2, 30) }, { true, true })
  equal({ model:detach(2, 30) }, { false, false })
  equal({ model:detach(90, 30) }, { false, false })
  equal({ model:detach(2, 50) }, { true, true })
  equal(model:tabs(), { 1, 2 })
  equal(model:buffers(2), {})
end)

test("transfer creates a target and removes source membership", function()
  local model = fixture()
  equal(model:transfer(1, 7, 20, 1), true)
  equal(model:buffers(1), { 10, 30, 40 })
  equal(model:buffers(7), { 20 })
  equal(model:owners(20), { 7 })
end)

test("transfer to an existing owner preserves destination position", function()
  local model = fixture()
  equal(model:transfer(1, 2, 30, 2), true)
  equal(model:buffers(2), { 30, 50 })
  equal(model:owners(30), { 2 })
end)

test("missing and same-tab transfers do not create or reorder tabs", function()
  local model = fixture()
  local before = snapshot(model)
  equal(model:transfer(1, 1, 20, 1), false)
  equal(model:transfer(1, 9, 90), false)
  equal(model:transfer(9, 8, 10), false)
  equal(snapshot(model), before)
end)

test("forget removes all memberships without removing tabs", function()
  local model = fixture()
  equal(model:forget_buffer(30), { 1, 2 })
  equal(model:owners(30), {})
  equal(model:buffers(1), { 10, 20, 40 })
  equal(model:buffers(2), { 50 })
  equal(model:forget_buffer(30), {})
end)

test("removing a tab reports only exclusive buffers as orphans", function()
  local model = fixture()
  equal(model:remove_tab(1), { buffers = { 10, 20, 30, 40 }, orphans = { 10, 20, 40 } })
  equal(model:buffers(2), { 30, 50 })
  equal(model:tabs(), { 2 })
  equal(model:remove_tab(1), { buffers = {}, orphans = {} })
  model:ensure_tab(7)
  equal(model:remove_tab(7), { buffers = {}, orphans = {} })
end)

test("invalid IDs and positions fail before changing state", function()
  local model = fixture()
  local before = snapshot(model)
  local invalid_ids = { 0, -1, 1.5, math.huge, -math.huge, 0 / 0, "1", false, {} }
  for _, value in ipairs(invalid_ids) do
    raises(function()
      model:ensure_tab(value)
    end)
    raises(function()
      model:buffers(value)
    end)
    raises(function()
      model:contains(1, value)
    end)
    raises(function()
      model:contains(value, 10)
    end)
    raises(function()
      model:owners(value)
    end)
    raises(function()
      model:attach(value, 99)
    end)
    raises(function()
      model:attach(99, value)
    end)
    raises(function()
      model:detach(value, 10)
    end)
    raises(function()
      model:detach(1, value)
    end)
    raises(function()
      model:transfer(value, 2, 10)
    end)
    raises(function()
      model:transfer(1, value, 10)
    end)
    raises(function()
      model:transfer(1, 2, value)
    end)
    raises(function()
      model:forget_buffer(value)
    end)
    raises(function()
      model:remove_tab(value)
    end)
  end
  for _, value in ipairs({ 1.5, math.huge, "1", false }) do
    raises(function()
      model:attach(99, 99, value)
    end)
    raises(function()
      model:transfer(1, 99, 10, value)
    end)
  end
  raises(function()
    model:ensure_tab(nil)
  end)
  equal(snapshot(model), before)
end)

test("move_to shifts intervening buffers and only changes one tab", function()
  local model = fixture()
  equal(model:move_to(1, 30, 1), true)
  equal(model:buffers(1), { 30, 10, 20, 40 })
  equal(model:buffers(2), { 30, 50 })
  equal(model:owners(30), { 1, 2 })
  equal(model:move_to(1, 30, 3), true)
  equal(model:buffers(1), { 10, 20, 30, 40 })
end)

test("moves clamp at both ends and report no changes", function()
  local model = fixture()
  equal(model:move_to(1, 20, -50), true)
  equal(model:move_to(1, 20, 0), false)
  equal(model:move(1, 20, 100), true)
  equal(model:buffers(1), { 10, 30, 40, 20 })
  equal(model:move(1, 20, 1), false)
  equal(model:move(1, 20, -2), true)
  equal(model:buffers(1), { 10, 20, 30, 40 })
  equal(model:move(1, 20, 0), false)
  equal(model:move_to(1, 20, 2), false)
  equal(model:move(1, 99, 1), false)
  equal(model:move_to(99, 20, 1), false)
  equal(model:move(99, 20, 1), false)
  local single = core.new()
  single:attach(1, 10)
  equal(single:move(1, 10, 1), false)
end)

test("reorder accepts only exact permutations and copies the input", function()
  local model = fixture()
  local ordered = { 40, 30, 20, 10 }
  equal(model:reorder(1, ordered), true)
  ordered[1] = 99
  equal(model:buffers(1), { 40, 30, 20, 10 })
  equal(model:reorder(1, { 40, 30, 20, 10 }), false)
  equal(model:buffers(2), { 30, 50 })
  model:ensure_tab(7)
  equal(model:reorder(7, {}), false)
  equal(model:reorder(99, {}), false)
  equal(model:reorder(99, { 10 }), false)
  local before = snapshot(model)
  for _, invalid in ipairs({
    { 10, 20 },
    { 10, 20, 30, 40, 50 },
    { 10, 20, 30, 99 },
    { 10, 10, 30, 40 },
    { [1] = 10, [3] = 30 },
    { 10, label = 20 },
    { 10, false },
    false,
  }) do
    raises(function()
      model:reorder(1, invalid)
    end)
    equal(snapshot(model), before)
  end
end)

test("sorting uses buffer IDs and preserves ties and other tabs", function()
  local model = fixture()
  local keys = { [10] = "z", [20] = "a", [30] = "a", [40] = "b" }
  equal(
    model:sort(1, function(a, b)
      return keys[a] < keys[b]
    end),
    true
  )
  equal(model:buffers(1), { 20, 30, 40, 10 })
  equal(model:buffers(2), { 30, 50 })
  equal(
    model:sort(1, function(a, b)
      return keys[a] < keys[b]
    end),
    false
  )
  equal(
    model:sort(1, function()
      return false
    end),
    false
  )
  -- Sorting is a one-time operation, not a mode applied to later additions.
  model:attach(1, 5)
  equal(model:buffers(1), { 20, 30, 40, 10, 5 })
end)

test("empty and singleton sorts do not invoke the comparator", function()
  local model = core.new()
  model:ensure_tab(1)
  model:attach(2, 10)
  local function never()
    error("comparator should not run")
  end
  equal(model:sort(1, never), false)
  equal(model:sort(2, never), false)
  equal(model:sort(99, never), false)
  equal(model:tabs(), { 1, 2 })
end)

test("sort errors leave order unchanged and release the mutation guard", function()
  local model = fixture()
  local before = snapshot(model)
  local calls = 0
  raises(function()
    model:sort(1, function(a, b)
      calls = calls + 1
      if calls == 3 then
        error("comparator failed")
      end
      return a > b
    end)
  end, "comparator failed")
  equal(snapshot(model), before)
  equal(model:attach(1, 60), true)
  equal(
    model:sort(1, function(a, b)
      return a > b
    end),
    true
  )
  equal(model:buffers(1), { 60, 40, 30, 20, 10 })
end)

test("sort comparators can query but cannot mutate their own model", function()
  local model = fixture()
  local before = snapshot(model)
  local mutations = {
    function()
      model:ensure_tab(7)
    end,
    function()
      model:attach(1, 60)
    end,
    function()
      model:detach(1, 10)
    end,
    function()
      model:transfer(1, 7, 10)
    end,
    function()
      model:forget_buffer(30)
    end,
    function()
      model:remove_tab(2)
    end,
    function()
      model:move_to(1, 10, 2)
    end,
    function()
      model:move(1, 10, 1)
    end,
    function()
      model:reorder(1, { 40, 30, 20, 10 })
    end,
    function()
      model:sort(2, function(a, b)
        return a < b
      end)
    end,
  }
  for _, mutate in ipairs(mutations) do
    raises(function()
      model:sort(1, function()
        mutate()
        return false
      end)
    end, "sort comparator")
    equal(snapshot(model), before)
  end
  equal(
    model:sort(1, function(a, b)
      equal(model:owners(30), { 1, 2 })
      return a > b
    end),
    true
  )
end)

test("neighbors wrap by default and support arbitrary signed offsets", function()
  local model = fixture()
  equal(model:neighbor(1, 10, 1), 20)
  equal(model:neighbor(1, 40, 1), 10)
  equal(model:neighbor(1, 10, -1), 40)
  equal(model:neighbor(1, 20, 9), 30)
  equal(model:neighbor(1, 20, -9), 10)
  equal(model:neighbor(1, 20, 0), 20)
  equal(model:neighbor(1, 20, 4, true), 20)
  equal(model:neighbor(1, 40, 1, false), nil)
  equal(model:neighbor(1, 10, -1, false), nil)
  equal(model:neighbor(1, 20, 1, false), 30)
  equal(model:neighbor(1, 20, 10, false), nil)
  equal(model:neighbor(99, 10, 1), nil)
  equal(model:neighbor(1, 99, 1), nil)
end)

test("navigation follows each tab's current order", function()
  local model = fixture()
  model:move_to(1, 30, 1)
  equal(model:neighbor(1, 30, 1), 10)
  equal(model:neighbor(2, 30, 1), 50)
  equal(model:replacement(1, 30), 10)
end)

test("large cyclic offsets preserve the starting position", function()
  local model = fixture()
  equal(model:neighbor(1, 20, 2 ^ 53), 20)
  equal(model:neighbor(1, 20, -(2 ^ 53)), 20)
  equal(model:neighbor(1, 30, 2 ^ 53), 30)
end)

test("replacement prefers right then left and handles missing and singleton buffers", function()
  local model = fixture()
  equal(model:replacement(1, 20), 30)
  equal(model:replacement(1, 10), 20)
  equal(model:replacement(1, 40), 30)
  equal(model:replacement(1, 99), nil)
  equal(model:replacement(99, 10), nil)
  model:attach(7, 10)
  equal(model:replacement(7, 10), nil)
  equal(model:neighbor(7, 10, 1), 10)
  equal(model:neighbor(7, 10, -1, false), nil)
end)

test("invalid ordering and navigation arguments do not change state", function()
  local model = fixture()
  local before = snapshot(model)
  for _, invalid in ipairs({ 1.5, math.huge, "1", false, {} }) do
    raises(function()
      model:move_to(1, 10, invalid)
    end)
    raises(function()
      model:move(1, 10, invalid)
    end)
    raises(function()
      model:neighbor(1, 10, invalid)
    end)
    raises(function()
      model:sort(1, invalid)
    end)
  end
  raises(function()
    model:neighbor(1, 10, 1, 1)
  end)
  raises(function()
    model:move_to(0, 10, 1)
  end)
  raises(function()
    model:move_to(1, 0, 1)
  end)
  raises(function()
    model:move(0, 10, 1)
  end)
  raises(function()
    model:move(1, 0, 1)
  end)
  raises(function()
    model:neighbor(0, 10, 1)
  end)
  raises(function()
    model:neighbor(1, 0, 1)
  end)
  raises(function()
    model:replacement(0, 10)
  end)
  raises(function()
    model:replacement(1, 0)
  end)
  raises(function()
    model:reorder(0, {})
  end)
  raises(function()
    model:sort(0, function()
      return false
    end)
  end)
  equal(snapshot(model), before)
end)

test("all target modes follow tab order without changing state", function()
  local model = fixture()
  model:reorder(1, { 40, 20, 30, 10 })
  local before = snapshot(model)
  equal(model:targets(1, "one", 30), { 30 })
  equal(model:targets(1, "all"), { 40, 20, 30, 10 })
  equal(model:targets(1, "all", 99), { 40, 20, 30, 10 })
  equal(model:targets(1, "others", 30), { 40, 20, 10 })
  equal(model:targets(1, "left", 30), { 40, 20 })
  equal(model:targets(1, "right", 30), { 10 })
  equal(model:targets(1, "left", 40), {})
  equal(model:targets(1, "right", 10), {})
  equal(model:targets(2, "right", 30), { 50 })
  equal(snapshot(model), before)
end)

test("missing pivots never select other buffers accidentally", function()
  local model = fixture()
  for _, mode in ipairs({ "one", "others", "left", "right" }) do
    equal(model:targets(1, mode), {})
    equal(model:targets(1, mode, 99), {})
    equal(model:targets(99, mode, 10), {})
  end
  equal(model:targets(99, "all"), {})
  model:attach(7, 10)
  equal(model:targets(7, "one", 10), { 10 })
  equal(model:targets(7, "others", 10), {})
  equal(model:targets(7, "left", 10), {})
  equal(model:targets(7, "right", 10), {})
end)

test("close plans normalize selections and separate shared from exclusive buffers", function()
  local model = fixture()
  local before = snapshot(model)
  equal(model:plan_close(1, { 40, 30, 20, 30, 99 }), {
    buffers = { 20, 30, 40 },
    shared = { 30 },
    exclusive = { 20, 40 },
    remaining = { 10 },
  })
  equal(model:plan_close(1, model:targets(1, "all")), {
    buffers = { 10, 20, 30, 40 },
    shared = { 30 },
    exclusive = { 10, 20, 40 },
    remaining = {},
  })
  equal(model:plan_close(1, {}), {
    buffers = {},
    shared = {},
    exclusive = {},
    remaining = { 10, 20, 30, 40 },
  })
  equal(model:plan_close(99, { 10 }), { buffers = {}, shared = {}, exclusive = {}, remaining = {} })
  equal(snapshot(model), before)
end)

test("selection, close and removal reports are independent snapshots", function()
  local model = fixture()
  local before = snapshot(model)
  local targets = model:targets(1, "all")
  local plan = model:plan_close(1, targets)
  targets[1] = 99
  plan.buffers[1] = 99
  plan.shared[1] = 99
  plan.exclusive[1] = 99
  equal(snapshot(model), before)
  local partial = model:plan_close(1, { 10 })
  partial.remaining[1] = 99
  equal(model:buffers(1), { 10, 20, 30, 40 })
  local removed = model:remove_tab(1)
  removed.buffers[3] = 99
  removed.orphans[1] = 99
  equal(model:buffers(2), { 30, 50 })
end)

test("plans do not retain selections or refresh themselves after ownership changes", function()
  local model = fixture()
  local selected = { 30 }
  local plan = model:plan_close(1, selected)
  selected[1] = 10
  model:detach(2, 30)
  equal(plan, { buffers = { 30 }, shared = { 30 }, exclusive = {}, remaining = { 10, 20, 40 } })
  equal(model:plan_close(1, { 30 }), {
    buffers = { 30 },
    shared = {},
    exclusive = { 30 },
    remaining = { 10, 20, 40 },
  })
end)

test("partial close commits only successful targets and leaves failures owned", function()
  local model = fixture()
  local plan = model:plan_close(1, model:targets(1, "others", 10))
  -- Simulate an adapter: 20 is modified and cannot be deleted, 30 is shared,
  -- and deletion of 40 succeeds. The core itself knows nothing about text.
  local deleted = {}
  for _, buf in ipairs(plan.buffers) do
    if #model:owners(buf) > 1 then
      model:detach(1, buf)
    elseif buf ~= 20 then
      deleted[#deleted + 1] = buf
      model:detach(1, buf)
    end
  end
  equal(deleted, { 40 })
  equal(model:buffers(1), { 10, 20 })
  equal(model:buffers(2), { 30, 50 })
  equal(model:owners(20), { 1 })
end)

test("external tab removal allows orphan recovery in another tab", function()
  local model = fixture()
  local removed = model:remove_tab(1)
  -- A future adapter may preserve modified orphan 20 by attaching it elsewhere.
  model:attach(2, 20)
  equal(removed.orphans, { 10, 20, 40 })
  equal(model:owners(20), { 2 })
  equal(model:buffers(2), { 30, 50, 20 })
end)

test("invalid selections fail without changing state", function()
  local model = fixture()
  local before = snapshot(model)
  for _, mode in ipairs({ "invalid", false, {}, 1 }) do
    raises(function()
      model:targets(1, mode, 10)
    end, "target mode")
  end
  raises(function()
    model:targets(1, nil)
  end)
  raises(function()
    model:targets(0, "all")
  end)
  raises(function()
    model:targets(1, "all", 0)
  end)
  raises(function()
    model:targets(1, "others", "10")
  end)
  raises(function()
    model:plan_close(0, {})
  end)
  for _, invalid in ipairs({ false, { 0 }, { 1.5 }, { [2] = 10 }, { 10, other = 20 } }) do
    raises(function()
      model:plan_close(1, invalid)
    end)
  end
  raises(function()
    model:plan_close(1, nil)
  end)
  equal(snapshot(model), before)
end)

test("mixed deterministic operations preserve ownership and planning invariants", function()
  local model = core.new()
  -- This oracle tracks only membership sets, independently of ordered lists.
  local members = {}
  local seed = 9173
  local function random(maximum)
    seed = (seed * 48271) % 2147483647
    return (seed % maximum) + 1
  end
  local function expected_owners(buf)
    local result = {}
    for tab = 1, 6 do
      if members[tab] and members[tab][buf] then
        result[#result + 1] = tab
      end
    end
    return result
  end
  local function verify()
    local expected_tabs = {}
    for tab = 1, 6 do
      if members[tab] then
        expected_tabs[#expected_tabs + 1] = tab
      end
      local actual = model:buffers(tab)
      local seen = {}
      for _, buf in ipairs(actual) do
        assert(not seen[buf], "duplicate membership")
        seen[buf] = true
      end
      equal(seen, members[tab] or {})
      local before = snapshot(model)
      local all = model:targets(tab, "all")
      equal(all, actual)
      local plan = model:plan_close(tab, all)
      equal(plan.buffers, actual)
      equal(plan.remaining, {})
      local shared, exclusive = {}, {}
      for _, buf in ipairs(actual) do
        if #expected_owners(buf) > 1 then
          shared[#shared + 1] = buf
        else
          exclusive[#exclusive + 1] = buf
        end
      end
      equal(plan.shared, shared)
      equal(plan.exclusive, exclusive)
      equal(snapshot(model), before)
    end
    equal(model:tabs(), expected_tabs)
    for buf = 1, 12 do
      equal(model:owners(buf), expected_owners(buf))
    end
  end
  for _ = 1, 1500 do
    local operation, tab, buf = random(10), random(6), random(12)
    if operation == 1 then
      model:ensure_tab(tab)
      members[tab] = members[tab] or {}
    elseif operation == 2 then
      model:attach(tab, buf, random(10) - 3)
      members[tab] = members[tab] or {}
      members[tab][buf] = true
    elseif operation == 3 then
      local present = members[tab] and members[tab][buf] or false
      local removed, orphan = model:detach(tab, buf)
      equal(removed, present)
      if present then
        members[tab][buf] = nil
      end
      equal(orphan, present and #expected_owners(buf) == 0)
    elseif operation == 4 then
      local to = random(6)
      local present = members[tab] and members[tab][buf] or false
      equal(model:transfer(tab, to, buf), tab ~= to and present)
      if tab ~= to and present then
        members[to] = members[to] or {}
        members[to][buf] = true
        members[tab][buf] = nil
      end
    elseif operation == 5 then
      equal(model:forget_buffer(buf), expected_owners(buf))
      for _, set in pairs(members) do
        set[buf] = nil
      end
    elseif operation == 6 then
      local previous = model:buffers(tab)
      local report = model:remove_tab(tab)
      members[tab] = nil
      equal(report.buffers, previous)
      local orphans = {}
      for _, previous_buf in ipairs(previous) do
        if #expected_owners(previous_buf) == 0 then
          orphans[#orphans + 1] = previous_buf
        end
      end
      equal(report.orphans, orphans)
    elseif operation == 7 then
      model:move(tab, buf, random(20) - 10)
    elseif operation == 8 then
      model:sort(tab, function(a, b)
        return a < b
      end)
      local ordered = model:buffers(tab)
      for i = 2, #ordered do
        assert(ordered[i - 1] < ordered[i], "sort order incorrect")
      end
    elseif operation == 9 then
      local previous = model:buffers(tab)
      local reversed = {}
      for i = #previous, 1, -1 do
        reversed[#reversed + 1] = previous[i]
      end
      model:reorder(tab, reversed)
      equal(model:buffers(tab), reversed)
    else
      local before = snapshot(model)
      local partial = model:plan_close(tab, { buf, buf, 99 })
      equal(partial.buffers, model:contains(tab, buf) and { buf } or {})
      model:neighbor(tab, buf, random(20) - 10)
      model:replacement(tab, buf)
      for _, mode in ipairs({ "one", "others", "left", "right" }) do
        model:targets(tab, mode, buf)
      end
      equal(snapshot(model), before)
    end
    verify()
  end
end)

local failed = 0
for _, entry in ipairs(tests) do
  local ok, err = xpcall(entry.run, debug.traceback)
  if ok then
    print("ok - " .. entry.name)
  else
    failed = failed + 1
    io.stderr:write("FAIL - " .. entry.name .. "\n" .. tostring(err) .. "\n")
  end
end
_G.vim = host_vim
print(string.format("%d tests, %d failures", #tests, failed))
if failed > 0 then
  os.exit(1)
end
