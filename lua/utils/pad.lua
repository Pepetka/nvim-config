---Return the display width of a string.
---@param str string
---@return integer
local strwidth = function(str)
  if type(vim) == "table" and vim.api and vim.api.nvim_strwidth then
    return vim.api.nvim_strwidth(str)
  end
  return #str
end

---Pad a string to the requested length with a fill character.
---@param str string
---@param length integer
---@param mode "left" | "right" | "center" | nil defaults to "center"
---@param fill_char string | nil defaults to " "
---@return string
local pad = function(str, length, mode, fill_char)
  mode = mode or "center"
  fill_char = fill_char or " "

  local width = strwidth(str)
  if width >= length then
    return str
  end

  local pad_length = length - width
  if mode == "left" then
    return string.rep(fill_char, pad_length) .. str
  elseif mode == "right" then
    return str .. string.rep(fill_char, pad_length)
  end

  local left_pad = math.floor(pad_length / 2)
  local right_pad = pad_length - left_pad
  return string.rep(fill_char, left_pad) .. str .. string.rep(fill_char, right_pad)
end

return pad
