local svelte_plugin_path = vim.fn.stdpath("data")
  .. "/mason/packages/svelte-language-server/node_modules/typescript-svelte-plugin"

local global_plugins = {
  {
    name = "typescript-svelte-plugin",
    location = svelte_plugin_path,
    enableForWorkspaceTypeScriptVersions = true,
  },
}

---@type vim.lsp.Config
return {
  cmd = { "vtsls", "--stdio" },
  root_dir = require("utils.ts_lsp").root_dir("vtsls"),
  filetypes = {
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
  },
  init_options = {
    hostInfo = "neovim",
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
    vtsls = {
      autoUseWorkspaceTsdk = true,
      tsserver = {
        globalPlugins = global_plugins,
      },
      experimental = {
        completion = {
          enableServerSideFuzzyMatch = true,
          entriesLimit = 200,
        },
        maxInlayHintLength = 30,
      },
    },
  },
}
