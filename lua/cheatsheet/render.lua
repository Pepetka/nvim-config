local cheatsheet_config = require("cheatsheet.config")
local api = vim.api
local ns = api.nvim_create_namespace("cheatsheet")

---@class CheatsheetState
---@field buf integer | nil
---@field win integer | nil
---@field mode CheatsheetMode

---@class CheatsheetRenderedLine
---@field text string
---@field hl string | nil
---@field col integer | nil
---@field end_col integer | nil
---@field text_start integer | nil
---@field key_start integer | nil

---@class CheatsheetWindowSize
---@field width number
---@field height number
---@field row number
---@field col number

local utils = {}

---@param window_config CheatsheetWindowConfig
---@return CheatsheetWindowSize
function utils.calculate_window_size(window_config)
  local width = math.floor(vim.o.columns * window_config.width)
  local height = math.floor(vim.o.lines * window_config.height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  ---@type CheatsheetWindowSize
  local window_size = {
    width = width,
    height = height,
    row = row,
    col = col,
  }

  return window_size
end

---@param str string
---@param length number
---@return string
function utils.pad_right(str, length)
  local width = vim.fn.strdisplaywidth(str)
  if width < length then
    return str .. string.rep(" ", length - width)
  end
  return str
end

---@param n number
---@return string
function utils.left_pad(n)
  return string.rep(" ", n)
end

local M = {}

---@param config CheatsheetConfig
---@return integer buf, integer win
function M.create_float(config)
  local window_config = config.window
  local size = utils.calculate_window_size(window_config)

  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_set_option_value("buflisted", false, { buf = buf })
  api.nvim_set_option_value("filetype", "cheatsheet", { buf = buf })
  api.nvim_set_option_value("modifiable", true, { buf = buf })

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    row = size.row,
    col = size.col,
    width = size.width,
    height = size.height,
    border = window_config.border,
    title = window_config.title,
    title_pos = window_config.title_pos,
    style = "minimal",
    zindex = window_config.zindex,
  })

  if win == 0 then
    vim.notify("cheatsheet: failed to create window", vim.log.levels.ERROR)
    return buf, 0
  end

  api.nvim_set_option_value("number", false, { win = win })
  api.nvim_set_option_value("relativenumber", false, { win = win })
  api.nvim_set_option_value("cursorline", false, { win = win })
  api.nvim_set_option_value("wrap", false, { win = win })

  return buf, win
end

---@param buf integer
---@param win integer
---@param groups CheatsheetGroup[]
---@param mode CheatsheetMode
---@param config CheatsheetConfig
---@return CheatsheetRenderedLine[] lines
function M.render(buf, win, groups, mode, config)
  ---@type CheatsheetRenderedLine[]
  local lines = {}
  local win_width = api.nvim_win_get_width(win)
  local pad = config.window.padding
  local content_width = math.max(1, win_width - pad.left - pad.right)

  for _ = 1, pad.top do
    table.insert(lines, { text = utils.left_pad(pad.left) })
  end

  local modes_str = ""
  for _, m in ipairs(config.modes) do
    if m == mode then
      modes_str = modes_str .. "[" .. m .. "] "
    else
      modes_str = modes_str .. " " .. m .. "  "
    end
  end

  local modes_width = vim.fn.strdisplaywidth(modes_str)
  local modes_offset

  if config.mode_align == "right" then
    modes_offset = pad.left + math.max(0, content_width - modes_width)
  elseif config.mode_align == "center" then
    modes_offset = pad.left + math.max(0, math.floor((content_width - modes_width) / 2))
  else
    modes_offset = pad.left
  end

  table.insert(
    lines,
    { text = utils.left_pad(modes_offset) .. modes_str, hl = "CheatsheetTitle", text_start = modes_offset }
  )
  table.insert(lines, { text = utils.left_pad(pad.left) })

  local global_max_lhs_width = 0
  for _, group in ipairs(groups) do
    for _, mapping in ipairs(group.mappings) do
      local w = vim.fn.strdisplaywidth(mapping.lhs)
      if w > global_max_lhs_width then
        global_max_lhs_width = w
      end
    end
  end

  local gap = 4

  for group_index, group in ipairs(groups) do
    local header_text = group.icon .. group.name
    local header_width = vim.fn.strdisplaywidth(header_text)
    local header_offset

    if config.group_align == "right" then
      header_offset = pad.left + math.max(0, content_width - header_width)
    elseif config.group_align == "center" then
      header_offset = pad.left + math.max(0, math.floor((content_width - header_width) / 2))
    else
      header_offset = pad.left
    end

    table.insert(lines, {
      text = utils.left_pad(header_offset) .. header_text,
      hl = "CheatsheetGroup",
      text_start = header_offset,
    })

    -- Separator between group header and its mappings.
    if config.group_underline then
      table.insert(lines, {
        text = utils.left_pad(pad.left) .. string.rep("─", content_width),
        hl = "CheatsheetSeparator",
        text_start = pad.left,
      })
    else
      table.insert(lines, { text = utils.left_pad(pad.left) })
    end

    for index, mapping in ipairs(group.mappings) do
      local lhs = utils.pad_right(mapping.lhs, global_max_lhs_width)
      local line_text = utils.left_pad(pad.left) .. lhs .. utils.left_pad(gap) .. mapping.desc
      local key_end = pad.left + lhs:len()
      local desc_start = key_end + gap

      table.insert(lines, {
        text = line_text,
        hl = "CheatsheetMapping",
        key_start = pad.left,
        col = key_end,
        end_col = desc_start,
      })

      -- One blank line between mappings, but not after the last one.
      if index < #group.mappings then
        table.insert(lines, { text = utils.left_pad(pad.left) })
      end
    end

    -- Three blank lines between groups, but not after the last group.
    if group_index < #groups then
      for _ = 1, 2 do
        table.insert(lines, { text = utils.left_pad(pad.left) })
      end
    end
  end

  for _ = 1, pad.bottom do
    table.insert(lines, { text = utils.left_pad(pad.left) })
  end

  ---@type string[]
  local text_lines = {}
  for _, line in ipairs(lines) do
    table.insert(text_lines, line.text)
  end

  api.nvim_set_option_value("modifiable", true, { buf = buf })
  api.nvim_buf_set_lines(buf, 0, -1, false, text_lines)
  api.nvim_set_option_value("modifiable", false, { buf = buf })

  return lines
end

---@param buf integer
---@param lines CheatsheetRenderedLine[]
---@return nil
function M.apply_highlights(buf, lines)
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  for row, line in ipairs(lines) do
    local row_index = row - 1

    if line.hl == "CheatsheetTitle" then
      api.nvim_buf_set_extmark(buf, ns, row_index, line.text_start or 0, {
        hl_group = line.hl,
        end_row = row_index,
        end_col = line.text:len(),
        strict = true,
      })
    elseif line.hl == "CheatsheetSeparator" then
      api.nvim_buf_set_extmark(buf, ns, row_index, line.text_start or 0, {
        hl_group = line.hl,
        end_row = row_index,
        end_col = line.text:len(),
        strict = true,
      })
    elseif line.hl == "CheatsheetGroup" then
      local text_start = line.text_start or 0
      local icon_text = line.text:match("^%s*([^%s]*)")
      local icon_end = text_start + (icon_text and icon_text:len() or 0)
      api.nvim_buf_set_extmark(buf, ns, row_index, text_start, {
        hl_group = "CheatsheetGroupIcon",
        end_row = row_index,
        end_col = icon_end,
        strict = true,
      })
      api.nvim_buf_set_extmark(buf, ns, row_index, icon_end, {
        hl_group = "CheatsheetGroup",
        end_row = row_index,
        end_col = line.text:len(),
        strict = true,
      })
    elseif line.hl == "CheatsheetMapping" then
      api.nvim_buf_set_extmark(buf, ns, row_index, line.key_start or 0, {
        hl_group = "CheatsheetKey",
        end_row = row_index,
        end_col = line.col,
        strict = true,
      })
      api.nvim_buf_set_extmark(buf, ns, row_index, line.end_col, {
        hl_group = "CheatsheetDesc",
        end_row = row_index,
        end_col = line.text:len(),
        strict = true,
      })
    end
  end
end

---@param buf integer
---@param win integer
---@param state CheatsheetState
---@param config CheatsheetConfig
---@return nil
function M.set_keymaps(buf, win, state, config)
  local mappings = config.mappings

  ---@param key string
  ---@param fn function
  ---@return nil
  local function keymap(key, fn)
    vim.keymap.set("n", key, fn, { buffer = buf, silent = true })
  end

  for _, key in ipairs(mappings.close) do
    keymap(key, function()
      M.close(state)
    end)
  end

  keymap(mappings.next_mode, function()
    require("cheatsheet").next_mode()
  end)

  keymap(mappings.prev_mode, function()
    require("cheatsheet").prev_mode()
  end)
end

---@param state CheatsheetState
---@return nil
function M.close(state)
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_win_close(state.win, true)
  end

  if state.buf and api.nvim_buf_is_valid(state.buf) then
    api.nvim_buf_delete(state.buf, { force = true })
  end

  state.win = nil
  state.buf = nil
  vim.g.cheatsheet_displayed = false
end

---@param state CheatsheetState
---@return nil
function M.redraw(state)
  if not state.win or not api.nvim_win_is_valid(state.win) then
    return
  end

  local current_mode = state.mode
  local opts = cheatsheet_config.options
  local groups = require("cheatsheet.parser").parse(current_mode)

  M.close(state)

  local buf, win = M.create_float(opts)
  if win == 0 then
    return
  end
  state.buf = buf
  state.win = win

  local lines = M.render(buf, win, groups, current_mode, opts)
  M.apply_highlights(buf, lines)
  M.set_keymaps(buf, win, state, opts)

  vim.g.cheatsheet_displayed = true
end

return M
