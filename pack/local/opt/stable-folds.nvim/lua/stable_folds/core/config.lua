local M = {}
M.foldexpr = "v:lua.require'stable_folds'.expr()"

---@param value unknown
---@return boolean
function M.integer(value)
  return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

---@return StableFoldsConfig
function M.defaults()
  return {
    filter = function()
      return true
    end,
    new_folds = "open",
    include_injections = true,
    max_lines = 0,
    max_bytes = 0,
    notify_errors = true,
  }
end

---@param opts? unknown
---@return StableFoldsConfig, string[]
function M.normalize(opts)
  local result, messages = M.defaults(), {}
  if opts == nil then
    return result, messages
  end
  if type(opts) ~= "table" then
    return result, { "stable-folds: invalid options, using defaults" }
  end
  for key, value in pairs(opts) do
    local valid = false
    if key == "filter" then
      valid = type(value) == "function"
    elseif key == "new_folds" then
      valid = value == "open" or value == "inherit"
    elseif key == "include_injections" then
      valid = type(value) == "boolean" or M.languages(value) ~= nil
      value = valid and type(value) == "table" and M.languages(value) or value
    elseif key == "notify_errors" then
      valid = type(value) == "boolean"
    elseif key == "max_lines" or key == "max_bytes" then
      valid = M.integer(value)
    else
      messages[#messages + 1] = "stable-folds: unknown option " .. tostring(key)
    end
    if result[key] ~= nil then
      if valid then
        result[key] = value
      else
        messages[#messages + 1] = "stable-folds: invalid " .. key .. ", using default"
      end
    end
  end
  table.sort(messages)
  return result, messages
end

---Copy a language -> boolean table, or nil when any entry is invalid.
---@param value unknown
---@return table<string, boolean>?
function M.languages(value)
  if type(value) ~= "table" then
    return nil
  end
  local result = {}
  for lang, enabled in pairs(value) do
    if type(lang) ~= "string" or type(enabled) ~= "boolean" then
      return nil
    end
    result[lang] = enabled
  end
  return result
end

---Languages missing from a table include injections.
---@param options StableFoldsConfig
---@param lang? string
---@return boolean
function M.injections(options, lang)
  local value = options.include_injections
  if type(value) == "table" then
    return not lang or value[lang] ~= false
  end
  return value
end

---@param size StableFoldsSize
---@param options StableFoldsConfig
---@return boolean
function M.within_limits(size, options)
  return (options.max_lines == 0 or size.lines <= options.max_lines)
    and (options.max_bytes == 0 or size.bytes <= options.max_bytes)
end

return M
