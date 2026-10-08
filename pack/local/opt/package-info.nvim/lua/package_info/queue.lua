---@class PackageInfoTask
---@field project string
---@field cwd string
---@field command string[]
---@field timeout? integer
---@field cancelled fun(): boolean
---@field callback fun(result: vim.SystemCompleted)
local M = { active = 0, projects = {}, jobs = {}, waiting = {} }

local function pump()
  local index = 1
  while M.active < 4 and index <= #M.waiting do
    local task = M.waiting[index]
    if task.cancelled() then
      table.remove(M.waiting, index)
    elseif (M.projects[task.project] or 0) >= 2 then
      index = index + 1
    else
      table.remove(M.waiting, index)
      M.active = M.active + 1
      M.projects[task.project] = (M.projects[task.project] or 0) + 1
      local ok, process = pcall(vim.system, task.command, {
        cwd = task.cwd,
        env = { COREPACK_ENABLE_NETWORK = "0" },
        text = true,
        timeout = task.timeout or 15000,
      }, function(result)
        vim.schedule(function()
          M.jobs[task] = nil
          M.active = M.active - 1
          M.projects[task.project] = M.projects[task.project] - 1
          if not task.cancelled() then
            task.callback(result)
          end
          pump()
        end)
      end)
      if ok then
        M.jobs[task] = process
      else
        M.active = M.active - 1
        M.projects[task.project] = M.projects[task.project] - 1
        task.callback({ code = -1, stdout = "", stderr = "Cannot start package manager" })
      end
    end
  end
end

---@param task PackageInfoTask
function M.submit(task)
  table.insert(M.waiting, task)
  pump()
end

function M.cancel()
  for task, process in pairs(M.jobs) do
    if task.cancelled() then
      process:kill(15)
    end
  end
  pump()
end

return M
