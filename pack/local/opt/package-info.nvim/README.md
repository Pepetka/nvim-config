# package-info.nvim

A standalone Neovim plugin that checks saved `package.json` files on open and save.
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
  -- managers = { ["/absolute/path/to/project"] = "yarn@4" },
})
```

This plugin's Lua modules use only Neovim APIs and its own `package_info` namespace.
The Node helper sources, pinned dependencies and tests are included in this folder.
The helper runtime and registry cache stay under `stdpath("data")/package-info`, outside the plugin source.
Highlights follow `ColorScheme` events without depending on the host configuration.

| Command                | Action                                                  |
| ---------------------- | ------------------------------------------------------- |
| `:PackageInfo`         | Details for declarations on the cursor line             |
| `:PackageInfoRefresh`  | Recheck the saved manifest, using the registry cache    |
| `:PackageInfoRefresh!` | Bypass cache/backoff and retry a failed helper          |
| `:PackageInfoToggle`   | Toggle annotations and automatic checks for this buffer |
| `:PackageInfoStatus`   | Helper, manager, workspace, request state and errors    |

Annotations show the actual installed version as soon as local inspection finishes. Registry results arrive
incrementally and replace it with an update within the declared range, a newer `latest` outside it, or a problem.
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
Manifest/lockfile changes refresh installed versions and comparisons while retaining reusable metadata;
rc and environment changes invalidate registry clients and their cache. Registry requests time out after
15 seconds; local manager/PnP lookups after five seconds.
Editing, disabling or closing a buffer cancels its checks
and hides annotations; stale responses cannot restore them. Invalid or duplicate-key JSON is skipped.
Common configuration/auth/network errors appear once in the buffer and in status; raw command output
and credentials are never shown.

## Tests

Run from this plugin's root directory. The tests resolve paths relative to their own files, so the plugin
can also be copied elsewhere and tested independently of the enclosing configuration.
Install test dependencies in an isolated directory:

```sh
mkdir -p /tmp/nvim-package-info-runtime
cp scripts/package{,-lock}.json /tmp/nvim-package-info-runtime/
(cd /tmp/nvim-package-info-runtime && npm ci --ignore-scripts --no-audit --no-fund)
NODE_PATH=/tmp/nvim-package-info-runtime/node_modules node --test tests/*.test.cjs
PACKAGE_INFO_TEST_RUNTIME=/tmp/nvim-package-info-runtime nvim --clean --headless -i NONE -l tests/nvim.lua
PACKAGE_INFO_TEST_RUNTIME=/tmp/nvim-package-info-runtime nvim --clean --headless -i NONE -l tests/nvim_network.lua
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
