local css = require("css_in_js.regions")
local api = vim.api
local M = {}
local documents = {}

---@param opts? { filter?: fun(buf: integer): boolean, styled_parser?: table }
function M.setup(opts)
  opts = opts or {}
  css.setup(opts)
  if opts.styled_parser then
    require("css_in_js.treesitter").setup(opts.styled_parser)
  end
  api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = api.nvim_create_augroup("CssInJsDocuments", { clear = true }),
    callback = function(args)
      local document = documents[args.buf]
      documents[args.buf] = nil
      if document and api.nvim_buf_is_valid(document.buf) then
        api.nvim_buf_delete(document.buf, { force = true })
      end
    end,
  })
end

-- Public helpers for host completion integrations.
M.context = css.context
M.supports_buffer = css.supports_buffer

---@param ctx table
---@param items table[]
---@return table[]
function M.filter_lsp_items(ctx, items)
  if not css.context(ctx.bufnr, ctx.cursor[1] - 1, ctx.cursor[2]) then
    return items
  end
  return vim.tbl_filter(function(item)
    local client = vim.lsp.get_client_by_id(item.client_id)
    return not client or (client.name ~= "tsgo" and client.name ~= "vtsls")
  end, items)
end

function M.new()
  return setmetatable({}, { __index = M })
end

function M:enabled()
  return css.supports_buffer(api.nvim_get_current_buf())
end

function M:get_trigger_characters()
  return { ":", "-", " " }
end

local function get_document(buf)
  local document = documents[buf]
  if document and api.nvim_buf_is_valid(document.buf) then
    local client = vim.lsp.get_client_by_id(document.client_id)
    if client and not client:is_stopped() then
      return document, client
    end
    api.nvim_buf_delete(document.buf, { force = true })
  end
  local base_config = vim.lsp.config.cssls
  if not base_config then
    return nil
  end
  local hidden = api.nvim_create_buf(false, true)
  -- Avoid a .css name or filetype: other CSS servers must not attach here.
  api.nvim_buf_set_name(hidden, api.nvim_buf_get_name(buf) .. ".css-in-js-" .. buf)
  local config = vim.deepcopy(base_config)
  config.name = "css_in_js"
  config.root_dir = vim.fs.root(buf, { "package.json", ".git" }) or vim.fn.getcwd()
  config.get_language_id = function()
    return "css"
  end
  config.capabilities =
    vim.tbl_deep_extend("force", vim.lsp.protocol.make_client_capabilities(), config.capabilities or {}, {
      general = { positionEncodings = { "utf-16" } },
    })
  config.settings = vim.tbl_deep_extend("force", config.settings or {}, { css = { validate = false } })
  config.handlers = vim.tbl_extend("force", config.handlers or {}, {
    ["textDocument/publishDiagnostics"] = function() end,
  })
  local client_id = vim.lsp.start(config, { bufnr = hidden })
  if not client_id then
    api.nvim_buf_delete(hidden, { force = true })
    return nil
  end
  document = { buf = hidden, client_id = client_id }
  documents[buf] = document
  return document, vim.lsp.get_client_by_id(client_id)
end

local function request_css(ctx, region, method, callback)
  local row, col = ctx.cursor[1] - 1, ctx.cursor[2]
  local document, client = get_document(ctx.bufnr)
  if not document or not client then
    callback(nil)
    return
  end
  api.nvim_buf_set_lines(document.buf, 0, -1, false, css.document(ctx.bufnr, region))
  local first_line = api.nvim_buf_get_lines(ctx.bufnr, region.start_row, region.start_row + 1, false)[1]
  local column_offset = vim.str_utfindex(first_line, "utf-16", region.start_col)
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(document.buf) },
    position = {
      line = row - region.start_row + 1,
      character = vim.str_utfindex(ctx.line, "utf-16", col) - (row == region.start_row and column_offset or 0),
    },
    context = method == "textDocument/completion" and { triggerKind = 1 } or nil,
  }
  local cancelled, request_id
  local tick = api.nvim_buf_get_changedtick(ctx.bufnr)
  local deadline = vim.uv.now() + 5000
  local function request()
    if cancelled then
      return
    end
    if
      not api.nvim_buf_is_valid(ctx.bufnr)
      or api.nvim_buf_get_changedtick(ctx.bufnr) ~= tick
      or client:is_stopped()
    then
      callback(nil)
      return
    end
    if not client.initialized then
      if vim.uv.now() < deadline then
        vim.defer_fn(request, 20)
      else
        callback(nil)
      end
      return
    end
    local success
    success, request_id = client:request(method, params, function(err, result)
      if cancelled then
        return
      end
      if
        err
        or not result
        or not api.nvim_buf_is_valid(ctx.bufnr)
        or api.nvim_buf_get_changedtick(ctx.bufnr) ~= tick
      then
        callback(nil)
        return
      end
      callback(result, column_offset, client)
    end, document.buf)
    if not success then
      callback(nil)
    end
  end
  request()
  return function()
    cancelled = true
    if request_id then
      client:cancel_request(request_id)
    end
  end
end

function M:get_completions(ctx, callback)
  local region = css.context(ctx.bufnr, ctx.cursor[1] - 1, ctx.cursor[2])
  local function empty()
    callback({ items = {}, is_incomplete_forward = true, is_incomplete_backward = true })
  end
  if not region then
    empty()
    return
  end
  return request_css(ctx, region, "textDocument/completion", function(result, column_offset, client)
    if not result then
      empty()
      return
    end
    local items = {}
    for _, item in ipairs(result.items or result) do
      local defaults = result.itemDefaults or {}
      item.insertTextFormat = item.insertTextFormat or defaults.insertTextFormat
      local edit = item.textEdit
      if not edit and defaults.editRange then
        edit = vim.deepcopy(defaults.editRange)
        if edit.start then
          edit = { range = edit }
        end
        edit.newText = item.textEditText or item.insertText or item.label
        item.textEdit = edit
      end
      local valid = true
      for _, key in ipairs({ "range", "insert", "replace" }) do
        if edit and edit[key] then
          edit[key] = css.host_range(edit[key], region, column_offset)
          valid = valid and edit[key] ~= nil
        end
      end
      for _, additional in ipairs(item.additionalTextEdits or {}) do
        additional.range = css.host_range(additional.range, region, column_offset)
        valid = valid and additional.range ~= nil
      end
      if valid then
        item.client_id = client.id
        item.client_name = client.name
        items[#items + 1] = item
      end
    end
    callback({ items = items, is_incomplete_forward = true, is_incomplete_backward = true })
  end)
end

function M.hover()
  local buf = api.nvim_get_current_buf()
  local cursor = api.nvim_win_get_cursor(0)
  local region = css.context(buf, cursor[1] - 1, cursor[2])
  if not region then
    return vim.lsp.buf.hover()
  end
  local ctx = { bufnr = buf, cursor = cursor, line = api.nvim_get_current_line() }
  return request_css(ctx, region, "textDocument/hover", function(result)
    if api.nvim_get_current_buf() ~= buf or not vim.deep_equal(api.nvim_win_get_cursor(0), cursor) then
      return
    end
    if not result or not result.contents then
      vim.notify("No information available")
      return
    end
    local contents = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
    if #contents > 0 then
      vim.lsp.util.open_floating_preview(contents, "markdown", {
        border = "rounded",
        focus_id = "textDocument/hover",
      })
    end
  end)
end

return M
