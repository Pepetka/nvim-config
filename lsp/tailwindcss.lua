---@type vim.lsp.Config
return {
  cmd = { "tailwindcss-language-server", "--stdio" },
  filetypes = {
    "html",
    "css",
    "javascript",
    "javascriptreact",
    "typescript",
    "typescriptreact",
    "svelte",
    "vue",
    "astro",
    "templ",
  },
  root_markers = {
    "tailwind.config.js",
    "tailwind.config.ts",
    "postcss.config.js",
    "postcss.config.ts",
  },
  workspace_required = true,
  capabilities = {
    workspace = {
      didChangeWatchedFiles = {
        dynamicRegistration = true,
      },
    },
  },
  settings = {
    tailwindCSS = {
      validate = true,
      lint = {
        cssConflict = "warning",
        invalidApply = "error",
        invalidConfigPath = "error",
        invalidScreen = "error",
        invalidTailwindDirective = "error",
        invalidVariant = "error",
        recommendedVariantOrder = "warning",
      },
      classAttributes = {
        "class",
        "className",
        "class:list",
        "classList",
        "ngClass",
      },
      includeLanguages = {
        svelte = "html",
        astro = "html",
        templ = "html",
      },
      experimental = {
        classRegex = {
          -- tw`...`
          "tw`([^`]*)`",
          -- tw(...)
          "tw\\(([^)]*)\\)",
          -- clsx(...) / cn(...) / cva(...)
          "(?:clsx|cn|cva)\\(([^)]*)\\)",
          -- xxxClassNamexxx = "..." | '...'
          "[a-zA-Z]*[cC]lass[Nn]ame[s]?[a-zA-Z]*\\s*=\\s*[\"']([^\"']*)[\"']",
          -- "xxxClassNamexxx": "..."
          "[\"']?[a-zA-Z]*[cC]lass[Nn]ame[s]?[\"']?\\s*:\\s*[\"']([^\"']*)[\"']",
          -- classNames={{ key: '...' }} or classNames: { key: '...' }
          {
            "(?:classNames|[a-zA-Z]*[cC]lass[Nn]ames)\\s*(?:=|:)\\s*\\{\\{?([\\s\\S]*?)\\}\\}?",
            "[\"']([^\"']*)[\"']",
          },
          -- const classes = ["...", "..."] / const styles = [...]
          {
            "(?:const|let|var)\\s+[a-zA-Z]*(?:[cC]lasses|[cC]lassNames|[cC]lassList|[sS]tyles)\\s*=\\s*\\{?\\[([\\s\\S]*?)\\]\\}?",
            "[\"']([^\"']*)[\"']",
          },
          -- className={[...]} / class={[...]} / classNames={[...]}
          {
            "(?:className|classNames|class)\\s*=\\s*\\{?\\[([\\s\\S]*?)\\]\\}?",
            "[\"']([^\"']*)[\"']",
          },
        },
      },
    },
  },
}
