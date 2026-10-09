local M = {}
---@param delay integer
---@param callback PackageInfoCancel
---@return PackageInfoCancel
function M.schedule(delay, callback)
  local timer = vim.defer_fn(callback, delay)
  return function()
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
end
---@param path string
---@return string?
local function read(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local value = file:read("*a")
  file:close()
  return value
end
---@return PackageInfoHelperAdapter
function M.new()
  local root = debug.getinfo(1, "S").source:sub(2)
  for _ = 1, 4 do
    root = vim.fs.dirname(root)
  end
  local processes = {}
  local generation = 0
  local config = require("package_info.core.config").defaults()
  local adapter = {
    source = root .. "/scripts",
    runtime = vim.fn.stdpath("data") .. "/package-info",
    now = function()
      return vim.uv.hrtime() / 1000000
    end,
    notify = function(message)
      vim.notify(message, vim.log.levels.WARN)
    end,
    schedule = M.schedule,
  }
  ---@cast adapter PackageInfoHelperAdapter
  function adapter.configure(options)
    config = require("package_info.core.config").copy(options)
  end
  function adapter.send(job, message)
    if vim.fn.chansend(job, vim.json.encode(message) .. "\n") == 0 then
      error("Closed helper channel")
    end
  end
  function adapter.start(runtime, response, exit)
    local partial = ""
    local options = {
      timeout = config.timeouts.registry,
      globalLimit = config.concurrency.http,
      projectLimit = config.concurrency.http_per_project,
      ttl = config.cache.ttl,
      retry = config.cache.retry,
      memoryLimit = config.cache.memory_limit,
      disk = config.cache.disk,
      diskLimit = config.cache.disk_limit,
      cleanupInterval = config.cache.cleanup_interval,
      clientTTL = config.cache.client_ttl,
      clientLimit = config.cache.client_limit,
    }
    return vim.fn.jobstart({ "node", runtime .. "/index.cjs", "--options", vim.json.encode(options) }, {
      on_stdout = function(_, lines)
        for index, line in ipairs(lines) do
          partial = partial .. line
          if index < #lines then
            local ok, value = pcall(vim.json.decode, partial)
            partial = ""
            if ok then
              response(value)
            end
          end
        end
      end,
      on_exit = exit,
    })
  end
  function adapter.stop(job)
    generation = generation + 1
    for process in pairs(processes) do
      pcall(process.kill, process, 15)
    end
    processes = {}
    if job then
      vim.fn.jobstop(job)
    end
  end
  ---@param command string[]
  ---@param options vim.SystemOpts
  ---@param callback fun(result: vim.SystemCompleted)
  ---@param failure PackageInfoBootstrapCallback
  local function spawn(command, options, callback, failure)
    local process
    local epoch = generation
    process = vim.system(command, options, function(result)
      vim.schedule(function()
        processes[process] = nil
        if epoch == generation then
          local ok = pcall(callback, result)
          if not ok then
            failure("Cannot prepare helper runtime")
          end
        end
      end)
    end)
    processes[process] = true
  end
  function adapter.bootstrap(source, runtime, callback)
    if vim.fn.executable("node") == 0 or vim.fn.executable("npm") == 0 then
      callback("Node >=22.18 and npm are required")
      return
    end
    spawn({ "node", "--version" }, { text = true, timeout = config.timeouts.manager }, function(result)
      local major, minor = (result.stdout or ""):match("v(%d+)%.(%d+)")
      if result.code ~= 0 or not major or tonumber(major) < 22 or tonumber(major) == 22 and tonumber(minor) < 18 then
        callback("Node >=22.18 is required")
        return
      end
      vim.fn.mkdir(runtime, "p")
      local lock = read(source .. "/package-lock.json")
      if not lock then
        callback("Helper lockfile is missing")
        return
      end
      local hash = vim.fn.sha256(lock)
      for _, name in ipairs(require("package_info.integrations.runtime_files")) do
        local content = read(source .. "/" .. name)
        if not content then
          callback("Cannot prepare helper runtime")
          return
        end
        local destination = runtime .. "/" .. name
        vim.fn.mkdir(vim.fs.dirname(destination), "p")
        local file = io.open(destination .. ".tmp", "wb")
        if not file then
          callback("Cannot prepare helper runtime")
          return
        end
        local written = file:write(content)
        file:close()
        if not written or not os.rename(destination .. ".tmp", destination) then
          callback("Cannot prepare helper runtime")
          return
        end
      end
      local present = true
      for _, name in ipairs({ "semver", "picomatch", "yaml" }) do
        present = present and vim.uv.fs_stat(runtime .. "/node_modules/" .. name) ~= nil
      end
      if read(runtime .. "/installed-lock") == hash and present then
        callback()
        return
      end
      spawn(
        { "npm", "ci", "--ignore-scripts", "--no-audit", "--no-fund" },
        { cwd = runtime, text = true, timeout = config.timeouts.bootstrap },
        function(install)
          if install.code ~= 0 then
            callback("Helper dependency installation failed; check npm connectivity and refresh")
            return
          end
          local file = io.open(runtime .. "/installed-lock", "wb")
          if file then
            file:write(hash)
            file:close()
          end
          callback()
        end,
        callback
      )
    end, callback)
  end
  return adapter
end
return M
