local M = {}

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

---@param value unknown
---@return boolean
function M.integer(value)
  return type(value) == "number" and value >= 0 and value < math.huge and value == math.floor(value)
end

---@param value unknown
---@return boolean
function M.list(value)
  if type(value) ~= "table" then
    return false
  end
  local count = 0
  for key in pairs(value) do
    if not M.integer(key) or key == 0 then
      return false
    end
    count = count + 1
  end
  for index = 1, count do
    if value[index] == nil then
      return false
    end
  end
  return true
end

---@param value unknown
---@return boolean
local function parser_info(value)
  if type(value) ~= "table" or type(value.url) ~= "string" or value.url == "" then
    return false
  end
  for _, key in ipairs({ "revision", "location", "cxx_standard" }) do
    if value[key] ~= nil and type(value[key]) ~= "string" then
      return false
    end
  end
  for _, key in ipairs({ "generate", "generate_from_json", "requires_generate_from_grammar" }) do
    if value[key] ~= nil and type(value[key]) ~= "boolean" then
      return false
    end
  end
  if value.files ~= nil then
    if type(value.files) ~= "table" then
      return false
    end
    local count = 0
    for key, item in pairs(value.files) do
      if not M.integer(key) or key == 0 or type(item) ~= "string" or item == "" then
        return false
      end
      count = count + 1
    end
    if count ~= #value.files then
      return false
    end
    for index = 1, count do
      if value.files[index] == nil then
        return false
      end
    end
  end
  return true
end

---@param value unknown
---@return boolean
function M.string_list(value)
  if not M.list(value) then
    return false
  end
  ---@cast value table
  for _, item in ipairs(value) do
    if type(item) ~= "string" or item == "" then
      return false
    end
  end
  return true
end

---@param value unknown
---@return boolean
local function positive_integer(value)
  return M.integer(value) and value > 0
end

---@param value unknown
---@return boolean
local function hover_border(value)
  return value == "none"
    or value == "single"
    or value == "double"
    or value == "rounded"
    or value == "solid"
    or value == "shadow"
end

---@param options? unknown
---@return CssInJsConfig, string[]
function M.normalize(options)
  ---@type CssInJsConfig
  local result = {
    filter = function()
      return true
    end,
    filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
    server_name = "cssls",
    request_timeout_ms = 5000,
    poll_interval_ms = 20,
    trigger_characters = { ":", "-", " " },
    suppressed_lsp_clients = { "vtsls", "tsgo" },
    hover = { border = "rounded" },
  }
  ---@type string[]
  local messages = {}
  if options == nil then
    return result, messages
  end
  if type(options) ~= "table" then
    return result, { "css-in-js: invalid options, using defaults" }
  end
  ---@param name string
  local function invalid(name)
    messages[#messages + 1] = "css-in-js: invalid " .. name .. ", using default"
  end
  if options.filter ~= nil then
    if type(options.filter) == "function" then
      result.filter = options.filter
    else
      invalid("filter")
    end
  end
  if options.styled_parser ~= nil then
    if parser_info(options.styled_parser) then
      result.styled_parser = M.copy(options.styled_parser)
    else
      messages[#messages + 1] = "css-in-js: invalid styled_parser, ignoring override"
    end
  end
  for _, name in ipairs({ "filetypes", "trigger_characters", "suppressed_lsp_clients" }) do
    if options[name] ~= nil then
      if M.string_list(options[name]) then
        result[name] = M.copy(options[name])
      else
        invalid(name)
      end
    end
  end
  for _, name in ipairs({ "request_timeout_ms", "poll_interval_ms" }) do
    if options[name] ~= nil then
      if positive_integer(options[name]) then
        result[name] = options[name]
      else
        invalid(name)
      end
    end
  end
  if options.server_name ~= nil then
    if type(options.server_name) == "string" and options.server_name ~= "" then
      result.server_name = options.server_name
    else
      invalid("server_name")
    end
  end
  if options.hover ~= nil then
    if type(options.hover) ~= "table" then
      invalid("hover")
    else
      if options.hover.border ~= nil then
        if hover_border(options.hover.border) then
          result.hover.border = options.hover.border
        else
          invalid("hover.border")
        end
      end
      for _, name in ipairs({ "max_width", "max_height" }) do
        if options.hover[name] ~= nil then
          if positive_integer(options.hover[name]) then
            result.hover[name] = options.hover[name]
          else
            invalid("hover." .. name)
          end
        end
      end
    end
  end
  return result, messages
end

return M
