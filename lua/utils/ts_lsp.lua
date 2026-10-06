local M = {}

local root_markers = {
  "package.json",
  "tsconfig.json",
  "jsconfig.json",
  "pnpm-lock.yaml",
  "yarn.lock",
  "package-lock.json",
  "bun.lock",
  "bun.lockb",
  ".git",
}

local overrides = {}
local project_cache = {}
local CACHE_MS = 30 * 1000

local function read_json(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  local decoded, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  return decoded and type(data) == "table" and data or nil
end

local function project_dirs(root)
  local dirs = {}
  local git_root = vim.fs.root(root, { ".git" })
  local dir = root
  while dir do
    dirs[#dirs + 1] = dir
    if dir == (git_root or root) then
      break
    end
    local parent = vim.fs.dirname(dir)
    if parent == dir then
      break
    end
    dir = parent
  end
  return dirs
end

function M.root(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name ~= "" and vim.fs.root(name, { root_markers }) or nil
end

local function native_project_command(root)
  for _, dir in ipairs(project_dirs(root)) do
    local tsc = vim.fs.joinpath(dir, "node_modules", ".bin", "tsc")
    local resolved_tsc = vim.uv.fs_realpath(tsc)
    local typescript = resolved_tsc
      and read_json(vim.fs.joinpath(vim.fs.dirname(vim.fs.dirname(resolved_tsc)), "package.json"))
    if not typescript then
      typescript = read_json(vim.fs.joinpath(dir, "node_modules", "typescript", "package.json"))
    end
    if
      typescript
      and typescript.name == "typescript"
      and type(typescript.version) == "string"
      and typescript.version:match("^7%.")
      and vim.fn.executable(tsc) == 1
    then
      return tsc
    end

    local tsgo = vim.fs.joinpath(dir, "node_modules", ".bin", "tsgo")
    if vim.fn.executable(tsgo) == 1 then
      return tsgo
    end
  end
end

local function available_command(local_command)
  local command = local_command
  if not command then
    local mason_bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin")
    for _, name in ipairs({ "tsc", "tsgo" }) do
      local path = vim.fs.joinpath(mason_bin, name)
      if vim.fn.executable(path) == 1 then
        command = path
        break
      end
    end
  end
  if not command and vim.fn.executable("tsgo") == 1 then
    command = "tsgo"
  end
  return command and { command, "--lsp", "--stdio" } or nil
end

local function needs_tsserver_plugins(root)
  for _, dir in ipairs(project_dirs(root)) do
    for _, name in ipairs({ "svelte.config.js", "svelte.config.ts", "svelte.config.mjs", "svelte.config.cjs" }) do
      if vim.fn.filereadable(vim.fs.joinpath(dir, name)) == 1 then
        return true
      end
    end

    local package = read_json(vim.fs.joinpath(dir, "package.json"))
    if package then
      for _, section in ipairs({ "dependencies", "devDependencies", "peerDependencies", "optionalDependencies" }) do
        local dependencies = package[section]
        if type(dependencies) == "table" then
          if dependencies.svelte then
            return true
          end
        end
      end
    end
  end
  return false
end

local function inspect_project(root)
  local cached = project_cache[root]
  if cached then
    return cached
  end
  local local_command = native_project_command(root)
  cached = {
    command = available_command(local_command),
    automatic = needs_tsserver_plugins(root) and "vtsls" or (local_command and "tsgo" or "vtsls"),
    checked_at = vim.uv.now(),
  }
  project_cache[root] = cached
  return cached
end

function M.native_command(root)
  return inspect_project(root).command
end

function M.selected(root)
  local project = inspect_project(root)
  if overrides[root] then
    if overrides[root] == "tsgo" and not project.command then
      return "vtsls"
    end
    return overrides[root]
  end
  return project.automatic
end

function M.root_dir(server)
  return function(bufnr, on_dir)
    local root = M.root(bufnr)
    if root and M.selected(root) == server and (server ~= "tsgo" or M.native_command(root)) then
      on_dir(root)
    end
  end
end

local function restart_project_clients(root, old_server)
  for _, client in ipairs(vim.lsp.get_clients({ name = old_server })) do
    if client.config.root_dir == root then
      client:stop(true)
    end
  end
  vim.lsp.enable({ "vtsls", "tsgo" })
end

local function refresh_project(root, force)
  local old = project_cache[root]
  if not old or (not force and vim.uv.now() - old.checked_at < CACHE_MS) then
    return
  end

  local old_server = M.selected(root)
  project_cache[root] = nil
  local new_server = M.selected(root)
  local new_command = M.native_command(root)
  if old_server ~= new_server or (new_server == "tsgo" and not vim.deep_equal(old.command, new_command)) then
    restart_project_clients(root, old_server)
  end
end

function M.refresh_all()
  local roots = vim.tbl_keys(project_cache)
  for _, root in ipairs(roots) do
    refresh_project(root, true)
  end
end

vim.api.nvim_create_autocmd("BufEnter", {
  group = vim.api.nvim_create_augroup("TsLspProjectCache", { clear = true }),
  callback = function(args)
    local root = M.root(args.buf)
    if root then
      refresh_project(root, false)
    end
  end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  group = "TsLspProjectCache",
  pattern = { "package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb" },
  callback = function(args)
    local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(args.buf))
    for root in pairs(project_cache) do
      if vim.tbl_contains(project_dirs(root), dir) then
        refresh_project(root, true)
      end
    end
  end,
})

function M.switch()
  local root = M.root(0)
  if not root then
    vim.notify("No TypeScript project found for this buffer", vim.log.levels.WARN)
    return
  end

  local current = M.selected(root)
  local next_server = current == "vtsls" and "tsgo" or "vtsls"
  if next_server == "tsgo" and not M.native_command(root) then
    vim.notify("Native TypeScript server is unavailable in this project", vim.log.levels.WARN)
    return
  end

  overrides[root] = next_server
  restart_project_clients(root, current)
  vim.notify("TypeScript LSP for " .. root .. ": " .. next_server .. " (manual)", vim.log.levels.INFO)
end

function M.auto()
  local root = M.root(0)
  if not root then
    vim.notify("No TypeScript project found for this buffer", vim.log.levels.WARN)
    return
  end

  local current = M.selected(root)
  local old_command = M.native_command(root)
  overrides[root] = nil
  project_cache[root] = nil
  local selected = M.selected(root)
  if current ~= selected or (selected == "tsgo" and not vim.deep_equal(old_command, M.native_command(root))) then
    restart_project_clients(root, current)
  end
  vim.notify("TypeScript LSP for " .. root .. ": " .. selected .. " (auto)", vim.log.levels.INFO)
end

function M.info()
  local root = M.root(0)
  if not root then
    vim.notify("No TypeScript project found for this buffer", vim.log.levels.WARN)
    return
  end
  local command = M.native_command(root)
  vim.notify(
    string.format(
      "TypeScript LSP: %s (%s)\nProject: %s\nNative command: %s",
      M.selected(root),
      overrides[root] and "manual" or "auto",
      root,
      command and command[1] or "unavailable"
    ),
    vim.log.levels.INFO
  )
end

return M
