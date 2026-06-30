local nvimtree = require("nvim-tree")
local nvimtree_api = require("nvim-tree.api")
local nvimtree_map = require("nvim-tree.api").map
local map = vim.keymap.set
local map_opts = require("utils.map_opts")

local function opts(desc, bufnr)
  return map_opts("Tree: " .. desc, { buffer = bufnr })
end

vim.api.nvim_create_autocmd("QuitPre", {
  desc = "Close nvim-tree window before quitting nvim",
  callback = function()
    local tree_wins = {}
    local floating_wins = {}
    local wins = vim.api.nvim_list_wins()
    for _, w in ipairs(wins) do
      local bufname = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
      if bufname:match("NvimTree_") ~= nil then
        table.insert(tree_wins, w)
      end
      if vim.api.nvim_win_get_config(w).relative ~= "" then
        table.insert(floating_wins, w)
      end
    end
    if 1 == #wins - #floating_wins - #tree_wins then
      for _, w in ipairs(tree_wins) do
        vim.api.nvim_win_close(w, true)
      end
    end
  end,
})

nvimtree_api.events.subscribe("FileCreated", function(file)
  vim.cmd("edit " .. vim.fn.fnameescape(file.fname))
end)

local function multi_operations(bufnr)
  local mark_move_j = function()
    nvimtree_api.marks.toggle()
    vim.cmd.normal({ "j", bang = true })
  end
  local mark_move_k = function()
    nvimtree_api.marks.toggle()
    vim.cmd.normal({ "k", bang = true })
  end

  local mark_trash = function()
    local marks = nvimtree_api.marks.list()
    if #marks == 0 then
      table.insert(marks, nvimtree_api.tree.get_node_under_cursor())
    end
    vim.ui.input({ prompt = string.format("Trash %s files/dirs? [y/n] ", #marks) }, function(input)
      if input == "y" then
        for _, node in ipairs(marks) do
          nvimtree_api.fs.trash(node)
        end
        nvimtree_api.marks.clear()
        nvimtree_api.tree.reload()
      end
    end)
  end

  local mark_remove = function()
    local marks = nvimtree_api.marks.list()
    if #marks == 0 then
      table.insert(marks, nvimtree_api.tree.get_node_under_cursor())
    end
    vim.ui.input({ prompt = string.format("Remove %s files/dirs? [y/n] ", #marks) }, function(input)
      if input == "y" then
        for _, node in ipairs(marks) do
          nvimtree_api.fs.remove(node)
        end
        nvimtree_api.marks.clear()
        nvimtree_api.tree.reload()
      end
    end)
  end

  local mark_copy = function()
    local marks = nvimtree_api.marks.list()
    if #marks == 0 then
      table.insert(marks, nvimtree_api.tree.get_node_under_cursor())
    end
    for _, node in ipairs(marks) do
      nvimtree_api.fs.copy.node(node)
    end
    nvimtree_api.marks.clear()
    nvimtree_api.tree.reload()
  end

  local mark_cut = function()
    local marks = nvimtree_api.marks.list()
    if #marks == 0 then
      table.insert(marks, nvimtree_api.tree.get_node_under_cursor())
    end
    for _, node in ipairs(marks) do
      nvimtree_api.fs.cut(node)
    end
    nvimtree_api.marks.clear()
    nvimtree_api.tree.reload()
  end

  local mark_move = function(copy)
    local marks = nvimtree_api.marks.list()
    if #marks == 0 then
      table.insert(marks, nvimtree_api.tree.get_node_under_cursor())
    end
    local file_src = marks[1].absolute_path
    local from_dir = vim.fn.fnamemodify(file_src, ":h") .. "/"

    vim.ui.input({ prompt = string.format("Move %s files to: ", #marks), default = from_dir }, function(input)
      if input then
        local to_dir = vim.fn.fnamemodify(input, ":h") .. "/"
        vim.fn.system({ "mkdir", "-p", to_dir })

        for _, node in ipairs(marks) do
          local file = node.absolute_path
          if copy then
            vim.fn.system({ "cp", "-R", file, to_dir })
          else
            vim.fn.system({ "mv", file, to_dir })
          end
        end

        nvimtree_api.marks.clear()
        nvimtree_api.tree.reload()
      end
    end)
  end

  map("n", "<Esc>", nvimtree_api.marks.clear, opts("Clear Marks", bufnr))
  map("n", "p", nvimtree_api.fs.paste, opts("Paste", bufnr))
  map("n", "J", mark_move_j, opts("Toggle Bookmark Down", bufnr))
  map("n", "K", mark_move_k, opts("Toggle Bookmark Up", bufnr))
  map("n", "x", mark_cut, opts("Cut File(s)", bufnr))
  map("n", "tr", mark_trash, opts("Trash File(s)", bufnr))
  map("n", "d", mark_remove, opts("Remove File(s)", bufnr))
  map("n", "c", mark_copy, opts("Copy File(s)", bufnr))
  map("n", "mv", function()
    mark_move(false)
  end, opts("Move To File(s)", bufnr))
  map("n", "cp", function()
    mark_move(true)
  end, opts("Copy To File(s)", bufnr))
end

local function vim_like_navigation(bufnr)
  nvimtree_map.on_attach.default(bufnr)

  local function edit_or_open()
    local node = nvimtree_api.tree.get_node_under_cursor()
    if not node then
      return
    end
    nvimtree_api.node.open.edit()
    if node.nodes == nil then
      nvimtree_api.tree.close()
    end
  end

  local function open_buffer_silent()
    nvimtree_api.node.open.edit()
    nvimtree_api.tree.focus()
  end

  map("n", "l", edit_or_open, opts("Open File or Folder", bufnr))
  map("n", "L", open_buffer_silent, opts("Open File Silently", bufnr))
  map("n", "h", nvimtree_api.node.navigate.parent_close, opts("Close Directory", bufnr))
  map("n", "H", nvimtree_api.tree.collapse_all, opts("Collapse", bufnr))
end

local function on_attach(bufnr)
  vim_like_navigation(bufnr)
  multi_operations(bufnr)
end

nvimtree.setup({
  disable_netrw = true,
  hijack_netrw = true,
  hijack_cursor = true,
  sync_root_with_cwd = true,
  prefer_startup_root = false,
  update_focused_file = {
    enable = true,
    update_root = {
      enable = false,
      ignore_list = {},
    },
  },
  sort = {
    sorter = "case_sensitive",
  },
  view = {
    width = { min = 30, max = 50 },
    side = "right",
    preserve_window_proportions = true,
    number = false,
    relativenumber = false,
    signcolumn = "yes",
  },
  renderer = {
    root_folder_label = false,
    highlight_git = "all",
    highlight_opened_files = "all",
    highlight_modified = "all",
    group_empty = true,
    indent_markers = { enable = true },
    icons = {
      show = {
        git = true,
        modified = true,
        diagnostics = true,
        folder_arrow = true,
      },
      glyphs = {
        default = "󰈚",
        folder = {
          default = "",
          empty = "",
          empty_open = "",
          open = "",
          symlink = "",
        },
        git = { unmerged = "" },
        modified = "●",
      },
    },
  },
  git = {
    enable = true,
    ignore = false,
    timeout = 1000,
  },
  modified = {
    enable = true,
  },
  diagnostics = {
    enable = false,
    show_on_dirs = true,
    show_on_open_dirs = true,
    icons = {
      hint = "󰠠",
      info = "",
      warning = "",
      error = "",
    },
  },
  filters = {
    dotfiles = false,
    custom = { ".cache", ".DS_Store" },
  },
  filesystem_watchers = {
    enable = true,
  },
  actions = {
    open_file = {
      quit_on_open = true,
      resize_window = true,
    },
  },
  ui = {
    confirm = {
      remove = false,
      trash = false,
    },
  },
  on_attach = on_attach,
})

map("n", "<leader>e", function()
  nvimtree_api.tree.open({ focus = true })
end, opts("Open file tree"))
map("n", "<C-n>", function()
  nvimtree_api.tree.toggle()
end, opts("Toggle file tree"))
