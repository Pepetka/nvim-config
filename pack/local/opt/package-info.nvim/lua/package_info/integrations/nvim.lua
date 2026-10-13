local M = {}
local sequence = 0
-- Files whose changes make installed versions or registry configuration stale.
local stamp_files = {
  "package.json",
  "package-lock.json",
  "npm-shrinkwrap.json",
  "yarn.lock",
  "pnpm-lock.yaml",
  "pnpm-workspace.yaml",
  ".npmrc",
  ".yarnrc",
  ".yarnrc.yml",
  ".pnp.cjs",
  ".yarn/install-state.gz",
  "node_modules/.package-lock.json",
  "node_modules/.modules.yaml",
  "node_modules/.yarn-state.yml",
  "node_modules/.yarn-integrity",
}
---@param name string
---@return boolean
local function registry_variable(name)
  local lower = name:lower()
  for _, prefix in ipairs({ "npm_config_", "yarn_", "pnpm_", "corepack_" }) do
    if vim.startswith(lower, prefix) then
      return true
    end
  end
  return vim.endswith(lower, "_proxy")
    or vim.list_contains(
      { "home", "xdg_config_home", "prefix", "node_extra_ca_certs", "node_tls_reject_unauthorized" },
      lower
    )
end
---@param buf integer
---@return boolean
local function visible(buf)
  return #vim.fn.win_findbuf(buf) > 0
end
---@return PackageInfoAdapter
function M.new()
  sequence = sequence + 1
  local name = "package-info" .. (sequence == 1 and "" or tostring(sequence))
  local namespace = vim.api.nvim_create_namespace(name)
  local owned_commands = {}
  local group
  local config = require("package_info.core.config").defaults()
  local command_names = { "PackageInfo", "PackageInfoStatus", "PackageInfoRefresh", "PackageInfoToggle" }
  local adapter = {
    schedule = require("package_info.integrations.runtime").schedule,
    namespace = namespace,
    null = vim.NIL,
    now = function()
      return vim.uv.hrtime() / 1000000
    end,
    current = function()
      return { buf = vim.api.nvim_get_current_buf(), row = vim.api.nvim_win_get_cursor(0)[1] - 1 }
    end,
    buffer = function(buf)
      if not vim.api.nvim_buf_is_valid(buf) then
        return nil
      end
      local path = vim.api.nvim_buf_get_name(buf)
      return {
        path = path,
        tick = vim.api.nvim_buf_get_changedtick(buf),
        modified = vim.bo[buf].modified,
        special = vim.bo[buf].buftype ~= "" or path:find("^%a[%w+.-]*://") ~= nil,
      }
    end,
    executable = function(name)
      return vim.fn.executable(name) == 1
    end,
    encode = vim.json.encode,
    decode = vim.json.decode,
    environment = vim.fn.environ,
    npm_path = function()
      return vim.fn.exepath("npm")
    end,
    user_config = function()
      return vim.env.NPM_CONFIG_USERCONFIG or vim.env.npm_config_userconfig
    end,
    manifest = require("package_info.integrations.treesitter").parse,
    notify = function(message)
      vim.notify(message, vim.log.levels.WARN)
    end,
  }
  ---@cast adapter PackageInfoAdapter
  function adapter.configure(options)
    config = require("package_info.core.config").copy(options)
  end
  adapter.helper = require("package_info.core.helper").new(require("package_info.integrations.runtime").new())
  adapter.queue = require("package_info.core.queue").new(function(task, callback)
    local env = { COREPACK_ENABLE_NETWORK = "0" }
    if task.command[1] == "pnpm" then
      -- pnpm otherwise downloads and runs the version declared by packageManager.
      env.npm_config_manage_package_manager_versions = "false"
      env.npm_config_pm_on_fail = "ignore"
    end
    local process = vim.system(
      task.command,
      { cwd = task.cwd, env = env, text = true, timeout = task.timeout or 15000 },
      function(result)
        vim.schedule(function()
          callback({ code = result.code, signal = result.signal, stdout = result.stdout, stderr = result.stderr })
        end)
      end
    )
    return {
      kill = function(_, signal)
        process:kill(signal)
      end,
    }
  end, adapter.notify)
  function adapter.environment_hash()
    local environment = adapter.environment()
    local names = {}
    for name in pairs(environment) do
      if registry_variable(name) then
        names[#names + 1] = name
      end
    end
    table.sort(names)
    local values = {}
    for _, name in ipairs(names) do
      values[#values + 1] = { name, environment[name] }
    end
    return vim.fn.sha256(adapter.encode(values))
  end
  function adapter.stamp(context)
    local parts = {}
    local dir = context.dir
    local home = vim.env.HOME
    while true do
      for _, name in ipairs(stamp_files) do
        local stat = vim.uv.fs_stat(dir .. "/" .. name)
        if stat then
          parts[#parts + 1] = table.concat({ dir, name, stat.mtime.sec, stat.mtime.nsec, stat.size }, ":")
        end
      end
      local parent = vim.fs.dirname(dir)
      if dir == context.root or parent == dir then
        break
      end
      dir = parent
    end
    for _, name in ipairs(home and { ".npmrc", ".yarnrc", ".yarnrc.yml" } or {}) do
      local stat = vim.uv.fs_stat(home .. "/" .. name)
      if stat then
        parts[#parts + 1] = table.concat({ name, stat.mtime.sec, stat.mtime.nsec, stat.size }, ":")
      end
    end
    return table.concat(parts, "|")
  end
  function adapter.clear(buf)
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
    end
  end
  function adapter.render(buf, rows)
    adapter.clear(buf)
    for row, chunks in pairs(rows) do
      vim.api.nvim_buf_set_extmark(
        buf,
        namespace,
        row,
        0,
        { virt_text = chunks, virt_text_pos = config.display.virt_text_pos }
      )
    end
  end
  function adapter.float(lines, options)
    local values = options or config.display.float
    vim.lsp.util.open_floating_preview(lines, "markdown", {
      border = values.border,
      focusable = values.focusable,
      max_width = values.max_width,
      max_height = values.max_height,
    })
  end
  function adapter.uninstall()
    if group then
      vim.api.nvim_del_augroup_by_id(group)
      group = nil
    end
    local commands = vim.api.nvim_get_commands({})
    for _, command in ipairs(command_names) do
      if owned_commands[command] and commands[command] and commands[command].callback == owned_commands[command] then
        pcall(vim.api.nvim_del_user_command, command)
      end
    end
    owned_commands = {}
  end
  ---@param controller PackageInfoController
  function adapter.install(controller)
    local function highlights()
      for group, link in pairs({
        PackageInfoUpdate = "DiagnosticInfo",
        PackageInfoLatest = "DiagnosticWarn",
        PackageInfoError = "DiagnosticError",
        PackageInfoMismatch = "DiagnosticWarn",
        PackageInfoMissing = "DiagnosticHint",
        PackageInfoInstalled = "Comment",
        PackageInfoUnsupported = "Comment",
      }) do
        vim.api.nvim_set_hl(0, group, { link = link, default = true })
      end
    end
    highlights()
    group = vim.api.nvim_create_augroup(name, { clear = true })
    vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights })
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = group,
      pattern = {
        "package.json",
        "package-lock.json",
        "npm-shrinkwrap.json",
        "yarn.lock",
        "pnpm-lock.yaml",
        "pnpm-workspace.yaml",
        ".npmrc",
        ".yarnrc",
        ".yarnrc.yml",
        ".pnp.cjs",
      },
      callback = function(event)
        local directory = vim.fs.dirname(vim.api.nvim_buf_get_name(event.buf))
        local affected = {}
        for buf, state in pairs(controller.buffers) do
          if buf ~= event.buf and state.path and state.path:sub(1, #directory + 1) == directory .. "/" then
            controller.invalidate(buf, state.disabled)
            if not state.disabled then
              affected[#affected + 1] = buf
            end
          end
        end
        if config.auto_refresh.on_save and #affected > 0 then
          vim.schedule(function()
            for _, buf in ipairs(affected) do
              if vim.api.nvim_buf_is_valid(buf) and visible(buf) then
                controller.enter(buf)
              end
            end
          end)
        end
      end,
    })
    vim.api.nvim_create_autocmd({ "BufEnter", "BufReadPost", "FileChangedShellPost", "BufWritePost" }, {
      group = group,
      pattern = "package.json",
      callback = function(event)
        if event.event == "BufWritePost" then
          if config.auto_refresh.on_save then
            controller.refresh(event.buf)
          end
        elseif config.auto_refresh.on_enter then
          controller.enter(event.buf)
        end
      end,
    })
    vim.api.nvim_create_autocmd("FocusGained", {
      group = group,
      callback = function()
        if config.auto_refresh.on_enter then
          local buffers = vim.tbl_keys(controller.buffers)
          for _, buf in ipairs(buffers) do
            if vim.api.nvim_buf_is_valid(buf) and visible(buf) then
              controller.enter(buf)
            end
          end
        end
      end,
    })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufUnload", "BufWipeout", "BufFilePost" }, {
      group = group,
      callback = function(event)
        local state = controller.buffers[event.buf]
        if not state then
          return
        end
        if event.event == "BufWipeout" then
          controller.forget(event.buf)
        elseif
          event.event ~= "TextChanged" and event.event ~= "TextChangedI"
          or vim.api.nvim_buf_get_changedtick(event.buf) ~= state.tick
          or vim.bo[event.buf].modified
        then
          controller.invalidate(event.buf, state.disabled)
        end
      end,
    })
    vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = controller.teardown })
    local commands = {
      PackageInfo = { callback = controller.info },
      PackageInfoStatus = { callback = controller.status },
      PackageInfoRefresh = {
        callback = function(args)
          controller.refresh(nil, args.bang)
        end,
        bang = true,
      },
      PackageInfoToggle = { callback = controller.toggle },
    }
    for name, command in pairs(commands) do
      vim.api.nvim_create_user_command(name, command.callback, { bang = command.bang or false, force = true })
      owned_commands[name] = command.callback
    end
  end
  return adapter
end
return M
