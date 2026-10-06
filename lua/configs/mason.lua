local mason = require("mason")
local mason_lsp = require("mason-lspconfig")

mason.setup({
  ui = {
    border = "rounded",
    icons = {
      package_installed = "✓",
      package_pending = "➜",
      package_uninstalled = "✗",
    },
  },
})

local servers = {
  "html",
  "vtsls",
  "tsc",
  "gopls",
  "cssls",
  "jsonls",
  "yamlls",
  "lua_ls",
  "svelte",
  "prismals",
  "tailwindcss",
  "cssmodules_ls",
  "css_variables",
}

-- root_dir callbacks can decline to start a server for a large buffer.
-- Keep each server's existing root resolution, including workspace_required.
for _, name in ipairs(vim.list_extend(vim.deepcopy(servers), { "tsgo" })) do
  local config = vim.lsp.config[name]
  if config then
    local original_root_dir = config.root_dir
    vim.lsp.config(name, {
      root_dir = function(bufnr, on_dir)
        if vim.b[bufnr].bigfile then
          return
        end
        if type(original_root_dir) == "function" then
          return original_root_dir(bufnr, on_dir)
        end
        return on_dir(original_root_dir)
      end,
    })
  end
end

mason_lsp.setup({
  ensure_installed = servers,
  automatic_enable = {
    exclude = { "vtsls", "tsgo", "tsc" },
  },
})

vim.lsp.enable({ "vtsls", "tsgo" })

require("mason-registry"):on(
  "package:install:success",
  vim.schedule_wrap(function(pkg)
    if pkg.name == "vtsls" or pkg.name == "tsc" then
      require("utils.ts_lsp").refresh_all()
      vim.lsp.enable({ "vtsls", "tsgo" })
    end
  end)
)
