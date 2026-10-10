---@class DashboardTestCase
---@field name string
---@field run DashboardTestAction

---@type DashboardTestCase[]
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

---@param name string
---@param fn DashboardTestAction
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
