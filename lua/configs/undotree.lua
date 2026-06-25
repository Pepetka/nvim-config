local map = vim.keymap.set
local map_opts = require("utils.map_opts")

vim.cmd("packadd nvim.undotree")

local function opts(desc, buffer)
  return map_opts("General: " .. desc, { buffer = buffer })
end

local M = {}

local default_opts = {
  command = "botright 35vnew",
  title = function(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    return string.format("Undo tree: %s", vim.fn.fnamemodify(name, ":."))
  end,
}

local excluded_filetypes = {
  "NvimTree",
  "dashboard",
  "terminal",
  "qf",
  "help",
  "prompt",
  "noice",
  "notify",
  "Trouble",
  "trouble",
  "nvim-undotree",
  "dap-view",
}

---@param opts table?
---@return nil
function M.open(opts)
  local ft = vim.bo.filetype
  if vim.tbl_contains(excluded_filetypes, ft) then
    vim.notify("Undotree is disabled in " .. ft .. " buffers", vim.log.levels.WARN)
    return
  end
  opts = vim.tbl_deep_extend("force", default_opts, opts or {})
  return require("undotree").open(opts)
end

---@return boolean
function M.close()
  local buf = vim.api.nvim_get_current_buf()
  local win = vim.b[buf].nvim_undotree or vim.b[buf].nvim_is_undotree
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
    return true
  end
  return false
end

---@param opts table?
---@return nil
function M.toggle(opts)
  local closed = M.close()
  if not closed then
    M.open(opts)
  end
end

local group = vim.api.nvim_create_augroup("nvim_undotree_local", { clear = true })

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "nvim-undotree",
  callback = function()
    vim.opt_local.number = false
    vim.opt_local.relativenumber = false
    vim.opt_local.signcolumn = "no"
    vim.opt_local.cursorline = true
    vim.opt_local.wrap = false
    vim.opt_local.foldenable = false

    map("n", "q", function()
      M.close()
    end, opts("Close undotree window"))

    map("n", "<CR>", function()
      M.close()
    end, opts("Apply untotree state and close"))
  end,
})

-- ═══════════════════════════════════════════════════════════════
--  Global keymaps
-- ═══════════════════════════════════════════════════════════════
map("n", "<leader>ut", function()
  M.toggle()
end, opts("Toggle undotree"))

return M
