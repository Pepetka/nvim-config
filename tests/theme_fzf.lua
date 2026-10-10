-- Exercise real provider entries and the pipe transformation used to feed fzf.
return function()
  local core = require("fzf-lua.core")
  local shell = require("fzf-lua.shell")
  local utils = require("fzf-lua.utils")
  local original_exec = core.fzf_exec
  local original_clients = vim.lsp.get_clients
  local original_client = vim.lsp.get_client_by_id
  local original_request = vim.lsp.buf_request_sync
  local namespace = vim.api.nvim_create_namespace("ThemeFzfEntriesTest")
  local job
  local picker_buffer
  local output
  local colored_files = false

  core.fzf_exec = function(contents, opts)
    -- Read the actual input pipe, including fn_transform, without launching fzf.
    local command = shell.stringify_mt(contents, opts) or shell.stringify(contents, opts)
    if opts.pipe_cmd then
      command = "(" .. command .. ") | " .. vim.fn.shellescape(opts.fzf_bin) .. " --filter='' --ansi"
    end
    local finished, code
    output = nil
    job = vim.fn.jobstart(command, {
      stdout_buffered = true,
      on_stdout = function(_, lines)
        output = table.concat(lines, "\n")
      end,
      on_exit = function(_, status)
        code = status
        finished = true
      end,
    })
    assert(job > 0, "Could not read the fzf input pipe")
    assert(
      vim.wait(5000, function()
        return finished
      end, 10),
      "Fzf input pipe did not finish"
    )
    job = nil
    assert(code == 0 and output and #output > 0, "Fzf input pipe returned no entries")
    assert(not output:find("38;2;", 1, true) and not output:find("48;2;", 1, true), "Fzf retained RGB colors")
    if not colored_files then
      assert(not output:find("\27[", 1, true), "Fzf provider serialized frozen colors: " .. vim.inspect(output))
    end
  end

  local ok, err = xpcall(function()
    vim.cmd.enew()
    local buffer = vim.api.nvim_get_current_buf()
    local filename = vim.fn.tempname() .. ".lua"
    vim.api.nvim_buf_set_name(buffer, filename)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { "local sample = function() end" })
    local range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 27 } }
    local client = {
      id = 99999,
      name = "theme-test",
      offset_encoding = "utf-16",
      supports_method = function()
        return true
      end,
    }
    vim.lsp.get_clients = function()
      return { client }
    end
    vim.lsp.get_client_by_id = function()
      return client
    end
    vim.lsp.buf_request_sync = function(_, method)
      local symbol = { name = "sample", kind = vim.lsp.protocol.SymbolKind.Function }
      if method == "textDocument/documentSymbol" then
        symbol.range, symbol.selectionRange = range, range
      else
        assert(method == "workspace/symbol", "Unexpected test LSP request: " .. method)
        symbol.location = { uri = vim.uri_from_fname(filename), range = range }
      end
      return { [client.id] = { result = { symbol } } }
    end

    for _, mode in ipairs({ "light", "dark" }) do
      vim.o.background = mode
      colored_files = true
      for _, multiprocess in ipairs({ false, true }) do
        require("fzf-lua").files({
          cmd = "printf '%s\\n' 'lua/utils/colors.lua' 'src/app.js' 'file with spaces.lua'",
          git_icons = false,
          multiprocess = multiprocess,
          hidden = false,
          follow = false,
          no_ignore = false,
        })
        assert(
          output:find("\27[0;90mlua/utils/\27[0mcolors.lua", 1, true),
          "File directories are not muted: " .. vim.inspect(output) .. "; multiprocess=" .. tostring(multiprocess)
        )
        assert(output:find("\27[0;33m", 1, true), "JavaScript icon lost its ANSI yellow")
        assert(output:find("file with spaces.lua", 1, true), "File coloring changed a filename")
        for _, line in ipairs(vim.split(output, "\n", { trimempty = true })) do
          local filename = require("fzf-lua.path").entry_to_file(line, {}).path
          assert(filename and not filename:find("\27", 1, true), "ANSI colors broke file actions")
        end
        utils.clear_CTX()
      end
      require("fzf-lua").git_files({ multiprocess = true })
      assert(output:find("\27[0;90mlua/utils/\27[0mcolors.lua", 1, true), "Git files lost ANSI path colors")
      utils.clear_CTX()
      colored_files = false
      vim.diagnostic.set(namespace, buffer, {
        {
          lnum = 0,
          col = 0,
          severity = vim.diagnostic.severity.ERROR,
          message = "Theme error",
          source = "theme-test",
          code = "E123",
        },
        {
          lnum = 0,
          col = 1,
          severity = vim.diagnostic.severity.WARN,
          message = "Theme warning",
          source = "theme-test",
          code = "W456",
        },
      })
      require("fzf-lua.providers.diagnostic").diagnostics({
        namespace = namespace,
        signs = { Error = { text = "E" }, Warn = { text = "W" } },
      })
      for _, text in ipairs({ "Theme error", "Theme warning", "theme-test", "E123", "W456" }) do
        assert(output:find(text, 1, true), "Diagnostics lost text: " .. text)
      end
      assert(output:find("E" .. utils.nbsp, 1, true), "Diagnostics lost the error sign")
      assert(output:find("W" .. utils.nbsp, 1, true), "Diagnostics lost the warning sign")
      utils.clear_CTX()
      for _, provider in ipairs({ "document_symbols", "workspace_symbols" }) do
        require("fzf-lua.providers.lsp")[provider]({ async = false })
        assert(output:find("sample", 1, true) and output:find("Function", 1, true), "LSP lost symbol details")
        utils.clear_CTX()
      end
    end

    -- The diagnostic wrapper must also work in an interactive terminal, where
    -- fzf reads keys from the TTY while receiving entries through the pipe.
    core.fzf_exec = original_exec
    require("fzf-lua").diagnostics_document({ namespace = namespace, query = "E123" })
    local function diagnostic_visible()
      local win = require("fzf-lua.win").__SELF()
      if not win or not win.fzf_bufnr or not vim.api.nvim_buf_is_valid(win.fzf_bufnr) then
        return false
      end
      picker_buffer = win.fzf_bufnr
      local text = table.concat(vim.api.nvim_buf_get_lines(picker_buffer, 0, -1, false), "\n")
      return text:find("Theme error", 1, true) and text:find("E123", 1, true)
    end
    assert(vim.wait(3000, diagnostic_visible, 10), "Interactive diagnostics lost the message or code")
    local original_buffer = picker_buffer
    for _, mode in ipairs({ "light", "dark" }) do
      vim.o.background = mode
      vim.wait(100)
      assert(diagnostic_visible() and picker_buffer == original_buffer, "Theme recreated or cleared diagnostics")
    end
  end, debug.traceback)

  if job then
    vim.fn.jobstop(job)
  end
  if picker_buffer and vim.api.nvim_buf_is_valid(picker_buffer) then
    pcall(require("fzf-lua").hide)
    local channel = vim.bo[picker_buffer].channel
    if channel > 0 then
      vim.fn.jobstop(channel)
    end
  end
  core.fzf_exec = original_exec
  vim.lsp.get_clients = original_clients
  vim.lsp.get_client_by_id = original_client
  vim.lsp.buf_request_sync = original_request
  vim.diagnostic.reset(namespace)
  utils.clear_CTX()
  assert(ok, err)
end
