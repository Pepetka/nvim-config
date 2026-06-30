local opt = vim.opt
local g = vim.g

g.netrw_banner = 0 -- Disable the banner at the top of netrw

opt.nu = true -- Show absolute line number for the current line
opt.relativenumber = true -- Show relative line numbers for easy motion
opt.numberwidth = 3 -- Minimum width of the number column
opt.cursorlineopt = "number" -- Highlight only the line number, not the whole line
opt.scrolloff = 8 -- Keep at least 8 lines visible above/below cursor
opt.sidescrolloff = 8 -- Keep at least 8 columns visible left/right of cursor
opt.colorcolumn = "120" -- Visual guide at column 120
opt.signcolumn = "yes" -- Always show the sign column (for git/diagnostics)
-- opt.guicursor = "" -- Use terminal default cursor style in all modes
opt.startofline = false -- Preserve horizontal cursor position on C-d/C-u

opt.tabstop = 2 -- Number of spaces a <Tab> counts for
opt.softtabstop = 2 -- Number of spaces inserted when hitting Tab in insert mode
opt.shiftwidth = 2 -- Number of spaces used for auto-indentation
opt.expandtab = true -- Convert tabs to spaces
opt.smartindent = true -- Smart auto-indenting when starting a new line
opt.shiftround = true -- Round indent to nearest multiple of shiftwidth

opt.backspace = "indent,eol,start" -- Natural backspace behavior in insert mode
opt.selection = "inclusive" -- Include the character under cursor in visual selection (Vim default)
opt.showmatch = false -- Disable native bracket jump; mini.pairs handles pairs
opt.matchtime = 0 -- No bracket highlight delay
opt.jumpoptions = "view" -- Preserve scroll position when jumping between locations
opt.whichwrap:append("<>[]hl") -- Allow h/l and arrows to cross line boundaries

opt.wrap = false -- Wrap lines that exceed window width
opt.showbreak = "↪ " -- Character to show at the start of wrapped lines
opt.linebreak = true -- Wrap lines at word boundaries, not mid-word
opt.smoothscroll = true -- Smooth scrolling for wrapped lines (Neovim 0.10+)
opt.synmaxcol = 500 -- Stop syntax highlighting after column 500 (performance)
opt.formatoptions:append("mM") -- Correctly break multi-byte characters (e.g. CJK)

opt.splitbelow = true -- Open horizontal splits below the current window
opt.splitright = true -- Open vertical splits to the right
opt.laststatus = 3 -- Use a single global statusline for all windows
opt.splitkeep = "screen" -- Keep screen position stable when opening/closing splits
opt.winminwidth = 5 -- Minimum window width to prevent accidental collapse

opt.ignorecase = true -- Ignore case in search patterns
opt.smartcase = true -- Override ignorecase if pattern contains uppercase
opt.inccommand = "split" -- Show preview of substitutions in a split window

opt.termguicolors = true -- Enable 24-bit RGB color support
opt.showmode = false -- Don't show mode indicator (-- INSERT --), statusline handles it
opt.title = true -- Set terminal window title to the current file name
opt.cmdheight = 0 -- Hide the command line when not in use
opt.winblend = 0 -- No transparency for floating windows
opt.pumheight = 10 -- Maximum number of items to show in the popup menu
opt.winborder = "rounded" -- Border style for floating windows
opt.pumborder = "rounded" -- Border for the completion popup menu

opt.list = true -- Show invisible characters defined in listchars
opt.listchars = {
  tab = "▸ ", -- Visual indicator for tabs
  trail = "·", -- Trailing spaces
  extends = "❯", -- Character shown when line overflows to the right
  precedes = "❮", -- Character shown when line overflows to the left
  nbsp = "␣", -- Non-breaking space
}
opt.fillchars = {
  fold = " ", -- Fill character for folded lines
  foldsep = " ", -- Separator between folds
  foldopen = "", -- Indicator for open folds
  foldclose = "", -- Indicator for closed folds
  vert = "│", -- Vertical split separator
  eob = " ", -- Remove ~ at end of buffer
  diff = "╱", -- Deleted lines in diff mode
}

opt.hidden = true -- Allow switching buffers without saving (no E37 error)

opt.swapfile = false -- Disable swap file creation
opt.backup = false -- Disable backup file creation
opt.writebackup = false -- Don't create temp backup before writing
opt.undofile = true -- Enable persistent undo across sessions
opt.undodir = vim.fn.stdpath("data") .. "/undodir" -- Directory to store undo files
opt.undolevels = 10000 -- Maximum number of undo levels

opt.completeopt = "menuone,noselect" -- Completion menu behavior (managed by blink.cmp)
opt.shortmess:append("csI") -- Suppress 'match 1 of 2' messages during completion
opt.autocomplete = false -- Disable native autocomplete; blink.cmp handles completion
opt.wildmenu = true -- Enhanced tab-completion menu in command line
opt.wildmode = "list:longest" -- Command-line completion: list matches & complete longest common
opt.wildignorecase = true -- Ignore case in command-line filename completion
opt.history = 500 -- Number of commands to keep in history

opt.clipboard:append("unnamedplus") -- Use system clipboard for all yank/delete/put
opt.isfname:append("@-@") -- Allow @ in file names (e.g. for SCP paths)

opt.updatetime = 250 -- Milliseconds to wait before triggering CursorHold (for LSP, git signs)
opt.timeoutlen = 500 -- Milliseconds to wait for a mapped sequence to complete
opt.ttimeoutlen = 0 -- Instant keycode response (no Escape delay)
opt.redrawtime = 10000 -- Prevent hangs during regex search in large files
opt.maxmempattern = 20000 -- More memory for pattern matching
opt.mouse = "a" -- Enable mouse in all modes
opt.virtualedit = "block" -- Allow cursor to move past end of line in visual block mode

opt.autoread = true -- Automatically re-read file if changed outside Neovim
opt.autowrite = true -- Automatically save before :next, :make, etc.
opt.confirm = true -- Ask for confirmation when quitting with unsaved changes

opt.grepprg = "rg --vimgrep --no-heading --smart-case" -- Use ripgrep for :grep
opt.grepformat = "%f:%l:%c:%m" -- Parse ripgrep output into quickfix format

opt.diffopt:append("linematch:40") -- Smarter inline diff alignment (Neovim 0.11+)
opt.conceallevel = 2 -- Hide markdown markup, links, etc. in supported filetypes

opt.modeline = false -- Ignore vim: directives in files (security hardening)

vim.opt.spell = false -- Enable spell checking
vim.opt.spelllang = "en_us,ru_ru" -- Spellcheck languages

-- TypeScript LSP selector: "vtsls" (stable, default) or "tsgo" (experimental native preview)
g.ts_lsp = "vtsls"

g.loaded_node_provider = 0
g.loaded_python3_provider = 0
g.loaded_perl_provider = 0
g.loaded_ruby_provider = 0
