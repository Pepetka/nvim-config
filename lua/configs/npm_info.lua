local npm_info = require("npm-info")
local core = require("npm-info.core")
local cfg = require("npm-info.config")

npm_info.setup({
  show_installed = false,
  icons = {
    current = "󰏖",
    outdated = "󰚰",
    isLatest = "󰄬",
    beta = "󰂡",
    unstable = "󰂡",
  },
  hl_groups = {
    current = "Comment",
    isLatest = "NpmLatest",
    outdated = "NpmOutdated",
    beta = "DiagnosticWarn",
    unstable = "NpmBeta",
  },
})

-- npm outdated may return entries without a `current` field (e.g. in monorepos
-- where a dependency is declared but not installed in the package's own
-- node_modules). Drop those entries so the plugin doesn't crash on
-- `string.find(nil, "-")`.
local orig_handle_npm_results = core.handle_npm_results
---@diagnostic disable-next-line: duplicate-set-field
core.handle_npm_results = function(result, dep_type, dependencies, bufnr)
  if dep_type == "outdated" and result.stdout then
    local ok, data = pcall(vim.json.decode, result.stdout)
    if ok and type(data) == "table" then
      local function drop_missing_current(tbl)
        for name, info in pairs(tbl) do
          if type(info) == "table" and info.current == nil then
            tbl[name] = nil
          end
        end
      end
      drop_missing_current(data)
      if type(data.dependencies) == "table" then
        drop_missing_current(data.dependencies)
      end
      result = vim.tbl_extend("force", result, { stdout = vim.json.encode(data) })
    end
  end
  return orig_handle_npm_results(result, dep_type, dependencies, bufnr)
end

-- The default autocmd runs npm commands from Neovim's cwd, so inner
-- package.json files in a monorepo get no results. Replace it with an
-- autocmd that runs npm from the buffer's own directory.
pcall(vim.api.nvim_del_augroup_by_name, "npm-info")

local group = vim.api.nvim_create_augroup("npm-info-monorepo", { clear = true })
local checks = {}
local REFRESH_MS = 2 * 60 * 1000

vim.api.nvim_create_autocmd("BufWipeout", {
  group = group,
  callback = function(event)
    checks[event.buf] = nil
  end,
})

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
  group = group,
  pattern = "package.json",
  callback = function(event)
    local bufnr = event.buf
    local path = vim.api.nvim_buf_get_name(bufnr)
    local stat = vim.uv.fs_stat(path)
    local mtime = stat and stat.mtime and (stat.mtime.sec .. ":" .. stat.mtime.nsec) or ""
    local previous = checks[bufnr]
    local now = vim.uv.now()
    if
      event.event == "BufEnter"
      and previous
      and previous.mtime == mtime
      and now - previous.checked_at < REFRESH_MS
    then
      return
    end

    local check = { mtime = mtime, checked_at = now, tick = vim.api.nvim_buf_get_changedtick(bufnr) }
    checks[bufnr] = check
    vim.api.nvim_buf_clear_namespace(bufnr, core.namespace, 0, -1)

    local ok, dependencies = pcall(core.parse_dependencies, bufnr)
    if not ok then
      checks[bufnr] = nil
      return
    end
    if #dependencies == 0 then
      return
    end

    local cwd = vim.fs.dirname(path)
    local user_config = cfg.get()

    local function show_result(out, kind)
      vim.schedule(function()
        if
          vim.api.nvim_buf_is_valid(bufnr)
          and checks[bufnr] == check
          and vim.api.nvim_buf_get_changedtick(bufnr) == check.tick
        then
          core.handle_npm_results(out, kind, dependencies, bufnr)
        end
      end)
    end

    if user_config.show_installed then
      vim.system({ "npm", "list", "--json", "--depth=0" }, { cwd = cwd }, function(out)
        show_result(out, "list")
      end)
    end

    vim.system({ "npm", "outdated", "--json" }, { cwd = cwd }, function(out)
      show_result(out, "outdated")
    end)
  end,
})
