local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path
vim.o.swapfile, vim.o.hidden = false, true
local support = require("support")
local test, equal = support.test, support.equal
local api = vim.api
local reads = { facts = 0, windows = 0, widths = 0, icons = 0, redraws = 0 }
local native = require("tab_buffers.integrations.nvim")
local create = native.new
---@diagnostic disable-next-line: duplicate-set-field
native.new = function()
  local adapter = create()
  local buffer, windows = adapter.buffer, adapter.tab_windows
  adapter.buffer = function(buf)
    reads.facts = reads.facts + 1
    return buffer(buf)
  end
  adapter.tab_windows = function(tab)
    reads.windows = reads.windows + 1
    return windows(tab)
  end
  return adapter
end
local styles = require("tab_buffers.integrations.tabline")
local create_panel = styles.new
---@diagnostic disable-next-line: duplicate-set-field
styles.new = function()
  local adapter = create_panel()
  local redraw = adapter.redraw
  adapter.redraw = function()
    reads.redraws = reads.redraws + 1
    redraw()
  end
  return adapter
end
local metrics = require("tab_buffers.integrations.text").metrics
local measure = metrics.measure
metrics.measure = function(text)
  reads.widths = reads.widths + 1
  return measure(text)
end
local original_icons = package.loaded["nvim-web-devicons"]
package.loaded["nvim-web-devicons"] = {
  get_icon = function()
    reads.icons = reads.icons + 1
    return "X"
  end,
}
local buffers = require("tab_buffers")
local panel = require("tab_buffers.tabline")
local first = api.nvim_get_current_buf()
api.nvim_buf_set_name(first, "/private/tmp/tab-buffers-optimization-main.lua")
local entries = { first }
for index = 1, 100 do
  local buf = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(buf, "/private/tmp/tab-buffers-optimization-" .. index .. ".lua")
  entries[#entries + 1] = buf
end
buffers.setup()
panel.setup()

---@return nil
local function settle()
  vim.wait(30, function()
    return false
  end)
end
---@return nil
local function reset()
  settle()
  for key in pairs(reads) do
    reads[key] = 0
  end
end

settle()
test("unchanged edits and saves skip global scans, layout and redraw", function()
  reset()
  for _, event in ipairs({ "TextChanged", "BufModifiedSet", "BufWritePost" }) do
    api.nvim_exec_autocmds(event, { buffer = first })
    settle()
  end
  equal(reads, { facts = 3, windows = 0, widths = 0, icons = 0, redraws = 0 })
  equal(#buffers.buffers(), #entries)
end)

test("focus changes reuse labels, icons and widths without a third observation", function()
  reset()
  equal(buffers.open(entries[2]), entries[2])
  settle()
  assert(reads.facts <= 2 * #entries + 5)
  assert(reads.windows <= 3)
  equal(reads.icons, 0)
  assert(reads.widths <= 10)
  equal(reads.redraws, 1)
end)

test("display option changes invalidate cached widths even with unchanged editor facts", function()
  reset()
  local original = vim.o.ambiwidth
  vim.o.ambiwidth = original == "single" and "double" or "single"
  settle()
  assert(reads.widths > 0)
  equal(reads.icons, 0)
  equal(reads.redraws, 1)
  vim.o.ambiwidth = original
  settle()
end)

test("theme changes invalidate icon cache and refresh presentation", function()
  reset()
  api.nvim_exec_autocmds("ColorScheme", { pattern = "test" })
  settle()
  equal(reads.icons, #entries)
  assert(reads.widths > 0)
  equal(reads.redraws, 1)
end)

test("hidden native deletion removes membership through targeted observation", function()
  reset()
  local buf = entries[3]
  vim.cmd({ cmd = "bdelete", args = { tostring(buf) } })
  settle()
  equal(buffers.contains(buf), false)
  equal(#buffers.buffers(), #entries - 1)
end)

support.run("tab-buffers optimization")
panel.teardown()
buffers.teardown()
native.new, styles.new, metrics.measure = create, create_panel, measure
package.loaded["nvim-web-devicons"] = original_icons
