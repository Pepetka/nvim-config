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

---@class DashboardCalendarDate
---@field month integer
---@field day integer
---@field yday integer

---Project the standard library's date union onto the dashboard calendar contract.
---@param timestamp? integer
---@return DashboardCalendarDate
M.calendar_date = function(timestamp)
  local date = os.date("*t", timestamp)
  assert(type(date) == "table", "calendar date must be a table")
  return { month = date.month, day = date.day, yday = date.yday }
end

---Return seasonal info for an explicit calendar date.
---@param date DashboardCalendarDate
---@return SeasonalInfo | nil
M.season = function(date)
  local month, day, yday = date.month, date.day, date.yday

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

---Return the dashboard header.
---@param info? SeasonalInfo
---@return string[]
M.header = function(info)
  local header = {}
  for _, line in ipairs(BASE) do
    table.insert(header, line)
  end
  -- Inter-block spacing belongs to the dashboard layout.
  table.remove(header)

  if info then
    header[7] = build_seasonal_frame(info)
  end

  return header
end

---Format dependency statistics without querying Neovim.
---@param count integer
---@param startup_ms? number
---@return string[]
M.format_footer = function(count, startup_ms)
  local ms = startup_ms and string.format("%.0f", startup_ms) or "?"
  local text = string.format("⚡ %d plugins · config %s ms", count, ms)
  local separator = pad("", M.row_length, "center", "─")
  return { separator, text, separator }
end

---Read cheap package statistics; functions keep their closures across reopening.
---@return string[]
M.footer = function()
  local startup_ms = rawget(_G, "nvim_startup_ms")
  return M.format_footer(#vim.pack.get(nil, { info = false }), type(startup_ms) == "number" and startup_ms or nil)
end

return M
