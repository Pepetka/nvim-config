local controller = require("dashboard.controller").new(require("dashboard.integrations.nvim").new())

---@type DashboardAPI
local api = {
  setup = controller.setup,
  show = controller.show,
  hide = controller.hide,
  refresh = controller.refresh,
  teardown = controller.teardown,
}

return api
