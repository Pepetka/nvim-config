local lint = require("lint")
local oxc = require("utils.oxc_config")

lint.linters_by_ft = {
  go = { "golangcilint" },
  python = { "ruff" },
  markdown = { "markdownlint" },
  sh = { "shellcheck" },
  bash = { "shellcheck" },
  zsh = { "shellcheck" },
}
local js_family = {}
for _, ft in ipairs(oxc.js_filetypes) do
  js_family[ft] = true
  lint.linters_by_ft[ft] = { "eslint_d" }
end

local generation = {}
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "FileType", "InsertLeave", "TextChanged" }, {
  group = vim.api.nvim_create_augroup("NvimLint", { clear = true }),
  callback = function(args)
    local buf = args.buf
    generation[buf] = (generation[buf] or 0) + 1
    local current = generation[buf]

    vim.defer_fn(function()
      if generation[buf] ~= current or not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      if vim.b[buf].bigfile or vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "" then
        return
      end

      local bufname = vim.api.nvim_buf_get_name(buf)
      if bufname:match("/node_modules/") then
        return
      end

      vim.api.nvim_buf_call(buf, function()
        if js_family[vim.bo[buf].filetype] then
          lint.try_lint(oxc.has_oxlint_config(bufname) and { "oxlint" } or { "eslint_d" })
        else
          lint.try_lint()
        end
      end)
    end, 250)
  end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
  group = "NvimLint",
  callback = function(args)
    generation[args.buf] = nil
  end,
})
