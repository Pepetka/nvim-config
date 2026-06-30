local translate = require("translate")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")

translate.setup({
  default = {
    command = "google",
    output = "floating",
    parse_before = "trim,natural",
    parse_after = "head",
  },
  preset = {
    output = {
      floating = {
        relative = "cursor",
        border = "rounded",
      },
    },
  },
  silent = true,
})

local function opts(desc)
  return map_opts("General: " .. desc)
end

map({ "n", "x" }, "<leader>tE", "<Cmd>Translate EN<CR>", opts("To English (popup)"))
map({ "n", "x" }, "<leader>tR", "<Cmd>Translate RU<CR>", opts("To Russian (popup)"))

map("x", "<leader>te", "<Cmd>Translate EN -output=replace<CR>", opts("To English (replace)"))
map("x", "<leader>tr", "<Cmd>Translate RU -output=replace<CR>", opts("To Russian (replace)"))
