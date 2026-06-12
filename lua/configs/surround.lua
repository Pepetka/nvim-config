local surround = require("nvim-surround")

local config = {
  highlight = { duration = 500 },

  move_cursor = "begin",

  surrounds = {
    ["$"] = {
      add = { "${", "}" },
      find = "$%b{}",
      delete = "^($%b{})().-(}())$",
      change = {
        target = "^${().-()}$",
        replacement = function()
          return { "${", "}" }
        end,
      },
      label = "${…}",
    },

    ["l"] = {
      add = { "console.log(", ")" },
      find = "console%.log%b()",
      delete = "^(console%.log%()().-(%)())$",
      change = {
        target = "^(console%.log%()().-(%)())$",
        replacement = function()
          return { "console.log(", ")" }
        end,
      },
      label = "console.log(…)",
    },
  },
}
surround.setup(config)
