local api = vim.api
local buffers = require("tab_buffers")
local layout = require("tab_buffers.tabline.layout")
local reviews = require("tab_buffers.integrations.diffview")
local M = {}
local expression = "%!v:lua.require'tab_buffers.tabline'.render()"
local group, config, original, visibility
local cached, targets, last_active = "", {}, {}
local generation, queued, next_target = 0, false, 0

local function highlights()
  local overrides = type(config.highlights) == "function" and config.highlights() or config.highlights
  local normal = api.nvim_get_hl(0, { name = "Normal", link = false })
  for name, link in pairs({
    Fill = "Normal",
    Buffer = "Normal",
    Visible = "Normal",
    Active = "Function",
    Tab = "Normal",
    TabActive = "Special",
    Offset = "Normal",
    Border = "Comment",
    ActiveBorder = "DiagnosticError",
    Overflow = "DiagnosticWarn",
  }) do
    local style = api.nvim_get_hl(0, { name = link, link = false })
    style = vim.tbl_extend("force", style, overrides[name] or {})
    style.fg = style.fg or normal.fg or (vim.o.background == "dark" and "#c8d3f5" or "#343b58")
    -- TabLineSel often uses a dark foreground intended for an opaque accent background.
    -- Use text/accent groups and explicit fg colors for this transparent panel instead.
    style.bg, style.ctermbg, style.reverse, style.cterm = nil, nil, nil, nil
    if name == "Active" or name == "TabActive" or name == "ActiveBorder" or name == "Overflow" then
      style.bold = true
    end
    api.nvim_set_hl(0, "TabBuffers" .. name, style)
  end
end

local function ordinary(win)
  local props = api.nvim_win_get_config(win)
  return props.relative == "" and not props.external and not vim.wo[win].previewwindow
end

local function offsets(tab)
  local left, right = 0, 0
  for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
    if ordinary(win) then
      local buf = api.nvim_win_get_buf(win)
      if vim.tbl_contains(config.offsets, vim.bo[buf].filetype) then
        local position = api.nvim_win_get_position(win)
        local width = api.nvim_win_get_width(win)
        -- Only full-height outer sidebars reserve space; stacked small splits do not.
        local usable_height = vim.o.lines
          - vim.o.cmdheight
          - (vim.o.showtabline == 2 and 1 or 0)
          - (vim.o.laststatus > 0 and 1 or 0)
        if api.nvim_win_get_height(win) >= usable_height - 1 then
          if position[2] == 0 then
            left = math.max(left, width + 1)
          elseif position[2] + width >= vim.o.columns then
            right = math.max(right, width + 1)
          end
        end
      end
    end
  end
  return left, right
end

local function segment(item, map)
  next_target = next_target + 1
  map[next_target] = item
  local text = item.text:gsub("%%", "%%%%")
  local border = item.text:sub(1, #"│")
  if border == "│" or border == "▎" then
    text = "%#TabBuffers"
      .. (item.active and "ActiveBorder" or "Border")
      .. "#"
      .. border
      .. "%#TabBuffers"
      .. item.highlight
      .. "#"
      .. text:sub(#border + 1)
  end
  return string.format(
    "%%#TabBuffers%s#%%%d@v:lua.require'tab_buffers.tabline'.click@%s%%X",
    item.highlight,
    next_target,
    text
  )
end

local function block(items, before, after, map)
  local result = { "%#TabBuffersOverflow#", before or "" }
  for _, item in ipairs(items) do
    result[#result + 1] = segment(item, map)
  end
  result[#result + 1] = "%#TabBuffersOverflow#" .. (after or "")
  return table.concat(result)
end

local function width(items, before, after)
  local total = vim.fn.strdisplaywidth(before or "") + vim.fn.strdisplaywidth(after or "")
  for _, item in ipairs(items) do
    total = total + vim.fn.strdisplaywidth(item.text)
  end
  return total
end

local function update()
  local tab, focused = api.nvim_get_current_tabpage(), api.nvim_get_current_win()
  local members, tabs = buffers.buffers(tab), buffers.tabs()
  local active, visible, entries = nil, {}, {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
    if ordinary(win) then
      local buf = api.nvim_win_get_buf(win)
      visible[buf] = true
      if win == focused and buffers.contains(buf, tab) then
        active = buf
      end
    end
  end
  if active then
    last_active[tab] = active
  elseif last_active[tab] and buffers.contains(last_active[tab], tab) then
    active = last_active[tab]
  else
    for _, buf in ipairs(members) do
      if visible[buf] then
        active = buf
        break
      end
    end
    active = active or members[1]
    last_active[tab] = active
  end
  for saved in pairs(last_active) do
    if not api.nvim_tabpage_is_valid(saved) then
      last_active[saved] = nil
    end
  end
  visibility = (#members > 1 or #tabs > 1) and 2 or 0
  if vim.tbl_contains(config.hide_filetypes, vim.bo[api.nvim_win_get_buf(focused)].filetype) then
    visibility = 0
  end
  vim.o.showtabline = visibility
  for _, buf in ipairs(members) do
    entries[#entries + 1] = { id = buf, name = api.nvim_buf_get_name(buf) }
  end
  local labels, items, anchor = layout.labels(entries), {}, 1
  local ok, icons = pcall(require, "nvim-web-devicons")
  for index, entry in ipairs(entries) do
    local icon = ""
    if config.icons and ok then
      icon = icons.get_icon(vim.fs.basename(entry.name), vim.fn.fnamemodify(entry.name, ":e"), { default = true }) or ""
    end
    local selected = entry.id == active
    if selected then
      anchor = index
    end
    items[#items + 1] = {
      kind = "buffer",
      id = entry.id,
      tab = tab,
      active = selected,
      highlight = selected and "Active" or visible[entry.id] and "Visible" or "Buffer",
      text = (selected and "▎ " or "│ ") .. (icon ~= "" and icon .. " " or "") .. layout.clip(
        labels[entry.id],
        config.max_name_length
      ) .. (vim.bo[entry.id].modified and " ●" or "") .. " ",
    }
  end
  local tab_items, tab_anchor = {}, 1
  if #tabs > 1 then
    for index, handle in ipairs(tabs) do
      local selected = handle == tab
      if selected then
        tab_anchor = index
      end
      tab_items[#tab_items + 1] = {
        kind = "tab",
        tab = handle,
        active = selected,
        highlight = selected and "TabActive" or "Tab",
        text = (selected and "▎ " or "│ ") .. (reviews.is_review(handle) and "󰊢 " or "") .. index .. " ",
      }
    end
  end
  local left, right = offsets(tab)
  left = math.min(left, math.max(0, vim.o.columns - 1))
  right = math.min(right, math.max(0, vim.o.columns - left - 1))
  local padding = math.min(config.padding, math.floor(math.max(0, vim.o.columns - left - right - 1) / 2))
  left, right = left + padding, right + padding
  local available = math.max(0, vim.o.columns - left - right)
  local tab_budget = math.min(available - (#items > 0 and 1 or 0), math.max(4, math.floor(available / 3)))
  local fitted_tabs, tb, ta = layout.fit(tab_items, tab_anchor, tab_budget)
  local tab_width = width(fitted_tabs, tb, ta)
  local fitted, before, after = layout.fit(items, anchor, available - tab_width)
  local map = {}
  cached = "%#TabBuffersOffset#"
    .. string.rep(" ", left)
    .. block(fitted, before, after, map)
    .. "%#TabBuffersFill#%="
    .. block(fitted_tabs, tb, ta, map)
    .. "%#TabBuffersOffset#"
    .. string.rep(" ", right)
  targets = map
  vim.cmd.redrawtabline()
end

local function schedule()
  if not group or queued then
    return
  end
  queued = true
  local ticket = generation
  vim.schedule(function()
    if not group or ticket ~= generation then
      return
    end
    queued = false
    update()
  end)
end

---Native tabline expression: rendering never changes buffers, windows or membership.
function M.render()
  return cached
end

---Native click callback. Resolve targets from the displayed snapshot before scheduling.
function M.click(id, clicks, button, modifiers)
  if clicks ~= 1 or modifiers and modifiers:find("[^ ]") or button ~= "l" and button ~= "m" then
    return
  end
  local target, ticket = targets[id], generation
  if not target then
    return
  end
  vim.schedule(function()
    if not group or ticket ~= generation or not api.nvim_tabpage_is_valid(target.tab) then
      return
    end
    if target.kind == "tab" then
      if button == "l" then
        api.nvim_set_current_tabpage(target.tab)
      end
    else
      buffers.refresh()
      if not api.nvim_buf_is_valid(target.id) or not buffers.contains(target.id, target.tab) then
        return
      end
      if button == "m" then
        buffers.close({ tab = target.tab, buf = target.id })
      else
        local _, err = buffers.open(target.id, { tab = target.tab })
        if err then
          vim.notify(err, vim.log.levels.WARN, { title = "tab-buffers" })
        end
      end
    end
    schedule()
  end)
end

---@param opts? { icons?: boolean, max_name_length?: integer, padding?: integer, offsets?: string[], hide_filetypes?: string[], highlights?: table|fun(): table }
function M.setup(opts)
  opts = opts or {}
  assert(type(opts) == "table", "options must be a table")
  local options = vim.tbl_extend("force", {
    icons = true,
    max_name_length = 30,
    padding = 0,
    offsets = {},
    hide_filetypes = {},
    highlights = {},
  }, opts)
  assert(
    type(options.max_name_length) == "number" and options.max_name_length >= 1 and options.max_name_length % 1 == 0,
    "max_name_length must be a positive integer"
  )
  assert(
    type(options.padding) == "number" and options.padding >= 0 and options.padding % 1 == 0,
    "padding must be a nonnegative integer"
  )
  assert(type(options.icons) == "boolean", "icons must be a boolean")
  for _, key in ipairs({ "offsets", "hide_filetypes" }) do
    assert(vim.islist(options[key]), key .. " must be a list")
    for _, value in ipairs(options[key]) do
      assert(type(value) == "string", key .. " must contain filetypes")
    end
  end
  assert(
    type(options.highlights) == "table" or type(options.highlights) == "function",
    "highlights must be a table or callback"
  )
  buffers.refresh()
  M.teardown()
  config = vim.deepcopy(options)
  original = { tabline = vim.o.tabline, showtabline = vim.o.showtabline }
  group = api.nvim_create_augroup("TabBuffersTabline", { clear = true })
  vim.o.tabline = expression
  api.nvim_create_autocmd({
    "BufEnter",
    "BufWinEnter",
    "WinEnter",
    "WinClosed",
    "TabEnter",
    "TabNewEntered",
    "TabClosed",
    "BufFilePost",
    "BufModifiedSet",
    "BufWritePost",
    "FileType",
    "VimResized",
    "WinResized",
  }, { group = group, callback = schedule })
  api.nvim_create_autocmd(
    "User",
    { group = group, pattern = { "TabBuffersChanged", "TabBuffersContextChanged" }, callback = schedule }
  )
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      highlights()
      schedule()
    end,
  })
  highlights()
  update()
end

function M.teardown()
  generation = generation + 1
  if not group then
    return false
  end
  api.nvim_del_augroup_by_id(group)
  group, queued = nil, false
  if vim.o.tabline == expression then
    vim.o.tabline = original.tabline
    if vim.o.showtabline == visibility then
      vim.o.showtabline = original.showtabline
    end
  end
  cached, targets, last_active = "", {}, {}
  return true
end

return M
