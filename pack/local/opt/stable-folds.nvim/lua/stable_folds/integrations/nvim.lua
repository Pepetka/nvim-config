local treesitter = require("stable_folds.integrations.treesitter")
local integer = require("stable_folds.core.config").integer
local foldexpr = require("stable_folds.core.config").foldexpr
local view_states = require("stable_folds.core.view").states
local api = vim.api
local M = {}
local sequence = 0

---@param win? integer
---@return integer?
local function window(win)
  if win == nil or win == 0 then
    return api.nvim_get_current_win()
  end
  if integer(win) and api.nvim_win_is_valid(win) then
    return win
  end
end

---@return StableFoldsAdapter
function M.new()
  sequence = sequence + 1
  local suffix = sequence == 1 and "" or tostring(sequence)
  local namespace = api.nvim_create_namespace("StableFoldStarts" .. suffix)
  local group_name = "SynchronousFolds" .. suffix
  ---@type integer?
  local group
  ---@type integer[]
  local handlers = {}
  ---@type table<integer, boolean>
  local marked = {}
  ---@type table<integer, StableFoldsWatcher>
  local watched = {}
  ---@type table<integer, integer[]>
  local reload_windows = {}
  local adapter = { collect = treesitter.collect }

  ---@return integer
  function adapter.current_window()
    return api.nvim_get_current_win()
  end

  ---@return integer
  function adapter.line()
    return vim.v.lnum
  end

  ---@param buf integer
  ---@param tick integer
  ---@return boolean
  function adapter.ready(buf, tick)
    local watcher = watched[buf]
    return not watcher or watcher.ready_tick == tick
  end

  ---@param buf integer
  ---@return nil
  function adapter.settled(buf)
    if watched[buf] then
      watched[buf].ready_tick = api.nvim_buf_get_changedtick(buf)
    end
  end

  ---@param win? integer
  ---@return StableFoldsContext?
  function adapter.context(win)
    local resolved = window(win)
    if not resolved then
      return nil
    end
    local buf = api.nvim_win_get_buf(resolved)
    if not api.nvim_buf_is_loaded(buf) then
      return nil
    end
    return {
      buf = buf,
      win = resolved,
      tick = api.nvim_buf_get_changedtick(buf),
      filetype = vim.bo[buf].filetype,
      lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype),
      buftype = vim.bo[buf].buftype,
      line = vim.v.lnum,
      minlines = vim.wo[resolved].foldminlines,
      nestmax = vim.wo[resolved].foldnestmax,
      foldlevel = vim.wo[resolved].foldlevel,
    }
  end

  ---@param buf? integer
  ---@return integer?
  function adapter.buffer(buf)
    if buf == nil or buf == 0 then
      buf = api.nvim_get_current_buf()
    end
    if integer(buf) and api.nvim_buf_is_valid(buf) and api.nvim_buf_is_loaded(buf) then
      return buf
    end
  end

  ---@param buf integer
  ---@return string[]
  function adapter.lines(buf)
    return api.nvim_buf_get_lines(buf, 0, -1, false)
  end

  ---@param buf integer
  ---@return integer
  function adapter.line_count(buf)
    return api.nvim_buf_line_count(buf)
  end

  ---Read only header rows, grouping consecutive starts into one buffer read.
  ---@param buf integer
  ---@param ranges StableFoldsRange[] Sorted normalized ranges.
  ---@return StableFoldsHeader[]
  function adapter.headers(buf, ranges)
    local rows = {}
    for _, range in ipairs(ranges) do
      if rows[#rows] ~= range.start then
        rows[#rows + 1] = range.start
      end
    end
    local result, index = {}, 1
    while index <= #rows do
      local last = index
      while rows[last + 1] == rows[last] + 1 do
        last = last + 1
      end
      local text = api.nvim_buf_get_lines(buf, rows[index] - 1, rows[last], false)
      for offset, header in ipairs(text) do
        result[#result + 1] = { line = rows[index] + offset - 1, header = header }
      end
      index = last + 1
    end
    return result
  end

  ---@param buf integer
  ---@return StableFoldsSize
  function adapter.size(buf)
    local count = api.nvim_buf_line_count(buf)
    return { lines = count, bytes = api.nvim_buf_get_offset(buf, count) }
  end

  ---@param buf integer
  ---@param marks StableFoldsMark[]
  ---@return StableFoldsPosition[]
  function adapter.positions(buf, marks)
    local positions = {}
    for _, position in ipairs(api.nvim_buf_get_extmarks(buf, namespace, 0, -1, {})) do
      positions[position[1]] = position[2] + 1
    end
    local result = {}
    for _, mark in ipairs(marks) do
      result[#result + 1] = {
        id = mark.id,
        header = mark.header,
        new = mark.new,
        line = positions[mark.id],
      }
    end
    return result
  end

  ---@param buf integer
  ---@param plan StableFoldsMarkPlan
  ---@return StableFoldsMark[]
  function adapter.apply_marks(buf, plan)
    marked[buf] = true
    for _, id in ipairs(plan.delete) do
      api.nvim_buf_del_extmark(buf, namespace, id)
    end
    local result = {}
    for _, mark in ipairs(plan.marks) do
      local id = mark.unchanged and mark.id
        or api.nvim_buf_set_extmark(buf, namespace, mark.line - 1, 0, { id = mark.id, right_gravity = true })
      result[#result + 1] = { id = id, header = mark.header, new = mark.new }
    end
    return result
  end

  ---@param buf integer
  ---@return nil
  function adapter.clear(buf)
    if api.nvim_buf_is_valid(buf) then
      api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    end
    marked[buf] = nil
  end

  ---@param buf integer
  ---@return integer[]
  function adapter.windows(buf)
    local result = {}
    for _, win in ipairs(vim.fn.win_findbuf(buf)) do
      if api.nvim_win_is_valid(win) and vim.wo[win].foldmethod == "expr" and vim.wo[win].foldexpr == foldexpr then
        result[#result + 1] = win
      end
    end
    return result
  end

  ---@return integer[]
  function adapter.buffers()
    local result, seen = {}, {}
    for _, win in ipairs(api.nvim_list_wins()) do
      if vim.wo[win].foldmethod == "expr" and vim.wo[win].foldexpr == foldexpr then
        local buf = api.nvim_win_get_buf(win)
        if not seen[buf] then
          seen[buf] = true
          result[#result + 1] = buf
        end
      end
    end
    return result
  end

  ---@param win? integer
  ---@return integer?
  function adapter.attach(win)
    local resolved = window(win)
    if resolved then
      vim.wo[resolved].foldexpr = foldexpr
      vim.wo[resolved].foldmethod = "expr"
    end
    return resolved
  end

  ---@param buf integer
  ---@param complete boolean
  ---@return nil
  local function restore_reload_windows(buf, complete)
    local windows = reload_windows[buf]
    if complete then
      reload_windows[buf] = nil
    end
    for _, win in ipairs(windows or {}) do
      if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
        adapter.attach(win)
      end
    end
  end

  ---@param win integer
  ---@return nil
  function adapter.recompute(win)
    if window(win) then
      api.nvim_win_call(win, function()
        -- Unlike zx/zX, this preserves manually opened and closed folds.
        vim.wo.foldmethod = "expr"
      end)
    end
  end

  ---@param win integer
  ---@param lines integer[]
  ---@return nil
  function adapter.open(win, lines)
    if #lines == 0 or not window(win) then
      return
    end
    api.nvim_win_call(win, function()
      for _, line in ipairs(lines) do
        if vim.fn.foldclosed(line) == line then
          vim.cmd(line .. "foldopen")
        end
      end
    end)
  end

  ---@param buf integer
  ---@param before_change StableFoldsBeforeChange
  ---@param reloaded? StableFoldsAction
  ---@return StableFoldsAction
  function adapter.watch(buf, before_change, reloaded)
    local watcher = watched[buf]
    if not watcher then
      watcher = { ready_tick = api.nvim_buf_get_changedtick(buf) }
      watched[buf] = watcher
      local ok, attached = pcall(api.nvim_buf_attach, buf, false, {
        on_bytes = function(_, _, tick, start_row, start_col, _, old_rows, _, _, new_rows)
          -- Native folds have shifted, but header extmarks still have old positions.
          if watcher.callback then
            watcher.ready_tick = tick
            watcher.callback({ start_row = start_row, start_col = start_col, old_rows = old_rows, new_rows = new_rows })
          else
            if watched[buf] == watcher then
              watched[buf] = nil
            end
            return true
          end
        end,
        on_detach = function()
          if watched[buf] == watcher then
            watched[buf] = nil
          end
          watcher.callback, watcher.reloaded = nil, nil
        end,
        on_reload = function()
          if watcher.callback then
            watcher.ready_tick = api.nvim_buf_get_changedtick(buf)
            restore_reload_windows(buf, true)
            if watcher.reloaded then
              watcher.reloaded()
            end
          end
        end,
      })
      if not ok or not attached then
        watched[buf] = nil
        error(ok and ("cannot watch fold buffer " .. buf) or tostring(attached), 0)
      end
    end
    watcher.callback, watcher.reloaded = before_change, reloaded
    return function()
      if watcher.callback == before_change then
        watcher.callback, watcher.reloaded = nil, nil
      end
    end
  end

  ---@param win integer
  ---@param positions StableFoldsPosition[]
  ---@param adjust? fun(shifted: boolean): nil
  ---@return table<integer, boolean>
  function adapter.closed(win, positions, adjust)
    return api.nvim_win_call(win, function()
      local count = api.nvim_buf_line_count(0)
      for _, mark in ipairs(positions) do
        if mark.line and mark.line > count then
          -- :checktime empties the text before BufReadPre, but retains the native
          -- fold tree. foldclosed() cannot inspect rows beyond the current text;
          -- mkview can serialize their flags. Only read it, never source it.
          local path, options = vim.fn.tempname(), vim.o.viewoptions
          local ok, result = pcall(function()
            vim.cmd("noautocmd set viewoptions=folds")
            vim.cmd("noautocmd mkview! " .. vim.fn.fnameescape(path))
            return view_states(vim.fn.readfile(path), positions, vim.wo.foldlevel)
          end)
          local restored, restore_error = pcall(function()
            vim.cmd("noautocmd set viewoptions=" .. options)
          end)
          vim.fn.delete(path)
          if not ok then
            error(result, 0)
          end
          if not restored then
            error(restore_error, 0)
          end
          return result
        end
      end
      local method, view = vim.wo.foldmethod, vim.fn.winsaveview()
      local opened = {}
      ---@type table<integer, boolean>
      local observed = {}
      local ok, result = pcall(function()
        -- Freeze the native tree while querying flags. Re-evaluating expr during
        -- on_bytes would apply old levels to the already edited buffer.
        vim.wo.foldmethod = "manual"
        local moved = true
        local decided = false
        ---@type table<integer, integer>
        local selected = {}
        ---@param row integer
        ---@param depth? integer
        ---@return boolean
        local function starts(row, depth)
          if vim.fn.foldclosed(row) == row then
            return true
          end
          local level = vim.fn.foldlevel(row)
          return level > 0 and level > vim.fn.foldlevel(row - 1) and (not depth or level >= depth)
        end
        for _, mark in ipairs(positions) do
          if mark.line and mark.old_line and mark.line ~= mark.old_line then
            local new_start, old_start = starts(mark.line, mark.level), starts(mark.old_line, mark.level)
            if new_start ~= old_start then
              selected[mark.id] = new_start and mark.line or mark.old_line
              if not decided then
                moved = new_start
                decided = true
              end
            end
          end
        end
        if adjust then
          adjust(moved)
        end
        local states = {}
        for _, mark in ipairs(positions) do
          local line = selected[mark.id] or (not moved and mark.old_line or mark.line)
          if line then
            if observed[line] ~= nil then
              states[mark.id] = observed[line]
            else
              local closed = vim.fn.foldclosed(line)
              while closed ~= -1 and closed < line do
                opened[#opened + 1] = closed
                vim.cmd(closed .. "foldopen")
                local next_closed = vim.fn.foldclosed(line)
                if next_closed == closed then
                  error("cannot expose hidden fold at line " .. line, 0)
                end
                closed = next_closed
              end
              states[mark.id] = closed == line
              observed[line] = states[mark.id]
              if closed == line then
                opened[#opened + 1] = closed
                vim.cmd(closed .. "foldopen")
              end
            end
          end
        end
        return states
      end)
      -- Restore every temporarily exposed ancestor, including hidden children.
      table.sort(opened, function(a, b)
        return a > b
      end)
      local failure = not ok and result or nil
      ---@param action StableFoldsAction
      local function cleanup(action)
        local restored, err = pcall(action)
        if not restored and failure == nil then
          failure = err
        end
      end
      for _, line in ipairs(opened) do
        cleanup(function()
          vim.cmd.foldclose({ range = { line } })
        end)
      end
      cleanup(function()
        vim.wo.foldmethod = method
      end)
      cleanup(function()
        vim.fn.winrestview(view)
      end)
      if failure ~= nil then
        error(failure, 0)
      end
      return result
    end)
  end

  ---@param win integer
  ---@param states StableFoldsFoldState[]
  ---@return nil
  function adapter.restore(win, states)
    if #states == 0 or not window(win) then
      return
    end
    api.nvim_win_call(win, function()
      -- Open ancestors first; close children before ancestors. Avoid opening
      -- existing nested folds recursively when restoring an open parent.
      for _, state in ipairs(states) do
        if not state.closed and vim.fn.foldclosed(state.line) == state.line then
          vim.cmd(state.line .. "foldopen")
        end
      end
      for index = #states, 1, -1 do
        local state = states[index]
        if state.closed and vim.fn.foldclosed(state.line) == -1 then
          vim.cmd(state.line .. "foldclose")
        end
      end
    end)
  end

  ---@return nil
  function adapter.uninstall()
    reload_windows = {}
    for _, watcher in pairs(watched) do
      watcher.callback, watcher.reloaded = nil, nil
    end
    for _, id in ipairs(handlers) do
      pcall(api.nvim_del_autocmd, id)
    end
    handlers = {}
    if group then
      local ok, remaining = pcall(api.nvim_get_autocmds, { group = group })
      if ok and #remaining == 0 then
        pcall(api.nvim_del_augroup_by_id, group)
      end
      group = nil
    end
    for buf in pairs(marked) do
      adapter.clear(buf)
    end
  end

  ---@param callbacks StableFoldsCallbacks
  ---@return nil
  function adapter.install(callbacks)
    adapter.uninstall()
    group = api.nvim_create_augroup(group_name, { clear = false })
    local ok, err = pcall(function()
      handlers[#handlers + 1] = api.nvim_create_autocmd("BufReadPre", {
        group = group,
        desc = "Capture stable fold states before disk reload",
        callback = function(args)
          reload_windows[args.buf] = reload_windows[args.buf] or adapter.windows(args.buf)
          callbacks.reading(args.buf)
        end,
      })
      handlers[#handlers + 1] = api.nvim_create_autocmd("BufReadPost", {
        group = group,
        desc = "Restore stable folding after reload filetype plugins",
        callback = function(args)
          local windows = reload_windows[args.buf]
          local watcher = watched[args.buf]
          restore_reload_windows(args.buf, not (watcher and watcher.callback))
          if windows then
            callbacks.changed(args.buf)
          end
        end,
      })
      handlers[#handlers + 1] = api.nvim_create_autocmd(
        { "TextChanged", "TextChangedI", "TextChangedP", "InsertLeave", "BufWritePost" },
        {
          group = group,
          desc = "Refresh complete stable fold boundaries",
          callback = function(args)
            if watched[args.buf] then
              watched[args.buf].ready_tick = api.nvim_buf_get_changedtick(args.buf)
            end
            callbacks.changed(args.buf)
          end,
        }
      )
      handlers[#handlers + 1] = api.nvim_create_autocmd("BufWinEnter", {
        group = group,
        desc = "Retry unavailable stable fold parsers and queries",
        callback = function(args)
          if watched[args.buf] then
            watched[args.buf].ready_tick = api.nvim_buf_get_changedtick(args.buf)
          end
          callbacks.entered(args.buf)
        end,
      })
      handlers[#handlers + 1] = api.nvim_create_autocmd("FileType", {
        group = group,
        desc = "Reset stable folds after a filetype change",
        callback = function(args)
          callbacks.reset(args.buf)
        end,
      })
      handlers[#handlers + 1] = api.nvim_create_autocmd("BufUnload", {
        group = group,
        desc = "Suspend stable fold identities before unloading",
        callback = function(args)
          reload_windows[args.buf] = adapter.windows(args.buf)
          callbacks.unloaded(args.buf)
        end,
      })
      handlers[#handlers + 1] = api.nvim_create_autocmd("BufWipeout", {
        group = group,
        desc = "Release stable fold buffer state",
        callback = function(args)
          reload_windows[args.buf] = nil
          callbacks.deleted(args.buf)
        end,
      })
      handlers[#handlers + 1] = api.nvim_create_autocmd("WinClosed", {
        group = group,
        desc = "Release stable fold window state",
        callback = function(args)
          callbacks.closed(assert(tonumber(args.match)))
        end,
      })
      handlers[#handlers + 1] = api.nvim_create_autocmd("OptionSet", {
        group = group,
        pattern = { "foldminlines", "foldnestmax" },
        desc = "Refresh window-specific stable fold levels",
        callback = function(args)
          callbacks.changed(args.buf)
        end,
      })
      handlers[#handlers + 1] = api.nvim_create_autocmd("User", {
        group = group,
        pattern = "TSUpdate",
        desc = "Refresh stable fold parsers and queries",
        callback = callbacks.updated,
      })
    end)
    if not ok then
      adapter.uninstall()
      error(err, 0)
    end
  end

  ---@param message string
  ---@return nil
  function adapter.notify(message)
    vim.schedule(function()
      vim.notify(message, vim.log.levels.WARN)
    end)
  end

  return adapter
end

return M
