-- Run with LuaJIT or nvim --clean --headless -i NONE -l tests/core.lua.
local source = debug.getinfo(1, "S").source:sub(2)
local directory = source:match("^(.*[/\\])") or "./"
package.path = directory .. "../lua/?.lua;" .. directory .. "?.lua;" .. package.path
local config = require("cheatsheet.core.config")
local mappings = require("cheatsheet.core.mappings")
local modes = require("cheatsheet.core.modes")
local patterns = require("cheatsheet.core.patterns")
local t = require("support")
local host_vim = rawget(_G, "vim")
_G.vim = nil

t.test("defaults and returned options never share caller-owned tables", function()
  local defaults = config.defaults()
  local options = { window = { width = 2 }, exclude = { groups = { "hidden" } } }
  local before = t.copy(options)
  local normalized, messages = config.normalize(options)
  t.equal(options, before)
  t.equal(#messages, 1)
  normalized.exclude.groups[1] = "changed"
  normalized.window.padding.left = 100
  t.equal(config.defaults(), defaults)
  t.equal(options, before)
  -- Deliberately corrupt a caller-owned default copy.
  ---@diagnostic disable-next-line: assign-type-mismatch
  defaults.modes[1] = "invalid"
  t.equal(config.defaults().modes[1], "n")
end)

t.test("partial dictionaries merge; empty lists and false values replace defaults", function()
  local result, messages = config.normalize({
    window = { padding = { left = 0 } },
    exclude = { no_desc = false, single_word = false, patterns = {} },
    icons = { enabled = false },
    mappings = { close = {} },
    group_underline = false,
  })
  t.equal(messages, {})
  t.equal(result.window.padding, { left = 0, right = 2, top = 1, bottom = 1 })
  t.equal(result.exclude.no_desc, false)
  t.equal(result.exclude.single_word, false)
  t.equal(result.exclude.patterns, {})
  t.equal(result.icons.enabled, false)
  t.equal(result.mappings.close, {})
  t.equal(result.group_underline, false)
  t.equal(result.mappings.next_mode, "<tab>")
end)

local invalid_options = {
  { window = true },
  { window = { padding = true } },
  { exclude = false },
  { icons = 1 },
  { default_group = "wrong" },
  { mappings = false },
  { modes = {} },
  { modes = { "n", "n" } },
  { modes = { "x" } },
  { modes = { [2] = "i" } },
  { modes = { n = "n" } },
  { window = { width = false } },
  { window = { width = 0 } },
  { window = { width = 0 / 0 } },
  { window = { height = math.huge } },
  { window = { height = -1 } },
  { window = { border = "bad" } },
  { window = { title = "bad\ntitle" } },
  { window = { title_pos = false } },
  { window = { zindex = 0 } },
  { window = { zindex = 1.5 } },
  { window = { padding = { left = 0.5 } } },
  { window = { padding = { right = math.huge } } },
  { window = { padding = { top = -1 } } },
  { window = { padding = { bottom = "0" } } },
  { sort_keys = false },
  { sort_keys = "bad" },
  { sort_groups = { "same", "same" } },
  { group_align = "bad" },
  { mode_align = false },
  { group_underline = 0 },
  { default_group = { name = "" } },
  { default_group = { icon = false } },
  { icons = { enabled = 1 } },
  { icons = { default = "bad\nicon" } },
  { exclude = { groups = { 1 } } },
  { exclude = { no_desc = 1 } },
  { exclude = { newline = 1 } },
  { exclude = { single_word = 1 } },
  { mappings = { close = { "q", "q" } } },
  { mappings = { next_mode = "" } },
  { mappings = { prev_mode = true } },
  { open_mapping = "" },
  { group_rules = { [2] = { pattern = "x", group = "test" } } },
  { group_rules = false },
  { exclude = { patterns = false } },
  { exclude = { desc_patterns = false } },
  { layout = false },
  { layout = { key_gap = -1 } },
  { layout = { key_gap = 0.5 } },
  { layout = { mapping_spacing = math.huge } },
  { layout = { mapping_spacing = 0 / 0 } },
  { layout = { group_spacing = "2" } },
  { group_rules = { { pattern = "x", group = "test", prefix = false } } },
  { group_rules = { { pattern = "x", group = "test", prefix = "bad\nprefix" } } },
}
for index, options in ipairs(invalid_options) do
  t.test("invalid configuration case " .. index .. " falls back with a diagnostic", function()
    local result, messages = config.normalize(options)
    t.equal(result, config.defaults())
    assert(#messages > 0)
  end)
end

t.test("wrong root types fall back, nil is an ordinary default setup", function()
  for _, value in ipairs({ true, 1, "options" }) do
    local result, messages = config.normalize(value)
    t.equal(result, config.defaults())
    t.equal(#messages, 1)
  end
  local result, messages = config.normalize()
  t.equal(result, config.defaults())
  t.equal(messages, {})
end)

t.test("valid options retain all supported values including optional and empty icons", function()
  local result, messages = config.normalize({
    window = { width = 1, height = 0.1, border = "none", title = "", title_pos = "right", zindex = 100 },
    modes = { "t", "o", "v", "i", "n" },
    open_mapping = "<leader>ch",
    group_rules = { { pattern = "^Test:", group = "test" }, { pattern = "Other:", group = "other", icon = "" } },
    default_group = { name = "misc", icon = "" },
    icons = { default = "X" },
    sort_keys = "desc",
    sort_groups = { "test" },
    group_align = "center",
    mode_align = "left",
    mappings = { close = { "q", "<Esc>" }, next_mode = "]m", prev_mode = "[m" },
  })
  t.equal(messages, {})
  t.equal(result.window.width, 1)
  t.equal(result.modes, { "t", "o", "v", "i", "n" })
  t.equal(result.open_mapping, "<leader>ch")
  t.equal(result.group_rules[1].icon, nil)
  t.equal(result.default_group.icon, "")
  t.equal(result.mappings.close, { "q", "<Esc>" })
end)

t.test("bad rules and malformed pattern suffixes are skipped individually", function()
  local valid = { pattern = "^Test:", group = "test" }
  local result, messages = config.normalize({
    group_rules = { valid, { pattern = "^Git:[", group = "bad" }, false, { pattern = "x", group = "" } },
    exclude = { patterns = { "^<Plug>", "^Never%", false, "valid" } },
  })
  t.equal(result.group_rules, { valid })
  t.equal(result.exclude.patterns, { "^<Plug>", "valid" })
  t.equal(#messages, 5)
end)

t.test("Lua pattern syntax supports classes, frontiers, balanced pairs and captures", function()
  for _, pattern in ipairs({
    "",
    "^Test:",
    "[a-z]",
    "[]a]",
    "[^]a]",
    "[%]]",
    "%f[%a]word",
    "%b()",
    "(a)%1",
    "()a",
    "((a)%2)%1",
    "%(",
    "%0",
  }) do
    local expected = pattern ~= "%0"
    t.equal(patterns.valid(pattern), expected, pattern)
  end
  for _, pattern in ipairs({
    "[",
    "[^",
    "[a%]",
    "^Never%",
    "%b",
    "%ba",
    "%f",
    "%fa",
    "%f[",
    "(",
    ")",
    "%1",
    "(%1)",
    "()%1",
    string.rep("()", 33),
  }) do
    t.equal(patterns.valid(pattern), false, pattern)
  end
  t.equal(patterns.valid(false), false)
end)

---@param global CheatsheetRawMapping[]
---@param local_mappings? CheatsheetRawMapping[]
---@param options? CheatsheetConfigPartial
---@param mode? CheatsheetMode
---@param leader? string
---@return CheatsheetGroup[]
local function build(global, local_mappings, options, mode, leader)
  return mappings.build(
    global,
    local_mappings or {},
    config.normalize(options),
    { mode = mode or "n", leader = leader or " " }
  )
end
---@param lhs string
---@param desc? string
---@return CheatsheetRawMapping
local function raw(lhs, desc)
  return { lhs = lhs, desc = desc }
end

t.test("buffer precedence is applied before filtering and inputs stay unchanged", function()
  local global = { raw("xx", "Global action"), raw("yy", "Other action") }
  local local_mappings = { raw("xx", ""), raw("", "Empty key"), { desc = "Missing key" } }
  local before_global, before_local = t.copy(global), t.copy(local_mappings)
  local groups = build(global, local_mappings)
  t.equal(#groups, 1)
  t.equal(groups[1].mappings, { { lhs = "yy", desc = "Other action", mode = "n" } })
  t.equal(global, before_global)
  t.equal(local_mappings, before_local)
end)

t.test("filters independently exclude missing descriptions, single words and newlines", function()
  local data =
    { raw("aa", nil), raw("bb", "One"), raw("cc", "Two words"), raw("dd", "Line\nTwo"), raw("ee", "\nTwo words\n") }
  t.equal(#build(data)[1].mappings, 1)
  local all = build(data, {}, { exclude = { no_desc = false, single_word = false, newline = false } })
  t.equal(#all[1].mappings, 5)
  t.equal(all[1].mappings[1].desc, "")
  t.equal(all[1].mappings[4].desc, "Line Two")
  t.equal(all[1].mappings[5].desc, "Two words")
  t.equal(#build(data, {}, { exclude = { no_desc = false } })[1].mappings, 1)
end)

t.test("Plug and custom exclusions follow configurable patterns", function()
  local data = { raw("<Plug>test", "Plug action"), raw("hidden", "Hidden action"), raw("visible", "Visible action") }
  t.equal(#build(data)[1].mappings, 2)
  t.equal(#build(data, {}, { exclude = { patterns = {} } })[1].mappings, 3)
  local result = build(data, {}, { exclude = { patterns = { "^hidden$" } } })
  t.equal(#result[1].mappings, 2)
end)

t.test("first matching rule wins, excluded groups vanish and priorities sort groups", function()
  local options = {
    group_rules = {
      { pattern = "^Test:", group = "test", icon = "T " },
      { pattern = ":", group = "tagged", icon = "G " },
    },
    sort_groups = { "tagged", "test" },
    exclude = { groups = { "other" } },
  }
  local result = build(
    { raw("c", "Test: third action"), raw("b", "Git: second action"), raw("a", "Ordinary action") },
    {},
    options
  )
  t.equal({ result[1].name, result[2].name }, { "tagged", "test" })
  t.equal(result[2].mappings[1].desc, "Third action")
  t.equal(result[2].icon, "T ")
end)

t.test("only a matched colon-terminated first token is removed", function()
  local options = { group_rules = { { pattern = ".", group = "test" } }, exclude = { single_word = false } }
  local result = build({
    raw("a", "rename symbol"),
    raw("b", "LSP: rename symbol"),
    raw("c", "https://example path"),
    raw("d", "LSP:"),
    raw("e", "LSP:rename symbol"),
  }, {}, options)
  local descriptions = {}
  for _, mapping in ipairs(result[1].mappings) do
    descriptions[#descriptions + 1] = mapping.desc
  end
  t.equal(descriptions, { "rename symbol", "Rename symbol", "https://example path", "", "LSP:rename symbol" })
  t.equal(build({ raw("a", "LSP: rename symbol") })[1].mappings[1].desc, "LSP: rename symbol")
end)

t.test("group icons follow matching-rule priority, optional fallback and explicit emptiness", function()
  local options = {
    group_rules = {
      { pattern = "^First:", group = "same", icon = "FIRST" },
      { pattern = "^Second:", group = "same", icon = "SECOND" },
    },
    icons = { default = "FALLBACK" },
  }
  local data = { raw("a", "Second: action two"), raw("z", "First: action one") }
  t.equal(build(data, {}, options)[1].icon, "FIRST")
  t.equal(build({ data[2], data[1] }, {}, options), build(data, {}, options))
  t.equal(build({ raw("a", "Some action") }, {}, options)[1].icon, "FALLBACK")
  options.icons.enabled = false
  t.equal(build(data, {}, options)[1].icon, "")
  options.icons.enabled = true
  options.default_group = { icon = "" }
  t.equal(build({ raw("a", "Some action") }, {}, options)[1].icon, "")
  options.group_rules[1].icon = nil
  t.equal(build(data, {}, options)[1].icon, "FALLBACK")
end)

t.test("descriptions sort with a key tie-breaker and ordinary keys sort lexically", function()
  local data = { raw("b", "Same action"), raw("a", "Same action"), raw("z", "A first action") }
  local result = build(data, {}, { sort_keys = "desc" })[1].mappings
  t.equal({ result[1].lhs, result[2].lhs, result[3].lhs }, { "z", "a", "b" })
  result = build(data)[1].mappings
  t.equal({ result[1].lhs, result[2].lhs, result[3].lhs }, { "a", "b", "z" })
end)

t.test("unlisted groups sort by name", function()
  local result = build({ raw("a", "Z: last action"), raw("b", "A: first action") }, {}, {
    group_rules = { { pattern = "^Z:", group = "z" }, { pattern = "^A:", group = "a" } },
  })
  t.equal({ result[1].name, result[2].name }, { "a", "z" })
end)

t.test("leader formatting uses explicit context and never strips ordinary keys", function()
  t.equal(mappings.format_lhs(" zz", " "), "<leader> + zz")
  t.equal(mappings.format_lhs("\\zz", "\\"), "<leader> + zz")
  t.equal(mappings.format_lhs("abzz", "ab"), "<leader> + zz")
  t.equal(mappings.format_lhs("zz", ""), "zz")
  t.equal(mappings.format_lhs("zz", " "), "zz")
  t.equal(mappings.format_lhs(" ", " "), "<leader> + ")
end)

t.test("sorting does not change or retain caller-owned groups and mappings", function()
  local groups = {
    {
      name = "z",
      icon = "",
      mappings = { { lhs = "b", desc = "B", mode = "n" }, { lhs = "a", desc = "A", mode = "n" } },
    },
    { name = "a", icon = "", mappings = {} },
  }
  local before = t.copy(groups)
  local sorted = mappings.sort(groups, config.normalize())
  t.equal(groups, before)
  t.equal(sorted[1].name, "a")
  sorted[2].mappings[1].desc = "Changed"
  t.equal(groups, before)
end)

t.test("mode cycling wraps in both directions and handles a single mode", function()
  t.equal(modes.index({ "n", "i" }, "i"), 2)
  t.equal(modes.index({ "n", "i" }, "v"), nil)
  t.equal(modes.cycle({ "n", "i" }, "n", -1), "i")
  t.equal(modes.cycle({ "n", "i" }, "i", 1), "n")
  t.equal(modes.cycle({ "n" }, "n", 1), "n")
  t.equal(modes.cycle({ "n", "i" }, "unknown", 1), "i")
end)

t.test("layout settings merge partially, accept zero and do not mutate options", function()
  local input = { layout = { key_gap = 0, mapping_spacing = 0 }, exclude = { desc_patterns = {} } }
  local before = t.copy(input)
  local options, messages = config.normalize(input)
  t.equal(messages, {})
  t.equal(options.layout, { key_gap = 0, mapping_spacing = 0, group_spacing = 2 })
  t.equal(options.exclude.desc_patterns, {})
  options.layout.key_gap = 20
  options.exclude.desc_patterns[1] = "changed"
  t.equal(input, before)
end)

t.test("description patterns are validated individually without discarding valid filters", function()
  local options, messages =
    config.normalize({ exclude = { desc_patterns = { "^MiniPairs", "^Never[", false, "hidden" } } })
  t.equal(options.exclude.desc_patterns, { "^MiniPairs", "hidden" })
  t.equal(#messages, 2)
  assert(messages[1]:find("desc_patterns", 1, true))
end)

t.test("description filters match trimmed original descriptions before prefix removal", function()
  local options = {
    group_rules = { { pattern = "^Test:", group = "test" } },
    exclude = { desc_patterns = { "^Test: hidden", "^MiniPairs" } },
  }
  local result = build(
    { raw("a", "  Test: hidden action  "), raw("b", "MiniPairs open pair"), raw("c", "Test: visible action") },
    {},
    options
  )
  t.equal(#result, 1)
  t.equal(result[1].mappings, { { lhs = "c", desc = "Visible action", mode = "n" } })
  t.equal(build({ raw("a", "Lua function action") }), {})
  t.equal(#build({ raw("a", "Lua function action") }, {}, { exclude = { desc_patterns = {} } }), 1)
end)

t.test("lhs and description filters act independently and preserve local precedence", function()
  local options = { exclude = { patterns = { "^hidden$" }, desc_patterns = { "^Private:" } } }
  local result = build(
    { raw("hidden", "Visible action"), raw("Private:key", "Visible action"), raw("local", "Global action") },
    { raw("local", "Private: local action") },
    options
  )
  t.equal(result[1].mappings, { { lhs = "Private:key", desc = "Visible action", mode = "n" } })
end)

t.test("explicit prefixes are literal, beginning-only and removed once", function()
  local options = { group_rules = { { pattern = ".", group = "test", prefix = "Inline diagnostic:" } } }
  local result = build({
    raw("a", "  Inline diagnostic: toggle diagnostics  "),
    raw("b", "Other: keep description"),
    raw("c", "Before Inline diagnostic: keep description"),
    raw("d", "Inline diagnostic: Inline diagnostic: action"),
  }, {}, options)
  t.equal(result[1].mappings[1].desc, "Toggle diagnostics")
  t.equal(result[1].mappings[2].desc, "Other: keep description")
  t.equal(result[1].mappings[3].desc, "Before Inline diagnostic: keep description")
  t.equal(result[1].mappings[4].desc, "Inline diagnostic: action")
  options.group_rules[1].prefix = "A[1].:"
  t.equal(build({ raw("a", "A[1].: literal prefix") }, {}, options)[1].mappings[1].desc, "Literal prefix")
  options.group_rules[1].prefix = "ключ:"
  t.equal(build({ raw("a", "ключ: action text") }, {}, options)[1].mappings[1].desc, "Action text")
end)

t.test("empty prefix preserves tagged descriptions and unmatched explicit prefix disables automatic removal", function()
  local options = { group_rules = { { pattern = "^Test:", group = "test", prefix = "" } } }
  t.equal(build({ raw("a", "Test: original action") }, {}, options)[1].mappings[1].desc, "Test: original action")
  options.group_rules[1].prefix = "Different:"
  t.equal(build({ raw("a", "Test: original action") }, {}, options)[1].mappings[1].desc, "Test: original action")
end)

t.test("prefix selection belongs to the first matched rule, independently of the group icon", function()
  local options = {
    group_rules = {
      { pattern = "^First:", group = "same", prefix = "First:" },
      { pattern = "^Inline diagnostic:", group = "same", prefix = "Inline diagnostic:" },
    },
  }
  local result = build({ raw("a", "Inline diagnostic: second action"), raw("b", "First: first action") }, {}, options)
  t.equal(result[1].mappings[1].desc, "Second action")
  t.equal(result[1].mappings[2].desc, "First action")
end)

local ok, err = pcall(t.run, "cheatsheet core (without vim)")
_G.vim = host_vim
assert(ok, err)
