local api = vim.api
local M = {}
---@type table<integer, { value: string }>
local hidden_originals = {}

---@return TabBuffersWindows
function M.new()
  local windows = {}
  local closing_options = {}

  ---@param buf integer
  ---@return boolean
  local function basic(buf)
    return api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and vim.bo[buf].buftype == ""
  end

  ---@param win integer
  ---@return boolean
  local function working(win)
    if not api.nvim_win_is_valid(win) then
      return false
    end
    local cfg = api.nvim_win_get_config(win)
    local tab = api.nvim_win_get_tabpage(win)
    return vim.t[tab].tab_buffers_excluded ~= true
      and cfg.relative == ""
      and not cfg.external
      and not vim.wo[win].previewwindow
  end

  ---@param buf integer
  ---@return integer[]
  local function displaying(buf)
    local found = {}
    for _, win in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_buf(win) == buf then
        found[#found + 1] = win
      end
    end
    return found
  end

  ---Temporarily prevent hiding from unloading/wiping buffers or losing modifications.
  ---Restore options even when a third-party autocmd fails or deletes a buffer.
  ---@param buffers integer[]
  ---@param fn TabBuffersTransaction
  ---@return boolean, boolean|string|nil, string?
  function windows.protected(buffers, fn)
    local saved, ancestors = {}, {}
    local ok, value, err = pcall(function()
      for _, buf in ipairs(buffers) do
        if api.nvim_buf_is_valid(buf) and saved[buf] == nil then
          saved[buf] = vim.bo[buf].bufhidden
          ancestors[buf] = hidden_originals[buf]
          hidden_originals[buf] = hidden_originals[buf] or { value = saved[buf] }
          vim.bo[buf].bufhidden = "hide"
        end
      end
      return fn()
    end)
    for buf, original in pairs(saved) do
      hidden_originals[buf] = ancestors[buf]
      if api.nvim_buf_is_valid(buf) then
        local restored, message = pcall(function()
          vim.bo[buf].bufhidden = original
        end)
        if not restored then
          closing_options[buf] = closing_options[buf] or (ancestors[buf] and ancestors[buf].value or original)
          if ok then
            ok, value = false, message
          end
        elseif closing_options[buf] == original then
          closing_options[buf] = nil
        end
      end
    end
    if not ok then
      return false, tostring(value)
    end
    return true, value, err
  end

  ---@param ctx TabBuffersContext
  ---@param buf integer
  ---@param opts TabBuffersOptions
  ---@return integer?, string?
  function windows.open(ctx, buf, opts)
    ---@type integer?
    local win = ctx.win
    ---@param candidate integer
    ---@return boolean
    local function suitable(candidate)
      return working(candidate) and basic(api.nvim_win_get_buf(candidate))
    end
    if opts.win and not suitable(assert(win)) then
      return nil, "target window is not a working window"
    end
    if not win or not suitable(win) then
      win = nil
      for _, candidate in ipairs(api.nvim_tabpage_list_wins(ctx.tab)) do
        if suitable(candidate) then
          win = candidate
          break
        end
      end
    end
    local reference = win
    if not reference then
      for _, candidate in ipairs(api.nvim_tabpage_list_wins(ctx.tab)) do
        if working(candidate) then
          reference = candidate
          break
        end
      end
    end
    if not reference then
      return nil, "tab has no window suitable for a split"
    end
    local focus = api.nvim_get_current_win()
    local original = win and api.nvim_win_get_buf(win)
    local created
    local ok, message = windows.protected({ buf, original or api.nvim_win_get_buf(reference) }, function()
      api.nvim_set_current_tabpage(ctx.tab)
      if opts.split or not win then
        created = api.nvim_open_win(buf, true, {
          win = reference,
          split = opts.split == "horizontal" and "below" or "right",
        })
        vim.wo[created].previewwindow = false
      else
        api.nvim_win_set_buf(win, buf)
        api.nvim_set_current_win(win)
      end
    end)
    if not ok then
      if created and api.nvim_win_is_valid(created) then
        pcall(api.nvim_win_close, created, true)
      elseif win and api.nvim_win_is_valid(win) and original and api.nvim_buf_is_valid(original) then
        windows.protected({ original, buf }, function()
          pcall(api.nvim_win_set_buf, win, original)
        end)
      end
      if api.nvim_win_is_valid(focus) then
        pcall(api.nvim_set_current_win, focus)
      end
      return nil, tostring(message)
    end
    if
      not (created or win)
      or not api.nvim_win_is_valid(created or assert(win))
      or api.nvim_win_get_buf(created or assert(win)) ~= buf
    then
      return nil, "target window changed during navigation"
    end
    if api.nvim_get_current_win() ~= (created or win) then
      return nil, "navigation focus changed during the operation"
    end
    return buf
  end

  ---@param ctx TabBuffersContext
  ---@param buf integer
  ---@return integer?, string?
  function windows.switch(ctx, buf)
    local original = api.nvim_win_get_buf(ctx.win)
    local ok, message = windows.protected({ original, buf }, function()
      local switched, failure = pcall(api.nvim_win_set_buf, ctx.win, buf)
      if not switched then
        if api.nvim_win_is_valid(ctx.win) and original and api.nvim_buf_is_valid(original) then
          pcall(api.nvim_win_set_buf, ctx.win, original)
        end
        error(failure, 0)
      end
    end)
    if not ok then
      return nil, tostring(message)
    end
    if not api.nvim_win_is_valid(ctx.win) or api.nvim_win_get_buf(ctx.win) ~= buf then
      return nil, "target window changed during navigation"
    end
    return buf
  end

  ---Replace only the owner's working windows. The callback commits after all
  ---window updates succeed; failures restore buffers while bufhidden is protected.
  ---@param tab integer
  ---@param buf integer
  ---@param next_buf? integer
  ---@param scan_visible TabBuffersAction
  ---@param commit TabBuffersAction
  ---@return boolean, string?
  function windows.replace(tab, buf, next_buf, scan_visible, commit)
    local targets = {}
    for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
      if working(win) and api.nvim_win_get_buf(win) == buf then
        targets[#targets + 1] = win
      end
    end
    local placeholder
    if not next_buf and #targets > 0 then
      local created, value = pcall(api.nvim_create_buf, true, false)
      if not created then
        return false, tostring(value)
      end
      next_buf, placeholder = value, value
    end
    local focus = api.nvim_get_current_win()
    local buffers = { buf }
    if next_buf then
      buffers[#buffers + 1] = next_buf
    end
    local protected_ok, completed, message = windows.protected(buffers, function()
      local ok, err = pcall(function()
        for _, win in ipairs(targets) do
          api.nvim_win_set_buf(win, assert(next_buf))
        end
        scan_visible()
        for _, win in ipairs(displaying(buf)) do
          if api.nvim_win_get_tabpage(win) == tab and working(win) then
            error("buffer was reopened during the operation")
          end
        end
        commit()
      end)
      if not ok then
        for _, win in ipairs(targets) do
          if api.nvim_win_is_valid(win) and api.nvim_buf_is_valid(buf) then
            pcall(api.nvim_win_set_buf, win, buf)
          end
        end
      end
      if api.nvim_win_is_valid(focus) and api.nvim_get_current_win() ~= focus then
        pcall(api.nvim_set_current_win, focus)
      end
      return ok, not ok and tostring(err) or nil
    end)
    if placeholder and api.nvim_buf_is_valid(placeholder) and #displaying(placeholder) == 0 then
      pcall(api.nvim_buf_delete, placeholder, { force = false })
    end
    if not protected_ok then
      return false, tostring(completed)
    end
    return completed == true, message
  end

  ---Keep original destructive options until native tab closure can be reconciled.
  ---@param buffers integer[]
  ---@return nil
  function windows.guard_closing(buffers)
    local ok, err = pcall(function()
      for _, buf in ipairs(buffers) do
        if api.nvim_buf_is_valid(buf) then
          if closing_options[buf] == nil then
            closing_options[buf] = hidden_originals[buf] and hidden_originals[buf].value or vim.bo[buf].bufhidden
          end
          vim.bo[buf].bufhidden = "hide"
        end
      end
    end)
    if not ok then
      windows.restore_closing()
      error(err, 0)
    end
  end

  ---@return nil
  function windows.restore_closing()
    local failures = {}
    for buf, original in pairs(closing_options) do
      local ok, err = pcall(function()
        if api.nvim_buf_is_valid(buf) then
          vim.bo[buf].bufhidden = original
        end
      end)
      if ok then
        closing_options[buf] = nil
      else
        failures[#failures + 1] = tostring(err)
      end
    end
    if #failures > 0 then
      error(table.concat(failures, "\n"), 0)
    end
  end

  return windows
end

return M
