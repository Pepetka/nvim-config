# Project Overview

Personal Neovim configuration (Lua, Neovim 0.12+, `vim.pack`). Targets the live config directory at `~/.config/nvim`.

## Technology Stack

- **Plugin manager:** `vim.pack` with lockfile `nvim-pack-lock.json`
- **LSP:** native `vim.lsp.config` + `mason.nvim` + `mason-lspconfig.nvim`
- **Completion:** `blink.cmp` (sources: `lazydev`, `lsp`, `path`, `snippets`, `buffer`)
- **Fuzzy finder:** `fzf-lua`
- **File tree:** `nvim-tree.lua`
- **Status/tab line:** `lualine.nvim` / `bufferline.nvim`
- **Dashboard:** `dashboard-nvim`
- **Colorscheme:** `tokyonight.nvim` (transparent, light/dark switched via `~/.config/theme/mode`)
- **Formatter:** `conform.nvim` (prefers Oxc when Oxc configs exist, else `eslint_d`/`prettierd`)
- **Linter:** `nvim-lint` (prefers `oxlint` when Oxc lint config exists, else `eslint_d`)
- **AI completion:** `windsurf.nvim` (active); `minuet-ai.nvim` and `neocodeium` configs are present but disabled
- **DAP:** `nvim-dap` + `nvim-dap-view` for JS/TS via `js-debug-adapter` and Go via `delve`
- **Extras:** `leap.nvim`, `vim-tmux-navigator`, `nvim-bqf`, `nvim-hlslens`, `todo-comments.nvim`, `mini.ai`, `mini.cursorword`

## Load Order

`init.lua` loads: `options` → `mappings` → `core` → `plugins`.

Plugin groups in `lua/plugins/init.lua` load in order: `shared` → `core` → `workflow` → `ui` → `extras`.

## Key Files

- `init.lua` — entry point
- `lua/options.lua` — `vim.opt` / `vim.g`, including `g.ts_lsp`
- `lua/mappings.lua` — global leader maps (`<leader>` = space, `<localleader>` = `\`)
- `lua/core.lua` — autocommands and user commands
  (`:PackClean`, `:PackUpdate`, `:LspRestart`, `:LspStop`, `:LspStart`, `:TsLspSwitch`)
- `lua/plugins/groups/*.lua` — plugin specs
- `lua/configs/*.lua` — per-plugin setup
- `lsp/*.lua` — server configs loaded by `vim.lsp.config` in `lua/configs/lsp.lua`
- `lua/utils/oxc_config.lua` — Oxc formatter/linter config detection
- `nvim-pack-lock.json` — pinned plugin revisions
- `stylua.toml` — formatter config (120 cols, 2 spaces, Unix endings, AutoPreferDouble)

## Build and Test Commands

No build step or test suite. When editing the config:

- `stylua --check .` — verify formatting
- `stylua .` — apply formatting
- `:source %` (`<leader>rs`) — reload current file
- `:restart` (`<leader>re`) — restart Neovim
- `:TsLspSwitch` (`<leader>lT`) — toggle between `vtsls` and `tsgo`
- `:PackClean` — remove unused `vim.pack` plugins
- `:PackUpdate [plugins...][!]` — update plugins

## Code Style

- Indent with 2 spaces, no tabs.
- Line width: 120 columns.
- Prefer double quotes (`AutoPreferDouble`).
- Use snake_case for modules under `lua/configs/` and `lua/utils/`.
- Name LSP configs after the server.
- Use `require("utils.map_opts")` for every keymap with a description.
- Add LuaCATS annotations where helpful.

## LSP, Formatting, and Linting

### LSP Servers

`mason-lspconfig` installs and enables:
`vtsls`, `tsgo`, `gopls`, `html`, `cssls`, `jsonls`, `lua_ls`, `svelte`, `prismals`, `tailwindcss`, `cssmodules_ls`, `css_variables`.

Active TypeScript server is `vim.g.ts_lsp` (`"vtsls"` default). `:TsLspSwitch`
toggles between `vtsls` and `tsgo` at runtime; only one is enabled at a time.

### Formatting

`conform.nvim` in `lua/configs/conform.lua`:

- Lua: `stylua`
- Go: `goimports` / `gofmt`
- Python: `ruff_format` / `black`
- JS/TS/JSX/TSX/Svelte: Oxc (`oxlint`, `oxfmt`) if Oxc configs exist; otherwise `eslint_d` then `prettierd`
- CSS/SCSS/HTML/YAML/Markdown/JSON/JSONC: `oxfmt` if Oxc formatter config exists;
  otherwise `prettierd` (JSON also tries `jq`)
- Shell: `shfmt`
- Fallback: `trim_whitespace`

`prettierd` runs only when a Prettier config is found. Auto-format on save is
enabled globally unless disabled with `:FormatDisable` / `:FormatDisable!`;
re-enable with `:FormatEnable`.

### Linting

`nvim-lint` in `lua/configs/lint.lua`:

- JS/TS/JSX/TSX/Svelte: `oxlint` if Oxc lint config exists; otherwise `eslint_d`
- Go: `golangci-lint`
- Python: `ruff`
- Markdown: `markdownlint`
- Shell: `shellcheck`

Triggers: `BufWritePost`, `BufReadPost`, `FileType`, `InsertLeave`, `TextChanged`. Files in `node_modules/` are skipped.

## Critical Keymaps

- `<leader>ff` — files, `<leader>fg` — grep, `<leader>fb` — buffers, `<leader>fr` — resume, `<leader>fk` — keymaps (`fzf-lua`)
- `<leader>e` / `<C-n>` — toggle `nvim-tree`
- `<leader>lf` — format buffer, `<leader>la` — code action, `<leader>lT` — switch TS LSP
- `gd`, `gD`, `grr`, `gri`, `grt` — LSP navigation
- `]d` / `[d` — next / previous diagnostic
- `<leader>id` / `<leader>ic` / `<leader>ia` / `<leader>ir` — inline diagnostics toggles
- `<leader>qd` / `<leader>qx` / `<leader>qs` / `<leader>ql` / `<leader>qq` / `<leader>qL` — `trouble.nvim`
- `<leader>x` — close current buffer, `<leader>cx` — close all except current (scope-aware)
- `<C-f>` — floating terminal
- `<leader>ut` — undo tree
- `<leader>ui` — toggle inlay hints (globally)
- DAP: `<leader>dc`, `<leader>db`/`dB`, `<leader>do`/`di`/`dO`, `<leader>dv`, `<leader>dw`
- Insert AI: `<A-g>`, `<A-w>`, `<A-l>`, `<A-j>`/`<A-k>`, `<A-c>` (`windsurf.nvim`)

For the full mapping list see `lua/mappings.lua` and `lua/configs/*.lua`.

## Security Considerations

- `opt.modeline = false` in `lua/options.lua`.
- External providers for Node, Python, Perl, and Ruby are disabled (`g.loaded_*_provider = 0`).
- Plugins are pinned in `nvim-pack-lock.json`.
- Files in `node_modules/` are skipped by the linter.
- Big files (>1.5 MB or average line length >1000) disable LSP, treesitter, and completion.

## Notes for AI Agents

- Add new plugins to the appropriate group in `lua/plugins/groups/`:
  - `shared.lua` — shared libraries, colorscheme, `lazydev.nvim`
  - `core.lua` — treesitter, mason, LSP, completion, formatting, linting
  - `workflow.lua` — navigation, editing, git, terminal, diagnostics, AI, tab-scope buffers, DAP
  - `ui.lua` — statusline, tabline, dashboard, notifications, visuals
  - `extras.lua` — optional utilities
- Create a matching `lua/configs/<plugin>.lua` and require it in the same group file.
- For a new LSP server add `lsp/<server>.lua` and add the server to
  `ensure_installed` in `lua/configs/mason.lua` if Mason manages it.
- When adding JS/TS formatter or linter support, update `lua/utils/oxc_config.lua` if Oxc detection is needed.
- Always use `require("utils.map_opts")` for new keymaps and include a description.
- Reuse helpers in `lua/utils/` instead of duplicating logic.
- If a plugin caches colors from `utils.colors` at setup time, register a `ColorScheme` callback via `utils.theme_highlights`.
- Run `stylua .` before committing Lua changes.
- Test changes inside Neovim; there is no external test runner.
