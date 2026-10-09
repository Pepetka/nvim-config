# package-info.nvim

A standalone Neovim plugin that checks saved `package.json` files on open and save.
Automatic checks can be disabled or configured independently for entering and saving buffers.
It supports npm >=7, Yarn Classic, Yarn 2–4 and pnpm >=7 using each manager's registry/auth configuration.
Neovim >=0.12, an installed JSON Tree-sitter parser, Node >=22.18 and npm are required.
On first use, three pinned helper dependencies are installed with
`npm ci --ignore-scripts --no-audit --no-fund` under Neovim's data directory (`package-info/`).
Project manifests, lockfiles and installations are read only. Managers must already be available;
Corepack network downloads are disabled.

## Setup

Place the plugin folder under `pack/<group>/opt/package-info.nvim` in any directory on Neovim's
`packpath`, then load it before configuring it:

```lua
vim.cmd.packadd("package-info.nvim")
require("package_info").setup({
  fast_registry = true,
  -- managers = { ["/absolute/path/to/project"] = "yarn@4" },
})
```

The plugin uses only its own `package_info` namespace and does not depend on host configuration modules.
The Node helper sources, pinned dependencies and tests are included in this folder.
The helper runtime and registry cache stay under `stdpath("data")/package-info`, outside the plugin source.
Highlights follow `ColorScheme` events without depending on the host configuration.

`setup()` replaces the previous configuration and registrations. An empty `managers` table clears
overrides; omitted options return to their defaults. Invalid options are ignored with a warning.
Set `fast_registry = false` to use manager CLI checks for every project.
`require("package_info").teardown()` removes owned commands/autocommands, clears annotations and caches,
cancels requests/timers and stops helper/bootstrap processes. Calling it repeatedly is safe; call `setup()`
to enable the plugin again. The public Lua API also exposes `refresh(buf?, force?)`, `info()` and `status()`.

## Configuration

All options are optional. Nested tables accept partial overrides; each `setup()` starts from fresh defaults.
Unknown keys and invalid fields produce warnings and keep the relevant defaults. Empty lists replace defaults.
All durations below are in milliseconds; limits must be integers. Defaults:

```lua
require("package_info").setup({
  managers = {},
  fast_registry = true,
  auto_refresh = { on_enter = true, on_save = true },
  sections = { "dependencies", "devDependencies", "optionalDependencies", "peerDependencies" },
  exclude = { packages = {}, projects = {} },
  timeouts = { registry = 15000, manager = 5000, helper = 5000, bootstrap = 120000 },
  concurrency = { http = 32, http_per_project = 16, cli = 4, cli_per_project = 2 },
  cache = {
    ttl = 900000, retry = 30000,
    memory_limit = 2000, cli_limit = 1000,
    disk = true, disk_limit = 2000, cleanup_interval = 60000,
    client_ttl = 900000, client_limit = 128,
  },
  display = {
    enabled = true,
    statuses = { "installed", "update", "major", "unavailable", "not_found", "unsupported", "error" },
    icons = { installed = "󰏖", update = "󰚰", error = "󰂡" },
    prefix = "  ", virt_text_pos = "eol",
    float = { border = "rounded", focusable = true }, -- optional max_width, max_height
  },
})
```

- `auto_refresh = false` disables both triggers; a table controls them independently. Manual refresh and
  buffer toggling remain available. Editing and configuration changes still invalidate stale annotations.
- `sections` selects declaration sections before manager/registry checks. An empty list checks no dependencies.
- `exclude.packages` matches declaration names and npm alias targets with full-name glob patterns (`*`, `?`);
  other characters are literal. For example, `"@private/*"` excludes a scope. `exclude.projects` contains
  absolute directory paths and excludes their entire subtrees. Use canonical paths; `~` is not expanded.
- `timeouts.registry` applies to HTTP requests and registry CLI commands. `manager` applies to manager version,
  configuration and PnP processes, plus the Node version probe. `helper` covers local helper requests;
  streamed checks receive a deadline derived from the dependency count and configured request timeouts.
  `bootstrap` is the npm helper installation timeout. Timeout values must be positive.
- `concurrency` sets global and per-workspace HTTP/CLI limits. Lower manager HTTP limits are still respected;
  the global limit also constrains the per-workspace limit. Values must be positive.
- `cache.ttl` controls metadata and manager-version cache lifetimes; `retry` controls error backoff, including
  helper/manager failures. Zero disables the corresponding reuse/backoff. `memory_limit` bounds Node metadata,
  `cli_limit` bounds Lua CLI metadata; zero disables retention. `disk = false` disables metadata file reads,
  writes and cleanup without deleting existing files. `disk_limit = 0` also disables disk use.
  `cleanup_interval = 0` sweeps on each disk operation. Registry clients have separate positive
  `client_ttl` and `client_limit` values, so disabling metadata reuse still permits registry checks.
- `display.enabled = false` hides annotations while checks and details remain available. `statuses` selects
  visible annotation categories; a hidden update/problem can fall back to the installed version when
  `installed` is enabled. An empty list hides all annotations. Empty icon strings enable plain text.
  `virt_text_pos` accepts `"eol"`, `"eol_right_align"` or `"right_align"`. Floating details/status windows accept
  `border` (`none`, `single`, `double`, `rounded`, `solid`, `shadow`), `focusable` and positive `max_width`/`max_height`.

| Command                | Action                                                  |
| ---------------------- | ------------------------------------------------------- |
| `:PackageInfo`         | Details for declarations on the cursor line             |
| `:PackageInfoRefresh`  | Recheck the saved manifest, using the registry cache    |
| `:PackageInfoRefresh!` | Bypass cache/backoff and retry a failed helper          |
| `:PackageInfoToggle`   | Toggle annotations and automatic checks for this buffer |
| `:PackageInfoStatus`   | Helper, manager, workspace, request state and errors    |

Annotations show the actual installed version as soon as local inspection finishes. Registry results arrive
incrementally and replace it with an update within the declared range, a newer `latest` outside it, or a problem.
The first annotation render is immediate; subsequent updates are coalesced within 16 ms per buffer.
Each flush uses the latest valid state and skips unchanged annotation text/highlights. Editing, disabling,
replacing or closing a buffer cancels its pending render, as does plugin teardown.
Details distinguish the declaration, actual installed version, maximum satisfying version (`wanted`),
and the registry's `latest` tag. Missing installations stay unknown, including optional/peer dependencies.
The latest tag is informational; overrides and resolutions may change what a future install chooses.
Prereleases and tag declarations do not get unrelated stable-version suggestions.

Workspaces are recognized through npm/Yarn `workspaces` or `pnpm-workspace.yaml` membership patterns.
Installed versions come from package-local or workspace-hoisted `node_modules` (including symlinks),
or the issuer's PnP API through `yarn node`. Lockfile versions are never treated as installed versions.
Ranges, exact versions, tags and `npm:` aliases are compared. `workspace:`, `file:`, `link:` and `portal:`
are local; Git, URL, catalog and patch specifications currently have explicit limited support.

Manager precedence is a configured override, the nearest applicable `packageManager`, then lockfiles.
Conflicting lockfiles without an explicit choice produce an error. With no markers, npm is used.
Pass package or workspace-root overrides to `setup()`:

```lua
require("package_info").setup({
  managers = { ["/absolute/path/to/project"] = "yarn@4" },
})
```

One persistent Node helper checks registries directly through the installed npm's transport, with at most
32 HTTP requests globally and 16 per workspace, respecting lower manager connection limits.
npm configuration uses npm's native reader;
Yarn/pnpm export their effective settings once per configuration. Default Yarn settings need no separate readers.
Scope registries, authentication, proxy and TLS settings are preserved. Custom Yarn plugins or host-specific
network settings use the manager CLI for compatibility; CLI checks run at most four processes globally and
two per workspace, with Yarn 2–4 batching up to eight packages from the same scope.

Registry metadata is cached in memory and on disk for 15 minutes, including across Neovim restarts.
The disk cache contains only versions, dist-tags and timestamps, with private directory/file permissions.
Credentials and registry URLs are never persisted. Errors back off in memory for 30 seconds.
The helper's metadata memory cache retains at most 2000 entries, including reads from disk.
During cache activity, a directory sweep runs at most once per minute, removes expired/corrupt metadata
and retains the newest 2000 files. An expired or corrupt requested file is also removed immediately.
Registry clients expire after 15 minutes without use and are limited to 128 entries; a changed configuration
replaces the previous client for that package directory. Evicted clients are configured again automatically.
Manifest/lockfile changes refresh installed versions and comparisons while retaining reusable metadata;
CLI metadata keys use the registry configuration fingerprint and target package, independently of declaration
ranges. A range edit recomputes `wanted`/`latest` from cached versions; registry/auth/environment, manager,
package-directory or workspace changes isolate those entries. Forced refresh and normal cache expiry still apply.
rc and environment changes invalidate registry clients and their cache. Registry requests time out after
15 seconds; local manager/PnP lookups after five seconds.
Editing, disabling or closing a buffer cancels its checks
and hides annotations; stale responses cannot restore them. Cancellation also discards pending registry
configuration and its late result. Invalid or duplicate-key JSON is skipped.
Common configuration/auth/network errors appear once in the buffer and in status; raw command output
and credentials are never shown.

## Architecture and types

Both runtimes separate domain logic from external effects:

- `lua/package_info/core/`: configuration, manifest facts, cache policy, request validity, protocol validation,
  presentation, helper lifecycle, process queue and registry orchestration. These modules have no `vim` dependency.
- `lua/package_info/controller.lua`: an instance owns buffer state and coordinates injected adapters.
- `lua/package_info/integrations/`: Neovim buffers/UI/events, Tree-sitter, processes, timers, bootstrap and NDJSON IO.
  `init.lua` exposes the configured instance through the public API.
- `scripts/core/`: declaration/version comparison, workspace membership, manager selection, metadata/cache validation,
  protocol and configuration transformations. No project filesystem access or network requests.
- `scripts/controller.cjs`: injected HTTP queue/cache and helper request dispatcher.
- `scripts/integrations/`: project filesystem/PnP inspection, manager configuration, private disk cache and stdio.
  `scripts/index.cjs` wires these adapters and preserves the `--pnp` entry point.

Lua contracts live in `lua/package_info/types.lua`; Node contracts live in `scripts/types.d.ts` and JSDoc.
External JSON starts as `unknown` and is checked at protocol, registry and disk-cache boundaries.
Runtime installation copies the explicit list in `integrations/runtime_files.lua`; update it when adding helper modules.
Tests create their own controller/adapter instances; mutable state is not part of the public facade.

## Running tests

Run from this plugin's root directory. The tests resolve paths relative to their own files, so the plugin
can also be copied elsewhere and tested independently of the enclosing configuration.
Install test dependencies in an isolated directory:

```sh
mkdir -p /tmp/nvim-package-info-runtime
cp scripts/package{,-lock}.json /tmp/nvim-package-info-runtime/
(cd /tmp/nvim-package-info-runtime && npm ci --ignore-scripts --no-audit --no-fund)
NODE_PATH=/tmp/nvim-package-info-runtime/node_modules node --test tests/*.test.cjs
luajit tests/core.lua
luajit tests/controller.lua
nvim --clean --headless -i NONE -l tests/core.lua
nvim --clean --headless -i NONE -l tests/controller.lua
nvim --clean --headless -i NONE -l tests/adapter.lua
PACKAGE_INFO_TEST_RUNTIME=/tmp/nvim-package-info-runtime nvim --clean --headless -i NONE -l tests/nvim.lua
PACKAGE_INFO_TEST_RUNTIME=/tmp/nvim-package-info-runtime nvim --clean --headless -i NONE -l tests/nvim_network.lua
```

Check LuaCATS with the installed Lua language server (Mason's default location is detected;
set `LUA_LS` to override it):

```sh
nvim --clean --headless -i NONE -l tests/types_check.lua
```

Check all helper sources and Node tests with strict TypeScript `checkJs`. Development dependencies stay
outside the production helper runtime:

```sh
mkdir -p /tmp/package-info-type-runtime
cp tests/package{,-lock}.json /tmp/package-info-type-runtime/
(cd /tmp/package-info-type-runtime && npm ci --ignore-scripts --no-audit --no-fund)
PACKAGE_INFO_TYPE_RUNTIME=/tmp/package-info-type-runtime node tests/types_check.cjs
```

The Neovim tests find the JSON Tree-sitter parser under `stdpath("data")/site`; set
`PACKAGE_INFO_TEST_PARSER_RTP` if it is installed elsewhere.
They use that parser and the real Node helper with simulated manager
responses. They cover queue limits, cancellation, cache/backoff, duplicate declarations, errors, UI,
theme callbacks and helper restarts. The network integration test verifies credential changes,
auth backoff, persistent cache after a helper restart and forced refresh using a local HTTP registry with a synthetic
private-scope token; set `PACKAGE_INFO_REAL_MANAGER` to `npm`, `pnpm`, `yarn1` or `yarn` to use the actual
manager instead of simulated Yarn config exports. These fixtures use npm 11.19.0, pnpm 10.23.0,
Yarn 1.22.22 or Yarn 4.18.0 respectively; managers must already be available (no Corepack downloads).
Node tests cover semver, adapters, project contexts, hoisting, symlinks,
a simulated PnP API, native npm configuration, parallelism, persistent cache and partial registry failures.
They also check cancellation isolation between buffers, malformed registry metadata, disabled networking
and failure to write the disk cache.
Tests do not change existing projects.
Pure Lua tests additionally run with `vim` removed and cover configuration replacement, cache expiration,
manifest facts, protocol validation, formatting, bootstrap generations, deadlines, process slot ownership,
annotation coalescing, unchanged render suppression and cancellation of delayed renders.
CLI integration tests verify metadata reuse across range edits and invalidation after registry configuration changes.
Native adapter tests cover nested duplicate keys, registration ownership, rollback and repeated setup/teardown.
