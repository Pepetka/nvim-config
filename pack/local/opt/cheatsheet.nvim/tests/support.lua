---@class CheatsheetTestCase
---@field name string
---@field run CheatsheetAction

---@type CheatsheetTestCase[]
local tests = {}
local M = { tests = tests }

---@generic T
---@param value T
---@return T
function M.copy(value)
  if type(value) ~= "table" then
    return value
  end
  local result = {}
  for key, item in pairs(value) do
    result[key] = M.copy(item)
  end
  return result
end

---@param actual unknown
---@param expected unknown
---@param path? string
---@return nil
function M.equal(actual, expected, path)
  path = path or "result"
  assert(type(actual) == type(expected), path .. ": types differ")
  if type(expected) ~= "table" then
    assert(actual == expected, path .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    return
  end
  for key, value in pairs(expected) do
    M.equal(actual[key], value, path .. "." .. tostring(key))
  end
  for key in pairs(actual) do
    assert(expected[key] ~= nil, path .. ": unexpected key " .. tostring(key))
  end
end

---@param document CheatsheetDocument
---@return nil
function M.check_spans(document)
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

---Display width for pure tests: one cell per code point, two cells for "界".
---@param text string
---@return integer
function M.measure(text)
  local _, codepoints = text:gsub("[^\128-\191]", "")
  local _, wide = text:gsub("界", "")
  return codepoints + wide
end

---@param name string
---@param fn CheatsheetAction
---@return nil
function M.test(name, fn)
  M.tests[#M.tests + 1] = { name = name, run = fn }
end

---@param label string
---@return nil
function M.run(label)
  local failed = 0
  for _, test in ipairs(M.tests) do
    local ok, err = xpcall(test.run, debug.traceback)
    if not ok then
      failed = failed + 1
      io.stderr:write("FAIL " .. test.name .. "\n" .. tostring(err) .. "\n")
    end
  end
  assert(failed == 0, tostring(failed) .. " test(s) failed")
  print(label .. ": " .. #M.tests .. " tests passed")
end

return M
