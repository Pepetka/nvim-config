-- Native TypeScript server selected per project by utils.ts_lsp.
-- Note: tsgo does not support tsserver plugins (e.g. Svelte).
-- CSS-in-JS completion is provided independently by a blink source + cssls.
--
-- Upstream reference:
-- https://github.com/neovim/nvim-lspconfig/blob/master/lsp/tsgo.lua

---@type vim.lsp.Config
return {
  root_dir = require("utils.ts_lsp").root_dir("tsgo"),
  handlers = {
    ["textDocument/inlayHint"] = function(err, result, ctx)
      if result then
        for _, hint in ipairs(result) do
          local label = hint.label
          if type(label) == "table" then
            label = table.concat(vim.tbl_map(function(part)
              return part.value
            end, label))
          end

          if vim.fn.strchars(label) > 30 then
            hint.label = vim.fn.strcharpart(label, 0, 29) .. "…"
          end
        end
      end

      return vim.lsp.inlay_hint.on_inlayhint(err, result, ctx)
    end,
  },
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
    local command =
      assert(require("utils.ts_lsp").native_command(config_ctx.root_dir), "Native TypeScript is unavailable")
    return vim.lsp.rpc.start(command, dispatchers)
  end,
  filetypes = {
    "javascript",
    "javascriptreact",
    "javascript.jsx",
    "typescript",
    "typescriptreact",
    "typescript.tsx",
  },
}
