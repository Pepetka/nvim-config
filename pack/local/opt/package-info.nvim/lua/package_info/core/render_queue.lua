local M = {}
---@param schedule fun(delay: integer, callback: PackageInfoCancel): PackageInfoCancel
---@param apply PackageInfoRender
---@param notify fun(message: string)
---@return PackageInfoRenderQueue
function M.new(schedule, apply, notify)
  ---@type table<integer, {state: PackageInfoBuffer, timer?: PackageInfoCancel}>
  local entries = {}
  local queue = {}
  ---@param buf integer
  ---@param state PackageInfoBuffer
  local function render(buf, state)
    if not pcall(apply, buf, state) then
      notify("package-info: annotation update failed")
    end
  end
  function queue.cancel(buf)
    local entry = entries[buf]
    entries[buf] = nil
    if entry and entry.timer then
      entry.timer()
    end
  end
  function queue.request(buf, state)
    local entry = entries[buf]
    if not entry or entry.state ~= state then
      queue.cancel(buf)
      entries[buf] = { state = state }
      -- Installed versions and initial errors remain visible without waiting for registry results.
      render(buf, state)
      return
    end
    if entry.timer then
      return
    end
    entry.timer = schedule(16, function()
      if entries[buf] ~= entry then
        return
      end
      entry.timer = nil
      render(buf, entry.state)
    end)
  end
  function queue.pending()
    local count = 0
    for _, entry in pairs(entries) do
      if entry.timer then
        count = count + 1
      end
    end
    return count
  end
  function queue.teardown()
    for buf in pairs(entries) do
      queue.cancel(buf)
    end
  end
  return queue
end
return M
