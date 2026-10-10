-- Run: nvim --headless -u ./init.lua -i NONE -n -c 'lua dofile("tests/theme_ui.lua")'
if vim.v.vim_did_enter == 0 then
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      vim.schedule(function()
        dofile("tests/theme_ui.lua")
      end)
    end,
  })
  return
end

local temporary = vim.fn.tempname()
local original_xdg = vim.env.XDG_CONFIG_HOME
vim.env.XDG_CONFIG_HOME = temporary
local directory = temporary .. "/theme"
vim.fn.mkdir(directory, "p")
local mode_file = directory .. "/mode"
local sync = require("utils.theme_sync")
local tree = require("nvim-tree.api")
local fzf = require("fzf-lua")
local color_markers = require("nvim-highlight-colors")
local colors = require("utils.colors")
local picker_buffer, marker_buffer, unlisted_buffer
local host = require("configs.lualine")
local original_setup = host.setup
local host_setups, changes = 0, 0
host.setup = function(...)
  host_setups = host_setups + 1
  return original_setup(...)
end
local group = vim.api.nvim_create_augroup("ThemeIntegrationTest", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = function()
    changes = changes + 1
  end,
})
local root_autocmds = vim.api.nvim_get_autocmds({ group = "LualineGitRootCache" })

local function publish(mode)
  local file = assert(io.open(mode_file .. ".next", "w"))
  file:write(mode .. "\n")
  file:close()
  assert(os.rename(mode_file .. ".next", mode_file))
end

local function transition(mode)
  changes = 0
  publish(mode)
  assert(
    vim.wait(1800, function()
      return vim.o.background == mode
    end, 10),
    "Mode did not update: " .. mode
  )
  vim.wait(100)
  assert(changes == 1, "Full config reloaded colorscheme multiple times")
end

local function expect_color(group_name, property, color)
  local highlight = vim.api.nvim_get_hl(0, { name = group_name, link = false })
  assert(highlight[property] == tonumber(color:sub(2), 16), group_name .. " retained an old " .. property)
end

local function markers(buf)
  return vim.api.nvim_buf_get_extmarks(
    buf or marker_buffer,
    vim.api.nvim_get_namespaces()["nvim-highlight-colors"],
    0,
    -1,
    { details = true }
  )
end

local function expect_markers(buf, hex)
  local marks = markers(buf)
  assert(#marks == 1, "Color markers disappeared or accumulated")
  expect_color(marks[1][4].hl_group, "bg", hex or "#abcdef")
end

local ok, err = xpcall(function()
  publish("dark")
  package.loaded["configs.theme"] = nil
  require("configs.theme")
  vim.wait(50)

  vim.cmd.enew()
  marker_buffer = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(marker_buffer, 0, -1, false, { 'local color = "#abcdef"' })
  vim.bo[marker_buffer].filetype = "lua"
  color_markers.turnOff()
  color_markers.turnOn()
  expect_markers()
  -- Preview/scratch buffers are often unlisted and can contain unique colors.
  unlisted_buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(unlisted_buffer, 0, -1, false, { 'local color = "#fedcba"' })
  vim.api.nvim_win_set_buf(0, unlisted_buffer)
  vim.bo[unlisted_buffer].filetype = "lua"
  color_markers.setup()
  expect_markers(unlisted_buffer, "#fedcba")
  vim.api.nvim_win_set_buf(0, marker_buffer)
  tree.tree.open({ focus = false })
  fzf.files({ query = "theme", cwd = vim.fn.getcwd() })
  vim.wait(400)
  local win = require("fzf-lua.win").__SELF()
  assert(win and win.fzf_bufnr and vim.api.nvim_buf_is_valid(win.fzf_bufnr), "Picker not open")
  picker_buffer = win.fzf_bufnr

  for _, mode in ipairs({ "light", "dark", "light", "dark" }) do
    transition(mode)
    assert(require("fzf-lua.win").__SELF().fzf_bufnr == picker_buffer, "Theme recreated the picker")
    expect_color("Normal", "fg", colors.fg)
    expect_color("NvimTreeFolderName", "fg", colors.focus)
    expect_color("NvimTreeGitDirtyIcon", "fg", colors.warning)
    expect_color("DashboardDesc", "fg", colors.muted)
    expect_color("DapBreakpoint", "fg", colors.error)
    expect_color("SnacksIndentScope", "fg", colors.focus)
    expect_color("MiniCursorword", "bg", colors.gutter)
    expect_color("TodoFgTODO", "fg", colors.focus)
    expect_color("ScrollbarError", "fg", colors.error)
    expect_color("ConfigStatusDiffAdd", "fg", colors.palette.green)
    expect_color("TabBuffersActive", "fg", colors.accent)
    assert(vim.api.nvim_get_hl(0, { name = "LineNr", link = false }).fg ~= nil)
    local config = require("lualine").get_config()
    assert(config.options.theme().normal.c.fg == colors.fg, "Lualine theme cached an old foreground")
    assert(
      vim.tbl_contains(vim.tbl_values(colors.palette), config.sections.lualine_c[1].color().bg),
      "Lualine mode cached old colors in mode " .. vim.fn.mode()
    )
    expect_markers()
    expect_markers(unlisted_buffer, "#fedcba")
  end
  assert(host_setups == 0, "Theme rebuilt the host lualine configuration")
  assert(
    vim.deep_equal(root_autocmds, vim.api.nvim_get_autocmds({ group = "LualineGitRootCache" })),
    "Theme recreated Git cache handlers"
  )

  color_markers.turnOff()
  transition("light")
  assert(not color_markers.is_active() and #markers() == 0, "Theme re-enabled disabled color markers")
  color_markers.turnOn()
  transition("dark")
  expect_markers()

  fzf.hide()
  fzf.resume()
  vim.wait(100)
  assert(require("fzf-lua.win").__SELF().fzf_bufnr == picker_buffer, "Hide/resume recreated picker")
  fzf.hide()
  tree.tree.close()
  vim.cmd.Dashboard()
  local dashboard_buffer = vim.api.nvim_get_current_buf()
  local content = vim.api.nvim_buf_get_lines(dashboard_buffer, 0, -1, false)
  transition("light")
  assert(vim.o.laststatus == 0 and vim.o.showtabline == 0, "Theme revealed dashboard panels")
  assert(
    vim.deep_equal(content, vim.api.nvim_buf_get_lines(dashboard_buffer, 0, -1, false)),
    "Theme changed dashboard layout"
  )
  expect_color("DashboardDesc", "fg", colors.muted)
  vim.cmd.enew()
  vim.wait(50)
  assert(vim.o.laststatus == 3, "Dashboard did not restore the statusline")

  local autocmd_count = #vim.api.nvim_get_autocmds({ event = "ColorScheme" })
  for _ = 1, 3 do
    package.loaded["configs.theme"] = nil
    require("configs.theme")
  end
  vim.wait(50)
  assert(#vim.api.nvim_get_autocmds({ event = "ColorScheme" }) == autocmd_count, "Theme reload accumulated handlers")
end, debug.traceback)

host.setup = original_setup
pcall(fzf.hide)
pcall(tree.tree.close)
if picker_buffer and vim.api.nvim_buf_is_valid(picker_buffer) then
  local channel = vim.bo[picker_buffer].channel
  if channel > 0 then
    vim.fn.jobstop(channel)
  end
end
sync.stop()
vim.env.XDG_CONFIG_HOME = original_xdg
vim.fn.delete(temporary, "rf")
vim.api.nvim_del_augroup_by_id(group)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd.cquit()
end
io.stdout:write("Theme UI passed: live fzf, tree, DAP, TODO, scrollbar, lualine, color markers and dashboard\n")
vim.cmd.qa({ bang = true })
