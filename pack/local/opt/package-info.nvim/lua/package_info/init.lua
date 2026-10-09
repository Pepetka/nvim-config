local controller = require("package_info.controller").new(require("package_info.integrations.nvim").new())
return {
  setup = controller.setup,
  teardown = controller.teardown,
  refresh = controller.refresh,
  info = controller.info,
  status = controller.status,
}
