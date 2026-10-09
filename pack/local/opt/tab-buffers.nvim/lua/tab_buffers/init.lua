---@type TabBuffers
local api = require("tab_buffers.controller").new(require("tab_buffers.integrations.nvim").new())
return api
