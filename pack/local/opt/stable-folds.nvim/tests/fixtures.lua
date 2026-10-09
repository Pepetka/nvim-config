local controller = require("stable_folds.controller")
local t = require("support")
local M = {}

---@return StableFoldsController, StableFoldsAdapter, StableFoldsTestState
function M.new()
  ---@type StableFoldsTestState
  local state = {
    current = 10,
    contexts = {
      [10] = {
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
      },
      [20] = {
        buf = 1,
        win = 20,
        tick = 1,
        filetype = "lua",
        lang = "lua",
        buftype = "",
        line = 1,
        minlines = 5,
        nestmax = 2,
        foldlevel = 99,
      },
    },
    text = { [1] = { "first", "a", "b", "end", "", "second", "c", "end" } },
    raw = {
      [1] = {
        { start_row = 0, start_col = 0, end_row = 3, end_col = 3 },
        { start_row = 5, start_col = 0, end_row = 7, end_col = 3 },
      },
    },
    unavailable = {},
    watchers = {},
    closed = {},
    restored = {},
    marks = {},
    enabled = { [10] = true, [20] = true },
    opened = {},
    next_id = 0,
    parses = 0,
    reads = 0,
    clears = 0,
    installs = 0,
    uninstalls = 0,
    messages = {},
    recomputes = {},
  }
  ---@type StableFoldsAdapter
  local adapter = {
    ready = function()
      return true
    end,
    settled = function() end,
    current_window = function()
      return state.current
    end,
    line = function()
      return state.contexts[state.current].line
    end,
    context = function(win)
      state.context_reads = (state.context_reads or 0) + 1
      if state.fail == "context" then
        error("context failed")
      end
      return t.copy(state.contexts[win and win ~= 0 and win or state.current])
    end,
    buffer = function(buf)
      buf = buf and buf ~= 0 and buf or state.contexts[state.current].buf
      return state.text[buf] and buf or nil
    end,
    lines = function(buf)
      state.reads = state.reads + 1
      if state.fail == "lines" then
        error("lines failed")
      end
      return t.copy(state.text[buf])
    end,
    line_count = function(buf)
      return #state.text[buf]
    end,
    headers = function(buf, normalized)
      state.reads = state.reads + 1
      if state.fail == "lines" then
        error("lines failed")
      end
      return require("stable_folds.core.ranges").headers(normalized, state.text[buf])
    end,
    size = function(buf)
      state.size_reads = (state.size_reads or 0) + 1
      local bytes = 0
      for _, line in ipairs(state.text[buf]) do
        bytes = bytes + #line + 1
      end
      return { lines = #state.text[buf], bytes = bytes }
    end,
    collect = function(buf)
      state.parses = state.parses + 1
      if state.on_collect then
        state.on_collect()
      end
      if state.fail == "collect" then
        error("collect failed")
      end
      if state.unavailable[buf] then
        return nil
      end
      return t.copy(state.raw[buf])
    end,
    positions = function(buf, marks)
      state.position_reads = (state.position_reads or 0) + 1
      local result = {}
      for _, mark in ipairs(marks) do
        result[#result + 1] =
          { id = mark.id, header = mark.header, new = mark.new, line = (state.marks[buf] or {})[mark.id] }
      end
      return result
    end,
    apply_marks = function(buf, plan)
      state.marks[buf] = state.marks[buf] or {}
      for _, id in ipairs(plan.delete) do
        state.marks[buf][id] = nil
      end
      local result = {}
      for _, mark in ipairs(plan.marks) do
        local id = mark.id
        if not id then
          state.next_id = state.next_id + 1
          id = state.next_id
        end
        if not mark.unchanged then
          state.marks[buf][id] = mark.line
          state.mark_writes = (state.mark_writes or 0) + 1
        end
        if state.fail == "apply" then
          error("apply failed")
        end
        result[#result + 1] = { id = id, header = mark.header, new = mark.new }
      end
      return result
    end,
    clear = function(buf)
      state.clears = state.clears + 1
      state.marks[buf] = nil
    end,
    windows = function(buf)
      if state.fail == "windows" then
        error("windows failed")
      end
      local result = {}
      for win, context in pairs(state.contexts) do
        if context.buf == buf and state.enabled[win] then
          result[#result + 1] = win
        end
      end
      table.sort(result)
      return result
    end,
    buffers = function()
      -- This fixture starts before any native window has been attached.
      return {}
    end,
    attach = function(win)
      win = win and win ~= 0 and win or state.current
      if state.contexts[win] then
        state.enabled[win] = true
        return win
      end
    end,
    recompute = function(win)
      state.recomputes[win] = (state.recomputes[win] or 0) + 1
      if state.fail == "recompute" and (not state.fail_win or state.fail_win == win) then
        error("recompute failed")
      end
      if state.on_recompute then
        state.on_recompute()
      end
    end,
    open = function(win, lines)
      state.opened[win] = t.copy(lines)
    end,
    watch = function(buf, callback)
      state.watchers[buf] = callback
      return function()
        if state.watchers[buf] == callback then
          state.watchers[buf] = nil
        end
      end
    end,
    closed = function(win)
      return t.copy(state.closed[win] or {})
    end,
    restore = function(win, states)
      state.restored[win] = t.copy(states)
    end,
    install = function(callbacks)
      state.installs = state.installs + 1
      state.callbacks = callbacks
      if state.fail == "install" then
        error("install failed")
      end
    end,
    uninstall = function()
      state.uninstalls = state.uninstalls + 1
      state.callbacks = nil
      state.watchers = {}
    end,
    notify = function(message)
      state.messages[#state.messages + 1] = message
    end,
  }
  return controller.new(adapter), adapter, state
end

---@param state StableFoldsTestState
---@param tick integer
---@return nil
function M.tick(state, tick)
  for _, context in pairs(state.contexts) do
    context.tick = tick
  end
end

return M
