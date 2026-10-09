local cheatsheet = require("cheatsheet")
local map_opts = require("utils.map_opts")

---@type CheatsheetConfigPartial
local options = {
  group_rules = {
    { pattern = "^FZF:", group = "find", icon = " " },
    { pattern = "^Git:", group = "git", icon = "󰊢 " },
    { pattern = "^LSP:", group = "lsp", icon = "󰒕 " },
    { pattern = "^DAP:", group = "debug", icon = " " },
    { pattern = "^Tree:", group = "tree", icon = "󰙅 " },
    { pattern = "^Trouble:", group = "trouble", icon = "󰁙 " },
    { pattern = "^Inline diagnostic:", group = "diagnostics", icon = "󰁙 ", prefix = "Inline diagnostic:" },
    { pattern = "^Buffer:", group = "buffer", icon = "󰓩 " },
    { pattern = "^AI:", group = "ai", icon = "󰚩 " },
    { pattern = "^Edit:", group = "edit", icon = "󰦨 " },
    { pattern = "^Navigate:", group = "navigate", icon = "󰆹 " },
    { pattern = "^General:", group = "general", icon = "󰌵 " },
    { pattern = "^Toggle:", group = "toggle", icon = " " },
    { pattern = "^Cheatsheet:", group = "cheatsheet", icon = "󰌌 " },
  },

  exclude = { desc_patterns = { "^Lua function", "^MiniPairs" } },
  layout = { key_gap = 4, mapping_spacing = 1, group_spacing = 2 },
  sort_groups = {
    "find",
    "git",
    "lsp",
    "debug",
    "tree",
    "buffer",
    "trouble",
    "diagnostics",
    "ai",
    "edit",
    "navigate",
    "general",
    "toggle",
    "cheatsheet",
    "other",
  },
}

cheatsheet.setup(options)

vim.keymap.set("n", "<leader>ch", cheatsheet.toggle, map_opts("Cheatsheet: Toggle"))
