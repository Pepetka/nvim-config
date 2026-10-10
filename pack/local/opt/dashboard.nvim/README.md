# dashboard.nvim

A self-contained startup screen for Neovim >=0.12. Text, action menus and custom
blocks share one vertical layout. No external plugins, theme names, filesystem
cache or serialization of callbacks are required.

## Setup

```lua
vim.cmd.packadd("dashboard.nvim")
require("dashboard").setup({
  blocks = {
    { id = "title", type = "text", lines = { "Welcome" }, style = "Header" },
    {
      id = "menu",
      type = "actions",
      items = {
        { id = "files", label = "Find files", key = "f", run = "FzfLua files" },
        { id = "new", label = "New buffer", key = "n", run = "enew" },
      },
    },
    { id = "footer", type = "text", lines = function() return { os.date("%Y-%m-%d") } end },
  },
  layout = { gap = 1 },
})
```

The personal configuration provides its own seasonal header, commands, palette
and cheap `vim.pack` statistics. The plugin never requires host modules.

## Options and blocks

| Option | Default | Meaning |
| --- | --- | --- |
| `blocks` | `{}` | Ordered text, action or custom blocks. Lists replace previous lists. |
| `layout.horizontal` | `"center"` | `"left"`, `"center"` or `"right"`, aligning the shared canvas and lines within it. |
| `layout.vertical` | `"center"` | `"top"`, `"center"` or `"bottom"`. |
| `layout.gap` | `0` | Blank lines between nonempty blocks. |
| `layout.bottom_padding` | `0` | Space reserved below vertically aligned content. |
| `highlights` | `{}` | Semantic role overrides, or a callback returning overrides. |
| `autostart` | `true` | Open once on an empty interactive startup. |
| `hide_chrome` | `true` | Hide statusline, tabline and dashboard window's winbar. |
| `chrome.hide_statusline` | `hide_chrome` | Hide the global statusline while a dashboard is visible in the current tab. |
| `chrome.hide_tabline` | `hide_chrome` | Hide the global tabline independently of the statusline. |
| `chrome.hide_winbar` | `hide_chrome` | Hide only dashboard windows' winbars. |
| `navigation.wrap` | `true` | Wrap between the first and last actions; false clamps at the ends. |
| `navigation.highlight_selected` | `false` | Highlight the selected row's text using the `Selected` role. |
| `navigation.keys.next` | `{ "j", "<Down>" }` | Next-action keys; numeric counts are supported. |
| `navigation.keys.previous` | `{ "k", "<Up>" }` | Previous-action keys; numeric counts are supported. |
| `navigation.keys.activate` | `{ "<CR>" }` | Execute the selected action. |
| `map_opts` | Internal helper | Optional host function building described keymap options. |

The horizontal canvas uses the widest rendered line. Its position is rounded once,
so blocks keep their relative alignment when window width changes between odd and even cell counts.
When an inner margin cannot be divided evenly, centered lines prefer the right cell.

Spacing and widths are finite nonnegative integers and accept zero. Unknown
options, including block/item fields, invalid types and duplicate IDs are rejected. Invalid
setup reports an error without replacing the current configuration. Inputs and
defaults are copied; callbacks keep their closures.

Each block has a unique nonempty `id` containing letters, digits, underscores or
hyphens, and a `type`:

- **Text:** `lines` is a string list or `fun(context): string[]`; `style` defaults
  to `Text`. Empty lists contribute no spacing. Newlines inside a line are invalid.
  Display text, including labels, icons and custom lines, must use spaces instead
  of tabs because tab width changes with the rendered column. Key notation such
  as `<Tab>` remains supported.
- **Actions:** `items` is an item list or a synchronous provider. Each item has
  `id`, `label`, `run`, optional `icon` and `key`. `label_width` is a minimum width
  in screen cells; omitted uses the widest label. `spacing` defaults to one blank
  line between items. No trailing blank line is added.
- **Custom:** `render(context)` returns a `DashboardDocument`. Use this to add
  arbitrary text, styles and interactive rows without changing the renderer.

All three block types accept these optional fields:

| Field | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Boolean or `fun(context): boolean`, evaluated before the content provider. |
| `layout.align` | Global `layout.horizontal` | Line alignment inside the shared canvas. |
| `layout.offset_x` | `0` | Signed horizontal shift in screen cells, after alignment. |
| `layout.gap_before` | `0` | Additional blank lines before this block. |
| `layout.gap_after` | `0` | Additional blank lines after this block. |

Disabled and empty blocks do not contribute width or margins and do not reserve
action keys. Disabled blocks never invoke their content providers. Visibility
providers must return a boolean; an error or invalid result preserves the previous
screen. Conditions are reevaluated on explicit refresh and geometry changes,
independently for each window, and never on theme events.

Margins are additive: the distance between two nonempty blocks is the first one's
`gap_after` plus global `layout.gap` plus the second one's `gap_before`. The first
block's leading margin and last block's trailing margin also count toward vertical
alignment. Horizontal offsets do not resize the shared canvas; negative shifts
clamp at the left edge, and positive shifts may extend beyond a small window.
Spans and action targets follow both horizontal and vertical shifts.

```lua
blocks = {
  {
    id = "header", type = "text", lines = { "Welcome" },
    enabled = function(context) return context.height >= 20 end,
    layout = { gap_after = 1 },
  },
  {
    id = "menu", type = "actions",
    layout = { align = "left", offset_x = 1 },
    items = { { id = "files", label = "Find files", key = "f", run = "FzfLua files" } },
  },
}
```

The context contains `win`, `source_buf`, `width` and `height`. Source identity is
preserved across refreshes and splits. Providers execute synchronously: lengthy
data collection belongs outside rendering, followed by an explicit `refresh()`.

Custom documents contain `lines`, `spans` and `targets` lists. Spans specify
zero-based `row`, inclusive `start_col`, exclusive `end_col` and semantic `style`;
columns are **byte offsets** on UTF-8 character boundaries. Targets specify `id`, zero-based `row`, byte `col`,
optional `key`, and `run`. Target IDs are unique within each block. The composer
assigns `block_id` and shifts coordinates; never pre-apply screen padding.

```lua
---@type DashboardCustomBlock
local project = {
  id = "project",
  type = "custom",
  render = function(context)
    return {
      lines = { "Current project" },
      spans = { { row = 0, start_col = 0, end_col = 15, style = "Project" } },
      targets = {
        { id = "open", row = 0, col = 0, key = "p", run = "pwd" },
      },
    }
  end,
}
```

Actions are Ex commands or `fun(context)`. Strings are never evaluated as Lua.
Keys are normalized by Neovim and must be unique across visible actions and the
configured navigation keys. Prefix collisions such as `f`/`ff` are rejected because
mappings execute without waiting. Navigation lists replace defaults per role;
an empty list disables that role's mappings and releases its keys for actions.
Selection follows the block/item identity across updates, falling
back to the first item when that identity disappears.

```lua
navigation = {
  wrap = false,
  highlight_selected = true,
  keys = { next = { "<Tab>" }, previous = { "<S-Tab>" }, activate = { "<CR>", "<Space>" } },
},
chrome = { hide_statusline = true, hide_tabline = false, hide_winbar = true },
```

Unspecified chrome flags inherit `hide_chrome`, which remains a shorthand for all
three flags. Explicit chrome flags take precedence. Each global panel captures its
current value when hidden and restores it independently when shown or when the last
dashboard in that tab disappears. Visible panels remain editable. A dashboard's
winbar similarly restores its latest visible value when toggled, while closing the
dashboard restores the source window's saved options.

## Theme

Default roles link to native groups: Header → Title, Text/Icon/Footer → Comment,
Key → Special, Selected → CursorLine. Selection highlighting is opt-in and covers
the chosen row's rendered text, excluding its leading layout spaces. It uses a
separate extmark namespace, so moving selection does not rewrite content or remove
block highlights. No colorscheme dependency is required. Role `Project` creates
the native group `DashboardProject`; custom blocks can introduce additional roles.
An override replaces the whole role definition, so fallback links never swallow
explicit colors.

```lua
highlights = function()
  local colors = require("utils.colors") -- host callback; not a plugin dependency
  return {
    Header = { fg = colors.focus, bold = true },
    Text = { fg = colors.muted },
    Project = { fg = colors.accent },
    Selected = { bg = colors.focus },
  }
end
```

The callback runs at setup and ColorScheme, without calling content providers or
rewriting buffer lines. Panel reconciliation runs after native theme consumers;
no host ColorScheme/FileType hooks are needed. A failed palette provider restores
the last successful role definitions and reports the error.

## API and lifecycle

- `setup(opts?)` replaces options with defaults plus the supplied values. Repeated
  calls update existing screens without duplicating handlers. Validation/provider
  failures preserve previous state; application failures roll back the documents
  and configuration.
- `show(win?)` opens in the current or specified ordinary window; `0` means current.
  Repeated show reuses that window's existing dashboard. Setup is required.
- `hide(win?)` restores its source buffer, or an ordinary empty buffer if the source
  was deleted. Repeated hide is safe and does not change focus.
- `refresh(win?)` rebuilds one screen, or all open screens when omitted. Each window
  updates independently: provider/application failures preserve its previous document,
  report the window ID, and allow other windows to refresh.
- `teardown()` closes owned screens and removes owned commands, handlers and styles.
  It is repeatable and permits another setup.
- `:Dashboard` calls `show()`. No global opening key is installed.

Automatic startup requires an attached UI, no file/directory arguments, no stdin,
and an unchanged empty unnamed regular buffer. Headless startup remains empty.
Scratch buffers are unlisted, unmodifiable, have no swap, and are wiped on exit.
External window closure/buffer wipe cleans up only owned resources. Native splits
receive an independent scratch buffer and layout.

Each window saves its original options. Global statusline/tabline visibility is
saved once while dashboards are visible in the current tab, then restored when
none remain visible. Other tabs and windows retain their buffers. Theme changes
and queued resize callbacks do not replace source identity or selected action.

Small windows use zero padding when content does not fit; wrapping stays disabled
and native scrolling keeps the selected row accessible. Unchanged documents skip
buffer writes, and refreshes reuse unchanged mappings. Resize only refreshes windows
whose geometry changed; explicit refresh always invokes their providers. Ordinary
editor events skip dashboard work when no owned windows remain.
Each distinct string is measured once within a document build. The cache is
discarded before the next build, so refresh observes current display options.
Split discovery indexes owned buffers per scan, and repeated panel reconciliation
avoids writing unchanged hidden options.
Pending callbacks are cancelled on teardown. Opening/provider/action
errors are contained and reported; partially created resources are released.

## Architecture and verification

`core/` contains pure configuration, block formatting, layout, measurement caching, navigation and
style rules. `controller.new(adapter)` owns state without `vim` and invokes
providers before publishing documents. `integrations/nvim` owns native effects,
resource tracking, commands, mappings, options and extmarks. `init` is the public
facade and `types.lua` defines LuaCATS contracts for all layers.

Run from the plugin directory, or pass full test paths from the configuration root:

```sh
luajit tests/core.lua
luajit tests/controller.lua
for suite in nvim adapter startup types_check; do
  NVIM_LOG_FILE=/dev/null nvim --clean --headless -i NONE -l "tests/$suite.lua"
done
stylua --check .
```

Pure suites also run in Neovim with `vim` removed during execution. Native suites
cover real keys, panels, splits, tabs, styles, lifecycle, callbacks and failures.
Startup tests attach a real embedded UI and cover empty/file/directory startup,
disabled autostart, modified content, headless mode and stdin. LuaLS checks the
entire plugin and tests against native Neovim API types; errors and warnings fail.
Set `LUA_LS` if LuaLS is not on PATH or in Mason.

Host verification runs from the configuration root:

```sh
NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -n -l tests/dashboard.lua
NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -n -l tests/dashboard_types.lua
NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -n -l tests/theme.lua
NVIM_LOG_FILE=/dev/null nvim --headless -u ./init.lua -i NONE -n -c 'lua dofile("tests/theme_ui.lua")'
NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -n -l tests/theme_startup.lua
```

Host snapshots verify the old dashboard's visible layout at 120×50 and 140×60,
with action labels widened one cell to match both frame edges, excluding changing statistics
and invisible trailing whitespace. Theme startup
tests inspect every rendered frame. Full host theme tests require local sockets
for fzf-lua; no plugins are downloaded by the independent plugin suites.
The host LuaLS suite checks personal dashboard setup and its content/palette helpers
against the local plugin contracts without loading the full configuration.
