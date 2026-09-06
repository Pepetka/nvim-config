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
map("x", "<leader>P", [=["_dP]=], map_opts("Edit: Paste over selection without losing yanked text"))
map({ "n", "v" }, "<leader>D", [=["_d]=], map_opts("Edit: Delete without yanking"))
map({ "n", "v" }, "<leader>C", [=["_c]=], map_opts("Edit: Change without yanking"))

map("n", "<leader>/", "gcc", map_opts("Edit: Toggle comment line", { remap = true }))
map("v", "<leader>/", "gc", map_opts("Edit: Toggle comment selection", { remap = true }))

map("v", "J", ":m '>+1<CR>gv=gv", map_opts("Edit: Move selection down"))
map("v", "K", ":m '<-2<CR>gv=gv", map_opts("Edit: Move selection up"))

map("v", "<", "<gv", map_opts("Edit: Unindent and keep selection"))
map("v", ">", ">gv", map_opts("Edit: Indent and keep selection"))

map("n", "gp", "printf('`[%s`]', getregtype()[0])", map_opts("Edit: Reselect last pasted area", { expr = true }))
map("n", "YY", "<cmd>%y+<CR>", map_opts("Edit: Copy whole file to system clipboard"))

-- ═══════════════════════════════════════════════════════════════
--  Navigation
-- ═══════════════════════════════════════════════════════════════
map("n", "<C-d>", "<C-d>zz", map_opts("Navigate: Scroll down and center cursor"))
map("n", "<C-u>", "<C-u>zz", map_opts("Navigate: Scroll up and center cursor"))

map("n", "n", "nzzzv", map_opts("Navigate: Next search result and center"))
map("n", "N", "Nzzzv", map_opts("Navigate: Previous search result and center"))

-- ═══════════════════════════════════════════════════════════════
--  Search
-- ═══════════════════════════════════════════════════════════════
map("n", "<ESC>", "<cmd>nohl<cr>", map_opts("Navigate: Clear search highlighting"))
map("n", "<leader>rr", ":%s/<C-r><C-w>//g<Left><Left>", map_opts("Navigate: Replace word under cursor"))

-- ═══════════════════════════════════════════════════════════════
--  Buffer
-- ═══════════════════════════════════════════════════════════════
map("n", "<leader>w", "<cmd>wa<cr>", map_opts("Buffer: Save all buffers"))
map("n", "<Tab>", "<cmd>bnext<cr>", map_opts("Buffer: Next buffer"))
map("n", "<S-Tab>", "<cmd>bprevious<cr>", map_opts("Buffer: Previous buffer"))

-- ═══════════════════════════════════════════════════════════════
--  Config / Meta
-- ═══════════════════════════════════════════════════════════════
map("n", "<leader>re", "<cmd>restart<cr>", map_opts("General: Restart Neovim"))
map("n", "<leader>rs", "<cmd>source %<cr>", map_opts("General: Source current file"))
map("n", "<leader>lT", "<cmd>TsLspSwitch<cr>", map_opts("LSP: Switch TypeScript server"))

-- ═══════════════════════════════════════════════════════════════
--  Toggle options
-- ═══════════════════════════════════════════════════════════════
-- Set a window-local option in all existing windows and as the default for new ones.
---@param name string window-local option name
---@param value boolean
local function set_win_option_global(name, value)
  vim.go[name] = value
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative == "" then -- skip floating windows
      vim.wo[win][name] = value
    end
  end
end

---@param name string window-local option name
---@param label string option label for the notification
local function toggle_win_option(name, label)
  local enabled = not vim.wo[name]
  set_win_option_global(name, enabled)
  vim.notify(label .. " " .. (enabled and "enabled" or "disabled"), vim.log.levels.INFO)
end

map("n", "<leader>un", function()
  toggle_win_option("number", "Line numbers")
end, map_opts("General: Toggle line numbers"))
map("n", "<leader>ur", function()
  toggle_win_option("relativenumber", "Relative numbers")
end, map_opts("General: Toggle relative numbers"))
map("n", "<leader>us", function()
  toggle_win_option("spell", "Spell check")
end, map_opts("Toggle: Spell check"))
map("n", "<leader>ui", function()
  local enabled = not vim.lsp.inlay_hint.is_enabled()
  vim.lsp.inlay_hint.enable(enabled)
  vim.notify("Inlay hints " .. (enabled and "enabled" or "disabled"), vim.log.levels.INFO)
end, map_opts("LSP: Toggle inlay hints"))

local function toggle_wrap()
  local enabled = not vim.wo.wrap
  set_win_option_global("wrap", enabled)
  vim.opt.linebreak = true
  if enabled then
    map("n", "j", "gj", map_opts("Navigate: Move down by visual line"))
    map("n", "k", "gk", map_opts("Navigate: Move up by visual line"))
  else
    pcall(vim.keymap.del, "n", "j")
    pcall(vim.keymap.del, "n", "k")
  end
  vim.notify("Wrap " .. (enabled and "enabled" or "disabled"), vim.log.levels.INFO)
end

map("n", "<leader>uw", toggle_wrap, map_opts("General: Toggle word wrap"))

map("n", "j", "gj", map_opts("Navigate: Move down by visual line"))
map("n", "k", "gk", map_opts("Navigate: Move up by visual line"))

-- ═══════════════════════════════════════════════════════════════
--  Folds
-- ═══════════════════════════════════════════════════════════════
map("n", "<leader>z", "za", map_opts("Navigate: Toggle fold under cursor"))
map("n", "<leader>Z", "zA", map_opts("Navigate: Toggle fold recursively"))
map("n", "<leader>zo", "zR", map_opts("Navigate: Open all folds"))
map("n", "<leader>zc", "zM", map_opts("Navigate: Close all folds"))

-- ═══════════════════════════════════════════════════════════════
--  Insert mode cursor movement
-- ═══════════════════════════════════════════════════════════════
map("i", "<C-b>", "<ESC>^i", map_opts("Edit: Move to beginning of line"))
map("i", "<C-e>", "<End>", map_opts("Edit: Move to end of line"))
map("i", "<C-h>", "<Left>", map_opts("Edit: Move left"))
map("i", "<C-l>", "<Right>", map_opts("Edit: Move right"))

-- ═══════════════════════════════════════════════════════════════
--  External
-- ═══════════════════════════════════════════════════════════════
map("n", "gx", function()
  vim.ui.open(vim.fn.expand("<cfile>"))
end, map_opts("General: Open URL or file under cursor"))
