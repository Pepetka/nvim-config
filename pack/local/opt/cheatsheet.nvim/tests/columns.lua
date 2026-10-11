-- Run with LuaJIT or nvim --clean --headless -i NONE -l tests/columns.lua.
local source = debug.getinfo(1, "S").source:sub(2)
local directory = source:match("^(.*[/\\])") or "./"
package.path = directory .. "../lua/?.lua;" .. directory .. "?.lua;" .. package.path
local columns = require("cheatsheet.core.columns")
local text = require("cheatsheet.core.text")
local t = require("support")
local host_vim = rawget(_G, "vim")
_G.vim = nil
local measure = t.measure

t.test("characters split on UTF-8 boundaries and keep invalid bytes", function()
  t.equal(text.chars("a界é"), { "a", "界", "é" })
  t.equal(text.chars(""), {})
  t.equal(text.chars("a\192b\255c\128"), { "a", "\192", "b", "\255", "c", "\128" })
  t.equal(table.concat(text.wrap("abc\255defghijkl", 4, measure)), "abc\255defghijkl")
end)

t.test("clip keeps the longest prefix that fits by cells", function()
  t.equal(text.clip("abcdef", 3, measure), "abc")
  t.equal(text.clip("a界b", 2, measure), "a")
  t.equal(text.clip("a界b", 3, measure), "a界")
  t.equal(text.clip("ab", 5, measure), "ab")
  t.equal(text.clip("界", 1, measure), "")
end)

t.test("word wrap fills lines greedily by cells and collapses whitespace", function()
  t.equal(text.wrap("one two three", 7, measure), { "one two", "three" })
  t.equal(text.wrap("ab cd", 5, measure), { "ab cd" })
  t.equal(text.wrap("  a   b  ", 10, measure), { "a b" })
  t.equal(text.wrap("", 5, measure), { "" })
  t.equal(text.wrap("   ", 5, measure), { "" })
end)

t.test("long words split by characters without breaking wide characters", function()
  t.equal(text.wrap("abcdefgh", 3, measure), { "abc", "def", "gh" })
  t.equal(text.wrap("x abcdefgh", 3, measure), { "x", "abc", "def", "gh" })
  t.equal(text.wrap("ab c", 1, measure), { "a", "b", "c" })
  t.equal(text.wrap("界界界", 3, measure), { "界", "界", "界" })
  t.equal(text.wrap("a界 b", 2, measure), { "a", "界", "b" })
  t.equal(text.wrap("界", 1, measure), { "界" })
end)

t.test("wrapped lines never exceed the width when every character fits", function()
  local samples = { "Opens filepath or URI under cursor", "界面 显示 文本 内容", "a bb ccc dddd eeeee", "x" }
  for _, sample in ipairs(samples) do
    for width = 2, 12 do
      for _, line in ipairs(text.wrap(sample, width, measure)) do
        assert(measure(line) <= width, sample .. " @" .. width .. ": " .. line)
      end
    end
  end
end)

t.test("column count follows the preferred width, limits and a minimum of one", function()
  t.equal(columns.count(100, 20, 4, 10), 4)
  t.equal(columns.count(100, 20, 4, 3), 3)
  t.equal(columns.count(44, 20, 4, 5), 2)
  t.equal(columns.count(43, 20, 4, 5), 1)
  t.equal(columns.count(10, 20, 4, 5), 1)
  t.equal(columns.count(0, 10, 0, 3), 1)
end)

t.test("column width divides the content after gaps and stays positive", function()
  t.equal(columns.width(100, 3, 4), 30)
  t.equal(columns.width(100, 1, 4), 100)
  t.equal(columns.width(1, 3, 4), 1)
end)

---@param heights integer[]
---@return CheatsheetCost
local function sum(heights)
  return function(first, last)
    local total = 0
    for index = first, last do
      total = total + heights[index]
    end
    return total
  end
end

---@param ranges CheatsheetRange[]
---@param items integer
---@return nil
local function check_ranges(ranges, items)
  local expected = 1
  for _, range in ipairs(ranges) do
    t.equal(range.first, expected)
    assert(range.last >= range.first, "ranges must be nonempty")
    expected = range.last + 1
  end
  t.equal(expected, items + 1)
end

---@param items integer
---@param count integer
---@param cost CheatsheetCost
---@return integer
local function brute_force(items, count, cost)
  ---@param first integer
  ---@param remaining integer
  ---@return integer
  local function best(first, remaining)
    if remaining == 1 then
      return cost(first, items)
    end
    local result = math.huge
    for last = first, items - remaining + 1 do
      result = math.min(result, math.max(cost(first, last), best(last + 1, remaining - 1)))
    end
    return result
  end
  return best(1, math.min(count, items))
end

t.test("partition matches exhaustive search on deterministic inputs", function()
  local seed = 7
  for items = 1, 7 do
    for count = 1, 4 do
      local heights = {}
      for index = 1, items do
        seed = (seed * 1103515245 + 12345) % 2147483648
        heights[index] = 1 + seed % 9
      end
      local cost = sum(heights)
      local ranges = columns.partition(items, count, cost)
      t.equal(#ranges, math.min(items, count))
      check_ranges(ranges, items)
      local tallest = 0
      for _, range in ipairs(ranges) do
        tallest = math.max(tallest, cost(range.first, range.last))
      end
      t.equal(tallest, brute_force(items, count, cost))
    end
  end
end)

t.test("partition ties keep earlier columns fuller and handle edge counts", function()
  t.equal(columns.partition(3, 2, sum({ 2, 2, 2 })), { { first = 1, last = 2 }, { first = 3, last = 3 } })
  t.equal(
    columns.partition(3, 5, sum({ 1, 2, 3 })),
    { { first = 1, last = 1 }, { first = 2, last = 2 }, { first = 3, last = 3 } }
  )
  t.equal(columns.partition(4, 1, sum({ 1, 1, 1, 1 })), { { first = 1, last = 4 } })
  t.equal(columns.partition(0, 3, sum({})), {})
end)

t.test("partition skips ranges that cannot end the final column", function()
  local seen = {}
  columns.partition(5, 1, function(first, last)
    seen[#seen + 1] = first .. ":" .. last
    return last - first + 1
  end)
  t.equal(seen, { "1:5" })
  columns.partition(5, 2, function(first, last)
    assert(first == 1 or last == 5, "unused range " .. first .. ":" .. last)
    return last - first + 1
  end)
end)

t.test("partition evaluates only valid ranges and caches costs", function()
  local calls, seen = 0, {}
  columns.partition(6, 3, function(first, last)
    assert(first >= 1 and last <= 6 and first <= last)
    local key = first .. ":" .. last
    assert(not seen[key], "cost evaluated twice for " .. key)
    seen[key], calls = true, calls + 1
    return last - first + 1
  end)
  assert(calls > 0)
end)

t.test("stack inserts blank spacing and shifts span rows", function()
  local result = columns.stack({
    { lines = { "a", "b" }, spans = { { row = 1, start_col = 0, end_col = 1, hl_group = "CheatsheetKey" } } },
    { lines = { "c" }, spans = { { row = 0, start_col = 0, end_col = 1, hl_group = "CheatsheetDesc" } } },
  }, 2)
  t.equal(result.lines, { "a", "b", "", "", "c" })
  t.equal(result.spans, {
    { row = 1, start_col = 0, end_col = 1, hl_group = "CheatsheetKey" },
    { row = 4, start_col = 0, end_col = 1, hl_group = "CheatsheetDesc" },
  })
  t.equal(columns.stack({}, 3), { lines = {}, spans = {} })
  t.equal(columns.stack({ { lines = { "a" }, spans = {} }, { lines = { "b" }, spans = {} } }, 0).lines, { "a", "b" })
end)

t.test("compose pads by cells, shifts spans by bytes and leaves no trailing padding", function()
  local result = columns.compose({
    {
      lines = { "ab", "", "界x" },
      spans = {
        { row = 0, start_col = 0, end_col = 2, hl_group = "CheatsheetKey" },
        { row = 2, start_col = 0, end_col = 3, hl_group = "CheatsheetKey" },
      },
    },
    {
      lines = { "cd", "ef" },
      spans = {
        { row = 0, start_col = 0, end_col = 2, hl_group = "CheatsheetDesc" },
        { row = 1, start_col = 0, end_col = 2, hl_group = "CheatsheetDesc" },
      },
    },
  }, 4, 2, 1, measure)
  t.equal(result.lines, { " ab    cd", "       ef", " 界x" })
  t.equal(result.spans, {
    { row = 0, start_col = 1, end_col = 3, hl_group = "CheatsheetKey" },
    { row = 0, start_col = 7, end_col = 9, hl_group = "CheatsheetDesc" },
    { row = 1, start_col = 7, end_col = 9, hl_group = "CheatsheetDesc" },
    { row = 2, start_col = 1, end_col = 4, hl_group = "CheatsheetKey" },
  })
  t.check_spans(result)
end)

t.test("compose aligns columns after wide characters and keeps empty rows as left padding", function()
  local result = columns.compose({
    { lines = { "界", "", "a" }, spans = {} },
    { lines = { "b", "" }, spans = {} },
    { lines = { "c" }, spans = {} },
  }, 3, 1, 2, measure)
  t.equal(result.lines, { "  界  b   c", "  ", "  a" })
  t.equal(columns.compose({}, 3, 1, 2, measure), { lines = {}, spans = {} })
end)

local ok, err = pcall(t.run, "cheatsheet columns (without vim)")
_G.vim = host_vim
assert(ok, err)
