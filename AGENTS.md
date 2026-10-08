# Project Overview

Personal Neovim configuration (Lua, Neovim 0.12+, `vim.pack`). Targets the live config directory at `~/.config/nvim`.

## Technology Stack

- **Plugin manager:** `vim.pack` with lockfile `nvim-pack-lock.json`
- **LSP:** native `vim.lsp.config` + `mason.nvim` + `mason-lspconfig.nvim`
- **Completion:** `blink.cmp` (sources: `lazydev`, `lsp`, `css_in_js`, `path`, `snippets`, `buffer`)
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
- `lua/options.lua` — `vim.opt` / `vim.g`
- `lua/mappings.lua` — global leader maps (`<leader>` = space, `<localleader>` = `\`)
- `lua/core.lua` — autocommands and user commands
  (`:PackClean`, `:PackUpdate`, `:LspRestart`, `:LspStop`, `:LspStart`, `:TsLspSwitch`, `:TsLspAuto`, `:TsLspInfo`)
- `lua/plugins/groups/*.lua` — plugin specs
- `lua/configs/*.lua` — per-plugin setup
- `lsp/*.lua` — server configs loaded by `vim.lsp.config` in `lua/configs/lsp.lua`
- `lua/utils/oxc_config.lua` — Oxc formatter/linter config detection
- `pack/local/opt/` — self-contained local plugins, loaded with native `packadd`
- `pack/local/opt/package-info.nvim/` — package.json dependency information, Node helper and tests
- `lua/configs/package_info.lua` — package-info setup
- `pack/local/opt/tab-buffers.nvim/` — tab-local buffer ownership, safe closure, bufferline/fzf/Diffview integrations and tests
- `lua/configs/tab_buffers.lua` — tab-buffers setup and buffer mappings
- `pack/local/opt/css-in-js.nvim/` — CSS template completion/hover, extraction, injection queries and tests
- `lua/configs/css_in_js.lua` — CSS-in-JS filter and styled parser revision
- `pack/local/opt/stable-folds.nvim/` — synchronous fold boundaries, stable closed state and tests
- `lua/configs/stable_folds.lua` — folding setup and personal fold options
- `pack/local/opt/cheatsheet.nvim/` — interactive keymap browser and tests
- `lua/configs/cheatsheet.lua` — personal keymap groups and opening mapping
- `nvim-pack-lock.json` — pinned plugin revisions
- `stylua.toml` — formatter config (120 cols, 2 spaces, Unix endings, AutoPreferDouble)

## Build and Test Commands

No build step. Package-info has focused Node and headless Neovim tests
(see `pack/local/opt/package-info.nvim/README.md`). When editing the config:

- `stylua --check .` — verify formatting
- `stylua .` — apply formatting
- `:source %` (`<leader>rs`) — reload current file
- `:restart` (`<leader>re`) — restart Neovim
- `:TsLspSwitch` (`<leader>lT`) — override the TS server for the current project; `:TsLspAuto` (`<leader>lA`) restores automatic selection
- `:PackClean` — remove unused `vim.pack` plugins
- `:PackUpdate [plugins...][!]` — update plugins
- `:PackageInfo`, `:PackageInfoRefresh[!]`, `:PackageInfoToggle`, `:PackageInfoStatus` — dependency information

Package-info requires Node >=22.18 and npm to bootstrap its isolated helper under `stdpath("data")/package-info`.
It uses the project's npm, Yarn 1–4, or pnpm >=7 without installing a manager or modifying project dependencies.
Registry checks share a persistent Node helper with native manager configuration, parallel HTTP requests,
and a private metadata cache; custom Yarn network hooks use the manager CLI for compatibility.

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

`mason-lspconfig` installs:
`vtsls`, `tsc` (native TypeScript binary), `gopls`, `html`, `cssls`, `jsonls`, `yamlls`, `lua_ls`, `svelte`, `prismals`, `tailwindcss`, `cssmodules_ls`, `css_variables`.

`lua/utils/ts_lsp.lua` selects `vtsls` or the native server (`tsgo` config) per project.
These TS configs are enabled by the config; Mason enables the other installed servers.
Svelte projects use `vtsls` for tsserver plugin support;
projects with local TypeScript 7 (including npm aliases) or `tsgo` use the native server when available.
`:TsLspSwitch` overrides one project for the session; `:TsLspAuto` restores automatic selection and
`:TsLspInfo` shows the current choice.

Tailwind LSP starts when an ancestor `package.json` declares `tailwindcss` in
`dependencies` or `devDependencies`; the search stops at the Git root and supports workspace-level dependencies.
The server detects v3 configs and v4 CSS entrypoints itself.

CSS-in-JS template completion uses the local `css-in-js.nvim` Blink source (`css_in_js`) with `cssls`,
independently of the TS server. Its `css_in_js.regions` module extracts the active template, masks
`${...}`, and maps completion edits back to the host document. Hidden buffers remain in memory.
`K` routes CSS hover requests through the same source; outside CSS it uses regular LSP hover.

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
re-enable globally with `:FormatEnable` or for one buffer with `:FormatEnable!`.

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
- `<leader>e` / `<C-n>` — open / toggle `nvim-tree`
- `<leader>lf` — format buffer, `<leader>lF` — formatting status, `<leader>la` — code action
- `<leader>lT` / `<leader>lA` / `<leader>lI` — override / restore / inspect project TS LSP
- `gd`, `gD`, `grr`, `gri`, `grt` — LSP navigation
- `]d` / `[d` — next / previous diagnostic
- `<leader>id` / `<leader>ic` / `<leader>ia` / `<leader>ir` — inline diagnostics toggles
- `<leader>qd` / `<leader>qx` / `<leader>qs` / `<leader>ql` / `<leader>qq` / `<leader>qL` — `trouble.nvim`
- `<Tab>` / `<S-Tab>` — next / previous buffer in the current tab
- `<leader>x` — close current buffer, `<leader>cx` — close all except current in the tab
- `<leader>bh` / `<leader>bl` — move current buffer left / right within the tab
- `<C-f>` — floating terminal
- `<leader>ut` — undo tree
- `<leader>ui` — toggle inlay hints (globally)
- `<leader>uc` — toggle markup and JSON quote conceal globally in regular windows
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

- Keep local plugins self-contained under `pack/local/opt/<plugin-name>/`, with their own Lua namespace,
  helper sources, tests and README. Load them with `vim.cmd.packadd()` in the appropriate group.
  Keep personal setup in `lua/configs/`; local plugins must not require modules from the host config.

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
- Host plugin configs that cache colors from `utils.colors` should register a `ColorScheme` callback via
  `utils.theme_highlights`. Self-contained local plugins should handle `ColorScheme` with their own autocommand.
- Run `stylua .` before committing Lua changes.
- Test changes inside Neovim. For package-info, also run the Node built-in tests described in its plugin README.
- For CSS-in-JS, stable-folds and cheatsheet, run the headless tests described in each local plugin README.
  CSS-in-JS owns the supplemental injection queries; the host config owns the styled parser pin.
  Stable-folds owns the fold expression and refresh handlers; personal fold options stay in its host config.
- For tab-buffers, run the core, Neovim adapter, UI and Diffview integration tests described in its README.
  Diffview tabs are excluded reviews; `gf` opens the local file in an ordinary tab and `<C-w>gf` creates one.
  Use its public API for tab-local navigation, sorting and closure; native buffer commands still use the global list.
  Bufferline Move/Sort/TogglePin commands are disabled. Membership is session-local.
