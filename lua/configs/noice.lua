local map = vim.keymap.set
local map_opts = require("utils.map_opts")
local noice = require("noice")

noice.setup({
  cmdline = {
    enabled = true,
    view = "cmdline_popup",
    opts = {},
    format = {
      cmdline = { pattern = "^:", icon = "", lang = "vim" },
      search_down = { kind = "search", pattern = "^/", icon = " ", lang = "regex" },
      search_up = { kind = "search", pattern = "^%?", icon = " ", lang = "regex" },
      filter = { pattern = "^:%s*!", icon = "󰳣", lang = "bash" },
      lua = {
        pattern = { "^:%s*lua%s+", "^:%s*lua%s*=%s*", "^:%s*=%s*" },
        icon = "",
        lang = "lua",
      },
      help = { pattern = "^:%s*he?l?p?%s+", icon = "" },
      input = { view = "cmdline_input", icon = "󰥻 " },
    },
  },

  messages = {
    enabled = true,
    view = "mini",
    view_error = "mini",
    view_warn = "mini",
    view_history = "messages",
    view_search = "mini",
  },

  popupmenu = {
    enabled = true,
    backend = "nui",
    kind_icons = {},
  },

  notify = {
    enabled = false,
    view = "notify",
  },

  lsp = {
    progress = {
      enabled = false,
    },
    override = {
      ["vim.lsp.util.convert_input_to_markdown_lines"] = false,
      ["vim.lsp.util.stylize_markdown"] = false,
      ["cmp.entry.get_documentation"] = false,
    },
    hover = {
      enabled = false,
      silent = false,
      view = nil,
      opts = {},
    },
    signature = {
      enabled = false,
      auto_open = {
        enabled = false,
        trigger = false,
        luasnip = false,
        throttle = 50,
      },
    },
    message = {
      enabled = false,
      view = "mini",
    },
    documentation = {
      view = "hover",
      opts = {
        lang = "markdown",
        replace = true,
        render = "plain",
        format = { "{message}" },
        win_options = { concealcursor = "n", conceallevel = 3 },
      },
    },
  },

  presets = {
    bottom_search = true,
    command_palette = true,
    long_message_to_split = true,
    inc_rename = false,
    lsp_doc_border = false,
  },

  routes = {
    {
      opts = { skip = true },
      filter = { event = "msg_show", kind = "search_count" },
    },
    {
      opts = { skip = true },
      filter = { event = "msg_show", find = "search hit" },
    },
    {
      view = "split",
      filter = { event = "msg_show", min_height = 20 },
    },
    {
      view = "mini",
      filter = { event = "lsp", kind = "message" },
    },
    {
      view = "mini",
      filter = { event = "msg_show", kind = { "", "echo", "echomsg" }, find = "%a" },
    },
  },

  views = {
    cmdline_popup = {
      position = {
        row = "20%",
        col = "50%",
      },
      size = {
        width = 60,
        height = "auto",
      },
      border = {
        style = "rounded",
        padding = { 0, 1 },
      },
      win_options = {
        winblend = 0,
        winhighlight = {
          Normal = "NormalFloat",
          FloatBorder = "FloatBorder",
          CursorLine = "PmenuSel",
          Search = "Search",
        },
      },
    },
    cmdline_popupmenu = {
      relative = "editor",
      position = {
        row = "20%",
        col = "50%",
      },
      size = {
        width = 60,
        height = "auto",
      },
      border = {
        style = "rounded",
        padding = { 0, 1 },
      },
      win_options = {
        winblend = 0,
        winhighlight = {
          Normal = "NormalFloat",
          FloatBorder = "FloatBorder",
          CursorLine = "PmenuSel",
          PmenuMatch = "PmenuMatch",
        },
      },
    },
    popupmenu = {
      relative = "editor",
      border = {
        style = "rounded",
        padding = { 0, 1 },
      },
      win_options = {
        winblend = 0,
        winhighlight = {
          Normal = "NormalFloat",
          FloatBorder = "FloatBorder",
          CursorLine = "PmenuSel",
          PmenuMatch = "PmenuMatch",
        },
      },
    },
    hover = {
      border = {
        style = "rounded",
        padding = { 0, 1 },
      },
      win_options = {
        winblend = 0,
        winhighlight = {
          Normal = "NormalFloat",
          FloatBorder = "FloatBorder",
        },
      },
    },
    signature = {
      border = {
        style = "rounded",
        padding = { 0, 1 },
      },
      win_options = {
        winblend = 0,
        winhighlight = {
          Normal = "NormalFloat",
          FloatBorder = "FloatBorder",
        },
      },
    },
    mini = {
      win_options = {
        winblend = 0,
        winhighlight = {
          Normal = "NormalFloat",
          FloatBorder = "FloatBorder",
        },
      },
    },
    split = {
      enter = true,
      size = "50%",
      win_options = {
        wrap = false,
      },
    },
    messages = {
      enter = true,
      size = "50%",
    },
  },
})

-- ═══════════════════════════════════════════════════════════════
--  Global keymaps
-- ═══════════════════════════════════════════════════════════════
local function opts(desc, params)
  return map_opts("General: " .. desc, params)
end

map("n", "<leader>nh", "<cmd>Noice history<cr>", opts("Open message history"))
map("n", "<leader>nd", "<cmd>Noice dismiss<cr>", opts("Dismiss notifications"))
