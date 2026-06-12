local scope = require("scope")
local core = require("scope.core")
local buffer_utils = require("utils.scope_buffers")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")

vim.api.nvim_create_autocmd("BufEnter", {
  group = vim.api.nvim_create_augroup("ScopeEmptyBufferCleanup", {}),
  callback = buffer_utils.cleanup_empty_buffers,
})

local config = {
  restore_state = true,
  hooks = {
    pre_tab_close = function()
      buffer_utils.close_buffers_in_closed_tab(core)
    end,
    post_tab_enter = function()
      vim.cmd("redrawtabline")
    end,
    post_tab_leave = function()
      vim.cmd("redrawtabline")
    end,
  },
}
scope.setup(config)

-- ═══════════════════════════════════════════════════════════════
--  Global keymaps
-- ═══════════════════════════════════════════════════════════════
local function opts(desc)
  return map_opts("Buffer: " .. desc)
end

map("n", "<leader>x", function()
  buffer_utils.smart_close_buffer(core)
end, opts("Delete current buffer (scope-aware)"))

map("n", "<leader>cx", function()
  buffer_utils.close_all_except_current(core)
end, opts("Close all except current"))
