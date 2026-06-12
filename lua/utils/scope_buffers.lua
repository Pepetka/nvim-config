local M = {}

---Count buffers that are currently listed.
---Because scope.nvim unlists buffers from inactive tabs, this effectively
---counts buffers visible in the current tab.
function M.count_listed_buffers()
  local count = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then
      count = count + 1
    end
  end
  return count
end

---Close buffers that belonged to a tab being closed.
---Skips buffers that are still used in other tabs or visible in other windows.
---Terminal buffers are preserved; everything else (including modified buffers)
---is closed forcefully, trusting the user to know what they are doing.
---@param core table scope.core module
function M.close_buffers_in_closed_tab(core)
  local closed_tab = core.last_tab
  local bufs = closed_tab and core.cache[closed_tab]
  if not bufs then
    return
  end

  -- Collect buffers used in other tabs' scopes.
  local used_elsewhere = {}
  for tab, tab_bufs in pairs(core.cache) do
    if tab ~= closed_tab then
      for _, buf in ipairs(tab_bufs) do
        used_elsewhere[buf] = true
      end
    end
  end

  -- Collect buffers currently visible in any window (all tabs).
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    used_elsewhere[vim.api.nvim_win_get_buf(win)] = true
  end

  for _, buf in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(buf) and not used_elsewhere[buf] then
      -- Keep terminal buffers alive; force-close everything else.
      if vim.bo[buf].buftype ~= "terminal" then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end
end

---Delete empty [No Name] buffers when entering a real file.
---This prevents scope.nvim from caching the transient empty buffer that
---:tabnew creates before the user opens an actual file.
function M.cleanup_empty_buffers()
  local current_buf = vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(current_buf) == "" then
    return
  end

  -- Collect buffers that are currently visible in any window (all tabs).
  local visible = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    visible[vim.api.nvim_win_get_buf(win)] = true
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      buf ~= current_buf
      and vim.api.nvim_buf_is_valid(buf)
      and vim.bo[buf].buflisted
      and vim.api.nvim_buf_get_name(buf) == ""
      and vim.bo[buf].buftype == ""
      and not vim.bo[buf].modified
      and not visible[buf]
    then
      pcall(vim.api.nvim_buf_delete, buf, { force = false })
    end
  end
end

---Close the current buffer respecting tab scope. If this is the last buffer
---in the last tab, delete it and let Neovim create a fresh empty buffer
---instead of quitting.
---@param core table scope.core module
function M.smart_close_buffer(core)
  local tab_count = #vim.api.nvim_list_tabpages()
  if tab_count == 1 and M.count_listed_buffers() <= 1 then
    local current = vim.api.nvim_get_current_buf()
    pcall(vim.api.nvim_buf_delete, current, { force = false })
  else
    pcall(core.close_buffer, { force = false })
  end
end

---Close or hide every buffer in the current tab except the current one.
---Uses the same ownership logic as scope.core.close_buffer: buffers that
---also belong to another tab are hidden in the current tab only, while
---buffers owned solely by the current tab are deleted.
---@param core table scope.core module
function M.close_all_except_current(core)
  local current = vim.api.nvim_get_current_buf()
  local current_tab = vim.api.nvim_get_current_tabpage()
  local excluded_buftypes = {
    terminal = true,
    nofile = true,
    prompt = true,
    quickfix = true,
  }

  -- Refresh the current tab's buffer list before acting on it.
  core.revalidate()

  -- Collect target buffers from the current tab's scope cache.
  local to_close = {}
  for _, buf in ipairs(core.cache[current_tab] or {}) do
    if buf ~= current and vim.api.nvim_buf_is_valid(buf) then
      local buftype = vim.bo[buf].buftype
      if not excluded_buftypes[buftype] then
        table.insert(to_close, buf)
      end
    end
  end

  -- Determine which target buffers are also used in other tabs.
  local used_elsewhere = {}
  for tab, tab_bufs in pairs(core.cache) do
    if tab ~= current_tab then
      for _, buf in ipairs(tab_bufs) do
        used_elsewhere[buf] = true
      end
    end
  end

  for _, buf in ipairs(to_close) do
    if vim.api.nvim_buf_is_valid(buf) then
      if used_elsewhere[buf] then
        vim.api.nvim_set_option_value("buflisted", false, { buf = buf })
        local filtered = {}
        for _, b in ipairs(core.cache[current_tab] or {}) do
          if b ~= buf then
            table.insert(filtered, b)
          end
        end
        core.cache[current_tab] = filtered
      else
        pcall(vim.api.nvim_buf_delete, buf, { force = false })
      end
    end
  end
end

return M
