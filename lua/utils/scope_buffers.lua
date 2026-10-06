local M = {}

local function close_buffer(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    vim.notify("Buffer was not closed: " .. tostring(err), vim.log.levels.WARN)
  end
end

local function buffers_in_other_tabs(core, current_tab)
  local buffers = {}
  for tab, tab_bufs in pairs(core.cache) do
    if tab ~= current_tab then
      for _, buf in ipairs(tab_bufs) do
        buffers[buf] = true
      end
    end
  end
  return buffers
end

local function visible_buffers()
  local buffers = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    buffers[vim.api.nvim_win_get_buf(win)] = true
  end
  return buffers
end

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
---Terminal and modified buffers are preserved. Modified buffers are relisted
---because scope.nvim unlists them when leaving the closed tab.
---@param core table scope.core module
function M.close_buffers_in_closed_tab(core)
  local closed_tab = core.last_tab
  local bufs = closed_tab and core.cache[closed_tab]
  if not bufs then
    return
  end

  -- Collect buffers used in other tabs' scopes.
  local used_elsewhere = buffers_in_other_tabs(core, closed_tab)

  -- Collect buffers currently visible in any window (all tabs).
  for buf in pairs(visible_buffers()) do
    used_elsewhere[buf] = true
  end

  for _, buf in ipairs(bufs) do
    if vim.api.nvim_buf_is_valid(buf) and not used_elsewhere[buf] then
      if vim.bo[buf].modified then
        vim.bo[buf].buflisted = true
      elseif vim.bo[buf].buftype ~= "terminal" then
        close_buffer(vim.api.nvim_buf_delete, buf, { force = false })
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
  local visible = visible_buffers()

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
    close_buffer(vim.api.nvim_buf_delete, current, { force = false })
  else
    close_buffer(core.close_buffer, { force = false })
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
  local used_elsewhere = buffers_in_other_tabs(core, current_tab)

  for _, buf in ipairs(to_close) do
    if vim.api.nvim_buf_is_valid(buf) then
      if used_elsewhere[buf] then
        vim.api.nvim_set_option_value("buflisted", false, { buf = buf })
      else
        close_buffer(vim.api.nvim_buf_delete, buf, { force = false })
      end
    end
  end
  core.revalidate()
end

return M
