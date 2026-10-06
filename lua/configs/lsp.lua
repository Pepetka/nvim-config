local map = vim.keymap.set
local map_opts = require("utils.map_opts")

local capabilities = require("blink.cmp").get_lsp_capabilities(vim.lsp.protocol.make_client_capabilities())

vim.lsp.config("*", {
  capabilities = capabilities,
  on_init = function(client, _)
    if client:supports_method("textDocument/semanticTokens") then
      client.server_capabilities.semanticTokensProvider = nil
    end
  end,
})

vim.diagnostic.config({
  virtual_text = {
    prefix = "",
    spacing = 4,
    source = "if_many",
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = " ",
      [vim.diagnostic.severity.WARN] = " ",
      [vim.diagnostic.severity.HINT] = "󰠠 ",
      [vim.diagnostic.severity.INFO] = " ",
    },
  },
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = {
    border = "rounded",
    source = "if_many",
    header = "",
  },
})

-- Neovim 0.11+ sets 'concealcursor=""' in stylized LSP floating windows
-- (hover, signature help, docs) so concealed markdown is visible. Override
-- open_floating_preview to restore "nv" so code fences (e.g. ```lua) stay
-- hidden while still allowing navigation/visual selection when focused.
do
  local orig_open_floating_preview = vim.lsp.util.open_floating_preview
  ---@diagnostic disable-next-line: duplicate-set-field
  function vim.lsp.util.open_floating_preview(contents, syntax, opts, ...)
    local bufnr, winnr = orig_open_floating_preview(contents, syntax, opts, ...)
    if winnr and vim.api.nvim_win_is_valid(winnr) then
      if vim.bo[bufnr].filetype == "markdown" and vim.wo[winnr].conceallevel > 0 then
        vim.wo[winnr].concealcursor = "nv"
      end
    end
    return bufnr, winnr
  end
end

-- Inlay hints are enabled globally; toggle with <leader>ui
vim.lsp.inlay_hint.enable(true)

-- Notify only Svelte servers whose workspace contains the saved JS/TS file.
vim.api.nvim_create_autocmd("BufWritePost", {
  group = vim.api.nvim_create_augroup("SvelteTsFileChanges", { clear = true }),
  pattern = { "*.js", "*.ts" },
  callback = function(args)
    local path = vim.api.nvim_buf_get_name(args.buf)
    local uri = vim.uri_from_fname(path)
    for _, client in ipairs(vim.lsp.get_clients({ name = "svelte" })) do
      local roots = {}
      if client.config.root_dir then
        roots[#roots + 1] = client.config.root_dir
      end
      for _, folder in ipairs(client.workspace_folders or {}) do
        roots[#roots + 1] = vim.uri_to_fname(folder.uri)
      end
      for _, root in ipairs(roots) do
        if vim.fs.relpath(root, path) then
          client:notify("$/onDidChangeTsOrJsFile", { uri = uri })
          break
        end
      end
    end
  end,
})

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
  callback = function(args)
    local bufnr = args.buf
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client then
      return
    end

    -- CSS Modules: avoid conflicts with TypeScript LSP's go-to-definition
    if client.name == "cssmodules_ls" then
      client.server_capabilities.definitionProvider = false
    end

    local function opts(desc)
      return map_opts("LSP: " .. desc, { buffer = bufnr })
    end

    local native_lsp_maps = {
      { "n", "grn" },
      { "n", "gra" },
      { "n", "grr" },
      { "n", "gri" },
      { "n", "grt" },
      { "n", "gO" },
    }
    for _, keymap in ipairs(native_lsp_maps) do
      pcall(vim.keymap.del, keymap[1], keymap[2], { buffer = bufnr })
    end

    map("n", "gd", vim.lsp.buf.definition, opts("Go to Definition"))
    map("n", "gD", vim.lsp.buf.declaration, opts("Go to Declaration"))
    map("n", "grr", vim.lsp.buf.references, opts("References"))
    map("n", "gri", vim.lsp.buf.implementation, opts("Implementation"))
    map("n", "grt", vim.lsp.buf.type_definition, opts("Type Definition"))

    map("n", "K", function()
      require("completion.css_in_js").hover()
    end, opts("Hover Documentation"))
    map("n", "grn", vim.lsp.buf.rename, opts("Rename Symbol"))
    map({ "n", "v" }, "<leader>la", vim.lsp.buf.code_action, opts("Code Action"))

    map("n", "]d", function()
      vim.diagnostic.jump({ count = 1 })
    end, opts("Next Diagnostic"))
    map("n", "[d", function()
      vim.diagnostic.jump({ count = -1 })
    end, opts("Previous Diagnostic"))
    map("n", "<leader>ld", vim.diagnostic.open_float, opts("Show Line Diagnostic"))
  end,
})
