local config_rules = require("tab_buffers.core.config")
local core = require("tab_buffers.core.model")
local validation = require("tab_buffers.core.validation")
local lists = require("tab_buffers.core.lists")
local context_rules = require("tab_buffers.core.context")
local selection = require("tab_buffers.core.selection")
local closing = require("tab_buffers.core.closing")
local reconcile_rules = require("tab_buffers.core.reconcile")
local integer, options = validation.integer, validation.options
local result = closing.result
local M = {}

---@return TabBuffers
---@param adapter TabBuffersAdapter
function M.new(adapter)
  local config = config_rules.behavior()
  ---@type table<integer, integer[]>
  local history = {}
  ---@type TabBuffersObservation?
  local phase
  ---@return nil
  local function invalidate()
    phase = nil
  end
  ---@param buf integer
  ---@return TabBuffersBufferFacts
  local function buffer_facts(buf)
    if not phase then
      return adapter.buffer(buf)
    end
    if not phase.buffers[buf] then
      phase.buffers[buf] = adapter.buffer(buf)
    end
    return phase.buffers[buf]
  end
  ---@param tab integer
  ---@return TabBuffersTabFacts
  local function tab_facts(tab)
    if not phase then
      return adapter.tab(tab)
    end
    if not phase.tabs[tab] then
      phase.tabs[tab] = adapter.tab(tab)
    end
    return phase.tabs[tab]
  end
  ---@param win integer
  ---@return TabBuffersWindowFacts
  local function window_facts(win)
    if not phase then
      return adapter.window(win)
    end
    if not phase.windows[win] then
      phase.windows[win] = adapter.window(win)
    end
    return phase.windows[win]
  end
  ---@param tab integer
  ---@return integer[]
  local function tab_windows(tab)
    if not phase then
      return adapter.tab_windows(tab)
    end
    if not phase.tab_windows[tab] then
      phase.tab_windows[tab] = adapter.tab_windows(tab)
    end
    return phase.tab_windows[tab]
  end
  ---@param buf integer
  ---@return boolean
  local function basic(buf)
    local facts = buffer_facts(buf)
    if not context_rules.basic(facts) then
      return false
    end
    if config.buffer_filter then
      local accepted = config.buffer_filter(buf, lists.copy(facts))
      assert(type(accepted) == "boolean", "buffer_filter must return a boolean")
      return accepted
    end
    return true
  end
  ---@param tab integer
  ---@return boolean
  local function managed(tab)
    local facts = tab_facts(tab)
    if not context_rules.managed(facts) then
      return false
    end
    if config.tab_filter then
      local accepted = config.tab_filter(tab, lists.copy(facts))
      assert(type(accepted) == "boolean", "tab_filter must return a boolean")
      return accepted
    end
    return true
  end
  ---@param win integer
  ---@return boolean
  local function working(win)
    return context_rules.working(window_facts(win)) and managed(adapter.window_tab(win))
  end
  ---@param buf integer
  ---@return integer[]
  local function displaying(buf)
    if not phase then
      return adapter.displaying(buf)
    end
    if not phase.displaying then
      local displayed = {}
      for _, tab in ipairs(adapter.tabs()) do
        for _, win in ipairs(tab_windows(tab)) do
          local shown = adapter.window_buffer(win)
          displayed[shown] = displayed[shown] or {}
          displayed[shown][#displayed[shown] + 1] = win
        end
      end
      phase.displaying = displayed
    end
    return phase.displaying[buf] or {}
  end
  ---@return integer?
  local function managed_destination()
    return reconcile_rules.destination(adapter.current_tab(), adapter.tabs(), managed)
  end
  local public = {}
  ---@cast public TabBuffers
  local model = core.new()
  ---@type TabBuffersAction?
  local cancel
  local initialized = false
  local generation, busy = 0, 0
  local queued, exiting = false, false
  local dirty = true
  ---@type table<integer, boolean>
  local text_buffers = {}
  ---@type table<integer, boolean>
  local changed = {}
  ---@type table<integer, TabBuffersCloseRequest>
  local requests = {}
  ---@type table<integer, integer[]>
  local snapshots = {}
  ---@type table<integer, string>
  local recovery_errors = {}
  ---@type fun(): boolean
  local reconcile
  ---@type TabBuffersAction
  local schedule
  ---@type fun(tab: integer, force?: boolean, report?: TabBuffersResult): TabBuffersResult
  local close_tab

  ---@return nil
  local function started()
    assert(initialized, "tab_buffers.setup() must be called first")
  end

  ---@param tab integer
  ---@return nil
  local function mark(tab)
    changed[tab] = true
  end

  ---@param tab integer
  ---@param buf integer
  ---@param index? integer
  ---@return boolean
  local function attach(tab, buf, index)
    if not managed(tab) then
      return false
    end
    if model:attach(tab, buf, index) then
      mark(tab)
      return true
    end
    return false
  end

  ---@param buf integer
  ---@return nil
  local function forget(buf)
    for _, tab in ipairs(model:forget_buffer(buf)) do
      mark(tab)
    end
  end

  ---@param buf integer
  ---@return boolean
  local function eligible(buf)
    return basic(buf) and context_rules.eligible(buffer_facts(buf), #model:owners(buf) > 0)
  end

  ---@return nil
  local function scan_visible()
    for _, tab in ipairs(model:tabs()) do
      if adapter.tab_valid(tab) and not managed(tab) then
        model:remove_tab(tab)
        mark(tab)
      end
    end
    for _, tab in ipairs(adapter.tabs()) do
      if managed(tab) and model:ensure_tab(tab) then
        mark(tab)
      end
      for _, win in ipairs(tab_windows(tab)) do
        local buf = adapter.window_buffer(win)
        if working(win) and eligible(buf) then
          attach(tab, buf)
        end
      end
    end
  end

  ---@param report TabBuffersResult
  ---@param prefix string
  ---@return nil
  local function notify_failures(report, prefix)
    if #report.failed == 0 and not report.error then
      return
    end
    local messages = {}
    for _, failure in ipairs(report.failed) do
      messages[#messages + 1] = tostring(failure.buf) .. ": " .. failure.message
    end
    if report.error then
      messages[#messages + 1] = report.error
    end
    adapter.notify("tab-buffers: " .. prefix .. "\n" .. table.concat(messages, "\n"))
  end

  ---@return boolean
  local function clean_closed()
    ---@type TabBuffersRemoved[]
    local removed = {}
    ---@type table<integer, TabBuffersOrphan>
    local candidates = {}
    ---@type integer[]
    local order = {}
    local tabs = reconcile_rules.candidates(model:tabs(), snapshots)
    for _, tab in ipairs(tabs) do
      if not adapter.tab_valid(tab) then
        local previous = model:remove_tab(tab)
        local request = requests[tab]
        local report = request and request.report or result()
        report.tab_closed = true
        local buffers = snapshots[tab] or previous.buffers
        removed[#removed + 1] = { tab = tab, buffers = buffers, report = report, own = request }
        mark(tab)
        for _, buf in ipairs(buffers) do
          if not candidates[buf] then
            candidates[buf] = { force = request ~= nil and request.force == true }
            order[#order + 1] = buf
          else
            candidates[buf].force = candidates[buf].force and request ~= nil and request.force == true
          end
        end
        snapshots[tab] = buffers
      end
    end
    -- Remove all closed owners before deciding which buffers are exclusive.
    for _, buf in ipairs(order) do
      local candidate = candidates[buf]
      candidate.error = recovery_errors[buf]
      if basic(buf) and #model:owners(buf) == 0 then
        local reason
        if #displaying(buf) > 0 then
          reason = "buffer is still displayed in an unmanaged window"
        elseif buffer_facts(buf).modified and not candidate.force then
          reason = "unsaved changes"
        else
          invalidate()
          local ok, err = pcall(adapter.delete_buffer, buf, { force = candidate.force })
          if not ok then
            reason = tostring(err)
          end
        end
        if reason and basic(buf) then
          recovery_errors[buf] = reason
          local destination = managed_destination()
          if not destination then
            invalidate()
            adapter.new_tab()
            destination = adapter.current_tab()
          end
          attach(destination, buf)
          assert(model:contains(destination, buf), "recovery destination is no longer managed")
          candidate.error = reason
        end
      end
    end
    local external = result()
    local reported = {}
    for _, item in ipairs(removed) do
      for _, buf in ipairs(item.buffers) do
        local candidate = candidates[buf]
        if candidate and candidate.error then
          item.report.failed[#item.report.failed + 1] = { buf = buf, message = candidate.error }
          if not item.own and not reported[buf] then
            external.failed[#external.failed + 1] = { buf = buf, message = candidate.error }
            reported[buf] = true
          end
        else
          item.report.closed[#item.report.closed + 1] = buf
        end
      end
    end
    for _, item in ipairs(removed) do
      requests[item.tab], snapshots[item.tab] = nil, nil
    end
    for _, buf in ipairs(order) do
      recovery_errors[buf] = nil
    end
    notify_failures(external, "Buffers from closed tabs were preserved in the current tab")
    return #removed > 0
  end

  reconcile = function()
    if not initialized or busy > 0 or exiting or adapter.exiting() then
      return false
    end
    busy = busy + 1
    phase = { buffers = {}, tabs = {}, windows = {}, tab_windows = {} }
    local ok, err = pcall(function()
      scan_visible()
      local effects = clean_closed()
      for _, tab in ipairs(model:tabs()) do
        for _, buf in ipairs(model:buffers(tab)) do
          if not basic(buf) then
            forget(buf)
          end
        end
      end
      -- Only closed-tab cleanup can mutate the editor during this observation.
      if effects then
        invalidate()
        phase = { buffers = {}, tabs = {}, windows = {}, tab_windows = {} }
        scan_visible()
      end
      for tab, previous in pairs(history) do
        if not managed(tab) then
          history[tab] = nil
        else
          local retained = {}
          for _, buf in ipairs(previous) do
            if model:contains(tab, buf) then
              retained[#retained + 1] = buf
            end
          end
          history[tab] = retained
        end
      end
      local tab, win = adapter.current_tab(), adapter.current_window()
      if working(win) then
        local buf = adapter.window_buffer(win)
        if model:contains(tab, buf) then
          local recent = history[tab] or {}
          local index = lists.index_of(recent, buf)
          if index then
            table.remove(recent, index)
          end
          table.insert(recent, 1, buf)
          history[tab] = recent
        end
      end
    end)
    invalidate()
    dirty, text_buffers = false, {}
    local restored, restore_error = pcall(adapter.restore_closing)
    busy = busy - 1
    if not ok then
      dirty = true
      error(err, 0)
    end
    if not restored then
      dirty = true
      error(restore_error, 0)
    end
    if dirty then
      schedule()
    end
    return true
  end

  schedule = function()
    if not initialized or queued or busy > 0 or exiting then
      return
    end
    queued = true
    local ticket = generation
    adapter.schedule(function()
      if ticket ~= generation or not initialized then
        return
      end
      queued = false
      if busy > 0 or exiting then
        return
      end
      if dirty then
        reconcile()
      else
        local pending = text_buffers
        dirty, text_buffers = true, {}
        for buf in pairs(pending) do
          if not basic(buf) then
            forget(buf)
          elseif #model:owners(buf) == 0 and eligible(buf) then
            for _, win in ipairs(displaying(buf)) do
              if working(win) then
                attach(adapter.window_tab(win), buf)
              end
            end
          end
        end
        dirty = false
      end
      local tabs = {}
      for tab in pairs(changed) do
        tabs[#tabs + 1] = tab
      end
      changed = {}
      table.sort(tabs)
      if #tabs > 0 then
        adapter.publish(tabs)
      end
    end)
  end

  ---@generic T
  ---@param fn fun(): T, string?
  ---@param effects? boolean
  ---@return T, string?
  local function run(fn, effects)
    started()
    assert(busy == 0, "tab-buffers operation is already in progress")
    reconcile()
    busy = busy + 1
    local ok, value, err = pcall(fn)
    busy = busy - 1
    local observed, problem = true, nil
    if effects ~= false or dirty then
      observed, problem = pcall(reconcile)
    end
    schedule()
    if not ok then
      error(observed and value or tostring(value) .. "\nReconciliation: " .. tostring(problem), 0)
    end
    if not observed then
      local message = tostring(problem)
      if closing.record_error(value, message) then
        return value, err
      end
      return value, err or message
    end
    return value, err
  end

  ---@param opts TabBuffersOptions
  ---@return TabBuffersContext?, string?
  local function context(opts)
    local tab = opts.tab or adapter.current_tab()
    if not adapter.tab_valid(tab) then
      return nil, "invalid tab handle"
    end
    local win = opts.win or adapter.tab_window(tab)
    if not adapter.window_valid(win) or adapter.window_tab(win) ~= tab then
      return nil, "invalid window handle for this tab"
    end
    local buf = opts.buf or adapter.window_buffer(win)
    if not adapter.buffer_valid(buf) then
      return nil, "invalid buffer handle"
    end
    return {
      tab = tab,
      win = win,
      buf = buf,
      unmanaged = not managed(tab),
      implicit_special = not managed(tab)
        or not (opts.tab or opts.buf or opts.win) and not (working(win) and basic(buf)),
    }
  end

  function public.setup(opts)
    local candidate = opts ~= nil and config_rules.behavior(opts) or config
    assert(busy == 0, "tab-buffers operation is already in progress")
    if initialized then
      local previous = config
      ---@type table<integer, integer[]>
      local memberships = {}
      for _, tab in ipairs(model:tabs()) do
        memberships[tab] = model:buffers(tab)
      end
      local previous_history = lists.copy(history)
      config = candidate
      local ok, value = pcall(public.refresh)
      if not ok then
        config, history = previous, previous_history
        model = core.new()
        for tab, members in pairs(memberships) do
          model:ensure_tab(tab)
          for _, buf in ipairs(members) do
            if adapter.buffer_valid(buf) then
              model:attach(tab, buf)
            end
          end
        end
        local restored, err = pcall(reconcile)
        schedule()
        error(restored and value or tostring(value) .. "\nReconciliation: " .. tostring(err), 0)
      end
      return value
    end
    config = candidate
    generation = generation + 1
    dirty, text_buffers = true, {}
    model = core.new()
    initialized = true
    exiting = false
    local ok, err = pcall(function()
      cancel = adapter.install({
        changed = function()
          dirty = true
          schedule()
        end,
        buffer = function(buf)
          if config.buffer_filter or config.tab_filter then
            dirty = true
          else
            text_buffers[buf] = true
          end
          schedule()
        end,
        text = function(buf)
          if config.buffer_filter or config.tab_filter then
            dirty = true
          else
            local facts = buffer_facts(buf)
            if context_rules.basic(facts) and #model:owners(buf) > 0 then
              return
            end
            text_buffers[buf] = true
          end
          schedule()
        end,
        closing = function()
          if initialized and not exiting then
            local tab = adapter.current_tab()
            if not managed(tab) then
              model:remove_tab(tab)
              mark(tab)
            end
            local buffers, seen = model:buffers(tab), {}
            for _, buf in ipairs(buffers) do
              seen[buf] = true
            end
            for _, win in ipairs(tab_windows(tab)) do
              local buf = adapter.window_buffer(win)
              if working(win) and eligible(buf) and not seen[buf] then
                buffers[#buffers + 1] = buf
                seen[buf] = true
              end
            end
            snapshots[tab] = buffers
            if not requests[tab] then
              -- TabClosedPre permits option changes, but forbids window changes.
              -- Preserve text/jobs until deferred cleanup can decide ownership.
              local protected_buffers = {}
              for _, win in ipairs(tab_windows(tab)) do
                protected_buffers[#protected_buffers + 1] = adapter.window_buffer(win)
              end
              adapter.guard_closing(protected_buffers)
            end
          end
        end,
        exiting = function()
          exiting = true
        end,
      })
      reconcile()
      phase = { buffers = {}, tabs = {}, windows = {}, tab_windows = {} }
      local buffers = adapter.buffers()
      table.sort(buffers)
      for _, buf in ipairs(buffers) do
        if config.bootstrap_hidden_buffers and eligible(buf) and #model:owners(buf) == 0 and #displaying(buf) == 0 then
          local destination = managed_destination()
          if destination then
            attach(destination, buf)
          end
        end
      end
      invalidate()
      schedule()
    end)
    invalidate()
    if not ok then
      generation = generation + 1
      if cancel then
        cancel()
      end
      adapter.restore_closing()
      model, cancel, initialized = core.new(), nil, false
      changed, requests, snapshots, recovery_errors, history = {}, {}, {}, {}, {}
      queued, exiting = false, false
      dirty, text_buffers = true, {}
      config = config_rules.behavior()
      error(err, 0)
    end
    return true
  end

  function public.teardown()
    assert(busy == 0, "tab-buffers operation is already in progress")
    if not initialized then
      return false
    end
    generation = generation + 1
    adapter.restore_closing()
    assert(cancel)()
    model, cancel, initialized = core.new(), nil, false
    changed, requests, snapshots, recovery_errors, history = {}, {}, {}, {}, {}
    queued, exiting = false, false
    dirty, text_buffers = true, {}
    config = config_rules.behavior()
    return true
  end

  function public.refresh()
    started()
    assert(busy == 0, "tab-buffers operation is already in progress")
    reconcile()
    schedule()
    return true
  end

  function public.tabs()
    started()
    return adapter.tabs()
  end

  function public.buffers(tab)
    started()
    tab = tab or adapter.current_tab()
    integer(tab, "tab", true)
    return model:buffers(tab)
  end

  function public.owners(buf)
    started()
    buf = buf or adapter.current_buffer()
    integer(buf, "buf", true)
    return model:owners(buf)
  end

  function public.contains(buf, tab)
    started()
    buf, tab = buf or adapter.current_buffer(), tab or adapter.current_tab()
    integer(buf, "buf", true)
    integer(tab, "tab", true)
    return model:contains(tab, buf)
  end

  function public.add(buf, opts)
    opts = lists.merge(options(opts), buf ~= nil and { buf = buf } or {})
    options(opts)
    return run(function()
      local ctx, err = context(opts)
      if not ctx then
        return false, err
      end
      if ctx.implicit_special or not eligible(ctx.buf) then
        return false
      end
      return attach(ctx.tab, ctx.buf, opts.index)
    end, false)
  end

  ---@param apply fun(ctx: TabBuffersContext): boolean
  ---@param opts? TabBuffersOptions
  ---@param effects? boolean
  ---@return boolean, string?
  local function order(apply, opts, effects)
    opts = options(opts)
    return run(function()
      local ctx, err = context(opts)
      if not ctx then
        return false, err
      end
      if ctx.implicit_special then
        return false
      end
      local did_change = apply(ctx)
      if did_change then
        mark(ctx.tab)
      end
      return did_change
    end, effects == true)
  end

  function public.move(offset, opts)
    integer(offset, "offset")
    return order(function(ctx)
      return model:move(ctx.tab, ctx.buf, offset)
    end, opts)
  end

  function public.move_to(index, opts)
    integer(index, "index")
    return order(function(ctx)
      return model:move_to(ctx.tab, ctx.buf, index)
    end, opts)
  end

  function public.reorder(buffers, opts)
    buffers = validation.buffer_list(buffers)
    return order(function(ctx)
      return model:reorder(ctx.tab, buffers)
    end, opts)
  end

  function public.sort(by, opts)
    ---@type TabBuffersComparator
    local comparator
    if type(by) == "function" then
      comparator = by
    elseif by == "id" then
      comparator = function(a, b)
        return a < b
      end
    elseif by == "name" or by == "path" then
      ---@type table<integer, string>
      local cached_names = {}
      ---@param buf integer
      ---@return string
      local function name(buf)
        if not cached_names[buf] then
          local path = adapter.buffer_name(buf)
          cached_names[buf] = by == "name" and (path:match("[^/]+$") or path) or path
        end
        return cached_names[buf]
      end
      comparator = function(a, b)
        return name(a) < name(b)
      end
    else
      error("sort expects id, name, path or a comparator")
    end
    return order(function(ctx)
      return model:sort(ctx.tab, comparator)
    end, opts, type(by) == "function")
  end

  function public.open(buf, opts)
    integer(buf, "buf", true)
    opts = options(opts)
    assert(opts.split == nil or opts.split == "horizontal" or opts.split == "vertical", "invalid split direction")
    return run(function()
      local ctx, err = context(lists.merge(opts, { buf = buf }))
      if not ctx then
        return nil, err
      end
      if ctx.unmanaged then
        return nil
      end
      if not model:contains(ctx.tab, buf) then
        return nil, "buffer does not belong to this tab"
      end
      return adapter.open(ctx, buf, opts)
    end)
  end

  function public.switch(offset, opts)
    integer(offset, "offset")
    opts = options(opts)
    return run(function()
      local ctx, err = context(opts)
      if not ctx then
        return nil, err
      end
      if ctx.implicit_special or not working(ctx.win) or not basic(adapter.window_buffer(ctx.win)) then
        return nil
      end
      local wrap = opts.wrap
      if wrap == nil then
        wrap = config.wrap
      end
      local buf = model:neighbor(ctx.tab, ctx.buf, offset, wrap)
      if not buf then
        return nil
      end
      return adapter.switch(ctx, buf)
    end)
  end

  function public.next(opts)
    return public.switch(1, opts)
  end
  function public.previous(opts)
    return public.switch(-1, opts)
  end

  ---@param tab integer
  ---@param buf integer
  ---@param force? boolean
  ---@return string?
  local function blocker(tab, buf, force)
    local foreign = false
    for _, win in ipairs(displaying(buf)) do
      if adapter.window_tab(win) ~= tab or not working(win) then
        foreign = true
        break
      end
    end
    return closing.blocker(#model:owners(buf), buffer_facts(buf).modified, force, foreign)
  end

  ---@param tab integer
  ---@param buf integer
  ---@param excluded table<integer, boolean>
  ---@return integer?
  local function replacement(tab, buf, excluded)
    return closing.replacement(model:buffers(tab), buf, excluded, eligible, config.replacement, history[tab])
  end

  ---@param tab integer
  ---@param buf integer
  ---@param excluded table<integer, boolean>
  ---@param commit TabBuffersAction
  ---@return boolean, string?
  local function replace_windows(tab, buf, excluded, commit)
    return adapter.replace(tab, buf, replacement(tab, buf, excluded), scan_visible, commit)
  end

  close_tab = function(tab, force, report)
    report = report or result()
    if not adapter.tab_valid(tab) then
      report.error = "invalid tab handle"
      return report
    end
    if #adapter.tabs() == 1 then
      report.error = "cannot close the last tab"
      return report
    end
    for _, buf in ipairs(model:buffers(tab)) do
      if basic(buf) and #model:owners(buf) == 1 and buffer_facts(buf).modified and not force then
        report.failed[#report.failed + 1] = { buf = buf, message = "unsaved changes" }
      end
    end
    if #report.failed > 0 then
      report.error = "tab contains modified exclusive buffers"
      return report
    end
    local buffers = model:buffers(tab)
    -- Special buffers/jobs are excluded from deletion but must also survive hiding.
    for _, win in ipairs(tab_windows(tab)) do
      buffers[#buffers + 1] = adapter.window_buffer(win)
    end
    requests[tab] = { force = force == true, report = report }
    local ok, err = adapter.protected(buffers, function()
      adapter.close_tab(tab, force == true)
    end)
    if adapter.tab_valid(tab) then
      requests[tab], snapshots[tab] = nil, nil
      report.error = ok and "tab did not close" or tostring(err)
    elseif not ok then
      -- TabClosedPre errors may still close the tab. Reconciliation must process it.
      report.error = tostring(err)
    end
    return report
  end

  ---@param tab integer
  ---@param report TabBuffersResult
  ---@return nil
  local function finish_empty(tab, report)
    if adapter.tab_valid(tab) and #model:buffers(tab) == 0 then
      if config.close_empty_tab and #adapter.tabs() > 1 then
        close_tab(tab, false, report)
      else
        local has_working = false
        for _, win in ipairs(tab_windows(tab)) do
          if working(win) and context_rules.basic(buffer_facts(adapter.window_buffer(win))) then
            has_working = true
            break
          end
        end
        if not has_working then
          local focus = adapter.current_window()
          local ok, err = pcall(adapter.new_working_window, tab)
          if adapter.window_valid(focus) then
            adapter.focus_window(focus)
          end
          if not ok then
            report.error = tostring(err)
          end
        end
      end
    end
  end

  ---@param mode? TabBuffersTargetMode
  ---@param opts? TabBuffersOptions
  ---@param selected? table<integer, boolean>
  ---@return TabBuffersResult
  local function close(mode, opts, selected)
    opts = options(opts)
    local report = run(function()
      local outcome = result()
      local ctx, err = context(opts)
      if not ctx then
        outcome.error = err
        return outcome
      end
      if ctx.unmanaged or ctx.implicit_special and not selected then
        return outcome
      end
      ---@type integer[]
      local targets
      if selected then
        targets = selection.selected(model:buffers(ctx.tab), selected)
      else
        targets = model:targets(ctx.tab, assert(mode), ctx.buf)
      end
      if #targets == 0 then
        return outcome
      end
      local excluded = {}
      for _, buf in ipairs(targets) do
        if not blocker(ctx.tab, buf, opts.force) then
          excluded[buf] = true
        end
      end
      for _, buf in ipairs(targets) do
        if basic(buf) and model:contains(ctx.tab, buf) then
          local reason = blocker(ctx.tab, buf, opts.force)
          if not reason then
            local committed = false
            local ok, message = replace_windows(ctx.tab, buf, excluded, function()
              if not managed(ctx.tab) or not basic(buf) then
                error("source context is no longer managed")
              end
              if not model:contains(ctx.tab, buf) then
                return
              end
              if #model:owners(buf) == 1 then
                local current_reason = blocker(ctx.tab, buf, opts.force)
                if current_reason then
                  error(current_reason)
                end
                local deleted, failure = pcall(adapter.delete_buffer, buf, { force = opts.force == true })
                if not deleted then
                  if adapter.buffer_valid(buf) then
                    error(failure, 0)
                  end
                  -- Autocmd errors can be reported after deletion has committed.
                  outcome.error = tostring(failure)
                end
                forget(buf)
              else
                model:detach(ctx.tab, buf)
                mark(ctx.tab)
              end
              committed = true
            end)
            if not ok and committed then
              closing.record_error(outcome, assert(message))
            elseif not ok then
              reason = message
            end
          end
          if reason then
            excluded[buf] = nil
            outcome.failed[#outcome.failed + 1] = { buf = buf, message = reason }
          else
            outcome.closed[#outcome.closed + 1] = buf
          end
        end
      end
      finish_empty(ctx.tab, outcome)
      return outcome
    end)
    notify_failures(report, "Close operation reported errors")
    return report
  end

  function public.close(opts)
    return close("one", opts)
  end
  function public.close_many(buffers, opts)
    local selected = {}
    for _, buf in ipairs(validation.buffer_list(buffers)) do
      selected[buf] = true
    end
    return close(nil, opts, selected)
  end
  function public.close_all(opts)
    return close("all", opts)
  end
  function public.close_others(opts)
    return close("others", opts)
  end
  function public.close_left(opts)
    return close("left", opts)
  end
  function public.close_right(opts)
    return close("right", opts)
  end

  function public.close_tab(opts)
    opts = options(opts)
    local report = run(function()
      local ctx, err = context(opts)
      if not ctx then
        local outcome = result()
        outcome.error = err
        return outcome
      end
      if ctx.implicit_special then
        return result()
      end
      return close_tab(ctx.tab, opts.force)
    end)
    notify_failures(report, "Some buffers could not be closed")
    return report
  end

  function public.transfer(target_tab, opts)
    integer(target_tab, "target_tab", true)
    opts = options(opts)
    local report = result()
    local changed_membership, err = run(function()
      local ctx, message = context(opts)
      if not ctx then
        return false, message
      end
      if not adapter.tab_valid(target_tab) then
        return false, "invalid target tab handle"
      end
      if not managed(target_tab) then
        return false, "target tab is unmanaged"
      end
      if ctx.implicit_special or ctx.tab == target_tab or not model:contains(ctx.tab, ctx.buf) then
        return false
      end
      local committed = false
      local ok, failure = replace_windows(ctx.tab, ctx.buf, { [ctx.buf] = true }, function()
        if not adapter.tab_valid(target_tab) then
          error("target tab closed during the operation")
        end
        if not managed(target_tab) then
          error("target tab is unmanaged")
        end
        if not adapter.tab_valid(ctx.tab) then
          error("source tab closed during the operation")
        end
        model:transfer(ctx.tab, target_tab, ctx.buf, opts.index)
        mark(ctx.tab)
        mark(target_tab)
        committed = true
      end)
      if not ok and not committed then
        return false, failure
      end
      finish_empty(ctx.tab, report)
      return true, not ok and failure or nil
    end)
    notify_failures(report, "The source tab could not be closed")
    return changed_membership, err or report.error
  end

  return public
end

return M
