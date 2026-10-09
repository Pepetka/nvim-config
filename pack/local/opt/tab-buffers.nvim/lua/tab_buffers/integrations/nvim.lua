local api = vim.api
local lifecycle = require("tab_buffers.integrations.lifecycle")
local M = {}

---@return TabBuffersAdapter
function M.new()
  local windows = require("tab_buffers.integrations.windows").new()
  local adapter = {
    current_tab = api.nvim_get_current_tabpage,
    current_buffer = api.nvim_get_current_buf,
    current_window = api.nvim_get_current_win,
    tab_valid = api.nvim_tabpage_is_valid,
    buffer_valid = api.nvim_buf_is_valid,
    window_valid = api.nvim_win_is_valid,
    tabs = api.nvim_list_tabpages,
    buffers = api.nvim_list_bufs,
    tab_windows = api.nvim_tabpage_list_wins,
    window_buffer = api.nvim_win_get_buf,
    window_tab = api.nvim_win_get_tabpage,
    tab_window = api.nvim_tabpage_get_win,
    buffer_name = api.nvim_buf_get_name,
    schedule = vim.schedule,
    protected = windows.protected,
    open = windows.open,
    switch = windows.switch,
    replace = windows.replace,
    guard_closing = windows.guard_closing,
    restore_closing = windows.restore_closing,
    install = lifecycle.install,
  }

  -- Resolve mutable API functions at call time so third-party hooks and failures are observed.
  ---@param buf integer
  ---@param opts { force: boolean }
  ---@return nil
  function adapter.delete_buffer(buf, opts)
    api.nvim_buf_delete(buf, opts)
  end

  ---@param win integer
  ---@return nil
  function adapter.focus_window(win)
    api.nvim_set_current_win(win)
  end

  ---@param tab integer
  ---@return TabBuffersTabFacts
  function adapter.tab(tab)
    return {
      valid = api.nvim_tabpage_is_valid(tab),
      excluded = api.nvim_tabpage_is_valid(tab) and vim.t[tab].tab_buffers_excluded == true,
    }
  end

  ---@param buf integer
  ---@return TabBuffersBufferFacts
  function adapter.buffer(buf)
    if not api.nvim_buf_is_valid(buf) then
      return {
        valid = false,
        listed = false,
        buftype = "",
        name = "",
        modified = false,
        loaded = false,
        has_text = false,
      }
    end
    local name, loaded = api.nvim_buf_get_name(buf), api.nvim_buf_is_loaded(buf)
    local has_text = false
    if loaded and name == "" and vim.bo[buf].buftype == "" then
      has_text = api.nvim_buf_line_count(buf) > 1 or api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= ""
    end
    return {
      valid = true,
      listed = vim.bo[buf].buflisted,
      buftype = vim.bo[buf].buftype,
      name = name,
      modified = vim.bo[buf].modified,
      loaded = loaded,
      has_text = has_text,
    }
  end

  ---@param win integer
  ---@return TabBuffersWindowFacts
  function adapter.window(win)
    if not api.nvim_win_is_valid(win) then
      return { valid = false, floating = false, external = false, preview = false, managed = false }
    end
    local cfg = api.nvim_win_get_config(win)
    return {
      valid = true,
      floating = cfg.relative ~= "",
      external = cfg.external == true,
      preview = vim.wo[win].previewwindow,
      managed = vim.t[api.nvim_win_get_tabpage(win)].tab_buffers_excluded ~= true,
    }
  end

  ---@param buf integer
  ---@return integer[]
  function adapter.displaying(buf)
    local result = {}
    for _, win in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_buf(win) == buf then
        result[#result + 1] = win
      end
    end
    return result
  end

  ---@return boolean
  function adapter.exiting()
    return vim.v.exiting ~= vim.NIL
  end

  ---@param tabs integer[]
  ---@return nil
  function adapter.publish(tabs)
    api.nvim_exec_autocmds("User", { pattern = "TabBuffersChanged", modeline = false, data = { tabs = tabs } })
  end

  ---@param message string
  ---@return nil
  function adapter.notify(message)
    vim.notify(message, vim.log.levels.WARN)
  end

  ---@return nil
  function adapter.new_tab()
    vim.cmd.tabnew()
  end

  ---@param tab integer
  ---@param force boolean
  ---@return nil
  function adapter.close_tab(tab, force)
    vim.cmd({ cmd = "tabclose", args = { tostring(api.nvim_tabpage_get_number(tab)) }, bang = force })
  end

  ---@param tab? integer
  ---@return nil
  function adapter.new_working_window(tab)
    if tab then
      api.nvim_set_current_tabpage(tab)
    end
    vim.cmd("botright new")
  end

  return adapter
end

return M
