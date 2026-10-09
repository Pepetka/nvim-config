local config = require("css_in_js.core.config")
local copy = config.copy
local document = require("css_in_js.core.document")
local before = require("css_in_js.core.regions").before
local M = {}

---@return CssInJsResponse
function M.empty()
  return { items = {}, is_incomplete_forward = true, is_incomplete_backward = true }
end

---@param edit unknown
---@param snapshot CssInJsDocument
---@param encoding CssInJsEncoding
---@return lsp.TextEdit | lsp.InsertReplaceEdit | nil
function M.edit(edit, snapshot, encoding)
  if type(edit) ~= "table" or type(edit.newText) ~= "string" then
    return nil
  end
  local result = copy(edit)
  if edit.range ~= nil then
    if edit.insert ~= nil or edit.replace ~= nil then
      return nil
    end
    result.range = document.host_range(snapshot, edit.range, encoding)
    if not result.range then
      return nil
    end
  else
    result.insert = document.host_range(snapshot, edit.insert, encoding)
    result.replace = document.host_range(snapshot, edit.replace, encoding)
    if not result.insert or not result.replace then
      return nil
    end
    if
      result.insert.start.line ~= result.replace.start.line
      or result.insert.start.character ~= result.replace.start.character
      or result.insert.start.line ~= result.insert["end"].line
      or result.replace.start.line ~= result.replace["end"].line
      or result.insert["end"].character > result.replace["end"].character
    then
      return nil
    end
  end
  return result
end

---@param ranges lsp.Range[]
---@return boolean
function M.disjoint(ranges)
  for index, current in ipairs(ranges) do
    for previous_index = 1, index - 1 do
      local previous = ranges[previous_index]
      local same_start = current.start.line == previous.start.line
        and current.start.character == previous.start.character
      if
        same_start
        or (
          before(current.start.line, current.start.character, previous["end"].line, previous["end"].character)
          and before(previous.start.line, previous.start.character, current["end"].line, current["end"].character)
        )
      then
        return false
      end
    end
  end
  return true
end

---@param value unknown
---@param defaults unknown
---@param snapshot CssInJsDocument
---@param client CssInJsClient
---@param cursor_column integer
---@return CssInJsItem?
function M.item(value, defaults, snapshot, client, cursor_column)
  if type(value) ~= "table" or type(value.label) ~= "string" then
    return nil
  end
  defaults = type(defaults) == "table" and defaults or {}
  local item = copy(value)
  for _, key in ipairs({ "insertTextFormat", "insertTextMode", "commitCharacters", "data" }) do
    if item[key] == nil then
      item[key] = copy(defaults[key])
    end
  end
  if item.textEdit == nil and defaults.editRange ~= nil then
    local range = defaults.editRange
    if type(range) ~= "table" then
      return nil
    end
    item.textEdit = range.start ~= nil and { range = copy(range) } or copy(range)
    item.textEdit.newText = item.textEditText or item.insertText or item.label
  end
  if item.insertTextFormat ~= nil and item.insertTextFormat ~= 1 and item.insertTextFormat ~= 2 then
    return nil
  end
  if item.insertTextMode ~= nil and item.insertTextMode ~= 1 and item.insertTextMode ~= 2 then
    return nil
  end
  if item.insertText ~= nil and type(item.insertText) ~= "string" then
    return nil
  end
  if item.commitCharacters ~= nil then
    if not config.list(item.commitCharacters) then
      return nil
    end
    for _, char in ipairs(item.commitCharacters) do
      if type(char) ~= "string" then
        return nil
      end
    end
  end
  if item.textEdit ~= nil then
    item.textEdit = M.edit(item.textEdit, snapshot, client.encoding)
    if not item.textEdit then
      return nil
    end
  end
  if item.additionalTextEdits ~= nil then
    if not config.list(item.additionalTextEdits) then
      return nil
    end
    for index, edit in ipairs(item.additionalTextEdits) do
      local mapped = M.edit(edit, snapshot, client.encoding)
      if not mapped or not mapped.range then
        return nil
      end
      item.additionalTextEdits[index] = mapped
    end
  end
  ---@type lsp.Range[]
  local ranges = {}
  if item.textEdit then
    ranges[#ranges + 1] = item.textEdit.range or item.textEdit.replace
  end
  for _, edit in ipairs(item.additionalTextEdits or {}) do
    ranges[#ranges + 1] = edit.range
  end
  if not M.disjoint(ranges) then
    return nil
  end
  item.client_id, item.client_name, item.cursor_column = client.id, client.name, cursor_column
  return item
end

---@param result unknown
---@return boolean
function M.valid_response(result)
  if type(result) ~= "table" then
    return false
  end
  if result.items == nil then
    return config.list(result)
  end
  return config.list(result.items)
    and (result.isIncomplete == nil or type(result.isIncomplete) == "boolean")
    and (result.itemDefaults == nil or type(result.itemDefaults) == "table")
end

---@param result unknown
---@param snapshot CssInJsDocument
---@param client CssInJsClient
---@param cursor_column integer
---@return CssInJsResponse
function M.response(result, snapshot, client, cursor_column)
  local response = M.empty()
  if not M.valid_response(result) then
    return response
  end
  ---@cast result table
  local values = result.items or result
  for _, value in ipairs(values) do
    local item = M.item(value, result.itemDefaults, snapshot, client, cursor_column)
    if item then
      response.items[#response.items + 1] = item
    end
  end
  return response
end

return M
