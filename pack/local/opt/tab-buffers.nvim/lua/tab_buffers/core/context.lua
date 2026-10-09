local M = {}

---@param buf TabBuffersBufferFacts
---@return boolean
function M.basic(buf)
  return buf.valid and buf.listed and buf.buftype == ""
end

---@param buf TabBuffersBufferFacts
---@param owned boolean
---@return boolean
function M.eligible(buf, owned)
  return M.basic(buf) and (owned or buf.name ~= "" or buf.modified or buf.loaded and buf.has_text)
end

---@param tab TabBuffersTabFacts
---@return boolean
function M.managed(tab)
  return tab.valid and not tab.excluded
end

---@param win TabBuffersWindowFacts
---@return boolean
function M.ordinary(win)
  return win.valid and not win.floating and not win.external and not win.preview
end

---@param win TabBuffersWindowFacts
---@return boolean
function M.working(win)
  return M.ordinary(win) and win.managed
end

return M
