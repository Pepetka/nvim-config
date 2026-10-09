local M = {}

---@type table<CheatsheetHighlight, string>
local highlights = {
  CheatsheetTitle = "FloatTitle",
  CheatsheetGroup = "Title",
  CheatsheetGroupIcon = "Constant",
  CheatsheetKey = "Special",
  CheatsheetDesc = "Normal",
  CheatsheetSeparator = "WinSeparator",
}

---@return CheatsheetAdapter
function M.new()
  local api = vim.api
  ---@type integer?
  local namespace
  local adapter = {}

  ---@param message string
  ---@param level CheatsheetLogLevel
  ---@return nil
  function adapter.notify(message, level)
    vim.notify(message, vim.log.levels[level])
  end

  ---@param value boolean
  ---@return nil
  function adapter.displayed(value)
    vim.g.cheatsheet_displayed = value
  end

  ---@return integer source_buf, integer source_win
  function adapter.source()
    return api.nvim_get_current_buf(), api.nvim_get_current_win()
  end

  ---@return CheatsheetViewport
  function adapter.viewport()
    return { columns = vim.o.columns, lines = vim.o.lines }
  end

  ---@return string
  function adapter.leader()
    return vim.g.mapleader or "\\"
  end

  ---@param text string
  ---@return integer
  function adapter.measure(text)
    return vim.fn.strdisplaywidth(text)
  end

  ---@param session CheatsheetSession
  ---@return boolean
  function adapter.valid(session)
    return session.win ~= nil
      and api.nvim_win_is_valid(session.win)
      and session.buf ~= nil
      and api.nvim_buf_is_valid(session.buf)
  end

  ---@param session CheatsheetSession
  ---@return boolean
  function adapter.exists(session)
    return (session.win ~= nil and api.nvim_win_is_valid(session.win))
      or (session.buf ~= nil and api.nvim_buf_is_valid(session.buf))
  end

  ---@param mode CheatsheetMode
  ---@param source_buf integer
  ---@return CheatsheetRawMapping[] global, CheatsheetRawMapping[] local_mappings
  function adapter.collect(mode, source_buf)
    local local_mappings = {}
    if api.nvim_buf_is_valid(source_buf) then
      local_mappings = api.nvim_buf_get_keymap(source_buf, mode)
    end
    return api.nvim_get_keymap(mode), local_mappings
  end

  ---@param options CheatsheetConfig
  ---@param size CheatsheetGeometry
  ---@return vim.api.keyset.win_config
  local function float_config(options, size)
    ---@type vim.api.keyset.win_config
    local result = {
      relative = "editor",
      row = size.row,
      col = size.col,
      width = size.width,
      height = size.height,
      border = options.window.border,
      style = "minimal",
      zindex = options.window.zindex,
    }
    if options.window.border ~= "none" and options.window.title ~= "" then
      result.title, result.title_pos = options.window.title, options.window.title_pos
    end
    return result
  end

  ---@param session CheatsheetSession
  ---@return nil
  function adapter.close(session)
    local win, buf = session.win, session.buf
    local restore_focus = win and api.nvim_win_is_valid(win) and api.nvim_get_current_win() == win
    local failure
    if win and api.nvim_win_is_valid(win) then
      local ok, err = pcall(api.nvim_win_close, win, true)
      if not ok then
        failure = err
      end
    end
    if buf and api.nvim_buf_is_valid(buf) then
      local ok, err = pcall(api.nvim_buf_delete, buf, { force = true })
      if not ok then
        failure = err
      end
    end
    if restore_focus and session.source_win and api.nvim_win_is_valid(session.source_win) then
      api.nvim_set_current_win(session.source_win)
    end
    if failure then
      error(failure, 0)
    end
  end

  ---@param options CheatsheetConfig
  ---@param source_buf integer
  ---@param source_win integer
  ---@param actions CheatsheetActions
  ---@param size CheatsheetGeometry
  ---@return CheatsheetSession session, string? error
  function adapter.create(options, source_buf, source_win, actions, size)
    ---@type CheatsheetSession
    local session = { source_buf = source_buf, source_win = source_win, options = options }
    local ok, err = pcall(function()
      session.buf = api.nvim_create_buf(false, true)
      for name, value in pairs({ buftype = "nofile", buflisted = false, bufhidden = "wipe", swapfile = false }) do
        api.nvim_set_option_value(name, value, { buf = session.buf })
      end
      api.nvim_set_option_value("filetype", "cheatsheet", { buf = session.buf })
      session.win = api.nvim_open_win(session.buf, true, float_config(options, size))
      api.nvim_set_option_value("wrap", false, { win = session.win })
      ---@param key string
      ---@param callback CheatsheetAction
      ---@param desc string
      ---@return nil
      local function map(key, callback, desc)
        vim.keymap.set("n", key, callback, { buffer = session.buf, silent = true, desc = "Cheatsheet: " .. desc })
      end
      for _, key in ipairs(options.mappings.close) do
        map(key, actions.close, "Close")
      end
      map(options.mappings.next_mode, actions.next_mode, "Next mode")
      map(options.mappings.prev_mode, actions.prev_mode, "Previous mode")
      assert(adapter.valid(session), "cheatsheet window was closed during creation")
    end)
    if not ok then
      -- Transfer partial allocations to the controller, which owns cleanup and retries.
      return session, tostring(err or "failed to create cheatsheet window")
    end
    return session
  end

  ---@param session CheatsheetSession
  ---@param size CheatsheetGeometry
  ---@param document CheatsheetDocument
  ---@param reset boolean
  ---@return nil
  function adapter.update(session, size, document, reset)
    local win, buf = assert(session.win), assert(session.buf)
    local namespace = assert(namespace)
    local view = api.nvim_win_call(win, vim.fn.winsaveview)
    local current = api.nvim_win_get_config(win)
    if
      current.width ~= size.width
      or current.height ~= size.height
      or current.row ~= size.row
      or current.col ~= size.col
    then
      api.nvim_win_set_config(win, float_config(session.options, size))
    end
    api.nvim_set_option_value("modifiable", true, { buf = buf })
    local ok, err = pcall(function()
      api.nvim_buf_set_lines(buf, 0, -1, false, document.lines)
      api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
      for _, span in ipairs(document.spans) do
        api.nvim_buf_set_extmark(buf, namespace, span.row, span.start_col, {
          end_row = span.row,
          end_col = span.end_col,
          hl_group = span.hl_group,
          strict = true,
        })
      end
    end)
    if api.nvim_buf_is_valid(buf) then
      api.nvim_set_option_value("modifiable", false, { buf = buf })
    end
    if not ok then
      error(err, 0)
    end
    if reset then
      api.nvim_win_set_cursor(win, { 1, 0 })
    else
      api.nvim_win_call(win, function()
        vim.fn.winrestview(view)
      end)
    end
  end

  ---@param options CheatsheetConfig
  ---@param callbacks CheatsheetCallbacks
  ---@return nil
  function adapter.install(options, callbacks)
    local group, command_created
    local ok, err = pcall(function()
      namespace = api.nvim_create_namespace("cheatsheet")
      ---@return nil
      local function set_highlights()
        for name, link in pairs(highlights) do
          api.nvim_set_hl(0, name, { link = link })
        end
      end
      set_highlights()
      group = api.nvim_create_augroup("Cheatsheet", { clear = true })
      api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })
      api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(args)
          local win = tonumber(args.match)
          if win then
            callbacks.closed("win", win)
          end
        end,
      })
      api.nvim_create_autocmd("BufWipeout", {
        group = group,
        callback = function(args)
          callbacks.closed("buf", args.buf)
        end,
      })
      local pending = false
      api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
        group = group,
        callback = function()
          if pending then
            return
          end
          pending = true
          vim.schedule(function()
            pending = false
            callbacks.resize()
          end)
        end,
      })
      api.nvim_create_user_command("Cheatsheet", callbacks.toggle, { desc = "Toggle cheatsheet window" })
      command_created = true
      if options.open_mapping then
        vim.keymap.set("n", options.open_mapping, callbacks.toggle, { desc = "Cheatsheet: Toggle", silent = true })
      end
    end)
    if not ok then
      if group then
        pcall(api.nvim_del_augroup_by_id, group)
      end
      if command_created then
        pcall(api.nvim_del_user_command, "Cheatsheet")
      end
      error(err, 0)
    end
  end

  return adapter
end

return M
