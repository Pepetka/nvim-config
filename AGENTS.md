# Project Overview

This repository is a personal Neovim configuration written in Lua. It is intended to be used as the Neovim configuration directory, typically located at `~/.config/nvim`. The configuration targets modern Neovim (0.10+) and uses the built-in `vim.pack` plugin manager introduced in Neovim 0.11, with a locked plugin manifest stored in `nvim-pack-lock.json`.

The config is built around a curated set of plugins for editing, navigation, LSP, formatting, linting, git integration, fuzzy finding, and AI-assisted completion. It is not a plugin itself and has no traditional build, package, or deployment step. The runtime environment is Neovim; all code is loaded when Neovim starts.

## Technology Stack

- **Language:** Lua (Neovim configuration)
- **Runtime:** Neovim 0.11 or later (uses `vim.pack`)
- **Plugin Manager:** Neovim built-in `vim.pack` via grouped specs in `lua/plugins/groups/`
- **LSP Framework:** Native Neovim LSP (`vim.lsp.config`) + `mason.nvim` + `mason-lspconfig.nvim`
- **Completion Engine:** `blink.cmp`
- **Fuzzy Finder:** `fzf-lua`
- **File Tree:** `nvim-tree.lua`
- **Statusline / Tabline:** `lualine.nvim` / `bufferline.nvim`
- **Dashboard:** `dashboard-nvim`
- **Colorscheme:** `tokyonight.nvim` (transparent)
- **Notifications / Indent Guides / Input / Image Viewer:** `snacks.nvim`
- **Formatter:** `conform.nvim`
- **Linter:** `nvim-lint`
- **Treesitter:** `nvim-treesitter` (custom fold expression)
- **Text Objects:** `mini.ai`
- **AI Completion:** `windsurf.nvim` (active); `minuet-ai.nvim` and `neocodeium` configs are present but disabled
- **Undo Tree:** Built-in `nvim.undotree` (loaded via `packadd`)
- **DAP:** `nvim-dap` + `nvim-dap-view` (JavaScript/TypeScript via `js-debug-adapter`)

## Directory Structure

```
.
├── init.lua                       # Entry point: requires options, mappings, core, plugins
├── nvim-pack-lock.json            # Locked plugin revisions for vim.pack
├── stylua.toml                    # Lua code formatter configuration
├── lsp/                           # Per-server LSP configs loaded by vim.lsp.config
│   ├── css_variables.lua
│   ├── cssls.lua
│   ├── cssmodules_ls.lua
│   ├── gopls.lua
│   ├── html.lua
│   ├── jsonls.lua
│   ├── lua_ls.lua
│   ├── prismals.lua
│   ├── svelte.lua
│   ├── tailwindcss.lua
│   └── vtsls.lua
└── lua/
    ├── options.lua                # vim.opt / vim.g settings
    ├── mappings.lua               # Global keymaps
    ├── core.lua                   # Autocommands and user commands
    ├── cheatsheet/                # Local cheatsheet plugin
    │   ├── init.lua
    │   ├── config.lua
    │   ├── parser.lua
    │   └── render.lua
    ├── plugins/
    │   ├── init.lua               # Loads plugin groups in order
    │   └── groups/                # Grouped plugin specs and their setup requires
    │       ├── shared.lua         # shared dependencies and colorscheme
    │       ├── core.lua           # treesitter, mason, LSP, completion, formatting, linting
    │       ├── ui.lua             # statusline, tabline, dashboard, notifications, visuals
    │       ├── workflow.lua       # navigation, editing, git, terminal, diagnostics, AI, tab-scope buffers, debugging
    │       └── extras.lua         # optional utilities
    ├── configs/                   # Per-plugin setup modules
    │   ├── autotag.lua
    │   ├── better_escape.lua
    │   ├── blink_cmp.lua
    │   ├── bqf.lua
    │   ├── bufferline.lua
    │   ├── cheatsheet.lua
    │   ├── conform.lua
    │   ├── cursorword.lua
    │   ├── dap.lua
    │   ├── dap_view.lua
    │   ├── dashboard.lua
    │   ├── diffview.lua
    │   ├── fzf_lua.lua
    │   ├── gitsigns.lua
    │   ├── highlight_colors.lua
    │   ├── hlslens.lua
    │   ├── import_cost.lua
    │   ├── leap.lua
    │   ├── lint.lua
    │   ├── live_preview.lua
    │   ├── lsp.lua
    │   ├── lualine.lua
    │   ├── mason.lua
    │   ├── mini_ai.lua
    │   ├── minuet.lua
    │   ├── neocodeium.lua
    │   ├── noice.lua
    │   ├── npm_info.lua
    │   ├── pairs.lua
    │   ├── scope.lua
    │   ├── scrollbar.lua
    │   ├── snacks.lua
    │   ├── surround.lua
    │   ├── theme.lua
    │   ├── tiny_inline_diagnostic.lua
    │   ├── todo_comments.lua
    │   ├── toggleterm.lua
    │   ├── translate.lua
    │   ├── tree.lua
    │   ├── treesitter.lua
    │   ├── trouble.lua
    │   ├── ts_comments.lua
    │   ├── undotree.lua
    │   └── windsurf.lua
    └── utils/                     # Shared helper modules
        ├── colors.lua
        ├── dashboard.lua
        ├── map_opts.lua
        ├── merge_tables.lua
        ├── pad.lua
        ├── scope_buffers.lua
        └── theme_highlights.lua
```

## Load Order

`init.lua` loads modules in this order:

1. `options` — vim options and global variables
2. `mappings` — global keymaps
3. `core` — autocommands and custom user commands
4. `plugins` — plugin declarations and per-plugin setup

Inside `lua/plugins/init.lua`, each plugin group under `lua/plugins/groups/` is required in a fixed order: `shared` → `core` → `workflow` → `ui` → `extras`. Each group file calls `vim.pack.add()` for its plugins and then requires the matching `configs.*` modules to apply setup and keymaps.

## Key Configuration Files

- **`init.lua`** — Entry point.
- **`stylua.toml`** — Lua formatter config: 120 column width, 2-space indentation, Unix line endings, AutoPreferDouble quotes.
- **`nvim-pack-lock.json`** — Lockfile pinning exact git revisions for every plugin used by `vim.pack`.
- **`lua/options.lua`** — Core vim options (numbers, tabs, UI, search, clipboard, etc.).
- **`lua/mappings.lua`** — Global leader-key mappings (`<leader>` = space, `<localleader>` = `\`).
- **`lua/core.lua`** — Autocommands (yank highlight, quickfix close, big-file detection, auto-create dirs, auto-reload, window auto-close) and the `:PackClean` / `:PackUpdate` commands.
- **`lua/plugins/init.lua`** — Orchestrates plugin group loading.
- **`lua/plugins/groups/*.lua`** — Grouped plugin specs (shared, core, workflow, ui, extras).
- **`lsp/*.lua`** — LSP server configurations loaded via `vim.lsp.config()` in `lua/configs/lsp.lua`.
- **`lua/cheatsheet/*.lua`** — Local cheatsheet plugin rendered by `configs.cheatsheet`.

## Build and Test Commands

This project has no build step, package manager, or test suite. However, when editing the configuration itself, the following workflows are useful:

- **Format Lua files:** Run `stylua .` from the repository root.
- **Check Lua syntax / types:** Use `lua-language-server` (configured in `lsp/lua_ls.lua`) with globals such as `vim` recognized.
- **Reload configuration after changes:** From inside Neovim, run `:source %` (mapped to `<leader>rs`) or restart Neovim (mapped to `<leader>re`).
- **Clean unused plugins:** Run `:PackClean` (defined in `lua/core.lua`). It removes plugins that are installed but not active in the current `vim.pack` spec.
- **Update plugins:** Run `:PackUpdate` (with optional plugin names or `!` to force).

## Code Style Guidelines

- **Formatter:** `stylua` with the project-level `stylua.toml`.
- **Indentation:** 2 spaces; no tabs (`expandtab`).
- **Line width:** 120 columns.
- **Quotes:** `AutoPreferDouble`; use double quotes unless the string requires them.
- **Comments:** Section headers use Unicode box-drawing comments (`-- ═══════════════════════`). Inline comments are written in English.
- **Naming:** Modules under `lua/configs/` are snake_case. Utility modules under `lua/utils/` are also snake_case. LSP configs are named after the server.
- **Keymap options:** Always use `require("utils.map_opts")` so every keymap gets a description and sensible defaults (`noremap = true`, `silent = true`).
- **Type annotations:** The codebase uses LuaCATS annotations (`---@param`, `---@return`, `---@class`) where helpful.

## LSP, Formatting, and Linting

### LSP Servers

`mason-lspconfig` ensures the following servers are installed and automatically enables them:

- `vtsls` — TypeScript / JavaScript
- `gopls` — Go
- `html` — HTML
- `cssls` — CSS / SCSS / Less
- `jsonls` — JSON / JSONC
- `lua_ls` — Lua
- `svelte` — Svelte
- `prismals` — Prisma
- `tailwindcss` — Tailwind CSS
- `cssmodules_ls` — CSS Modules
- `css_variables` — CSS Variables

Server-specific settings live in `lsp/<server>.lua` and are loaded in `lua/configs/lsp.lua` with `vim.lsp.config(server_name, require("lsp." .. server_name))`. Global capabilities are extended by `blink.cmp`.

### Formatting

`conform.nvim` is configured in `lua/configs/conform.lua`. Formatters by filetype:

- Lua: `stylua`
- Go: `goimports` / `gofmt`
- Python: `ruff_format` / `black`
- JS/TS/JSX/TSX/Svelte: `eslint_d` then `prettierd`
- CSS/SCSS/HTML/YAML/Markdown: `prettierd`
- JSON/JSONC: `jq` / `prettierd`
- Shell (sh/bash/zsh): `shfmt`
- Fallback: `trim_whitespace`

`prettierd` / `prettier` are only run when a Prettier config file is found. Auto-format on save is enabled globally; disable it with `:FormatDisable` (or `:FormatDisable!` for the current buffer) and re-enable with `:FormatEnable`.

### Linting

`nvim-lint` runs `eslint_d` for JS/TS/Svelte, `ruff` for Python, `markdownlint` for Markdown, and `shellcheck` for shell scripts. It triggers on `BufWritePost`, `BufReadPost`, `InsertLeave`, and `TextChanged`.

## Keymaps and Leader Keys

- **Leader:** `<Space>`
- **Local leader:** `\`

Representative global mappings:

- `<leader>ff` — find files (`fzf-lua`)
- `<leader>fg` — live grep (`fzf-lua`)
- `<leader>fb` — buffers (`fzf-lua`)
- `<leader>fh` — help tags (`fzf-lua`)
- `<leader>fr` — resume last picker (`fzf-lua`)
- `<leader>fo` — recent files (`fzf-lua`)
- `<leader>fk` — keymaps (`fzf-lua`)
- `<leader>e` / `<C-n>` — open / toggle `nvim-tree`
- `<leader>lf` — format buffer (`conform`)
- `<leader>la` — code action
- `gd`, `gD`, `grr`, `gri`, `grt` — LSP navigation
- `]d` / `[d` — next / previous diagnostic
- `<leader>id` — toggle inline diagnostics (`tiny-inline-diagnostic`)
- `<leader>ic` — toggle cursor-only inline diagnostics
- `<leader>ia` — toggle all diagnostics on cursor line
- `<leader>ir` — reset inline diagnostic display options
- `<leader>x` — close current buffer (scope-aware)
- `<leader>cx` — close all buffers except current (scope-aware)
- `<C-f>` — toggle floating terminal (`toggleterm`)
- `<leader>ut` — toggle native undo tree (`nvim.undotree`)
- `<leader>nH` — notification history (`snacks.nvim`)
- `<leader>nD` — dismiss all notifications (`snacks.nvim`)
- `<leader>mi` — preview image under cursor (`snacks.nvim`)
- `<leader>mp` / `<leader>mP` — start / close live preview
- `<leader>dc` — continue / start debugging (`nvim-dap`)
- `<leader>db` / `<leader>dB` — toggle / conditional breakpoint (`nvim-dap`)
- `<leader>do` / `<leader>di` / `<leader>dO` — step over / into / out (`nvim-dap`)
- `<leader>dv` — toggle `nvim-dap-view`
- `<leader>dw` — add expression to watches (`nvim-dap-view`)

Insert-mode AI mappings for `windsurf.nvim`:

- `<A-g>` — accept suggestion
- `<A-w>` — accept next word
- `<A-l>` — accept next line
- `<A-j>` / `<A-k>` — cycle suggestions
- `<A-c>` — clear suggestion

Each plugin's buffer-local or global mappings are defined in its `lua/configs/*.lua` module.

## Testing Instructions

There are no automated tests in this repository. To verify changes:

1. Run `stylua --check .` to confirm formatting.
2. Open Neovim and check `:messages` for load errors.
3. Run `:checkhealth` to inspect LSP, treesitter, and plugin health.
4. Trigger the changed feature manually (e.g., open a file of the relevant type and run the mapped command).

## Security Considerations

- `opt.modeline = false` is set in `lua/options.lua` to prevent malicious `vim:` modelines in edited files.
- External providers for Node, Python, Perl, and Ruby are disabled (`g.loaded_*_provider = 0`) to reduce attack surface and improve startup time.
- Plugins are pinned in `nvim-pack-lock.json` and installed via `vim.pack.add()` using the pinned revisions, preventing unexpected upstream changes.
- Linting is skipped for files inside `node_modules/`.
- Big-file detection (>1.5 MB or average line length >1000) disables LSP, treesitter, and completion for performance and safety.

## Notes for AI Agents

- When adding a new plugin, add it to the appropriate group file under `lua/plugins/groups/`:
  - `shared.lua` — shared libraries (plenary, web-devicons, nui, friendly-snippets) and the colorscheme (`tokyonight`).
  - `core.lua` — essential editor tooling (treesitter, mason, LSP, completion, formatting, linting).
  - `workflow.lua` — navigation, editing enhancements (leap, mini.ai, mini.pairs, surround, autotag, ts-comments, better-escape), git, terminal, diagnostics, AI (`windsurf.nvim`; `minuet`/`neocodeium` configs are commented out), tab-scope buffers, and debugging (DAP).
  - `ui.lua` — visual/status UI (statusline, tabline, dashboard, noice, scrollbar, highlight-colors, snacks for notifications/indent/input/image, and the local cheatsheet).
  - `extras.lua` — optional utilities (translate, live preview, npm-info, import-cost, native undotree via `packadd`).
  Then create a matching `lua/configs/<plugin>.lua` module and require it in that same group file.
- For a local plugin like `lua/cheatsheet/`, place the module under `lua/`, add a thin `lua/configs/cheatsheet.lua` loader, and require it from `ui.lua`.
- When adding a new LSP server, add a `lsp/<server>.lua` config file and add the server name to `ensure_installed` in `lua/configs/mason.lua` if it is managed by Mason.
- Use `require("utils.map_opts")` for every new keymap and include a concise description.
- Shared helpers (colors, padding, dashboard utilities, scope buffer helpers, etc.) live under `lua/utils/`; reuse them instead of duplicating logic.
- If a plugin caches colors from `require("utils.colors")` at setup time, register a highlight-refresh callback in `require("utils.theme_highlights")` so the plugin stays in sync with `ColorScheme` events. See `configs/scrollbar.lua`, `configs/cursorword.lua`, and `configs/todo_comments.lua` for examples.
- Run `stylua .` before committing Lua changes.
- This is a live user configuration: test changes inside Neovim rather than relying on external test runners.
