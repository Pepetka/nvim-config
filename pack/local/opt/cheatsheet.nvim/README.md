# cheatsheet.nvim

Self-contained interactive keymap browser for Neovim >=0.12. Collects global and
source-buffer mappings, applies caller-defined grouping and sorting, and displays
highlighted keys in a floating window. No external plugins or host helpers are required.

## Setup and public API

```lua
vim.cmd.packadd("cheatsheet.nvim")
require("cheatsheet").setup({
  group_rules = {
    { pattern = "^Git:", group = "git", icon = "" },
    { pattern = "^Inline diagnostic:", group = "diagnostics", prefix = "Inline diagnostic:" },
  },
  sort_groups = { "git", "other" },
  exclude = { desc_patterns = { "^Lua function", "^MiniPairs" } },
  layout = { key_gap = 4, mapping_spacing = 1, group_spacing = 2 },
})
```

`setup(opts?)` defines `:Cheatsheet`. Call it before `show(mode?)`, `toggle()`,
`next_mode()` or `prev_mode()`. Repeated setup warns and keeps the original configuration.
Calling an opening operation before setup reports an error without opening a window.
`hide()` is safe before setup and can be repeated.

Defaults include modes n/i/v/o/t, an 80% rounded floating window, q to close, and
Tab/Shift-Tab to cycle modes. `show(mode)` accepts a configured mode; an invalid or
unconfigured mode reports an error and leaves the session unchanged. Closing resets
the selected mode to the first configured mode.

No global opening key is installed by default. `open_mapping` can optionally provide
one. The host owns `<leader>ch`, its group rules and ordering in `lua/configs/cheatsheet.lua`.

## Mapping and configuration behavior

- The source buffer is captured when opening. Mode switching and resize continue to
  use that buffer rather than the cheatsheet's scratch buffer. If the source buffer
  is wiped, collection falls back to global mappings.
- Buffer-local mappings override global mappings with the same key **before** filtering.
  An excluded local mapping does not reveal a shadowed global mapping.
- `group_rules` match trimmed descriptions with Lua patterns. The first matching rule
  wins. Groups not matched by a rule use `default_group` (name `other` by default).
- Without an explicit rule `prefix`, only a colon-terminated first token on a matched description is removed. For example,
  `Git: commit changes` becomes `Commit changes`; ordinary `Rename symbol` stays intact.
  A URL or `Git:commit changes` is not treated as a separate prefix token.
- A rule's `prefix` overrides automatic removal: it is literal text matched once at the
  beginning of the trimmed description, not a Lua pattern. For example,
  `prefix = "Inline diagnostic:"` turns `Inline diagnostic: toggle diagnostics` into
  `Toggle diagnostics`. An empty prefix keeps the complete description. If an explicit
  prefix does not match, the description stays intact without automatic prefix removal.
- `exclude.patterns` match the original lhs; the default list excludes `<Plug>` keys.
  `exclude.desc_patterns` match trimmed original descriptions before display formatting
  or prefix removal; the default list contains `^Lua function`. Both lists contain Lua
  patterns and independently exclude matching mappings. An empty list disables its filter.
  `exclude.groups` matches group names. The no-desc, single-word and newline filters
  are independent: set both `no_desc = false` and `single_word = false` to include
  mappings without descriptions. Their displayed description is empty.
- When `exclude.newline = false`, description line breaks become spaces for safe rendering.
- `icons.enabled = false` hides all icons. A rule or default-group icon overrides
  `icons.default`; an omitted icon uses that fallback and an explicit empty string
  suppresses the icon. For groups with multiple matching rules, the earliest matched
  rule determines their icon, independently of keymap collection order.
- `sort_groups` defines group priorities; unlisted groups sort by name. `sort_keys`
  supports lexical lhs order (`alphanum`) or descriptions (`desc`, then lhs for ties).
- Partial option dictionaries merge with defaults; supplied lists replace default lists,
  including empty lists. Options and defaults are never mutated by normalization.
  Invalid fields warn and use defaults; invalid individual rules or patterns warn and
  are skipped. Modes must be a nonempty list of unique supported modes.

`layout` controls document density. All values are nonnegative integers and accept zero:

| Option | Default | Meaning |
| --- | --- | --- |
| `key_gap` | `4` | Spaces between the padded key column and descriptions |
| `mapping_spacing` | `1` | Blank lines between mappings in a group |
| `group_spacing` | `2` | Blank lines between groups |

Spacing applies only between items; it adds no trailing blank lines after the final item.
Window padding and the blank line below a group header when `group_underline = false`
remain separate. To make mapping rows compact, set `mapping_spacing = 0`.

Defaults and validation live in `lua/cheatsheet/core/config.lua`; LuaCATS option and
internal interface types live in `lua/cheatsheet/types.lua`. Other options cover window
size, padding and title, alignments, separators, and window-local mappings. Width and
height are fractions in `(0, 1]`; padding is nonnegative integers and zindex is a positive
integer. The float is centered with space reserved for its border, with content dimensions
of at least one cell. Border `none` omits the border title. Long content remains horizontally
scrollable with wrapping disabled.

## Session lifecycle

The controller owns one session; `vim.g.cheatsheet_displayed` is only a compatibility
reflection of its visibility. Changing that variable does not control the plugin.

Resize updates the existing window and buffer, preserving mode, cursor, scroll position
and focus. Repeated resize events are coalesced, and unchanged geometry skips redraw.
ColorScheme reapplies the plugin's highlight links.

Normal closure, external window closure and scratch-buffer wipe clean up the owned
resources. Unrelated windows and buffers are ignored, including ones with the same
filetype. Closing a focused cheatsheet returns to the source window if it still exists;
closing from elsewhere preserves the current focus. A failed creation or rendering
attempt cleans up allocated resources and reports an error. If cleanup itself fails,
remaining session resources stay tracked so closure can be retried.

## Architecture

| Module              | Responsibility                                                               |
| ------------------- | ---------------------------------------------------------------------------- |
| `core.config`       | Copying defaults, merging options and producing validation diagnostics       |
| `core.patterns`     | Lua-pattern syntax validation, including suffixes unreachable during a match |
| `core.mappings`     | Precedence, filtering, key/description formatting, grouping and sorting      |
| `core.modes`        | Mode lookup and cycling                                                      |
| `core.layout`       | Geometry, alignment, document lines and explicit highlight spans             |
| `controller`        | Session lifecycle and orchestration through an injected adapter              |
| `integrations.nvim` | Neovim commands, events, keymaps, resources, measurement and extmarks        |
| `init`              | The public API facade                                                        |

Core modules and the controller do not depend on `vim`. Core functions do not retain or
modify caller-owned tables. Layout receives a text-width function: alignment uses screen
cells while highlight spans use zero-based byte offsets with an exclusive end column.
The Neovim adapter applies the document without parsing rendered text again. Internal
module interfaces are implementation details; the public API is `require("cheatsheet")`.

## Tests

Run from this plugin's root. All suites also resolve their module paths when the script
is passed by absolute path.

```sh
luajit tests/core.lua
luajit tests/layout.lua
luajit tests/controller.lua
NVIM_LOG_FILE=/tmp/cheatsheet-nvim.log nvim --clean --headless -i NONE -l tests/nvim.lua
NVIM_LOG_FILE=/tmp/cheatsheet-adapter.log nvim --clean --headless -i NONE -l tests/adapter.lua
NVIM_LOG_FILE=/tmp/cheatsheet-regressions.log nvim --clean --headless -i NONE -l tests/regressions.lua
NVIM_LOG_FILE=/tmp/cheatsheet-types.log nvim --clean --headless -i NONE -l tests/types_check.lua
stylua --check .
```

All production functions, public options, domain structures and adapter callbacks have
LuaCATS contracts. The public API uses partial options; normalization and syntax validation
accept `unknown` at the untrusted-input boundary. Session resource IDs remain optional
because allocation and cleanup can fail independently. Test helpers and the injected
adapter use the same contracts, with separate fixture types. Intentional invalid API
calls in negative tests suppress only the specific diagnostic on that line.

`tests/types_check.lua` checks the entire plugin and its tests with Lua Language Server,
including native Neovim API definitions. It fails on errors and warnings, requires no host
configuration and writes temporary settings and logs outside the plugin. It finds LuaLS
on PATH or in Mason; set `LUA_LS=/path/to/lua-language-server` to override its location.

The three pure suites also run with `nvim --clean --headless -i NONE -l tests/<suite>.lua`;
they remove the `vim` global while executing tests. No dependencies are installed or modified.

- **Core:** option validation, immutable inputs/defaults, pattern syntax, lhs/description filters,
  source precedence, descriptions, icons, stable sorting, leader formatting and modes.
- **Layout:** exact lines and spans, Unicode byte/cell boundaries, alignments, separators,
  configurable spacing (including zero), empty results, empty icons/descriptions and small-window geometry.
- **Controller:** independent instances, setup, source context, mode changes, resize,
  ownership, reentrancy, error handling and cleanup retries using an injected test adapter.
- **Neovim:** public API and actual mapped keys, source-buffer overrides, extmarks,
  ColorScheme, resize/view/focus, external closure, source deletion and queued events.
- **Adapter:** every supported mode and border, default leader, optional opening mapping,
  tiny floats, explicit prefixes, description filters, custom layout through resize,
  setup rollback and injected allocation/rendering/cleanup failures.
- **Regressions:** seven previously failing public-API scenarios, reproduced before refactoring.
