local directory = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or "./"
package.path = directory .. "../lua/?.lua;" .. directory .. "?.lua;" .. package.path
local rules = require("dashboard.core.config")
local blocks = require("dashboard.core.blocks")
local layout = require("dashboard.core.layout")
local nav = require("dashboard.core.navigation")
local styles = require("dashboard.core.styles")
local keys = require("dashboard.core.keys")
local t = require("support")
local host_vim = rawget(_G, "vim")
_G.vim = nil

---@param text string
---@return integer
local function measure(text)
  local _, length = text:gsub("[^\128-\191]", "")
  return length
end

---@type DashboardContext
local context = { win = 1, source_buf = 2, width = 20, height = 10 }

t.test("normalization owns its data and respects false and zero", function()
  local options = {
    blocks = { { id = "title", type = "text", lines = { "hello" } } },
    layout = { gap = 0 },
    hide_chrome = false,
    autostart = false,
  }
  local before = t.copy(options)
  local config = rules.normalize(options)
  config.blocks[1].id = "changed"
  t.equal(options, before)
  t.equal(config.hide_chrome, false)
  t.equal(config.autostart, false)
  t.equal(config.layout.gap, 0)
  t.equal(rules.normalize().blocks, {})
end)

---@type unknown[]
local invalid = {
  false,
  { blocks = false },
  { layout = false },
  { layout = { gap = false } },
  { blocks = { { id = "a", type = "actions", items = {}, spacing = false } } },
  { surprise = true },
  { layout = { horizontal = "bad" } },
  { layout = { gap = -1 } },
  { layout = { gap = math.huge } },
  { layout = { gap = 0.5 } },
  { autostart = 1 },
  { highlights = false },
  { blocks = { { id = "", type = "text", lines = {} } } },
  { blocks = { { id = "title", type = "unknown" } } },
  { blocks = { { id = "title", type = "text", lines = { "a\nb" } } } },
  { blocks = { { id = "title", type = "custom" } } },
  { blocks = { { id = "title", type = "text", lines = {} }, { id = "title", type = "text", lines = {} } } },
  { blocks = { { id = "menu", type = "actions", items = { { id = "a", label = "a", run = 1 } } } } },
}
for index, input in ipairs(invalid) do
  t.test("reject invalid configuration " .. index, function()
    assert(not pcall(rules.normalize, input))
  end)
end

t.test("text uses byte spans and leaves inputs untouched", function()
  local lines = { "Привет", "", "界" }
  local doc = blocks.text(lines, "Header")
  t.equal(doc.lines, lines)
  t.equal(doc.spans, {
    { row = 0, start_col = 0, end_col = 12, style = "Header" },
    { row = 2, start_col = 0, end_col = 3, style = "Header" },
  })
  doc.lines[1] = "changed"
  t.equal(lines[1], "Привет")
end)

t.test("actions measure labels and separate bytes from cells", function()
  local doc = blocks.actions({
    { id = "a", label = "ёж", icon = "★", key = "f", run = "echo 1" },
    { id = "b", label = "long", run = "echo 2" },
  }, 0, 1, measure)
  t.equal(doc.lines, { "★ ёж    [f]", "", "long" })
  t.equal(doc.targets[1].col, 4)
  t.equal(doc.targets[2].row, 2)
  t.equal(doc.spans[2], { row = 0, start_col = 4, end_col = 10, style = "Text" })
end)

t.test("spacing zero has no extra lines", function()
  local doc =
    blocks.actions({ { id = "a", label = "a", run = "" }, { id = "b", label = "b", run = "" } }, 0, 0, measure)
  t.equal(doc.lines, { "a", "b" })
end)

t.test("layout centers lines and shifts ranges and targets", function()
  local fragment = blocks.actions({ { id = "go", label = "abc", run = "" } }, 0, 0, measure)
  local before = t.copy(fragment)
  local doc = layout.compose({ fragment }, { "menu" }, context, rules.normalize().layout, measure)
  t.equal(#doc.lines, 5)
  t.equal(doc.lines[5], "        abc")
  t.equal(doc.targets[1], { id = "go", block_id = "menu", row = 4, col = 8, run = "" })
  t.equal(doc.spans[1].start_col, 8)
  t.equal(fragment, before)
end)

t.test("shared canvas keeps Unicode blocks, spans and targets aligned across window parity", function()
  local fragments = {
    blocks.text({ "------" }, "Header"),
    blocks.actions({ { id = "go", label = "ёжabc", run = "" } }, 0, 0, measure),
    blocks.text({ "------" }, "Footer"),
  }
  t.equal(layout.content_width({}, measure), 0)
  t.equal(layout.content_width(fragments, measure), 6)
  for _, width in ipairs({ 10, 11 }) do
    local doc = layout.compose(
      fragments,
      { "header", "menu", "footer" },
      { win = 1, source_buf = 2, width = width, height = 3 },
      rules.normalize().layout,
      measure
    )
    t.equal(doc.lines, { "  ------", "   ёжabc", "  ------" })
    t.equal(doc.targets[1].col, 3)
    t.equal(doc.spans[2], { row = 1, start_col = 3, end_col = 10, style = "Text" })
  end
end)

t.test("empty blocks do not add gaps and tiny sizes never add negative padding", function()
  local doc = layout.compose(
    { blocks.empty(), blocks.text({ "long" }, "Text"), blocks.empty(), blocks.text({ "tail" }, "Text") },
    { "empty", "a", "empty2", "b" },
    { win = 1, source_buf = 2, width = 1, height = 1 },
    { horizontal = "center", vertical = "center", gap = 2, bottom_padding = 4 },
    measure
  )
  t.equal(doc.lines, { "long", "", "", "tail" })
  t.equal(layout.compose({}, {}, context, rules.normalize().layout, measure).targets, {})
end)

t.test("all alignments and bottom reservation", function()
  t.equal(layout.offset(10, 3, "left"), 0)
  t.equal(layout.offset(10, 3, "center"), 3)
  t.equal(layout.offset(10, 3, "center", true), 4)
  t.equal(layout.offset(10, 4, "center", true), 3)
  t.equal(layout.offset(10, 3, "right"), 7)
  t.equal(layout.offset(2, 9, "bottom"), 0)
  local doc = layout.compose(
    { blocks.text({ "x" }, "Text") },
    { "a" },
    context,
    { horizontal = "left", vertical = "bottom", gap = 0, bottom_padding = 2 },
    measure
  )
  t.equal(#doc.lines, 8)
end)

t.test("duplicate and reserved keys fail before mappings are installed", function()
  local a = blocks.actions({ { id = "a", key = "f", label = "a", run = "" } }, 0, 0, measure)
  assert(not pcall(layout.compose, { a, a }, { "a", "b" }, context, rules.normalize().layout, measure))
  a.targets[1].key = "j"
  assert(not pcall(layout.compose, { a }, { "a" }, context, rules.normalize().layout, measure))
  a.targets[1].key = "<cr>"
  assert(not pcall(layout.compose, { a }, { "a" }, context, rules.normalize().layout, measure))
end)

t.test("tabs are rejected in all display text but key notation remains supported", function()
  assert(not pcall(rules.normalize, { blocks = { { id = "a", type = "text", lines = { "\tX" } } } }))
  assert(not pcall(blocks.text, { "\tX" }, "Text"))
  assert(not pcall(blocks.actions, { { id = "a", label = "\tX", run = "" } }, 0, 0, measure))
  assert(not pcall(blocks.actions, { { id = "a", label = "X", icon = "\t", run = "" } }, 0, 0, measure))
  assert(not pcall(blocks.validate, { lines = { "\tX" }, spans = {}, targets = {} }))
  rules.items({ { id = "a", label = "X", key = "<Tab>", run = "" } })
end)

t.test("key identities are supplied by the adapter before duplicate checks", function()
  local fragment = blocks.actions({ { id = "a", label = "X", key = "alias", run = "" } }, 0, 0, measure)
  assert(not pcall(layout.compose, { fragment }, { "menu" }, context, rules.normalize().layout, measure, function(key)
    return key == "alias" and "j" or key
  end))
end)

t.test("custom documents are copied and invalid coordinates rejected", function()
  local doc = blocks.text({ "test" }, "Project")
  t.equal(blocks.validate(doc), doc)
  doc.spans[1].end_col = 10
  assert(not pcall(blocks.validate, doc))
end)

t.test("selection survives movement and falls back when removed", function()
  local doc =
    blocks.actions({ { id = "a", label = "a", run = "" }, { id = "b", label = "b", run = "" } }, 0, 1, measure)
  t.equal(nav.move(doc.targets, doc.targets[1], -1), doc.targets[2])
  t.equal(nav.move(doc.targets, doc.targets[2], 1), doc.targets[1])
  t.equal(nav.preserve({ doc.targets[2] }, doc.targets[2]), doc.targets[2])
  t.equal(nav.preserve({ doc.targets[1] }, doc.targets[2]), doc.targets[1])
  t.equal(nav.move({}, nil, 1), nil)
end)

t.test("explicit colors replace fallback links and custom styles are independent", function()
  local input = { Text = { fg = "#123456" }, Project = { bold = true } }
  local result = styles.resolve(input)
  t.equal(result.Text, { fg = "#123456" })
  t.equal(result.Header, { link = "Title" })
  result.Project.bold = false
  t.equal(input.Project.bold, true)
end)

t.test("navigation and chrome options merge defaults without sharing input lists", function()
  local input = {
    hide_chrome = false,
    chrome = { hide_tabline = true },
    navigation = { wrap = false, highlight_selected = true, keys = { next = { "n" }, previous = {} } },
  }
  local before = t.copy(input)
  local config = rules.normalize(input)
  t.equal(config.chrome, { hide_statusline = false, hide_tabline = true, hide_winbar = false })
  t.equal(config.navigation.keys, { next = { "n" }, previous = {}, activate = { "<CR>" } })
  t.equal(config.navigation.wrap, false)
  t.equal(config.navigation.highlight_selected, true)
  config.navigation.keys.next[1] = "changed"
  t.equal(input, before)
  t.equal(rules.normalize().navigation.keys.next, { "j", "<Down>" })
end)

t.test("new option schemas reject false tables, misspellings and invalid values", function()
  local bad = {
    { navigation = false },
    { navigation = { keys = false } },
    { navigation = { wrap = 1 } },
    { navigation = { highlight_selected = 1 } },
    { navigation = { keys = { next = "n" } } },
    { navigation = { keys = { next = { "" } } } },
    { navigation = { keys = { prev = {} } } },
    { chrome = false },
    { chrome = { hide_tabline = 1 } },
    { chrome = { statusline = false } },
  }
  for _, input in ipairs(bad) do
    assert(not pcall(rules.normalize, input))
  end
  local layouts = {
    false,
    { align = "bad" },
    { offset_x = false },
    { offset_x = 0.5 },
    { offset_x = math.huge },
    { gap_before = false },
    { gap_after = -1 },
    { offset = 1 },
  }
  for _, block_layout in ipairs(layouts) do
    assert(not pcall(
      rules.normalize,
      { blocks = {
        { id = "title", type = "text", lines = {}, layout = block_layout },
      } }
    ))
  end
  assert(not pcall(rules.normalize, { blocks = { { id = "title", type = "text", lines = {}, enabled = 1 } } }))
end)

t.test("block margins and horizontal offsets shift text, byte spans and targets together", function()
  local menu = blocks.actions({ { id = "go", label = "ёжx", run = "" } }, 0, 0, measure)
  local doc = layout.compose(
    { blocks.text({ "------" }, "Header"), blocks.empty(), menu, blocks.text({ "zz" }, "Footer") },
    { "header", "empty", "menu", "footer" },
    { win = 1, source_buf = 2, width = 12, height = 10 },
    { horizontal = "center", vertical = "top", gap = 1, bottom_padding = 0 },
    measure,
    nil,
    {
      block_layouts = {
        { gap_before = 1, gap_after = 1 },
        { gap_before = 99, gap_after = 99 },
        { align = "left", offset_x = 2, gap_before = 2, gap_after = 1 },
        { align = "right" },
      },
    }
  )
  t.equal(doc.lines, { "", "   ------", "", "", "", "", "     ёжx", "", "", "       zz" })
  t.equal(doc.targets[1].row, 6)
  t.equal(doc.targets[1].col, 5)
  t.equal(doc.spans[2], { row = 6, start_col = 5, end_col = 10, style = "Text" })
end)

t.test("negative offsets clamp at the left edge without consuming Unicode content", function()
  local doc = layout.compose(
    { blocks.text({ "ёж" }, "Header") },
    { "header" },
    context,
    rules.normalize().layout,
    measure,
    nil,
    { block_layouts = { { offset_x = -99 } } }
  )
  t.equal(doc.lines[#doc.lines], "ёж")
  t.equal(doc.spans[1].start_col, 0)
  t.equal(doc.spans[1].end_col, 4)
end)

t.test("nonwrapping navigation clamps counts at the first and last target", function()
  local targets =
    blocks.actions({ { id = "a", label = "A", run = "" }, { id = "b", label = "B", run = "" } }, 0, 0, measure).targets
  t.equal(nav.move(targets, targets[1], -99, false), targets[1])
  t.equal(nav.move(targets, targets[1], 99, false), targets[2])
  t.equal(nav.move(targets, targets[2], 0, false), targets[2])
  t.equal(nav.move({}, nil, 99, false), nil)
end)

t.test("navigation determines reserved keys and empty lists release former defaults", function()
  local navigation = rules.normalize({ navigation = { keys = { next = {} } } }).navigation.keys
  local menu = blocks.actions({ { id = "go", label = "Go", key = "j", run = "" } }, 0, 0, measure)
  local doc = layout.compose(
    { menu },
    { "menu" },
    context,
    rules.normalize().layout,
    measure,
    nil,
    { navigation = navigation }
  )
  t.equal(doc.targets[1].key, "j")
  assert(not pcall(keys.reserved, { next = { "n" }, previous = { "n" }, activate = {} }, keys.normalize))
end)

t.test("navigation and action key sequences cannot shadow each other by prefix", function()
  assert(not pcall(keys.reserved, { next = { "n" }, previous = { "nn" }, activate = {} }, keys.normalize))
  local menu = blocks.actions({ { id = "go", label = "Go", key = "jj", run = "" } }, 0, 0, measure)
  assert(not pcall(layout.compose, { menu }, { "menu" }, context, rules.normalize().layout, measure))
end)

t.test("measurement cache retains zero widths and retries failures", function()
  local calls = 0
  local cached = require("dashboard.core.measure").cached(function(text)
    calls = calls + 1
    if text == "error" and calls == 3 then
      error("measurement failed")
    end
    return #text
  end)
  t.equal(cached(""), 0)
  t.equal(cached(""), 0)
  t.equal(cached("Hello"), 5)
  t.equal(cached("Hello"), 5)
  t.equal(calls, 2)
  assert(not pcall(cached, "error"))
  t.equal(cached("error"), 5)
  t.equal(calls, 4)
end)

t.test("unknown block and item fields are rejected instead of ignored", function()
  local cases = {
    { id = "menu", type = "actions", items = {}, offset_x = 100 },
    { id = "title", type = "text", lines = {}, spacing = 1 },
    {
      id = "custom",
      type = "custom",
      render = function()
        return blocks.empty()
      end,
      lines = {},
    },
    { id = "menu", type = "actions", items = { { id = "a", label = "A", run = "", keys = "f" } } },
  }
  for _, block in ipairs(cases) do
    local ok, err = pcall(rules.normalize, { blocks = { block } })
    assert(not ok and tostring(err):find("unknown", 1, true))
  end
end)

t.test("sparse lists are rejected regardless of the Lua length boundary", function()
  -- LuaJIT can report #list == 2 even though index 1 is absent and index 5 exists.
  local sparse = {}
  sparse[2], sparse[5] = "line", "line"
  assert(not pcall(rules.list, sparse, "lines"))
  for hole = 1, 10 do
    local list = {}
    for index = 1, 10 do
      if index ~= hole then
        list[index] = "line"
      end
    end
    if hole < 10 then
      assert(not pcall(rules.list, list, "lines"))
    else
      rules.list(list, "lines")
    end
  end
end)

t.test("custom offsets must fall on UTF-8 character boundaries", function()
  local doc = blocks.text({ "界é" }, "Text")
  doc.targets = { { id = "go", row = 0, col = 3, run = "" } }
  blocks.validate(doc)
  for _, col in ipairs({ 1, 2, 4 }) do
    local invalid_span = rules.copy(doc)
    invalid_span.spans[1].start_col = col
    assert(not pcall(blocks.validate, invalid_span))
    invalid_span = rules.copy(doc)
    invalid_span.spans[1].end_col = col
    assert(not pcall(blocks.validate, invalid_span))
    local invalid_target = rules.copy(doc)
    invalid_target.targets[1].col = col
    assert(not pcall(blocks.validate, invalid_target))
  end
end)

t.test("custom document typos and false shortcut keys fail validation", function()
  local invalid = {
    { lines = {}, spans = {}, targets = {}, typo = true },
    { lines = { "x" }, spans = { { row = 0, start_col = 0, end_col = 1, style = "Text", typo = true } }, targets = {} },
    { lines = { "x" }, spans = {}, targets = { { id = "a", row = 0, col = 0, run = "", key = false } } },
    { lines = { "x" }, spans = {}, targets = { { id = "a", row = 0, col = 0, run = "", typo = true } } },
  }
  for _, document in ipairs(invalid) do
    assert(not pcall(blocks.validate, document))
  end
end)

t.run("Dashboard core")
_G.vim = host_vim
