local source = debug.getinfo(1, "S").source:sub(2)
local test_dir = source:match("^(.*[/\\])") or "./"
local root = test_dir .. ".."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. root .. "/tests/?.lua;" .. package.path
local saved_vim = _G.vim
local support, fixtures = require("support"), require("fixtures")
local test, equal = support.test, support.equal
local new_controller = require("tab_buffers.controller").new
local new_panel = require("tab_buffers.tabline.controller").new

---@return TabBuffersTabline, TabBuffersFakePanelState, TabBuffers, TabBuffersFakeState
local function fixture()
  local editor, editor_state = fixtures.editor()
  local buffers = new_controller(editor)
  fixtures.buffer(editor_state)
  buffers.setup()
  fixtures.drain(editor_state)
  local state = {
    snapshot = {
      tab = 1,
      tabs = { 1 },
      active = 1,
      visible = { [1] = true },
      entries = {
        { id = 1, name = "/a.lua", modified = false, icon = "" },
        { id = 2, name = "/b.lua", modified = false, icon = "" },
      },
      filetype = "lua",
      columns = 120,
      left = 0,
      right = 0,
      reviews = {},
    },
    queued = {},
    styles = {},
    shown = 1,
    redraws = 0,
    installs = 0,
    removed = 0,
    notices = {},
  }
  ---@cast state TabBuffersFakePanelState
  local adapter = {
    metrics = {
      measure = function(text)
        return #text
      end,
      length = function(text)
        return #text
      end,
      suffix = function(text, first)
        return text:sub(first + 1)
      end,
    },
    tab_valid = editor.tab_valid,
    buffer_valid = editor.buffer_valid,
    focus_tab = function(tab)
      editor_state.current_tab = tab
    end,
    notify = function(message)
      state.notices[#state.notices + 1] = message
    end,
    redraw = function()
      state.redraws = state.redraws + 1
    end,
    schedule = function(action)
      state.queued[#state.queued + 1] = action
    end,
    highlights = function(input)
      return require("tab_buffers.core.config").highlights(type(input) == "function" and input() or input)
    end,
    apply = function(styles, shown)
      if state.fail_apply then
        error("apply failed")
      end
      state.styles, state.shown = styles or state.styles, shown
    end,
    snapshot = function()
      return support.copy(state.snapshot)
    end,
    install = function(callbacks)
      if state.fail_install then
        error("install failed")
      end
      state.callbacks, state.installs = callbacks, state.installs + 1
      return function()
        state.removed, state.callbacks = state.removed + 1, nil
      end
    end,
  }
  ---@cast adapter TabBuffersPanelAdapter
  return new_panel(adapter, buffers), state, buffers, editor_state
end

---@param state TabBuffersFakePanelState
---@return nil
local function drain(state)
  while #state.queued > 0 do
    table.remove(state.queued, 1)()
  end
end

---@param public TabBuffersTabline
---@param text string
---@return integer
local function token(public, text)
  for id, label in public.render():gmatch("%%(%d+)@[^@]+@(.-)%%X") do
    if label:find(text, 1, true) then
      return assert(tonumber(id))
    end
  end
  error("missing target " .. text)
end

_G.vim = nil

test("setup publishes a document and teardown invalidates state", function()
  local public, state = fixture()
  equal(public.render(), "")
  public.setup({ icons = false })
  assert(public.render():find("a.lua", 1, true))
  equal(state.installs, 1)
  equal(state.shown, 2)
  equal(public.teardown(), true)
  equal(public.render(), "")
  equal(state.removed, 1)
  equal(public.teardown(), false)
end)

test("reconfiguration replaces document without duplicate handlers", function()
  local public, state = fixture()
  public.setup()
  local previous = token(public, "b.lua")
  public.setup({ padding = 3 })
  assert(token(public, "b.lua") > previous)
  equal(state.installs, 1)
end)

test("invalid configuration never installs native resources", function()
  local public, state = fixture()
  support.raises(function()
    -- Invalid external input deliberately bypasses the typed public contract.
    ---@diagnostic disable-next-line: assign-type-mismatch
    public.setup({ icons = 1 })
  end)
  equal(state.installs, 0)
  equal(public.render(), "")
end)

test("callback failure leaves a previous panel intact", function()
  local public, state = fixture()
  public.setup()
  local previous = public.render()
  support.raises(function()
    public.setup({
      highlights = function()
        error("callback failed")
      end,
    })
  end)
  equal(public.render(), previous)
  equal(state.installs, 1)
  equal(state.removed, 0)
end)

test("native failure during first setup removes new resources", function()
  local public, state = fixture()
  state.fail_apply = true
  support.raises(public.setup, "apply failed")
  equal(state.removed, 1)
  equal(public.teardown(), false)
  state.fail_apply = false
  public.setup()
  equal(state.installs, 2)
end)

test("native failure during repeat setup preserves current targets", function()
  local public, state = fixture()
  public.setup()
  local previous = public.render()
  state.fail_apply = true
  support.raises(public.setup, "apply failed")
  equal(public.render(), previous)
  equal(state.removed, 0)
end)

test("events coalesce and cancelled generations do not redraw", function()
  local public, state = fixture()
  public.setup()
  local before = state.redraws
  assert(state.callbacks).changed()
  assert(state.callbacks).changed()
  equal(#state.queued, 1)
  public.teardown()
  drain(state)
  equal(state.redraws, before)
end)

test("theme errors warn and leave styles and document intact", function()
  local public, state = fixture()
  local fail = false
  public.setup({
    highlights = function()
      if fail then
        error("theme failed")
      end
      return { Active = { fg = "#123456" } }
    end,
  })
  local previous = public.render()
  fail = true
  assert(state.callbacks).theme()
  equal(#state.notices, 1)
  equal(public.render(), previous)
  equal(state.styles.Active.fg, "#123456")
end)

test("clicks use membership API and ignore unsupported buttons", function()
  local public, state, _, editor = fixture()
  public.setup()
  local id = token(public, "b.lua")
  public.click(id, 2, "l")
  public.click(id, 1, "r")
  public.click(id, 1, "l", "c")
  equal(#state.queued, 0)
  public.click(id, 1, "l")
  drain(state)
  equal(editor.windows[101].buf, 2)
end)

test("reconfiguration cancels an already queued click", function()
  local public, state, _, editor = fixture()
  public.setup()
  public.click(token(public, "b.lua"), 1, "l")
  public.setup({ padding = 1 })
  drain(state)
  equal(editor.windows[101].buf, 1)
end)

test("middle click protects modified exclusive text", function()
  local public, state, buffers, editor = fixture()
  public.setup()
  editor.buffers[2].modified = true
  public.click(token(public, "b.lua"), 1, "m")
  drain(state)
  assert(buffers.contains(2))
  assert(editor.buffers[2].modified)
end)

test("detached or deleted targets are rejected at execution", function()
  local public, state, buffers, editor = fixture()
  public.setup()
  public.click(token(public, "b.lua"), 1, "l")
  editor.buffers[2] = nil
  buffers.refresh()
  drain(state)
  equal(editor.windows[101].buf, 1)
end)

test("identical snapshots retain click targets and skip redraw", function()
  local public, state = fixture()
  public.setup()
  local document, redraws = public.render(), state.redraws
  local id = token(public, "a.lua")
  for _ = 1, 3 do
    assert(state.callbacks).changed()
    drain(state)
  end
  equal(public.render(), document)
  equal(state.redraws, redraws)
  public.click(id, 1, "l", "")
  drain(state)
  equal(#state.notices, 0)
end)

test("display invalidation rebuilds unchanged snapshot and width cache", function()
  local public, state = fixture()
  public.setup()
  local redraws = state.redraws
  assert(assert(state.callbacks).metrics)()
  drain(state)
  equal(state.redraws, redraws + 1)
end)

_G.vim = saved_vim
support.run("tab-buffers panel controller")
