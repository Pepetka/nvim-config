local leap = require("leap")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")

leap.opts.preview = function(ch0, ch1, ch2)
  return not (ch1:match("%s") or (ch0:match("%a") and ch1:match("%a") and ch2:match("%a")))
end

-- ═══════════════════════════════════════════════════════════════
--  Global keymaps
-- ═══════════════════════════════════════════════════════════════
local function opts(desc)
  return map_opts("Navigate: " .. desc, { noremap = false })
end

map({ "n", "x", "o" }, "s", "<Plug>(leap)", opts("Jump"))

map({ "x", "o" }, "an", function()
  require("leap.treesitter").select({
    opts = require("leap.user").with_traversal_keys("n", "N"),
  })
end, opts("Select Treesitter node"))
