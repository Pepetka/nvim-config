-- Run from the config root: NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -n -l tests/theme.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd.packadd("tokyonight.nvim")

local temporary = vim.fn.tempname()
local original_xdg = vim.env.XDG_CONFIG_HOME
vim.env.XDG_CONFIG_HOME = temporary
local directory = temporary .. "/theme"
local mode_file = directory .. "/mode"
local sync = require("utils.theme_sync")
local changes = 0
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    changes = changes + 1
  end,
})

local function publish(mode)
  vim.fn.mkdir(directory, "p")
  local file = assert(io.open(mode_file .. ".next", "w"))
  file:write(mode)
  file:close()
  assert(os.rename(mode_file .. ".next", mode_file))
end

local function expect_mode(mode)
  assert(
    vim.wait(1800, function()
      return vim.o.background == mode
    end, 10),
    "Mode did not update: " .. mode
  )
  assert(vim.g.colors_name == "tokyonight-" .. (mode == "light" and "day" or "moon"))
end

local ok, err = xpcall(function()
  require("tokyonight").setup({ style = "moon", light_style = "day", transparent = true, terminal_colors = false })
  vim.o.background = "dark"
  vim.cmd.colorscheme("tokyonight")
  local original = {}
  for _, group in ipairs({ "Normal", "LineNr", "CursorLineNr", "WinSeparator", "StatusLine" }) do
    original[group] = vim.api.nvim_get_hl(0, { name = group, link = false })
  end
  require("configs.theme")
  local colors = require("utils.colors")
  local original_snapshot = colors.get()
  assert(select("#", colors.get()) == 1, "Palette getter leaked an extra provider argument")
  local palette_setup = require("tokyonight.colors").setup
  require("tokyonight.colors").setup = function()
    error("Reading the color snapshot must not reconstruct TokyoNight")
  end
  assert(colors.fg == original_snapshot.fg and colors.palette == original_snapshot.palette)
  require("tokyonight.colors").setup = palette_setup
  for group, highlight in pairs(original) do
    local actual = vim.api.nvim_get_hl(0, { name = group, link = false })
    assert(actual.fg == highlight.fg, group .. " lost foreground")
    assert(actual.bold == highlight.bold, group .. " lost bold")
    assert(actual.bg == nil, group .. " is not transparent")
  end

  -- Startup without state respects native detection, then recovers when the
  -- service creates its directory. Atomic replacement must keep working.
  changes = 0
  publish("light\n")
  expect_mode("light")
  assert(colors.get() ~= original_snapshot and original_snapshot.fg == original_snapshot.palette.fg)
  assert(changes == 1, "A transition applied colorscheme more than once")
  assert(require("utils.colors").fg == require("tokyonight.colors").setup({ style = "day" }).fg)
  changes = 0
  publish("light\n")
  vim.wait(1100)
  assert(changes == 0, "Unchanged state reapplied colorscheme")
  publish("garbage\n")
  vim.wait(1100)
  assert(vim.o.background == "light", "Invalid state changed mode")
  os.remove(mode_file)
  vim.wait(1100)
  assert(vim.o.background == "light", "Missing state changed mode")

  changes = 0
  vim.o.background = "dark"
  assert(changes == 1, "Native background change must apply once")
  assert(require("utils.colors").fg == require("tokyonight.colors").setup({ style = "moon" }).fg)

  -- No filesystem handle: verify real periodic fallback, not a user action.
  local new_fs_event = vim.uv.new_fs_event
  vim.uv.new_fs_event = function()
    return nil
  end
  sync.watch(mode_file, function(mode)
    vim.o.background = mode
  end)
  vim.uv.new_fs_event = new_fs_event
  changes = 0
  publish(" light \n")
  expect_mode("light")
  assert(changes == 1)
  vim.fn.delete(directory, "rf")
  publish("dark\n")
  expect_mode("dark")

  -- Re-sourcing does not accumulate active watcher/timer handles.
  local function handles()
    local count = 0
    vim.uv.walk(function(handle)
      if not handle:is_closing() and handle:is_active() then
        count = count + 1
      end
    end)
    return count
  end
  package.loaded["configs.theme"] = nil
  require("configs.theme")
  vim.wait(50)
  local before = handles()
  for _ = 1, 5 do
    package.loaded["configs.theme"] = nil
    require("configs.theme")
  end
  vim.wait(50)
  assert(handles() == before, "Reload leaked active handles")

  -- Already-created terminals retain palette indices despite termguicolors.
  assert(vim.g.terminal_color_1 == nil)
  vim.cmd.enew()
  local terminal = vim.api.nvim_open_term(0, {})
  vim.api.nvim_chan_send(terminal, "\27[31mred\27[0m")
  vim.wait(50)
  vim.cmd.redraw()
  local cell = vim.api.nvim__inspect_cell(1, 0, 0)
  assert(cell[2].fg_indexed, "Terminal pinned ANSI red to a fixed RGB value")

  vim.cmd.packadd("nvim-web-devicons")
  vim.cmd.packadd("fzf-lua")
  vim.cmd.packadd("trouble.nvim")
  vim.cmd.packadd("tab-buffers.nvim")
  require("configs.fzf_lua")
  local config = require("fzf-lua.config")
  local core = require("fzf-lua.core")
  for _, picker in ipairs({ "files", "buffers", "grep", "tags", "diagnostics" }) do
    local opts = config.normalize_opts({}, picker)
    assert(opts.color_icons == false, picker .. " retains RGB icons")
    opts.is_live = true
    opts._fzf_cli_args = {}
    local colors = core.create_fzf_colors(opts)
    assert(not colors or not colors:find("#"), picker .. " retains RGB colors")
    assert(opts.fzf_opts["--color"]:match("^16,"))
  end
  assert(config.globals.winopts.preview.default == "builtin")
  local commits = config.normalize_opts({}, "git.commits")
  if vim.fn.executable("delta") == 1 then
    assert(commits.preview_pager:find("--syntax-theme=ansi", 1, true), "Commit preview inherited RGB pager")
  else
    assert(commits.preview_pager == false, "Native preview requires an absent delta")
  end
  dofile("tests/theme_fzf.lua")()
end, debug.traceback)

sync.stop()
vim.env.XDG_CONFIG_HOME = original_xdg
vim.fn.delete(temporary, "rf")
if not ok then
  error(err)
end
print("Theme tests passed: transitions, highlights, fallback, lifecycle, ANSI terminals and fzf")
