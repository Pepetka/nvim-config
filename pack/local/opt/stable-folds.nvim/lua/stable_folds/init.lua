local controller = require("stable_folds.controller").new(require("stable_folds.integrations.nvim").new())

---@type StableFoldsAPI
local api = {
  foldexpr = controller.foldexpr,
  setup = controller.setup,
  attach = controller.attach,
  expr = controller.expr,
  refresh = controller.refresh,
  teardown = controller.teardown,
}

return api
