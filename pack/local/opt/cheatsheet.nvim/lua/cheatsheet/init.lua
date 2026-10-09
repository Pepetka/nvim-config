local controller = require("cheatsheet.controller").new(require("cheatsheet.integrations.nvim").new())

---@type CheatsheetAPI
local api = {
  setup = controller.setup,
  show = controller.show,
  hide = controller.hide,
  toggle = controller.toggle,
  next_mode = controller.next_mode,
  prev_mode = controller.prev_mode,
}

return api
