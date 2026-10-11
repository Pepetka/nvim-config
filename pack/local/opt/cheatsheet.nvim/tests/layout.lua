local source = debug.getinfo(1, "S").source:sub(2)
local directory = source:match("^(.*[/\\])") or "./"
package.path = directory .. "../lua/?.lua;" .. directory .. "?.lua;" .. package.path
local config = require("cheatsheet.core.config")
local layout = require("cheatsheet.core.layout")
local t = require("support")
local host_vim = rawget(_G, "vim")
_G.vim = nil

local measure = t.measure

local check_spans = t.check_spans

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
  t.equal(document.lines, { " ", " [normal]  insert  ", " ", " I tools", " ", " a     Alpha", " ", " bb    Beta", " " })
  t.equal(document.spans, {
    { row = 1, start_col = 1, end_col = 19, hl_group = "CheatsheetTitle" },
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
  t.equal(document.lines[4], "  No mappings for insert mode")
  t.equal(document.spans[2], { row = 3, start_col = 2, end_col = 29, hl_group = "CheatsheetDesc" })
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
    layout = { max_columns = 1 },
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
  t.equal(layout.mode_label({ "n", "i" }, "i"), " normal  [insert] ")
  t.equal(layout.mode_label({ "v", "o", "t" }, "o"), " visual  [operator]  terminal  ")
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
    { "[normal] ", "", "first", "", "a   Alpha", "", "", "界  Wide", "", "", "", "second", "", "bb  Beta" }
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
    layout = { key_gap = 0, mapping_spacing = 0, group_spacing = 0, max_columns = 1 },
    window = { padding = { left = 0, right = 0, top = 0, bottom = 0 } },
    modes = { "n" },
    mode_align = "left",
    group_underline = false,
  })
  local document = layout.build({
    { name = "first", icon = "", mappings = { { lhs = "a", desc = "Alpha" }, { lhs = "b", desc = "Beta" } } },
    { name = "second", icon = "", mappings = { { lhs = "c", desc = "Gamma" } } },
  }, "n", options, 20, measure)
  t.equal(document.lines, { "[normal] ", "", "first", "", "aAlpha", "bBeta", "second", "", "cGamma" })
  for index, span in ipairs(document.spans) do
    if span.hl_group == "CheatsheetKey" then
      t.equal(span.end_col, document.spans[index + 1].start_col)
    end
  end
  check_spans(document)
end)

---@param name string
---@param mappings CheatsheetDisplayMapping[]
---@return CheatsheetDisplayGroup
local function group(name, mappings)
  return { name = name, icon = "", mappings = mappings }
end

t.test("column target caps natural width and keeps headers and keys readable", function()
  local groups = { group("tools", { { lhs = "ab", desc = string.rep("x", 30) } }) }
  local options = config.normalize({ layout = { key_gap = 4, max_column_width = 20 } })
  t.equal(layout.column_target(groups, options, measure), 20)
  options.layout.max_column_width = 60
  t.equal(layout.column_target(groups, options, measure), 36)
  options.layout.max_column_width = 1
  t.equal(layout.column_target(groups, options, measure), 7)
  groups[1].name = string.rep("n", 12)
  t.equal(layout.column_target(groups, options, measure), 12)
end)

t.test("mapping lines wrap descriptions under the description column", function()
  local mapping = { lhs = "a", desc = "one two three" }
  t.equal(layout.mapping_lines(mapping, 2, 1, 7, measure), {
    lines = { "a  one two", "   three" },
    spans = {
      { row = 0, start_col = 0, end_col = 2, hl_group = "CheatsheetKey" },
      { row = 0, start_col = 3, end_col = 10, hl_group = "CheatsheetDesc" },
      { row = 1, start_col = 3, end_col = 8, hl_group = "CheatsheetDesc" },
    },
  })
  t.equal(layout.mapping_lines(mapping, 2, 1, nil, measure).lines, { "a  one two three" })
  t.equal(layout.mapping_lines({ lhs = "x", desc = "" }, 1, 1, 5, measure).lines, { "x " })
end)

t.test("blocks are column-relative with aligned headers and column-wide separators", function()
  local options = config.normalize({ group_align = "center", layout = { key_gap = 1, mapping_spacing = 1 } })
  local block = layout.block(
    { name = "git", icon = "I ", mappings = { { lhs = "a", desc = "Alpha beta" }, { lhs = "bb", desc = "Gamma" } } },
    2,
    10,
    options,
    measure,
    7
  )
  t.equal(block.lines, { "  I git", string.rep("─", 10), "a  Alpha", "   beta", "", "bb Gamma" })
  t.equal(block.spans[1], { row = 0, start_col = 2, end_col = 4, hl_group = "CheatsheetGroupIcon" })
  t.equal(block.spans[3], { row = 1, start_col = 0, end_col = 30, hl_group = "CheatsheetSeparator" })
  t.check_spans(block)
end)

t.test("block height matches rendered blocks for every spacing and wrap combination", function()
  local subject = group("tools", {
    { lhs = "a", desc = "short" },
    { lhs = "bb", desc = "a longer description that wraps" },
    { lhs = "c", desc = "" },
  })
  for _, underline in ipairs({ true, false }) do
    for spacing = 0, 2 do
      for _, desc_width in ipairs({ false, 3, 10, 100 }) do
        local options = config.normalize({ group_underline = underline, layout = { mapping_spacing = spacing } })
        local width = desc_width or nil
        local block = layout.block(subject, 2, 30, options, measure, width)
        t.equal(layout.block_height(subject, options, measure, width), #block.lines)
      end
    end
  end
end)

t.test("column height uses the key width of its own range", function()
  local options = config.normalize({ group_underline = false, layout = { key_gap = 1, group_spacing = 1 } })
  local groups = {
    group("a", { { lhs = "a", desc = "aa bb cc" } }),
    group("b", { { lhs = "abcdef", desc = "x" } }),
  }
  t.equal(layout.column_height(groups, { first = 1, last = 1 }, 12, options, measure, true), 3)
  t.equal(layout.column_height(groups, { first = 1, last = 2 }, 12, options, measure, true), 4 + 1 + 3)
  t.equal(layout.column_height(groups, { first = 1, last = 2 }, 12, options, measure, false), 3 + 1 + 3)
  for _, wrap in ipairs({ true, false }) do
    local range = { first = 1, last = 2 }
    t.equal(
      layout.column_height(groups, range, 12, options, measure, wrap),
      #layout.column(groups, range, 12, options, measure, wrap).lines
    )
  end
end)

---@param width integer
---@param max_columns? integer
---@return CheatsheetDocument
local function multi(width, max_columns)
  local options = config.normalize({
    window = { padding = { left = 1, right = 1, top = 0, bottom = 0 } },
    modes = { "n" },
    mode_align = "left",
    group_underline = false,
    layout = {
      key_gap = 1,
      mapping_spacing = 0,
      group_spacing = 1,
      column_gap = 2,
      max_column_width = 10,
      max_columns = max_columns,
    },
  })
  return layout.build({
    group("a", { { lhs = "a", desc = "Alpha" } }),
    group("b", { { lhs = "bb", desc = "Beta one two" } }),
    group("c", { { lhs = "c", desc = "Gamma" } }),
  }, "n", options, width, measure)
end

t.test("wide documents place groups in columns with their own key widths and wrapping", function()
  local document = multi(36)
  local pad = string.rep(" ", 11)
  t.equal(document.lines, {
    " [normal] ",
    " ",
    " a" .. pad .. "b" .. pad .. "c",
    " ",
    " a Alpha     bb Beta     c Gamma",
    " " .. string.rep(" ", 12) .. "   one two",
  })
  t.check_spans(document)
  for row = 3, #document.lines do
    local line = document.lines[row]
    assert(line == " " or not line:find("%s$"), "trailing whitespace: " .. line)
  end
  local continuation = false
  for _, span in ipairs(document.spans) do
    if span.row == 5 and span.hl_group == "CheatsheetDesc" then
      t.equal(document.lines[6]:sub(span.start_col + 1, span.end_col), "one two")
      continuation = true
    end
  end
  assert(continuation, "continuation lines must be highlighted as descriptions")
end)

t.test("narrow documents keep the unwrapped single-column layout", function()
  t.equal(multi(20), multi(20, 1))
  t.equal(multi(36, 1).lines[9], " bb Beta one two")
  t.equal(multi(36, 2).lines[3], " a" .. string.rep(" ", 17) .. "c")
end)

t.test("columns keep the newspaper order of groups", function()
  local options = config.normalize({
    window = { padding = { left = 0, right = 0, top = 0, bottom = 0 } },
    modes = { "n" },
    mode_align = "left",
    group_underline = false,
    layout = { key_gap = 1, mapping_spacing = 0, group_spacing = 1, column_gap = 1, max_columns = 2 },
  })
  local mappings = { { lhs = "a", desc = "Alpha" } }
  local document = layout.build({
    group("g1", { mappings[1], mappings[1], mappings[1] }),
    group("g2", mappings),
    group("g3", mappings),
    group("g4", mappings),
  }, "n", options, 40, measure)
  local gap = string.rep(" ", 18)
  t.equal(document.lines[3], "g1" .. gap .. "g3")
  t.equal(document.lines[7], "a Alpha" .. string.rep(" ", 13) .. "g4")
  t.equal(document.lines[9], "g2" .. gap .. "a Alpha")
  t.equal(#document.lines, 11)
  t.check_spans(document)
end)

t.test("column target uses each group's own key width", function()
  local options = config.normalize({ layout = { key_gap = 4, max_column_width = 60 } })
  local groups = {
    group("a", { { lhs = string.rep("k", 20), desc = "short" } }),
    group("b", { { lhs = "x", desc = string.rep("d", 40) } }),
  }
  t.equal(layout.column_target(groups, options, measure), 45)
  options.layout.max_column_width = 1
  t.equal(layout.column_target(groups, options, measure), 25)
end)

t.test("fit clips overflowing lines and their spans", function()
  local document = layout.fit({
    lines = { "abcdef", "ab", "a界b" },
    spans = {
      { row = 0, start_col = 0, end_col = 6, hl_group = "CheatsheetDesc" },
      { row = 0, start_col = 4, end_col = 6, hl_group = "CheatsheetKey" },
      { row = 2, start_col = 1, end_col = 5, hl_group = "CheatsheetDesc" },
    },
  }, 2, measure)
  t.equal(document.lines, { "ab", "ab", "a" })
  t.equal(document.spans, { { row = 0, start_col = 0, end_col = 2, hl_group = "CheatsheetDesc" } })
end)

t.test("separators fill the column by cells for double-width box characters", function()
  local options = config.normalize()
  ---@param value string
  ---@return integer
  local function wide_box(value)
    local _, boxes = value:gsub("─", "")
    return measure(value) + boxes
  end
  local block = layout.block(group("g", {}), 0, 11, options, wide_box)
  t.equal(block.lines[2], string.rep("─", 5))
end)

t.test("segments wider than their column never shift neighbouring columns", function()
  local options = config.normalize({
    window = { padding = { left = 0, right = 0, top = 0, bottom = 0 } },
    modes = { "n" },
    group_underline = false,
    layout = { key_gap = 1, column_gap = 1, max_column_width = 1, mapping_spacing = 0 },
  })
  local groups = {
    group("a", { { lhs = "abcdefgh", desc = "界界" } }),
    group("b", { { lhs = "b", desc = "Beta" } }),
  }
  local document = layout.build(groups, "n", options, 21, measure)
  t.equal(document.columns, 2)
  for row = 3, #document.lines do
    local line = document.lines[row]
    local second = line:sub(12)
    assert(measure(line:sub(1, 11)) <= 11, "first column overflows: " .. line)
    assert(second == "" or line:sub(11, 11) == " ", "second column shifted: " .. line)
  end
  t.check_spans(document)
end)

t.test("wrapped descriptions are cached between height and rendering", function()
  local calls = 0
  ---@param value string
  ---@return integer
  local function counting(value)
    calls = calls + 1
    return measure(value)
  end
  local options = config.normalize()
  local subject = group("g", { { lhs = "a", desc = "one two three four" } })
  layout.block_height(subject, options, counting, 5)
  local first = calls
  layout.block_height(subject, options, counting, 5)
  t.equal(calls, first)
  t.equal(layout.mapping_lines(subject.mappings[1], 1, 1, 5, counting).lines[2], "  two")
end)

t.test("complete documents report their column count", function()
  t.equal(multi(36).columns, 3)
  t.equal(multi(20).columns, 1)
  t.equal(layout.build({}, "n", config.normalize(), 40, measure).columns, 1)
end)

local ok, err = pcall(t.run, "cheatsheet layout (without vim)")
_G.vim = host_vim
assert(ok, err)
