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

local BIGFILE_SIZE = 1.5 * 1024 * 1024
local BIGFILE_LINE_LENGTH = 1000

vim.api.nvim_create_autocmd("BufReadPost", {
  desc = "Disable heavy features for big files",
  callback = function(args)
    local buf = args.buf
    local path = vim.api.nvim_buf_get_name(buf)
    if path == "" then
      return
    end

    local ok, stats = pcall(vim.uv.fs_stat, path)
    if not ok or not stats then
      return
    end

    local is_big = stats.size > BIGFILE_SIZE
    local line_count = vim.api.nvim_buf_line_count(buf)
    local is_long_lines = line_count > 0 and (stats.size / line_count) > BIGFILE_LINE_LENGTH
    if not is_big and not is_long_lines then
      return
    end

    vim.b[buf].bigfile = true
    vim.b[buf].minianimate_disable = true
    vim.b[buf].completion = false
    vim.b[buf].spell = false

    vim.api.nvim_create_autocmd("LspAttach", {
      buffer = buf,
      callback = function(ev)
        vim.schedule(function()
          vim.lsp.buf_detach_client(ev.buf, ev.data.client_id)
        end)
      end,
    })

    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        vim.treesitter.stop(buf)
        vim.bo[buf].syntax = vim.bo[buf].filetype
      end
    end)

    if vim.fn.exists(":NoMatchParen") ~= 0 then
      vim.cmd("NoMatchParen")
    end

    vim.notify("Big file detected. Heavy features disabled.", vim.log.levels.INFO)
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
