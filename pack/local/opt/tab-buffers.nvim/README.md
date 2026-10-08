# tab-buffers.nvim

A standalone Neovim plugin for tab-local buffer membership, ordering and safe closure.
Neovim >=0.12 is required for the adapter; the separate Lua core also runs in LuaJIT without Neovim.
The ownership model and Neovim adapter have no dependencies on the enclosing configuration or UI plugins.
Optional integrations use bufferline.nvim, fzf-lua and Diffview. This configuration loads the plugin in the workflow group.

Each tab owns an ordered list of unique buffer IDs. One buffer may belong to several tabs with
independent positions. Membership does not imply a separate copy of its text.
The adapter uses stable positive integer handles, not tab numbers. Reordering Neovim tabs does not
change their ownership. Zero is not a current-tab/current-buffer shorthand; omit optional arguments
to use the current context.

## Use

Place the plugin under `pack/<group>/opt/tab-buffers.nvim` on Neovim's `packpath`, then load and set it up:

```lua
vim.cmd.packadd("tab-buffers.nvim")
require("tab_buffers").setup()
```

`setup()` enables observation and captures existing buffers. The adapter is intended to run as the
sole ownership manager; do not run scope alongside it.
It does not install commands or mappings. Personal mappings can call its public functions directly:

```lua
local buffers = require("tab_buffers")
-- Examples of mapping callbacks:
-- function() buffers.next() end
-- function() buffers.move(-1) end
-- function() buffers.close_others() end
```

## Public Neovim API

Call `setup()` before other methods. Repeated setup preserves membership and order and does not
duplicate autocommands. `teardown()` disables observation, cancels queued work and discards the
model without deleting real buffers. A later setup captures the current Neovim state again.

| Method | Behavior and result |
| --- | --- |
| `setup()`, `teardown()` | Return whether initialization/teardown succeeded. Teardown without setup returns false. |
| `refresh()` | Immediately reconcile ownership with actual buffers/windows, then schedule change publication. Returns true. |
| `tabs()` | Return real tab handles in Neovim display order. |
| `buffers(tab?)` | Return the tab's ordered buffer IDs. |
| `owners(buf?)` | Return owner tab handles in ascending handle order. |
| `contains(buf?, tab?)` | Test membership; note the buffer-first argument order in this public API. |
| `add(buf?, opts?)` | Add an eligible buffer to a tab, including sharing a buffer already owned elsewhere. Does not display it. |
| `transfer(target_tab, opts?)` | Move membership to another valid tab, replacing source working windows. Preserve an existing destination position. |
| `move(offset, opts?)`, `move_to(index, opts?)` | Move the selected buffer within its tab; positions clamp at the ends. |
| `reorder(buffers, opts?)` | Apply an exact permutation of the tab's membership list. |
| `sort(by, opts?)` | One-time stable sort by `"id"`, basename `"name"`, full buffer `"path"`, or a comparator receiving buffer IDs. |
| `switch(offset, opts?)`, `next(opts?)`, `previous(opts?)` | Switch a working window according to model order. Return the selected buffer ID, or nil if no target exists. |
| `open(buf, opts?)` | Select an existing member, focusing a working window or creating a split while preserving special windows. |
| `close(opts?)` | Close the selected buffer's membership in the tab. |
| `close_all(opts?)`, `close_others(opts?)` | Close all buffers, or all except the selected buffer. |
| `close_left(opts?)`, `close_right(opts?)` | Close buffers before/after the selected buffer in tab order. |
| `close_tab(opts?)` | Preflight and close the selected tab. Never exits the final tab. |
| `close_many(buffers, opts?)` | Close an explicit selection in model order; ignore duplicates and expired/foreign memberships. |

Membership/order operations return `changed, error?`; navigation returns `buffer?, error?`.
No-op operations have no error. Closing returns a report:

```lua
{
  closed = {},    -- Buffer IDs whose membership in the target tab was closed.
  failed = {},    -- { buf = buffer_id, message = "reason" } entries.
  tab_closed = false,
  error = nil,   -- Optional operation-level error, including errors after a committed change.
}
```

Closing functions return partial results and issue one warning for failures. Shared buffers count as
closed after their target-tab membership is removed, even though their actual buffers remain alive.

Options are optional tables. Each operation uses the applicable fields:

| Option | Default and meaning |
| --- | --- |
| `tab` | Current tab handle. |
| `win` | The selected tab's current window; must belong to that tab. |
| `buf` | The selected window's buffer. The positional argument to `add` overrides this field. |
| `index` | Destination insertion position for `add` and `transfer`; defaults to the end. |
| `force` | False; allows discarding modified exclusive buffers during close. Shared text is preserved even with force. |
| `wrap` | True for navigation. False returns nil past either end. |
| `split` | Only for `open`: `"horizontal"` opens below, `"vertical"` opens to the right. |

For example, `buffers.close({ tab = tab_handle, buf = buffer_id })` operates on a specific tab/buffer
without requiring a focus change. Calls from special, floating or preview windows with no explicit
`tab`, `buf` or `win` do nothing. Navigation always requires a working target window. Unknown pivots
do not select other buffers accidentally. Invalid argument types raise errors; expired handles
return no change plus an error for managing operations. Queries return empty results for unknown IDs.

Native commands are observed and reconciled on the next scheduled turn. Use `refresh()` when an
immediate query after a native command needs current ownership. Public managing operations reconcile
before and after execution. Do not reenter managing methods from a sort comparator or window callback;
queries remain available during operations.

`open()` never adopts a foreign buffer. Without an explicit window, it uses the tab's current working
window, otherwise the first working window in tab layout order. If none exists, it creates a working
split to the right of an ordinary non-preview window. Explicit `win` must already be a working window.
The operation focuses its destination tab/window and protects the original buffer while switching.
Unlike implicit navigation, explicit buffer selection can be invoked from a tree, float or preview.
`close_many()` also treats its list as explicit selection; an empty or stale list does not close a tab.
Its list must be dense and contain positive integer IDs, just like other public handle arguments.

Changes publish a coalesced `User TabBuffersChanged` event with `args.data.tabs`: affected tab handles
in ascending handle order, including removed tabs. No-op operations do not publish changes.
This event is the integration point for optional UI adapters.

## Buffer lifecycle and safe closure

The adapter manages listed ordinary buffers (`buftype = ""`) shown in ordinary windows. Special buffers,
terminals, floating windows and preview windows do not create membership. Empty unnamed buffers enroll
after text or modifications appear; once enrolled they remain owned even if their text is cleared.

At first setup, visible working buffers belong to their respective tabs. Eligible hidden buffers with
no owner append to the current ordinary tab (or another ordinary tab if the current tab is excluded) in buffer ID order. Buffers displayed only in excluded windows remain
unowned. Newly created background buffers after setup stay unowned until shown or explicitly added.
Hiding a buffer or closing a split does not remove membership. Rename retains membership/order;
actual deletion, unlisting or changing to a special buftype removes it. The adapter does not change
`buflisted` on tab switches, so native `bnext`/`bprevious` still traverse the global list; use its functions
for tab-local navigation.

Shared close changes only the target tab. Its working windows get a remaining buffer to the right,
otherwise to the left. Bulk-close replacements skip other permitted closing targets. Exclusive close
uses `nvim_buf_delete` after safety checks. Modified exclusive buffers require explicit force; buffers
still referenced by unmanaged windows are retained. Failures preserve membership and restore affected
window buffers where the handles remain valid. Other tabs and normal split layouts are preserved.

Bulk close closes permitted targets and leaves failures owned by the tab. A zero-target operation
does not close an empty tab. Closing/transferring the last owned buffer closes its source tab when
other tabs exist. The final tab keeps empty working windows instead of quitting; if an explicit close
from a special-only final tab needs a working window, an empty split is added while preserving focus.

`close_tab()` refuses modified exclusive buffers before any window changes unless forced. Once a tab
has actually closed, cleanup deletes permitted exclusive buffers, retains shared buffers, and recovers
undeletable exclusive buffers in a surviving ordinary tab. It may therefore report `tab_closed = true`
with failures for recovered buffers.

External tab closure, `tabonly` and closure of a tab's last window also trigger cleanup. Modified or
undeletable exclusive buffers recover in a surviving ordinary tab with one notification. If only excluded
review tabs survive, recovery creates an ordinary tab. External
`tabclose!` does not opt into discarding their text. All closed owners are removed before cleanup decides
whether a shared buffer has become exclusive. Native forced buffer deletion itself remains global.

Window operations and tab-closing events temporarily protect `bufhidden`, then restore its original
value, so `wipe`, `delete` or `unload` cannot prematurely destroy text or terminal jobs. Global `hidden`
and `buflisted` are preserved. Pending cleanup is cancelled on teardown or editor exit.

## Core model

The lower-level model is independent of the adapter and uses arbitrary positive integer IDs.
It can also be loaded directly through Lua's module path without Neovim:

```lua
local model = require("tab_buffers.core").new()

model:attach(1, 10)
model:attach(1, 20)
model:attach(2, 20) -- Share the same buffer with another tab.
model:move_to(1, 20, 1)

assert(model:neighbor(1, 20, 1) == 10)
assert(model:contains(2, 20))

local plan = model:plan_close(1, model:targets(1, "all"))
-- plan.buffers   = { 20, 10 }
-- plan.shared    = { 20 }
-- plan.exclusive = { 10 }
-- plan.remaining = {}
-- Planning has not removed anything.
```

Models are independent instances. State is private and all returned lists are independent snapshots.
Mutating methods return `true` when they change state and `false` otherwise, except the reporting
methods explicitly described below. Invalid arguments raise an error before changing state.
IDs must be finite positive integers; positions and offsets must be finite integers.

## Membership API

| Method                            | Behavior and result                                                                                                                                                             |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ensure_tab(tab)`                 | Create an empty tab. Existing tabs are unchanged.                                                                                                                               |
| `tabs()`                          | Return tab IDs in ascending ID order, including empty tabs. This is not display order.                                                                                          |
| `buffers(tab)`                    | Return the tab's buffers in their current order; an unknown tab returns `{}`.                                                                                                   |
| `contains(tab, buf)`              | Return whether the buffer belongs to this tab.                                                                                                                                  |
| `owners(buf)`                     | Return owner tab IDs in ascending ID order; an unknown buffer returns `{}`.                                                                                                     |
| `attach(tab, buf, index?)`        | Create the tab if needed and insert the buffer. Default position is the end. Clamp a supplied position to `1..n+1`. Existing membership keeps its position.                     |
| `detach(tab, buf)`                | Remove one membership. Return `(removed, orphan)`, where `orphan` is true only if a membership was removed and no owners remain. A missing membership returns `(false, false)`. |
| `transfer(from, to, buf, index?)` | Add to the destination and remove from the source. Preserve an existing destination position. Same-tab and missing-source transfers return false without creating tabs.         |
| `forget_buffer(buf)`              | Remove the buffer from all tabs and return affected tab IDs in ascending order.                                                                                                 |
| `remove_tab(tab)`                 | Remove the tab and return `{ buffers = {...}, orphans = {...} }`, both in its previous buffer order. Orphans have no remaining owners. An unknown tab returns empty lists.      |

Detaching, transferring and forgetting buffers retain empty tabs. Removing a tab is a separate
operation; the core does not decide whether an empty tab should close in Neovim.

## Order and navigation API

| Method                              | Behavior and result                                                                                                                                        |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `move_to(tab, buf, index)`          | Move a buffer to an absolute position, shifting intervening buffers. Clamp to `1..n`.                                                                      |
| `move(tab, buf, offset)`            | Move relative to the current position, clamping at either end without wrapping.                                                                            |
| `reorder(tab, buffers)`             | Apply an exact permutation of the current list. Reject duplicates, missing/foreign buffers and malformed lists. Copy the input.                            |
| `sort(tab, less)`                   | Apply a one-time stable sort using a comparator receiving buffer IDs. Ties retain their previous order.                                                    |
| `neighbor(tab, buf, offset, wrap?)` | Return the buffer at a signed offset. Default `wrap = true`; non-wrapping navigation beyond either end returns nil. Offset zero returns the buffer itself. |
| `replacement(tab, buf)`             | Return the immediate neighbor to the right, otherwise to the left. No neighbor means nil.                                                                  |

Unknown tabs or missing buffers produce false for movement and nil for navigation.
Reordering an unknown tab with a valid duplicate-free list returns false; it does not create a tab.
Sorting empty, singleton or unknown tabs returns false without invoking the comparator.

Sorting is not a persistent mode: future additions still append by default, and manual moves remain
in effect. The comparator must provide a strict weak ordering. It may query the model, but calling
any mutating method on that same model raises an error. Comparator errors leave the previous state
intact and do not prevent later operations. The core does not resolve filenames or paths.

## Close selection and planning API

`targets(tab, mode, pivot?)` returns buffer IDs in current tab order:

| Mode       | Selection                        |
| ---------- | -------------------------------- |
| `"one"`    | The pivot buffer.                |
| `"all"`    | All buffers; no pivot is needed. |
| `"others"` | All buffers except the pivot.    |
| `"left"`   | Buffers preceding the pivot.     |
| `"right"`  | Buffers following the pivot.     |

An absent or unowned pivot returns `{}` for every mode requiring a pivot. This prevents an unrelated
current buffer, such as a tree or terminal, from accidentally selecting all regular buffers.
An unknown tab returns `{}`. Unknown modes and invalid IDs raise an error.

`plan_close(tab, buffers)` accepts a dense list of buffer IDs and returns:

```lua
{
  buffers = {},   -- Requested members, deduplicated and in tab order.
  shared = {},    -- Selected members also owned by another tab.
  exclusive = {}, -- Selected members owned only by this tab.
  remaining = {}, -- Unselected members in tab order.
}
```

Foreign buffers and duplicate requests are ignored. Neither selection nor planning changes state.
Plans are snapshots, not transactions, and do not refresh after ownership or ordering changes.

An adapter must recheck membership and owners immediately before acting. For a shared
buffer, it can remove just the current tab's membership. For an exclusive buffer, it must perform
the permitted Neovim deletion first and call `detach` only after success. It must also replace
visible window buffers safely before detaching shared buffers. The core cannot inspect modified
text, windows, jobs or actual buffer validity. Calling `detach` alone does not close a Neovim buffer.

## UI integrations

Configure bufferline after the ownership adapter:

```lua
require("tab_buffers.integrations.bufferline").setup({
  highlights = {}, -- Personal appearance settings.
  options = { show_buffer_close_icons = false },
})
```

The integration filters and sorts by current-tab membership, wires left clicks to `open()` and
close/right clicks to safe `close()`, and updates on tab/model changes. Mandatory ownership callbacks
override corresponding options supplied by the caller. Global sort persistence and automatic line
visibility are disabled. The line shows for multiple current-tab members or multiple real tabs.
Native BufferLine Move/Sort/TogglePin commands are disabled; use `move`, `move_to`, `reorder` and `sort`.
Pins, custom groups and session restoration are outside this integration's scope. Native BufferLine
navigation commands are not routed through `open`; use the plugin's functions and mappings.
Repeated setup replaces integration handlers. `teardown()` cancels pending clicks, restores the supplied
bufferline configuration and restores the previous visibility if it has not been changed independently.
Tear down this integration before tearing down the ownership adapter.

```lua
require("tab_buffers.integrations.fzf").buffers({ prompt = "Buffers❯ " })
-- Resume using the normal public API:
require("fzf-lua").resume()
```

The fzf provider builds current-tab entries in model order, including hidden and unnamed members.
Nonempty searches use normal fzf ranking with stable input-order ties. IDs identify selections,
independently of names/icons, and builtin preview reads actual buffers. Enter opens the first selected
buffer; Ctrl-S/Ctrl-V open it in horizontal/vertical splits; Ctrl-X safely closes all selected members
and reloads. Each action retains its generation's tab handle and rejects stale membership.
The provider forces `no_hide=true`: Escape ends its process, so resume rebuilds the current tab's list
while retaining the query. Visual options remain configurable; membership actions are fixed.
The native `FzfLua buffers` provider is separate; call this provider for tab-local membership and order.

## Diffview integration

Pass the integration's public hooks and callbacks to Diffview:

```lua
local review = require("tab_buffers.integrations.diffview")
require("diffview").setup({
  hooks = review.hooks(),
  keymaps = {
    view = {
      { "n", "gf", review.goto_file },
      { "n", "<C-w>gf", review.goto_file_tab },
    },
    -- Use the same callbacks in file_panel and file_history_panel.
  },
})
```

Diffview and file-history tabs are separate reviews. Their staged/commit versions and real working-tree
previews do not acquire membership or appear in the scoped bufferline/fzf picker. Existing ownership
in ordinary tabs remains intact. Our management functions do nothing in review tabs, including explicit
close/open requests; Diffview owns their windows, navigation, cleanup and modified-index checks.
Use `DiffviewClose` or its `q` mapping to close a review.

`gf` opens the actual working-tree file in the previous ordinary tab, falling back to the first ordinary
tab or creating one if necessary. `<C-w>gf` always creates an ordinary tab. Opening enrolls the file,
preserves existing membership/order and special windows, and carries the review cursor when available.
Missing local files produce a warning without changing tabs. These callbacks also work from the file
and history panels. Outside a review they use native `gf` behavior. Native `<C-w><C-f>` still splits
inside the review and does not enroll its preview.

A file shared with an ordinary tab keeps its text and membership when the review closes. Closing an
exclusive ordinary member still displayed in review is refused to preserve that review's layout.
Diffview's default `clean_up_buffers = false` should be retained: its cleanup checks physical windows,
not hidden tab membership. Review-only real buffers may remain globally listed after Diffview closes;
the scoped integrations hide them without changing the global buffer list.

The adapter recognizes `vim.t[tab].tab_buffers_excluded = true`. Setting this flag releases that tab's
memberships without deleting buffers. After changing it, publish `User TabBuffersContextChanged` for
scheduled reconciliation or call `refresh()` for immediate reconciliation. Ordinary diff windows remain
managed; exclusion applies to the review tab. `tabs()` continues to list all real tabs for tab navigation.

The host configuration loads this plugin before tree/fzf configuration and replaces scope entirely.
Its normal mappings are Tab/Shift-Tab for navigation, `<leader>x` for close, `<leader>cx` for close others,
`<leader>bh`/`<leader>bl` for moving left/right, and `<leader>fb` for this picker. Restart Neovim after
switching from scope so its old autocommands and listing state are no longer active. Native `bnext`,
`bdelete!` and other global commands retain Neovim's global semantics. Membership is session-local.
The installed but inactive scope package can remain until a separate package cleanup. Its lockfile
entry must remain while installed: `vim.pack` repairs missing installed-package records on startup.

## Tests

The suites require LuaJIT for the core or Neovim >=0.12, with no additional test framework.
UI integration tests additionally require installed bufferline.nvim, fzf-lua and the fzf executable.
Diffview tests require installed diffview-plus.nvim, bufferline.nvim and Git.
Run from this plugin's root:

```sh
luajit tests/core.lua
nvim --clean --headless -i NONE -l tests/core.lua
nvim --clean --headless -i NONE -l tests/nvim.lua
nvim --clean --headless -i NONE -l tests/integrations.lua
nvim --clean --headless -i NONE -l tests/diffview.lua
stylua --check .
```

You may also pass absolute paths to the test scripts from any working directory. Tests locate the
plugin relative to their own files. Core tests clear the global `vim` while exercising it, including
under Neovim. All runners exit nonzero on failure. The Neovim suites use real buffers/windows/tabs,
temporary buffer names without writing files, and short-lived terminal jobs. They do not load the full host
configuration or change existing projects. Targeted integration cases load host mappings and the
Diffview setup. Diffview tests create and remove their own temporary Git repository; they never stage
or commit changes in the enclosing repository. Swap files are disabled. In a restricted environment, set
`NVIM_LOG_FILE` to a writable temporary path.
Fzf-lua also requires permission to open a local Neovim RPC socket. The UI suite discovers installed
plugins under `stdpath("data")/site`; it does not download or modify dependencies. Its fzf tests run
real processes, inspect previews and send terminal input to verify deletion/reload and resume.

Coverage includes every public method, shared ownership, independent tab orders and instances,
empty states, repeated operations, movement boundaries, navigation, stable sorting, invalid input,
sort callback errors and reentrancy, immutable query snapshots, partial-close workflows, orphan
recovery, and 1,500 deterministic mixed operations checked against a separate membership-set oracle.

Integration coverage includes bootstrap, background/unloaded/unnamed buffers, excluded windows,
rename and deletion events, eligibility changes, idempotent setup/teardown, change events, ordering,
navigation, shared/modified closures, partial failures, all bulk-close modes, split/focus preservation,
window/deletion rollback, expired handles, transfers, tab preflight/force, inactive and external closure,
`tabonly`, last windows/buffers/tabs, recovery, destructive `bufhidden`, terminal survival, editor exit,
reentrant callbacks and errors after changes have committed.
UI coverage includes actual bufferline rendering, per-tab order and visibility, safe click callbacks,
idempotent integration setup/teardown, stale selections, fzf entry order/metadata, fast callbacks,
multi-close, split selection, real buffer previews, reload and resume across tabs, and host mappings.

Diffview coverage includes staged/working previews, file history, multiple reviews, actual host setup,
scoped UI exclusion, dirty index guards, native closure, shared files, safe ordinary-tab selection,
new-tab navigation, special-only destinations and missing files.
