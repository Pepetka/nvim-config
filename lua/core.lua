-- ═══════════════════════════════════════════════════════════════
--  Autocommands
-- ═══════════════════════════════════════════════════════════════
vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight when yanking (copying) text",
  callback = function()
    vim.hl.on_yank()
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  pattern = "qf",
  callback = function(args)
    vim.keymap.set("n", "q", "<cmd>close<cr>", {
      buffer = args.buf,
      silent = true,
      desc = "General: Close quickfix window",
    })
  end,
})

-- ═══════════════════════════════════════════════════════════════
--  Quickfix formatter: show only filenames for LSP references
-- ═══════════════════════════════════════════════════════════════
---Return only the filename for LSP references lists; coordinates and
---context are visible in the nvim-bqf preview.
---@param info table
---@return string[]
_G.user_qf_textfunc = function(info)
  local list
  if info.quickfix == 1 then
    list = vim.fn.getqflist({ id = info.id, items = 0, title = 1 })
  else
    list = vim.fn.getloclist(info.winid or 0, { id = info.id, items = 0, title = 1 })
  end

  if list.title ~= "References" then
    return {}
  end

  local lines = {}
  local start_idx = info.start_idx or 1
  local end_idx = info.end_idx or #list.items
  for i = start_idx, end_idx do
    local item = list.items[i]
    if item then
      local name = item.bufnr > 0 and vim.api.nvim_buf_get_name(item.bufnr) or item.filename
      table.insert(lines, vim.fn.fnamemodify(name, ":t"))
    end
  end
  return lines
end

vim.o.qftf = "v:lua.user_qf_textfunc"

local BIGFILE_SIZE = 1.5 * 1024 * 1024
local BIGFILE_LINE_LENGTH = 1000
local saved_spell = {}

local function disable_bigfile_features(buf)
  if not vim.b[buf].bigfile then
    vim.b[buf].bigfile = true
    vim.b[buf].minianimate_disable = true
    vim.b[buf].completion = false
    vim.b[buf].matchparen_timeout = 1
    vim.b[buf].matchparen_insert_timeout = 1

    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.treesitter.stop(buf)
        vim.bo[buf].syntax = vim.bo[buf].filetype
      end
    end)

    vim.notify("Big file detected. Heavy features disabled.", vim.log.levels.INFO)
  end

  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if saved_spell[win] == nil then
      saved_spell[win] = vim.wo[win].spell
    end
    vim.wo[win].spell = false
  end
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    vim.lsp.buf_detach_client(buf, client.id)
  end
end

vim.api.nvim_create_autocmd("BufReadPre", {
  desc = "Detect large files before heavy features start",
  callback = function(args)
    local stats = vim.uv.fs_stat(args.file)
    if stats and stats.size > BIGFILE_SIZE then
      disable_bigfile_features(args.buf)
    end
  end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
  desc = "Detect long lines in files",
  callback = function(args)
    if vim.b[args.buf].bigfile then
      return
    end
    local stats = vim.uv.fs_stat(args.file)
    local line_count = vim.api.nvim_buf_line_count(args.buf)
    if stats and line_count > 0 and stats.size / line_count > BIGFILE_LINE_LENGTH then
      disable_bigfile_features(args.buf)
    end
  end,
})

vim.api.nvim_create_autocmd("BufWinEnter", {
  desc = "Keep spell checking disabled in big-file windows",
  callback = function(args)
    if vim.b[args.buf].bigfile then
      disable_bigfile_features(args.buf)
    end
  end,
})

vim.api.nvim_create_autocmd("BufWinLeave", {
  desc = "Restore spell checking after leaving a big file",
  callback = function(args)
    local win = vim.api.nvim_get_current_win()
    if vim.b[args.buf].bigfile and saved_spell[win] ~= nil then
      vim.wo[win].spell = saved_spell[win]
      saved_spell[win] = nil
    end
  end,
})

vim.api.nvim_create_autocmd("LspAttach", {
  desc = "Detach LSP clients that attach to big files",
  callback = function(args)
    if vim.b[args.buf].bigfile then
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(args.buf) then
          vim.lsp.buf_detach_client(args.buf, args.data.client_id)
        end
      end)
    end
  end,
})

vim.api.nvim_create_autocmd("BufWritePre", {
  desc = "Create missing parent directories before saving",
  pattern = "*",
  group = vim.api.nvim_create_augroup("auto_create_dir", { clear = true }),
  callback = function(ctx)
    local dir = vim.fn.fnamemodify(ctx.file, ":p:h")
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, "p")
    end
  end,
})

local auto_read_group = vim.api.nvim_create_augroup("auto_read", { clear = true })

vim.api.nvim_create_autocmd("FileChangedShellPost", {
  desc = "Notify when buffer is reloaded from disk",
  pattern = "*",
  group = auto_read_group,
  callback = function()
    vim.notify("File changed on disk. Buffer reloaded!", vim.log.levels.WARN)
  end,
})

vim.api.nvim_create_autocmd({ "FocusGained", "CursorHold" }, {
  desc = "Check for external file changes",
  pattern = "*",
  group = auto_read_group,
  callback = function()
    if vim.fn.getcmdwintype() == "" then
      vim.cmd("checktime")
    end
  end,
})

vim.api.nvim_create_autocmd("VimResized", {
  desc = "Resize windows equally when terminal is resized",
  group = vim.api.nvim_create_augroup("win_autoresize", { clear = true }),
  command = "wincmd =",
})

vim.api.nvim_create_autocmd("BufEnter", {
  desc = "Quit nvim if only one special window is left",
  pattern = "*",
  group = vim.api.nvim_create_augroup("auto_close_win", { clear = true }),
  callback = function()
    local quit_filetypes = { "qf", "NvimTree" }
    local wins = vim.api.nvim_tabpage_list_wins(0)

    if #wins ~= 1 then
      return
    end

    local buf = vim.api.nvim_win_get_buf(wins[1])
    local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })

    if vim.tbl_contains(quit_filetypes, ft) then
      vim.cmd("qall")
    end
  end,
})

-- ═══════════════════════════════════════════════════════════════
--  User commands
-- ═══════════════════════════════════════════════════════════════
vim.api.nvim_create_user_command("PackClean", function()
  local to_delete = {}
  for _, p in ipairs(vim.pack.get()) do
    if not p.active then
      table.insert(to_delete, p.spec.name)
    end
  end

  if #to_delete == 0 then
    vim.notify("No unused plugins to clean", vim.log.levels.INFO)
    return
  end

  vim.pack.del(to_delete, { force = true })
end, { desc = "Remove unused vim.pack plugins" })

vim.api.nvim_create_user_command("PackUpdate", function(opts)
  local names = {}
  if opts.args and opts.args ~= "" then
    names = vim.split(opts.args, "%s+")
  end
  vim.pack.update(#names > 0 and names or nil, { force = opts.bang, offline = false })
end, { desc = "Update vim.pack plugins", nargs = "*", bang = true })

-- ═══════════════════════════════════════════════════════════════
--  LSP commands
-- ═══════════════════════════════════════════════════════════════
local function get_clients_by_name(name)
  local clients = vim.lsp.get_clients()
  if not name or name == "" then
    return clients
  end
  return vim.tbl_filter(function(client)
    return client.name == name
  end, clients)
end

vim.api.nvim_create_user_command("LspRestart", function(opts)
  local name = opts.args ~= "" and opts.args or nil
  local clients = get_clients_by_name(name)
  if #clients == 0 then
    vim.notify("No LSP clients to restart" .. (name and " (" .. name .. ")" or ""), vim.log.levels.WARN)
    return
  end
  for _, client in ipairs(clients) do
    client:stop(true)
    vim.lsp.enable(client.name, true)
  end
  vim.notify("LSP restarted" .. (name and " (" .. name .. ")" or ""), vim.log.levels.INFO)
end, { desc = "Restart LSP client(s)", nargs = "?", complete = "shellcmd" })

vim.api.nvim_create_user_command("LspStop", function(opts)
  local name = opts.args ~= "" and opts.args or nil
  local clients = get_clients_by_name(name)
  if #clients == 0 then
    vim.notify("No LSP clients to stop" .. (name and " (" .. name .. ")" or ""), vim.log.levels.WARN)
    return
  end
  for _, client in ipairs(clients) do
    client:stop()
  end
  vim.notify("LSP stopped" .. (name and " (" .. name .. ")" or ""), vim.log.levels.INFO)
end, { desc = "Stop LSP client(s)", nargs = "?", complete = "shellcmd" })

vim.api.nvim_create_user_command("LspStart", function(opts)
  local name = opts.args ~= "" and opts.args or nil
  if not name then
    vim.notify("LSP server name required", vim.log.levels.WARN)
    return
  end
  vim.lsp.enable(name, true)
  vim.notify("LSP started (" .. name .. ")", vim.log.levels.INFO)
end, { desc = "Start LSP server", nargs = "?" })

vim.api.nvim_create_user_command("TsLspSwitch", function()
  require("utils.ts_lsp").switch()
end, { desc = "Switch TypeScript LSP for the current project" })

vim.api.nvim_create_user_command("TsLspAuto", function()
  require("utils.ts_lsp").auto()
end, { desc = "Restore automatic TypeScript LSP selection for the current project" })

vim.api.nvim_create_user_command("TsLspInfo", function()
  require("utils.ts_lsp").info()
end, { desc = "Show the TypeScript LSP choice for the current project" })
