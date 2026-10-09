local settings = require("css_in_js.core.config")
local treesitter = require("css_in_js.integrations.treesitter")
local M = {}
local sequence = 0
---@type table<integer, string>
local owned_clients = {}

---@return CssInJsAdapter
function M.new()
  local options = settings.normalize()
  local api = vim.api
  sequence = sequence + 1
  local owner = sequence
  local suffix = owner == 1 and "" or tostring(owner)
  local override = treesitter.override("CssInJsParser" .. suffix)
  local group
  local adapter = {}

  ---@return CssInJsContext
  function adapter.current()
    return {
      bufnr = api.nvim_get_current_buf(),
      cursor = api.nvim_win_get_cursor(0),
      line = api.nvim_get_current_line(),
    }
  end
  ---@param buf integer
  ---@return { filetype: string, buftype: string }?
  function adapter.buffer(buf)
    if not api.nvim_buf_is_valid(buf) then
      return nil
    end
    return { filetype = vim.bo[buf].filetype, buftype = vim.bo[buf].buftype }
  end
  ---@param buf integer
  ---@return integer?
  function adapter.tick(buf)
    return api.nvim_buf_is_valid(buf) and api.nvim_buf_get_changedtick(buf) or nil
  end
  ---@param buf integer
  ---@param row integer
  ---@param col integer
  ---@return CssInJsRegion?
  function adapter.extract(buf, row, col)
    local region = treesitter.context(buf, row, col)
    return region and treesitter.plain(region) or nil
  end
  ---@param buf integer
  ---@param first_row integer
  ---@param last_row integer
  ---@return string[]
  function adapter.lines(buf, first_row, last_row)
    return api.nvim_buf_get_lines(buf, first_row, last_row, true)
  end
  ---@param id integer
  ---@return CssInJsClient?
  function adapter.client(id)
    local client = vim.lsp.get_client_by_id(id)
    if not client then
      return nil
    end
    return {
      id = id,
      name = client.name,
      initialized = client.initialized,
      stopped = client:is_stopped(),
      encoding = client.offset_encoding or "utf-16",
      completion = client.initialized and client:supports_method("textDocument/completion"),
      hover = client.initialized and client:supports_method("textDocument/hover"),
    }
  end
  ---@param id integer
  ---@return string?
  function adapter.client_name(id)
    local client = vim.lsp.get_client_by_id(id)
    return client and client.name or nil
  end
  ---@param allocation CssInJsAllocation
  ---@return boolean
  function adapter.valid(allocation)
    return allocation.buf ~= nil and api.nvim_buf_is_valid(allocation.buf)
  end
  ---@param allocation CssInJsAllocation
  function adapter.close(allocation)
    if allocation.buf and api.nvim_buf_is_valid(allocation.buf) then
      api.nvim_buf_delete(allocation.buf, { force = true })
    end
    local id = allocation.client_id
    local client = id and vim.lsp.get_client_by_id(id) or nil
    if id and owned_clients[id] and client and next(client.attached_buffers) == nil then
      client:stop()
      owned_clients[id] = nil
    end
  end
  ---@param host integer
  ---@return CssInJsAllocation, string?
  function adapter.create(host)
    ---@type CssInJsAllocation
    local allocation = {}
    local base = vim.lsp.config[options.server_name]
    if not base then
      return allocation
    end
    local ok, err = pcall(function()
      allocation.buf = api.nvim_create_buf(false, true)
      api.nvim_buf_set_name(allocation.buf, api.nvim_buf_get_name(host) .. ".css-in-js-" .. host .. "-" .. owner)
      local config = vim.deepcopy(base)
      config.name = "css_in_js"
      config.root_dir = vim.fs.root(host, { "package.json", ".git" }) or vim.fn.getcwd()
      config.get_language_id = function()
        return "css"
      end
      config.capabilities = vim.tbl_deep_extend(
        "force",
        vim.lsp.protocol.make_client_capabilities(),
        config.capabilities or {},
        { general = { positionEncodings = { "utf-16", "utf-8", "utf-32" } } }
      )
      config.settings = vim.tbl_deep_extend("force", config.settings or {}, { css = { validate = false } })
      config.handlers =
        vim.tbl_extend("force", config.handlers or {}, { ["textDocument/publishDiagnostics"] = function() end })
      local existing = {}
      for _, client in ipairs(vim.lsp.get_clients()) do
        existing[client.id] = true
      end
      allocation.client_id = vim.lsp.start(config, {
        bufnr = allocation.buf,
        reuse_client = function(client, candidate)
          return owned_clients[client.id] == options.server_name
            and not client:is_stopped()
            and client.name == candidate.name
            and client.config.root_dir == candidate.root_dir
        end,
      })
      if allocation.client_id and not existing[allocation.client_id] then
        owned_clients[allocation.client_id] = options.server_name
      end
    end)
    return allocation, not ok and tostring(err) or nil
  end
  ---@param allocation CssInJsAllocation
  ---@param lines string[]
  function adapter.write(allocation, lines)
    api.nvim_buf_set_lines(assert(allocation.buf), 0, -1, false, lines)
  end
  ---@param allocation CssInJsAllocation
  ---@return string
  function adapter.uri(allocation)
    return vim.uri_from_bufnr(assert(allocation.buf))
  end
  ---@param allocation CssInJsAllocation
  ---@param method CssInJsMethod
  ---@param params lsp.CompletionParams | lsp.HoverParams
  ---@param callback fun(err: unknown, result: unknown): nil
  ---@return integer?
  function adapter.request(allocation, method, params, callback)
    local client = assert(vim.lsp.get_client_by_id(assert(allocation.client_id)))
    local success, id = client:request(method, params, callback, assert(allocation.buf))
    return success and id or nil
  end
  ---@param allocation CssInJsAllocation
  ---@param id integer
  function adapter.cancel(allocation, id)
    local client = allocation.client_id and vim.lsp.get_client_by_id(allocation.client_id) or nil
    if client then
      client:cancel_request(id)
    end
  end
  ---@return integer
  function adapter.now()
    return vim.uv.now()
  end
  ---@param delay integer
  ---@param callback CssInJsCancel
  ---@return CssInJsCancel
  function adapter.schedule(delay, callback)
    local cancelled = false
    local timer = vim.defer_fn(function()
      if not cancelled then
        callback()
      end
    end, delay)
    return function()
      cancelled = true
      if not timer:is_closing() then
        timer:stop()
        timer:close()
      end
    end
  end
  function adapter.uninstall()
    if group then
      api.nvim_del_augroup_by_id(group)
      group = nil
    end
    override.teardown()
    for id in pairs(owned_clients) do
      local client = vim.lsp.get_client_by_id(id)
      if not client or client:is_stopped() then
        owned_clients[id] = nil
      elseif next(client.attached_buffers) == nil then
        client:stop()
        owned_clients[id] = nil
      end
    end
  end
  ---@param config CssInJsConfig
  ---@param deleted fun(buf: integer): nil
  function adapter.install(config, deleted)
    adapter.uninstall()
    options = settings.copy(config)
    local ok, err = pcall(function()
      group = api.nvim_create_augroup("CssInJsDocuments" .. suffix, { clear = true })
      api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = group,
        callback = function(args)
          deleted(args.buf)
        end,
      })
      if config.styled_parser then
        override.setup(config.styled_parser)
      end
    end)
    if not ok then
      adapter.uninstall()
      error(err, 0)
    end
  end
  function adapter.fallback_hover()
    vim.lsp.buf.hover()
  end
  ---@param result? lsp.Hover
  function adapter.show_hover(result)
    if not result or not result.contents then
      vim.notify("No information available")
      return
    end
    local contents = vim.lsp.util.convert_input_to_markdown_lines(result.contents)
    if #contents > 0 then
      ---@type vim.lsp.util.open_floating_preview.Opts
      local preview = {
        border = options.hover.border,
        max_width = options.hover.max_width,
        max_height = options.hover.max_height,
        focus_id = "textDocument/hover",
      }
      vim.lsp.util.open_floating_preview(contents, "markdown", preview)
    end
  end
  ---@param message string
  function adapter.notify(message)
    vim.notify(message, vim.log.levels.WARN)
  end
  return adapter
end

return M
