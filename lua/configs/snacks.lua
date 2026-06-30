local snacks = require("snacks")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")
local colors = require("utils.colors")

local excluded = {
  filetypes = {
    "help",
    "dashboard",
    "TelescopePrompt",
    "TelescopeResults",
    "lazy",
    "mason",
    "notify",
    "lspinfo",
    "checkhealth",
    "man",
    "gitcommit",
    "",
  },
  buftypes = {
    "terminal",
    "nofile",
    "quickfix",
    "prompt",
  },
}

local function set_indent_hl()
  vim.api.nvim_set_hl(0, "SnacksIndent", { fg = colors.gutter })
  vim.api.nvim_set_hl(0, "SnacksIndentScope", { fg = colors.focus, bold = true })
end

snacks.setup({
  indent = {
    indent = {
      char = "│",
    },
    scope = {
      enabled = true,
      underline = true,
    },
    animate = {
      enabled = false,
    },
    filter = function(buf)
      if vim.tbl_contains(excluded.filetypes, vim.bo[buf].filetype) then
        return false
      end
      if vim.tbl_contains(excluded.buftypes, vim.bo[buf].buftype) then
        return false
      end
      return vim.g.snacks_indent ~= false and vim.b[buf].snacks_indent ~= false
    end,
  },

  input = {
    enabled = true,
    expand = true,
  },

  notifier = {
    enabled = true,
    timeout = 5000,
    width = { min = 40, max = 0.382 },
    height = { min = 1, max = 0.6 },
    margin = { top = 0, right = 1, bottom = 0 },
    padding = true,
    top_down = false,
    style = "compact",
    level = vim.log.levels.TRACE,
  },

  image = {
    enabled = true,
    force = false,
    formats = {
      "png",
      "jpg",
      "jpeg",
      "gif",
      "bmp",
      "webp",
      "tiff",
      "heic",
      "avif",
      "mp4",
      "mov",
      "avi",
      "mkv",
      "webm",
      "pdf",
      "icns",
      "svg",
    },
    doc = {
      enabled = true,
      inline = true,
      float = true,
      max_width = 80,
      max_height = 40,
      conceal = function(lang, type)
        return type == "math"
      end,
    },
    img_dirs = { "img", "images", "assets", "static", "public", "media", "attachments" },
    convert = {
      notify = false,
      magick = {
        default = { "{src}[0]", "-scale", "1920x1080>" },
        vector = { "-density", 192, "{src}[{page}]" },
        math = { "-density", 192, "{src}[{page}]", "-trim" },
        pdf = { "-density", 192, "{src}[{page}]", "-background", "white", "-alpha", "remove", "-trim" },
      },
    },
  },

  styles = {
    notification = {
      border = "rounded",
      wo = { winblend = 0 },
    },
    notification_history = {
      width = 0.7,
      height = 0.5,
    },
  },
})

local durations = {
  [vim.log.levels.ERROR] = 10000,
  [vim.log.levels.WARN] = 7000,
  [vim.log.levels.INFO] = 5000,
  [vim.log.levels.DEBUG] = 0,
  [vim.log.levels.TRACE] = 0,
}

local notify = vim.notify
---@diagnostic disable-next-line: duplicate-set-field
vim.notify = function(msg, level, opts)
  opts = opts or {}
  if opts.timeout == nil and durations[level] then
    opts.timeout = durations[level]
  end
  return notify(msg, level, opts)
end

set_indent_hl()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("snacks_indent_hl", { clear = true }),
  callback = set_indent_hl,
})

local function opts(desc)
  return map_opts("General: " .. desc)
end

map("n", "<leader>nH", function()
  snacks.notifier.show_history()
end, opts("Notification history"))

map("n", "<leader>mi", function()
  snacks.image.hover()
end, opts("Preview image under cursor"))

map("n", "<leader>nD", function()
  snacks.notifier.hide()
end, opts("Dismiss all notifications"))
