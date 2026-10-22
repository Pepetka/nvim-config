local lualine = require("lualine")
local theme_highlights = require("utils.theme_highlights")

---@param c table
---@return table<string, vim.api.keyset.highlight>
local function capsule_highlights(c)
  local p = c.palette
  local groups = {
    ConfigStatusBranch = { fg = p.magenta, bg = c.surface, bold = true },
    ConfigStatusBranchIcon = { fg = c.surface, bg = p.magenta },
    ConfigStatusFile = { fg = p.green, bg = c.surface },
    ConfigStatusFileIcon = { fg = c.surface, bg = p.green },
    ConfigStatusFileModified = { fg = p.orange, bg = c.surface },
    ConfigStatusFileModifiedIcon = { fg = c.surface, bg = p.orange },
    ConfigStatusRecording = { fg = c.surface, bg = p.yellow },
    ConfigStatusSearch = { fg = c.surface, bg = p.cyan },
    ConfigStatusFiletypeIcon = { fg = c.surface, bg = p.magenta },
    ConfigStatusFiletype = { fg = p.magenta, bg = c.surface },
    ConfigStatusProgress = { fg = c.fg, bg = c.surface },
    ConfigStatusLocation = { fg = c.surface, bg = p.purple, bold = true },
  }
  for name, group in pairs(vim.deepcopy(groups)) do
    groups[name .. "Edge"] = { fg = group.bg }
  end
  groups.ConfigStatusGap = { fg = c.fg }
  groups.ConfigStatusLsp = { fg = c.fg, bold = true }
  groups.ConfigStatusDiffAdd = { fg = p.green, bg = c.surface }
  groups.ConfigStatusDiffChange = { fg = p.orange, bg = c.surface }
  groups.ConfigStatusDiffDelete = { fg = p.red, bg = c.surface }
  return groups
end

theme_highlights.register("lualine", capsule_highlights)

local M = {}
-- Statusline expressions require this module, so `:source %` must replace it for them as well.
package.loaded["configs.lualine"] = M

local EDGE_LEFT, EDGE_RIGHT = "", ""
local SEARCH_MAX_COUNT = 999
local SEARCH_TIMEOUT_MS = 30

---@param text string
---@return string
local function escape(text)
  return (text:gsub("%%", "%%%%"))
end

---@alias StatusSegment { [1]: string, [2]: string }

---Render segments as one rounded capsule; texts are statusline format strings.
---@param segments StatusSegment[]
---@param opts? { gap?: "before"|"after", right?: boolean }
---@return string
local function capsule(segments, opts)
  opts = opts or {}
  local parts = {}
  if opts.gap == "before" then
    parts[#parts + 1] = "%#ConfigStatusGap# "
  end
  parts[#parts + 1] = "%#" .. segments[1][1] .. "Edge#" .. EDGE_LEFT
  for _, segment in ipairs(segments) do
    parts[#parts + 1] = "%#" .. segment[1] .. "#" .. segment[2]
  end
  if opts.right ~= false then
    parts[#parts + 1] = "%#" .. segments[#segments][1] .. "Edge#" .. EDGE_RIGHT
  end
  if opts.gap == "after" then
    parts[#parts + 1] = "%#ConfigStatusGap# "
  end
  return table.concat(parts)
end

-- Native expressions update cursor-dependent fields without rewriting the statusline.
---@param win integer
local function location(win)
  return string.format("%%{printf('%%3d:%%-2d', line('.', %d), charcol('.', %d))}", win, win)
end

---@param win integer
local function progress(win)
  local current = "line('.', " .. win .. ")"
  local total = "max([1, line('$', " .. win .. ")])"
  return "%{"
    .. current
    .. " == 1 ? 'Top' : "
    .. current
    .. " == "
    .. total
    .. " ? 'Bot' : printf('%2d%%', "
    .. current
    .. " * 100 / "
    .. total
    .. ")}"
end

---@class ConfigSearchMatches
---@field positions integer[][] match starts as { line, byte column }, at most SEARCH_MAX_COUNT + 1
---@field incomplete integer 1 after the time limit, 2 after more than SEARCH_MAX_COUNT matches

---@class ConfigSearchState
---@field win? integer window the statusline was rendered for
---@field key? string search state the text belongs to
---@field text string
---@field matches_key? string buffer state the matches belong to
---@field matches? ConfigSearchMatches
---@field before_ex? string @/ before the last Ex command
---@field ex_pattern? string @/ set by an Ex command such as :substitute

---@type ConfigSearchState
local search_state = { text = "" }

---Insert and Replace edits change the buffer on every key, so the count waits until they end.
---@return boolean
local function counting_paused()
  local mode = vim.api.nvim_get_mode().mode:sub(1, 1)
  return mode == "i" or mode == "R" or mode == "c" or mode == "t"
end

-- search("") follows the last search command with its case rules (* ignores 'smartcase'),
-- but an Ex command such as :substitute leaves its own pattern in @/.
local function track_ex_pattern()
  if search_state.before_ex then
    local pattern = vim.fn.getreg("/")
    if pattern ~= search_state.before_ex then
      search_state.ex_pattern = pattern
    end
    search_state.before_ex = nil
  end
end

---Match starts with a real time limit: searchcount() checks its timeout only between matches
---and rescans the whole buffer for every cursor move.
---@param query string
---@return ConfigSearchMatches
local function collect_matches(query)
  local matches = { positions = {}, incomplete = 0 }
  local deadline = vim.uv.hrtime() + SEARCH_TIMEOUT_MS * 1e6
  local cursor = vim.fn.getcurpos()
  vim.fn.cursor(1, 1)
  local flags = "cW"
  while #matches.positions <= SEARCH_MAX_COUNT do
    local remaining = math.ceil((deadline - vim.uv.hrtime()) / 1e6)
    if remaining <= 0 then
      matches.incomplete = 1
      break
    end
    local ok, position = pcall(vim.fn.searchpos, query, flags, 0, remaining)
    if not ok or position[1] == 0 then
      matches.incomplete = ok and vim.uv.hrtime() >= deadline and 1 or 0
      break
    end
    matches.positions[#matches.positions + 1] = position
    flags = "W"
  end
  if #matches.positions > SEARCH_MAX_COUNT then
    matches.incomplete = 2
  end
  vim.fn.cursor({ cursor[2], cursor[3], cursor[4], cursor[5] })
  return matches
end

---@param positions integer[][]
---@param cursor integer[] (1,0)-indexed
---@return integer count of matches that start at or before the cursor
local function matches_before(positions, cursor)
  local low, high = 0, #positions
  while low < high do
    local middle = math.floor((low + high + 1) / 2)
    local line, col = positions[middle][1], positions[middle][2] - 1
    if line < cursor[1] or (line == cursor[1] and col <= cursor[2]) then
      low = middle
    else
      high = middle - 1
    end
  end
  return low
end

---@param matches ConfigSearchMatches
---@param cursor integer[]
---@return string
local function format_search_count(matches, cursor)
  if matches.incomplete == 1 then
    return "[?/??]"
  end
  local total = #matches.positions
  if total == 0 then
    return ""
  end
  local function limited(value)
    return value > SEARCH_MAX_COUNT and ">" .. SEARCH_MAX_COUNT or tostring(value)
  end
  return string.format("[%s/%s]", limited(matches_before(matches.positions, cursor)), limited(total))
end

---@param win integer
---@return string? key, string? matches_key
local function search_keys(win)
  if not vim.o.hlsearch or vim.v.hlsearch == 0 or not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.b[buf].bigfile then
    return nil
  end
  local pattern = vim.fn.getreg("/")
  local matches_key = table.concat({
    buf,
    vim.api.nvim_buf_get_changedtick(buf),
    tostring(vim.o.ignorecase),
    tostring(vim.o.smartcase),
    tostring(pattern == search_state.ex_pattern),
    pattern,
  }, "\0")
  local cursor = vim.api.nvim_win_get_cursor(win)
  return table.concat({ win, cursor[1], cursor[2], matches_key }, "\0"), matches_key
end

---Recompute the count when the search state of the window changed.
---@param win integer
---@return boolean changed whether the text changed
local function update_search(win)
  if counting_paused() then
    return false
  end
  track_ex_pattern()
  local key, matches_key = search_keys(win)
  if win == search_state.win and key == search_state.key then
    return false
  end
  local text = ""
  if key then
    if matches_key ~= search_state.matches_key then
      local pattern = vim.fn.getreg("/")
      local query = pattern == search_state.ex_pattern and pattern or ""
      local matches = { positions = {}, incomplete = 0 }
      pcall(vim.api.nvim_win_call, win, function()
        matches = collect_matches(query)
      end)
      search_state.matches_key, search_state.matches = matches_key, matches
    end
    local count = format_search_count(search_state.matches, vim.api.nvim_win_get_cursor(win))
    text = count ~= "" and capsule({ { "ConfigStatusSearch", count } }, { gap = "after" }) or ""
  end
  local changed = text ~= search_state.text
  search_state.win, search_state.key, search_state.text = win, key, text
  return changed
end

---Search count of the window lualine renders for, evaluated by Neovim on redraw.
---@param win integer
---@return string
function M.search(win)
  if win ~= search_state.win and counting_paused() then
    return ""
  end
  update_search(win)
  return search_state.text
end

---@return string
function M.recording()
  local register = vim.fn.reg_recording()
  if register == "" then
    return ""
  end
  return capsule({ { "ConfigStatusRecording", " recording @" .. escape(register) .. " " } }, { gap = "after" })
end

function M.setup()
  local colors = require("utils.colors")
  local transparent = "none"

  local mode_colors = {
    n = "purple",
    no = "orange",
    i = "green",
    ic = "yellow",
    ix = "yellow",
    v = "yellow",
    V = "yellow",
    ["\22"] = "blue",
    s = "orange",
    S = "orange",
    ["\19"] = "orange",
    R = "orange",
    c = "magenta",
    cv = "red",
    t = "blue",
  }

  ---@return { fg: string, bg: string }
  local function mode_style()
    local mode = vim.api.nvim_get_mode().mode
    local key = mode_colors[mode] and mode or mode_colors[mode:sub(1, 2)] and mode:sub(1, 2) or mode:sub(1, 1)
    return {
      bg = colors.palette[mode_colors[key] or "cyan"],
      fg = key == "cv" and colors.fg or colors.surface,
    }
  end

  local ignored_filetypes = { NvimTree = true, qf = true, dashboard = true }

  ---@type table<string, fun(): boolean>
  local conditions = {
    buffer_editable = function()
      return vim.bo.buftype == ""
    end,
    buffer_not_empty = function()
      return vim.api.nvim_buf_get_name(0) ~= ""
    end,
    -- The global statusline spans the whole editor, not the focused window.
    width_gt_100 = function()
      return vim.o.columns > 100
    end,
    width_gt_80 = function()
      return vim.o.columns > 80
    end,
    width_gt_60 = function()
      return vim.o.columns > 60
    end,
  }

  ---@param ... fun(): boolean
  ---@return fun(): boolean
  local function all(...)
    local fns = { ... }
    return function()
      for _, fn in ipairs(fns) do
        if not fn() then
          return false
        end
      end
      return true
    end
  end

  local editable_file = all(conditions.buffer_not_empty, conditions.buffer_editable)

  local preferred_servers = { "svelte", "vtsls", "tsgo" }

  ---@return string
  local function lsp_name()
    local filetype = vim.bo.filetype
    local supported, first = {}, nil
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
      local filetypes = (client.config --[[@as vim.lsp.Config]]).filetypes
      if filetypes and vim.tbl_contains(filetypes, filetype) then
        supported[client.name] = true
        first = first or client.name
      end
    end
    for _, name in ipairs(preferred_servers) do
      if supported[name] then
        return name
      end
    end
    return first or ""
  end

  local config = {
    options = {
      theme = function()
        return {
          normal = { c = { fg = colors.fg, bg = transparent } },
          inactive = { c = { fg = colors.fg, bg = transparent } },
        }
      end,
      component_separators = "",
      section_separators = "",
      globalstatus = true,
      disabled_filetypes = {
        statusline = { "NvimTree", "qf", "dashboard" },
      },
      ignore_focus = function(win)
        return vim.api.nvim_win_get_config(win).relative ~= ""
          or ignored_filetypes[vim.bo[vim.api.nvim_win_get_buf(win)].filetype] == true
      end,
      refresh = {
        statusline = 1000,
        -- Lualine refreshes every window of the tab for these events; LualineRefresh below handles the rest.
        events = { "SessionLoadPost" },
      },
    },
    sections = {
      lualine_a = {},
      lualine_b = {},
      lualine_c = {
        {
          "mode",
          color = function()
            local style = mode_style()
            return { fg = style.fg, bg = style.bg, gui = "bold" }
          end,
          separator = { right = EDGE_RIGHT },
          padding = { left = 1, right = 0 },
        },
        {
          function()
            local head = vim.b.gitsigns_head
            local name = vim.api.nvim_buf_get_name(0)
            if (not head or head == "") and name ~= "" and vim.fs.relpath(vim.fn.getcwd(), name) then
              -- Gitsigns skips files longer than its max_file_length; they still belong to the working directory repo.
              head = vim.g.gitsigns_head
            end
            if not head or head == "" then
              return ""
            end
            return capsule({
              { "ConfigStatusBranch", escape(head) .. " " },
              { "ConfigStatusBranchIcon", " " },
            }, { gap = "before" })
          end,
          cond = all(conditions.buffer_editable, conditions.width_gt_80),
          padding = 0,
        },
        {
          function()
            local group = vim.bo.modified and "ConfigStatusFileModified" or "ConfigStatusFile"
            return capsule({
              { group, escape(vim.fn.expand("%:t")) .. " " },
              { group .. "Icon", " " },
            }, { gap = "before" })
          end,
          cond = all(editable_file, conditions.width_gt_80),
          padding = 0,
        },
      },
      lualine_x = {
        {
          "lsp_status",
          show_name = false,
          icons_enabled = false,
        },
        {
          function()
            local name = lsp_name()
            return name ~= "" and "%#ConfigStatusLsp# " .. escape(name) .. " %#ConfigStatusGap# " or ""
          end,
          cond = conditions.width_gt_60,
          padding = 0,
        },
        {
          "diff",
          source = function()
            local status = vim.b.gitsigns_status_dict
            if status then
              return { added = status.added, modified = status.changed, removed = status.removed }
            end
          end,
          symbols = { added = " ", modified = "󰝤 ", removed = " " },
          cond = conditions.width_gt_60,
          separator = { left = EDGE_LEFT, right = EDGE_RIGHT },
          color = function()
            return { fg = colors.fg, bg = colors.surface }
          end,
          diff_color = {
            added = "ConfigStatusDiffAdd",
            modified = "ConfigStatusDiffChange",
            removed = "ConfigStatusDiffDelete",
          },
          padding = 0,
        },
        { "diagnostics" },
        {
          function()
            return "%#ConfigStatusGap# "
          end,
          padding = 0,
        },
        {
          function()
            return "%{%v:lua.require'configs.lualine'.recording()%}"
          end,
          cond = conditions.width_gt_80,
          padding = 0,
        },
        {
          function()
            return "%{%v:lua.require'configs.lualine'.search(" .. vim.api.nvim_get_current_win() .. ")%}"
          end,
          cond = conditions.width_gt_80,
          padding = 0,
        },
        {
          function()
            local filetype = vim.bo.filetype
            if filetype == "" then
              return ""
            end
            local ok, devicons = pcall(require, "nvim-web-devicons")
            local icon = ok and (devicons.get_icon(vim.fn.expand("%:t")) or devicons.get_icon_by_filetype(filetype))
            return capsule({
              { "ConfigStatusFiletypeIcon", (icon or "") .. " " },
              { "ConfigStatusFiletype", " " .. escape(filetype) },
            }, { gap = "after" })
          end,
          cond = all(editable_file, conditions.width_gt_100),
          padding = 0,
        },
        {
          function()
            return capsule({
              { "ConfigStatusProgress", " " .. progress(vim.api.nvim_get_current_win()) .. " " },
            }, { gap = "after" })
          end,
          cond = conditions.width_gt_100,
          padding = 0,
        },
        {
          function()
            return capsule(
              { { "ConfigStatusLocation", location(vim.api.nvim_get_current_win()) .. " " } },
              { right = false }
            )
          end,
          padding = 0,
        },
      },
      lualine_y = {},
      lualine_z = {},
    },
    inactive_sections = {},
  }

  lualine.setup(config)

  -- Window scope also covers ignored floats, which display the statusline of the window behind them.
  local group = vim.api.nvim_create_augroup("LualineRefresh", { clear = true })
  vim.api.nvim_create_autocmd({
    "VimEnter",
    "WinEnter",
    "BufEnter",
    "FileType",
    "BufFilePost",
    "BufModifiedSet",
    "FileChangedShellPost",
    "VimResized",
    "ModeChanged",
    "DiagnosticChanged",
    "LspAttach",
    "LspDetach",
  }, {
    group = group,
    callback = function(args)
      lualine.refresh({ scope = "window", place = { "statusline" }, force = args.event == "VimEnter" })
    end,
  })
  -- Neovim redraws the statusline for cursor moves, but not for :nohlsearch, * without a jump or in-place edits.
  -- Only a changed count redraws, so a statusline that hides it cannot loop.
  vim.api.nvim_create_autocmd("SafeState", {
    group = group,
    callback = function()
      track_ex_pattern()
      local win = search_state.win
      if win and vim.o.laststatus ~= 0 and conditions.width_gt_80() and update_search(win) then
        vim.cmd.redrawstatus()
      end
    end,
  })
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      if vim.v.event.cmdtype == ":" and not vim.v.event.abort then
        search_state.before_ex = vim.fn.getreg("/")
      end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "GitSignsUpdate",
    callback = function()
      lualine.refresh({ scope = "window", place = { "statusline" } })
    end,
  })
  lualine.refresh({ scope = "all", place = { "statusline" }, force = true })
end

M.setup()
theme_highlights.on_refresh("lualine", function()
  lualine.refresh({ scope = "all", place = { "statusline" }, force = true })
end, 20)

return M
