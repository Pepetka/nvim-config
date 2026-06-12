local config = {
  cmd = { "vscode-html-language-server", "--stdio" },
  filetypes = { "html" },
  root_markers = { "package.json", ".git" },
  init_options = {
    provideFormatter = true,
    embeddedLanguages = { css = true, javascript = true },
    configurationSection = { "html", "css", "javascript" },
  },
  settings = {
    html = {
      format = {
        wrapLineLength = 120,
        wrapAttributes = "auto",
        indentInnerHtml = true,
      },
      validate = {
        scripts = true,
        styles = true,
      },
      suggest = {
        html5 = true,
      },
      autoClosingTags = true,
    },
  },
}

return config
