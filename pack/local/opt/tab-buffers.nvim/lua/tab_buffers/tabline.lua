---@type TabBuffersTabline
local api = require("tab_buffers.tabline.controller").new(
  require("tab_buffers.integrations.tabline").new(),
  require("tab_buffers")
)
return api
