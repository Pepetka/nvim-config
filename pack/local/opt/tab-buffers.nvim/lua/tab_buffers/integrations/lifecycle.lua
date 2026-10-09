local api = vim.api
local M = {}
local sequence = 0

---@param callbacks TabBuffersCallbacks
---@return fun(): nil
function M.install(callbacks)
  sequence = sequence + 1
  local group = api.nvim_create_augroup("TabBuffersNvim" .. sequence, { clear = true })
  local ok, err = pcall(function()
    api.nvim_create_autocmd({
      "BufEnter",
      "BufWinEnter",
      "TabEnter",
      "TabNewEntered",
      "WinEnter",
      "WinClosed",
      "FileType",
      "TabClosed",
    }, { group = group, callback = callbacks.changed })
    api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
      group = group,
      callback = function(args)
        if callbacks.text then
          callbacks.text(args.buf)
        else
          callbacks.changed()
        end
      end,
    })
    api.nvim_create_autocmd({ "BufDelete", "BufWipeout", "BufFilePost", "BufWritePost", "BufModifiedSet", "BufAdd" }, {
      group = group,
      callback = function(args)
        if callbacks.buffer then
          callbacks.buffer(args.buf)
        else
          callbacks.changed()
        end
      end,
    })
    api.nvim_create_autocmd("OptionSet", {
      group = group,
      pattern = { "buflisted", "buftype", "previewwindow" },
      callback = callbacks.changed,
    })
    api.nvim_create_autocmd("User", {
      group = group,
      pattern = "TabBuffersContextChanged",
      callback = callbacks.changed,
    })
    api.nvim_create_autocmd("TabClosedPre", { group = group, callback = callbacks.closing })
    api.nvim_create_autocmd("VimLeavePre", { group = group, callback = callbacks.exiting })
  end)
  if not ok then
    pcall(api.nvim_del_augroup_by_id, group)
    error(err, 0)
  end
  local alive = true
  return function()
    if alive then
      alive = false
      pcall(api.nvim_del_augroup_by_id, group)
    end
  end
end

return M
