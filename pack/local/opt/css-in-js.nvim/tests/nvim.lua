local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
vim.o.swapfile = false
local api = vim.api
local function equal(actual, expected)
  assert(vim.deep_equal(actual, expected), "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual))
end
-- Use installed parsers and bundled queries without loading the host config.
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/site")
vim.opt.packpath:append(vim.fn.stdpath("data") .. "/site")
vim.cmd.packadd("nvim-treesitter")

local plugin = require("css_in_js")
local regions = require("css_in_js.regions")
local source = plugin.new()
plugin.setup()
plugin.setup()
equal(#api.nvim_get_autocmds({ group = "CssInJsDocuments" }), 2)
local buf = api.nvim_get_current_buf()
vim.bo[buf].filetype = "typescriptreact"
api.nvim_buf_set_name(buf, "/private/tmp/css-in-js-test.tsx")
local function template(text, needle)
  api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  local col = assert(text:find(needle, 1, true)) - 1
  return assert(plugin.context(buf, 0, col), text), col
end
for _, text in ipairs({
  "const a = styled.div`color: red;`;",
  "const a = styled.div<Props>`color: red;`;",
  "const a = styled(Component)<Props>`color: red;`;",
  "const a = css`color: red;`;",
  "const a = keyframes`color: red;`;",
  "const a = createGlobalStyle`color: red;`;",
}) do
  template(text, "color")
end
local text = "const a = styled.div`color: ${props.😀}; padding: 1px;`;"
local region, col = template(text, "color")
assert(not plugin.context(buf, 0, assert(text:find("props", 1, true)) - 1))
local document = regions.document(buf, region)
equal(document[1], "a{")
equal(document[#document], ";}")
assert(not document[2]:find("props", 1, true))
equal(
  vim.str_utfindex(document[2], "utf-16"),
  vim.str_utfindex(text:sub(region.start_col + 1, region.end_col), "utf-16")
)
equal(
  regions.host_range(
    { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 5 } },
    region,
    region.start_col
  ),
  {
    start = { line = 0, character = region.start_col },
    ["end"] = { line = 0, character = region.start_col + 5 },
  }
)
equal(
  regions.host_range({ start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 0 } }, region, 0),
  nil
)
assert(source:enabled())
plugin.setup({
  filter = function()
    return false
  end,
})
assert(not source:enabled())
plugin.setup()
-- Exercise source edits, cancellation and hidden-buffer cleanup at the LSP boundary.
vim.lsp.config("cssls", { cmd = { "unused-css-server" } })
local client = { id = 12345, name = "css_in_js", initialized = true }
function client:is_stopped()
  return false
end
local hidden, response, cancel_id
local original_start, original_get = vim.lsp.start, vim.lsp.get_client_by_id
vim.lsp.start = function(config, opts)
  hidden = opts.bufnr
  equal(config.name, "css_in_js")
  equal(config.get_language_id(), "css")
  equal(config.settings.css.validate, false)
  return client.id
end
vim.lsp.get_client_by_id = function(id)
  return id == client.id and client or { name = "vtsls" }
end
function client:request(method, params, callback, request_buf)
  equal(method, "textDocument/completion")
  equal(request_buf, hidden)
  equal(params.position.line, 1)
  response = callback
  return true, 42
end
function client:cancel_request(id)
  cancel_id = id
end
region, col = template("const a = styled.div`color: red;`;", "color")
local ctx = { bufnr = buf, cursor = { 1, col }, line = api.nvim_get_current_line() }
local result
local cancel = source:get_completions(ctx, function(value)
  result = value
end)
response(nil, {
  itemDefaults = {
    insertTextFormat = 2,
    editRange = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 5 } },
  },
  items = {
    { label = "color", textEditText = "color: $0" },
    {
      label = "invalid",
      textEdit = {
        newText = "bad",
        range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } },
      },
    },
  },
})
equal(#result.items, 1)
equal(result.items[1].insertTextFormat, 2)
equal(result.items[1].textEdit.range.start, { line = 0, character = region.start_col })
equal(result.items[1].client_id, client.id)
assert(not vim.bo[hidden].buflisted)
assert(vim.bo[hidden].filetype == "")
local items = { { client_id = client.id }, { client_id = 999 } }
equal(plugin.filter_lsp_items(ctx, items), { items[1] })
result = nil
cancel = source:get_completions(ctx, function(value)
  result = value
end)
cancel()
response(nil, { items = { { label = "late" } } })
equal(cancel_id, 42)
equal(result, nil)
-- A changed host document invalidates an outstanding response.
source:get_completions(ctx, function(value)
  result = value
end)
api.nvim_buf_set_lines(buf, 0, -1, false, { "const changed = true;" })
response(nil, { items = { { label = "stale" } } })
equal(result.items, {})
api.nvim_buf_delete(buf, { force = true })
assert(not api.nvim_buf_is_valid(hidden))
vim.lsp.start, vim.lsp.get_client_by_id = original_start, original_get
-- A caller-supplied parser override survives nvim-treesitter refresh events.
local info = { url = "test-parser", revision = "pinned", files = { "src/parser.c" } }
plugin.setup({ styled_parser = info })
local parsers = require("nvim-treesitter.parsers")
equal(parsers.styled.install_info, info)
parsers.styled.install_info = {}
api.nvim_exec_autocmds("User", { pattern = "TSUpdate" })
equal(parsers.styled.install_info, info)
print("css-in-js: Neovim tests passed")
