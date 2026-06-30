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

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspConfig", { clear = true }),
  callback = function(args)
    local bufnr = args.buf
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client then
      return
    end

    vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })

    -- Svelte: workaround to trigger reloading JS/TS files
    -- See https://github.com/sveltejs/language-tools/issues/2008
    if client.name == "svelte" then
      vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = { "*.js", "*.ts" },
        group = vim.api.nvim_create_augroup("lspconfig.svelte", {}),
        callback = function(ctx)
          ---@diagnostic disable-next-line: param-type-mismatch
          client:notify("$/onDidChangeTsOrJsFile", { uri = ctx.match })
        end,
      })
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

    map("n", "K", vim.lsp.buf.hover, opts("Hover Documentation"))
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
