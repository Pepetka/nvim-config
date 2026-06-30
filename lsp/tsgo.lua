-- Experimental Go-native TypeScript language server from Microsoft.
-- Install via Mason (`:MasonInstall tsgo`) or npm:
--   npm install -D @typescript/native-preview
--
-- Switch between vtsls and tsgo with `vim.g.ts_lsp` in lua/options.lua.
-- Note: tsgo does not support tsserver plugins (e.g. Svelte / styled-components).
--
-- Upstream reference:
-- https://github.com/neovim/nvim-lspconfig/blob/master/lsp/tsgo.lua

---@type vim.lsp.Config
return {
  settings = {
    typescript = {
      updateImportsOnFileMove = { enabled = "always" },
      suggest = {
        completeFunctionCalls = true,
      },
      inlayHints = {
        parameterNames = { enabled = "literals", suppressWhenArgumentMatchesName = true },
        parameterTypes = { enabled = true },
        variableTypes = { enabled = true, suppressWhenTypeMatchesName = true },
        propertyDeclarationTypes = { enabled = true },
        functionLikeReturnTypes = { enabled = true },
        enumMemberValues = { enabled = true },
      },
      preferences = {
        importModuleSpecifier = "shortest",
        importModuleSpecifierEnding = "auto",
        quoteStyle = "auto",
        includePackageJsonAutoImports = "auto",
      },
    },
    javascript = {
      updateImportsOnFileMove = { enabled = "always" },
      suggest = {
        completeFunctionCalls = true,
      },
      inlayHints = {
        parameterNames = { enabled = "literals", suppressWhenArgumentMatchesName = true },
        parameterTypes = { enabled = true },
        variableTypes = { enabled = true, suppressWhenTypeMatchesName = true },
        propertyDeclarationTypes = { enabled = true },
        functionLikeReturnTypes = { enabled = true },
        enumMemberValues = { enabled = true },
      },
      preferences = {
        importModuleSpecifier = "shortest",
        importModuleSpecifierEnding = "auto",
        quoteStyle = "auto",
        includePackageJsonAutoImports = "auto",
      },
    },
  },
  cmd = function(dispatchers, config_ctx)
    local cmd = "tsgo"
    if (config_ctx or {}).root_dir then
      local local_cmd = vim.fs.joinpath(config_ctx.root_dir, "node_modules/.bin", cmd)
      if vim.fn.executable(local_cmd) == 1 then
        cmd = local_cmd
      end
    end
    return vim.lsp.rpc.start({ cmd, "--lsp", "--stdio" }, dispatchers)
  end,
  filetypes = {
    "javascript",
    "javascriptreact",
    "javascript.jsx",
    "typescript",
    "typescriptreact",
    "typescript.tsx",
  },
  root_markers = {
    "package-lock.json",
    "yarn.lock",
    "pnpm-lock.yaml",
    "bun.lockb",
    "bun.lock",
    "tsconfig.json",
    "jsconfig.json",
    ".git",
  },
}
