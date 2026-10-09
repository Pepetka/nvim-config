local api = vim.api
local buffers = require("tab_buffers")
local M = {}
local review_rules = require("tab_buffers.core.reviews")
local views = review_rules.new()

---Whether a tab is an observed Diffview or file-history review.
---@param tab integer
---@return boolean
function M.is_review(tab)
  return api.nvim_tabpage_is_valid(tab) and views.get(tab) ~= nil
end

---@return nil
local function changed()
  api.nvim_exec_autocmds("User", { pattern = "TabBuffersContextChanged", modeline = false })
end

---Pass these public hooks to diffview.setup(). Review tabs are owned by Diffview.
---@return TabBuffersDiffviewHooks
function M.hooks()
  ---@param view TabBuffersReview
  ---@return nil
  local function observe(view)
    local tab = view.tabpage
    if tab and api.nvim_tabpage_is_valid(tab) then
      local previous = views.get(tab)
      local claimed = views.observe(tab, view, vim.t[tab].tab_buffers_excluded)
      if claimed then
        vim.t[tab].tab_buffers_excluded = true
      end
      if claimed or previous ~= view then
        changed()
      end
    end
  end
  return {
    view_opened = observe,
    view_enter = observe,
    view_post_layout = observe,
    view_closed = function(view)
      local tab = view.tabpage
      if not tab then
        return
      end
      if views.get(tab) ~= view then
        return
      end
      local valid = api.nvim_tabpage_is_valid(tab)
      local current = valid and vim.t[tab].tab_buffers_excluded or nil
      local restore, original = views.close(tab, view, current)
      if valid then
        if restore then
          vim.t[tab].tab_buffers_excluded = original
        end
        changed()
      end
    end,
  }
end

---@param new_tab boolean
---@return integer?, string?
local function go(new_tab)
  views.prune(api.nvim_tabpage_is_valid)
  local view = views.get(api.nvim_get_current_tabpage())
  if not view then
    -- Diffview attaches buffer-local mappings to local files reused in ordinary tabs.
    vim.cmd.normal({ new_tab and "\23gf" or "gf", bang = true })
    return
  end
  if not view.infer_cur_file then
    return nil, "Review does not support local file navigation"
  end
  local file = view:infer_cur_file()
  if not file then
    return
  end
  if vim.fn.filereadable(file.absolute_path) ~= 1 then
    return nil, "File does not exist on disk: " .. file.absolute_path
  end
  local cursor
  if file == view.cur_entry and view.cur_layout then
    local win = view.cur_layout:get_main_win().id
    if api.nvim_win_is_valid(win) then
      cursor = api.nvim_win_get_cursor(win)
    end
  end
  ---@param tab? integer
  ---@return boolean
  local function available(tab)
    return tab ~= nil
      and api.nvim_tabpage_is_valid(tab)
      and vim.t[tab].tab_buffers_excluded ~= true
      and not views.get(tab)
  end
  local target
  if not new_tab then
    local tabs = api.nvim_list_tabpages()
    local previous = tabs[vim.fn.tabpagenr("#")]
    target = review_rules.destination(tabs, previous, available)
  end
  local buf = vim.fn.bufadd(file.absolute_path)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  if not target then
    vim.cmd.tabnew()
    target = api.nvim_get_current_tabpage()
  end
  local _, err = buffers.add(buf, { tab = target })
  if err then
    return nil, err
  end
  local opened, message = buffers.open(buf, { tab = target })
  if opened and cursor then
    local line = math.min(cursor[1], api.nvim_buf_line_count(buf))
    local text = api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
    api.nvim_win_set_cursor(0, { line, math.min(cursor[2], #text) })
  end
  return opened, message
end

---@param new_tab boolean
---@return integer?, string?
local function navigate(new_tab)
  local ok, buf, err = pcall(go, new_tab)
  if not ok then
    err, buf = tostring(buf), nil
  end
  if err then
    vim.notify(err, vim.log.levels.WARN, { title = "tab-buffers" })
  end
  return buf, err
end

---@return integer?, string?
function M.goto_file()
  return navigate(false)
end

---@return integer?, string?
function M.goto_file_tab()
  return navigate(true)
end

return M
