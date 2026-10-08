local buffers = require("tab_buffers")
local map_opts = require("utils.map_opts")

buffers.setup()

local mappings = {
  { "<Tab>", buffers.next, "Next buffer in tab" },
  { "<S-Tab>", buffers.previous, "Previous buffer in tab" },
  { "<leader>x", buffers.close, "Close current buffer in tab" },
  { "<leader>cx", buffers.close_others, "Close other buffers in tab" },
  {
    "<leader>bh",
    function()
      buffers.move(-1)
    end,
    "Move buffer left in tab",
  },
  {
    "<leader>bl",
    function()
      buffers.move(1)
    end,
    "Move buffer right in tab",
  },
}
for _, mapping in ipairs(mappings) do
  vim.keymap.set("n", mapping[1], mapping[2], map_opts("Buffer: " .. mapping[3]))
end
