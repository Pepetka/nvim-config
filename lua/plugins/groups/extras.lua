local add = vim.pack.add

add({
  "https://github.com/uga-rosa/translate.nvim",
  "https://github.com/brianhuster/live-preview.nvim",
})

require("configs.translate")
require("configs.live_preview")
vim.cmd.packadd("package-info.nvim")
require("configs.package_info")
require("configs.undotree")
