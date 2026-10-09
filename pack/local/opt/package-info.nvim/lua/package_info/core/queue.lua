local M = {}
---@param spawn fun(task: PackageInfoTask, callback: fun(result: PackageInfoProcessResult)): PackageInfoProcess
---@param notify fun(message: string)
---@return PackageInfoQueue
function M.new(spawn, notify)
  local queue = { active = 0, projects = {}, waiting = {}, jobs = {} }
  ---@cast queue PackageInfoQueue
  local pumping = false
  local limits = require("package_info.core.config").defaults().concurrency
  ---@type fun()
  local pump
  ---@param task PackageInfoTask
  ---@param result? PackageInfoProcessResult
  local function finish(task, result)
    local job = queue.jobs[task]
    if not job then
      return
    end
    queue.jobs[task] = nil
    queue.active = queue.active - 1
    queue.projects[task.project] = queue.projects[task.project] - 1
    if result and not job.cancelled and not task.cancelled() then
      local ok, err = pcall(task.callback, result)
      if not ok then
        notify(tostring(err))
      end
    end
    pump()
  end
  pump = function()
    if pumping then
      return
    end
    pumping = true
    local index = 1
    while queue.active < limits.cli and index <= #queue.waiting do
      local task = queue.waiting[index]
      if task.cancelled() then
        table.remove(queue.waiting, index)
      elseif (queue.projects[task.project] or 0) >= limits.cli_per_project then
        index = index + 1
      else
        table.remove(queue.waiting, index)
        queue.active = queue.active + 1
        queue.projects[task.project] = (queue.projects[task.project] or 0) + 1
        local job = {}
        queue.jobs[task] = job
        local ok, process = pcall(spawn, task, function(result)
          finish(task, result)
        end)
        if ok then
          if queue.jobs[task] == job then
            job.process = process
          end
        else
          finish(task, { code = -1, stdout = "", stderr = "Cannot start package manager" })
        end
      end
    end
    pumping = false
  end
  function queue.submit(task)
    queue.waiting[#queue.waiting + 1] = task
    pump()
  end
  function queue.configure(options)
    limits = require("package_info.core.config").copy(options)
    pump()
  end
  function queue.cancel()
    for task, job in pairs(queue.jobs) do
      if task.cancelled() and not job.cancelled then
        local process = job.process
        job.cancelled = true
        if process then
          pcall(process.kill, process, 15)
        end
      end
    end
    pump()
  end
  function queue.teardown()
    queue.waiting = {}
    for task, job in pairs(queue.jobs) do
      local process = job.process
      job.cancelled = true
      if process then
        pcall(process.kill, process, 15)
      end
    end
  end
  return queue
end
return M
