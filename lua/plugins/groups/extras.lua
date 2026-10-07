local add = vim.pack.add

add({
  "https://github.com/uga-rosa/translate.nvim",
  "https://github.com/brianhuster/live-preview.nvim",
  "https://github.com/pxnditxyr/npm-info.nvim",
})

require("configs.translate")
require("configs.live_preview")
require("configs.npm_info")
require("configs.undotree")
