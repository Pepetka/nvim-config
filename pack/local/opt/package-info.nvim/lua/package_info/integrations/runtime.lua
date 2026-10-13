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
  ---@type string?
  local held_lock
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
    local stderr = {}
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
      on_stderr = function(_, lines)
        for _, line in ipairs(lines) do
          if line ~= "" then
            stderr[#stderr + 1] = line:sub(1, 200)
            if #stderr > 5 then
              table.remove(stderr, 1)
            end
          end
        end
      end,
      on_exit = function(_, code)
        local last = stderr[#stderr]
        exit(code ~= 0 and ("exit " .. code .. (last and ": " .. last or "")) or nil)
      end,
    })
  end
  function adapter.stop(job)
    generation = generation + 1
    for process in pairs(processes) do
      pcall(process.kill, process, 15)
    end
    processes = {}
    if held_lock then
      vim.uv.fs_rmdir(held_lock)
      held_lock = nil
    end
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
  ---@param source string
  ---@param runtime string
  ---@return boolean
  local function copy_sources(source, runtime)
    local files, contents = require("package_info.integrations.runtime_files"), {}
    for index, name in ipairs(files) do
      contents[index] = read(source .. "/" .. name)
      if not contents[index] then
        return false
      end
    end
    local digest = vim.fn.sha256(table.concat(files, "\0") .. "\0" .. table.concat(contents, "\0"))
    local marker = runtime .. "/installed-sources"
    local complete = read(marker) == digest
    for _, name in ipairs(files) do
      complete = complete and vim.uv.fs_stat(runtime .. "/" .. name) ~= nil
    end
    if complete then
      return true
    end
    -- Unique temporary names keep concurrent Neovim instances from renaming each other's files.
    local suffix = "." .. vim.uv.os_getpid() .. ".tmp"
    local function write(destination, content)
      vim.fn.mkdir(vim.fs.dirname(destination), "p")
      local file = io.open(destination .. suffix, "wb")
      if not file then
        return false
      end
      local written = file:write(content)
      file:close()
      if written and os.rename(destination .. suffix, destination) then
        return true
      end
      os.remove(destination .. suffix)
      return false
    end
    for index, name in ipairs(files) do
      if not write(runtime .. "/" .. name, contents[index]) then
        return false
      end
    end
    return write(marker, digest)
  end
  ---@param runtime string
  ---@param hash string
  ---@return boolean
  local function installed(runtime, hash)
    local present = read(runtime .. "/installed-lock") == hash
    for _, name in ipairs({ "semver", "picomatch", "yaml" }) do
      present = present and vim.uv.fs_stat(runtime .. "/node_modules/" .. name) ~= nil
    end
    return present
  end
  ---@param runtime string
  ---@param hash string
  ---@param callback PackageInfoBootstrapCallback
  ---@param started? number
  local function install(runtime, hash, callback, started)
    if installed(runtime, hash) then
      callback()
      return
    end
    started = started or adapter.now()
    local lock = runtime .. "/.install.lock"
    if not vim.uv.fs_mkdir(lock, 448) then
      local stat = vim.uv.fs_stat(lock)
      if not stat then
        callback("Cannot prepare helper runtime")
        return
      elseif os.time() - stat.mtime.sec > config.timeouts.bootstrap / 1000 then
        vim.uv.fs_rmdir(lock)
      elseif adapter.now() - started > config.timeouts.bootstrap then
        callback("Helper installation is locked by another Neovim instance")
        return
      end
      -- Another Neovim instance is installing the same runtime.
      local epoch = generation
      vim.defer_fn(function()
        if epoch == generation then
          install(runtime, hash, callback, started)
        end
      end, 500)
      return
    end
    held_lock = lock
    local function release(message)
      held_lock = nil
      vim.uv.fs_rmdir(lock)
      callback(message)
    end
    spawn(
      { "npm", "ci", "--ignore-scripts", "--no-audit", "--no-fund" },
      { cwd = runtime, text = true, timeout = config.timeouts.bootstrap },
      function(result)
        if result.code ~= 0 then
          release("Helper dependency installation failed; check npm connectivity and refresh")
          return
        end
        local file = io.open(runtime .. "/installed-lock", "wb")
        if file then
          file:write(hash)
          file:close()
        end
        release()
      end,
      release
    )
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
      if not copy_sources(source, runtime) then
        callback("Cannot prepare helper runtime")
        return
      end
      install(runtime, hash, callback)
    end, callback)
  end
  return adapter
end
return M
