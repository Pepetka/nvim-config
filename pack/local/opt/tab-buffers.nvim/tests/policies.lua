local source = debug.getinfo(1, "S").source:sub(2)
local test_dir = source:match("^(.*[/\\])") or "./"
local root = test_dir .. ".."
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. root .. "/tests/?.lua;" .. package.path
local saved_vim = _G.vim
local support = require("support")
local test, equal = support.test, support.equal
local context = require("tab_buffers.core.context")
local config = require("tab_buffers.core.config")
local closing = require("tab_buffers.core.closing")
local reconcile = require("tab_buffers.core.reconcile")
local layout = require("tab_buffers.core.layout")
local width_cache = require("tab_buffers.core.metrics")
local panel = require("tab_buffers.core.panel")
local reviews = require("tab_buffers.core.reviews")
local picker = require("tab_buffers.core.picker")
local fixtures = require("fixtures")
require("tab_buffers.controller")
require("tab_buffers.tabline.controller")
---@type TabBuffersTextMetrics
local metrics = {
  measure = function(text)
    return #text
  end,
  length = function(text)
    return #text
  end,
  suffix = function(text, first)
    return text:sub(first + 1)
  end,
}

_G.vim = nil

test("every core and controller module loads without vim", function()
  for _, name in ipairs({
    "model",
    "ordering",
    "selection",
    "validation",
    "lists",
    "context",
    "closing",
    "reconcile",
    "config",
    "layout",
    "panel",
    "reviews",
    "picker",
  }) do
    assert(require("tab_buffers.core." .. name))
  end
  assert(require("tab_buffers.controller"))
  assert(require("tab_buffers.tabline.controller"))
end)

test("eligibility distinguishes untouched placeholders, drafts and owned empties", function()
  local adapter, state = fixtures.editor()
  local blank = fixtures.buffer(state, "")
  equal(context.eligible(adapter.buffer(blank), false), false)
  equal(context.eligible(adapter.buffer(blank), true), true)
  state.buffers[blank].modified = true
  equal(context.eligible(adapter.buffer(blank), false), true)
  state.buffers[blank].buftype = "terminal"
  equal(context.eligible(adapter.buffer(blank), true), false)
  equal(context.basic(adapter.buffer(99)), false)
end)

for _, property in ipairs({ "floating", "external", "preview" }) do
  test("working windows exclude " .. property, function()
    local facts = { valid = true, managed = true, floating = false, external = false, preview = false }
    facts[property] = true
    equal(context.working(facts), false)
    facts[property] = false
    equal(context.working(facts), true)
    facts.managed = false
    equal(context.ordinary(facts), true)
    equal(context.working(facts), false)
  end)
end

test("managed tabs must exist and not be excluded", function()
  equal(context.managed({ valid = false, excluded = false }), false)
  equal(context.managed({ valid = true, excluded = true }), false)
  equal(context.managed({ valid = true, excluded = false }), true)
end)

test("configuration copies lists and preserves defaults", function()
  local input = { offsets = { "Tree" }, highlights = { Active = { bold = true } } }
  local normalized = config.normalize(input)
  normalized.offsets[1] = "changed"
  equal(input.offsets, { "Tree" })
  equal(config.normalize().offsets, {})
  equal(normalized.padding, 0)
  equal(normalized.max_name_length, 30)
end)

test("normalization isolates highlight literals and operation options", function()
  local input = { highlights = { Active = { fg = "#123456" } } }
  local normalized = config.normalize(input)
  assert(type(normalized.highlights) == "table")
  normalized.highlights.Active.fg = "#654321"
  equal(input.highlights.Active.fg, "#123456")
  local opts = { force = false, tab = 1 }
  local copy = require("tab_buffers.core.validation").options(opts)
  opts.force = true
  equal(copy.force, false)
end)

test("sidebar offsets only reserve full-height outer ordinary windows", function()
  local windows = {
    { ordinary = true, filetype = "Tree", column = 0, width = 20, height = 40 },
    { ordinary = true, filetype = "Tree", column = 90, width = 30, height = 40 },
    { ordinary = true, filetype = "Tree", column = 0, width = 40, height = 10 },
    { ordinary = false, filetype = "Tree", column = 0, width = 50, height = 40 },
  }
  equal({ panel.offsets(windows, 120, 40, { "Tree" }) }, { 21, 31 })
  equal({ panel.offsets(windows, 120, 40, {}) }, { 0, 0 })
end)

for _, input in ipairs({
  false,
  { padding = math.huge },
  { max_name_length = 0 },
  { icons = 1 },
  { offsets = { [2] = "Tree" } },
  { hide_filetypes = { true } },
  { highlights = 1 },
}) do
  test("invalid config is rejected before effects: " .. tostring(input), function()
    support.raises(function()
      config.normalize(input)
    end)
  end)
end

test("highlight callbacks must return a mapping of tables", function()
  support.raises(function()
    config.highlights(nil)
  end, "table")
  support.raises(function()
    config.highlights({ Active = false })
  end, "style")
  local input = { Active = { fg = "#123456" } }
  config.highlights(input).Active.fg = "#654321"
  equal(input.Active.fg, "#123456")
end)

test("replacement skips selected and ineligible neighbors and prefers right", function()
  local eligible = function(buf)
    return buf ~= 3
  end
  equal(closing.replacement({ 1, 2, 3, 4 }, 2, {}, eligible), 4)
  equal(closing.replacement({ 1, 2, 3, 4 }, 2, { [4] = true }, eligible), 1)
  equal(closing.replacement({ 1, 2 }, 99, {}, eligible), nil)
end)

test("closure policy protects modified and externally displayed exclusive buffers", function()
  equal(closing.blocker(1, true, false, true), "unsaved changes")
  equal(closing.blocker(1, false, true, true), "buffer is still displayed in an unmanaged window")
  equal(closing.blocker(2, true, true, true), nil)
  equal(closing.blocker(1, true, true, false), nil)
end)

test("reconciliation considers snapshots of never-enrolled tabs exactly once", function()
  equal(reconcile.candidates({ 3, 1 }, { [1] = {}, [2] = {} }), { 1, 2, 3 })
  equal(
    reconcile.destination(99, { 1, 2, 3 }, function(tab)
      return tab == 2
    end),
    2
  )
end)

test("sanitized names remain distinct and percent signs stay literal", function()
  local labels = layout.labels({
    { id = 1, name = "/a/file\n.lua" },
    { id = 2, name = "/b/file\r.lua" },
    { id = 3, name = "/same/file\n.lua" },
    { id = 4, name = "/same/file\r.lua" },
    { id = 5, name = "/100%.lua" },
  })
  assert(labels[1] ~= labels[2] and labels[3] ~= labels[4])
  equal(labels[5], "100%.lua")
  equal(layout.clean("a\tb\nc"), "a b c")
end)

test("ID suffixes cannot collide with actual filename labels", function()
  local labels = layout.labels({
    { id = 1, name = "/f\n" },
    { id = 2, name = "/f\r" },
    { id = 3, name = "/f  [1]" },
  })
  local seen = {}
  for _, label in pairs(labels) do
    assert(not seen[label])
    seen[label] = true
  end
end)

test("fit does not mutate inputs and includes its anchor within the budget", function()
  local items = { { text = "one" }, { text = "two" }, { text = "three" } }
  for width = 1, 20 do
    local fitted, before, after = layout.fit(items, 2, width, metrics)
    local used = #(before or "") + #(after or "")
    for _, item in ipairs(fitted) do
      used = used + #item.text
    end
    -- Native ellipsis/arrows are multibyte; the injected byte metric accounts for their width.
    assert(used <= width)
  end
  equal(items[2].text, "two")
end)

---@return TabBuffersPanelSnapshot
local function snapshot()
  return {
    tab = 1,
    tabs = { 1, 2 },
    active = 1,
    visible = { [1] = true },
    entries = {
      { id = 1, name = "/a.lua", modified = true, icon = "" },
      { id = 2, name = "/b.lua", modified = false, icon = "" },
    },
    filetype = "lua",
    columns = 120,
    left = 0,
    right = 0,
    reviews = { [2] = true },
  }
end

test("panel builds escaped text and isolated stable click targets", function()
  local input = snapshot()
  input.entries[1].name = "/100%.lua"
  local old = { [99] = 1 }
  local document = panel.build(input, config.normalize(), old, 100, metrics)
  assert(document.text:find("100%%.lua", 1, true))
  equal(old, { [99] = 1 })
  equal(document.last_active, { [1] = 1 })
  equal(document.visibility, 2)
  assert(document.next_target > 100)
  for id, target in pairs(document.targets) do
    assert(id > 100 and target.tab > 0)
  end
end)

test("panel keeps last active owned buffer when focus moves to a special window", function()
  local input = snapshot()
  input.active = nil
  equal(panel.build(input, config.normalize(), { [1] = 2 }, 0, metrics).last_active, { [1] = 2 })
end)

test("hidden filetype hides panel without changing membership", function()
  local input = snapshot()
  local document = panel.build(input, config.normalize({ hide_filetypes = { "lua" } }), {}, 0, metrics)
  equal(document.visibility, 0)
  equal(#input.entries, 2)
end)

test("review close preserves pre-existing exclusion and ignores stale views", function()
  local registry = reviews.new()
  local first, second = { infer_cur_file = function() end }, { infer_cur_file = function() end }
  equal(registry.observe(1, first, true), false)
  equal(registry.close(1, first, true), false)
  registry.observe(2, first, false)
  registry.observe(2, second, true)
  equal(registry.close(2, first, true), false)
  equal(registry.get(2), second)
  equal({ registry.close(2, second, true) }, { true, false })
end)

test("review close respects external exclusion changes and prunes expired handles", function()
  local registry = reviews.new()
  local view = { infer_cur_file = function() end }
  registry.observe(1, view, nil)
  equal(registry.close(1, view, false), false)
  registry.observe(2, view, nil)
  registry.prune(function()
    return false
  end)
  equal(registry.get(2), nil)
  equal(
    reviews.destination({ 1, 2 }, 2, function()
      return true
    end),
    2
  )
end)

test("picker selection rejects malformed, duplicate and foreign IDs", function()
  equal(
    picker.selected({ "[2] file", "[2] duplicate", "[0] zero", "invalid", "[3] stale", "[1] file" }, function(buf)
      return buf < 3
    end),
    { 2, 1 }
  )
end)

test("clipped labels preserve distinguishing IDs and obey their width", function()
  local entries = {
    { id = 1, name = "/one/long-file.lua" },
    { id = 2, name = "/two/long-file.lua" },
    { id = 3, name = "/literal/[1]" },
  }
  for width = 3, 15 do
    local labels = layout.clipped_labels(entries, width, metrics)
    assert(labels[1] ~= labels[2] and labels[1] ~= labels[3] and labels[2] ~= labels[3])
    for _, text in pairs(labels) do
      assert(metrics.measure(text) <= width)
    end
  end
end)

test("behavior defaults are independent and setup validates every option", function()
  local defaults = config.behavior()
  equal(defaults.close_empty_tab, true)
  equal(defaults.wrap, true)
  equal(defaults.replacement, "right")
  equal(defaults.bootstrap_hidden_buffers, true)
  for _, opts in ipairs({
    { close_empty_tab = 1 },
    { wrap = "yes" },
    { bootstrap_hidden_buffers = false, replacement = "bad" },
    { bootstrap_hidden_buffers = 1 },
    { buffer_filter = false },
    { tab_filter = {} },
  }) do
    support.raises(function()
      config.behavior(opts)
    end)
  end
  defaults.wrap = false
  equal(config.behavior().wrap, true)
end)

test("replacement policies skip excluded, foreign and ineligible history entries", function()
  local eligible = function(buf)
    return buf ~= 3
  end
  equal(closing.replacement({ 1, 2, 3, 4 }, 2, {}, eligible, "left"), 1)
  equal(closing.replacement({ 1, 2, 3, 4 }, 2, {}, eligible, "last_used", { 99, 2, 3, 1, 4 }), 1)
  equal(closing.replacement({ 1, 2, 3, 4 }, 2, { [1] = true }, eligible, "last_used", { 1, 3 }), 4)
end)

test("panel visibility modes respect hidden filetypes", function()
  local input = snapshot()
  input.tabs, input.entries = { 1 }, { input.entries[1] }
  equal(panel.visibility(input, config.normalize()), 0)
  equal(panel.visibility(input, config.normalize({ visibility = "always" })), 2)
  equal(panel.visibility(input, config.normalize({ visibility = "never" })), 0)
  equal(panel.visibility(input, config.normalize({ visibility = "always", hide_filetypes = { "lua" } })), 0)
end)

test("panel validates visibility and finite tab width ratios", function()
  for _, opts in ipairs({
    { visibility = "invalid" },
    { tab_width_ratio = 0 },
    { tab_width_ratio = -1 },
    { tab_width_ratio = 2 },
    { tab_width_ratio = math.huge },
    { tab_width_ratio = 0 / 0 },
    { tab_width_ratio = "wide" },
  }) do
    support.raises(function()
      config.normalize(opts)
    end)
  end
  equal(config.normalize().tab_width_ratio, 1 / 3)
  equal(config.normalize({ tab_width_ratio = 1 }).tab_width_ratio, 1)
end)

test("tab width ratio expands the visible tabs while preserving the active buffer", function()
  local input = snapshot()
  input.tabs = {}
  for tab = 1, 20 do
    input.tabs[#input.tabs + 1] = tab
  end
  input.columns = 100
  local narrow = panel.build(input, config.normalize({ tab_width_ratio = 0.2 }), {}, 0, metrics)
  local wide = panel.build(input, config.normalize({ tab_width_ratio = 0.8 }), {}, 0, metrics)
  ---@param document TabBuffersPanelDocument
  ---@return integer
  local function count(document)
    local tabs, active = 0, false
    for _, item in pairs(document.targets) do
      if item.kind == "tab" then
        tabs = tabs + 1
      elseif item.id == input.active then
        active = true
      end
    end
    assert(active)
    return tabs
  end
  assert(count(wide) > count(narrow))
end)

test("display-width memoization is bounded and preserves zero widths", function()
  local reads = 0
  local measured = width_cache.new({
    measure = function(text)
      reads = reads + 1
      return #text
    end,
    length = metrics.length,
    suffix = metrics.suffix,
  }, 2)
  equal(measured.measure(""), 0)
  equal(measured.measure(""), 0)
  equal(reads, 1)
  measured.measure("a")
  measured.measure("b")
  measured.measure("")
  equal(reads, 4)
end)

test("long ASCII labels clip with logarithmic suffix measurements", function()
  local reads = 0
  local measured = {
    measure = metrics.measure,
    length = metrics.length,
    suffix = function(text, first)
      reads = reads + 1
      return metrics.suffix(text, first)
    end,
  }
  local clipped = layout.clip(string.rep("a", 10000) .. "/file.lua", 20, measured)
  assert(clipped:sub(-9) == "/file.lua")
  assert(#clipped <= 20)
  assert(reads < 20)
end)

_G.vim = saved_vim
support.run("tab-buffers policies")
