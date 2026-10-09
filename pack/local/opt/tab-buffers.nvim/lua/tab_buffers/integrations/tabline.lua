local api = vim.api
local config_rules = require("tab_buffers.core.config")
local panel = require("tab_buffers.core.panel")
local M = {}
local expression = "%!v:lua.require'tab_buffers.tabline'.render()"
local sequence = 0

---@param name string
---@param resolved boolean
---@return vim.api.keyset.highlight
local function read_highlight(name, resolved)
  local info = api.nvim_get_hl(0, { name = name, link = not resolved })
  ---@type vim.api.keyset.highlight
  local style = {}
  for key, value in pairs(info) do
    style[key] = value
  end
  if type(info.link) == "number" then
    style.link = api.nvim_get_hl_name_by_id(info.link)
  end
  return style
end

---@return TabBuffersPanelAdapter
function M.new()
  sequence = sequence + 1
  local group_name = sequence == 1 and "TabBuffersTabline" or "TabBuffersTabline" .. sequence
  local buffers = require("tab_buffers")
  local reviews = require("tab_buffers.integrations.diffview")
  local context = require("tab_buffers.core.context")
  local editor = require("tab_buffers.integrations.nvim").new()
  ---@type { tabline: string, showtabline: integer }
  local original
  ---@type integer?
  local visibility
  ---@type table<integer, { name: string, icon: string }>
  local icon_cache = {}
  local icons_attempted = false
  ---@type TabBuffersIcons?
  local icon_provider
  local adapter = {
    metrics = require("tab_buffers.integrations.text").metrics,
    schedule = vim.schedule,
    tab_valid = api.nvim_tabpage_is_valid,
    buffer_valid = api.nvim_buf_is_valid,
    focus_tab = api.nvim_set_current_tabpage,
  }

  ---@param message string
  ---@return nil
  function adapter.notify(message)
    vim.notify(message, vim.log.levels.WARN, { title = "tab-buffers" })
  end

  ---@return nil
  function adapter.redraw()
    vim.cmd.redrawtabline()
  end

  ---@param input TabBuffersHighlights|fun(): TabBuffersHighlights
  ---@return TabBuffersHighlights
  function adapter.highlights(input)
    local overrides = config_rules.highlights(type(input) == "function" and input() or input)
    local normal = api.nvim_get_hl(0, { name = "Normal", link = false })
    local result = {}
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
      local style = read_highlight(link, true)
      for key, value in pairs(overrides[name] or {}) do
        style[key] = value
      end
      local link = style.link
      if type(link) == "number" then
        link = api.nvim_get_hl_name_by_id(link)
      end
      if type(link) == "string" then
        local resolved = read_highlight(link, true)
        for key, value in pairs(overrides[name] or {}) do
          if key ~= "link" then
            resolved[key] = value
          end
        end
        style = resolved
      end
      style.link = nil
      style.fg = style.fg or normal.fg or (vim.o.background == "dark" and "#c8d3f5" or "#343b58")
      style.bg, style.ctermbg, style.reverse, style.cterm = nil, nil, nil, nil
      if name == "Active" or name == "TabActive" or name == "ActiveBorder" or name == "Overflow" then
        style.bold = true
      end
      result["TabBuffers" .. name] = style
    end
    return result
  end

  ---@param styles? TabBuffersHighlights
  ---@param shown integer
  ---@return nil
  function adapter.apply(styles, shown)
    local old_styles, old_shown = {}, vim.o.showtabline
    local ok, err = pcall(function()
      for name, style in pairs(styles or {}) do
        old_styles[name] = read_highlight(name, false)
        api.nvim_set_hl(0, name, style)
      end
      if vim.o.showtabline ~= shown then
        vim.o.showtabline = shown
      end
    end)
    if not ok then
      for name, style in pairs(old_styles) do
        pcall(api.nvim_set_hl, 0, name, style)
      end
      vim.o.showtabline = old_shown
      error(err, 0)
    end
    visibility = shown
  end

  ---@param config TabBuffersTablineConfig
  ---@return TabBuffersPanelSnapshot
  function adapter.snapshot(config)
    local tab, focused = api.nvim_get_current_tabpage(), api.nvim_get_current_win()
    ---@type TabBuffersPanelSnapshot
    local snapshot = {
      tab = tab,
      tabs = buffers.tabs(),
      active = nil,
      visible = {},
      entries = {},
      filetype = vim.bo[api.nvim_win_get_buf(focused)].filetype,
      columns = vim.o.columns,
      left = 0,
      right = 0,
      reviews = {},
    }
    local sidebars = {}
    for _, win in ipairs(api.nvim_tabpage_list_wins(tab)) do
      local ordinary = context.ordinary(editor.window(win))
      if ordinary then
        local buf = api.nvim_win_get_buf(win)
        snapshot.visible[buf] = true
        if win == focused and buffers.contains(buf, tab) then
          snapshot.active = buf
        end
      end
      if #config.offsets > 0 then
        sidebars[#sidebars + 1] = {
          ordinary = ordinary,
          filetype = vim.bo[api.nvim_win_get_buf(win)].filetype,
          column = api.nvim_win_get_position(win)[2],
          width = api.nvim_win_get_width(win),
          height = api.nvim_win_get_height(win),
        }
      end
    end
    if config.icons then
      local loaded = package.loaded["nvim-web-devicons"]
      if type(loaded) == "table" then
        icon_provider = loaded
      elseif not icons_attempted then
        icons_attempted = true
        local ok, provider = pcall(require, "nvim-web-devicons")
        if ok then
          icon_provider = provider
        end
      end
    end
    local icons = config.icons and icon_provider or nil
    for _, buf in ipairs(buffers.buffers(tab)) do
      local name, icon = api.nvim_buf_get_name(buf), ""
      if icons then
        local stored = icon_cache[buf]
        if not stored or stored.name ~= name then
          stored = {
            name = name,
            icon = icons.get_icon(vim.fs.basename(name), vim.fn.fnamemodify(name, ":e"), { default = true }) or "",
          }
          icon_cache[buf] = stored
        end
        icon = stored.icon
      end
      snapshot.entries[#snapshot.entries + 1] = { id = buf, name = name, modified = vim.bo[buf].modified, icon = icon }
    end
    for buf in pairs(icon_cache) do
      if not api.nvim_buf_is_valid(buf) then
        icon_cache[buf] = nil
      end
    end
    for _, handle in ipairs(snapshot.tabs) do
      snapshot.reviews[handle] = reviews.is_review(handle)
    end
    local shown = panel.visibility(snapshot, config)
    local height = vim.o.lines - vim.o.cmdheight - (shown == 2 and 1 or 0) - (vim.o.laststatus > 0 and 1 or 0)
    snapshot.left, snapshot.right = panel.offsets(sidebars, snapshot.columns, height, config.offsets)
    return snapshot
  end

  ---@param callbacks TabBuffersPanelCallbacks
  ---@return TabBuffersAction
  function adapter.install(callbacks)
    icon_cache = {}
    local saved = { tabline = vim.o.tabline, showtabline = vim.o.showtabline }
    local group = api.nvim_create_augroup(group_name, { clear = true })
    local ok, err = pcall(function()
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
      }, { group = group, callback = callbacks.changed })
      api.nvim_create_autocmd("User", {
        group = group,
        pattern = { "TabBuffersChanged", "TabBuffersContextChanged" },
        callback = callbacks.changed,
      })
      api.nvim_create_autocmd("OptionSet", {
        group = group,
        pattern = { "ambiwidth", "emoji", "display", "laststatus", "cmdheight", "winbar", "previewwindow" },
        callback = callbacks.metrics or callbacks.changed,
      })
      api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
          icon_cache, icon_provider, icons_attempted = {}, nil, false
          callbacks.theme()
        end,
      })
      vim.o.tabline = expression
    end)
    if not ok then
      pcall(api.nvim_del_augroup_by_id, group)
      error(err, 0)
    end
    original = saved
    local alive = true
    return function()
      if not alive then
        return
      end
      alive = false
      icon_cache = {}
      pcall(api.nvim_del_augroup_by_id, group)
      if vim.o.tabline == expression then
        vim.o.tabline = original.tabline
        if vim.o.showtabline == visibility then
          vim.o.showtabline = original.showtabline
        end
      end
    end
  end

  return adapter
end

return M
