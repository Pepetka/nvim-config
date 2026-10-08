local api = vim.api
local buffers = require("tab_buffers")
local M = {}
local views = {}

---Whether a tab is an observed Diffview or file-history review.
---@param tab integer
---@return boolean
function M.is_review(tab)
  return api.nvim_tabpage_is_valid(tab) and views[tab] ~= nil
end

local function changed()
  api.nvim_exec_autocmds("User", { pattern = "TabBuffersContextChanged", modeline = false })
end

---Pass these public hooks to diffview.setup(). Review tabs are owned by Diffview.
---@return table<string, function>
function M.hooks()
  local function observe(view)
    local tab = view.tabpage
    if tab and api.nvim_tabpage_is_valid(tab) then
      views[tab] = view
      if vim.t[tab].tab_buffers_excluded ~= true then
        vim.t[tab].tab_buffers_excluded = true
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
      views[tab] = nil
      if api.nvim_tabpage_is_valid(tab) then
        vim.t[tab].tab_buffers_excluded = nil
        changed()
      end
    end,
  }
end

local function go(new_tab)
  local view = views[api.nvim_get_current_tabpage()]
  if not view then
    -- Diffview attaches buffer-local mappings to local files reused in ordinary tabs.
    vim.cmd.normal({ new_tab and "\23gf" or "gf", bang = true })
    return
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
  local function available(tab)
    return tab and api.nvim_tabpage_is_valid(tab) and vim.t[tab].tab_buffers_excluded ~= true and not views[tab]
  end
  local target
  if not new_tab then
    local tabs = api.nvim_list_tabpages()
    local previous = tabs[vim.fn.tabpagenr("#")]
    if available(previous) then
      target = previous
    else
      for _, tab in ipairs(tabs) do
        if available(tab) then
          target = tab
          break
        end
      end
    end
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

function M.goto_file()
  return navigate(false)
end

function M.goto_file_tab()
  return navigate(true)
end

return M
