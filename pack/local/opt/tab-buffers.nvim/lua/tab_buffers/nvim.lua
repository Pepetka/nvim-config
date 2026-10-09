---Compatibility factory for independent Neovim-backed instances.
local M = {}
---@return TabBuffers
function M.new()
  return require("tab_buffers.controller").new(require("tab_buffers.integrations.nvim").new())
end
return M
