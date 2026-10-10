-- Host content and screen geometry, against snapshots captured from dashboard-nvim.
local root = vim.fn.getcwd()
local plugin = root .. "/pack/local/opt/dashboard.nvim"
vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(plugin)
package.path = plugin .. "/tests/?.lua;" .. package.path
local fixtures = require("fixtures")
local t = require("support")
local content = require("utils.dashboard")
local state = fixtures.new()
state.adapter.measure = vim.fn.strdisplaywidth
package.loaded.dashboard = state.api
require("utils.colors").update({ blue = "#123456", comment = "#456789", error = "#987654" })
local original_season = content.season
-- The historical snapshots are nonseasonal; calendar behavior is tested below.
---@param date DashboardCalendarDate
---@return SeasonalInfo?
content.season = function(date)
  return nil
end
require("configs.dashboard")
content.season = original_season

for _, size in ipairs({ { 120, 50 }, { 140, 60 } }) do
  t.test("historical dashboard geometry with corrected menu at " .. size[1] .. "x" .. size[2], function()
    state.contexts[1] = { win = 1, source_buf = 1001, width = size[1], height = size[2] - 1 }
    state.api.show()
    local actual = {}
    for _, line in ipairs(state.live[1].document.lines) do
      actual[#actual + 1] = line:find("plugins · config", 1, true) and "<statistics>" or line:gsub("%s+$", "")
    end
    local expected =
      vim.json.decode(table.concat(vim.fn.readfile(plugin .. "/tests/view-" .. size[1] .. ".json"), "\n"))
    -- Preserve the historical fixture; widen labels by one cell to match the frames.
    for row, line in ipairs(expected) do
      if line:match("%[[frgeq]%]$") then
        expected[row] = line:gsub("(%[[frgeq]%])$", " %1")
      end
    end
    t.equal(actual, expected)
    state.api.hide()
  end)
end

t.test("both menu edges match the frames at every window width", function()
  for width = 35, 145 do
    state.contexts[1] = { win = 1, source_buf = 1001, width = width, height = 49 }
    state.api.show()
    local edges = {}
    for _, line in ipairs(state.live[1].document.lines) do
      if line:find("Find file", 1, true) or line:find("╭", 1, true) or line:match("^ *─") then
        edges[#edges + 1] = #assert(line:match("^ *"))
      end
    end
    local left = math.max(0, math.floor((width - 42) / 2))
    t.equal(edges, { left, left, left, left }, "misaligned blocks at width " .. width)
    local actions = 0
    for _, line in ipairs(state.live[1].document.lines) do
      if line:match("%[[frgeq]%]$") then
        actions = actions + 1
        t.equal(#assert(line:match("^ *")), left)
        t.equal(vim.fn.strdisplaywidth(line), left + content.row_length, "menu right edge at width " .. width)
      end
    end
    t.equal(actions, 5)
    state.api.hide()
  end
end)

t.test("standard library calendar values have an explicit typed projection", function()
  local date = content.calendar_date(os.time({ year = 2024, month = 9, day = 12, hour = 12 }))
  t.equal(date, { month = 9, day = 12, yday = 256 })
  t.equal(assert(content.season(date)).color, "blue")
  assert(type(content.calendar_date().month) == "number")
end)

t.test("seasonal data uses explicit dates including leap-year programmer day", function()
  local cases = {
    { month = 3, day = 8, yday = 67, color = "magenta" },
    { month = 5, day = 1, yday = 121, color = "green" },
    { month = 5, day = 9, yday = 129, color = "blue" },
    { month = 9, day = 12, yday = 256, color = "blue" },
    { month = 10, day = 31, yday = 304, color = "orange" },
    { month = 12, day = 25, yday = 359, color = "cyan" },
    { month = 1, day = 1, yday = 1, color = "cyan" },
  }
  for _, date in ipairs(cases) do
    t.equal(assert(content.season(date)).color, date.color)
  end
  t.equal(content.season({ month = 10, day = 10, yday = 283 }), nil)
end)

t.test("headers are independent and seasonal decoration affects only its frame", function()
  local base = content.header()
  local decorated = content.header({ text = "Season", icon = "★", color = "blue" })
  assert(decorated[7]:find("Season", 1, true))
  for index, line in ipairs(base) do
    if index ~= 7 then
      t.equal(decorated[index], line)
    end
  end
  decorated[1] = "changed"
  t.equal(content.header(), base)
end)

t.test("statistics formatting is separate from collection", function()
  t.equal(content.format_footer(3, 12.4)[2], "⚡ 3 plugins · config 12 ms")
  t.equal(content.format_footer(3)[2], "⚡ 3 plugins · config ? ms")
end)

t.run("Dashboard host")
