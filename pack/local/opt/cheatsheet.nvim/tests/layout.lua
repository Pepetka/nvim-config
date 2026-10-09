local source = debug.getinfo(1, "S").source:sub(2)
local directory = source:match("^(.*[/\\])") or "./"
package.path = directory .. "../lua/?.lua;" .. directory .. "?.lua;" .. package.path
local config = require("cheatsheet.core.config")
local layout = require("cheatsheet.core.layout")
local t = require("support")
local host_vim = rawget(_G, "vim")
_G.vim = nil

---@param text string
---@return integer
local function measure(text)
  local _, codepoints = text:gsub("[^\128-\191]", "")
  local _, wide = text:gsub("界", "")
  return codepoints + wide
end

---@param document CheatsheetDocument
---@return nil
local function check_spans(document)
  for _, span in ipairs(document.spans) do
    local text = document.lines[span.row + 1]
    assert(text, "span row must exist")
    assert(span.start_col >= 0 and span.end_col > span.start_col and span.end_col <= #text)
    -- Neither endpoint may split a UTF-8 continuation byte.
    for _, col in ipairs({ span.start_col, span.end_col }) do
      local byte = text:byte(col + 1)
      assert(not byte or byte < 128 or byte >= 192, "span splits a UTF-8 character")
    end
  end
end

t.test("ASCII document has exact spacing and explicit highlight spans", function()
  local options = config.normalize({
    window = { padding = { left = 1, right = 1, top = 1, bottom = 1 } },
    modes = { "n", "i" },
    mode_align = "left",
    group_underline = false,
  })
  local groups =
    { { name = "tools", icon = "I ", mappings = { { lhs = "a", desc = "Alpha" }, { lhs = "bb", desc = "Beta" } } } }
  local before = t.copy(groups)
  local document = layout.build(groups, "n", options, 16, measure)
  t.equal(document.lines, { " ", " [n]  i  ", " ", " I tools", " ", " a     Alpha", " ", " bb    Beta", " " })
  t.equal(document.spans, {
    { row = 1, start_col = 1, end_col = 9, hl_group = "CheatsheetTitle" },
    { row = 3, start_col = 1, end_col = 3, hl_group = "CheatsheetGroupIcon" },
    { row = 3, start_col = 3, end_col = 8, hl_group = "CheatsheetGroup" },
    { row = 5, start_col = 1, end_col = 3, hl_group = "CheatsheetKey" },
    { row = 5, start_col = 7, end_col = 12, hl_group = "CheatsheetDesc" },
    { row = 7, start_col = 1, end_col = 3, hl_group = "CheatsheetKey" },
    { row = 7, start_col = 7, end_col = 11, hl_group = "CheatsheetDesc" },
  })
  check_spans(document)
  t.equal(groups, before)
end)

t.test("Unicode screen widths and byte columns remain separate", function()
  local options =
    config.normalize({ window = { padding = { left = 0, right = 0, top = 0, bottom = 0 } }, mode_align = "left" })
  local document = layout.build({
    { name = "tools", icon = "★ ", mappings = { { lhs = "界", desc = "Wide" }, { lhs = "é", desc = "Accent" } } },
  }, "n", options, 12, measure)
  t.equal(document.lines[3], "★ tools")
  t.equal(document.lines[4], string.rep("─", 12))
  t.equal(document.lines[5], "界    Wide")
  t.equal(document.lines[7], "é     Accent")
  t.equal(document.spans[2], { row = 2, start_col = 0, end_col = 4, hl_group = "CheatsheetGroupIcon" })
  t.equal(document.spans[3].start_col, 4)
  t.equal(document.spans[5].end_col, 3)
  t.equal(document.spans[6].start_col, 7)
  check_spans(document)
end)

t.test("empty icons never color the group name as an icon", function()
  local options = config.normalize()
  local document = layout.build({ { name = "tools with spaces", icon = "", mappings = {} } }, "n", options, 30, measure)
  for _, span in ipairs(document.spans) do
    assert(span.hl_group ~= "CheatsheetGroupIcon")
  end
  check_spans(document)
end)

t.test("icon boundaries include embedded spaces rather than parsing a first word", function()
  local options = config.normalize()
  local document = layout.build({ { name = "group", icon = "A B ", mappings = {} } }, "n", options, 30, measure)
  t.equal(document.spans[2].end_col - document.spans[2].start_col, 4)
end)

t.test("empty results show a message and highlight it as a description", function()
  local document = layout.build({}, "i", config.normalize(), 30, measure)
  t.equal(document.lines[4], "  No mappings for i mode")
  t.equal(document.spans[2], { row = 3, start_col = 2, end_col = 24, hl_group = "CheatsheetDesc" })
  check_spans(document)
end)

t.test("empty descriptions produce no zero-length highlight spans", function()
  local document = layout.build(
    { { name = "other", icon = "", mappings = { { lhs = "x", desc = "" } } } },
    "n",
    config.normalize(),
    20,
    measure
  )
  for _, span in ipairs(document.spans) do
    assert(span.hl_group ~= "CheatsheetDesc")
  end
  check_spans(document)
end)

t.test("alignment works for all modes and group headings", function()
  for _, align in ipairs({ "left", "center", "right" }) do
    local options = config.normalize({
      window = { padding = { left = 1, right = 1, top = 0, bottom = 0 } },
      modes = { "n" },
      mode_align = align,
      group_align = align,
      group_underline = false,
    })
    local document = layout.build({ { name = "ab", icon = "", mappings = {} } }, "n", options, 12, measure)
    local expected = align == "left" and 1 or align == "center" and 5 or 9
    t.equal(document.lines[3], string.rep(" ", expected) .. "ab")
    check_spans(document)
  end
  t.equal(layout.offset("right", 2, 10, 1), 1)
  t.equal(layout.offset("center", 9, 2, 1), 4)
end)

t.test("content can scroll horizontally when wider than its window or padding", function()
  local options = config.normalize({ window = { padding = { left = 10, right = 10 } } })
  local document = layout.build(
    { { name = "very long group", icon = "", mappings = { { lhs = "long mapping", desc = "Long description" } } } },
    "n",
    options,
    1,
    measure
  )
  assert(document.lines[6]:find("Long description", 1, true))
  t.equal(document.lines[5], string.rep(" ", 10) .. "─")
  check_spans(document)
end)

t.test("group and mapping spacing has no trailing inter-group blanks", function()
  local options = config.normalize({
    window = { padding = { left = 0, top = 0, bottom = 0 } },
    mode_align = "left",
    group_underline = false,
  })
  local document = layout.build({
    { name = "first", icon = "", mappings = { { lhs = "a", desc = "A" } } },
    { name = "second", icon = "", mappings = { { lhs = "b", desc = "B" } } },
  }, "n", options, 20, measure)
  t.equal(document.lines[6], "")
  t.equal(document.lines[7], "")
  t.equal(document.lines[8], "second")
  t.equal(document.lines[#document.lines], "b    B")
end)

t.test("geometry reserves border cells and centers the full float", function()
  local options = config.normalize()
  t.equal(
    layout.geometry(options.window, { columns = 120, lines = 40 }),
    { width = 96, height = 32, row = 3, col = 11 }
  )
  options.window.width, options.window.height = 1, 1
  for _, border in ipairs({ "none", "shadow", "single", "double", "rounded", "solid" }) do
    options.window.border = border
    local reserved = border == "none" and 0 or border == "shadow" and 1 or 2
    t.equal(
      layout.geometry(options.window, { columns = 12, lines = 8 }),
      { width = 12 - reserved, height = 8 - reserved, row = 0, col = 0 }
    )
  end
end)

t.test("tiny ratios and viewports never produce zero or negative dimensions", function()
  local options = config.normalize({ window = { width = 0.001, height = 0.001 } })
  for _, viewport in ipairs({ { columns = 1, lines = 1 }, { columns = 12, lines = 3 }, { columns = 0, lines = 0 } }) do
    local geometry = layout.geometry(options.window, viewport)
    t.equal(geometry.width, 1)
    t.equal(geometry.height, 1)
    assert(geometry.row >= 0 and geometry.col >= 0)
  end
end)

t.test("mode labels and key widths handle empty and mixed-width groups", function()
  t.equal(layout.mode_label({ "n", "i" }, "i"), " n  [i] ")
  t.equal(layout.key_width({}, measure), 0)
  t.equal(layout.key_width({ { mappings = { { lhs = "界" }, { lhs = "aaa" } } } }, measure), 3)
end)

t.test("custom column gap and vertical spacing produce exact lines and spans", function()
  local options = config.normalize({
    layout = { key_gap = 2, mapping_spacing = 2, group_spacing = 3 },
    window = { padding = { left = 0, right = 0, top = 0, bottom = 0 } },
    modes = { "n" },
    mode_align = "left",
    group_underline = false,
  })
  local document = layout.build({
    { name = "first", icon = "", mappings = { { lhs = "a", desc = "Alpha" }, { lhs = "界", desc = "Wide" } } },
    { name = "second", icon = "", mappings = { { lhs = "bb", desc = "Beta" } } },
  }, "n", options, 20, measure)
  t.equal(
    document.lines,
    { "[n] ", "", "first", "", "a   Alpha", "", "", "界  Wide", "", "", "", "second", "", "bb  Beta" }
  )
  local starts = {}
  for _, span in ipairs(document.spans) do
    if span.hl_group == "CheatsheetDesc" then
      starts[#starts + 1] = { span.row, span.start_col }
    end
  end
  t.equal(starts, { { 4, 4 }, { 7, 5 }, { 13, 4 } })
  check_spans(document)
end)

t.test("zero spacing creates compact rows without trailing blanks or overlapping spans", function()
  local options = config.normalize({
    layout = { key_gap = 0, mapping_spacing = 0, group_spacing = 0 },
    window = { padding = { left = 0, right = 0, top = 0, bottom = 0 } },
    modes = { "n" },
    mode_align = "left",
    group_underline = false,
  })
  local document = layout.build({
    { name = "first", icon = "", mappings = { { lhs = "a", desc = "Alpha" }, { lhs = "b", desc = "Beta" } } },
    { name = "second", icon = "", mappings = { { lhs = "c", desc = "Gamma" } } },
  }, "n", options, 20, measure)
  t.equal(document.lines, { "[n] ", "", "first", "", "aAlpha", "bBeta", "second", "", "cGamma" })
  for index, span in ipairs(document.spans) do
    if span.hl_group == "CheatsheetKey" then
      t.equal(span.end_col, document.spans[index + 1].start_col)
    end
  end
  check_spans(document)
end)

local ok, err = pcall(t.run, "cheatsheet layout (without vim)")
_G.vim = host_vim
assert(ok, err)
