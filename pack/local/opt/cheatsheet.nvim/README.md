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
  include = { patterns = { "^[%[%]][qQ]$" } },
  layout = { key_gap = 4, mapping_spacing = 1, group_spacing = 2 },
})
```

`setup(opts?)` defines `:Cheatsheet [mode]`: without an argument it toggles the browser,
with a configured mode (completed on the command line) it shows that mode. Call setup before
`show(mode?)`, `toggle()`, `next_mode()` or `prev_mode()`. Repeated setup closes an open
browser and replaces the configuration, commands, autocommands and opening key, so re-sourcing
the host configuration applies changes. If installation fails, the previous registrations are
removed and the plugin stays uninitialized until a later setup succeeds. Calling an opening
operation before setup reports an error without opening a window. `hide()` is safe before
setup and can be repeated. `is_open()` reports whether the browser window exists.

Defaults include modes n/i/v/o/t, an 80% rounded floating window, q and Esc to close, and
Tab/Shift-Tab to cycle modes. The mode line shows full names (`[normal]  insert  ...`).
`show(mode)` accepts a configured mode; an invalid or unconfigured mode reports an error
and leaves the session unchanged. Closing resets the selected mode to the first configured mode.

No global opening key is installed by default. `open_mapping` can optionally provide
one. The host owns `<leader>ch`, its group rules and ordering in `lua/configs/cheatsheet.lua`.

## Mapping and configuration behavior

- The source buffer is captured when opening. Mode switching and resize continue to
  use that buffer rather than the cheatsheet's scratch buffer. If the source buffer
  is wiped, collection falls back to global mappings.
- Buffer-local mappings override global mappings with the same key **before** filtering.
  An excluded local mapping does not reveal a shadowed global mapping.
- Mappings are matched by their raw keymap mode. The visual tab includes `:map`, `:vmap`
  and `:xmap` entries but not select-only `:smap` entries, which neither appear there nor
  shadow visual mappings with the same key.
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
- `include.patterns` match the original lhs and always display matching mappings, bypassing
  the description and key filters below; `exclude.groups` still applies. Use it for useful
  mappings with terse descriptions, such as the native `]q` (`:cnext`).
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
  supports lhs order (`alphanum`) or descriptions (`desc`, then lhs for ties). Both compare
  case-insensitively and place lowercase first (`gb`, `gc`, `gC`).
- The leader prefix is displayed as `<leader> + `; remaining literal spaces become `<Space>`.
- Partial option dictionaries merge with defaults; supplied lists replace default lists,
  including empty lists. Options and defaults are never mutated by normalization.
  Invalid fields warn and use defaults; invalid individual rules or patterns warn and
  are skipped. Unknown options and rule fields warn and are ignored. Modes must be a
  nonempty list of unique supported modes.

`layout` controls document density and columns. Gap and spacing values are nonnegative
integers and accept zero; `max_columns` and `max_column_width` are positive integers:

| Option | Default | Meaning |
| --- | --- | --- |
| `key_gap` | `4` | Spaces between the padded key column and descriptions |
| `mapping_spacing` | `1` | Blank lines between mappings in a group |
| `group_spacing` | `2` | Blank lines between groups in a column |
| `max_columns` | `4` | Upper limit for the number of columns; `1` keeps a single column |
| `column_gap` | `4` | Spaces between columns |
| `max_column_width` | `60` | Preferred maximum column width used to choose the column count |

Spacing applies only between items; it adds no trailing blank lines after the final item.
Window padding and the blank line below a group header when `group_underline = false`
remain separate. To make mapping rows compact, set `mapping_spacing = 0`.

### Columns

The mode line spans the whole window; groups below it are laid out in newspaper order:
top to bottom, then into the next column, preserving `sort_groups`. Groups are never split.

- The preferred width is the widest unwrapped line measured with each group's own key width,
  capped by `max_column_width`, but never narrower than the widest group header or a group's
  key column plus one description cell.
- The column count is how many preferred widths with `column_gap` fit the content width,
  limited by `max_columns` and the number of groups. Columns get equal widths; the remainder
  of the division (fewer cells than columns) stays unused on the right.
- Group boundaries minimize the tallest column; ties keep earlier columns fuller.
- Each column aligns keys to its own widest key. With two or more columns, descriptions
  wider than the column wrap onto continuation lines indented under the description column.
- With two or more columns every line fits its column: separators are repeated by cells
  (also for a double-width `─`), and any remaining overflow, such as a wide character in a
  one-cell description, is clipped instead of shifting the next column.
- A single column renders exactly as before: no wrapping and horizontal scrolling for long lines.
- Columns are not padded after the last nonempty segment of a row; text inside a segment, such
  as a padded key with an empty description, is kept as is.
- A resize recomputes columns in the same window. The view is kept while the column count is
  unchanged; when it changes, the cursor and view return to the top.
- Wrapped descriptions are cached per mapping and width, so balancing and rendering share them.

Defaults and validation live in `lua/cheatsheet/core/config.lua`; LuaCATS option and
internal interface types live in `lua/cheatsheet/types.lua`. Other options cover window
size, padding and title, alignments, separators, and window-local mappings. Width and
height are fractions in `(0, 1]`; padding is nonnegative integers and zindex is a positive
integer. The float is centered with space reserved for its border, with content dimensions
of at least one cell. Border `none` omits the border title. Long single-column content remains
horizontally scrollable with window wrapping disabled.

## Session lifecycle

The controller owns one session. Floating windows belong to a tab page: opening or toggling
the browser from another tab page closes the hidden window and opens it on the current one,
keeping the selected mode.

Resize updates the existing window and buffer, preserving mode and focus; cursor and scroll
position are preserved unless the column count changes. Repeated resize events are coalesced, and unchanged geometry skips redraw.
Highlight groups are default links (descriptions use `NormalFloat`), so definitions from the
host or a colorscheme take precedence; ColorScheme restores links cleared by `:highlight clear`.

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
| `core.text`         | UTF-8 characters, cell-aware word wrapping and clipping                      |
| `core.columns`      | Column count and width, balanced partition, vertical and horizontal joining  |
| `core.layout`       | Geometry, group blocks, column assembly, document lines and highlight spans  |
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
luajit tests/columns.lua
luajit tests/controller.lua
NVIM_LOG_FILE=/tmp/cheatsheet-nvim.log nvim --clean --headless -i NONE -l tests/nvim.lua
NVIM_LOG_FILE=/tmp/cheatsheet-adapter.log nvim --clean --headless -i NONE -l tests/adapter.lua
NVIM_LOG_FILE=/tmp/cheatsheet-regressions.log nvim --clean --headless -i NONE -l tests/regressions.lua
NVIM_LOG_FILE=/tmp/cheatsheet-types.log nvim --clean --headless -i NONE -l tests/types_check.lua
stylua --check .
```

`stylua.toml` in the plugin root matches the host configuration, so `stylua --check .` verifies
formatting from the plugin root as well as from the configuration root; `stylua .` applies it.

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

The four pure suites also run with `nvim --clean --headless -i NONE -l tests/<suite>.lua`;
they remove the `vim` global while executing tests. No dependencies are installed or modified.

- **Core:** option validation and unknown-option warnings, immutable inputs/defaults, pattern syntax,
  lhs/description filters and inclusions, raw keymap modes, source precedence, descriptions, icons,
  case-insensitive sorting, leader and Space formatting and modes.
- **Layout:** exact lines and spans, Unicode byte/cell boundaries, alignments, separators,
  configurable spacing (including zero), empty results, empty icons/descriptions, small-window geometry,
  column targets, wrapped mapping lines, block heights, per-column key widths, newspaper order and
  single-column equivalence.
- **Columns:** UTF-8 splitting and word wrap, column count and width, partition optimality against
  exhaustive search with deterministic ties, stacking and cell-aligned composition.
- **Controller:** independent instances, setup and reconfiguration, source context, mode changes,
  tab pages, resize, ownership, reentrancy, error handling and cleanup retries using an injected test adapter.
- **Neovim:** public API and actual mapped keys, command arguments and completion, source-buffer
  overrides, select-only mappings, extmarks, ColorScheme and host highlights, columns, resize/view/focus,
  tab pages, external closure, source deletion and queued events.
- **Adapter:** every supported mode and border, default leader, optional and reconfigured opening mapping,
  tiny floats, explicit prefixes, description filters, custom layout through resize,
  setup rollback and injected allocation/rendering/cleanup failures.
- **Regressions:** seven previously failing public-API scenarios, reproduced before refactoring.
