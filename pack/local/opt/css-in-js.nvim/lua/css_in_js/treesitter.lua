local M = {}

---Override the styled parser definition before nvim-treesitter installs parsers.
---@param install_info table nvim-treesitter parser install_info
function M.setup(install_info)
  local info = vim.deepcopy(install_info)
  local function apply()
    require("nvim-treesitter.parsers").styled.install_info = vim.deepcopy(info)
  end
  apply()
  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("CssInJsParser", { clear = true }),
    pattern = "TSUpdate",
    callback = apply,
  })
end

return M
