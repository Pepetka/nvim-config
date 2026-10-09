local support = require("support")
local M = {}

---@return TabBuffersAdapter, TabBuffersFakeState
function M.editor()
  local state = {
    tabs = { 1 },
    windows = { [101] = { tab = 1, buf = 1 } },
    buffers = {
      [1] = {
        valid = true,
        listed = true,
        buftype = "",
        name = "/main.lua",
        modified = false,
        loaded = true,
        has_text = true,
      },
    },
    current_tab = 1,
    current_win = 101,
    excluded = {},
    queued = {},
    published = {},
    notices = {},
    installs = 0,
    restores = 0,
    next_buffer = 1,
  }
  ---@cast state TabBuffersFakeState
  local adapter = {}
  ---@cast adapter TabBuffersAdapter

  function adapter.current_tab()
    return state.current_tab
  end
  function adapter.current_window()
    return state.current_win
  end
  function adapter.current_buffer()
    return state.windows[state.current_win].buf
  end
  function adapter.tab_valid(tab)
    return require("tab_buffers.core.lists").index_of(state.tabs, tab) ~= nil
  end
  function adapter.buffer_valid(buf)
    return state.buffers[buf] ~= nil
  end
  function adapter.window_valid(win)
    return state.windows[win] ~= nil
  end
  function adapter.tabs()
    if state.fail_tabs then
      error("observation failed")
    end
    return support.copy(state.tabs)
  end
  function adapter.buffers()
    if state.fail_buffers then
      error("bootstrap failed")
    end
    local result = {}
    for buf in pairs(state.buffers) do
      result[#result + 1] = buf
    end
    table.sort(result)
    return result
  end
  function adapter.tab_windows(tab)
    local result = {}
    for win, facts in pairs(state.windows) do
      if facts.tab == tab then
        result[#result + 1] = win
      end
    end
    table.sort(result)
    return result
  end
  function adapter.tab_window(tab)
    return assert(adapter.tab_windows(tab)[1])
  end
  function adapter.window_buffer(win)
    return state.windows[win].buf
  end
  function adapter.window_tab(win)
    return state.windows[win].tab
  end
  function adapter.buffer_name(buf)
    return state.buffers[buf].name
  end
  function adapter.tab(tab)
    return { valid = adapter.tab_valid(tab), excluded = state.excluded[tab] == true }
  end
  function adapter.buffer(buf)
    return support.copy(state.buffers[buf] or {
      valid = false,
      listed = false,
      buftype = "",
      name = "",
      modified = false,
      loaded = false,
      has_text = false,
    })
  end
  function adapter.window(win)
    local facts = state.windows[win]
    return {
      valid = facts ~= nil,
      floating = facts and facts.floating == true or false,
      external = false,
      preview = facts and facts.preview == true or false,
      managed = facts ~= nil and state.excluded[facts.tab] ~= true,
    }
  end
  function adapter.displaying(buf)
    local result = {}
    for win, facts in pairs(state.windows) do
      if facts.buf == buf then
        result[#result + 1] = win
      end
    end
    table.sort(result)
    return result
  end
  function adapter.delete_buffer(buf)
    if state.fail_delete then
      error("delete failed")
    end
    state.buffers[buf] = nil
  end
  function adapter.focus_window(win)
    state.current_win, state.current_tab = win, state.windows[win].tab
  end
  function adapter.schedule(action)
    state.queued[#state.queued + 1] = action
  end
  function adapter.publish(tabs)
    state.published[#state.published + 1] = support.copy(tabs)
  end
  function adapter.notify(message)
    state.notices[#state.notices + 1] = message
  end
  function adapter.exiting()
    return state.exiting == true
  end
  function adapter.install(callbacks)
    if state.fail_install then
      error("install failed")
    end
    state.installs, state.callbacks = state.installs + 1, callbacks
    return function()
      state.callbacks = nil
    end
  end
  function adapter.protected(_, action)
    local ok, value, err = pcall(action)
    if not ok then
      return false, tostring(value)
    end
    return true, value, err
  end
  function adapter.open(ctx, buf)
    state.windows[ctx.win].buf = buf
    adapter.focus_window(ctx.win)
    return buf
  end
  function adapter.switch(ctx, buf)
    if state.fail_switch then
      return nil, "switch failed"
    end
    state.windows[ctx.win].buf = buf
    return buf
  end
  function adapter.replace(tab, buf, replacement, scan, commit)
    if state.fail_replace then
      return false, "replace failed"
    end
    local targets = {}
    for _, win in ipairs(adapter.tab_windows(tab)) do
      if adapter.window_buffer(win) == buf then
        targets[#targets + 1] = win
      end
    end
    if not replacement and #targets > 0 then
      replacement = M.buffer(state, "", false)
    end
    for _, win in ipairs(targets) do
      state.windows[win].buf = assert(replacement)
    end
    local ok, err = pcall(function()
      scan()
      if state.before_commit then
        state.before_commit()
      end
      commit()
    end)
    if not ok then
      for _, win in ipairs(targets) do
        if state.windows[win] and adapter.buffer_valid(buf) then
          state.windows[win].buf = buf
        end
      end
      return false, tostring(err)
    end
    return true
  end
  function adapter.guard_closing() end
  function adapter.restore_closing()
    state.restores = state.restores + 1
  end
  function adapter.close_tab(tab)
    if state.callbacks then
      local saved = state.current_tab
      state.current_tab = tab
      state.callbacks.closing()
      state.current_tab = saved
    end
    for index, value in ipairs(state.tabs) do
      if value == tab then
        table.remove(state.tabs, index)
        break
      end
    end
    for win, facts in pairs(state.windows) do
      if facts.tab == tab then
        state.windows[win] = nil
      end
    end
    state.current_tab = state.tabs[1]
    state.current_win = assert(adapter.tab_windows(state.current_tab)[1])
  end
  function adapter.new_tab()
    local tab = (state.tabs[#state.tabs] or 0) + 1
    state.tabs[#state.tabs + 1] = tab
    state.current_tab, state.current_win = tab, tab + 100
    state.windows[state.current_win] = { tab = tab, buf = M.buffer(state, "", false) }
  end
  function adapter.new_working_window(tab)
    local win = 1000 + state.next_buffer
    state.windows[win] = { tab = tab or state.current_tab, buf = M.buffer(state, "", false) }
  end
  return adapter, state
end

---@param state TabBuffersFakeState
---@param name? string
---@param modified? boolean
---@return integer
function M.buffer(state, name, modified)
  state.next_buffer = state.next_buffer + 1
  local buf = state.next_buffer
  state.buffers[buf] = {
    valid = true,
    listed = true,
    buftype = "",
    name = name or ("/file" .. buf .. ".lua"),
    modified = modified == true,
    loaded = true,
    has_text = name ~= "",
  }
  return buf
end

---@param state TabBuffersFakeState
---@return nil
function M.drain(state)
  local limit = 0
  while #state.queued > 0 do
    limit = limit + 1
    assert(limit < 100, "scheduled work did not settle")
    table.remove(state.queued, 1)()
  end
end

return M
