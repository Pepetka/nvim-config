local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path
vim.o.swapfile, vim.o.hidden = false, true
local support = require("support")
local test, equal = support.test, support.equal
local api = vim.api
local buffers = require("tab_buffers")
local line = require("tab_buffers.tabline")
local editor = require("tab_buffers.integrations.nvim").new()
local diffview = require("tab_buffers.integrations.diffview")
local notices = {}
local notify = vim.notify
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(message)
  notices[#notices + 1] = message
end
local a, b = api.nvim_create_buf(true, false), api.nvim_create_buf(true, false)
api.nvim_buf_set_name(a, "/private/tmp/adapter-a.lua")
api.nvim_buf_set_name(b, "/private/tmp/adapter-b.lua")
api.nvim_set_current_buf(a)
buffers.setup()

test("buffer facts do not load an unloaded named buffer", function()
  local buf = vim.fn.bufadd("/private/tmp/adapter-unloaded.lua")
  local facts = editor.buffer(buf)
  equal(facts.loaded, false)
  equal(api.nvim_buf_is_loaded(buf), false)
  equal(editor.buffer(999999).valid, false)
end)

test("protection restores all bufhidden options after callback failure", function()
  vim.bo[a].bufhidden, vim.bo[b].bufhidden = "wipe", "delete"
  local ok, err = editor.protected({ a, a, b }, function()
    equal(vim.bo[a].bufhidden, "hide")
    equal(vim.bo[b].bufhidden, "hide")
    error("callback failed")
  end)
  equal(ok, false)
  assert(type(err) == "string" and err:find("callback failed"))
  equal(vim.bo[a].bufhidden, "wipe")
  equal(vim.bo[b].bufhidden, "delete")
  vim.bo[a].bufhidden, vim.bo[b].bufhidden = "", ""
end)

test("failed protection preparation restores buffers already protected", function()
  vim.bo[a].bufhidden, vim.bo[b].bufhidden = "wipe", "delete"
  local setter = api.nvim_set_option_value
  -- Intentional failure while preparing the second buffer.
  ---@diagnostic disable-next-line: duplicate-set-field
  api.nvim_set_option_value = function(name, value, opts)
    if name == "bufhidden" and value == "hide" and opts.buf == b then
      error("prepare failed")
    end
    return setter(name, value, opts)
  end
  local invoked = false
  local ok, err = editor.protected({ a, b }, function()
    invoked = true
  end)
  api.nvim_set_option_value = setter
  equal(ok, false)
  assert(type(err) == "string" and err:find("prepare failed"))
  equal(invoked, false)
  equal(vim.bo[a].bufhidden, "wipe")
  equal(vim.bo[b].bufhidden, "delete")
  vim.bo[a].bufhidden, vim.bo[b].bufhidden = "", ""
end)

test("nested protection restores the outer protected value", function()
  vim.bo[a].bufhidden = "wipe"
  editor.protected({ a }, function()
    editor.protected({ a }, function()
      equal(vim.bo[a].bufhidden, "hide")
    end)
    equal(vim.bo[a].bufhidden, "hide")
  end)
  equal(vim.bo[a].bufhidden, "wipe")
  vim.bo[a].bufhidden = ""
end)

test("nested restoration failure never retries the temporary hide value", function()
  vim.bo[a].bufhidden = "wipe"
  local setter = api.nvim_set_option_value
  local fail = false
  ---@diagnostic disable-next-line: duplicate-set-field
  api.nvim_set_option_value = function(name, value, opts)
    if fail and name == "bufhidden" and value == "hide" and opts.buf == a then
      fail = false
      error("nested restoration failed")
    end
    return setter(name, value, opts)
  end
  local ok = editor.protected({ a }, function()
    local nested = editor.protected({ a }, function()
      fail = true
    end)
    equal(nested, false)
  end)
  api.nvim_set_option_value = setter
  assert(ok)
  editor.restore_closing()
  equal(vim.bo[a].bufhidden, "wipe")
  vim.bo[a].bufhidden = ""
end)

test("setup callback error leaves options and handlers untouched", function()
  line.teardown()
  vim.o.tabline, vim.o.showtabline = "previous", 1
  local count = #api.nvim_get_autocmds({ event = "ColorScheme" })
  support.raises(function()
    line.setup({
      highlights = function()
        error("theme failed")
      end,
    })
  end, "theme failed")
  equal(vim.o.tabline, "previous")
  equal(vim.o.showtabline, 1)
  equal(#api.nvim_get_autocmds({ event = "ColorScheme" }), count)
  equal(line.teardown(), false)
end)

test("failed repeated setup keeps the working document and configuration", function()
  line.setup({ icons = false })
  local text, expression = line.render(), vim.o.tabline
  local count = #api.nvim_get_autocmds({ group = "TabBuffersTabline" })
  support.raises(function()
    line.setup({
      highlights = function()
        error("reconfiguration failed")
      end,
    })
  end, "reconfiguration failed")
  equal(line.render(), text)
  equal(vim.o.tabline, expression)
  equal(#api.nvim_get_autocmds({ group = "TabBuffersTabline" }), count)
end)

test("invalid native highlight rolls back installation and all styles", function()
  line.teardown()
  vim.o.tabline, vim.o.showtabline = "previous", 1
  local count = #api.nvim_get_autocmds({ event = "ColorScheme" })
  api.nvim_set_hl(0, "TabBuffersActive", { link = "Normal" })
  local old = api.nvim_get_hl(0, { name = "TabBuffersActive" })
  support.raises(function()
    line.setup({ highlights = { Active = { fg = "not-a-valid-color-123" } } })
  end)
  equal(vim.o.tabline, "previous")
  equal(vim.o.showtabline, 1)
  equal(api.nvim_get_hl(0, { name = "TabBuffersActive" }), old)
  equal(#api.nvim_get_autocmds({ event = "ColorScheme" }), count)
  equal(line.teardown(), false)
end)

test("theme callback failure retains last valid styles and warns", function()
  local fail = false
  line.setup({
    highlights = function()
      if fail then
        error("theme changed failed")
      end
      return { Active = { fg = "#123456" } }
    end,
  })
  local before = api.nvim_get_hl(0, { name = "TabBuffersActive" })
  fail = true
  local count = #notices
  api.nvim_exec_autocmds("ColorScheme", { pattern = "test" })
  equal(api.nvim_get_hl(0, { name = "TabBuffersActive" }), before)
  equal(#notices, count + 1)
  line.teardown()
end)

test("Diffview restores pre-existing true and false exclusions", function()
  local tab = api.nvim_get_current_tabpage()
  local hooks = diffview.hooks()
  local view = { tabpage = tab, infer_cur_file = function() end }
  for _, initial in ipairs({ true, false }) do
    vim.t[tab].tab_buffers_excluded = initial
    hooks.view_opened(view)
    hooks.view_closed(view)
    equal(vim.t[tab].tab_buffers_excluded, initial)
  end
  vim.t[tab].tab_buffers_excluded = nil
end)

test("a stale Diffview close does not release the current view", function()
  local tab = api.nvim_get_current_tabpage()
  local hooks = diffview.hooks()
  local first = { tabpage = tab, infer_cur_file = function() end }
  local second = { tabpage = tab, infer_cur_file = function() end }
  hooks.view_opened(first)
  hooks.view_opened(second)
  hooks.view_closed(first)
  equal(diffview.is_review(tab), true)
  equal(vim.t[tab].tab_buffers_excluded, true)
  hooks.view_closed(second)
  equal(diffview.is_review(tab), false)
  equal(vim.t[tab].tab_buffers_excluded, nil)
end)

test("review indicator changes publish context updates even for pre-excluded tabs", function()
  local tab, count = api.nvim_get_current_tabpage(), 0
  local group = api.nvim_create_augroup("TabBuffersAdapterReviewTest", { clear = true })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "TabBuffersContextChanged",
    callback = function()
      count = count + 1
    end,
  })
  vim.t[tab].tab_buffers_excluded = true
  local hooks = diffview.hooks()
  local view = { tabpage = tab, infer_cur_file = function() end }
  hooks.view_opened(view)
  equal(count, 1)
  hooks.view_closed(view)
  equal(count, 2)
  equal(vim.t[tab].tab_buffers_excluded, true)
  vim.t[tab].tab_buffers_excluded = nil
  api.nvim_del_augroup_by_id(group)
end)

test("double-width ambiguous characters never exceed the clipping budget", function()
  local previous = vim.o.ambiwidth
  vim.o.ambiwidth = "double"
  local layout = require("tab_buffers.tabline.layout")
  for width = 1, 20 do
    assert(vim.fn.strdisplaywidth(layout.clip("long-long-file.lua", width)) <= width)
  end
  vim.o.ambiwidth = previous
end)

test("native lifecycle subscriptions are cancellable and independent", function()
  local first, second = 0, 0
  local cancel_one = editor.install({
    changed = function()
      first = first + 1
    end,
    closing = function() end,
    exiting = function() end,
  })
  local cancel_two = editor.install({
    changed = function()
      second = second + 1
    end,
    closing = function() end,
    exiting = function() end,
  })
  api.nvim_exec_autocmds("TextChangedI", { buffer = a })
  assert(first > 0 and second > 0)
  cancel_one()
  local before = first
  api.nvim_exec_autocmds("TextChangedP", { buffer = a })
  equal(first, before)
  assert(second > before)
  cancel_one()
  cancel_two()
end)

test("placeholder creation failure produces a partial report without losing the visible buffer", function()
  buffers.refresh()
  local create = api.nvim_create_buf
  -- Intentional failure before a replacement buffer exists.
  ---@diagnostic disable-next-line: duplicate-set-field
  api.nvim_create_buf = function()
    error("placeholder failed")
  end
  local ok, report = pcall(buffers.close_all)
  api.nvim_create_buf = create
  assert(ok, tostring(report))
  equal(report.failed[1].buf, a)
  assert(report.failed[1].message:find("placeholder failed"))
  assert(api.nvim_buf_is_valid(a))
  equal(api.nvim_get_current_buf(), a)
  assert(buffers.contains(a))
end)

test("linked highlight overrides preserve transparent panel styles", function()
  api.nvim_set_hl(0, "TabBuffersTestLinked", { fg = "#123456", bg = "#654321", reverse = true })
  line.setup({ highlights = { Active = { link = "TabBuffersTestLinked" } } })
  local style = api.nvim_get_hl(0, { name = "TabBuffersActive", link = false })
  equal(style.fg, 0x123456)
  equal(style.bg, nil)
  equal(style.reverse, nil)
  line.teardown()
end)

test("previewwindow changes enroll newly ordinary windows", function()
  local managed = require("tab_buffers.nvim").new()
  local buf = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(buf, "/private/tmp/adapter-preview.lua")
  local focus = api.nvim_get_current_win()
  local win = api.nvim_open_win(buf, true, { split = "right", win = focus })
  vim.wo[win].previewwindow = true
  managed.setup()
  equal(managed.contains(buf), false)
  vim.wo[win].previewwindow = false
  assert(vim.wait(1000, function()
    return managed.contains(buf)
  end))
  managed.teardown()
  api.nvim_win_close(win, true)
end)

test("panel option changes invalidate the cached document", function()
  local native = require("tab_buffers.integrations.tabline").new()
  local updates = 0
  local cancel = native.install({
    changed = function()
      updates = updates + 1
    end,
    theme = function() end,
  })
  local original = vim.o.ambiwidth
  vim.o.ambiwidth = original == "single" and "double" or "single"
  assert(updates > 0)
  vim.o.ambiwidth = original
  cancel()
end)

test("navigation rejects autocmd redirection in open and switch", function()
  local managed = require("tab_buffers.nvim").new()
  local original = api.nvim_get_current_buf()
  local target, redirect = api.nvim_create_buf(true, false), api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(target, "/private/tmp/adapter-navigation-target.lua")
  api.nvim_buf_set_name(redirect, "/private/tmp/adapter-navigation-redirect.lua")
  managed.setup()
  managed.move_to(1, { buf = original })
  managed.move_to(2, { buf = target })
  local group = api.nvim_create_augroup("TabBuffersNavigationRedirectTest", { clear = true })
  api.nvim_create_autocmd("BufEnter", {
    group = group,
    buffer = target,
    callback = function()
      api.nvim_set_current_buf(redirect)
    end,
  })
  local opened, err = managed.open(target)
  equal(opened, nil)
  assert(err and err:find("target window changed"))
  equal(api.nvim_get_current_buf(), redirect)
  api.nvim_set_current_buf(original)
  local switched, message = managed.next()
  equal(switched, nil)
  assert(message and message:find("target window changed"))
  api.nvim_del_augroup_by_id(group)
  managed.teardown()
  api.nvim_set_current_buf(original)
  api.nvim_buf_delete(target, { force = true })
  api.nvim_buf_delete(redirect, { force = true })
end)

test("shared closure reports committed membership when option restoration fails", function()
  local managed = require("tab_buffers.nvim").new()
  local source = api.nvim_get_current_tabpage()
  local buf = api.nvim_get_current_buf()
  managed.setup()
  vim.cmd.tabnew()
  local destination = api.nvim_get_current_tabpage()
  managed.add(buf)
  api.nvim_set_current_tabpage(source)
  local setter = api.nvim_set_option_value
  local original = vim.bo[buf].bufhidden
  ---@diagnostic disable-next-line: duplicate-set-field
  api.nvim_set_option_value = function(name, value, opts)
    if name == "bufhidden" and value == original and opts.buf == buf then
      error("restore failed")
    end
    return setter(name, value, opts)
  end
  local ok, report = pcall(managed.close, { buf = buf })
  api.nvim_set_option_value = setter
  assert(ok, tostring(report))
  equal(report.closed, { buf })
  equal(report.failed, {})
  assert(report.error and report.error:find("restore failed"))
  equal(managed.contains(buf, source), false)
  assert(managed.contains(buf, destination))
  managed.refresh()
  equal(vim.bo[buf].bufhidden, original)
  managed.teardown()
  api.nvim_set_current_tabpage(destination)
  vim.cmd.tabclose()
  api.nvim_set_current_buf(buf)
end)

support.run("tab-buffers adapter")
line.teardown()
buffers.teardown()
vim.notify = notify
