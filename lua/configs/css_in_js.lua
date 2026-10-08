require("css_in_js").setup({
  filter = function(buf)
    return not vim.b[buf].bigfile
  end,
  -- Use the forked styled parser until the upstream fix is merged.
  styled_parser = {
    url = "https://github.com/Pepetka/tree-sitter-styled",
    revision = "e2bfd21812dadd0d7a84dfc878c9151f61295944",
    files = { "src/parser.c", "src/scanner.c" },
  },
})
