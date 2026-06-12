local svelte_plugin_path = vim.fn.stdpath("data")
  .. "/mason/packages/svelte-language-server/node_modules/typescript-svelte-plugin"

local styled_plugin_path = vim.trim(vim.fn.system("npm root -g")) .. "/@styled/typescript-styled-plugin"

local config = {
  cmd = { "vtsls", "--stdio" },
  filetypes = {
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
  },
  root_markers = {
    "package-lock.json",
    "yarn.lock",
    "pnpm-lock.yaml",
    "bun.lockb",
    "bun.lock",
    "tsconfig.json",
    ".git",
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
        globalPlugins = {
          {
            name = "typescript-svelte-plugin",
            location = svelte_plugin_path,
            enableForWorkspaceTypeScriptVersions = true,
          },
          {
            name = "@styled/typescript-styled-plugin",
            location = styled_plugin_path,
            enableForWorkspaceTypeScriptVersions = true,
          },
        },
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

return config
