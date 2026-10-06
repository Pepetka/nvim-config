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
  root_dir = function(bufnr, on_dir)
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path == "" then
      return
    end
    local git_root = vim.fs.root(path, ".git")
    local dir = vim.fs.dirname(path)
    while dir do
      local ok, package = pcall(function()
        return vim.json.decode(table.concat(vim.fn.readfile(vim.fs.joinpath(dir, "package.json")), "\n"))
      end)
      if ok and type(package) == "table" then
        for _, section in ipairs({ "dependencies", "devDependencies" }) do
          local dependencies = package[section]
          if type(dependencies) == "table" and dependencies.tailwindcss then
            on_dir(dir)
            return
          end
        end
      end
      if dir == git_root then
        return
      end
      local parent = vim.fs.dirname(dir)
      if parent == dir then
        return
      end
      dir = parent
    end
  end,
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
