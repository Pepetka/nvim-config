local autotag = require("nvim-ts-autotag")

local config = {
  opts = {
    enable_close = true,
    enable_rename = true,
    enable_close_on_slash = true,
  },
  per_filetype = {
    ["markdown"] = {
      enable_close = false,
      enable_rename = false,
    },
  },
}
autotag.setup(config)
