local config = require("cheatsheet.config")
local parser = require("cheatsheet.parser")
local render = require("cheatsheet.render")
local map_opts = require("utils.map_opts")
local api = vim.api

local M = {}

---@type CheatsheetState
local state = {
  mode = "n",
  win = nil,
  buf = nil,
}

local function set_highlights()
  vim.api.nvim_set_hl(0, "CheatsheetTitle", { link = "FloatTitle" })
  vim.api.nvim_set_hl(0, "CheatsheetGroup", { link = "Title" })
  vim.api.nvim_set_hl(0, "CheatsheetGroupIcon", { link = "Constant" })
  vim.api.nvim_set_hl(0, "CheatsheetKey", { link = "Special" })
  vim.api.nvim_set_hl(0, "CheatsheetDesc", { link = "Normal" })
  vim.api.nvim_set_hl(0, "CheatsheetSeparator", { link = "WinSeparator" })
end

local function setup_autocmds()
  local group = api.nvim_create_augroup("Cheatsheet", { clear = true })

  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = set_highlights,
  })

  api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    pattern = "*",
    callback = function(args)
      if api.nvim_get_option_value("filetype", { buf = args.buf }) == "cheatsheet" then
        vim.g.cheatsheet_displayed = false
        state.buf = nil
        state.win = nil
        state.mode = config.options.modes[1]
      end
    end,
  })

  api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = group,
    callback = function()
      if vim.g.cheatsheet_displayed then
        render.redraw(state)
      end
    end,
  })
end

local init = false

---@param opts? CheatsheetConfigPartial
---@return nil
function M.setup(opts)
  if init then
    vim.notify("cheatsheet: already initialized", vim.log.levels.WARN)
    return
  end
  config.setup(opts)

  state.mode = config.options.modes[1]

  set_highlights()
  setup_autocmds()

  api.nvim_create_user_command("Cheatsheet", function()
    M.toggle()
  end, { desc = "Toggle cheatsheet window" })

  local open_mapping = config.options.open_mapping
  if open_mapping then
    vim.keymap.set("n", open_mapping, M.toggle, map_opts("Cheatsheet: Toggle"))
  end

  init = true
end

---@param mode? CheatsheetMode
---@return nil
function M.show(mode)
  mode = mode or state.mode
  state.mode = mode

  local groups = parser.parse(mode)
  if #groups == 0 then
    groups = {
      {
        name = "Info",
        icon = "󰌌 ",
        mappings = {
          { lhs = "", desc = "No mappings for " .. mode .. " mode", mode = mode },
        },
      },
    }
  end

  local opts = config.options
  local is_open = state.win and api.nvim_win_is_valid(state.win) and vim.g.cheatsheet_displayed

  if not is_open then
    if vim.g.cheatsheet_displayed then
      M.hide()
    end

    local buf, win = render.create_float(opts)
    if win == 0 then
      return
    end

    state.buf = buf
    state.win = win
    render.set_keymaps(buf, win, state, opts)
  end

  local lines = render.render(state.buf, state.win, groups, mode, opts)
  render.apply_highlights(state.buf, lines)

  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_win_set_cursor(state.win, { 1, 0 })
  end

  vim.g.cheatsheet_displayed = true
end

---@return nil
function M.hide()
  render.close(state)
end

---@return nil
function M.toggle()
  if vim.g.cheatsheet_displayed then
    M.hide()
  else
    M.show(state.mode)
  end
end

---@param direction number
---@return nil
local function cycle_mode(direction)
  local modes = config.options.modes
  local current_index = nil

  for index, m in ipairs(modes) do
    if m == state.mode then
      current_index = index
      break
    end
  end

  if not current_index then
    current_index = 1
  end

  local new_index = current_index + direction
  if new_index > #modes then
    new_index = 1
  elseif new_index < 1 then
    new_index = #modes
  end

  M.show(modes[new_index])
end

---@return nil
function M.next_mode()
  cycle_mode(1)
end

---@return nil
function M.prev_mode()
  cycle_mode(-1)
end

return M
