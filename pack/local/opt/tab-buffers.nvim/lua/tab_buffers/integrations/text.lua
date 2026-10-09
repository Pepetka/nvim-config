local M = {}
---@type TabBuffersTextMetrics
M.metrics = {
  measure = function(text)
    return vim.fn.strdisplaywidth(text)
  end,
  length = function(text)
    return vim.fn.strchars(text, true)
  end,
  suffix = function(text, first)
    return vim.fn.strcharpart(text, first, vim.fn.strchars(text, true), true)
  end,
}
return M
