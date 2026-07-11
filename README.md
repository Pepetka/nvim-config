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

| Tool | Purpose |
|------|---------|
| `fzf` | Fuzzy matching backend for `fzf-lua` |
| `fd` / `fdfind` | Fast file listing for `fzf-lua` |
| `rg` (ripgrep) | Live grep and file search |
| `bat` | Syntax-highlighted previews |
| `delta` | Pretty git diff previews |

#### Language servers and runtimes

| Tool | Purpose |
|------|---------|
| `node`, `npm` | JS/TS LSPs, debug adapter, and Mason installs (nvm recommended) |
| `go` | `gopls` language server |
| `python` | Python language server support |

#### Language server plugins

| Tool | Purpose |
|------|---------|
| `@styled/typescript-styled-plugin` | CSS-in-JS support for styled-components / Emotion in `vtsls` (`npm install -g`) |

#### Linters and formatters (also available via `:Mason`)

| Tool | Purpose |
|------|---------|
| `ruff` | Python formatting and linting |
| `jq` | JSON formatting fallback |
| `shfmt`, `shellcheck` | Shell formatting and linting |
| `prettier`, `eslint_d` | JS/TS/CSS formatting and linting fallback |
| `oxlint`, `oxfmt` | Preferred JS/TS linter and formatter when Oxc configs are present |
| `markdownlint` / `markdownlint-cli2` | Markdown linting |

#### Debug adapters

| Tool | Purpose |
|------|---------|
| `js-debug-adapter` | JS/TS debugging via `nvim-dap` (install via `:Mason`) |

#### Other

| Tool | Purpose |
|------|---------|
| ImageMagick | Image previews via `snacks.nvim` |

On macOS with Homebrew, a typical starting set is:

```bash
brew install neovim git fd ripgrep fzf bat delta jq shfmt shellcheck go node imagemagick
```

Python tools and Node-based formatters can usually be installed per-project or via Mason after first launch.

## Full environment setup

This Neovim config is designed to work alongside a matching terminal, multiplexer, and shell setup.
If you want the complete experience — including
TokyoNight theme switching across terminal, tmux, zsh, and Neovim — use the
companion [dotfiles][dotfiles-repo] repository.

[dotfiles-repo]: https://github.com/Pepetka/dotfiles

It provides:

- **Zsh** configuration with Oh My Zsh, Powerlevel10k, and custom aliases
- **Tmux** config with TokyoNight theme, popups, and a powerline-style status bar
- **Terminal emulator** configs for Ghostty, Alacritty, and WezTerm
- **Unified `theme` command** that switches dark/light mode across tmux, terminal, and Neovim via `~/.config/theme/mode`

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

| Language | LSP server | Notes |
|----------|------------|-------|
| TypeScript / TSX | `vtsls` or `tsgo` | Switch with `:TsLspSwitch` |
| JavaScript / JSX | `vtsls` / `tsgo` | Shared with TypeScript server |
| Svelte | `svelte` | |
| HTML | `html` | |
| CSS / SCSS / Less | `cssls` + `tailwindcss` | CSS Modules and CSS Variables support |
| JSON / JSONC | `jsonls` | |
| Go | `gopls` | |
| Lua | `lua_ls` | |
| Python | `ruff` | Via Mason / system `ruff` |
| Prisma | `prismals` | |
| Shell (sh/bash/zsh) | — | `shfmt` + `shellcheck` |
| Markdown | — | `markdownlint` |
| Rust | — | Treesitter support |
| YAML / TOML / XML | — | Treesitter support |

For CSS-in-JS support (styled-components, Emotion) with `vtsls`, install the TypeScript plugin globally:

```bash
npm install -g @styled/typescript-styled-plugin
```

`tsgo` does not support tsserver plugins (for example styled-components or Svelte), so switch back to `vtsls`
when you need those features.

Additional Treesitter parsers are installed for syntax highlighting and folding.

## Key features

- **Plugin management** with Neovim's built-in `vim.pack` and a lockfile
- **Native LSP** configured via `vim.lsp.config`, with Mason for server installation
- **Completion** powered by `blink.cmp`
- **Fuzzy finding** with `fzf-lua` for files, grep, git, buffers, and more
- **Formatting and linting** via `conform.nvim` and `nvim-lint`, with automatic Oxc detection
- **Git integration** with `gitsigns.nvim` and `diffview-plus.nvim`
- **Debugging** for JS/TS using `nvim-dap` and `nvim-dap-view`
- **Transparent TokyoNight** theme with external light/dark mode switching
- **Minimal, fast UI** with `lualine`, `bufferline`, `dashboard-nvim`, and `snacks.nvim`
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
- **Live theme switching** via `~/.config/theme/mode`
- **Better Escape** — `jk`, `kj`, `jj` act as Escape in insert/visual modes

## Key bindings

Leader is `<Space>`, local leader is `\`.

| Binding | Action |
|----------|----------|
| `<leader>ff` | Find files |
| `<leader>fg` | Live grep |
| `<leader>fb` | Buffers |
| `<leader>fr` | Resume last picker |
| `<leader>fk` | Keymaps |
| `<leader>ch` | Toggle interactive cheatsheet |
| `s` + two characters | Leap to target |
| `<leader>e`, `<C-n>` | Toggle file tree |
| `<leader>go` | Open diffview |
| `<leader>lf` | Format buffer |
| `<leader>la` | Code action |
| `<leader>lT` | Switch TypeScript LSP (`vtsls` / `tsgo`) |
| `gd`, `gD`, `grr`, `gri`, `grt` | LSP navigation |
| `]d`, `[d` | Next / previous diagnostic |
| `<leader>id` | Toggle inline diagnostics |
| `<leader>qd` | Buffer diagnostics (Trouble) |
| `<leader>qx` | Workspace diagnostics (Trouble) |
| `<leader>x` | Close current buffer |
| `<leader>cx` | Close all buffers except current |
| `<C-f>` | Toggle floating terminal |
| `<leader>ut` | Toggle undo tree |
| `<leader>nH` | Notification history |
| `<leader>nh` | Message history (Noice) |
| `<leader>dc` | Start / continue debugging |
| `<leader>db` | Toggle breakpoint |
| `<leader>dv` | Toggle debug view |
| `<leader>dt` | Terminate debugging |
| `<leader>dr` | Toggle debug REPL |
| `<leader>ld` | Floating diagnostic for current line |
| `]h`, `[h` | Next / previous git hunk |
| `<leader>hp` | Preview git hunk |
| `<leader>hb` | Blame line |
| `<leader>fh` | Help tags |
| `<leader>fo` | Recent files |
| `<leader>qf` | Find TODOs |
| `<leader>qt` | Open TODOs in Trouble |
| `<leader>ic` | Toggle cursor diagnostic |
| `<leader>mp` | Start live preview |
| `<leader>mi` | Hover image under cursor |

For the full list, see `lua/mappings.lua` and `lua/configs/*.lua`.

## Post-install checklist

- [ ] Install a Nerd Font and use it in your terminal.
- [ ] Install `rg`, `fd`, `bat`, and `fzf` for the best `fzf-lua` experience.
- [ ] Open `:Mason` and install the linters and formatters you need (`prettierd`, `eslint_d`, `stylua`, `shfmt`, etc.).
- [ ] If you plan to debug JS/TS, install `js-debug-adapter` via `:Mason`.
- [ ] Verify that the lsp and treesitter parsers were installed automatically (run `:LspInfo` and `:checkhealth nvim-treesitter`).
- [ ] Optionally create `~/.config/theme/mode` containing `light` or `dark` to switch the theme from outside Neovim.
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
