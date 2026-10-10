-- Minimal independent configuration for embedded-UI startup tests.
local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
vim.opt.rtp:prepend(root)
vim.o.swapfile = false
if vim.env.DASHBOARD_TEST_MODIFIED == "1" then
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
end
require("dashboard").setup({
  autostart = vim.env.DASHBOARD_TEST_AUTOSTART ~= "0",
  blocks = { { id = "title", type = "text", lines = { "Startup dashboard" }, style = "Header" } },
})
