# css-in-js.nvim

Self-contained CSS-in-JS completion and hover for styled-components / Emotion in
JavaScript, JSX, TypeScript and TSX. Requires Neovim >=0.12; no host configuration
modules are loaded and no dependencies are installed.

## Setup and public API

```lua
vim.cmd.packadd("css-in-js.nvim")
---@type CssInJsOptions
local options = {
  filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
  server_name = "cssls",
  request_timeout_ms = 5000,
  poll_interval_ms = 20,
  trigger_characters = { ":", "-", " " },
  suppressed_lsp_clients = { "vtsls", "tsgo" },
  hover = { border = "rounded", max_width = 80, max_height = 20 },
  filter = function(buf) return not vim.b[buf].bigfile end,
  styled_parser = {
    url = "https://github.com/your-fork/tree-sitter-styled",
    revision = "your-pinned-revision",
    files = { "src/parser.c", "src/scanner.c" },
  },
}
require("css_in_js").setup(options)
```

All options are optional. The default filter accepts ordinary buffers with supported
filetypes. Invalid known options warn and use defaults independently; caller options are copied.
A filter exception rejects the buffer and reports a warning. Calling `setup()` replaces
previous settings, including settings used by existing Blink sources.

| Option | Default | Behavior |
| --- | --- | --- |
| `filetypes` | JS, JSX, TS, TSX names shown above | Replaces allowed ordinary buffer filetypes; `{}` disables the source. Custom types require matching parsers/injection queries. |
| `server_name` | `"cssls"` | Name of a registered `vim.lsp.config` to copy for hidden CSS documents. Missing configs return empty results. |
| `request_timeout_ms` | `5000` | Positive integer; total deadline for initialization and response. |
| `poll_interval_ms` | `20` | Positive integer; initialization polling interval, capped by the remaining deadline. |
| `trigger_characters` | `{ ":", "-", " " }` | Replaces Blink automatic trigger characters; `{}` removes these triggers while manual completion remains available. |
| `suppressed_lsp_clients` | `{ "vtsls", "tsgo" }` | Names removed from other LSP completion results once CSS is ready; `{}` preserves every client. |
| `hover.border` | `"rounded"` | One of `none`, `single`, `double`, `rounded`, `solid`, `shadow`. |
| `hover.max_width`, `hover.max_height` | unset | Optional positive integers; native hover preview size limits. |

Lists must be dense arrays of nonempty strings and replace defaults rather than merge.
Hover fields merge with their defaults independently. Buffer filters, CSS context checks,
TS fallback on failures and hover fallback outside CSS continue to apply.

Configure `vim.lsp.config[server_name]` with an installed CSS language server. Install the
`javascript`, `typescript`, `tsx` and `styled` parsers and their bundled injection queries
using nvim-treesitter. Load this plugin before parsing templates: it extends the `ecma`
and `typescript` injection queries. Highlighting and parser installation are caller-owned.

`styled_parser` accepts parser installation information and requires nvim-treesitter.
Setup applies it immediately and on `User TSUpdate`; the host owns the fork/revision pin.
Multiple overrides share ownership: the newest active owner wins, including after TSUpdate.
Teardown restores the preceding active owner or original definition and preserves foreign replacements.

```lua
require("blink.cmp").setup({
  sources = {
    default = { "lsp", "css_in_js" },
    providers = {
      css_in_js = { name = "CSS-in-JS", module = "css_in_js" },
      lsp = { transform_items = require("css_in_js").filter_lsp_items },
    },
  },
})
```

- `setup(opts?)` replaces configuration and cleans up the previous session. Failed
  registration rolls back partial resources and can be retried.
- `new()` returns a Blink source with `enabled`, `get_trigger_characters` and
  `get_completions`. Default triggers are `:`, `-` and space.
- `context(buf, row, col)` accepts zero-based byte coordinates and returns the active
  region or nil. The public region retains its `node` and start/end coordinates;
  it also exposes substitution ranges. The public call extracts the tree once. Core snapshots contain no TS nodes.
- `supports_buffer(buf)` always returns boolean and applies the caller filter.
- `filter_lsp_items(ctx, items)` removes vtsls/tsgo results only inside CSS after a
  valid CSS completion response from a live client, including an empty result. Before CSS is available,
  or after a failed request, TS results remain available. `${...}` keeps TS completion.
- `hover()` requests CSS documentation inside a template and delegates to native
  `vim.lsp.buf.hover()` elsewhere. The caller owns its keymap. CSS hover retains the
  rounded Markdown preview and ignores replies after the cursor/buffer changes.
- `teardown()` cancels requests and timers, releases hidden documents and owned
  registrations, and disables existing sources until `setup()` is called again.
  It is safe to repeat, including retrying failed cleanup.

Before explicit setup, default configuration is usable; cleanup handlers are installed
lazily before allocating resources. Private module paths are implementation details.
The old `css_in_js.regions` and `css_in_js.treesitter` modules have moved into the core
and integration layers; integrations should use the public facade above.

## Documents, edits and request ownership

One hidden, unlisted in-memory CSS document is retained per host buffer and controller.
Only rows covering the active template are read and copied; full boundary lines retain
host prefixes for correct Unicode coordinates. Completion and hover reuse the immutable
snapshot and cached region when changedtick, filetype and the active template are unchanged.
Moving outside that template triggers extraction again; switching templates invalidates
pending requests even without host edits. Setup, allocation replacement and host deletion
clear snapshots. Cached context still checks the caller filter and rejects substitutions.
Its name has no `.css` extension and its filetype stays empty, preventing ordinary CSS
server attachment. Only plugin-owned CSS clients with matching registered server names and roots are reused;
generated diagnostics are suppressed. Clients are stopped after their last attachment
is released, without stopping foreign clients or other adapters' active documents.

The generated document wraps the template in `a{` / `;}` and masks substitutions with
spaces and a declaration placeholder, preserving UTF-16 widths. A segment map translates
between generated text and host bytes. Requests and edits use the client's negotiated
UTF-8, UTF-16 or UTF-32 encoding, including characters after masked substitutions.

Completion responses are copied. Array responses, `itemDefaults`, snippets, ordinary
and insert/replace edits, and additional text edits are translated. Invalid ranges,
reversed positions, Unicode splits, wrapper edits, overlapping edits and edits crossing substitutions
reject the entire completion item. This prevents edits outside the active template.

Requests capture host changedtick before extracting the template and verify it throughout document
preparation; host changes during allocation or rendering discard the request. Requests also capture
the generated-document version. Switching templates
without editing the host invalidates previous requests. New requests replace older
requests of the same kind; completion and hover may coexist on the same snapshot.
Cancellation and replacement are silent, while failure/staleness of an active completion
returns an empty result. Callbacks complete at most once. The total operation deadline
defaults to five seconds, including initialization, polled at 20 ms intervals; both values
are configurable. All timers are
cancelled when the operation ends. Unchanged CSS content avoids redundant buffer writes.

Host deletion/wipeout and teardown cancel pending operations before deleting hidden
buffers. Partial allocation and rendering failures clean up resources; failed cleanup
retains ownership for a later retry.

## Architecture and typing

| Module | Responsibility |
| --- | --- |
| `core.config` | Immutable options, validation and diagnostics |
| `core.regions` | Supported buffer kinds and active-region boundaries |
| `core.coordinates` | Strict Unicode decoding and byte/encoding conversion |
| `core.document` | Extraction, masking, wrappers and source maps |
| `core.completion` | Defaults and immutable completion/edit translation |
| `core.requests` | Request-state decisions |
| `controller` | Injected resource ownership, scheduling and orchestration |
| `integrations.nvim` | Buffers, native LSP clients, timers, events and hover UI |
| `integrations.treesitter` | Native syntax trees and parser override ownership |
| `integrations.blink` | Source methods and TS-item filtering |
| `init` / `types` | Public facade and LuaCATS contracts |

Core and controller modules do not depend on `vim`. Production functions, callbacks,
options, domain structures, adapter contracts and test fixtures are typed. Untrusted
configuration/protocol validation accepts `unknown`; known data uses precise types.
LuaLS checks use native Neovim protocol definitions without loading the host config.

## Tests

Run from this plugin's root, or pass absolute script paths from any directory. No test
installs dependencies or modifies project files. Neovim suites use installed parsers
and nvim-treesitter under `stdpath("data")/site`.

```sh
luajit tests/core.lua
luajit tests/controller.lua
NVIM_LOG_FILE=/tmp/css-in-js-nvim.log XDG_STATE_HOME=/tmp/css-in-js-state nvim --clean --headless -i NONE -l tests/nvim.lua
NVIM_LOG_FILE=/tmp/css-in-js-adapter.log XDG_STATE_HOME=/tmp/css-in-js-state nvim --clean --headless -i NONE -l tests/adapter.lua
NVIM_LOG_FILE=/tmp/css-in-js-lsp.log XDG_STATE_HOME=/tmp/css-in-js-state nvim --clean --headless -i NONE -l tests/lsp.lua
NVIM_LOG_FILE=/tmp/css-in-js-types.log XDG_STATE_HOME=/tmp/css-in-js-state nvim --clean --headless -i NONE -l tests/types_check.lua
stylua --search-parent-directories --check .
```

The pure suites also run with headless Neovim and remove the `vim` global during execution.
`lsp.lua` uses a real installed vscode-css-language-server to verify completion application
and hover; set `CSS_LS` to override its executable. `types_check.lua` fails on LuaLS errors
and warnings; set `LUA_LS` to override its executable. Both locate Mason executables when
not available on PATH and keep logs/configuration outside the plugin.

- **Core:** configuration, filetypes, region/substitution boundaries, Unicode round trips,
  masking, empty/multiline templates, source maps, immutable edits/defaults and invalid replies.
- **Controller:** initialization, timeouts, cancellation, supersession, host edits/deletion,
  cleanup retries, failed setup, filter errors, hover and independent instances using fake time.
- **Public compatibility:** existing extraction, parser refresh, defaults, cancellation,
  filtering and hidden-buffer cleanup through the public API.
- **Adapters/regressions:** real syntax trees across all four filetypes, generic/attrs
  templates, allocation failures, stale regions, response mutation, parser ownership,
  setup rollback, and independent adapters sharing a host.
- **Real LSP:** actual server completion edits preserve JS syntax and hover returns documentation.
