# Neovim Config

A personal, modern Neovim configuration written in Lua.
Built around the native `vim.pack` plugin manager, native LSP, and a curated set of tools for editing, navigation, and debugging.

![dashboard](assets/screenshots/dashboard.png)

> Screenshot: the startup dashboard. Open Neovim on a file or empty buffer to capture this.

## Screenshots

### File tree

![file tree](assets/screenshots/file-tree.png)

> Open the file tree with `<leader>e` or `<C-n>` and capture the sidebar.

### Fuzzy finder

![fzf files](assets/screenshots/fzf-files.png)

> Press `<leader>ff` to open the file picker, then take a screenshot.

### LSP and diagnostics

![lsp diagnostics](assets/screenshots/lsp-diagnostics.png)

> Open a code file, trigger a hover (`K`) or diagnostics (`<leader>qd`), then capture the UI.

### Git integration

![git gitsigns](assets/screenshots/git-gitsigns.png)

> Open a file in a git repo with changes and show gitsigns hunks or a diff.

### Diff view

![diff view](assets/screenshots/diffview.png)

> Open `:DiffviewOpen` or press `<leader>go` in a git repo to see a side-by-side diff.

### Floating terminal

![floating terminal](assets/screenshots/terminal-toggleterm.png)

> Press `<C-f>` to toggle the floating terminal and capture it.

### Debugging (optional)

![dap debugging](assets/screenshots/dap-debugging.png)

> Start a debugging session in a JS/TS file with `<leader>dc` and show `nvim-dap-view`.

### Cheatsheet

![cheatsheet](assets/screenshots/cheatsheet.png)

> Press `<leader>ch` to open the interactive cheatsheet, then take a screenshot.

<details>
<summary>Screenshots (light theme)</summary>

### Dashboard (light)

![dashboard light](assets/screenshots/dashboard-light.png)

> Open Neovim on a file or empty buffer in light mode and capture the startup screen.

### File tree (light)

![file tree light](assets/screenshots/file-tree-light.png)

> Open the file tree with `<leader>e` or `<C-n>` in light mode and capture the sidebar.

### Fuzzy finder (light)

![fzf files light](assets/screenshots/fzf-files-light.png)

> Press `<leader>ff` to open the file picker in light mode, then take a screenshot.

### LSP and diagnostics (light)

![lsp diagnostics light](assets/screenshots/lsp-diagnostics-light.png)

> Open a code file in light mode, trigger a hover (`K`) or diagnostics (`<leader>qd`),
> then capture the UI.

### Git integration (light)

![git gitsigns light](assets/screenshots/git-gitsigns-light.png)

> Open a file in a git repo with changes in light mode and show gitsigns hunks or a diff.

### Diff view (light)

![diff view light](assets/screenshots/diffview-light.png)

> Open `:DiffviewOpen` or press `<leader>go` in a git repo in light mode to see a side-by-side diff.

### Floating terminal (light)

![floating terminal light](assets/screenshots/terminal-toggleterm-light.png)

> Press `<C-f>` to toggle the floating terminal in light mode and capture it.

### Debugging (optional, light)

![dap debugging light](assets/screenshots/dap-debugging-light.png)

> Start a debugging session in a JS/TS file in light mode with `<leader>dc`
> and show `nvim-dap-view`.

### Cheatsheet (light)

![cheatsheet light](assets/screenshots/cheatsheet-light.png)

> Press `<leader>ch` to open the interactive cheatsheet in light mode,
> then take a screenshot.

</details>

## Requirements

- **Neovim** >= 0.12 (tested on 0.12.4)
- **Git** — required by `vim.pack` and Mason
- A **Nerd Font** — for icons in the file tree, statusline, and pickers

This config uses the built-in `vim.pack` plugin manager that are only available in Neovim 0.12 and later.

### Optional CLI tools

These tools are not strictly required to start Neovim, but many features expect them.
Most linters and formatters can also be installed through `:Mason` after first launch.

#### Fuzzy finder and previews

| Tool            | Purpose                              |
| --------------- | ------------------------------------ |
| `fzf`           | Fuzzy matching backend for `fzf-lua` |
| `fd` / `fdfind` | Fast file listing for `fzf-lua`      |
| `rg` (ripgrep)  | Live grep and file search            |
| `bat`           | Syntax-highlighted previews          |
| `delta`         | Pretty git diff previews             |

#### Language servers and runtimes

| Tool          | Purpose                                                         |
| ------------- | --------------------------------------------------------------- |
| `node`, `npm` | JS/TS LSPs, debug adapter, and Mason installs (nvm recommended) |
| `go`          | `gopls` language server                                         |
| `python`      | Python language server support                                  |

#### Linters and formatters (also available via `:Mason`)

| Tool                                 | Purpose                                                           |
| ------------------------------------ | ----------------------------------------------------------------- |
| `ruff`                               | Python formatting and linting                                     |
| `jq`                                 | JSON formatting fallback                                          |
| `shfmt`, `shellcheck`                | Shell formatting and linting                                      |
| `prettier`, `eslint_d`               | JS/TS/CSS formatting and linting fallback                         |
| `oxlint`, `oxfmt`                    | Preferred JS/TS linter and formatter when Oxc configs are present |
| `markdownlint` / `markdownlint-cli2` | Markdown linting                                                  |

#### Debug adapters

| Tool               | Purpose                                               |
| ------------------ | ----------------------------------------------------- |
| `js-debug-adapter` | JS/TS debugging via `nvim-dap` (install via `:Mason`) |

#### Other

| Tool        | Purpose                          |
| ----------- | -------------------------------- |
| ImageMagick | Image previews via `snacks.nvim` |

On macOS with Homebrew, a typical starting set is:

```bash
brew install neovim git fd ripgrep fzf bat delta jq shfmt shellcheck go node imagemagick
```

Python tools and Node-based formatters can usually be installed per-project or via Mason after first launch.

## Full environment setup

This Neovim config is designed to work alongside a matching terminal, multiplexer, and shell setup.
If you want the complete experience — including
Automatic macOS TokyoNight theming across terminal, tmux, zsh, and Neovim — use the
companion [dotfiles][dotfiles-repo] repository.

[dotfiles-repo]: https://github.com/Pepetka/dotfiles

It provides:

- **Zsh** configuration with Oh My Zsh, Powerlevel10k, and custom aliases
- **Tmux** config with TokyoNight theme, popups, and a powerline-style status bar
- **Terminal emulator** configs for Ghostty, Alacritty, and WezTerm
- **Shared theme engine** installed with `theme install`; resolves persistent auto/dark/light policy and publishes dark/light mode under `${XDG_CONFIG_HOME:-~/.config}/theme/mode`

Install it first (or alongside this config) for the best results.

## Installation

1. Back up your existing config if you have one:

   ```bash
   mv ~/.config/nvim ~/.config/nvim.bak
   mv ~/.local/share/nvim ~/.local/share/nvim.bak
   mv ~/.local/state/nvim ~/.local/state/nvim.bak
   ```

2. Clone this repository:

   ```bash
   git clone https://github.com/yourusername/nvim-config.git ~/.config/nvim
   cd ~/.config/nvim
   ```

3. Start Neovim. `vim.pack` will install the plugins automatically on first launch:

   ```bash
   nvim
   ```

4. The language servers listed in `lua/configs/mason.lua` will be auto-installed by `mason-lspconfig` on first launch.
   Treesitter parsers for the configured languages are also auto-installed.
   Linters, formatters, and DAP adapters are not auto-installed — open Mason and install the ones you need manually:

   ```vim
   :Mason
   ```

   Auto-format on save is enabled by default. Toggle it globally with `:FormatDisable` / `:FormatEnable`,
   or per-buffer with `:FormatDisable!` / `:FormatEnable!`.

5. Run `:checkhealth` to verify that external dependencies are detected correctly.

## Supported languages

This config is primarily tuned for web and systems development. The following
languages have LSP, Treesitter, and formatting/linting support out of the box:

| Language            | LSP server                            | Notes                                             |
| ------------------- | ------------------------------------- | ------------------------------------------------- |
| TypeScript / TSX    | `vtsls` or native TypeScript (`tsgo`) | Chosen per project; `:TsLspInfo` shows the choice |
| JavaScript / JSX    | `vtsls` / native TypeScript           | Shared with TypeScript server                     |
| Svelte              | `svelte`                              |                                                   |
| HTML                | `html`                                |                                                   |
| CSS / SCSS / Less   | `cssls` + `tailwindcss`               | CSS Modules and CSS Variables support             |
| JSON / JSONC        | `jsonls`                              |                                                   |
| Go                  | `gopls`                               |                                                   |
| Lua                 | `lua_ls`                              |                                                   |
| Python              | `ruff`                                | Via Mason / system `ruff`                         |
| Prisma              | `prismals`                            |                                                   |
| Shell (sh/bash/zsh) | —                                     | `shfmt` + `shellcheck`                            |
| Markdown            | —                                     | `markdownlint`                                    |
| Rust                | —                                     | Treesitter support                                |
| YAML / TOML / XML   | —                                     | Treesitter support                                |

CSS-in-JS template literals (styled-components / Emotion) use a dedicated `blink.cmp` source with `cssls`,
independently of the TypeScript server. CSS properties and values complete inside `styled`,
`css`, `keyframes`, and `createGlobalStyle` templates, while `${...}` retains TypeScript completion.
Hidden CSS buffers stay in memory; CSS diagnostics are disabled for these generated documents.
`K` shows CSS hover documentation inside templates and regular LSP documentation inside `${...}`.
Object styles rely on the library's TypeScript types.

Svelte projects use `vtsls` for tsserver plugin support. Other projects use the
native server when a local TypeScript 7 compiler (including an npm alias) or `tsgo` is available;
otherwise they use `vtsls`. `:TsLspSwitch` overrides the choice for the current project during this
Neovim session, `:TsLspAuto` restores automatic selection, and `:TsLspInfo` shows the chosen server and command.

Additional Treesitter parsers are installed for syntax highlighting and folding.

Tailwind LSP starts when `tailwindcss` is declared in `dependencies` or `devDependencies`
of an ancestor `package.json`, including a monorepo workspace manifest up to the Git root.
The server automatically discovers v3 configuration files or v4 CSS entrypoints such as
a stylesheet with `@import "tailwindcss"`; no Tailwind or PostCSS config file is required to start the LSP.

## Key features

- **Plugin management** with Neovim's built-in `vim.pack` and a lockfile
- **Native LSP** configured via `vim.lsp.config`, with Mason for server installation
- **Completion** powered by `blink.cmp`
- **Fuzzy finding** with `fzf-lua` for files, grep, git, buffers, and more
- **Formatting and linting** via `conform.nvim` and `nvim-lint`, with automatic Oxc detection
- **Git integration** with `gitsigns.nvim` and `diffview-plus.nvim`
- **Debugging** for JS/TS using `nvim-dap` and `nvim-dap-view`
- **Transparent TokyoNight** theme following the shared engine's effective mode, preserving foregrounds and highlight styles
- **Minimal, fast UI** with `lualine`, the local tab-buffers panel, local `dashboard.nvim`, and `snacks.nvim`
- **Custom fold expression** based on Treesitter
- **Scope-aware buffers** with `scope.nvim` so buffer lists stay per tab
- **Image previews** under the cursor via `snacks.nvim`
- **Live preview** for Markdown and web files
- **AI code completion** with `windsurf.nvim`
- **Interactive cheatsheet** (`<leader>ch`) to browse every keymap grouped by mode
- **Fast motion** with `leap.nvim` (press `s` + two characters)
- **Seamless tmux navigation** with `vim-tmux-navigator`
- **Rich editing helpers**: `mini.ai`, `mini.pairs`, `nvim-surround`, `ts-comments.nvim`, `better-escape.nvim`
- **Inline diagnostics** with `tiny-inline-diagnostic.nvim`
- **TODO/FIXME highlighting** with `todo-comments.nvim`
- **Polished message UI** with `noice.nvim`
- **File tree on the right** with `nvim-tree` (`netrw` is disabled)
- **Live theme switching** via the shared engine, with directory watching and a one-second fallback
- **Better Escape** — `jk`, `kj`, `jj` act as Escape in insert/visual modes

## Local plugins

Locally developed plugins live under [`pack/local/opt/`](pack/local/opt/). Each plugin folder contains
its own Lua modules, helper sources, tests and documentation, and can become a separate repository.
The appropriate plugin group loads it with `vim.cmd.packadd("<name>")` before its `lua/configs/` setup.

[`package-info.nvim`](pack/local/opt/package-info.nvim/README.md) checks saved `package.json` files using
npm, Yarn or pnpm settings. Installed versions appear immediately; registry results arrive incrementally
and are cached between Neovim sessions. Its setup is in [`lua/configs/package_info.lua`](lua/configs/package_info.lua).

Commands: `:PackageInfo`, `:PackageInfoRefresh[!]`, `:PackageInfoToggle`, `:PackageInfoStatus`.
See the [plugin README](pack/local/opt/package-info.nvim/README.md) for behavior, requirements and test commands.

[`tab-buffers.nvim`](pack/local/opt/tab-buffers.nvim/README.md) manages tab-local buffer ownership,
order and safe closure. Its optional native tabline shows buffers on the left and tab numbers on the right,
with a Diffview indicator. Left click opens, middle click safely closes; layout and theme update automatically.
Panel settings live in [`lua/configs/tabline.lua`](lua/configs/tabline.lua).

[`css-in-js.nvim`](pack/local/opt/css-in-js.nvim/README.md) provides CSS template completion and hover,
including template extraction, LSP edit mapping and supplemental injection queries.
[`stable-folds.nvim`](pack/local/opt/stable-folds.nvim/README.md) computes synchronous Tree-sitter folds
and preserves closed fold state across edits.
[`cheatsheet.nvim`](pack/local/opt/cheatsheet.nvim/README.md) implements the interactive keymap browser.
[`dashboard.nvim`](pack/local/opt/dashboard.nvim/README.md) implements the startup screen with typed text,
action and custom blocks. It owns layout, theme updates and restoration of editor panels;
personal seasonal content, actions and colors remain in `lua/configs/dashboard.lua`.
Personal setup remains in `lua/configs/css_in_js.lua`, `stable_folds.lua` and `cheatsheet.lua`.
Each plugin has headless Neovim tests described in its README.

## Key bindings

Leader is `<Space>`, local leader is `\`.

| Binding                         | Action                                     |
| ------------------------------- | ------------------------------------------ |
| `<leader>ff`                    | Find files                                 |
| `<leader>fg`                    | Live grep                                  |
| `<leader>fb`                    | Buffers                                    |
| `<leader>fr`                    | Resume last picker                         |
| `<leader>fk`                    | Keymaps                                    |
| `<leader>ch`                    | Toggle interactive cheatsheet              |
| `s` + two characters            | Leap to target                             |
| `<leader>e` / `<C-n>`           | Open / toggle file tree                    |
| `<leader>go`                    | Open diffview                              |
| `<leader>lf`                    | Format buffer                              |
| `<leader>lF`                    | Show formatting status                     |
| `<leader>la`                    | Code action                                |
| `<leader>lT`                    | Switch TypeScript LSP for current project  |
| `<leader>lA` / `<leader>lI`     | Restore automatic TS LSP / show its status |
| `gd`, `gD`, `grr`, `gri`, `grt` | LSP navigation                             |
| `]d`, `[d`                      | Next / previous diagnostic                 |
| `<leader>id`                    | Toggle inline diagnostics                  |
| `<leader>qd`                    | Buffer diagnostics (Trouble)               |
| `<leader>qx`                    | Workspace diagnostics (Trouble)            |
| `<leader>x`                     | Close current buffer                       |
| `<leader>cx`                    | Close all buffers except current           |
| `<C-f>`                         | Toggle floating terminal                   |
| `<leader>ut`                    | Toggle undo tree                           |
| `<leader>ui`                    | Toggle inlay hints                         |
| `<leader>uc`                    | Toggle markup / JSON quote conceal globally |
| `<leader>nH`                    | Notification history                       |
| `<leader>nh`                    | Message history (Noice)                    |
| `<leader>dc`                    | Start / continue debugging                 |
| `<leader>db`                    | Toggle breakpoint                          |
| `<leader>dv`                    | Toggle debug view                          |
| `<leader>dt`                    | Terminate debugging                        |
| `<leader>dr`                    | Toggle debug REPL                          |
| `<leader>ld`                    | Floating diagnostic for current line       |
| `]h`, `[h`                      | Next / previous git hunk                   |
| `<leader>hp`                    | Preview git hunk                           |
| `<leader>hb`                    | Blame line                                 |
| `<leader>fh`                    | Help tags                                  |
| `<leader>fo`                    | Recent files                               |
| `<leader>qf`                    | Find TODOs                                 |
| `<leader>qt`                    | Open TODOs in Trouble                      |
| `<leader>ic`                    | Toggle cursor diagnostic                   |
| `<leader>mp`                    | Start live preview                         |
| `<leader>mi`                    | Hover image under cursor                   |

For the full list, see `lua/mappings.lua` and `lua/configs/*.lua`.

## Post-install checklist

- [ ] Install a Nerd Font and use it in your terminal.
- [ ] Install `rg`, `fd`, `bat`, and `fzf` for the best `fzf-lua` experience.
- [ ] Open `:Mason` and install the linters and formatters you need (`prettierd`, `eslint_d`, `stylua`, `shfmt`, etc.).
- [ ] If you plan to debug JS/TS, install `js-debug-adapter` via `:Mason`.
- [ ] Verify that the lsp and treesitter parsers were installed automatically (run `:LspInfo` and `:checkhealth nvim-treesitter`).
- [ ] On macOS run `theme install` from the matching dotfiles; use `theme auto`, `theme dark` or `theme light`. Authorize the Ghostty helper once with `theme authorize` for live terminal reload.
- [ ] Run `:checkhealth` and fix any missing optional dependencies.
- [ ] If you use AI completion, authenticate Codeium so `windsurf.nvim` can read `~/.codeium/config.json`.
- [ ] Press `<leader>ch` to open the cheatsheet and explore keymaps by mode.

## Updating

Update plugins with:

```vim
:PackUpdate
```

Remove unused plugins with:

```vim
:PackClean
```

Format Lua files before committing:

```bash
stylua .
```

## License

This repository is distributed under the MIT License. See the [LICENSE](LICENSE) file for details.

## System theme verification

The dotfiles theme engine resolves `auto/dark/light` policy and publishes the effective mode as `dark` or `light` under
`${XDG_CONFIG_HOME:-~/.config}/theme/mode`. Missing/invalid state preserves the current background; startup
falls back to native terminal detection. Neovim reloads TokyoNight once per actual background transition.
Its terminal buffers inherit the host ANSI palette (`terminal_colors = false`), and fzf uses base ANSI colors
so an already-open picker follows the terminal without losing its query or selection. File previews use
Neovim highlights; native bat/diff previews use ANSI colors. Arbitrary old RGB terminal output remains unchanged.
Files and Git files use muted ANSI directories, the default filename foreground and icons mapped to the six
base terminal hues. Their colors follow the terminal palette even while the picker is open.
LSP symbol labels inherit the terminal foreground. Diagnostics pass through `scripts/fzf-plain`, which removes
serialized color escapes while preserving messages, severity signs, sources and error codes. The wrapper uses
the installed `fzf` and standard `awk`; the provider's callback strings bypass its usual `fn_transform` hook.

TokyoNight publishes one active palette snapshot through `utils.colors`. Personal plugin definitions register
with `utils.theme_highlights` and are merged before native plugin color handlers run. Derived UI updates run
once afterwards: color markers in listed/unlisted buffers are restored, and lualine uses dynamic colors without
rebuilding its host configuration or Git cache. Local plugins retain their own color handlers; dashboard receives
semantic styles through its palette callback and independently keeps its editor panels hidden.

The dashboard renders its footer without collecting Git branches/tags for every plugin, so its first visible
frame already has centered content and custom highlights. The footer's time measures configuration loading.
Its footer callback keeps its closure in memory and supports reopening `:Dashboard` after leaving the initial screen.
Layout snapshots and seasonal content are checked with `tests/dashboard.lua`; custom blocks use the same
document contract as built-in text and menus. Palette updates never invoke content providers.

Run the focused theme regression suite with installed plugins:

```sh
NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -n -l tests/dashboard.lua
NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -n -l tests/dashboard_types.lua
NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -n -l tests/theme.lua
NVIM_LOG_FILE=/dev/null nvim --headless -u ./init.lua -i NONE -n -c 'lua dofile("tests/theme_ui.lua")'
NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -n -l tests/theme_startup.lua
```

The startup suite attaches a real RPC UI in both modes and checks the first frame, automatic theme transitions,
resize and reopening. It publishes temporary mode files; it does not change macOS Appearance. The full config
tests need permission to create local sockets for fzf. Restart existing Neovim sessions once after updating
the theme modules so cached Lua modules are replaced.

For a visual check, open fzf and ToggleTerm alongside the tree/statusline in both Ghostty and Alacritty,
directly and through tmux, then switch macOS Appearance without interacting with those windows. Repeat
after sleep and with multiple Neovim instances. Also check `theme dark`, `theme light` and return to `theme auto`.
`theme status` reports the selected policy, effective mode and application adapter state.
