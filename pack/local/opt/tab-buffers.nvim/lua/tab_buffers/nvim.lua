local core = require("tab_buffers.core")
local api = vim.api
local M = {}
local instance_count = 0
local hidden_originals = {}

---@class TabBuffersOptions
---@field tab? integer Stable tabpage handle, never a tab number.
---@field buf? integer
---@field win? integer
---@field index? integer
---@field force? boolean
---@field wrap? boolean
---@field split? "horizontal"|"vertical" Only used by open().

---@class TabBuffersResult
---@field closed integer[] Memberships successfully closed.
---@field failed {buf: integer, message: string}[]
---@field tab_closed boolean
---@field error? string

---@class TabBuffers
---@field setup fun(): boolean
---@field teardown fun(): boolean
---@field refresh fun(): boolean
---@field tabs fun(): integer[]
---@field buffers fun(tab?: integer): integer[]
---@field owners fun(buf?: integer): integer[]
---@field contains fun(buf?: integer, tab?: integer): boolean
---@field add fun(buf?: integer, opts?: TabBuffersOptions): boolean, string?
---@field transfer fun(target_tab: integer, opts?: TabBuffersOptions): boolean, string?
---@field move fun(offset: integer, opts?: TabBuffersOptions): boolean, string?
---@field move_to fun(index: integer, opts?: TabBuffersOptions): boolean, string?
---@field reorder fun(buffers: integer[], opts?: TabBuffersOptions): boolean, string?
---@field sort fun(by: string|fun(a: integer, b: integer): boolean, opts?: TabBuffersOptions): boolean, string?
---@field switch fun(offset: integer, opts?: TabBuffersOptions): integer?, string?
---@field next fun(opts?: TabBuffersOptions): integer?, string?
---@field previous fun(opts?: TabBuffersOptions): integer?, string?
---@field open fun(buf: integer, opts?: TabBuffersOptions): integer?, string?
---@field close fun(opts?: TabBuffersOptions): TabBuffersResult
---@field close_all fun(opts?: TabBuffersOptions): TabBuffersResult
---@field close_others fun(opts?: TabBuffersOptions): TabBuffersResult
---@field close_left fun(opts?: TabBuffersOptions): TabBuffersResult
---@field close_right fun(opts?: TabBuffersOptions): TabBuffersResult
---@field close_tab fun(opts?: TabBuffersOptions): TabBuffersResult
---@field close_many fun(buffers: integer[], opts?: TabBuffersOptions): TabBuffersResult

local function integer(value, name, positive)
  assert(
    type(value) == "number" and value > -math.huge and value < math.huge and value == math.floor(value),
    name .. " must be a finite integer"
  )
  assert(not positive or value > 0, name .. " must be positive")
end

local function options(opts)
  assert(opts == nil or type(opts) == "table", "opts must be a table")
  opts = opts or {}
  for _, key in ipairs({ "tab", "buf", "win" }) do
    if opts[key] ~= nil then
      integer(opts[key], key, true)
    end
  end
  if opts.index ~= nil then
    integer(opts.index, "index")
  end
  for _, key in ipairs({ "force", "wrap" }) do
    assert(opts[key] == nil or type(opts[key]) == "boolean", key .. " must be a boolean")
  end
  return opts
end

local function result()
  return { closed = {}, failed = {}, tab_closed = false }
end

local function basic(buf)
  return api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and vim.bo[buf].buftype == ""
end

local function managed(tab)
  return api.nvim_tabpage_is_valid(tab) and vim.t[tab].tab_buffers_excluded ~= true
end

local function managed_destination()
  local current = api.nvim_get_current_tabpage()
  if managed(current) then
    return current
  end
  for _, tab in ipairs(api.nvim_list_tabpages()) do
    if managed(tab) then
      return tab
    end
  end
end

local function working(win)
  if not api.nvim_win_is_valid(win) then
    return false
  end
  local config = api.nvim_win_get_config(win)
  return managed(api.nvim_win_get_tabpage(win))
    and config.relative == ""
    and not config.external
    and not vim.wo[win].previewwindow
end

local function displaying(buf)
  local windows = {}
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(win) == buf then
      windows[#windows + 1] = win
    end
  end
  return windows
end

---Temporarily prevent hiding from unloading/wiping buffers or losing modifications.
---Restore options even when a third-party autocmd fails or deletes a buffer.
local function protected(buffers, fn)
  local saved, ancestors = {}, {}
  for _, buf in ipairs(buffers) do
    if api.nvim_buf_is_valid(buf) and saved[buf] == nil then
      saved[buf] = vim.bo[buf].bufhidden
      ancestors[buf] = hidden_originals[buf]
      hidden_originals[buf] = hidden_originals[buf] or { value = saved[buf] }
      vim.bo[buf].bufhidden = "hide"
    end
  end
  local ok, value, err = pcall(fn)
  for buf, original in pairs(saved) do
    hidden_originals[buf] = ancestors[buf]
    if api.nvim_buf_is_valid(buf) then
      local restored, message = pcall(function()
        vim.bo[buf].bufhidden = original
      end)
      if not restored and ok then
        ok, value = false, message
      end
    end
  end
  if not ok then
    return false, tostring(value)
  end
  return true, value, err
end

---@return TabBuffers
function M.new()
  instance_count = instance_count + 1
  local group_name = "TabBuffersNvim" .. instance_count
  local public = {}
  local model, group
  local generation, busy = 0, 0
  local queued, exiting = false, false
  local changed, requests, snapshots, closing_options = {}, {}, {}, {}
  local reconcile, schedule, close_tab

  local function started()
    assert(model, "tab_buffers.setup() must be called first")
  end

  local function mark(tab)
    changed[tab] = true
  end

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

  local function forget(buf)
    for _, tab in ipairs(model:forget_buffer(buf)) do
      mark(tab)
    end
  end

  local function eligible(buf)
    if not basic(buf) then
      return false
    end
    if #model:owners(buf) > 0 or api.nvim_buf_get_name(buf) ~= "" or vim.bo[buf].modified then
      return true
    end
    if api.nvim_buf_is_loaded(buf) then
      return api.nvim_buf_line_count(buf) > 1 or api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= ""
    end
    return false
  end

  local function scan_visible()
    for _, tab in ipairs(model:tabs()) do
      if api.nvim_tabpage_is_valid(tab) and not managed(tab) then
        model:remove_tab(tab)
        mark(tab)
      end
    end
    for _, tab in ipairs(api.nvim_list_tabpages()) do
      if managed(tab) and model:ensure_tab(tab) then
        mark(tab)
      end
      for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
        local buf = api.nvim_win_get_buf(win)
        if working(win) and eligible(buf) then
          attach(tab, buf)
        end
      end
    end
  end

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
    vim.notify("tab-buffers: " .. prefix .. "\n" .. table.concat(messages, "\n"), vim.log.levels.WARN)
  end

  local function clean_closed()
    local removed, candidates, order = {}, {}, {}
    local tabs, known = model:tabs(), {}
    for _, tab in ipairs(tabs) do
      known[tab] = true
    end
    -- A newly created tab may close before the scheduled observer enrolls it.
    for tab in pairs(snapshots) do
      if not known[tab] then
        tabs[#tabs + 1] = tab
      end
    end
    table.sort(tabs)
    for _, tab in ipairs(tabs) do
      if not api.nvim_tabpage_is_valid(tab) then
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
        requests[tab], snapshots[tab] = nil, nil
      end
    end
    -- Remove all closed owners before deciding which buffers are exclusive.
    for _, buf in ipairs(order) do
      local candidate = candidates[buf]
      if basic(buf) and #model:owners(buf) == 0 then
        local reason
        if #displaying(buf) > 0 then
          reason = "buffer is still displayed in an unmanaged window"
        elseif vim.bo[buf].modified and not candidate.force then
          reason = "unsaved changes"
        else
          local ok, err = pcall(api.nvim_buf_delete, buf, { force = candidate.force })
          if not ok then
            reason = tostring(err)
          end
        end
        if reason and basic(buf) then
          local destination = managed_destination()
          if not destination then
            vim.cmd.tabnew()
            destination = api.nvim_get_current_tabpage()
          end
          attach(destination, buf)
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
    notify_failures(external, "Buffers from closed tabs were preserved in the current tab")
  end

  local function restore_closing_options()
    for buf, original in pairs(closing_options) do
      if api.nvim_buf_is_valid(buf) then
        pcall(function()
          vim.bo[buf].bufhidden = original
        end)
      end
    end
    closing_options = {}
  end

  reconcile = function()
    if not model or busy > 0 or exiting or vim.v.exiting ~= vim.NIL then
      return false
    end
    busy = busy + 1
    local ok, err = pcall(function()
      scan_visible()
      clean_closed()
      for _, tab in ipairs(model:tabs()) do
        for _, buf in ipairs(model:buffers(tab)) do
          if not basic(buf) then
            forget(buf)
          end
        end
      end
      -- Deletion/autocmds may have created a new window or changed its buffer.
      scan_visible()
    end)
    restore_closing_options()
    busy = busy - 1
    if not ok then
      error(err, 0)
    end
    return true
  end

  schedule = function()
    if not model or queued or busy > 0 or exiting then
      return
    end
    queued = true
    local ticket = generation
    vim.schedule(function()
      if ticket ~= generation or not model then
        return
      end
      queued = false
      if busy > 0 or exiting then
        return
      end
      reconcile()
      local tabs = {}
      for tab in pairs(changed) do
        tabs[#tabs + 1] = tab
      end
      changed = {}
      table.sort(tabs)
      if #tabs > 0 then
        api.nvim_exec_autocmds("User", { pattern = "TabBuffersChanged", modeline = false, data = { tabs = tabs } })
      end
    end)
  end

  local function run(fn)
    started()
    assert(busy == 0, "tab-buffers operation is already in progress")
    reconcile()
    busy = busy + 1
    local ok, value, err = pcall(fn)
    busy = busy - 1
    reconcile()
    schedule()
    if not ok then
      error(value, 0)
    end
    return value, err
  end

  local function context(opts)
    local tab = opts.tab or api.nvim_get_current_tabpage()
    if not api.nvim_tabpage_is_valid(tab) then
      return nil, "invalid tab handle"
    end
    local win = opts.win or api.nvim_tabpage_get_win(tab)
    if not api.nvim_win_is_valid(win) or api.nvim_win_get_tabpage(win) ~= tab then
      return nil, "invalid window handle for this tab"
    end
    local buf = opts.buf or api.nvim_win_get_buf(win)
    if not api.nvim_buf_is_valid(buf) then
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

  function public.setup()
    assert(busy == 0, "tab-buffers operation is already in progress")
    if model then
      return public.refresh()
    end
    generation = generation + 1
    model = core.new()
    exiting = false
    group = api.nvim_create_augroup(group_name, { clear = true })
    api.nvim_create_autocmd({
      "BufEnter",
      "BufWinEnter",
      "TabEnter",
      "TabNewEntered",
      "WinEnter",
      "WinClosed",
      "BufDelete",
      "BufWipeout",
      "BufFilePost",
      "BufWritePost",
      "BufModifiedSet",
      "TextChanged",
      "TextChangedI",
      "TextChangedP",
      "FileType",
      "BufAdd",
    }, {
      group = group,
      callback = function()
        schedule()
      end,
    })
    api.nvim_create_autocmd("OptionSet", {
      group = group,
      pattern = { "buflisted", "buftype" },
      callback = function()
        schedule()
      end,
    })
    api.nvim_create_autocmd("User", { group = group, pattern = "TabBuffersContextChanged", callback = schedule })
    api.nvim_create_autocmd("TabClosedPre", {
      group = group,
      callback = function()
        if model and not exiting then
          local tab = api.nvim_get_current_tabpage()
          if not managed(tab) then
            model:remove_tab(tab)
            mark(tab)
          end
          local buffers, seen = model:buffers(tab), {}
          for _, buf in ipairs(buffers) do
            seen[buf] = true
          end
          for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
            local buf = api.nvim_win_get_buf(win)
            if working(win) and eligible(buf) and not seen[buf] then
              buffers[#buffers + 1] = buf
              seen[buf] = true
            end
          end
          snapshots[tab] = buffers
          if not requests[tab] then
            -- TabClosedPre permits option changes, but forbids window changes.
            -- Preserve text/jobs until deferred cleanup can decide ownership.
            for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
              local buf = api.nvim_win_get_buf(win)
              if closing_options[buf] == nil then
                closing_options[buf] = hidden_originals[buf] and hidden_originals[buf].value or vim.bo[buf].bufhidden
              end
              vim.bo[buf].bufhidden = "hide"
            end
          end
        end
      end,
    })
    api.nvim_create_autocmd("TabClosed", {
      group = group,
      callback = function()
        schedule()
      end,
    })
    api.nvim_create_autocmd("VimLeavePre", {
      group = group,
      callback = function()
        exiting = true
      end,
    })
    reconcile()
    local buffers = api.nvim_list_bufs()
    table.sort(buffers)
    for _, buf in ipairs(buffers) do
      if eligible(buf) and #model:owners(buf) == 0 and #displaying(buf) == 0 then
        local destination = managed_destination()
        if destination then
          attach(destination, buf)
        end
      end
    end
    schedule()
    return true
  end

  function public.teardown()
    assert(busy == 0, "tab-buffers operation is already in progress")
    if not model then
      return false
    end
    generation = generation + 1
    restore_closing_options()
    api.nvim_del_augroup_by_id(group)
    model, group = nil, nil
    changed, requests, snapshots = {}, {}, {}
    queued, exiting = false, false
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
    return api.nvim_list_tabpages()
  end

  function public.buffers(tab)
    started()
    tab = tab or api.nvim_get_current_tabpage()
    integer(tab, "tab", true)
    return model:buffers(tab)
  end

  function public.owners(buf)
    started()
    buf = buf or api.nvim_get_current_buf()
    integer(buf, "buf", true)
    return model:owners(buf)
  end

  function public.contains(buf, tab)
    started()
    buf, tab = buf or api.nvim_get_current_buf(), tab or api.nvim_get_current_tabpage()
    integer(buf, "buf", true)
    integer(tab, "tab", true)
    return model:contains(tab, buf)
  end

  function public.add(buf, opts)
    opts = vim.tbl_extend("force", options(opts), buf ~= nil and { buf = buf } or {})
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
    end)
  end

  local function order(method, argument, opts)
    opts = options(opts)
    return run(function()
      local ctx, err = context(opts)
      if not ctx then
        return false, err
      end
      if ctx.implicit_special then
        return false
      end
      local did_change
      if method == "reorder" or method == "sort" then
        did_change = model[method](model, ctx.tab, argument)
      else
        did_change = model[method](model, ctx.tab, ctx.buf, argument)
      end
      if did_change then
        mark(ctx.tab)
      end
      return did_change
    end)
  end

  function public.move(offset, opts)
    integer(offset, "offset")
    return order("move", offset, opts)
  end

  function public.move_to(index, opts)
    integer(index, "index")
    return order("move_to", index, opts)
  end

  function public.reorder(buffers, opts)
    assert(type(buffers) == "table", "buffers must be a list")
    return order("reorder", buffers, opts)
  end

  function public.sort(by, opts)
    local comparator
    if type(by) == "function" then
      comparator = by
    elseif by == "id" then
      comparator = function(a, b)
        return a < b
      end
    elseif by == "name" or by == "path" then
      local function name(buf)
        local path = api.nvim_buf_get_name(buf)
        return by == "name" and vim.fn.fnamemodify(path, ":t") or path
      end
      comparator = function(a, b)
        return name(a) < name(b)
      end
    else
      error("sort expects id, name, path or a comparator")
    end
    return order("sort", comparator, opts)
  end

  function public.open(buf, opts)
    integer(buf, "buf", true)
    opts = options(opts)
    assert(opts.split == nil or opts.split == "horizontal" or opts.split == "vertical", "invalid split direction")
    return run(function()
      local ctx, err = context(vim.tbl_extend("force", opts, { buf = buf }))
      if not ctx then
        return nil, err
      end
      if ctx.unmanaged then
        return nil
      end
      if not model:contains(ctx.tab, buf) then
        return nil, "buffer does not belong to this tab"
      end
      local win = ctx.win
      local function suitable(candidate)
        return working(candidate) and basic(api.nvim_win_get_buf(candidate))
      end
      if opts.win and not suitable(win) then
        return nil, "target window is not a working window"
      end
      if not suitable(win) then
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
      local ok, message = protected({ buf, original or api.nvim_win_get_buf(reference) }, function()
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
        elseif win and api.nvim_win_is_valid(win) and api.nvim_buf_is_valid(original) then
          protected({ original, buf }, function()
            pcall(api.nvim_win_set_buf, win, original)
          end)
        end
        if api.nvim_win_is_valid(focus) then
          pcall(api.nvim_set_current_win, focus)
        end
        return nil, message
      end
      return buf
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
      if ctx.implicit_special or not working(ctx.win) or not basic(api.nvim_win_get_buf(ctx.win)) then
        return nil
      end
      local buf = model:neighbor(ctx.tab, ctx.buf, offset, opts.wrap)
      if not buf then
        return nil
      end
      local original = api.nvim_win_get_buf(ctx.win)
      local ok, message = protected({ original, buf }, function()
        local switched, failure = pcall(api.nvim_win_set_buf, ctx.win, buf)
        if not switched then
          if api.nvim_win_is_valid(ctx.win) and api.nvim_buf_is_valid(original) then
            pcall(api.nvim_win_set_buf, ctx.win, original)
          end
          error(failure, 0)
        end
      end)
      if not ok then
        return nil, message
      end
      return buf
    end)
  end

  function public.next(opts)
    return public.switch(1, opts)
  end
  function public.previous(opts)
    return public.switch(-1, opts)
  end

  local function blocker(tab, buf, force)
    if #model:owners(buf) == 1 then
      if vim.bo[buf].modified and not force then
        return "unsaved changes"
      end
      for _, win in ipairs(displaying(buf)) do
        if api.nvim_win_get_tabpage(win) ~= tab or not working(win) then
          return "buffer is still displayed in an unmanaged window"
        end
      end
    end
  end

  local function replacement(tab, buf, excluded)
    local buffers = model:buffers(tab)
    local pivot
    for i, item in ipairs(buffers) do
      if item == buf then
        pivot = i
        break
      end
    end
    if not pivot then
      return nil
    end
    for i = pivot + 1, #buffers do
      if not excluded[buffers[i]] and eligible(buffers[i]) then
        return buffers[i]
      end
    end
    for i = pivot - 1, 1, -1 do
      if not excluded[buffers[i]] and eligible(buffers[i]) then
        return buffers[i]
      end
    end
  end

  ---Replace only the owner's working windows. The callback commits after all
  ---window updates succeed; failures restore buffers while bufhidden is protected.
  local function replace_windows(tab, buf, excluded, commit)
    local windows = {}
    for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
      if working(win) and api.nvim_win_get_buf(win) == buf then
        windows[#windows + 1] = win
      end
    end
    local next_buf = replacement(tab, buf, excluded)
    local placeholder
    if not next_buf and #windows > 0 then
      next_buf = api.nvim_create_buf(true, false)
      placeholder = next_buf
    end
    local focus = api.nvim_get_current_win()
    local buffers = { buf }
    if next_buf then
      buffers[#buffers + 1] = next_buf
    end
    local protected_ok, completed, message = protected(buffers, function()
      local ok, err = pcall(function()
        for _, win in ipairs(windows) do
          api.nvim_win_set_buf(win, next_buf)
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
        for _, win in ipairs(windows) do
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
      return false, completed
    end
    return completed, message
  end

  close_tab = function(tab, force, report)
    report = report or result()
    if not api.nvim_tabpage_is_valid(tab) then
      report.error = "invalid tab handle"
      return report
    end
    if #api.nvim_list_tabpages() == 1 then
      report.error = "cannot close the last tab"
      return report
    end
    for _, buf in ipairs(model:buffers(tab)) do
      if basic(buf) and #model:owners(buf) == 1 and vim.bo[buf].modified and not force then
        report.failed[#report.failed + 1] = { buf = buf, message = "unsaved changes" }
      end
    end
    if #report.failed > 0 then
      report.error = "tab contains modified exclusive buffers"
      return report
    end
    local buffers = model:buffers(tab)
    -- Special buffers/jobs are excluded from deletion but must also survive hiding.
    for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
      buffers[#buffers + 1] = api.nvim_win_get_buf(win)
    end
    requests[tab] = { force = force == true, report = report }
    local ok, err = protected(buffers, function()
      vim.cmd({ cmd = "tabclose", args = { tostring(api.nvim_tabpage_get_number(tab)) }, bang = force == true })
    end)
    if api.nvim_tabpage_is_valid(tab) then
      requests[tab], snapshots[tab] = nil, nil
      report.error = ok and "tab did not close" or tostring(err)
    elseif not ok then
      -- TabClosedPre errors may still close the tab. Reconciliation must process it.
      report.error = tostring(err)
    end
    return report
  end

  local function finish_empty(tab, report)
    if api.nvim_tabpage_is_valid(tab) and #model:buffers(tab) == 0 then
      if #api.nvim_list_tabpages() > 1 then
        close_tab(tab, false, report)
      else
        local has_working = false
        for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
          if working(win) and basic(api.nvim_win_get_buf(win)) then
            has_working = true
            break
          end
        end
        if not has_working then
          local focus = api.nvim_get_current_win()
          local ok, err = pcall(vim.cmd, "botright new")
          if api.nvim_win_is_valid(focus) then
            api.nvim_set_current_win(focus)
          end
          if not ok then
            report.error = tostring(err)
          end
        end
      end
    end
  end

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
      local targets = selected
          and vim.tbl_filter(function(buf)
            return selected[buf] == true
          end, model:buffers(ctx.tab))
        or model:targets(ctx.tab, mode, ctx.buf)
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
            local ok, message = replace_windows(ctx.tab, buf, excluded, function()
              if not api.nvim_tabpage_is_valid(ctx.tab) then
                error("source tab closed during the operation")
              end
              if not model:contains(ctx.tab, buf) then
                return
              end
              if #model:owners(buf) == 1 then
                local current_reason = blocker(ctx.tab, buf, opts.force)
                if current_reason then
                  error(current_reason)
                end
                local deleted, failure = pcall(api.nvim_buf_delete, buf, { force = opts.force == true })
                if not deleted then
                  if api.nvim_buf_is_valid(buf) then
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
            end)
            if not ok then
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
    assert(type(buffers) == "table", "buffers must be a list")
    local selected, count = {}, 0
    for index, buf in pairs(buffers) do
      integer(index, "buffer list index", true)
      assert(index <= #buffers, "buffers must be a dense list")
      integer(buf, "buf", true)
      selected[buf] = true
      count = count + 1
    end
    assert(count == #buffers, "buffers must be a dense list")
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
      if not api.nvim_tabpage_is_valid(target_tab) then
        return false, "invalid target tab handle"
      end
      if not managed(target_tab) then
        return false, "target tab is unmanaged"
      end
      if ctx.implicit_special or ctx.tab == target_tab or not model:contains(ctx.tab, ctx.buf) then
        return false
      end
      local ok, failure = replace_windows(ctx.tab, ctx.buf, { [ctx.buf] = true }, function()
        if not api.nvim_tabpage_is_valid(target_tab) then
          error("target tab closed during the operation")
        end
        if not managed(target_tab) then
          error("target tab is unmanaged")
        end
        if not api.nvim_tabpage_is_valid(ctx.tab) then
          error("source tab closed during the operation")
        end
        model:transfer(ctx.tab, target_tab, ctx.buf, opts.index)
        mark(ctx.tab)
        mark(target_tab)
      end)
      if not ok then
        return false, failure
      end
      finish_empty(ctx.tab, report)
      return true
    end)
    notify_failures(report, "The source tab could not be closed")
    return changed_membership, err or report.error
  end

  return public
end

return M
