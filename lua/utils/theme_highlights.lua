local colors = require("utils.colors")
local M = {}
local providers, refreshers = {}, {}
local queued = false

local function active()
  return colors.ready() and (vim.g.colors_name or ""):match("^tokyonight%-") ~= nil
end

local function call(name, fn, ...)
  local ok, result = pcall(fn, ...)
  if not ok then
    vim.notify("Theme update failed for " .. name .. ": " .. result, vim.log.levels.ERROR)
    return nil
  end
  return result
end

local function sorted_names(entries)
  local names = vim.tbl_keys(entries)
  table.sort(names)
  return names
end

local function apply(name)
  local groups = call(name, providers[name], colors.get()) or {}
  for group, highlight in pairs(groups) do
    vim.api.nvim_set_hl(0, group, highlight)
  end
end

---Definitions are pure: return highlight groups from the current color snapshot.
---Registration replaces the previous provider and applies it immediately.
---@param name string
---@param provider fun(colors: table, base?: table): table<string, vim.api.keyset.highlight>
function M.register(name, provider)
  providers[name] = provider
  if active() then
    apply(name)
  end
end

---Extend TokyoNight's highlights before plugins derive their own colors.
---@param highlights table<string, vim.api.keyset.highlight>
function M.extend(highlights)
  for _, name in ipairs(sorted_names(providers)) do
    local groups = call(name, providers[name], colors.get(), highlights) or {}
    for group, highlight in pairs(groups) do
      highlights[group] = highlight
    end
  end
end

function M.apply_all()
  if active() then
    for _, name in ipairs(sorted_names(providers)) do
      apply(name)
    end
  end
end

---Refresh derived UI after native ColorScheme/OptionSet handlers finish.
---@param name string
---@param fn fun()
---@param priority? integer Lower priorities run first.
function M.on_refresh(name, fn, priority)
  refreshers[name] = { fn = fn, priority = priority or 0 }
end

function M.refresh()
  -- Startup registrations already apply their groups. A startup redraw can
  -- expose a dashboard that is still being assembled by another callback.
  if queued or vim.v.vim_did_enter == 0 or not active() then
    return
  end
  queued = true
  vim.schedule(function()
    queued = false
    if not active() then
      return
    end
    M.apply_all()
    local names = vim.tbl_keys(refreshers)
    table.sort(names, function(a, b)
      local ap, bp = refreshers[a].priority, refreshers[b].priority
      return ap < bp or (ap == bp and a < b)
    end)
    for _, name in ipairs(names) do
      call(name, refreshers[name].fn)
    end
    vim.cmd.redraw()
  end)
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("ThemeHighlights", { clear = true }),
  callback = M.refresh,
})

return M
