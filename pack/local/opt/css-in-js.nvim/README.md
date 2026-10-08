# css-in-js.nvim

Local CSS-in-JS completion and hover for styled-components / Emotion templates in
JavaScript, JSX, TypeScript and TSX. Neovim >=0.12 is required.

The plugin contains its Blink source, template extraction and edit mapping, supplemental
Tree-sitter injection queries, and an optional nvim-treesitter parser override integration.
It does not load personal configuration modules or install dependencies.

## Setup

```lua
vim.cmd.packadd("css-in-js.nvim")
require("css_in_js").setup({
  filter = function(buf) return not vim.b[buf].bigfile end,
})
```

Configure `vim.lsp.config.cssls` with an available CSS language server. Install the
`javascript`, `typescript`, `tsx` and `styled` parsers and their bundled injection queries
using nvim-treesitter. This plugin extends the `ecma` and `typescript` injection queries;
load it before parsing templates. Highlighting and parser installation remain caller-owned.

Optional `styled_parser` accepts an nvim-treesitter `install_info` table. When supplied,
setup replaces the styled parser definition and reapplies it on `User TSUpdate`.
This requires nvim-treesitter and must run before parser installation. The host pins its
chosen fork in `lua/configs/css_in_js.lua`; the plugin has no hardcoded parser revision.

Add the source and filter TS completions inside CSS regions:

```lua
require("blink.cmp").setup({
  sources = {
    default = { "lsp", "css_in_js" },
    providers = {
      css_in_js = { name = "CSS-in-JS", module = "css_in_js" },
      lsp = { transform_items = require("css_in_js").filter_lsp_items },
    },
  },
})
```

`require("css_in_js").hover()` requests CSS hover inside a template and delegates to
`vim.lsp.buf.hover()` elsewhere. The caller owns its keymap. `context(buf, row, col)`
uses zero-based byte coordinates and returns the active region or nil;
`supports_buffer(buf)` also applies the optional caller filter.

Templates use hidden in-memory CSS buffers, without a CSS filetype, named to avoid
other CSS servers attaching. Substitutions are masked while preserving UTF-16 widths;
`${...}` stays with TypeScript completion/hover. Generated CSS diagnostics are suppressed.
Completion edit ranges are translated back to the host, including item defaults and
additional edits. Cancelled requests and replies after host edits are discarded.
Hidden buffers are deleted when their host buffer is deleted. Setup replaces cleanup
handlers on repeated calls. `filter_lsp_items` removes vtsls/tsgo items only inside CSS.

## Tests

Run from this plugin's root, or pass an absolute script path from any directory:

```sh
NVIM_LOG_FILE=/tmp/css-in-js-nvim.log XDG_STATE_HOME=/tmp/css-in-js-state nvim --clean --headless -i NONE -l tests/nvim.lua
stylua --check .
```

The suite uses installed nvim-treesitter queries and parsers under `stdpath("data")/site`;
it does not load the host configuration, install parsers or start a language server.
Real syntax trees exercise generic styled templates, css/keyframes/createGlobalStyle,
substitution exclusion and UTF-16 masking. A controlled LSP client exercises completion
mapping, item defaults, invalid edits, TS filtering, cancellation, stale replies and
hidden-buffer cleanup. Parser override refresh and caller filters are also checked.
