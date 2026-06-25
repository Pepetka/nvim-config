local fzf = require("fzf-lua")
local actions = require("fzf-lua.actions")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")

local config = {
  { "fzf-native", "hide" },
  winopts = {
    height = 0.85,
    width = 0.80,
    row = 0.35,
    col = 0.50,
    border = "rounded",
    fullscreen = false,
    backdrop = 60,

    preview = {
      default = "builtin",
      border = "border",
      wrap = "nowrap",
      hidden = "nohidden",
      layout = "flex",
      flip_columns = 120,
      vertical = "down:45%",
      horizontal = "right:60%",
      delay = 100,
    },
  },
  fzf_opts = {
    ["--ansi"] = "",
    ["--info"] = "inline-right",
    ["--height"] = "100%",
    ["--layout"] = "reverse",
    ["--border"] = "none",
    ["--cycle"] = "",
    ["--history"] = vim.fn.stdpath("data") .. "/fzf-lua-history",
  },
  fzf_colors = true,
  actions = {
    files = {
      ["default"] = actions.file_edit_or_qf,
      ["ctrl-s"] = actions.file_split,
      ["ctrl-v"] = actions.file_vsplit,
      ["ctrl-t"] = require("trouble.sources.fzf").actions.open,
      ["alt-i"] = actions.toggle_ignore,
      ["alt-h"] = actions.toggle_hidden,
    },
    buffers = {
      ["default"] = actions.buf_edit,
      ["ctrl-s"] = actions.buf_split,
      ["ctrl-v"] = actions.buf_vsplit,
      ["ctrl-x"] = { actions.buf_del, actions.resume },
    },
  },
  previewers = {
    bat = {
      cmd = "bat",
      args = "--style=numbers,changes --color=always",
      theme = "Coldark-Dark",
    },
    git_diff = {
      cmd_deleted = "git diff --color HEAD --",
      cmd_modified = "git diff --color HEAD",
      cmd_untracked = "git diff --color --no-index /dev/null",
      pager = "delta --width=$FZF_PREVIEW_COLUMNS",
    },
    builtin = {
      syntax = true,
      syntax_limit_l = 0,
      syntax_limit_b = 1024 * 1024,
      limit_b = 1024 * 1024 * 10,
      snacks_image = { enabled = true, render_inline = true },
    },
  },
  files = {
    prompt = "Files❯ ",
    multiprocess = true,
    file_icons = true,
    git_icons = true,
    color_icons = true,
    fd_opts = "--color=never --type f --hidden --follow --exclude .git --exclude node_modules --exclude .venv --exclude target --exclude dist --exclude build",
    rg_opts = "--color=never --files --hidden --follow -g '!.git' -g '!node_modules' -g '!.venv' -g '!target' -g '!dist' -g '!build'",
  },
  grep = {
    prompt = "Grep❯ ",
    input_prompt = "Grep For❯ ",
    multiprocess = true,
    file_icons = true,
    git_icons = true,
    color_icons = true,
    rg_opts = "--column --line-number --no-heading --color=always --smart-case --max-columns=512 --hidden -g '!.git' -g '!node_modules' -g '!.venv' -g '!target' -g '!dist' -g '!build'",
    rg_glob = true,
    glob_flag = "--iglob",
    glob_separator = "%s%-%-",
    actions = {
      ["ctrl-g"] = { actions.grep_lgrep },
    },
  },
  buffers = {
    prompt = "Buffers❯ ",
    file_icons = true,
    color_icons = true,
    sort_lastused = true,
  },
  oldfiles = {
    prompt = "History❯ ",
    cwd_only = false,
    stat_file = true,
    include_current_session = false,
  },
  git = {
    files = {
      prompt = "Git Files❯ ",
      cmd = "git ls-files --exclude-standard",
      multiprocess = true,
      file_icons = true,
      git_icons = true,
      color_icons = true,
    },
    status = {
      prompt = "Git Status❯ ",
      cmd = "git status -s",
      previewer = "git_diff",
      file_icons = true,
      git_icons = true,
      color_icons = true,
      actions = {
        ["right"] = { actions.git_unstage, actions.resume },
        ["left"] = { actions.git_stage, actions.resume },
      },
    },
    commits = {
      prompt = "Commits❯ ",
      cmd = "git log --pretty=oneline --abbrev-commit --color",
      preview = "git show --pretty='%Cred%H%n%Cblue%an%n%Cgreen%s' --color {1}",
      actions = {
        ["default"] = actions.git_checkout,
      },
    },
    bcommits = {
      prompt = "Buffer Commits❯ ",
      cmd = "git log --pretty=oneline --abbrev-commit --color",
      preview = "git show --pretty='%Cred%H%n%Cblue%an%n%Cgreen%s' --color {1}",
      actions = {
        ["default"] = actions.git_buf_edit,
        ["ctrl-s"] = actions.git_buf_split,
        ["ctrl-v"] = actions.git_buf_vsplit,
        ["ctrl-t"] = actions.git_buf_tabedit,
      },
    },
    branches = {
      prompt = "Branches❯ ",
      cmd = "git branch --all --color",
      preview = "git log --graph --pretty=oneline --abbrev-commit --color {1}",
      actions = {
        ["default"] = actions.git_switch,
      },
    },
  },
  lsp = {
    prompt_postfix = "❯ ",
    cwd_only = false,
    async_or_timeout = 5000,
    file_icons = true,
    git_icons = false,
    lsp_icons = true,
    ui_select = true,
    severity = "hint",
    icons = {
      ["Error"] = { icon = " ", color = "red" },
      ["Warning"] = { icon = " ", color = "yellow" },
      ["Information"] = { icon = "󰠠 ", color = "blue" },
      ["Hint"] = { icon = " ", color = "magenta" },
    },
  },
  code_actions = {
    prompt = "Code Actions❯ ",
    async_or_timeout = 5000,
    previewer = "codeaction",
  },
}
fzf.setup(config)

fzf.register_ui_select(function(opts, items)
  local min_h, max_h = 0.15, 0.70
  local h = math.min(math.max((#items + 4) / vim.o.lines, min_h), max_h)
  return {
    winopts = {
      title = opts.title or "Select",
      height = h,
      width = 0.60,
      row = 0.40,
      col = 0.50,
    },
  }
end)

-- ═══════════════════════════════════════════════════════════════
--  Global keymaps
-- ═══════════════════════════════════════════════════════════════
local function opts(desc)
  return map_opts("FZF: " .. desc)
end

map("n", "<leader>ff", function()
  fzf.files()
end, opts("Find files"))
map("n", "<leader>fg", function()
  fzf.live_grep()
end, opts("Live grep"))
map("n", "<leader>fb", function()
  fzf.buffers()
end, opts("Buffers"))
map("n", "<leader>fh", function()
  fzf.helptags()
end, opts("Help tags"))
map("n", "<leader>fr", function()
  fzf.resume()
end, opts("Resume last picker"))
map("n", "<leader>fo", function()
  fzf.oldfiles()
end, opts("Recent files"))

map("n", "<leader>gf", function()
  fzf.git_files()
end, opts("Git files"))
map("n", "<leader>gs", function()
  fzf.git_status()
end, opts("Git status"))
map("n", "<leader>gc", function()
  fzf.git_commits()
end, opts("Git commits"))
map("n", "<leader>gC", function()
  fzf.git_bcommits()
end, opts("Buffer commits"))
map("n", "<leader>gb", function()
  fzf.git_branches()
end, opts("Git branches"))

map("n", "<leader>ss", function()
  fzf.lsp_document_symbols()
end, opts("Document symbols"))
map("n", "<leader>sS", function()
  fzf.lsp_live_workspace_symbols()
end, opts("Workspace symbols"))
map("n", "<leader>sd", function()
  fzf.diagnostics_workspace()
end, opts("Workspace diagnostics"))

map("n", "<leader>fk", function()
  fzf.keymaps()
end, opts("Show all keymaps"))
