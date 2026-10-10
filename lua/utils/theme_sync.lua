local M = {}
local active

function M.read_mode(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local mode = vim.trim(file:read("*a") or "")
  file:close()
  return (mode == "light" or mode == "dark") and mode or nil
end

function M.stop()
  if not active then
    return
  end
  active.closed = true
  for _, handle in pairs(active.handles) do
    if not handle:is_closing() then
      handle:stop()
      handle:close()
    end
  end
  active = nil
end

-- Watch the directory rather than the file: the publisher uses atomic rename.
-- Polling also recovers missed events, missing directories and exhausted watchers.
function M.watch(path, on_mode)
  M.stop()
  local state = { closed = false, handles = {}, watching = false }
  active = state
  local directory = vim.fn.fnamemodify(path, ":h")
  local basename = vim.fn.fnamemodify(path, ":t")
  local event = vim.uv.new_fs_event()
  local poll = assert(vim.uv.new_timer())
  local debounce = assert(vim.uv.new_timer())
  state.handles = { poll = poll, debounce = debounce, event = event }

  local function reconcile()
    if not state.closed then
      local mode = M.read_mode(path)
      if mode then
        on_mode(mode)
      end
    end
  end

  local function start_watcher()
    if state.closed or not event then
      return
    end
    local stat = vim.uv.fs_stat(directory)
    local inode = stat and stat.ino
    if state.watching and inode == state.inode then
      return
    end
    event:stop()
    state.watching = false
    if not stat then
      return
    end
    local ok = event:start(directory, {}, function(err, filename)
      if state.closed then
        return
      end
      if err then
        event:stop()
        state.watching = false
      elseif not filename or filename == "" or filename == basename then
        debounce:start(50, 0, vim.schedule_wrap(reconcile))
      end
    end)
    state.watching = not not ok
    state.inode = inode
  end

  start_watcher()
  reconcile()
  poll:start(
    1000,
    1000,
    vim.schedule_wrap(function()
      if not state.closed then
        start_watcher()
        reconcile()
      end
    end)
  )
end

return M
