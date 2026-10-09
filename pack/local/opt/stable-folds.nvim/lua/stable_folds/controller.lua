local config = require("stable_folds.core.config")
local cache = require("stable_folds.core.cache")
local ranges = require("stable_folds.core.ranges")
local tracking = require("stable_folds.core.tracking")
local M = {}
M.foldexpr = config.foldexpr

---@param adapter StableFoldsAdapter
---@return StableFoldsController
function M.new(adapter)
  local options = config.defaults()
  local active, refreshing, evaluating, capturing = true, false, false, false
  local generation = 0
  ---@type table<integer, StableFoldsBuffer>
  local buffers = {}
  ---@type table<integer, StableFoldsBuffer>
  local suspended = {}
  ---@type table<integer, StableFoldsView>
  local views = {}
  ---@type table<integer, StableFoldsApplied>
  local applied = {}
  ---@type { win: integer, view: StableFoldsView }?
  local evaluation
  ---@type table<integer, string>
  local errors = {}
  ---@type table<integer, boolean>
  local pending = {}
  ---@type table<integer, table<string, boolean>>
  local requested = {}
  local controller = { foldexpr = M.foldexpr }
  ---@type fun(buf: integer, force: boolean): nil
  local refresh

  ---@generic T
  ---@param win integer
  ---@param current? StableFoldsView
  ---@param action fun(): T
  ---@return T
  local function with_view(win, current, action)
    local previous = evaluation
    evaluation = current and { win = win, view = current } or nil
    local ok, result = pcall(action)
    evaluation = previous
    if not ok then
      error(result, 0)
    end
    return result
  end

  ---@param err unknown
  ---@param context? StableFoldsContext
  ---@return nil
  local function report(err, context)
    if not options.notify_errors then
      return
    end
    local message = tostring(err):match("^[^\r\n]*") or "unknown error"
    local buf = context and context.buf or 0
    local key = tostring(context and context.tick) .. ":" .. tostring(context and context.lang) .. ":" .. message
    if errors[buf] ~= key then
      errors[buf] = key
      pcall(adapter.notify, "stable-folds: " .. message)
    end
  end

  ---@param buf integer
  ---@return nil
  local function forget_views(buf)
    for win, view in pairs(views) do
      if view.buf == buf then
        views[win] = nil
      end
    end
    for win, item in pairs(applied) do
      if item.buf == buf then
        applied[win] = nil
      end
    end
  end

  ---@param buf integer
  ---@param state StableFoldsBuffer
  ---@param tick integer
  ---@return StableFoldsPosition[]
  local function positions(buf, state, tick)
    if not state.positions or state.positions_tick ~= tick then
      state.positions = state.tracking and adapter.positions(buf, state.tracking.marks) or {}
      state.positions_tick = tick
    end
    return state.positions
  end

  ---@param buf integer
  ---@return nil
  local function clear(buf)
    local state = buffers[buf]
    if state and state.cancel then
      state.cancel()
    end
    buffers[buf], suspended[buf], errors[buf] = nil, nil, nil
    forget_views(buf)
    local ok, err = pcall(adapter.clear, buf)
    if not ok then
      report(err)
    end
  end

  ---@param buf integer
  ---@param state StableFoldsBuffer
  ---@param edit? StableFoldsEdit
  ---@return nil
  local function before_change(buf, state, edit)
    if not active or evaluating or capturing or buffers[buf] ~= state or not state.tracking then
      return
    end
    capturing = true
    local ok, err = pcall(function()
      state.closed = state.closed or {}
      local shifted
      local original = state.pending_snapshot or state.snapshot
      local entry = original
      if entry and edit and edit.new_rows ~= edit.old_rows then
        entry = {
          tick = entry.tick,
          filetype = entry.filetype,
          lang = entry.lang,
          headers = entry.headers,
          available = entry.available,
          line_count = math.max(1, entry.line_count + edit.new_rows - edit.old_rows),
          ranges = ranges.shift(entry.ranges, edit),
        }
      end
      if edit then
        state.pending_snapshot = entry
      end
      for _, win in ipairs(adapter.windows(buf)) do
        local previous = state.closed[win] or {}
        local unresolved = {}
        for _, mark in ipairs(state.tracking.marks) do
          if previous[mark.id] == nil then
            unresolved[mark.id] = true
          end
        end
        -- Capture each observable identity once. Previously hidden children can
        -- become observable after another edit in the same burst.
        if next(unresolved) then
          shifted = shifted or tracking.shifted(adapter.positions(buf, state.tracking.marks), edit)
          local candidates = {}
          for _, mark in ipairs(shifted) do
            if unresolved[mark.id] then
              candidates[#candidates + 1] =
                { id = mark.id, header = mark.header, line = mark.line, old_line = mark.old_line, new = mark.new }
            end
          end
          local context = adapter.context(win)
          if context and original then
            views[win] = cache.view(original, context, views)
            for _, mark in ipairs(candidates) do
              local row = mark.old_line or mark.line
              local level = row and views[win].levels[row]
              mark.level = level and tonumber(level:match("^>(%d+)$")) or nil
            end
          end
          local observed = with_view(win, views[win], function()
            return adapter.closed(win, candidates, function(moved)
              if context and entry and moved then
                local current = cache.view(entry, context, views)
                views[win] = current
                evaluation = { win = win, view = current }
              end
            end)
          end)
          for id, closed in pairs(observed) do
            if previous[id] == nil then
              previous[id] = closed
            end
          end
        end
        state.closed[win] = previous
      end
    end)
    capturing = false
    if not ok then
      report(err)
    end
  end

  ---@param entry StableFoldsSnapshot
  ---@param context StableFoldsContext
  ---@param state StableFoldsBuffer
  ---@return nil
  local function reconcile(entry, context, state)
    local previous = state.tracking
    if previous and (previous.lang ~= context.lang or previous.filetype ~= context.filetype) then
      adapter.clear(context.buf)
      state.closed = nil
      state.positions = nil
      previous = nil
    end
    local old = previous and (previous.positions or positions(context.buf, state, context.tick)) or {}
    local plan = tracking.match(old, entry.headers, previous ~= nil and previous.tick ~= context.tick)
    if previous and previous.positions then
      -- Saved positions describe an unloaded tree; its extmarks have been cleared.
      for _, mark in ipairs(plan.marks) do
        mark.unchanged = nil
      end
    end
    local ok, marks = pcall(adapter.apply_marks, context.buf, plan)
    if not ok then
      -- Roll back only an extmark transaction; parse errors leave old identities intact.
      pcall(adapter.clear, context.buf)
      state.tracking, state.closed, state.positions = nil, nil, nil
      error(marks, 0)
    end
    state.tracking = entry.available
        and {
          tick = context.tick,
          filetype = context.filetype,
          lang = context.lang,
          marks = marks,
        }
      or nil
    state.positions = {}
    state.positions_tick = context.tick
    for index, mark in ipairs(marks) do
      state.positions[index] = { id = mark.id, header = mark.header, new = mark.new, line = plan.marks[index].line }
    end
  end

  ---@param context StableFoldsContext
  ---@param state StableFoldsBuffer
  ---@param owner integer
  ---@return StableFoldsSnapshot?
  local function collect(context, state, owner)
    local raw = adapter.collect(context.buf, context.lang, options.include_injections)
    local count = adapter.line_count(context.buf)
    local normalized = ranges.normalize(raw or {}, count)
    local headers = #normalized > 0 and adapter.headers(context.buf, normalized) or {}
    local current = adapter.context(context.win)
    if
      not active
      or generation ~= owner
      or buffers[context.buf] ~= state
      or not current
      or current.buf ~= context.buf
      or current.buftype ~= context.buftype
      or not cache.matches(cache.signature(context), current)
    then
      return nil
    end
    return {
      tick = context.tick,
      filetype = context.filetype,
      lang = context.lang,
      line_count = count,
      headers = headers,
      ranges = normalized,
      available = raw ~= nil,
    }
  end

  ---@param context StableFoldsContext
  ---@param state StableFoldsBuffer
  ---@return StableFoldsSnapshot?
  local function snapshot(context, state)
    if state.pending_snapshot then
      if state.pending_snapshot.filetype == context.filetype and state.pending_snapshot.lang == context.lang then
        return state.pending_snapshot
      end
      state.pending_snapshot = nil
    end
    if not adapter.ready(context.buf, context.tick) then
      -- Undo can evaluate folding after changing the text but before on_bytes
      -- invalidates Tree-sitter. Never commit those still-old tree coordinates.
      return state.snapshot
    end
    if cache.matches(state.snapshot, context) then
      return state.snapshot
    end
    if cache.matches(state.failure, context) then
      return nil
    end
    state.snapshot, state.failure = nil, nil
    forget_views(context.buf)
    local owner = generation
    local ok, result = pcall(function()
      local entry = collect(context, state, owner)
      if entry then
        reconcile(entry, context, state)
      end
      return entry
    end)
    if not ok then
      if generation ~= owner or buffers[context.buf] ~= state then
        return nil
      end
      state.failure = cache.signature(context)
      report(result, context)
      return nil
    end
    state.snapshot = result
    return result
  end

  ---@param context StableFoldsContext
  ---@return StableFoldsView?
  local function view(context)
    local owner = generation
    local allowed = context.buftype == "" and options.filter(context.buf)
    if not active or generation ~= owner then
      return nil
    end
    if not allowed then
      if buffers[context.buf] then
        clear(context.buf)
      end
      return nil
    end
    local state = buffers[context.buf]
    if not state then
      state = suspended[context.buf] or {}
      suspended[context.buf] = nil
      -- An unloaded buffer gets a fresh listener after FileType at BufReadPost;
      -- that listener does not receive the reload notification already in flight.
      state.reloading = nil
      buffers[context.buf] = state
    end
    if cache.matches(state.limited, context) then
      return nil
    end
    if
      (options.max_lines > 0 or options.max_bytes > 0)
      and not cache.matches(state.snapshot, context)
      and not cache.matches(state.failure, context)
    then
      if not config.within_limits(adapter.size(context.buf), options) then
        clear(context.buf)
        buffers[context.buf] = { limited = cache.signature(context) }
        return nil
      end
    end
    state.limited = nil
    if not state.cancel then
      state.cancel = adapter.watch(context.buf, function(edit)
        state.positions, evaluation = nil, nil
        before_change(context.buf, state, edit)
      end, function()
        if active and buffers[context.buf] == state then
          state.reloading, state.snapshot, state.failure, state.positions = nil, nil, nil, nil
          state.pending_snapshot = nil
          forget_views(context.buf)
          refresh(context.buf, false)
        end
      end)
    end
    local entry = snapshot(context, state)
    if not entry then
      return nil
    end
    local result = cache.view(entry, context, views)
    views[context.win] = result
    return result
  end

  ---@param line? integer
  ---@return string
  function controller.expr(line)
    if not active or evaluating or (line ~= nil and (not config.integer(line) or line == 0)) then
      return "0"
    end
    ---@type StableFoldsContext?
    local context
    evaluating = true
    local ok, result = pcall(function()
      local cached = evaluation
      if cached and views[cached.win] == cached.view and adapter.current_window() == cached.win then
        return cached.view.levels[line or adapter.line()] or "0"
      end
      context = adapter.context()
      if not context then
        return "0"
      end
      if capturing then
        local previous = views[context.win]
        return previous and previous.levels[line or context.line] or "0"
      end
      local current = view(context)
      return current and current.levels[line or context.line] or "0"
    end)
    evaluating = false
    if not ok then
      report(result, context)
      return "0"
    end
    return result
  end

  ---@param buf integer
  ---@param win integer
  ---@param owner integer
  ---@return nil
  local function refresh_window(buf, win, owner)
    local context = adapter.context(win)
    if not context or context.buf ~= buf then
      return
    end
    -- Commit a full snapshot before native folding evaluates the expression.
    local current = view(context)
    if not active or generation ~= owner then
      return
    end
    local state = buffers[buf]
    if state and state.reloading then
      -- BufReadPost can run before FileType and before changedtick advances.
      -- Keep the captured flags until the native on_reload notification.
      return
    end
    local last = applied[win]
    if
      last
      and last.view == current
      and cache.matches(last, context)
      and last.minlines == context.minlines
      and last.nestmax == context.nestmax
      and not (state and state.closed and state.closed[win] and next(state.closed[win]))
    then
      return
    end
    local starts = state and positions(buf, state, context.tick) or {}
    local open = {}
    if current and state then
      state.closed = state.closed or {}
      local pending = state.closed[win] or {}
      for _, mark in ipairs(starts) do
        if mark.new and mark.line and (current.levels[mark.line] or ""):sub(1, 1) == ">" then
          if options.new_folds == "open" then
            open[#open + 1] = mark.line
            pending[mark.id] = false
          else
            local depth = assert(tonumber(current.levels[mark.line]:sub(2)))
            pending[mark.id] = depth > context.foldlevel
          end
        end
      end
      state.closed[win] = pending
    end
    with_view(win, current, function()
      adapter.recompute(win)
      if not active or generation ~= owner then
        return false
      end
      adapter.open(win, open)
      if not active or generation ~= owner then
        return false
      end
      if current and state then
        local pending = state.closed and state.closed[win]
        adapter.restore(win, tracking.restore(starts, pending, current.levels))
        if state.closed then
          state.closed[win] = nil
        end
      end
      return true
    end)
    if not active or generation ~= owner then
      return
    end
    applied[win] = {
      buf = buf,
      tick = context.tick,
      filetype = context.filetype,
      lang = context.lang,
      minlines = context.minlines,
      nestmax = context.nestmax,
      view = current,
    }
  end

  ---@param buf integer
  ---@param force boolean
  ---@return nil
  local function refresh_once(buf, force)
    local owner = generation
    local ok, err = pcall(function()
      evaluation = nil
      local state = buffers[buf]
      if force and state then
        before_change(buf, state)
        state.positions = nil
        state.snapshot, state.failure, state.limited, state.pending_snapshot = nil, nil, nil, nil
        forget_views(buf)
      end
      for _, win in ipairs(adapter.windows(buf)) do
        if not active or generation ~= owner then
          return
        end
        local success, problem = pcall(refresh_window, buf, win, owner)
        if not success then
          report(problem)
        end
      end
      local current = buffers[buf]
      if current and current.tracking then
        for _, mark in ipairs(current.tracking.marks) do
          mark.new = false
        end
        for _, mark in ipairs(current.positions or {}) do
          mark.new = false
        end
      end
    end)
    if not ok then
      report(err)
    end
  end

  ---@param buf integer
  ---@param force boolean
  ---@return nil
  refresh = function(buf, force)
    if not active then
      return
    end
    local ok, key = pcall(function()
      local win = adapter.windows(buf)[1]
      local context = win and adapter.context(win)
      return tostring(context and context.tick)
        .. ":"
        .. tostring(context and context.filetype)
        .. ":"
        .. tostring(context and context.lang)
        .. ":"
        .. tostring(force)
    end)
    if not ok then
      report(key)
      return
    end
    if not refreshing then
      requested = {}
    end
    requested[buf] = requested[buf] or {}
    if requested[buf][key] then
      return
    end
    requested[buf][key] = true
    pending[buf] = force or pending[buf] or false
    if refreshing then
      return
    end
    refreshing = true
    local owner = generation
    while active and generation == owner do
      local next_buf, next_force = next(pending)
      if next_buf == nil then
        break
      end
      pending[next_buf] = nil
      refresh_once(next_buf, next_force == true)
    end
    refreshing = false
    if generation == owner then
      pending, requested = {}, {}
    elseif active then
      local next_buf, next_force = next(pending)
      if next_buf ~= nil then
        refresh(next_buf, next_force == true)
      end
    end
  end

  ---@param buf? integer
  ---@return nil
  function controller.refresh(buf)
    local ok, resolved = pcall(adapter.buffer, buf)
    if ok and resolved then
      adapter.settled(resolved)
      refresh(resolved, true)
    elseif not ok then
      report(resolved)
    end
  end

  ---@param buf integer
  ---@return nil
  local function entered(buf)
    local state = buffers[buf]
    local retry = state ~= nil and (state.failure ~= nil or (state.snapshot ~= nil and not state.snapshot.available))
    refresh(buf, retry)
  end

  ---@param win? integer
  ---@return nil
  function controller.attach(win)
    if not active then
      return
    end
    local ok, attached = pcall(adapter.attach, win)
    if not ok then
      report(attached)
    elseif attached then
      local success, context = pcall(adapter.context, attached)
      if success and context then
        entered(context.buf)
      elseif not success then
        report(context)
      end
    end
  end

  ---@return nil
  function controller.teardown()
    generation = generation + 1
    active = false
    pending, requested = {}, {}
    for buf in pairs(buffers) do
      clear(buf)
    end
    views, applied, errors, suspended, evaluation = {}, {}, {}, {}, nil
    local ok, err = pcall(adapter.uninstall)
    if not ok then
      report(err)
    end
  end

  ---@param opts? StableFoldsOptions
  ---@return nil
  function controller.setup(opts)
    local normalized, messages = config.normalize(opts)
    local affected = {}
    for buf in pairs(buffers) do
      affected[buf] = true
    end
    local listed, visible = pcall(adapter.buffers)
    if listed then
      for _, buf in ipairs(visible) do
        affected[buf] = true
      end
    end
    controller.teardown()
    options, active = normalized, true
    for _, message in ipairs(messages) do
      if options.notify_errors then
        pcall(adapter.notify, message)
      end
    end
    local owner = generation
    ---@return boolean
    local function installed()
      return active and generation == owner
    end
    local ok, err = pcall(adapter.install, {
      unloaded = function(buf)
        if not installed() then
          return
        end
        local state = buffers[buf]
        if state then
          before_change(buf, state)
          if state.tracking then
            state.tracking.positions = adapter.positions(buf, state.tracking.marks)
          end
        end
        clear(buf)
        if state and state.tracking then
          -- :edit! unloads before BufReadPre. Keep only identities and flags;
          -- native watchers, extmarks and text snapshots are released now.
          suspended[buf] = { tracking = state.tracking, closed = state.closed, reloading = true }
        end
      end,
      reading = function(buf)
        local state = buffers[buf] or suspended[buf]
        if installed() and state then
          before_change(buf, state)
          state.reloading = true
        end
      end,
      changed = function(buf)
        if installed() then
          evaluation = nil
          if buffers[buf] then
            buffers[buf].pending_snapshot = nil
          end
          refresh(buf, false)
        end
      end,
      entered = function(buf)
        if installed() then
          entered(buf)
        end
      end,
      deleted = function(buf)
        if installed() then
          clear(buf)
        end
      end,
      reset = function(buf)
        if not installed() then
          return
        end
        if suspended[buf] or (buffers[buf] and buffers[buf].reloading) then
          -- Reload filetype plugins can temporarily replace foldexpr. Reconcile
          -- the language once the adapter restores owned windows at BufReadPost.
          return
        end
        local state = buffers[buf] or suspended[buf]
        local previous = state and (state.tracking or state.snapshot)
        local same_language = false
        for _, win in ipairs(adapter.windows(buf)) do
          local context = adapter.context(win)
          if context and previous then
            same_language = previous.filetype == context.filetype and previous.lang == context.lang
            break
          end
        end
        -- FileType also runs on :edit!; retain identities and the pre-read flags
        -- when the language did not actually change.
        if not same_language then
          clear(buf)
        elseif state then
          state.snapshot, state.failure = nil, nil
          forget_views(buf)
        end
        refresh(buf, false)
      end,
      closed = function(win)
        if installed() then
          views[win], applied[win] = nil, nil
          for _, state in pairs(buffers) do
            if state.closed then
              state.closed[win] = nil
            end
          end
          for _, state in pairs(suspended) do
            if state.closed then
              state.closed[win] = nil
            end
          end
        end
      end,
      updated = function()
        if not installed() then
          return
        end
        for buf in pairs(buffers) do
          refresh(buf, true)
        end
      end,
    })
    if not ok then
      controller.teardown()
      report(err)
    else
      for buf in pairs(affected) do
        if installed() then
          refresh(buf, false)
        end
      end
    end
  end

  return controller
end

return M
