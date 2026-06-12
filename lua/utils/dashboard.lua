local pad = require("utils.pad")

local M = {}

M.row_length = 42

---@type string[]
local BASE = {
  " ██████╗    ██████╗    ██████╗    ███████╗",
  "██╔════╝   ██╔═══██╗   ██╔══██╗   ██╔════╝",
  "██║        ██║   ██║   ██████╔╝   █████╗  ",
  "██║        ██║   ██║   ██╔══██╗   ██╔══╝  ",
  "╚██████╗██╗╚██████╔╝██╗██║  ██║██╗███████╗",
  " ╚═════╝╚═╝ ╚═════╝ ╚═╝╚═╝  ╚═╝╚═╝╚══════╝",
  "╭────────────────────────────────────────╮",
  "│    Code. Organize. Refine. Execute.    │",
  "╰────────────────────────────────────────╯",
  "                                          ",
}

---@class SeasonalInfo
---@field text string
---@field icon string
---@field color string tokyonight color name for DashboardHeader

---Return seasonal info for the current date, if any.
---@return SeasonalInfo | nil
local get_seasonal_info = function()
  local month = tonumber(os.date("%m"))
  local day = tonumber(os.date("%d"))
  local yday = tonumber(os.date("%j"))

  if month == 3 and day >= 7 and day <= 9 then
    return { text = "Happy Women's Day", icon = "♀", color = "magenta" }
  end

  if month == 5 and day >= 1 and day <= 3 then
    return { text = "Happy May Day", icon = "🌱", color = "green" }
  end

  if month == 5 and day >= 8 and day <= 10 then
    return { text = "Remember & Honor", icon = "✦", color = "blue" }
  end

  if yday == 256 then
    return { text = "Programmer's Day", icon = "01", color = "blue" }
  end

  if month == 10 and day >= 28 and day <= 31 then
    return { text = "Happy Halloween", icon = "🎃", color = "orange" }
  end

  if (month == 12 and day >= 21) or (month == 1 and day <= 10) then
    return { text = "Happy New Year", icon = "❄", color = "cyan" }
  end

  return nil
end

---Build the top frame line with seasonal text embedded in the border.
---@param info SeasonalInfo
---@return string
local build_seasonal_frame = function(info)
  local inner = " " .. info.icon .. " " .. info.text .. " " .. info.icon .. " "
  local content = pad(inner, M.row_length - 2, "center", "─")
  return "╭" .. content .. "╮"
end

---Return the hex color for the current season, if any.
---@return string | nil
M.get_seasonal_highlight = function()
  local info = get_seasonal_info()
  return info and info.color or nil
end

local header_cache ---@type string[]?

---Return the dashboard header.
---@return string[]
M.get_header = function()
  if header_cache then
    return header_cache
  end

  local info = get_seasonal_info()
  local header = {}
  for _, line in ipairs(BASE) do
    table.insert(header, line)
  end

  if info then
    header[7] = build_seasonal_frame(info)
  end

  header_cache = header
  return header
end

---Return the dashboard footer lines with plugin count and startup time.
---@return string[]
M.footer = function()
  local count = #vim.pack.get()
  local ms = _G.nvim_startup_ms and string.format("%.0f", _G.nvim_startup_ms) or "?"
  local text = string.format("⚡ Loaded %d plugins in %s ms", count, ms)
  local separator = pad("", M.row_length, "center", "─")
  return { separator, text, separator }
end

return M
