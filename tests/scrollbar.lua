-- Run: NVIM_LOG_FILE=/dev/null nvim --headless -u ./init.lua -i NONE -n -c 'lua dofile("tests/scrollbar.lua")'
if vim.v.vim_did_enter == 0 then
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      vim.schedule(function()
        dofile("tests/scrollbar.lua")
      end)
    end,
  })
  return
end

local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, "p")
local renderer = require("scrollbar.renderer")
local store = require("scrollbar.shared.store")
local colors = require("utils.colors")
local source, buffer, child

local function wait(predicate, label)
  assert(vim.wait(5000, predicate, 10), label)
end

-- Mouse input needs an attached UI, so fold-column clicks run in an embedded child.
local function click_fold_column(path)
  local unpack = vim.mpack.Unpacker()
  local replies, serial, failure = {}, 0, nil
  child = vim.fn.jobstart({
    vim.v.progpath,
    "--embed",
    "-u",
    vim.fn.getcwd() .. "/init.lua",
    "-i",
    "NONE",
    "-n",
    path,
  }, {
    env = { NVIM_LOG_FILE = "/dev/null" },
    on_stdout = function(_, chunks)
      local chunk = table.concat(
        vim.tbl_map(function(part)
          return part:gsub("\n", "\0")
        end, chunks),
        "\n"
      )
      local position = 1
      while position <= #chunk do
        local message
        message, position = unpack(chunk, position)
        if message and message[1] == 1 then
          replies[message[2]] = message
        end
      end
    end,
    on_stderr = function(_, chunks)
      local output = table.concat(chunks, "\n")
      if output ~= "" then
        failure = output
      end
    end,
  })
  assert(child > 0, "Could not start the UI child")

  local function request(method, ...)
    serial = serial + 1
    local id = serial
    vim.fn.chansend(child, vim.mpack.encode({ 0, id, method, { ... } }))
    wait(function()
      return replies[id] ~= nil or failure ~= nil
    end, method)
    assert(not failure, failure)
    assert(replies[id][3] == vim.NIL, vim.inspect(replies[id][3]))
    return replies[id][4]
  end

  local function eventually(code, label)
    local deadline = vim.uv.now() + 5000
    while not request("nvim_exec_lua", code, {}) do
      assert(vim.uv.now() < deadline, label)
      vim.wait(20)
    end
  end

  local extent = [[local state = require("scrollbar.renderer").get_state(vim.api.nvim_get_current_win())
    local extent = state and state.geometry.total_extent or 0
    return ]]
  local opened = extent .. "extent >= 1200 and vim.fn.foldclosed(200) == -1"
  local closed = extent .. "extent < 500 and vim.fn.foldclosed(200) == 200"

  request("nvim_ui_attach", 100, 40, { ext_linegrid = true })
  request("nvim_exec_lua", "vim.api.nvim_win_set_cursor(0, { 200, 0 })", {})
  eventually(opened, "The UI child did not render the open fold")
  local position =
    request("nvim_exec_lua", "return { vim.fn.screenpos(0, 200, 1).row - 1, vim.fn.win_screenpos(0)[2] - 1 }", {})
  for _, expected in ipairs({ closed, opened }) do
    request("nvim_input_mouse", "left", "press", "", 0, position[1], position[2])
    request("nvim_input_mouse", "left", "release", "", 0, position[1], position[2])
    eventually(expected, "A fold-column click was not reflected in the scrollbar")
    -- A second click within 'mousetime' is a double click, which does not toggle folds.
    vim.wait(vim.o.mousetime + 50)
  end
  vim.fn.jobstop(child)
end

local function git(...)
  local command = { "git", "-C", temporary }
  vim.list_extend(command, { ... })
  local result = vim.system(command, { text = true }):wait()
  assert(result.code == 0, result.stderr)
end

local function rendered(mark_type)
  for _, row in ipairs(renderer.get_hitmap(source) or {}) do
    for _, cell in ipairs(row) do
      if cell.type == mark_type then
        return true
      end
    end
  end
  return false
end

local function expect_color(name, property, color)
  local highlight = vim.api.nvim_get_hl(0, { name = name, link = false })
  assert(highlight[property] == tonumber(color:sub(2), 16), name .. " retained an old " .. property)
end

local ok, err = xpcall(function()
  local lines = {}
  for i = 1, 1200 do
    lines[i] = "-- sample row " .. i
  end
  lines[150] = "-- scrollbar_target"
  lines[200] = "local function folded()"
  lines[800] = "-- scrollbar_target"
  lines[1100] = "end"
  local path = temporary .. "/sample.lua"
  vim.fn.writefile(lines, path)
  git("init", "-q")
  git("add", "sample.lua")
  git("-c", "user.name=Scrollbar Test", "-c", "user.email=scrollbar@example.invalid", "commit", "-qm", "fixture")
  lines[400] = "-- changed row"
  vim.fn.writefile(lines, path)

  vim.cmd.edit(vim.fn.fnameescape(path))
  source = vim.api.nvim_get_current_win()
  buffer = vim.api.nvim_get_current_buf()
  wait(function()
    return renderer.get_state(source) ~= nil
  end, "Scrollbar did not open for a file")
  assert(package.loaded.hlslens == nil, "Search still loads hlslens")

  local namespace = vim.api.nvim_create_namespace("ScrollbarIntegrationTest")
  vim.diagnostic.set(namespace, buffer, {
    { lnum = 300, col = 0, message = "test error", severity = vim.diagnostic.severity.ERROR },
    { lnum = 1000, col = 0, message = "test warning", severity = vim.diagnostic.severity.WARN },
  })
  wait(function()
    return rendered("Error") and rendered("Warn")
  end, "Diagnostics did not reach the rendered scrollbar")
  wait(function()
    return rendered("GitChange")
  end, "Real gitsigns changes did not reach the rendered scrollbar")

  vim.fn.feedkeys("/scrollbar_target\r", "xt")
  wait(function()
    return #(store.get(buffer).search or {}) == 2 and rendered("Search")
  end, "Native search did not render both matches")
  vim.fn.feedkeys(":nohlsearch\r", "xt")
  wait(function()
    return not rendered("Search") and #(store.get(buffer).search or {}) == 0
  end, "Clearing search left scrollbar marks behind")

  vim.cmd.vsplit()
  local second = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(second, { 1150, 0 })
  vim.cmd.normal({ "zt", bang = true })
  wait(function()
    local first_state, second_state = renderer.get_state(source), renderer.get_state(second)
    return first_state ~= nil
      and second_state ~= nil
      and first_state.handle ~= false
      and second_state.handle ~= false
      and first_state.handle.first_row ~= second_state.handle.first_row
  end, "Two splits of one buffer did not get independent thumbs")
  assert(renderer.get_state(source).float_win ~= renderer.get_state(second).float_win)

  vim.api.nvim_set_current_win(source)
  assert(vim.wo.foldmethod == "expr", "Host fold method changed")
  vim.api.nvim_win_set_cursor(source, { 200, 0 })
  -- Neither command moves the cursor, so only the host fold hook can refresh the geometry.
  vim.fn.feedkeys("zc", "xt")
  wait(function()
    local state = renderer.get_state(source)
    return state ~= nil and state.geometry.total_extent < 500
  end, "Closed folds above 1000 lines were not reflected in the scrollbar")
  vim.fn.feedkeys("zo", "xt")
  wait(function()
    local state = renderer.get_state(source)
    return state ~= nil and state.geometry.total_extent >= 1200
  end, "Opening folds did not restore the scrollbar extent")
  click_fold_column(path)

  for _, mode in ipairs({ "light", "dark", "light", "dark" }) do
    vim.o.background = mode
    vim.wait(100)
    expect_color("ScrollbarThumb", "bg", colors.muted)
    expect_color("ScrollbarCursor", "fg", colors.accent)
    expect_color("ScrollbarSearch", "fg", colors.warning)
    expect_color("ScrollbarError", "fg", colors.error)
    expect_color("ScrollbarWarn", "fg", colors.warning)
    expect_color("ScrollbarGitChange", "fg", colors.warning)
    expect_color("ScrollbarSearchThumb", "bg", colors.muted)
    expect_color("ScrollbarSearchThumb", "fg", colors.warning)
    assert(vim.api.nvim_get_hl(0, { name = "ScrollbarThumb" }).blend == 30)
    assert(renderer.get_state(source) ~= nil, "Theme change hid the scrollbar")
  end

  vim.bo[buffer].filetype = "prompt"
  wait(function()
    return renderer.get_state(source) == nil and renderer.get_state(second) == nil
  end, "Excluded filetype kept its scrollbar")
  vim.bo[buffer].filetype = "lua"
  wait(function()
    return renderer.get_state(source) ~= nil
  end, "Leaving an excluded filetype did not restore its scrollbar")

  local small = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_win_set_buf(source, small)
  wait(function()
    return renderer.get_state(source) == nil and renderer.get_state(second) ~= nil
  end, "A file fitting in its window did not hide only its own scrollbar")
  assert(not require("scrollbar.minimap.config").get().enabled, "Migration enabled the minimap")
end, debug.traceback)

if child then
  vim.fn.jobstop(child)
end
if buffer and vim.api.nvim_buf_is_valid(buffer) then
  require("gitsigns").detach(buffer)
end
require("utils.theme_sync").stop()
vim.fn.delete(temporary, "rf")
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd.cquit()
end
io.stdout:write(
  "Scrollbar passed: native search, diagnostics, real Git changes, splits, folds, fold-column clicks, themes and exclusions\n"
)
vim.cmd.qa({ bang = true })
