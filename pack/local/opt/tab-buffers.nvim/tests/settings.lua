local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path
vim.o.swapfile, vim.o.hidden = false, true
local support = require("support")
local test, equal = support.test, support.equal
local api = vim.api
local buffers, panel = require("tab_buffers"), require("tab_buffers.tabline")
local sequence = 0

---@return integer
local function named()
  sequence = sequence + 1
  local buf = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(buf, "/private/tmp/tab-buffers-settings-" .. sequence .. ".lua")
  return buf
end

---@param opts? TabBuffersSetupOptions
---@return integer
local function reset(opts)
  panel.teardown()
  buffers.teardown()
  vim.cmd("tabonly!")
  vim.cmd("only!")
  local buf = named()
  api.nvim_set_current_buf(buf)
  for _, old in ipairs(api.nvim_list_bufs()) do
    if old ~= buf then
      api.nvim_buf_delete(old, { force = true })
    end
  end
  buffers.setup(opts)
  return buf
end

test("native navigation uses configured wrap and explicit override", function()
  local first = reset({ wrap = false })
  local second = named()
  buffers.add(second)
  equal(buffers.previous(), nil)
  equal(buffers.previous({ wrap = true }), second)
  equal(api.nvim_get_current_buf(), second)
  equal(buffers.next(), nil)
  equal(buffers.next({ wrap = true }), first)
end)

test("native left and last-used replacements preserve the configured history", function()
  for _, policy in ipairs({ "left", "last_used" }) do
    local first = reset({ replacement = policy })
    local second, third, fourth = named(), named(), named()
    buffers.add(second)
    buffers.add(third)
    buffers.add(fourth)
    buffers.open(fourth)
    buffers.open(second)
    buffers.close()
    equal(api.nvim_get_current_buf(), policy == "left" and first or fourth)
  end
end)

test("disabled hidden bootstrap still adopts visible files and explicit additions", function()
  local first = reset()
  buffers.teardown()
  local hidden = named()
  buffers.setup({ bootstrap_hidden_buffers = false })
  equal(buffers.buffers(), { first })
  assert(buffers.add(hidden))
  equal(buffers.buffers(), { first, hidden })
end)

test("keeping an empty special-only inactive tab creates its placeholder in that tab", function()
  reset({ close_empty_tab = false })
  local source, focus = api.nvim_get_current_tabpage(), api.nvim_get_current_win()
  local source_count = #api.nvim_tabpage_list_wins(source)
  vim.cmd.tabnew()
  local target = api.nvim_get_current_tabpage()
  local member = named()
  api.nvim_set_current_buf(member)
  buffers.refresh()
  local special = api.nvim_create_buf(false, true)
  api.nvim_set_current_buf(special)
  api.nvim_set_current_tabpage(source)
  local report = buffers.close({ tab = target, buf = member })
  equal(report.closed, { member })
  equal(report.tab_closed, false)
  assert(api.nvim_tabpage_is_valid(target))
  equal(#api.nvim_tabpage_list_wins(target), 2)
  equal(#api.nvim_tabpage_list_wins(source), source_count)
  equal(api.nvim_get_current_win(), focus)
  equal(api.nvim_win_get_buf(api.nvim_tabpage_list_wins(target)[1]), special)
  assert(buffers.close_tab({ tab = target }).tab_closed)
end)

test("native filters release modified files and cannot enroll special buffers or reviews", function()
  local first = reset()
  api.nvim_buf_set_lines(first, 0, -1, false, { "unsaved" })
  buffers.setup({
    buffer_filter = function(buf)
      return buf ~= first
    end,
  })
  equal(buffers.buffers(), {})
  assert(api.nvim_buf_is_valid(first) and vim.bo[first].modified)
  buffers.setup({
    buffer_filter = function()
      return true
    end,
  })
  assert(buffers.contains(first))
  local tab = api.nvim_get_current_tabpage()
  buffers.setup({
    tab_filter = function()
      return false
    end,
  })
  equal(buffers.close({ buf = first }).closed, {})
  assert(api.nvim_buf_is_valid(first))
  vim.t[tab].tab_buffers_excluded = true
  buffers.setup({
    tab_filter = function()
      return true
    end,
  })
  equal(buffers.add(first), false)
  vim.t[tab].tab_buffers_excluded = nil
  buffers.refresh()
  local special = api.nvim_create_buf(true, false)
  vim.bo[special].buftype = "nofile"
  equal(buffers.add(special), false)
end)

test("native visibility modes support single buffers and hidden filetype overrides", function()
  local buf = reset()
  panel.setup({ visibility = "always", tab_width_ratio = 0.5 })
  equal(vim.o.showtabline, 2)
  panel.setup({ visibility = "never" })
  equal(vim.o.showtabline, 0)
  panel.setup({ visibility = "auto" })
  equal(vim.o.showtabline, 0)
  vim.bo[buf].filetype = "dashboard"
  panel.setup({ visibility = "always", hide_filetypes = { "dashboard" } })
  equal(vim.o.showtabline, 0)
end)

support.run("tab-buffers settings")
panel.teardown()
buffers.teardown()
