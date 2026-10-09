local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(vim.fn.stdpath("data") .. "/site")
vim.opt.packpath:append(vim.fn.stdpath("data") .. "/site")
vim.cmd.packadd("nvim-treesitter")
package.path = root .. "/tests/?.lua;" .. package.path
vim.o.swapfile = false
local t = require("support")
local plugin = require("css_in_js")
local api = vim.api
local controller = require("css_in_js.controller")
local integration = require("css_in_js.integrations.nvim")
local original_notify = vim.notify
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function() end

---@generic T
---@param owner table<string, T>
---@param name string
---@param replacement T
---@param fn CssInJsCancel
local function fault(owner, name, replacement, fn)
  local original = owner[name]
  owner[name] = replacement
  local ok, err = xpcall(fn, debug.traceback)
  owner[name] = original
  assert(ok, err)
end

---@param ft? string
---@param text? string
---@return integer, CssInJsSource, CssInJsContext
local function fixture(ft, text)
  plugin.setup()
  local buf = api.nvim_create_buf(true, false)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = ft or "typescriptreact"
  text = text or "const a = css`color: red;`;"
  api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  local col = assert(text:find("color", 1, true)) - 1
  return buf, plugin.new(), { bufnr = buf, cursor = { 1, col }, line = text }
end

---@return integer
local function hidden_count()
  local count = 0
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_get_name(buf):find(".css-in-js-", 1, true) then
      count = count + 1
    end
  end
  return count
end

---@param fn fun(client: CssInJsMockClient, replies: CssInJsReply[]): nil
local function with_client(fn)
  ---@type CssInJsReply[]
  local replies = {}
  local client = {
    id = 12345,
    name = "css_in_js",
    initialized = true,
    offset_encoding = "utf-16",
    attached_buffers = {},
    stopped = false,
  }
  function client:is_stopped()
    return self.stopped
  end
  function client:supports_method()
    return true
  end
  function client:stop()
    self.stopped = true
  end
  function client:request(_, _, callback)
    replies[#replies + 1] = callback
    return true, #replies
  end
  function client:cancel_request() end
  fault(vim.lsp, "start", function()
    return client.id
  end, function()
    fault(vim.lsp, "get_client_by_id", function(id)
      return id == client.id and client or nil
    end, function()
      fn(client, replies)
      plugin.teardown()
    end)
  end)
end

for _, ft in ipairs({ "javascript", "javascriptreact", "typescript", "typescriptreact" }) do
  for _, tag in ipairs({ "styled.div", "css", "keyframes", "createGlobalStyle" }) do
    t.test(ft .. " tagged template " .. tag, function()
      local buf, _, ctx = fixture(ft, "const a = " .. tag .. "`color: red;`;")
      assert(plugin.context(buf, 0, ctx.cursor[2]))
      assert(plugin.supports_buffer(buf))
      plugin.teardown()
      api.nvim_buf_delete(buf, { force = true })
    end)
  end
end
for _, tag in ipairs({ "styled.div<Props>", "styled(Component)<Props>", "styled.div.attrs({})" }) do
  t.test("TSX generic/attrs " .. tag, function()
    local buf, _, ctx = fixture(nil, "const a = " .. tag .. "`color: red;`;")
    assert(plugin.context(buf, 0, ctx.cursor[2]))
    api.nvim_buf_delete(buf, { force = true })
  end)
end
t.test("substitution, tag and surrounding JavaScript stay outside CSS", function()
  local text = "const a = css`color: ${props.color};`;"
  local buf = fixture(nil, text)
  t.equal(plugin.context(buf, 0, 0), nil)
  t.equal(plugin.context(buf, 0, assert(text:find("props", 1, true)) - 1), nil)
  t.equal(plugin.supports_buffer(-1), false)
  vim.bo[buf].filetype = "css"
  t.equal(plugin.supports_buffer(buf), false)
end)
t.test("start exception frees partially allocated buffers", function()
  local _, source, ctx = fixture()
  vim.lsp.config("cssls", { cmd = { "unused" } })
  local before = hidden_count()
  fault(vim.lsp, "start", function()
    error("start failed")
  end, function()
    source:get_completions(ctx, function(response)
      t.equal(response.items, {})
    end)
  end)
  t.equal(hidden_count(), before)
end)
t.test("failure to obtain a client frees the hidden buffer", function()
  local _, source, ctx = fixture()
  local before = hidden_count()
  fault(vim.lsp, "start", function()
    return nil
  end, function()
    source:get_completions(ctx, function(response)
      t.equal(response.items, {})
    end)
  end)
  t.equal(hidden_count(), before)
end)
t.test("hidden documents suppress diagnostics and other CSS server attachments", function()
  local _, source, ctx = fixture()
  fault(vim.lsp, "start", function(config, options)
    local buf = options.bufnr
    assert(not vim.bo[buf].buflisted and vim.bo[buf].filetype == "")
    assert(not api.nvim_buf_get_name(buf):match("%.css$"))
    assert(config.handlers["textDocument/publishDiagnostics"])
    t.equal(config.settings.css.validate, false)
    t.equal(config.get_language_id(), "css")
    return nil
  end, function()
    source:get_completions(ctx, function() end)
  end)
end)
t.test("LSP response and item defaults stay unchanged", function()
  with_client(function(_, replies)
    local _, source, ctx = fixture()
    local input = {
      itemDefaults = {
        insertTextFormat = 2,
        editRange = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 5 } },
      },
      items = { { label = "color" } },
    }
    local before = t.copy(input)
    source:get_completions(ctx, function(response)
      t.equal(#response.items, 1)
    end)
    replies[1](nil, input)
    t.equal(input, before)
  end)
end)
t.test("switching regions without edits rejects the old response", function()
  with_client(function(_, replies)
    local text = "const a = css`color: red;`; const b = css`padding: 1px;`;"
    local _, source, ctx = fixture(nil, text)
    local calls = 0
    source:get_completions(ctx, function()
      calls = calls + 1
    end)
    local tick = api.nvim_buf_get_changedtick(ctx.bufnr)
    ctx.cursor = { 1, assert(text:find("padding", 1, true)) - 1 }
    source:get_completions(ctx, function() end)
    t.equal(api.nvim_buf_get_changedtick(ctx.bufnr), tick)
    replies[1](nil, { items = { { label = "stale" } } })
    t.equal(calls, 0)
  end)
end)
t.test("host deletion and repeated teardown remove all hidden buffers", function()
  with_client(function(_, replies)
    local buf, source, ctx = fixture()
    local calls = 0
    source:get_completions(ctx, function()
      calls = calls + 1
    end)
    api.nvim_buf_delete(buf, { force = true })
    replies[1](nil, { items = {} })
    plugin.teardown()
    plugin.teardown()
    t.equal(hidden_count(), 0)
    t.equal(calls, 0)
  end)
end)
t.test("TS completion remains available before CSS is ready", function()
  local _, _, ctx = fixture()
  local items = { { label = "ts", client_id = 999 } }
  fault(vim.lsp, "get_client_by_id", function()
    return { name = "vtsls" }
  end, function()
    t.equal(plugin.filter_lsp_items(ctx, items), items)
  end)
end)
t.test("parser override restores owned settings and respects foreign replacements", function()
  local parsers = require("nvim-treesitter.parsers")
  local before = t.copy(parsers.styled.install_info)
  local info = { url = "test", revision = "pinned" }
  plugin.setup({ styled_parser = info })
  info.url = "changed"
  t.equal(parsers.styled.install_info.url, "test")
  plugin.teardown()
  t.equal(parsers.styled.install_info, before)
  plugin.setup({ styled_parser = { url = "test" } })
  parsers.styled.install_info = { url = "foreign" }
  plugin.teardown()
  t.equal(parsers.styled.install_info.url, "foreign")
  parsers.styled.install_info = before
end)
t.test("partial handler installation rolls back and permits setup retry", function()
  plugin.teardown()
  fault(api, "nvim_create_autocmd", function()
    error("registration failed")
  end, function()
    plugin.setup()
  end)
  local present = pcall(api.nvim_get_autocmds, { group = "CssInJsDocuments" })
  t.equal(present, false)
  plugin.setup()
  t.equal(#api.nvim_get_autocmds({ group = "CssInJsDocuments" }), 2)
end)
t.test("independent adapters create unique buffers and handlers", function()
  with_client(function(_, _)
    local buf, _, ctx = fixture()
    local a, b = controller.new(integration.new()), controller.new(integration.new())
    a.setup()
    b.setup()
    a.complete(ctx, function() end)
    b.complete(ctx, function() end)
    assert(hidden_count() == 2)
    api.nvim_buf_delete(buf, { force = true })
    t.equal(hidden_count(), 0)
    a.teardown()
    b.teardown()
  end)
end)
t.test("parser override follows replaced parser definitions on TSUpdate", function()
  local parsers = require("nvim-treesitter.parsers")
  local previous = parsers.styled
  plugin.setup({ styled_parser = { url = "pinned-parser" } })
  parsers.styled = { install_info = { url = "updated-parser" } }
  api.nvim_exec_autocmds("User", { pattern = "TSUpdate" })
  t.equal(parsers.styled.install_info.url, "pinned-parser")
  plugin.teardown()
  parsers.styled = previous
end)
t.test("parser owners restore the baseline with either teardown order", function()
  local treesitter = require("css_in_js.integrations.treesitter")
  local parsers = require("nvim-treesitter.parsers")
  local baseline = t.copy(parsers.styled.install_info)
  for _, first in ipairs({ "a", "b" }) do
    local a, b = treesitter.override("CssOwnerA"), treesitter.override("CssOwnerB")
    a.setup({ url = "owner-A" })
    b.setup({ url = "owner-B" })
    if first == "a" then
      a.teardown()
      t.equal(parsers.styled.install_info.url, "owner-B")
      b.teardown()
    else
      b.teardown()
      t.equal(parsers.styled.install_info.url, "owner-A")
      a.teardown()
    end
    t.equal(parsers.styled.install_info, baseline)
  end
end)
t.test("TSUpdate applies the newest active owner regardless of callback order", function()
  local treesitter = require("css_in_js.integrations.treesitter")
  local parsers = require("nvim-treesitter.parsers")
  local baseline = t.copy(parsers.styled.install_info)
  local a, b = treesitter.override("CssOwnerA"), treesitter.override("CssOwnerB")
  a.setup({ url = "owner-A" })
  b.setup({ url = "owner-B" })
  a.setup({ url = "owner-A-new" })
  api.nvim_exec_autocmds("User", { pattern = "TSUpdate" })
  t.equal(parsers.styled.install_info.url, "owner-A-new")
  a.teardown()
  b.teardown()
  t.equal(parsers.styled.install_info, baseline)
end)
t.test("default parser owners have independent registrations and preserve foreign definitions", function()
  local treesitter = require("css_in_js.integrations.treesitter")
  local parsers = require("nvim-treesitter.parsers")
  local baseline = t.copy(parsers.styled.install_info)
  local a, b = treesitter.override(), treesitter.override()
  a.setup({ url = "owner-A" })
  b.setup({ url = "owner-B" })
  b.teardown()
  vim.api.nvim_exec_autocmds("User", { pattern = "TSUpdate" })
  t.equal(parsers.styled.install_info.url, "owner-A")
  parsers.styled.install_info = { url = "foreign" }
  a.teardown()
  t.equal(parsers.styled.install_info.url, "foreign")
  parsers.styled.install_info = baseline
end)
t.test("configured server selection preserves configs and separates client reuse", function()
  local config = require("css_in_js.core.config")
  vim.lsp.config("css_test_a", { cmd = { "server-a" }, settings = { css = { validate = true } } })
  vim.lsp.config("css_test_b", { cmd = { "server-b" } })
  local baseline = t.copy(vim.lsp.config.css_test_a)
  local host = api.nvim_create_buf(true, false)
  local a, b = integration.new(), integration.new()
  a.install(config.normalize({ server_name = "css_test_a" }), function() end)
  b.install(config.normalize({ server_name = "css_test_b" }), function() end)
  local calls = 0
  ---@type vim.lsp.Client?
  local candidate_client
  ---@type CssInJsAllocation[]
  local allocations = {}
  fault(vim.lsp, "start", function(server, opts)
    calls = calls + 1
    if calls == 1 then
      t.equal(server.cmd, { "server-a" })
      local candidate = {
        id = 919191,
        name = "css_in_js",
        config = { root_dir = server.root_dir },
        is_stopped = function()
          return false
        end,
      }
      ---@cast candidate vim.lsp.Client
      candidate_client = candidate
      return candidate.id
    end
    local reuse = assert(opts.reuse_client)
    t.equal(reuse(assert(candidate_client), server), calls == 3)
    t.equal(server.cmd, calls == 2 and { "server-b" } or { "server-a" })
    return nil
  end, function()
    allocations[1] = a.create(host)
    allocations[2] = b.create(host)
    a.close(allocations[1])
    allocations[3] = a.create(host)
  end)
  t.equal(calls, 3)
  t.equal(vim.lsp.config.css_test_a, baseline)
  for _, allocation in ipairs(allocations) do
    a.close(allocation)
  end
  a.uninstall()
  b.uninstall()
  api.nvim_buf_delete(host, { force = true })
end)
t.test("configured hover appearance is copied and resets on reinstall", function()
  local config = require("css_in_js.core.config")
  local adapter = integration.new()
  local input = { hover = { border = "single", max_width = 64, max_height = 8 } }
  adapter.install(config.normalize(input), function() end)
  input.hover.max_width = 1
  local calls = 0
  fault(vim.lsp.util, "open_floating_preview", function(contents, syntax, preview)
    calls = calls + 1
    t.equal(contents, { "CSS documentation" })
    t.equal(syntax, "markdown")
    t.equal(preview.focus_id, "textDocument/hover")
    if calls <= 2 then
      t.equal(preview.border, "single")
      t.equal(preview.max_width, 64)
      t.equal(preview.max_height, 8)
      preview.max_width = 1
    else
      t.equal(preview.border, "rounded")
      t.equal(preview.max_width, nil)
      t.equal(preview.max_height, nil)
    end
    return 0, 0
  end, function()
    local result = { contents = { kind = "markdown", value = "CSS documentation" } }
    adapter.show_hover(result)
    adapter.show_hover(result)
    adapter.install(config.normalize(), function() end)
    adapter.show_hover(result)
  end)
  t.equal(calls, 3)
  adapter.uninstall()
end)
t.test("public source configuration changes affect existing instances", function()
  local buf, source = fixture()
  plugin.setup({ filetypes = {}, trigger_characters = {} })
  assert(not source:enabled())
  t.equal(source:get_trigger_characters(), {})
  plugin.setup({ filetypes = { "typescriptreact" }, trigger_characters = { ":" } })
  assert(source:enabled())
  t.equal(source:get_trigger_characters(), { ":" })
  plugin.teardown()
  api.nvim_buf_delete(buf, { force = true })
end)
t.test("missing configured server leaves completion fallback and allocates no hidden documents", function()
  local buf, source, ctx = fixture()
  plugin.setup({ server_name = "css_in_js_missing_server" })
  local before = hidden_count()
  local calls = 0
  source:get_completions(ctx, function(response)
    t.equal(response.items, {})
    calls = calls + 1
  end)
  t.equal(calls, 1)
  t.equal(hidden_count(), before)
  local items = { { label = "ts", client_id = 123 } }
  assert(plugin.filter_lsp_items(ctx, items) == items)
  plugin.teardown()
  api.nvim_buf_delete(buf, { force = true })
end)
t.test("public context extracts the syntax tree once and keeps public nodes", function()
  local buf, _, ctx = fixture()
  local treesitter = require("css_in_js.integrations.treesitter")
  local context = treesitter.context
  local calls = 0
  fault(treesitter, "context", function(host, row, col)
    calls = calls + 1
    return context(host, row, col)
  end, function()
    local region_value = assert(plugin.context(buf, 0, ctx.cursor[2]))
    assert(region_value.node:type() == "template_string")
    t.equal(calls, 1)
    t.equal(plugin.context(buf, -1, 0), nil)
    t.equal(plugin.context(buf, 0, -1), nil)
    t.equal(calls, 1)
    vim.b[buf].bigfile = true
    plugin.setup({
      filter = function(host)
        return not vim.b[host].bigfile
      end,
    })
    t.equal(plugin.context(buf, 0, ctx.cursor[2]), nil)
    t.equal(calls, 1)
  end)
  plugin.teardown()
  api.nvim_buf_delete(buf, { force = true })
end)
t.test("native snapshot reads only template rows and skips reads on repeated completion", function()
  with_client(function(_, replies)
    local buf, source, ctx = fixture()
    local text = { "const header = 1;", "const a = css`color: red;`;", "const footer = 2;" }
    api.nvim_buf_set_lines(buf, 0, -1, false, text)
    ctx.cursor = { 2, 14 }
    ctx.line = text[2]
    local read = api.nvim_buf_get_lines
    local reads = 0
    fault(api, "nvim_buf_get_lines", function(host, first, last, strict)
      if host == buf then
        reads = reads + 1
        t.equal({ first, last }, { 1, 2 })
      end
      return read(host, first, last, strict)
    end, function()
      source:get_completions(ctx, function(response)
        t.equal(response.items[1].textEdit.range.start, { line = 1, character = 14 })
      end)
      replies[1](nil, {
        items = {
          {
            label = "color",
            textEdit = {
              newText = "color",
              range = {
                start = { line = 1, character = 0 },
                ["end"] = { line = 1, character = 5 },
              },
            },
          },
        },
      })
      source:get_completions(ctx, function() end)
      replies[2](nil, { items = {} })
      t.equal(reads, 1)
    end)
  end)
end)
local ok, err = pcall(t.run, "css-in-js Neovim adapters and regressions")
plugin.teardown()
vim.notify = original_notify
assert(ok, err)
