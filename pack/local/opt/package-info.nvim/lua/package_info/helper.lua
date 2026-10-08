local M = { pending = {}, waiting = {}, next_id = 0, state = "idle" }
local source = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))
M.source = source .. "/scripts"
M.runtime = vim.fn.stdpath("data") .. "/package-info"

local function read(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local value = file:read("*a")
  file:close()
  return value
end

local function fail(message)
  M.state, M.error = "failed", message
  M.failed_at = vim.uv.hrtime()
  local waiting, pending = M.waiting, M.pending
  M.waiting, M.pending = {}, {}
  for _, callback in ipairs(waiting) do
    callback(nil, message)
  end
  for _, callback in pairs(pending) do
    callback(nil, message)
  end
end

local function start()
  local partial = ""
  local job
  job = vim.fn.jobstart({ "node", M.runtime .. "/index.cjs" }, {
    on_stdout = function(_, lines)
      for index, line in ipairs(lines) do
        partial = partial .. line
        if index < #lines then
          local ok, response = pcall(vim.json.decode, partial)
          partial = ""
          if ok and type(response) == "table" and M.pending[response.id] then
            local callback = M.pending[response.id]
            if response.done ~= false then
              M.pending[response.id] = nil
            end
            callback(response.result, response.error, response.done ~= false)
          end
        end
      end
    end,
    on_exit = function()
      if M.job == job then
        M.job = nil
        fail("Node helper stopped; refresh to restart")
      end
    end,
  })
  if job <= 0 then
    fail("Cannot start Node helper")
    return
  end
  M.job, M.state, M.error = job, "ready", nil
  local waiting = M.waiting
  M.waiting = {}
  for _, callback in ipairs(waiting) do
    callback(true)
  end
end

function M.ensure(callback)
  if M.state == "ready" then
    callback(true)
    return
  end
  if M.state == "failed" and M.failed_at and (vim.uv.hrtime() - M.failed_at) / 1000000 < 30000 then
    callback(nil, M.error)
    return
  end
  table.insert(M.waiting, callback)
  if M.state == "installing" or M.state == "starting" then
    return
  end
  if vim.fn.executable("node") == 0 or vim.fn.executable("npm") == 0 then
    fail("Node >=22.18 and npm are required")
    return
  end
  M.state = "starting"
  vim.system({ "node", "--version" }, { text = true }, function(result)
    vim.schedule(function()
      local major, minor = (result.stdout or ""):match("v(%d+)%.(%d+)")
      if result.code ~= 0 or not major or tonumber(major) < 22 or tonumber(major) == 22 and tonumber(minor) < 18 then
        fail("Node >=22.18 is required")
        return
      end
      vim.fn.mkdir(M.runtime, "p")
      local lock = read(M.source .. "/package-lock.json")
      if not lock then
        fail("Helper lockfile is missing")
        return
      end
      local hash = vim.fn.sha256(lock)
      for _, name in ipairs({ "package.json", "package-lock.json", "index.cjs", "core.cjs", "network.cjs" }) do
        local content = read(M.source .. "/" .. name)
        local file = io.open(M.runtime .. "/" .. name, "wb")
        if not content or not file then
          fail("Cannot prepare helper runtime")
          return
        end
        file:write(content)
        file:close()
      end
      local dependencies_present = true
      for _, name in ipairs({ "semver", "picomatch", "yaml" }) do
        dependencies_present = dependencies_present and vim.uv.fs_stat(M.runtime .. "/node_modules/" .. name) ~= nil
      end
      if read(M.runtime .. "/installed-lock") == hash and dependencies_present then
        start()
        return
      end
      M.state = "installing"
      vim.system({ "npm", "ci", "--ignore-scripts", "--no-audit", "--no-fund" }, {
        cwd = M.runtime,
        text = true,
        timeout = 120000,
      }, function(install)
        vim.schedule(function()
          if install.code ~= 0 then
            fail("Helper dependency installation failed; check npm connectivity and refresh")
            return
          end
          local file = io.open(M.runtime .. "/installed-lock", "wb")
          if file then
            file:write(hash)
            file:close()
          end
          start()
        end)
      end)
    end)
  end)
end

function M.retry()
  M.failed_at = nil
end

function M.request(method, input, callback, options)
  options = options or {}
  local ticket = {}
  M.ensure(function(ok, err)
    if ticket.cancelled then
      return
    end
    if not ok then
      callback(nil, err)
      return
    end
    M.next_id = M.next_id + 1
    local id = M.next_id
    ticket.id = id
    M.pending[id] = callback
    vim.fn.chansend(M.job, vim.json.encode({ id = id, method = method, input = input }) .. "\n")
    vim.defer_fn(function()
      if M.pending[id] then
        M.cancel(ticket)
        callback(nil, "Node helper request timed out")
      end
    end, options.timeout or 5000)
  end)
  return ticket
end

function M.cancel(ticket)
  if not ticket then
    return
  end
  ticket.cancelled = true
  if ticket.id and M.pending[ticket.id] then
    M.pending[ticket.id] = nil
    if M.job then
      vim.fn.chansend(M.job, vim.json.encode({ method = "cancel", input = { id = ticket.id } }) .. "\n")
    end
  end
end

function M.stop()
  local job = M.job
  M.job, M.state = nil, "idle"
  if job then
    vim.fn.jobstop(job)
  end
  fail("Node helper stopped")
  M.state = "idle"
end

return M
