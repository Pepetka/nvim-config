local M = {
  callbacks = {},
}

function M.register(name, fn)
  M.callbacks[name] = fn
end

function M.apply_all()
  for name, fn in pairs(M.callbacks) do
    local ok, err = pcall(fn)
    if not ok then
      vim.notify("Theme highlight update failed for " .. name .. ": " .. err, vim.log.levels.ERROR)
    end
  end
end

return M
