local npm_info = require("npm-info")
local core = require("npm-info.core")
local cfg = require("npm-info.config")

local config = {
  show_installed = false,
  icons = {
    current = "󰏖",
    outdated = "󰚰",
    isLatest = "󰄬",
    beta = "󰂡",
    unstable = "󰂡",
  },
  hl_groups = {
    current = "Comment",
    isLatest = "NpmLatest",
    outdated = "NpmOutdated",
    beta = "DiagnosticWarn",
    unstable = "NpmBeta",
  },
}
npm_info.setup(config)

-- The default autocmd runs npm commands from Neovim's cwd, so inner
-- package.json files in a monorepo get no results. Replace it with an
-- autocmd that runs npm from the buffer's own directory.
pcall(vim.api.nvim_del_augroup_by_name, "npm-info")

local group = vim.api.nvim_create_augroup("npm-info-monorepo", { clear = true })

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
  group = group,
  pattern = "package.json",
  callback = function(event)
    local bufnr = event.buf
    vim.api.nvim_buf_clear_namespace(bufnr, core.namespace, 0, -1)

    local dependencies = core.parse_dependencies(bufnr)
    if #dependencies == 0 then
      return
    end

    local cwd = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":h")
    local user_config = cfg.get()

    if user_config.show_installed then
      vim.system({ "npm", "list", "--json", "--depth=0" }, { cwd = cwd }, function(out)
        vim.schedule(function()
          core.handle_npm_results(out, "list", dependencies, bufnr)
        end)
      end)
    end

    vim.system({ "npm", "outdated", "--json" }, { cwd = cwd }, function(out)
      vim.schedule(function()
        core.handle_npm_results(out, "outdated", dependencies, bufnr)
      end)
    end)
  end,
})
