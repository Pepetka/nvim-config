local merge_tables = require("utils.merge_tables")
local lualine = require("lualine")

local colors = {
  bg = "none",
  fg = "#cad3f5",
  yellow = "#eed49f",
  cyan = "#91d7e3",
  darkblue = "#333853",
  green = "#a6da95",
  orange = "#f5a97f",
  violet = "#b7bdf8",
  magenta = "#f5bde6",
  blue = "#8aadf4",
  red = "#ed8796",
  transparent = "none",
}

local mode_colors = {
  n = { bg = colors.violet, fg = colors.darkblue },
  i = { bg = colors.green, fg = colors.darkblue },
  v = { bg = colors.yellow, fg = colors.darkblue },
  ["\22"] = { bg = colors.blue, fg = colors.darkblue },
  V = { bg = colors.yellow, fg = colors.darkblue },
  c = { bg = colors.magenta, fg = colors.darkblue },
  no = { bg = colors.orange, fg = colors.darkblue },
  s = { bg = colors.orange, fg = colors.darkblue },
  S = { bg = colors.orange, fg = colors.darkblue },
  ["\19"] = { bg = colors.orange, fg = colors.darkblue },
  ic = { bg = colors.yellow, fg = colors.darkblue },
  R = { bg = colors.orange, fg = colors.darkblue },
  Rv = { bg = colors.orange, fg = colors.darkblue },
  cv = { bg = colors.red, fg = colors.fg },
  ce = { bg = colors.red, fg = colors.fg },
  r = { bg = colors.cyan, fg = colors.darkblue },
  rm = { bg = colors.cyan, fg = colors.darkblue },
  ["r?"] = { bg = colors.cyan, fg = colors.darkblue },
  ["!"] = { bg = colors.cyan, fg = colors.darkblue },
  t = { bg = colors.blue, fg = colors.darkblue },
}

local function mode_style()
  return mode_colors[vim.fn.mode()] or { bg = colors.cyan, fg = colors.darkblue }
end

local config = {
  options = {
    theme = {
      normal = { c = { fg = colors.fg, bg = colors.transparent } },
      inactive = { c = { fg = colors.fg, bg = colors.transparent } },
    },
    component_separators = "",
    section_separators = "",
    globalstatus = true,
    disabled_filetypes = {
      statusline = { "NvimTree", "mason", "lazy", "qf" },
      winbar = { "NvimTree", "mason", "lazy", "qf" },
    },
    ignore_focus = { "NvimTree", "mason", "lazy", "qf" },
    refresh = {
      statusline = 100,
      tabline = 100,
      winbar = 100,
    },
  },
  sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {},
    lualine_x = {},
    lualine_y = {},
    lualine_z = {},
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = { { "filename", path = 1, color = { fg = colors.fg } } },
    lualine_x = { { "location", color = { fg = colors.fg } } },
    lualine_y = {},
    lualine_z = {},
  },
  tabline = {},
  winbar = {},
  inactive_winbar = {},
  extensions = { "nvim-tree", "mason", "lazy", "quickfix" },
}

local conditions = {
  buffer_editable = function()
    return vim.bo.buftype == ""
  end,
  buffer_not_empty = function()
    return vim.fn.empty(vim.fn.expand("%:t")) ~= 1
  end,
  width_gt_100 = function()
    return vim.fn.winwidth(0) > 100
  end,
  width_gt_80 = function()
    return vim.fn.winwidth(0) > 80
  end,
  width_gt_60 = function()
    return vim.fn.winwidth(0) > 60
  end,
  git_workspace = function()
    local filepath = vim.fn.expand("%:p:h")
    local gitdir = vim.fn.finddir(".git", filepath .. ";")
    return gitdir and #gitdir > 0 and #gitdir < #filepath
  end,
  lsp_active = function()
    return next(vim.lsp.get_clients({ bufnr = 0 })) ~= nil
  end,
}

local function all(...)
  local fns = { ... }
  return function()
    for _, fn in ipairs(fns) do
      if not fn() then
        return false
      end
    end
    return true
  end
end

local function ins_left(component)
  table.insert(config.sections.lualine_c, component)
end

local function ins_right(component)
  table.insert(config.sections.lualine_x, component)
end

local function space(right, cond)
  local ins = right and ins_right or ins_left
  ins({
    function()
      return " "
    end,
    draw_empty = true,
    padding = -2,
    cond = cond,
  })
end

local function ins_left_capsule(component, icon_block, opts)
  if opts and opts.left then
    space(false, component.cond)
  end
  ins_left(merge_tables({
    separator = { left = "" },
    icons_enabled = false,
    padding = { left = 0, right = 1 },
  }, component))
  ins_left({
    cond = component.cond,
    function()
      return icon_block.icon()
    end,
    draw_empty = true,
    color = icon_block.color,
    separator = { right = "" },
    padding = { left = 1, right = 0 },
  })
  if opts and opts.right then
    space(false, component.cond)
  end
end

ins_left({
  "mode",
  color = function()
    local style = mode_style()
    return { fg = style.fg, bg = style.bg, gui = "bold" }
  end,
  separator = { right = "" },
  padding = { left = 1, right = 0 },
})

ins_left_capsule({
  "branch",
  cond = all(conditions.buffer_editable, conditions.git_workspace, conditions.width_gt_80),
  color = { fg = colors.magenta, bg = colors.darkblue, gui = "bold" },
  separator = { left = "" },
  icons_enabled = false,
}, {
  icon = function()
    return ""
  end,
  color = { fg = colors.darkblue, bg = colors.magenta },
}, { left = true })

ins_left_capsule({
  "filename",
  path = 0,
  cond = all(conditions.buffer_not_empty, conditions.buffer_editable, conditions.width_gt_80),
  color = function()
    return vim.bo.modified and { fg = colors.orange, bg = colors.darkblue }
      or { fg = colors.green, bg = colors.darkblue }
  end,
  separator = { left = "" },
  file_status = false,
}, {
  icon = function()
    return ""
  end,
  color = function()
    return vim.bo.modified and { fg = colors.darkblue, bg = colors.orange }
      or { fg = colors.darkblue, bg = colors.green }
  end,
}, { left = true })

ins_right({
  cond = conditions.lsp_active,
  "lsp_status",
  show_name = false,
  icons_enabled = false,
})
ins_right({
  cond = all(conditions.lsp_active, conditions.width_gt_60),
  function()
    local buf_ft = vim.api.nvim_get_option_value("filetype", { buf = 0 })
    local clients = vim.lsp.get_clients({ bufnr = 0 })
    if next(clients) == nil then
      return "No LSP"
    end

    local preferred = { "svelte-language-server", "vtsls" }
    local function supports(client)
      local filetypes = client.config and client.config.filetypes
      return filetypes and vim.tbl_contains(filetypes, buf_ft)
    end

    for _, client in ipairs(clients) do
      if supports(client) and vim.tbl_contains(preferred, client.name) then
        return client.name
      end
    end
    for _, client in ipairs(clients) do
      if supports(client) then
        return client.name
      end
    end
    return "No LSP"
  end,
  color = { fg = colors.fg, gui = "bold" },
})
space(true, all(conditions.lsp_active, conditions.width_gt_60))

ins_right({
  "diff",
  symbols = { added = " ", modified = "󰝤 ", removed = " " },
  cond = conditions.width_gt_60,
  separator = { left = "", right = "" },
  color = { fg = colors.fg, bg = colors.darkblue },
  diff_color = {
    added = { fg = colors.green, bg = colors.darkblue },
    modified = { fg = colors.orange, bg = colors.darkblue },
    removed = { fg = colors.red, bg = colors.darkblue },
  },
  padding = { left = 0, right = 0 },
})

ins_right({ "diagnostics" })
space(true)

ins_right({
  function()
    return require("noice").api.status.mode.get()
  end,
  cond = function()
    return conditions.width_gt_80() and package.loaded.noice and require("noice").api.status.mode.has()
  end,
  color = { fg = colors.darkblue, bg = colors.yellow },
  separator = { left = "", right = "" },
  padding = { left = 1, right = 1 },
})
space(true, function()
  return conditions.width_gt_80() and package.loaded.noice and require("noice").api.status.mode.has()
end)

ins_right({
  function()
    local search = require("noice").api.status.search.get()
    return search:match("%[[^%]]+%]") or search
  end,
  cond = function()
    return conditions.width_gt_80() and package.loaded.noice and require("noice").api.status.search.has()
  end,
  color = { fg = colors.darkblue, bg = colors.cyan },
  separator = { left = "", right = "" },
  padding = { left = 0, right = 0 },
})
space(true, function()
  return conditions.width_gt_80() and package.loaded.noice and require("noice").api.status.search.has()
end)

ins_right({
  "filetype",
  cond = all(conditions.buffer_not_empty, conditions.buffer_editable, conditions.width_gt_100),
  color = { fg = colors.darkblue, bg = colors.magenta },
  colored = false,
  icon_only = true,
  separator = { left = "" },
  padding = { left = 0, right = 0 },
})
ins_right({
  "filetype",
  cond = all(conditions.buffer_not_empty, conditions.buffer_editable, conditions.width_gt_100),
  color = { fg = colors.magenta, bg = colors.darkblue },
  icons_enabled = false,
  separator = { right = "" },
  padding = { left = 1, right = 0 },
})
space(true, all(conditions.buffer_not_empty, conditions.buffer_editable, conditions.width_gt_100))

ins_right({
  "progress",
  cond = conditions.width_gt_100,
  color = { fg = colors.fg, bg = colors.darkblue },
  icons_enabled = false,
  separator = { left = "", right = "" },
  padding = { left = 1, right = 1 },
})
space(true, conditions.width_gt_100)

ins_right({
  "location",
  color = { fg = colors.darkblue, bg = colors.violet, gui = "bold" },
  separator = { left = "", color = { fg = colors.violet, bg = colors.violet } },
  padding = { left = 0, right = 1 },
})

lualine.setup(config)
