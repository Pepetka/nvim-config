---@class TabBuffersTestCase
---@field name string
---@field run fun(): nil

local M = {}
---@type TabBuffersTestCase[]
local tests = {}

---@generic T
---@param value T
---@return T
function M.copy(value)
  return require("tab_buffers.core.lists").copy(value)
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

---@param fn fun(): unknown?
---@param pattern? string
---@return nil
function M.raises(fn, pattern)
  local ok, err = pcall(fn)
  assert(not ok, "expected an error")
  if pattern then
    assert(tostring(err):find(pattern, 1, true), tostring(err))
  end
end

---@param name string
---@param run fun(): nil
---@return nil
function M.test(name, run)
  tests[#tests + 1] = { name = name, run = run }
end

---@param label string
---@return nil
function M.run(label)
  local failed = 0
  for _, case in ipairs(tests) do
    local ok, err = xpcall(case.run, debug.traceback)
    if not ok then
      failed = failed + 1
      io.stderr:write("FAIL " .. case.name .. "\n" .. tostring(err) .. "\n")
    end
  end
  assert(failed == 0, tostring(failed) .. " test(s) failed")
  print(label .. ": " .. #tests .. " tests passed")
end

return M
