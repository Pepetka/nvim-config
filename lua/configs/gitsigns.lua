local gitsigns = require("gitsigns")
local map_opts = require("utils.map_opts")

gitsigns.setup({
  signs = {
    add = { text = "┃" },
    change = { text = "┃" },
    delete = { text = "_" },
    topdelete = { text = "‾" },
    changedelete = { text = "~" },
    untracked = { text = "┆" },
  },
  signs_staged = {
    add = { text = "┃" },
    change = { text = "┃" },
    delete = { text = "_" },
    topdelete = { text = "‾" },
    changedelete = { text = "~" },
    untracked = { text = "┆" },
  },
  signs_staged_enable = true,

  signcolumn = true,
  numhl = false,
  linehl = false,
  word_diff = false,

  watch_gitdir = {
    follow_files = true,
  },

  auto_attach = true,
  attach_to_untracked = true,

  current_line_blame = false,
  current_line_blame_opts = {
    virt_text = true,
    virt_text_pos = "eol",
    delay = 1000,
    ignore_whitespace = false,
    virt_text_priority = 100,
    use_focus = true,
  },
  current_line_blame_formatter = "<author>, <author_time:%R> - <summary>",

  sign_priority = 6,
  update_debounce = 100,
  status_formatter = nil,
  max_file_length = 40000,

  preview_config = {
    border = "rounded",
    style = "minimal",
    relative = "cursor",
    row = 0,
    col = 1,
  },

  -- ═══════════════════════════════════════════════════════════════
  --  Buffer-local keymaps
  -- ═══════════════════════════════════════════════════════════════
  on_attach = function(bufnr)
    local map = vim.keymap.set
    local function opts(desc)
      return map_opts("Git: " .. desc, { buffer = bufnr })
    end

    map("n", "]h", function()
      if vim.wo.diff then
        vim.cmd.normal({ "]c", bang = true })
      else
        gitsigns.nav_hunk("next")
      end
    end, opts("Next hunk"))

    map("n", "[h", function()
      if vim.wo.diff then
        vim.cmd.normal({ "[c", bang = true })
      else
        gitsigns.nav_hunk("prev")
      end
    end, opts("Previous hunk"))

    map("n", "<leader>hs", gitsigns.stage_hunk, opts("Stage hunk"))
    map("n", "<leader>hr", gitsigns.reset_hunk, opts("Reset hunk"))

    map("v", "<leader>hs", function()
      gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
    end, opts("Stage hunk"))
    map("v", "<leader>hr", function()
      gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
    end, opts("Reset hunk"))

    map("n", "<leader>hS", gitsigns.stage_buffer, opts("Stage buffer"))
    map("n", "<leader>hR", gitsigns.reset_buffer, opts("Reset buffer"))

    map("n", "<leader>hp", gitsigns.preview_hunk, opts("Preview hunk"))
    map("n", "<leader>hb", function()
      gitsigns.blame_line({ full = true })
    end, opts("Blame line"))
    map("n", "<leader>hB", gitsigns.toggle_current_line_blame, opts("Toggle line blame"))

    map("n", "<leader>hd", gitsigns.diffthis, opts("Diff this"))
    map("n", "<leader>hD", function()
      gitsigns.diffthis("~")
    end, opts("Diff this ~"))

    map({ "o", "x" }, "ih", ":<C-U>Gitsigns select_hunk<CR>", opts("Select hunk"))
  end,
})
