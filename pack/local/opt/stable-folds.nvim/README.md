# stable-folds.nvim

Local synchronous Tree-sitter folding for Neovim >=0.12. The plugin computes complete
fold boundaries once per buffer changedtick instead of using incremental native folding
levels that can temporarily close unrelated text while a parse is pending.

## Setup

```lua
vim.cmd.packadd("stable-folds.nvim")
local folds = require("stable_folds")
folds.setup({ filter = function(buf) return not vim.b[buf].bigfile end })
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = folds.foldexpr
```

Call `folds.attach(win?)` to set the expression and foldmethod in a window (`0` by default).
Install parsers and `folds` queries for the desired languages separately; missing parsers
and special buffers produce zero levels. `expr(line?)` returns a fold level for the current
buffer and window, using `vim.v.lnum` when no line is supplied.

The optional `filter(buf)` defaults to allowing regular buffers. Visual options, initial
foldlevel, foldcolumn, foldminlines and foldnestmax remain caller-owned; the host keeps
them in `lua/configs/stable_folds.lua`. The plugin does not require host helpers.

Moving header extmarks identify existing folds across edits, including formatter
replacements with unchanged unique headers. New folds do not inherit neighbouring
closed states. Refresh handlers run on TextChanged, InsertLeave and BufWritePost;
FileType and BufUnload clear the cached levels and header marks. Repeated setup replaces
handlers. No mappings, parsers or global fold options are installed by setup.

## Tests

```sh
NVIM_LOG_FILE=/tmp/stable-folds-nvim.log nvim --clean --headless -i NONE -l tests/nvim.lua
stylua --check .
```

Run from this plugin's root or pass an absolute script path. Tests use the installed Lua
parser and nvim-treesitter fold queries from `stdpath("data")/site` without loading the
host config. They cover boundaries, edits above closed folds, formatter replacements,
new neighbouring folds, missing parsers, caller filters, special buffers, cleanup and
repeated setup. Dependencies are never downloaded or changed.
