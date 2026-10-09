---Compatibility wrapper using native Unicode screen-cell metrics.
local layout = require("tab_buffers.core.layout")
local metrics = require("tab_buffers.integrations.text").metrics
local M = { clean = layout.clean, labels = layout.labels }
---@param text string
---@param width integer
---@return string
function M.clip(text, width)
  return layout.clip(text, width, metrics)
end
---@generic T: TabBuffersTextItem
---@param items T[]
---@param anchor? integer
---@param width integer
---@return T[], string?, string?
function M.fit(items, anchor, width)
  return layout.fit(items, anchor, width, metrics)
end
return M
