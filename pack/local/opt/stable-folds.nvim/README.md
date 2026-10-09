# stable-folds.nvim

Synchronous Tree-sitter folding for Neovim >=0.12. A complete range snapshot is
computed once per buffer changedtick, filetype and language. Snapshots retain
only ranges, unique header text and a line count; header reads group adjacent
starts and omit fold bodies. Windows reuse that
snapshot with their own `foldminlines` and `foldnestmax`; switching windows or
changing these options does not parse the tree again. Injections and fold query
metadata are included.

Automatic events at an unchanged revision and window fold profile skip native
recomputation and state restoration. A new window or changed fold limits refresh
only affected views. Header positions are read once per buffer during state
capture and once during reconciliation, then shared across windows. Correctly
positioned extmarks are reused without rewriting them. Native expression batches
reuse their prepared window view and filter decision; ordinary public `expr()`
calls still observe dynamic filters and current window settings immediately.
Explicit `refresh()` always forces a new snapshot and native recomputation.

## Setup and API

```lua
vim.cmd.packadd("stable-folds.nvim")
local folds = require("stable_folds")

---@type StableFoldsOptions
local options = {
  new_folds = "open",
  include_injections = true,
  max_lines = 0,
  max_bytes = 0,
  notify_errors = true,
  filter = function(buf) return not vim.b[buf].bigfile end,
}
folds.setup(options)
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = folds.foldexpr
```

Install parsers and `folds` queries separately. The plugin installs no parsers,
queries, mappings or commands and does not require host configuration helpers.

| Option | Default | Behavior |
| --- | --- | --- |
| `filter` | Accept regular buffers | Buffer predicate; special buffers are always excluded. |
| `new_folds` | `"open"` | `"open"` opens new folds after edits; `"inherit"` uses each window's current `foldlevel`. Existing folds retain their manual state. |
| `include_injections` | `true` | Include nested languages. `false` parses and queries only host trees, even if another consumer already parsed injections. |
| `max_lines` | `0` | Skip buffers with more lines than this limit; `0` disables the limit. |
| `max_bytes` | `0` | Skip buffers exceeding this UTF-8 byte limit, including Neovim's line terminators; `0` disables the limit. |
| `notify_errors` | `true` | Emit configuration warnings and contained runtime errors through `vim.notify`. `false` silences both. |

Size limits accept finite nonnegative integers and include the boundary itself.
They are checked before parsing, reading the full text or attaching an edit
listener. Rejected revisions are cached; shrinking a buffer below both limits
automatically enables folds again. No size queries are made with both limits
disabled. `refresh()` rechecks a rejected buffer; repeated `setup()` replaces
all options with defaults plus the supplied values and updates existing windows.

- `setup(opts?)` registers refresh and cleanup handlers. Repeated calls replace
  options and resources and immediately refresh existing plugin windows.
  `filter(buf)` defaults to `true` for regular buffers;
  special buffers are always excluded. Invalid options warn and use defaults;
  unknown keys warn and are ignored.
- `attach(win?)` sets the expression and foldmethod in a window; omitted or `0`
  means the current window. Other fold options are caller-owned.
- `expr(line?)` returns a level string for the current buffer/window. Omitted line
  uses `vim.v.lnum`; invalid or out-of-buffer lines return `"0"`. It and `attach`
  work before `setup`, with defaults, but automatic refresh requires setup.
- `refresh(buf?)` invalidates the range snapshot and refreshes all windows using
  this expression for the buffer. Omitted or `0` means the current buffer.
  Hidden buffers recompute when next evaluated. This also picks up parser/query
  changes at an unchanged changedtick and retries a failed parse.
  Reentrant requests for other buffers, newer revisions or a forced refresh
  are processed after the current pass; identical requests are merged.
- `teardown()` cancels owned callbacks, clears caches and header marks, and removes
  owned autocommands. It is repeatable. Window options remain caller-owned;
  `expr` returns `"0"` until the next setup.

Visual options, initial `foldlevel`, `foldlevelstart`, `foldcolumn`, `foldminlines`,
`foldnestmax` and `foldtext` stay in the personal host configuration. Its existing
setup requires no migration.

## Fold identity and refresh

Moving header extmarks identify folds across edits. All positional matches are
reserved before attempting formatter recovery by headers unique in both
snapshots. An inserted duplicate cannot steal an original fold's identity.
Ambiguous full replacements use fresh identities rather than transferring a
neighbour's state. Marks are independent of window size/nesting limits.

Open/closed states, including hidden children, are captured once per identity/window
during an edit burst and restored by identity after refresh. This preserves different manual states in
splits, formatter replacements with changing line counts and reordered unique
headers. State inspection freezes the native fold tree and temporarily exposes
closed ancestors, then restores folds, window options and the view immediately.
Restoring an open parent does not recursively open existing children. By default, new folds after text edits are opened;
initial folds and option/query changes honor native fold settings.

TextChanged, TextChangedI, TextChangedP, InsertLeave and BufWritePost refresh complete boundaries. FileType
resets identity when the language changes. BufUnload releases snapshots, watchers
and marks while retaining lightweight identities and closed flags until reload
or BufWipeout. BufReadPre captures state when a reload does not unload first;
BufReadPost and the buffer's reload notification restore the expression in
previously owned windows after filetype plugins and restore fold state, including
across reordered headers. For `:checktime`, Neovim clears text before BufReadPre;
flags beyond the temporary line count are read from a temporary native `mkview`
serialization, which is never executed and is removed immediately. WinClosed
releases window state. OptionSet refreshes fold limits. BufWinEnter retries missing
parsers/queries, and User TSUpdate invalidates known snapshots. Manual refresh is
available independently of nvim-treesitter.

Missing parsers/queries and excluded buffers produce zero levels. Filter, parse,
query and adapter errors are contained; notifications are deduplicated per buffer
revision. Failed parses do not publish partial levels or discard existing header
identities. Explicit refresh, entering a window or a new changedtick retries them.
Buffer edits and lifecycle changes during collection discard stale results.

The buffer edit listener is cancelled immediately on cleanup; its inactive native
attachment removes itself on the next edit/detach event. It never calls
`nvim_buf_detach`, which would also detach other Lua listeners such as Tree-sitter.

## Architecture and types

The structure matches the other local plugins:

- `lua/stable_folds/init.lua`: typed public facade.
- `controller.lua`: an isolated `new(adapter)` instance coordinating snapshots,
  window views, identity, refresh and lifecycle without a dependency on `vim`.
- `core/`: pure configuration normalization, range conversion/deduplication,
  level calculation, snapshot/view cache rules and identity/state matching.
- `integrations/treesitter.lua`: native synchronous parsing and query extraction,
  returning plain coordinates without trees or nodes.
- `integrations/nvim.lua`: buffers, windows, extmarks, edit listeners, autocommands
  and notifications. Adapter instances own independent resources.
- `types.lua`: LuaCATS contracts for public options/API, domain data, controller
  and adapter. Tests and fixtures are typed too.

## Tests

Run from this plugin's root, or provide script paths from the repository root:

```sh
luajit tests/core.lua
luajit tests/controller.lua
for suite in core controller adapter nvim interactive types_check; do
  NVIM_LOG_FILE="/tmp/stable-folds-${suite}.log" \
    nvim --clean --headless -i NONE -l "tests/${suite}.lua"
done
stylua --check .
```

Core/controller suites also run with `vim = nil` inside Neovim. The native suites
use installed Lua/JSON parsers and nvim-treesitter queries from
`stdpath("data")/site`, without loading the host configuration or downloading
anything. The type checker uses LuaLS with native Neovim API types; set `LUA_LS`
if its executable is not on PATH or in the usual Mason location.

Coverage includes nested/shared boundaries, exclusive end coordinates, metadata,
quantified captures, injections, duplicate headers, formatting/reordering,
window-specific states and limits, snapshot reuse, parser/query availability,
errors/recovery, reentrancy, stale callbacks, registration rollback, listener
cancellation, resource isolation and repeated setup/teardown.

During byte edits, Neovim may expose its old or already moved native fold tree,
and undo can evaluate foldexpr before Tree-sitter receives the edit notification.
State capture detects native starts individually; temporary translated levels
keep folds stable until the safe text-change event commits a fresh parse. Insert
and popup completion changes restore states immediately, without waiting for Escape.

`tests/interactive.lua` drives a separate embedded Neovim through real RPC input,
without manually firing editing autocommands. It covers `o`/`O`, mode transitions,
multiline input, deletion, register/linewise/bracketed/streamed paste, undo/redo,
popup completion, nested folds and different states in splits. Native opening of
the target fold for editing or undo cursor movement remains supported.
