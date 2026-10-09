local M = {}

---@param controller CssInJsController
---@param adapter CssInJsAdapter
---@return CssInJsSource
function M.new(controller, adapter)
  local source = {}
  ---@return boolean
  function source:enabled()
    return controller.supports_buffer(adapter.current().bufnr)
  end
  ---@return string[]
  function source:get_trigger_characters()
    return controller.configuration().trigger_characters
  end
  ---@param ctx CssInJsContext
  ---@param callback fun(response: CssInJsResponse): nil
  ---@return CssInJsCancel?
  function source:get_completions(ctx, callback)
    return controller.complete(ctx, callback)
  end
  return source
end

---@param controller CssInJsController
---@param adapter CssInJsAdapter
---@param ctx CssInJsContext
---@param items CssInJsItem[]
---@return CssInJsItem[]
function M.filter(controller, adapter, ctx, items)
  local names = controller.configuration().suppressed_lsp_clients
  if #names == 0 then
    return items
  end
  if not controller.context(ctx.bufnr, ctx.cursor[1] - 1, ctx.cursor[2]) or not controller.ready(ctx.bufnr) then
    return items
  end
  local suppressed = {}
  for _, name in ipairs(names) do
    suppressed[name] = true
  end
  local result = {}
  for _, item in ipairs(items) do
    local name = item.client_id and adapter.client_name(item.client_id) or nil
    if not name or not suppressed[name] then
      result[#result + 1] = item
    end
  end
  return result
end

return M
