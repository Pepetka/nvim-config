-- nvim --clean --headless -i NONE -l tests/tabline.lua
local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path
local support = require("support")
vim.o.swapfile, vim.o.hidden = false, true
local api = vim.api
local buffers = require("tab_buffers")
local line = require("tab_buffers.tabline")
local layout = require("tab_buffers.tabline.layout")
local reviews = require("tab_buffers.integrations.diffview")
local tests, sequence, notices = {}, 0, {}
local notify = vim.notify
-- Intentional native API replacement for failure injection.
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg)
  notices[#notices + 1] = msg
end
local equal = support.equal
---@return nil
local function drain()
  for _ = 1, 4 do
    local done = false
    vim.schedule(function()
      done = true
    end)
    assert(vim.wait(1000, function()
      return done
    end, 1))
  end
end
---@return nil
local function reset()
  line.teardown()
  buffers.teardown()
  vim.o.columns, vim.o.lines, vim.o.tabline, vim.o.showtabline = 120, 40, "", 1
  for _, buf in ipairs(api.nvim_list_bufs()) do
    vim.bo[buf].modified = false
  end
  vim.cmd("silent! tabonly!")
  vim.cmd("silent! only!")
  vim.cmd.enew()
  vim.t.tab_buffers_excluded = nil
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if buf ~= api.nvim_get_current_buf() then
      api.nvim_buf_delete(buf, { force = true })
    end
  end
  buffers.setup()
  notices = {}
end
---@param name? string
---@return integer
local function file(name)
  sequence = sequence + 1
  local buf = api.nvim_create_buf(true, false)
  if name ~= "" then
    api.nvim_buf_set_name(buf, "/private/tmp/tabline-tests/" .. sequence .. "/" .. (name or "file.lua"))
  end
  api.nvim_buf_set_lines(buf, 0, -1, false, { "text" })
  vim.bo[buf].modified = false
  buffers.add(buf)
  return buf
end
---@param buf integer
---@return nil
local function show(buf)
  api.nvim_set_current_buf(buf)
  drain()
end
local function rendered()
  drain()
  return api.nvim_eval_statusline(line.render(), { use_tabline = true, maxwidth = vim.o.columns, highlights = true })
end
---@param text string
---@param kind? string
---@return integer
local function token(text, kind)
  drain()
  for hl, id, label in line.render():gmatch("%%#TabBuffers(%w+)#%%(%d+)@[^@]+@(.-)%%X") do
    local is_tab = hl == "Tab" or hl == "TabActive"
    if (kind == "tab") == is_tab and label:find(text, 1, true) then
      return assert(tonumber(id))
    end
  end
  error("missing click target: " .. text)
end
---@param name string
---@param fn fun(): nil
---@return nil
local function test(name, fn)
  tests[#tests + 1] = { name = name, run = fn }
end

test("path suffixes and unnamed buffers are distinct", function()
  equal(
    layout.labels({
      { id = 1, name = "/x/client/index.ts" },
      { id = 2, name = "/y/server/index.ts" },
      { id = 3, name = "" },
      { id = 4, name = "" },
      { id = 5, name = "/one/unique.ts" },
    }),
    { [1] = "client/index.ts", [2] = "server/index.ts", [3] = "[No Name] 3", [4] = "[No Name] 4", [5] = "unique.ts" }
  )
end)

test("Unicode clipping counts cells and preserves combining marks", function()
  equal(layout.clip("a界é", 3), "…é")
  equal(layout.clip("界", 1), "…")
  equal(layout.clip("long", 0), "")
  equal(layout.clean("a\nb\rc\td"), "a b c d")
  for width = 0, 30 do
    assert(vim.fn.strdisplaywidth(layout.clip("Очень длинное имя 界界 é.lua", width)) <= width)
  end
end)

test("layout fits every width and retains the active item", function()
  local items = {}
  for i = 1, 12 do
    items[i] = { id = i, text = "▎file" .. i .. ".lua ", active = true }
  end
  for anchor = 1, #items do
    for width = 1, 160 do
      local fitted, before, after = layout.fit(items, anchor, width)
      local cells, found, previous =
        vim.fn.strdisplaywidth(before or "") + vim.fn.strdisplaywidth(after or ""), false, nil
      for _, item in ipairs(fitted) do
        cells = cells + vim.fn.strdisplaywidth(item.text)
        found = found or item.id == anchor
        if previous then
          equal(item.id, previous + 1)
        end
        previous = item.id
      end
      assert(found and cells <= width, "overflow at width " .. width)
    end
  end
end)

test("overflow markers count hidden entries and border highlights distinguish active items", function()
  local items = {}
  for i = 1, 10 do
    items[i] = { id = i, text = "│ file" .. i .. " " }
  end
  local fitted, before, after = layout.fit(items, 5, 20)
  equal(before, "«4 ")
  equal(after, " 5»")
  ---@cast fitted { id: integer, text: string }[]
  equal(fitted[1].id, 5)
  local a = file("first.lua")
  file("second.lua")
  show(a)
  line.setup({ icons = false })
  local result = rendered()
  assert(result.str:find("▎ first.lua │ second.lua ", 1, true))
  assert(line.render():find("%%#TabBuffersActiveBorder#▎"))
  assert(line.render():find("%%#TabBuffersBorder#│"))
  vim.cmd.tabnew()
  rendered()
  assert(line.render():find("%%#TabBuffersActiveBorder#▎%%#TabBuffersTabActive# 2 "))
  assert(line.render():find("%%#TabBuffersBorder#│%%#TabBuffersTab# 1 "))
end)

test("native rendering escapes percent and control characters", function()
  local buf = file("100%#TabLineSel#\n界.lua")
  show(buf)
  line.setup({ icons = false })
  local result = rendered()
  assert(result.str:find("100%#TabLineSel# 界.lua", 1, true))
  assert(result.width <= vim.o.columns)
  equal(vim.o.showtabline, 0)
  local second = file("")
  rendered()
  equal(vim.o.showtabline, 2)
  assert(rendered().str:find("[No Name]", 1, true))
  buffers.close({ buf = second })
  rendered()
  equal(vim.o.showtabline, 0)
end)

test("active and visible highlights follow splits and special-window focus", function()
  local a, b = file("a.lua"), file("b.lua")
  show(a)
  line.setup({ icons = false })
  vim.cmd.vsplit()
  show(b)
  local special = api.nvim_create_buf(false, true)
  local float = api.nvim_open_win(special, true, { relative = "editor", width = 10, height = 2, row = 2, col = 2 })
  rendered()
  assert(line.render():find("TabBuffersActiveBorder#▎%%#TabBuffersActive# b.lua "))
  assert(line.render():find("TabBuffersBorder#│%%#TabBuffersVisible# a.lua "))
  api.nvim_win_close(float, true)
  buffers.close({ buf = b })
  rendered()
  assert(line.render():find("TabBuffersActiveBorder#▎%%#TabBuffersActive# a.lua "))
end)

test("modified flags, rename, narrow rendering and resize update", function()
  local a = file("first.lua")
  show(a)
  for i = 1, 10 do
    file("other-long-name-" .. i .. ".lua")
  end
  line.setup({ icons = false })
  vim.bo[a].modified = true
  api.nvim_buf_set_name(a, "/private/tmp/tabline-renamed.ts")
  assert(rendered().str:find("tabline-renamed.ts ●", 1, true))
  vim.o.columns = 20
  api.nvim_exec_autocmds("VimResized", {})
  local result = rendered()
  assert(result.width <= 20)
  assert(result.str:find("renamed.ts", 1, true))
  assert(result.str:find("»", 1, true))
  vim.o.columns = 160
  api.nvim_exec_autocmds("VimResized", {})
  assert(rendered().width <= 160)
end)

test("clicks use source handles, reject detached targets and preserve changed text", function()
  local a, b = file("first.lua"), file("second.lua")
  show(a)
  line.setup({ icons = false })
  local first = api.nvim_get_current_tabpage()
  local click = token("second.lua")
  line.click(click, 1, "l", "    ")
  vim.cmd.tabnew()
  local second = api.nvim_get_current_tabpage()
  drain()
  equal(api.nvim_get_current_tabpage(), first)
  equal(api.nvim_get_current_buf(), b)
  vim.bo[b].modified = true
  click = token("second.lua")
  line.click(click, 1, "m", "    ")
  drain()
  assert(api.nvim_buf_is_valid(b) and buffers.contains(b, first))
  equal(#notices, 1)
  line.click(click, 1, "r", "    ")
  line.click(click, 2, "m", "    ")
  line.click(click, 1, "m", "s   ")
  drain()
  equal(#notices, 1)
  click = token("first.lua")
  line.click(click, 1, "l", "    ")
  buffers.close({ buf = a })
  drain()
  equal(api.nvim_get_current_buf(), b)
  api.nvim_set_current_tabpage(second)
  line.click(click, 1, "l", "    ")
  drain()
  equal(api.nvim_get_current_tabpage(), second)
end)

test("shared buffer close removes only captured membership", function()
  local a, b = file("shared.lua"), file("other.lua")
  show(b)
  local first = api.nvim_get_current_tabpage()
  vim.cmd.tabnew()
  show(a)
  local second = api.nvim_get_current_tabpage()
  api.nvim_set_current_tabpage(first)
  line.setup({ icons = false })
  line.click(token("shared.lua"), 1, "m", "    ")
  api.nvim_set_current_tabpage(second)
  drain()
  equal(buffers.contains(a, first), false)
  equal(buffers.contains(a, second), true)
  equal(api.nvim_buf_is_valid(a), true)
end)

test("tab numbers and Diffview marker use handles after renumbering", function()
  show(file("ordinary.lua"))
  local first = api.nvim_get_current_tabpage()
  vim.cmd.tabnew()
  local review = api.nvim_get_current_tabpage()
  local hooks = reviews.hooks()
  local observed = { infer_cur_file = function() end, tabpage = review }
  hooks.view_opened(observed)
  line.setup({ icons = false })
  equal(buffers.buffers(review), {})
  assert(rendered().str:find("󰊢 2", 1, true))
  line.click(token(" 1 ", "tab"), 1, "l", "    ")
  drain()
  equal(api.nvim_get_current_tabpage(), first)
  local click = token("󰊢 2", "tab")
  vim.cmd.tabnew()
  vim.cmd("tabmove 0")
  line.click(click, 1, "l", "    ")
  drain()
  equal(api.nvim_get_current_tabpage(), review)
  assert(rendered().str:find("󰊢 3", 1, true))
  hooks.view_closed(observed)
  assert(not reviews.is_review(review))
end)

test("tab overflow retains the active tab", function()
  show(file("base.lua"))
  for _ = 1, 15 do
    vim.cmd.tabnew()
  end
  line.setup({ icons = false })
  vim.o.columns = 20
  api.nvim_exec_autocmds("VimResized", {})
  local result = rendered()
  assert(result.str:find("16", 1, true))
  assert(result.width <= 20 and result.str:find("«", 1, true))
end)

test("sidebar offsets ignore floats and stacked windows; dashboard hides panel", function()
  local a = file("working.lua")
  show(a)
  file("hidden.lua")
  line.setup({ icons = false, offsets = { "NvimTree" }, hide_filetypes = { "dashboard" } })
  vim.cmd("botright 25vnew")
  local tree = api.nvim_get_current_buf()
  vim.bo[tree].filetype = "NvimTree"
  vim.bo[tree].buftype = "nofile"
  local treewin = api.nvim_get_current_win()
  local result = rendered()
  assert(result.str:sub(-26) == string.rep(" ", 26), "missing right sidebar space")
  vim.cmd.split()
  rendered()
  assert(not line.render():match(" " .. string.rep(" ", 25) .. "$"), "stacked sidebar reserved space")
  vim.cmd.close()
  api.nvim_win_close(treewin, true)
  local dashboard = api.nvim_create_buf(false, true)
  vim.bo[dashboard].filetype = "dashboard"
  api.nvim_set_current_buf(dashboard)
  rendered()
  equal(vim.o.showtabline, 0)
  show(a)
  rendered()
  equal(vim.o.showtabline, 2)
end)

test("setup, theme changes and teardown preserve external configuration", function()
  show(file("a.lua"))
  file("b.lua")
  vim.o.tabline, vim.o.showtabline = "previous", 1
  line.setup({ icons = false })
  local count = #api.nvim_get_autocmds({ group = "TabBuffersTabline" })
  local click = token("b.lua")
  line.click(click, 1, "m", "    ")
  line.setup({ icons = false })
  drain()
  equal(#api.nvim_get_autocmds({ group = "TabBuffersTabline" }), count)
  equal(#buffers.buffers(), 2)
  api.nvim_set_hl(0, "TabLineSel", { fg = "#000000", bg = "#abcdef", reverse = true })
  api.nvim_set_hl(0, "Function", { fg = "#abcdef", bg = "#123456", reverse = true })
  api.nvim_exec_autocmds("ColorScheme", { pattern = "test" })
  local hl = api.nvim_get_hl(0, { name = "TabBuffersActive" })
  equal(hl.fg, tonumber("abcdef", 16))
  equal(hl.bg, nil)
  assert(hl.bold and not hl.reverse)
  line.teardown()
  equal(vim.o.tabline, "previous")
  equal(vim.o.showtabline, 1)
  line.setup({ icons = false })
  vim.o.tabline, vim.o.showtabline = "external", 0
  line.teardown()
  equal(vim.o.tabline, "external")
  equal(vim.o.showtabline, 0)
end)

test("transparent highlight overrides refresh for dark and light themes", function()
  local dark = true
  line.setup({
    icons = false,
    highlights = function()
      return {
        Buffer = { fg = dark and "#c8d3f5" or "#343b58" },
        Active = { fg = dark and "#65bcff" or "#006c86", bg = "#000000", reverse = true },
      }
    end,
  })
  equal(api.nvim_get_hl(0, { name = "TabBuffersBuffer" }).fg, tonumber("c8d3f5", 16))
  dark = false
  api.nvim_exec_autocmds("ColorScheme", { pattern = "light" })
  equal(api.nvim_get_hl(0, { name = "TabBuffersBuffer" }).fg, tonumber("343b58", 16))
  local active = api.nvim_get_hl(0, { name = "TabBuffersActive" })
  equal(active.fg, tonumber("006c86", 16))
  equal(active.bg, nil)
  equal(active.reverse, nil)
  assert(active.bold)
end)

test("native mouse dispatch opens and closes through the tabline callback", function()
  local child = vim.fn.jobstart({ vim.v.progpath, "--embed", "--clean", "-u", "NONE", "-i", "NONE" }, { rpc = true })
  assert(child > 0)
  local ok, err = xpcall(function()
    vim.rpcrequest(child, "nvim_ui_attach", 80, 24, { rgb = true })
    local ids = vim.rpcrequest(
      child,
      "nvim_exec_lua",
      [[
      vim.opt.rtp:prepend(...)
      vim.o.mouse, vim.o.swapfile, vim.o.hidden = "a", false, true
      local api = vim.api
      local a, b = api.nvim_create_buf(true, false), api.nvim_create_buf(true, false)
      api.nvim_buf_set_name(a, "/private/tmp/mouse-first.lua")
      api.nvim_buf_set_name(b, "/private/tmp/mouse-second.lua")
      api.nvim_set_current_buf(a)
      require("tab_buffers").setup()
      require("tab_buffers.tabline").setup({ icons = false })
      return { a, b }
    ]],
      { root }
    )
    assert(type(ids) == "table")
    ---@cast ids integer[]
    local function position()
      local text = vim.rpcrequest(
        child,
        "nvim_exec_lua",
        [[
        return vim.api.nvim_eval_statusline(require("tab_buffers.tabline").render(), { use_tabline = true }).str
      ]],
        {}
      )
      assert(type(text) == "string")
      return vim.fn.strdisplaywidth(text:sub(1, assert(text:find("mouse-second.lua", 1, true)) - 1))
    end
    vim.rpcrequest(child, "nvim_input_mouse", "left", "press", "", 0, 0, position())
    assert(
      vim.wait(1000, function()
        return vim.rpcrequest(child, "nvim_get_current_buf") == ids[2]
      end, 5),
      "native left click did not open buffer"
    )
    vim.rpcrequest(child, "nvim_input_mouse", "left", "release", "", 0, 0, position())
    vim.rpcrequest(child, "nvim_input_mouse", "middle", "press", "", 0, 0, position())
    assert(
      vim.wait(1000, function()
        return not vim.rpcrequest(child, "nvim_buf_is_valid", ids[2])
      end, 5),
      "native middle click did not close buffer"
    )
  end, debug.traceback)
  vim.fn.jobstop(child)
  if not ok then
    error(err)
  end
end)

local failed = 0
for _, entry in ipairs(tests) do
  local ok, err = xpcall(function()
    reset()
    entry.run()
  end, debug.traceback)
  if ok then
    print("ok - " .. entry.name)
  else
    failed = failed + 1
    io.stderr:write("FAIL - " .. entry.name .. "\n" .. err .. "\n")
  end
end
reset()
vim.notify = notify
print(string.format("%d tests, %d failures", #tests, failed))
if failed > 0 then
  vim.cmd("cquit 1")
end
