local map = vim.keymap.set
local map_opts = require("utils.map_opts")

-- ═══════════════════════════════════════════════════════════════
--  Leader keys
-- ═══════════════════════════════════════════════════════════════
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- ═══════════════════════════════════════════════════════════════
--  General
-- ═══════════════════════════════════════════════════════════════
map({ "n", "v" }, ";", ":", map_opts("General: Enter command mode", { silent = false }))

-- ═══════════════════════════════════════════════════════════════
--  Text editing
-- ═══════════════════════════════════════════════════════════════
map("x", "<leader>P", [=["_dP]=], map_opts("Text: Paste over selection without losing yanked text"))
map({ "n", "v" }, "<leader>D", [=["_d]=], map_opts("Text: Delete without yanking"))
map({ "n", "v" }, "<leader>C", [=["_c]=], map_opts("Text: Change without yanking"))

map("n", "<leader>/", "gcc", map_opts("Text: Toggle comment line", { remap = true }))
map("v", "<leader>/", "gc", map_opts("Text: Toggle comment selection", { remap = true }))

map("v", "J", ":m '>+1<CR>gv=gv", map_opts("Text: Move selection down"))
map("v", "K", ":m '<-2<CR>gv=gv", map_opts("Text: Move selection up"))

map("v", "<", "<gv", map_opts("Text: Unindent and keep selection"))
map("v", ">", ">gv", map_opts("Text: Indent and keep selection"))

map("n", "gp", "printf('`[%s`]', getregtype()[0])", map_opts("Text: Reselect last pasted area", { expr = true }))
map("n", "YY", "<cmd>%y+<CR>", map_opts("Text: Copy whole file to system clipboard"))

-- ═══════════════════════════════════════════════════════════════
--  Navigation
-- ═══════════════════════════════════════════════════════════════
map("n", "<C-d>", "<C-d>zz", map_opts("Navigation: Scroll down and center cursor"))
map("n", "<C-u>", "<C-u>zz", map_opts("Navigation: Scroll up and center cursor"))

map("n", "n", "nzzzv", map_opts("Navigation: Next search result and center"))
map("n", "N", "Nzzzv", map_opts("Navigation: Previous search result and center"))

-- ═══════════════════════════════════════════════════════════════
--  Search
-- ═══════════════════════════════════════════════════════════════
map("n", "<ESC>", "<cmd>nohl<cr>", map_opts("Search: Clear search highlighting"))
map("n", "<leader>rr", ":%s/<C-r><C-w>//g<Left><Left>", map_opts("Search: Replace word under cursor"))

-- ═══════════════════════════════════════════════════════════════
--  Buffer
-- ═══════════════════════════════════════════════════════════════
map("n", "<leader>w", "<cmd>wa<cr>", map_opts("Buffer: Save all buffers"))
map("n", "<Tab>", "<cmd>bnext<cr>", map_opts("Buffer: Next buffer"))
map("n", "<S-Tab>", "<cmd>bprevious<cr>", map_opts("Buffer: Previous buffer"))

-- ═══════════════════════════════════════════════════════════════
--  Config / Meta
-- ═══════════════════════════════════════════════════════════════
map("n", "<leader>re", "<cmd>restart<cr>", map_opts("Config: Restart Neovim"))
map("n", "<leader>rs", "<cmd>source %<cr>", map_opts("Config: Source current file"))

-- ═══════════════════════════════════════════════════════════════
--  Toggle options
-- ═══════════════════════════════════════════════════════════════
map("n", "<leader>un", "<cmd>set nu!<CR>", map_opts("Toggle: Line numbers"))
map("n", "<leader>ur", "<cmd>set rnu!<CR>", map_opts("Toggle: Relative numbers"))

-- ═══════════════════════════════════════════════════════════════
--  Folds
-- ═══════════════════════════════════════════════════════════════
map("n", "<leader>z", "za", map_opts("Folds: Toggle fold under cursor"))
map("n", "<leader>Z", "zA", map_opts("Folds: Toggle fold recursively"))
map("n", "<leader>zo", "zR", map_opts("Folds: Open all folds"))
map("n", "<leader>zc", "zM", map_opts("Folds: Close all folds"))

-- ═══════════════════════════════════════════════════════════════
--  Insert mode cursor movement
-- ═══════════════════════════════════════════════════════════════
map("i", "<C-b>", "<ESC>^i", map_opts("Insert: Move to beginning of line"))
map("i", "<C-e>", "<End>", map_opts("Insert: Move to end of line"))
map("i", "<C-h>", "<Left>", map_opts("Insert: Move left"))
map("i", "<C-l>", "<Right>", map_opts("Insert: Move right"))

-- ═══════════════════════════════════════════════════════════════
--  External
-- ═══════════════════════════════════════════════════════════════
map("n", "gx", function()
  vim.ui.open(vim.fn.expand("<cfile>"))
end, map_opts("External: Open URL or file under cursor"))
