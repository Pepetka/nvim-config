local merge_tables = require("utils.merge_tables")
local lualine = require("lualine")

local M = {}

function M.setup()
  local colors = require("utils.colors")
  local transparent = "none"

  local mode_colors = {
    n = { bg = colors.palette.purple, fg = colors.surface },
    i = { bg = colors.palette.green, fg = colors.surface },
    v = { bg = colors.palette.yellow, fg = colors.surface },
    ["\22"] = { bg = colors.palette.blue, fg = colors.surface },
    V = { bg = colors.palette.yellow, fg = colors.surface },
    c = { bg = colors.palette.magenta, fg = colors.surface },
    no = { bg = colors.palette.orange, fg = colors.surface },
    s = { bg = colors.palette.orange, fg = colors.surface },
    S = { bg = colors.palette.orange, fg = colors.surface },
    ["\19"] = { bg = colors.palette.orange, fg = colors.surface },
    ic = { bg = colors.palette.yellow, fg = colors.surface },
    R = { bg = colors.palette.orange, fg = colors.surface },
    Rv = { bg = colors.palette.orange, fg = colors.surface },
    cv = { bg = colors.palette.red, fg = colors.fg },
    ce = { bg = colors.palette.red, fg = colors.fg },
    r = { bg = colors.palette.cyan, fg = colors.surface },
    rm = { bg = colors.palette.cyan, fg = colors.surface },
    ["r?"] = { bg = colors.palette.cyan, fg = colors.surface },
    ["!"] = { bg = colors.palette.cyan, fg = colors.surface },
    t = { bg = colors.palette.blue, fg = colors.surface },
  }

  ---@return { fg: string, bg: string }
  local function mode_style()
    return mode_colors[vim.fn.mode()] or { bg = colors.palette.cyan, fg = colors.surface }
  end

  local config = {
    options = {
      theme = {
        normal = { c = { fg = colors.fg, bg = transparent } },
        inactive = { c = { fg = colors.fg, bg = transparent } },
      },
      component_separators = "",
      section_separators = "",
      globalstatus = true,
      disabled_filetypes = {
        statusline = { "NvimTree", "mason", "lazy", "qf", "dashboard" },
        winbar = { "NvimTree", "mason", "lazy", "qf", "dashboard" },
      },
      ignore_focus = { "NvimTree", "mason", "lazy", "qf", "dashboard" },
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

  ---@type table<string, fun(): boolean>
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

  ---@param ... fun(): boolean
  ---@return fun(): boolean
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

  ---@param component table
  local function ins_left(component)
    table.insert(config.sections.lualine_c, component)
  end

  ---@param component table
  local function ins_right(component)
    table.insert(config.sections.lualine_x, component)
  end

  ---@param right boolean
  ---@param cond? fun(): boolean
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

  ---@param component table
  ---@param icon_block table
  ---@param opts? { left?: boolean, right?: boolean }
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
    color = { fg = colors.palette.magenta, bg = colors.surface, gui = "bold" },
    separator = { left = "" },
    icons_enabled = false,
  }, {
    icon = function()
      return ""
    end,
    color = { fg = colors.surface, bg = colors.palette.magenta },
  }, { left = true })

  ins_left_capsule({
    "filename",
    path = 0,
    cond = all(conditions.buffer_not_empty, conditions.buffer_editable, conditions.width_gt_80),
    color = function()
      return vim.bo.modified and { fg = colors.palette.orange, bg = colors.surface }
        or { fg = colors.palette.green, bg = colors.surface }
    end,
    separator = { left = "" },
    file_status = false,
  }, {
    icon = function()
      return ""
    end,
    color = function()
      return vim.bo.modified and { fg = colors.surface, bg = colors.palette.orange }
        or { fg = colors.surface, bg = colors.palette.green }
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

      local preferred = { "svelte-language-server", "vtsls", "tsgo" }
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
    color = { fg = colors.fg, bg = colors.surface },
    diff_color = {
      added = { fg = colors.palette.green, bg = colors.surface },
      modified = { fg = colors.palette.orange, bg = colors.surface },
      removed = { fg = colors.palette.red, bg = colors.surface },
    },
    padding = { left = 0, right = 0 },
  })

  ins_right({ "diagnostics" })
  space(true)

  ins_right({
    function()
      ---@diagnostic disable-next-line: undefined-field
      return require("noice").api.status.mode.get()
    end,
    cond = function()
      ---@diagnostic disable-next-line: undefined-field
      return conditions.width_gt_80() and package.loaded.noice and require("noice").api.status.mode.has()
    end,
    color = { fg = colors.surface, bg = colors.palette.yellow },
    separator = { left = "", right = "" },
    padding = { left = 1, right = 1 },
  })
  space(true, function()
    ---@diagnostic disable-next-line: undefined-field
    return conditions.width_gt_80() and package.loaded.noice and require("noice").api.status.mode.has()
  end)

  ins_right({
    function()
      ---@diagnostic disable-next-line: undefined-field
      local search = require("noice").api.status.search.get()
      return search:match("%[[^%]]+%]") or search
    end,
    cond = function()
      ---@diagnostic disable-next-line: undefined-field
      return conditions.width_gt_80() and package.loaded.noice and require("noice").api.status.search.has()
    end,
    color = { fg = colors.surface, bg = colors.palette.cyan },
    separator = { left = "", right = "" },
    padding = { left = 0, right = 0 },
  })
  space(true, function()
    ---@diagnostic disable-next-line: undefined-field
    return conditions.width_gt_80() and package.loaded.noice and require("noice").api.status.search.has()
  end)

  ins_right({
    "filetype",
    cond = all(conditions.buffer_not_empty, conditions.buffer_editable, conditions.width_gt_100),
    color = { fg = colors.surface, bg = colors.palette.magenta },
    colored = false,
    icon_only = true,
    separator = { left = "" },
    padding = { left = 0, right = 0 },
  })
  ins_right({
    "filetype",
    cond = all(conditions.buffer_not_empty, conditions.buffer_editable, conditions.width_gt_100),
    color = { fg = colors.palette.magenta, bg = colors.surface },
    icons_enabled = false,
    separator = { right = "" },
    padding = { left = 1, right = 0 },
  })
  space(true, all(conditions.buffer_not_empty, conditions.buffer_editable, conditions.width_gt_100))

  ins_right({
    "progress",
    cond = conditions.width_gt_100,
    color = { fg = colors.fg, bg = colors.surface },
    icons_enabled = false,
    separator = { left = "", right = "" },
    padding = { left = 1, right = 1 },
  })
  space(true, conditions.width_gt_100)

  ins_right({
    "location",
    color = { fg = colors.surface, bg = colors.palette.purple, gui = "bold" },
    separator = { left = "", color = { fg = colors.palette.purple, bg = colors.palette.purple } },
    padding = { left = 0, right = 1 },
  })

  lualine.setup(config)
end

M.setup()

return M
