local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/site")
vim.opt.packpath:append(vim.fn.stdpath("data") .. "/site")
vim.cmd.packadd("nvim-treesitter")
vim.o.swapfile = false
local command = vim.env.CSS_LS or vim.fn.exepath("vscode-css-language-server")
if command == "" then
  command = vim.fn.stdpath("data") .. "/mason/bin/vscode-css-language-server"
end
assert(vim.fn.executable(command) == 1, "Set CSS_LS to an installed vscode-css-language-server")
vim.lsp.config("cssls", { cmd = { command, "--stdio" } })
local plugin = require("css_in_js")
plugin.setup()
local api = vim.api
local buf = api.nvim_get_current_buf()
vim.bo[buf].filetype = "typescriptreact"
api.nvim_buf_set_name(buf, "/private/tmp/css-in-js-real-lsp.tsx")
local source = plugin.new()
local text = "const a = styled.div`color: re;`;"
api.nvim_buf_set_lines(buf, 0, -1, false, { text })
local col = assert(text:find("re;", 1, true)) + 1
---@type CssInJsResponse?
local response
local cancel = source:get_completions({ bufnr = buf, cursor = { 1, col }, line = text }, function(value)
  response = value
end)
---@type CssInJsController?
local hover
local ok, err = xpcall(function()
  assert(
    vim.wait(8000, function()
      return response ~= nil
    end, 10),
    "completion timed out"
  )
  ---@type CssInJsItem?
  local red
  for _, item in ipairs(assert(response).items) do
    if item.label == "red" then
      red = item
    end
  end
  assert(red, "real cssls did not return red")
  local edit = assert(red.textEdit)
  ---@cast edit lsp.TextEdit
  local client = assert(vim.lsp.get_client_by_id(assert(red.client_id)))
  vim.lsp.util.apply_text_edits({ edit }, buf, client.offset_encoding)
  assert(api.nvim_get_current_line() == "const a = styled.div`color: red;`;", "completion changed host syntax")
  local controller = require("css_in_js.controller")
  local adapter = require("css_in_js.integrations.nvim").new()
  local current = api.nvim_get_current_line()
  api.nvim_win_set_cursor(0, { 1, assert(current:find("color", 1, true)) - 1 })
  local captured
  local show = adapter.show_hover
  adapter.show_hover = function(result)
    captured = result
  end
  hover = controller.new(adapter)
  hover.setup()
  hover.hover()
  assert(
    vim.wait(8000, function()
      return captured ~= nil
    end, 10),
    "real hover timed out"
  )
  assert(captured.contents, "real hover has no contents")
  hover.teardown()
  adapter.show_hover = show

  local lines = {
    "export const StyledWrapper = styled.div<{ $withMinusPadding: boolean }>`",
    "  ${({ $withMinusPadding }) =>",
    "    $withMinusPadding",
    "      ? css`",
    "          margin-l: -30px;",
    "        `",
    "      : ''};",
    "",
    "  padding-inl: 30px;",
    "  padding-top: 29px;",
    "  padding-bottom: 20px;",
    "  background-color: ${({ theme }) => theme.common.secondary_background_color_300};",
    "`;",
  }
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local tick = api.nvim_buf_get_changedtick(buf)
  ---@param row integer
  ---@param prefix string
  ---@param label string
  ---@return lsp.TextEdit, CssInJsEncoding
  local function complete(row, prefix, label)
    response = nil
    local line = lines[row]
    local cursor_col = assert(line:find(prefix, 1, true)) - 1 + #prefix
    cancel = source:get_completions({ bufnr = buf, cursor = { row, cursor_col }, line = line }, function(value)
      response = value
    end)
    assert(
      vim.wait(8000, function()
        return response ~= nil
      end, 10),
      label .. " completion timed out"
    )
    for _, item in ipairs(assert(response).items) do
      if item.label == label then
        local item_client = assert(vim.lsp.get_client_by_id(assert(item.client_id)))
        ---@type lsp.TextEdit
        local item_edit = assert(item.textEdit)
        return item_edit, item_client.offset_encoding
      end
    end
    error("real cssls did not return " .. label)
  end
  local padding, encoding = complete(9, "padding-inl", "padding-inline")
  local margin = complete(5, "margin-l", "margin-left")
  complete(9, "padding-inl", "padding-inline")
  complete(5, "margin-l", "margin-left")
  assert(api.nvim_buf_get_changedtick(buf) == tick, "switching templates changed the host")
  vim.lsp.util.apply_text_edits({ padding, margin }, buf, encoding)
  lines[5] = "          margin-left: -30px;"
  lines[9] = "  padding-inline: 30px;"
  assert(vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), lines), "nested edits changed host syntax")
end, debug.traceback)
if hover then
  hover.teardown()
end
if cancel then
  cancel()
end
plugin.teardown()
assert(ok, err)
print("css-in-js real cssls: completion edits, nested templates and hover passed")
