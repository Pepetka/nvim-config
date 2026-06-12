---@class MapOpts : vim.keymap.set.Opts
---@field desc string
---@field buffer? integer

---Builds a keymap options table with sensible defaults.
---@param desc string Keymap description
---@param params? vim.keymap.set.Opts Optional overrides
---@return MapOpts
local function map_opts(desc, params)
  params = params or {}
  local result = {
    desc = desc,
    noremap = params.noremap == nil and true or params.noremap,
    silent = params.silent == nil and true or params.silent,
    expr = params.expr == nil and false or params.expr,
  }
  for k, v in pairs(params) do
    if result[k] == nil then
      result[k] = v
    end
  end
  return result
end

return map_opts
