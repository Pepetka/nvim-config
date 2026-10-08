local cheatsheet = require("cheatsheet")
local map_opts = require("utils.map_opts")

cheatsheet.setup({
  group_rules = {
    { pattern = "^FZF:", group = "find", icon = " " },
    { pattern = "^Git:", group = "git", icon = "󰊢 " },
    { pattern = "^LSP:", group = "lsp", icon = "󰒕 " },
    { pattern = "^DAP:", group = "debug", icon = " " },
    { pattern = "^Tree:", group = "tree", icon = "󰙅 " },
    { pattern = "^Trouble:", group = "trouble", icon = "󰁙 " },
    { pattern = "^Buffer:", group = "buffer", icon = "󰓩 " },
    { pattern = "^AI:", group = "ai", icon = "󰚩 " },
    { pattern = "^Edit:", group = "edit", icon = "󰦨 " },
    { pattern = "^Navigate:", group = "navigate", icon = "󰆹 " },
    { pattern = "^General:", group = "general", icon = "󰌵 " },
    { pattern = "^Cheatsheet:", group = "cheatsheet", icon = "󰌌 " },
  },

  exclude = { groups = { "terminal (t)", "autopairs" } },
  sort_groups = {
    "find",
    "git",
    "lsp",
    "debug",
    "tree",
    "buffer",
    "trouble",
    "ai",
    "edit",
    "navigate",
    "general",
    "cheatsheet",
    "other",
  },
})

vim.keymap.set("n", "<leader>ch", cheatsheet.toggle, map_opts("Cheatsheet: Toggle"))
