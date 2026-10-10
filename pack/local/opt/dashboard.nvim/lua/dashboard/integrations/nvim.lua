local api = vim.api
local M = {}

---@class DashboardWindowState
---@field session DashboardSession
---@field options table<string, string|boolean|integer>
---@field keys string[]
---@field document? DashboardDocument Last document actually applied by the adapter.
---@field mapping_signature? string[]
---@field mapping_revision? integer
---@field width? integer
---@field height? integer
---@field winbar_hidden? boolean
---@field saved_winbar? string

---@param description string
---@param options? vim.keymap.set.Opts
---@return vim.keymap.set.Opts
local function default_map_opts(description, options)
  return vim.tbl_extend("force", { desc = description, silent = true, nowait = true }, options or {})
end

---@return DashboardAdapter
function M.new()
  local adapter = {}
  ---@cast adapter DashboardAdapter
  ---@type DashboardConfig?
  local config
  ---@type DashboardCallbacks?
  local callbacks
  ---@type table<integer, DashboardWindowState>
  local windows = {}
  ---@type table<string, integer>?
  local chrome
  ---@type DashboardStyles
  local original_styles = {}
  ---@type DashboardStyles
  local active_styles = {}
  local group, command, changing, startup_done = nil, false, false, false
  local resize_queued, epoch = false, 0
  local mapping_revision = 0
  local ns = api.nvim_create_namespace("Dashboard")
  local selection_ns = api.nvim_create_namespace("DashboardSelection")
  ---@type table<string, string|boolean>
  local window_options = {
    number = false,
    relativenumber = false,
    cursorline = false,
    cursorcolumn = false,
    signcolumn = "no",
    foldcolumn = "0",
    statuscolumn = "",
    colorcolumn = "",
    list = false,
    spell = false,
    wrap = false,
  }

  ---@param win integer
  ---@return boolean
  local function ordinary(win)
    return api.nvim_win_is_valid(win) and api.nvim_win_get_config(win).relative == ""
  end

  ---@param session DashboardSession
  ---@return boolean
  function adapter.valid(session)
    return ordinary(session.win)
      and api.nvim_buf_is_valid(session.buf)
      and api.nvim_win_get_buf(session.win) == session.buf
  end

  ---@param win? integer
  ---@return DashboardContext
  function adapter.context(win)
    if not win or win == 0 then
      win = api.nvim_get_current_win()
    end
    assert(ordinary(win), "dashboard requires an ordinary window")
    return {
      win = win,
      source_buf = api.nvim_win_get_buf(win),
      width = api.nvim_win_get_width(win),
      height = api.nvim_win_get_height(win),
    }
  end

  ---@param text string
  ---@return integer
  function adapter.measure(text)
    return vim.fn.strdisplaywidth(text)
  end

  ---@param key string
  ---@return string
  function adapter.normalize_key(key)
    return api.nvim_replace_termcodes(key, true, true, true)
  end

  ---@param name string
  ---@param hidden boolean
  ---@return nil
  local function reconcile_panel(name, hidden)
    local saved = chrome and chrome[name]
    if hidden then
      if saved == nil then
        local value = api.nvim_get_option_value(name, { scope = "global" })
        ---@cast value integer
        chrome = chrome or {}
        chrome[name] = value
      end
      if api.nvim_get_option_value(name, { scope = "global" }) ~= 0 then
        api.nvim_set_option_value(name, 0, { scope = "global" })
      end
    elseif saved ~= nil then
      assert(chrome)[name] = nil
      api.nvim_set_option_value(name, saved, { scope = "global" })
    end
  end

  ---@param state DashboardWindowState
  ---@param hidden boolean
  ---@return nil
  local function reconcile_winbar(state, hidden)
    if hidden then
      local value = api.nvim_get_option_value("winbar", { win = state.session.win })
      if not state.winbar_hidden and state.saved_winbar == nil then
        ---@cast value string
        state.saved_winbar = value
      end
      state.winbar_hidden = true
      if value ~= "" then
        api.nvim_set_option_value("winbar", "", { win = state.session.win })
      end
    elseif state.winbar_hidden then
      local saved = state.saved_winbar or state.options.winbar
      state.winbar_hidden = false
      state.saved_winbar = nil
      api.nvim_set_option_value("winbar", saved, { win = state.session.win })
    else
      state.saved_winbar = nil
    end
  end

  ---@return nil
  function adapter.reconcile()
    if changing then
      return
    end
    changing = true
    local ok, err = pcall(function()
      local visible = false
      local current_tab = api.nvim_get_current_tabpage()
      for _, state in pairs(windows) do
        local session = state.session
        if adapter.valid(session) then
          if api.nvim_win_get_tabpage(session.win) == current_tab then
            visible = true
          end
          reconcile_winbar(state, config ~= nil and config.chrome.hide_winbar)
        end
      end
      reconcile_panel("laststatus", visible and config ~= nil and config.chrome.hide_statusline)
      reconcile_panel("showtabline", visible and config ~= nil and config.chrome.hide_tabline)
      if chrome and not next(chrome) then
        chrome = nil
      end
    end)
    changing = false
    if not ok then
      error(err)
    end
  end

  ---@param win integer
  ---@param options table<string, string|boolean|integer>
  ---@return nil
  local function restore_window(win, options)
    if api.nvim_win_is_valid(win) then
      for name, value in pairs(options) do
        api.nvim_set_option_value(name, value, { win = win })
      end
    end
  end

  ---@param session DashboardSession
  ---@param restore boolean
  ---@return nil
  function adapter.close(session, restore)
    local state = windows[session.win]
    if not state then
      return
    end
    windows[session.win] = nil
    local ok, err = pcall(function()
      restore_window(session.win, state.options)
      if restore and adapter.valid(session) then
        local source = api.nvim_buf_is_valid(session.source_buf) and session.source_buf
          or api.nvim_create_buf(true, false)
        api.nvim_win_set_buf(session.win, source)
      end
      if api.nvim_buf_is_valid(session.buf) then
        -- A native split may still display this buffer until it is adopted.
        for _, win in ipairs(vim.fn.win_findbuf(session.buf)) do
          if ordinary(win) then
            restore_window(win, state.options)
          end
          local source = api.nvim_buf_is_valid(session.source_buf) and session.source_buf
            or api.nvim_create_buf(true, false)
          api.nvim_win_set_buf(win, source)
        end
        if api.nvim_buf_is_valid(session.buf) then
          api.nvim_buf_delete(session.buf, { force = true })
        end
      end
    end)
    if not ok then
      windows[session.win] = state
      adapter.reconcile()
      error(err)
    end
    adapter.reconcile()
  end

  ---@param win integer
  ---@return table<string, string|boolean|integer>
  local function capture_window(win)
    local buf = api.nvim_win_get_buf(win)
    for _, parent in pairs(windows) do
      if buf == parent.session.buf then
        return vim.deepcopy(parent.options)
      end
    end
    local options = {}
    for name in pairs(window_options) do
      options[name] = api.nvim_get_option_value(name, { win = win })
    end
    options.winbar = api.nvim_get_option_value("winbar", { win = win })
    return options
  end

  ---@param context DashboardContext
  ---@param track fun(session: DashboardSession): nil
  ---@return DashboardSession
  function adapter.create(context, track)
    local options = capture_window(context.win)
    local visible_winbar = api.nvim_get_option_value("winbar", { win = context.win })
    local saved_winbar = options.winbar
    ---@cast saved_winbar string
    local buf = api.nvim_create_buf(false, true)
    local session = {
      win = context.win,
      buf = buf,
      source_buf = context.source_buf,
      document = { lines = {}, spans = {}, targets = {} },
    }
    ---@type DashboardWindowState
    local state = { session = session, options = options, keys = {}, saved_winbar = saved_winbar }
    windows[context.win] = state
    track(session)
    vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "nofile", "wipe", false
    api.nvim_win_set_buf(context.win, buf)
    for name, value in pairs(window_options) do
      api.nvim_set_option_value(name, value, { win = context.win })
    end
    if config and not config.chrome.hide_winbar then
      -- Buffer changes reset local winbar state; preserve it without pinning future changes.
      api.nvim_set_option_value("winbar", visible_winbar, { win = context.win })
    end
    adapter.reconcile()
    return session
  end

  ---@param session DashboardSession
  ---@param target? DashboardTarget
  ---@param document? DashboardDocument
  ---@return nil
  function adapter.select(session, target, document)
    if adapter.valid(session) then
      api.nvim_buf_clear_namespace(session.buf, selection_ns, 0, -1)
      if target and config and config.navigation.highlight_selected then
        local current = document or assert(windows[session.win]).document or session.document
        local line = current.lines[target.row + 1]
        local start = #assert(line:match("^ *"))
        if #line > start then
          api.nvim_buf_set_extmark(session.buf, selection_ns, target.row, start, {
            end_row = target.row,
            end_col = #line,
            hl_group = "DashboardSelected",
            priority = 4097,
          })
        end
      end
      api.nvim_win_set_cursor(session.win, target and { target.row + 1, target.col } or { 1, 0 })
    end
  end

  ---@param state DashboardWindowState
  ---@param key string
  ---@param description string
  ---@param fn fun(): nil
  ---@param builder DashboardMapOpts
  ---@return nil
  local function map(state, key, description, fn, builder)
    vim.keymap.set("n", key, fn, builder(description, { buffer = state.session.buf, nowait = true }))
    state.keys[#state.keys + 1] = key
  end

  ---@param state DashboardWindowState
  ---@param document DashboardDocument
  ---@param fallback? DashboardMapOpts
  ---@return nil
  local function mappings(state, document, fallback)
    local signature = {}
    for _, target in ipairs(document.targets) do
      if target.key then
        signature[#signature + 1] = (target.block_id or "") .. "\0" .. target.id .. "\0" .. target.key
      end
    end
    if
      not fallback
      and state.mapping_revision == mapping_revision
      and vim.deep_equal(state.mapping_signature, signature)
    then
      return
    end
    state.mapping_signature, state.mapping_revision = nil, nil
    local builder = fallback or (config and config.map_opts) or default_map_opts
    for _, key in ipairs(state.keys) do
      api.nvim_buf_del_keymap(state.session.buf, "n", key)
    end
    state.keys = {}
    local cb = assert(callbacks)
    local navigation = assert(config).navigation.keys
    for _, key in ipairs(navigation.next) do
      map(state, key, "Dashboard: next action", function()
        cb.move(state.session.win, vim.v.count1)
      end, builder)
    end
    for _, key in ipairs(navigation.previous) do
      map(state, key, "Dashboard: previous action", function()
        cb.move(state.session.win, -vim.v.count1)
      end, builder)
    end
    for _, key in ipairs(navigation.activate) do
      map(state, key, "Dashboard: run selected action", function()
        cb.activate(state.session.win)
      end, builder)
    end
    for _, target in ipairs(document.targets) do
      if target.key then
        map(state, target.key, "Dashboard: " .. target.id, function()
          cb.activate(state.session.win, target.block_id, target.id)
        end, builder)
      end
    end
    if not fallback then
      state.mapping_signature, state.mapping_revision = signature, mapping_revision
    end
  end

  ---@param buf integer
  ---@param document DashboardDocument
  ---@return nil
  local function highlight(buf, document)
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, span in ipairs(document.spans) do
      api.nvim_buf_set_extmark(buf, ns, span.row, span.start_col, {
        end_col = span.end_col,
        hl_group = "Dashboard" .. span.style,
      })
    end
  end

  ---@param session DashboardSession
  ---@param document DashboardDocument
  ---@param selected? DashboardTarget
  ---@return nil
  function adapter.apply(session, document, selected)
    assert(adapter.valid(session), "dashboard resources are no longer valid")
    local buf = session.buf
    local state = assert(windows[session.win])
    local previous = state.document or { lines = { "" }, spans = {}, targets = {} }
    local ok, err = pcall(function()
      local lines_changed = not vim.deep_equal(previous.lines, document.lines)
      if lines_changed then
        vim.bo[buf].modifiable = true
        api.nvim_buf_set_lines(buf, 0, -1, false, document.lines)
      end
      if lines_changed or not vim.deep_equal(previous.spans, document.spans) then
        highlight(buf, document)
      end
      mappings(state, document)
      if vim.bo[buf].filetype ~= "dashboard" then
        vim.bo[buf].filetype = "dashboard"
      end
      adapter.select(session, selected, document)
    end)
    if not ok then
      vim.bo[buf].modifiable = true
      api.nvim_buf_set_lines(buf, 0, -1, false, previous.lines)
      highlight(buf, previous)
      mappings(state, previous, default_map_opts)
      adapter.select(session, session.selected, previous)
      vim.bo[buf].modifiable, vim.bo[buf].modified = false, false
      error(err)
    end
    state.document = document
    state.width, state.height = api.nvim_win_get_width(session.win), api.nvim_win_get_height(session.win)
    vim.bo[buf].modifiable, vim.bo[buf].modified = false, false
  end

  ---@param styles DashboardStyles
  ---@return nil
  function adapter.styles(styles)
    local before = {}
    local ok, err = pcall(function()
      for role in pairs(active_styles) do
        before[role] = api.nvim_get_hl(0, { name = "Dashboard" .. role })
        if not styles[role] then
          api.nvim_set_hl(0, "Dashboard" .. role, original_styles[role])
        end
      end
      for role, value in pairs(styles) do
        local name = "Dashboard" .. role
        before[role] = before[role] or api.nvim_get_hl(0, { name = name })
        original_styles[role] = original_styles[role] or before[role]
        api.nvim_set_hl(0, name, value)
      end
    end)
    if not ok then
      for role, value in pairs(before) do
        api.nvim_set_hl(0, "Dashboard" .. role, value)
      end
      error(err)
    end
    active_styles = styles
  end

  ---@param candidate DashboardConfig
  ---@param styles DashboardStyles
  ---@return nil
  function adapter.configure(candidate, styles)
    adapter.styles(styles)
    config = candidate
    mapping_revision = mapping_revision + 1
    adapter.reconcile()
  end

  ---@return integer[]
  function adapter.aliases()
    local result = {}
    if not next(windows) then
      return result
    end
    ---@type table<integer, boolean>
    local buffers = {}
    for _, state in pairs(windows) do
      buffers[state.session.buf] = true
    end
    for _, win in ipairs(api.nvim_list_wins()) do
      if not windows[win] and ordinary(win) and buffers[api.nvim_win_get_buf(win)] then
        result[#result + 1] = win
      end
    end
    return result
  end

  ---@return nil
  local function startup()
    if startup_done or not config or not config.autostart or #api.nvim_list_uis() == 0 then
      return
    end
    startup_done = true
    local ctx = adapter.context()
    local buf = ctx.source_buf
    if vim.fn.argc() ~= 0 or vim.bo[buf].buftype ~= "" or vim.bo[buf].modified or api.nvim_buf_get_name(buf) ~= "" then
      return
    end
    for _, arg in ipairs(vim.v.argv) do
      if arg == "-" then
        return
      end
    end
    if api.nvim_buf_line_count(buf) == 1 and api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "" then
      assert(callbacks).show(ctx.win)
    end
  end

  ---@return nil
  local function resized()
    if resize_queued or not next(windows) then
      return
    end
    resize_queued = true
    local ticket = epoch
    vim.schedule(function()
      if ticket == epoch and callbacks then
        resize_queued = false
        for _, state in pairs(windows) do
          local session = state.session
          if
            adapter.valid(session)
            and (
              state.width ~= api.nvim_win_get_width(session.win)
              or state.height ~= api.nvim_win_get_height(session.win)
            )
          then
            callbacks.refresh(session.win)
          end
        end
      end
    end)
  end

  ---@param cb DashboardCallbacks
  ---@return nil
  function adapter.install(cb)
    callbacks = cb
    assert(vim.fn.exists(":Dashboard") == 0, "Dashboard command already belongs to another plugin")
    group = api.nvim_create_augroup("Dashboard", { clear = true })
    api.nvim_create_user_command("Dashboard", function()
      cb.show()
    end, { desc = "Open dashboard", force = false })
    command = true
    api.nvim_create_autocmd("UIEnter", { group = group, callback = startup })
    api.nvim_create_autocmd({ "VimResized", "WinResized" }, { group = group, callback = resized })
    api.nvim_create_autocmd(
      { "BufEnter", "BufWinEnter", "BufWinLeave", "WinEnter", "WinClosed", "TabEnter", "BufWipeout" },
      {
        group = group,
        callback = function()
          if not next(windows) and not chrome then
            return
          end
          adapter.reconcile()
          cb.changed()
        end,
      }
    )
    api.nvim_create_autocmd("OptionSet", {
      group = group,
      pattern = { "laststatus", "showtabline", "winbar" },
      callback = function()
        if next(windows) or chrome then
          adapter.reconcile()
        end
      end,
    })
    api.nvim_create_autocmd("ColorScheme", {
      group = group,
      callback = function()
        cb.theme()
        -- OptionSet does not nest inside other autocommands. Reconcile after
        -- native colorscheme consumers have finished changing UI options.
        local ticket = epoch
        vim.schedule(function()
          if ticket == epoch and callbacks then
            adapter.reconcile()
          end
        end)
      end,
    })
    api.nvim_create_autocmd("CursorMoved", {
      group = group,
      callback = function()
        local state = windows[api.nvim_get_current_win()]
        if state and adapter.valid(state.session) and state.session.selected then
          local row = api.nvim_win_get_cursor(state.session.win)[1] - 1
          local target = assert(state.session.selected)
          if row ~= target.row then
            cb.move(state.session.win, row > target.row and 1 or -1)
          else
            adapter.select(state.session, target)
          end
        end
      end,
    })
    -- Setup after UI attachment still supports the initial empty screen.
    if vim.v.vim_did_enter == 1 then
      local ticket = epoch
      vim.schedule(function()
        if ticket == epoch then
          startup()
        end
      end)
    end
  end

  ---@return nil
  function adapter.uninstall()
    epoch, resize_queued = epoch + 1, false
    if group then
      api.nvim_del_augroup_by_id(group)
      group = nil
    end
    if command then
      api.nvim_del_user_command("Dashboard")
      command = false
    end
    for role, value in pairs(original_styles) do
      api.nvim_set_hl(0, "Dashboard" .. role, value)
    end
    original_styles, active_styles = {}, {}
    callbacks, config, startup_done = nil, nil, false
    adapter.reconcile()
  end

  ---@param callback fun(): nil
  ---@return nil
  function adapter.schedule(callback)
    vim.schedule(callback)
  end

  ---@param action DashboardRun
  ---@param context DashboardContext
  ---@return nil
  function adapter.run(action, context)
    ---@return nil
    local function execute()
      if type(action) == "string" then
        vim.cmd(action)
      else
        action(context)
      end
    end
    if api.nvim_get_current_win() == context.win then
      -- Temporary window contexts restore focus after the callback, which
      -- would pull focus out of a picker or split opened by an action.
      execute()
    else
      api.nvim_win_call(context.win, execute)
    end
  end

  ---@param message string
  ---@return nil
  function adapter.notify(message)
    vim.notify(message, vim.log.levels.ERROR, { title = "dashboard" })
  end

  return adapter
end

return M
