local M = {}

---@return DashboardNavigationKeys
function M.defaults()
  return { next = { "j", "<Down>" }, previous = { "k", "<Up>" }, activate = { "<CR>" } }
end

---@param key string
---@return string
function M.normalize(key)
  return (key:gsub("<[^>]+>", string.lower))
end

---@param claimed table<string, boolean>
---@param key string
---@param normalize DashboardKeyNormalizer
---@param message string
---@return nil
function M.claim(claimed, key, normalize, message)
  local identity = normalize(key)
  assert(not claimed[identity], message .. ": " .. key)
  for existing in pairs(claimed) do
    assert(
      identity:sub(1, #existing) ~= existing and existing:sub(1, #identity) ~= identity,
      "conflicting key prefix: " .. key
    )
  end
  claimed[identity] = true
end

---@param keys DashboardNavigationKeys
---@param normalize DashboardKeyNormalizer
---@return table<string, boolean>
function M.reserved(keys, normalize)
  local result = {}
  for _, role in ipairs({ "next", "previous", "activate" }) do
    for _, key in ipairs(keys[role]) do
      M.claim(result, key, normalize, "duplicate navigation key")
    end
  end
  return result
end

return M
