local adapter = require("css_in_js.integrations.nvim").new()
local controller = require("css_in_js.controller").new(adapter)
local blink = require("css_in_js.integrations.blink")
local config = require("css_in_js.core.config")
local treesitter = require("css_in_js.integrations.treesitter")
local M = {}
M.setup = controller.setup
M.teardown = controller.teardown
M.supports_buffer = controller.supports_buffer
M.hover = controller.hover

---@return CssInJsSource
function M.new()
  return blink.new(controller, adapter)
end

---@param buf integer
---@param row integer
---@param col integer
---@return CssInJsPublicRegion?
function M.context(buf, row, col)
  if not config.integer(row) or not config.integer(col) or not controller.supports_buffer(buf) then
    return nil
  end
  local ok, result = pcall(treesitter.context, buf, row, col)
  return ok and result or nil
end

---@param ctx CssInJsContext
---@param items CssInJsItem[]
---@return CssInJsItem[]
function M.filter_lsp_items(ctx, items)
  return blink.filter(controller, adapter, ctx, items)
end

return M
