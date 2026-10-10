local M = {}
local utils = require("fzf-lua.utils")

-- Keep the icon's hue using the six terminal colors rather than its RGB value.
-- Neutral icons and directories use ANSI bright black (palette index 8).
local function icon_color(hex)
  local r, g, b = (hex or ""):match("^#(%x%x)(%x%x)(%x%x)$")
  if not r then
    return "grey"
  end
  r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
  local high, low = math.max(r, g, b), math.min(r, g, b)
  local delta = high - low
  if delta == 0 or delta < high * 0.15 then
    return "grey"
  end
  local hue
  if high == r then
    hue = ((g - b) / delta) % 6
  elseif high == g then
    hue = (b - r) / delta + 2
  else
    hue = (r - g) / delta + 4
  end
  return ({ "red", "yellow", "green", "cyan", "blue", "magenta" })[math.floor((hue + 0.5) % 6) + 1]
end

---Apply indexed colors after the native file transform preserves icons and paths.
---This module also runs in fzf-lua's file-list worker; no host theme is needed.
---@param raw string
---@param opts table
---@return string?
function M.file(raw, opts)
  local entry = require("fzf-lua.make_entry").file(raw, opts)
  if not entry then
    return nil
  end
  local prefix, position = "", 1
  if opts.git_icons then
    local separator = assert(entry:find(utils.nbsp, position, true))
    prefix = entry:sub(position, separator + #utils.nbsp - 1)
    position = separator + #utils.nbsp
  end
  if opts.file_icons then
    local separator = assert(entry:find(utils.nbsp, position, true))
    local _, color = require("fzf-lua.devicons").get_devicon(raw)
    prefix = prefix .. utils.ansi_codes[icon_color(color)](entry:sub(position, separator - 1)) .. utils.nbsp
    position = separator + #utils.nbsp
  end
  local filepath = entry:sub(position)
  local directory, filename = filepath:match("^(.*[/\\])([^/\\]+)$")
  if directory then
    filepath = utils.ansi_codes.grey(directory) .. filename
  end
  return prefix .. filepath
end

return M
