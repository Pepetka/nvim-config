# cheatsheet.nvim

Local interactive keymap browser for Neovim >=0.12. Collects global and current-buffer
mappings, applies caller-defined grouping and sorting, and displays them in a floating
window with highlighted keys and mode switching. No external plugins or host helpers
are required.

## Setup

```lua
vim.cmd.packadd("cheatsheet.nvim")
require("cheatsheet").setup({
  group_rules = { { pattern = "^Git:", group = "git", icon = "" } },
  sort_groups = { "git", "other" },
})
```

Setup defines `:Cheatsheet`. The public API is `show(mode?)`, `hide()`, `toggle()`,
`next_mode()` and `prev_mode()`. Defaults include modes n/i/v/o/t, a rounded floating
window, q to close, and Tab/Shift-Tab to switch displayed modes. Buffer-local mappings
take precedence over global mappings with the same key. Descriptions with prefixes
can be grouped using Lua patterns; the displayed description omits its first word.

All configuration options and types live in `lua/cheatsheet/config.lua`: window size,
padding and title, modes, grouping rules, exclusion filters, icons, group/key sorting,
alignment, separators and window mappings. No global opening key is installed by default;
`open_mapping` can optionally provide one. The host owns `<leader>ch` and its personal
group rules and ordering in `lua/configs/cheatsheet.lua`.

Setup initializes once; subsequent calls warn and keep the existing setup. ColorScheme
reapplies the plugin's own highlights. Resize recreates the open window. Its scratch
buffer is wiped when the window closes, including external closure.

## Tests

```sh
NVIM_LOG_FILE=/tmp/cheatsheet-nvim.log nvim --clean --headless -i NONE -l tests/nvim.lua
stylua --check .
```

Run from this plugin's root or pass an absolute script path. The suite runs independently
of the host config and checks keymap precedence, grouping/formatting, command registration,
rendering/highlights, mode switching, ColorScheme, resize, normal and external closure,
scratch-buffer disposal and reopening. No dependencies are installed or modified.
