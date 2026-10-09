local source = debug.getinfo(1, "S").source:sub(2)
local test_dir = source:match("^(.*[/\\])") or "./"
local root = test_dir .. ".."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. root .. "/tests/?.lua;" .. package.path
local saved_vim = _G.vim
local support, fixtures = require("support"), require("fixtures")
local new = require("tab_buffers.controller").new
local test, equal = support.test, support.equal

---@return TabBuffers, TabBuffersAdapter, TabBuffersFakeState
local function fixture()
  local adapter, state = fixtures.editor()
  local public = new(adapter)
  public.setup()
  fixtures.drain(state)
  return public, adapter, state
end

_G.vim = nil

test("bootstrap and queries require setup and return independent snapshots", function()
  local adapter, state = fixtures.editor()
  local public = new(adapter)
  support.raises(public.buffers, "setup")
  public.setup()
  equal(public.buffers(), { 1 })
  equal(public.tabs(), { 1 })
  equal(public.owners(), { 1 })
  assert(public.contains())
  public.buffers()[1] = 100
  equal(public.buffers(), { 1 })
  public.setup()
  equal(state.installs, 1)
end)

test("failed installation can be retried without half-initialized state", function()
  local adapter, state = fixtures.editor()
  local public = new(adapter)
  state.fail_install = true
  support.raises(public.setup, "install failed")
  equal(public.teardown(), false)
  state.fail_install = false
  public.setup()
  equal(public.buffers(), { 1 })
  equal(state.installs, 1)
end)

test("bootstrap failure releases subscriptions and pending work before retry", function()
  local adapter, state = fixtures.editor()
  local public = new(adapter)
  state.fail_buffers = true
  support.raises(public.setup, "bootstrap failed")
  equal(state.callbacks, nil)
  fixtures.drain(state)
  support.raises(public.buffers, "setup")
  state.fail_buffers = false
  public.setup()
  equal(public.buffers(), { 1 })
end)

test("instances do not share model, queues or lifecycle", function()
  local first, _, one = fixture()
  local second, _, two = fixture()
  local buf = fixtures.buffer(one)
  first.add(buf)
  equal(second.buffers(), { 1 })
  first.teardown()
  fixtures.drain(one)
  equal(second.contains(), true)
  equal(two.installs, 1)
end)

test("changed notifications coalesce and no-op operations publish nothing", function()
  local public, _, state = fixture()
  state.published = {}
  local buf = fixtures.buffer(state)
  public.add(buf)
  public.move_to(1, { buf = buf })
  public.add(buf)
  fixtures.drain(state)
  equal(state.published, { { 1 } })
  state.published = {}
  public.move_to(1, { buf = buf })
  public.refresh()
  fixtures.drain(state)
  equal(state.published, {})
end)

test("teardown invalidates queued work and later setup bootstraps again", function()
  local public, _, state = fixture()
  public.add(fixtures.buffer(state))
  public.teardown()
  state.published = {}
  fixtures.drain(state)
  equal(state.published, {})
  public.setup()
  equal(#public.buffers(), 2)
  equal(public.teardown(), true)
  equal(public.teardown(), false)
end)

test("ordering and navigation use selected tab order", function()
  local public, _, state = fixture()
  local a, b = fixtures.buffer(state, "/z.lua"), fixtures.buffer(state, "/a.lua")
  public.add(a)
  public.add(b)
  public.move(-1, { buf = b })
  equal(public.buffers(), { 1, b, a })
  public.reorder({ a, 1, b })
  equal(public.next(), b)
  equal(public.previous(), 1)
  public.sort("name")
  equal(public.buffers(), { b, 1, a })
  public.sort("path")
  public.sort("id")
  equal(public.buffers(), { 1, a, b })
end)

test("special implicit context does not mutate or navigate", function()
  local public, _, state = fixture()
  state.windows[101].floating = true
  equal(public.add(fixtures.buffer(state)), true)
  equal(public.next(), nil)
  equal(public.move(1), false)
  equal(public.close().closed, {})
end)

test("excluded tab removes memberships without deleting buffers", function()
  local public, _, state = fixture()
  state.excluded[1] = true
  public.refresh()
  equal(public.buffers(), {})
  assert(state.buffers[1].valid)
  equal(public.close_tab().closed, {})
end)

test("stale explicit handles return errors without operations", function()
  local public = fixture()
  local changed, err = public.add(99)
  equal(changed, false)
  assert(err and err:find("invalid buffer"))
  local opened, message = public.open(1, { tab = 99 })
  equal(opened, nil)
  assert(message and message:find("invalid tab"))
end)

test("reentrant sort mutation leaves model unchanged", function()
  local public, _, state = fixture()
  public.add(fixtures.buffer(state))
  local previous = public.buffers()
  support.raises(function()
    public.sort(function()
      public.add(1)
      return false
    end)
  end, "already in progress")
  equal(public.buffers(), previous)
  public.move_to(1, { buf = previous[2] })
end)

for _, method in ipairs({ "close", "close_all", "close_others", "close_left", "close_right", "close_many" }) do
  test(method .. " selects targets in model order and keeps final tab", function()
    local public, _, state = fixture()
    local a, b = fixtures.buffer(state), fixtures.buffer(state)
    public.add(a)
    public.add(b)
    local report
    if method == "close_many" then
      report = public.close_many({ b, 1, b, 999 })
      equal(report.closed, { 1, b })
    else
      local invoke = public[method]
      report = invoke({ buf = a })
      local expected = {
        close = { a },
        close_all = { 1, a, b },
        close_others = { 1, b },
        close_left = { 1 },
        close_right = { b },
      }
      equal(report.closed, expected[method])
    end
    equal(report.failed, {})
    equal(report.tab_closed, false)
    equal(state.tabs, { 1 })
  end)
end

test("partial bulk close reports modified failure and closes other targets", function()
  local public, _, state = fixture()
  local dirty = fixtures.buffer(state, nil, true)
  public.add(dirty)
  local report = public.close_all()
  equal(report.closed, { 1 })
  equal(report.failed, { { buf = dirty, message = "unsaved changes" } })
  equal(public.buffers(), { dirty })
  equal(#state.notices, 1)
end)

test("force discards only exclusive modified text", function()
  local public, _, state = fixture()
  state.buffers[1].modified = true
  equal(public.close({ force = true }).closed, { 1 })
  equal(state.buffers[1], nil)
end)

test("sharing has independent order and close retains shared modified text", function()
  local public, adapter, state = fixture()
  adapter.new_tab()
  public.refresh()
  public.add(1)
  state.buffers[1].modified = true
  equal(public.owners(1), { 1, 2 })
  local report = public.close({ buf = 1 })
  equal(report.closed, { 1 })
  assert(state.buffers[1].modified)
  equal(public.owners(1), { 1 })
end)

test("deletion failure keeps membership and original window", function()
  local public, _, state = fixture()
  state.fail_delete = true
  local report = public.close()
  equal(#report.failed, 1)
  equal(public.buffers(), { 1 })
  equal(state.windows[101].buf, 1)
end)

test("window replacement failure makes no membership change", function()
  local public, _, state = fixture()
  state.fail_replace = true
  local report = public.close()
  equal(report.failed, { { buf = 1, message = "replace failed" } })
  equal(public.buffers(), { 1 })
end)

test("navigation failure retains selected buffer", function()
  local public, _, state = fixture()
  public.add(fixtures.buffer(state))
  state.fail_switch = true
  local selected, err = public.next()
  equal(selected, nil)
  equal(err, "switch failed")
  equal(state.windows[101].buf, 1)
end)

test("native close captures old ownership and recovers unsaved orphan", function()
  local public, adapter, state = fixture()
  state.buffers[1].modified = true
  adapter.new_tab()
  public.refresh()
  adapter.close_tab(1, false)
  public.refresh()
  equal(public.owners(1), { 2 })
  assert(state.buffers[1].modified)
end)

test("exit suppresses deferred cleanup and publication", function()
  local public, _, state = fixture()
  state.published = {}
  public.add(fixtures.buffer(state))
  assert(state.callbacks).exiting()
  fixtures.drain(state)
  equal(state.published, {})
end)

test("transfer rechecks destination changed during replacement", function()
  local public, adapter, state = fixture()
  adapter.new_tab()
  public.refresh()
  state.before_commit = function()
    state.excluded[2] = true
  end
  local changed, err = public.transfer(2, { tab = 1, buf = 1 })
  equal(changed, false)
  assert(err and err:find("unmanaged"))
  equal(public.owners(1), { 1 })
  equal(state.windows[101].buf, 1)
end)

test("transfer commits membership and preserves shared destination order", function()
  local public, adapter, state = fixture()
  local other = fixtures.buffer(state)
  public.add(other)
  adapter.new_tab()
  public.refresh()
  public.add(1)
  public.add(other)
  local previous = public.buffers(2)
  equal(public.transfer(2, { tab = 1, buf = 1, index = 100 }), true)
  equal(public.buffers(2), previous)
  equal(public.owners(1), { 2 })
end)

test("post-operation observation failure reports already committed ordering", function()
  local public, _, state = fixture()
  local buf = fixtures.buffer(state)
  public.add(buf)
  local changed, err = public.sort(function(a, b)
    state.fail_tabs = true
    return a > b
  end)
  equal(changed, true)
  assert(err and err:find("observation failed"))
  equal(public.buffers(), { buf, 1 })
  state.fail_tabs = false
  public.refresh()
end)

test("post-close observation failure preserves the committed close report", function()
  local public, _, state = fixture()
  local remaining = fixtures.buffer(state)
  public.add(remaining)
  state.before_commit = function()
    state.fail_tabs = true
  end
  local report = public.close({ buf = 1 })
  equal(report.closed, { 1 })
  equal(report.failed, {})
  assert(report.error and report.error:find("observation failed"))
  equal(state.buffers[1], nil)
  equal(public.buffers(), { remaining })
  state.fail_tabs = false
  public.refresh()
end)

test("last tab closure is refused without deleting text", function()
  local public, _, state = fixture()
  equal(public.close_tab().error, "cannot close the last tab")
  assert(state.buffers[1].valid)
end)

test("failed orphan recovery survives repeated retries and restores every candidate", function()
  local public, adapter, state = fixture()
  local second = fixtures.buffer(state, "/unsaved.lua", true)
  public.add(second)
  state.buffers[1].modified = true
  adapter.new_tab()
  state.excluded[2] = true
  public.refresh()
  local create = adapter.new_tab
  adapter.new_tab = function()
    error("recovery creation failed")
  end
  adapter.close_tab(1, false)
  for _ = 1, 2 do
    support.raises(public.refresh, "recovery creation failed")
    assert(adapter.buffer_valid(1) and adapter.buffer_valid(second))
  end
  adapter.new_tab = create
  public.refresh()
  equal(public.owners(1), { 3 })
  equal(public.owners(second), { 3 })
  equal(#state.notices, 1)
  public.refresh()
  equal(#state.notices, 1)
end)

test("committed close survives an error from replacement cleanup", function()
  local public, adapter, state = fixture()
  public.add(fixtures.buffer(state))
  local replace = adapter.replace
  adapter.replace = function(...)
    local ok, err = replace(...)
    if ok then
      return false, "replacement cleanup failed"
    end
    return ok, err
  end
  local report = public.close()
  equal(report.closed, { 1 })
  equal(report.failed, {})
  assert(report.error and report.error:find("cleanup failed"))
  equal(public.contains(1), false)
end)

test("committed transfer returns changed with a cleanup error", function()
  local public, adapter, state = fixture()
  public.add(fixtures.buffer(state))
  adapter.new_tab()
  public.refresh()
  local replace = adapter.replace
  adapter.replace = function(...)
    local ok, err = replace(...)
    return false, ok and "replacement cleanup failed" or err
  end
  local changed, err = public.transfer(2, { tab = 1, buf = 1 })
  equal(changed, true)
  assert(err and err:find("cleanup failed"))
  equal(public.owners(1), { 2 })
end)

test("setup disables hidden bootstrap without changing visible enrollment", function()
  local adapter, state = fixtures.editor()
  local hidden = fixtures.buffer(state)
  local public = new(adapter)
  local opts = { bootstrap_hidden_buffers = false }
  public.setup(opts)
  opts.bootstrap_hidden_buffers = true
  equal(public.buffers(), { 1 })
  public.setup()
  equal(public.contains(hidden), false)
  public.add(hidden)
  assert(public.contains(hidden))
end)

test("setup navigation default supports explicit operation overrides", function()
  local adapter, state = fixtures.editor()
  local second = fixtures.buffer(state)
  local public = new(adapter)
  public.setup({ wrap = false })
  equal(public.previous(), nil)
  equal(public.previous({ wrap = true }), second)
  equal(public.next(), nil)
  public.setup({ wrap = true })
  equal(public.next(), 1)
end)

test("empty-tab policy retains tabs after closure and transfer but permits explicit close_tab", function()
  local adapter, state = fixtures.editor()
  local public = new(adapter)
  public.setup({ close_empty_tab = false })
  adapter.new_tab()
  public.refresh()
  local report = public.close({ tab = 1, buf = 1 })
  equal(report.closed, { 1 })
  equal(report.tab_closed, false)
  assert(adapter.tab_valid(1))
  local buf = fixtures.buffer(state)
  public.add(buf, { tab = 1 })
  assert(public.transfer(2, { tab = 1, buf = buf }))
  assert(adapter.tab_valid(1))
  equal(public.close_tab({ tab = 1 }).tab_closed, true)
end)

test("left replacement prefers the left neighbor and falls back to the right", function()
  local adapter, state = fixtures.editor()
  local second, third = fixtures.buffer(state), fixtures.buffer(state)
  local public = new(adapter)
  public.setup({ replacement = "left" })
  public.open(second)
  equal(public.close().closed, { second })
  equal(state.windows[101].buf, 1)
  public.close()
  equal(state.windows[101].buf, third)
end)

test("last-used replacement follows focus independently of tab order", function()
  local adapter, state = fixtures.editor()
  local second, third, fourth = fixtures.buffer(state), fixtures.buffer(state), fixtures.buffer(state)
  local public = new(adapter)
  public.setup({ replacement = "last_used" })
  public.open(fourth)
  public.open(second)
  public.close()
  equal(state.windows[101].buf, fourth)
  public.close_many({ fourth, third })
  equal(state.windows[101].buf, 1)
end)

test("buffer filters release membership without deleting modified text and apply to explicit add", function()
  local public, adapter, state = fixture()
  state.buffers[1].modified = true
  public.setup({
    buffer_filter = function(buf)
      return buf ~= 1
    end,
  })
  equal(public.contains(1), false)
  assert(adapter.buffer_valid(1) and state.buffers[1].modified)
  equal(public.add(1), false)
  public.setup({
    buffer_filter = function()
      return true
    end,
  })
  assert(public.contains(1))
  state.buffers[1].buftype = "terminal"
  public.refresh()
  equal(public.add(1), false)
end)

test("tab filters restrict explicit actions without permitting excluded reviews", function()
  local public, adapter, state = fixture()
  adapter.new_tab()
  public.setup({
    tab_filter = function(tab)
      return tab ~= 1
    end,
  })
  equal(public.buffers(1), {})
  equal(public.open(1, { tab = 1 }), nil)
  equal(public.close_tab({ tab = 1 }).tab_closed, false)
  assert(adapter.buffer_valid(1))
  public.setup({
    tab_filter = function()
      return true
    end,
  })
  assert(public.contains(1, 1))
  state.excluded[1] = true
  public.refresh()
  equal(public.buffers(1), {})
  equal(public.add(1, { tab = 1 }), false)
end)

test("filtered buffers from an external tab closure remain alive", function()
  local public, adapter, state = fixture()
  adapter.new_tab()
  public.refresh()
  public.setup({
    buffer_filter = function(buf)
      return buf ~= 1
    end,
  })
  adapter.close_tab(1, false)
  public.refresh()
  assert(adapter.buffer_valid(1))
  equal(public.owners(1), {})
end)

test("invalid reconfiguration retains membership and previous navigation settings", function()
  local public, _, state = fixture()
  public.add(fixtures.buffer(state))
  support.raises(function()
    ---@diagnostic disable-next-line: assign-type-mismatch
    public.setup({ replacement = "invalid" })
  end, "replacement")
  equal(public.previous(), 2)
  equal(public.buffers(), { 1, 2 })
end)

test("teardown discards navigation configuration and focus history", function()
  local public, _, state = fixture()
  public.add(fixtures.buffer(state))
  public.setup({ wrap = false })
  public.teardown()
  public.setup()
  equal(public.previous(), 2)
end)

test("filter errors preserve the previous setup and allow later operations", function()
  local public, _, state = fixture()
  public.add(fixtures.buffer(state))
  support.raises(function()
    public.setup({
      buffer_filter = function()
        error("filter failed")
      end,
    })
  end, "filter failed")
  equal(public.buffers(), { 1, 2 })
  equal(public.previous(), 2)
end)

test("failed first setup rejects nonboolean filters and can retry with defaults", function()
  local adapter = fixtures.editor()
  local public = new(adapter)
  support.raises(function()
    public.setup({
      buffer_filter = function()
        ---@diagnostic disable-next-line: return-type-mismatch
        return "yes"
      end,
    })
  end, "boolean")
  public.setup()
  equal(public.buffers(), { 1 })
end)

test("failed filter reconfiguration restores hidden membership and order", function()
  local public, _, state = fixture()
  local second, third = fixtures.buffer(state), fixtures.buffer(state)
  public.add(second)
  public.add(third)
  public.reorder({ third, second, 1 })
  local visits = 0
  support.raises(function()
    public.setup({
      buffer_filter = function(buf)
        visits = visits + 1
        if visits > 3 then
          error("late filter failed")
        end
        return buf ~= third
      end,
    })
  end, "late filter failed")
  equal(public.buffers(), { third, second, 1 })
end)

test("observations read each owned buffer once and publication does not rescan", function()
  local public, adapter, state = fixture()
  for _ = 1, 100 do
    public.add(fixtures.buffer(state))
  end
  fixtures.drain(state)
  local reads, scans = 0, 0
  local read, windows = adapter.buffer, adapter.tab_windows
  adapter.buffer = function(buf)
    reads = reads + 1
    return read(buf)
  end
  adapter.tab_windows = function(tab)
    scans = scans + 1
    return windows(tab)
  end
  public.refresh()
  equal(reads, 101)
  equal(scans, 1)
  fixtures.drain(state)
  equal(reads, 101)
  equal(scans, 1)
  reads, scans = 0, 0
  public.move(1)
  fixtures.drain(state)
  assert(reads <= 103)
  equal(scans, 2)
end)

test("ordinary edits and unchanged metadata avoid global scans", function()
  local public, adapter, state = fixture()
  for _ = 1, 100 do
    public.add(fixtures.buffer(state))
  end
  fixtures.drain(state)
  local reads, scans = 0, 0
  local read, windows = adapter.buffer, adapter.tab_windows
  adapter.buffer = function(buf)
    reads = reads + 1
    return read(buf)
  end
  adapter.tab_windows = function(tab)
    scans = scans + 1
    return windows(tab)
  end
  for _ = 1, 3 do
    assert(assert(state.callbacks).text)(1)
    assert(assert(state.callbacks).buffer)(1)
    fixtures.drain(state)
  end
  equal(scans, 0)
  equal(reads, 6)
  equal(#public.buffers(), 101)
end)

test("targeted events enroll visible drafts and remove hidden deleted memberships", function()
  local public, _, state = fixture()
  local draft = fixtures.buffer(state, "", false)
  state.windows[101].buf = draft
  assert(assert(state.callbacks).text)(draft)
  fixtures.drain(state)
  equal(public.contains(draft), false)
  state.buffers[draft].has_text = true
  assert(assert(state.callbacks).text)(draft)
  fixtures.drain(state)
  assert(public.contains(draft))
  assert(assert(state.callbacks).buffer)(1)
  state.buffers[1] = nil
  fixtures.drain(state)
  equal(public.owners(1), {})
end)

test("text events with dynamic filters retain full reconciliation", function()
  local public, _, state = fixture()
  local accepted = true
  public.setup({
    buffer_filter = function()
      return accepted
    end,
  })
  fixtures.drain(state)
  accepted = false
  assert(assert(state.callbacks).text)(1)
  fixtures.drain(state)
  equal(public.buffers(), {})
end)

test("failed targeted observation is retried by the next full update", function()
  local public, adapter, state = fixture()
  assert(assert(state.callbacks).buffer)(1)
  local read = adapter.buffer
  adapter.buffer = function()
    error("target observation failed")
  end
  support.raises(function()
    fixtures.drain(state)
  end, "target observation failed")
  adapter.buffer = read
  state.buffers[1].listed = false
  assert(state.callbacks).changed()
  fixtures.drain(state)
  equal(public.owners(1), {})
end)

_G.vim = saved_vim
support.run("tab-buffers controller")
