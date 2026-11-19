---@type CssInJsOptions
local options = {
  filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
  server_name = "cssls",
  request_timeout_ms = 5000,
  poll_interval_ms = 20,
  trigger_characters = { ":", "-", " " },
  suppressed_lsp_clients = { "vtsls", "tsgo" },
  hover = { border = "rounded" },
  filter = function(buf)
    return not vim.b[buf].bigfile
  end,
  -- Use the forked styled parser until the upstream fix is merged.
  styled_parser = {
    url = "https://github.com/Pepetka/tree-sitter-styled",
    revision = "a4f6cc5d1a2d1dd72a0d2265a29801e0e30c7f5d",
    files = { "src/parser.c", "src/scanner.c" },
  },
}

require("css_in_js").setup(options)
