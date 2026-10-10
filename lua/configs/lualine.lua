local lualine = require("lualine")
local theme_highlights = require("utils.theme_highlights")

theme_highlights.register("lualine", function(c)
  return {
    ConfigStatusDiffAdd = { fg = c.palette.green, bg = c.surface },
    ConfigStatusDiffChange = { fg = c.palette.orange, bg = c.surface },
    ConfigStatusDiffDelete = { fg = c.palette.red, bg = c.surface },
  }
end)

local M = {}

function M.setup()
  local colors = require("utils.colors")
  local transparent = "none"
  local git_roots = {}

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "DirChanged" }, {
    group = vim.api.nvim_create_augroup("LualineGitRootCache", { clear = true }),
    callback = function(args)
      if args.event ~= "DirChanged" then
        git_roots[args.buf] = nil
      else
        git_roots = {}
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufDelete", {
    group = "LualineGitRootCache",
    callback = function(args)
      git_roots[args.buf] = nil
    end,
  })

  local mode_colors = {
    n = "purple",
    i = "green",
    v = "yellow",
    ["\22"] = "blue",
    V = "yellow",
    c = "magenta",
    no = "orange",
    s = "orange",
    S = "orange",
    ["\19"] = "orange",
    ic = "yellow",
    R = "orange",
    Rv = "orange",
    cv = "red",
    ce = "red",
    r = "cyan",
    rm = "cyan",
    ["r?"] = "cyan",
    ["!"] = "cyan",
    t = "blue",
  }

  ---@return { fg: string, bg: string }
  local function mode_style()
    local mode = vim.fn.mode()
    return {
      bg = colors.palette[mode_colors[mode] or "cyan"],
      fg = (mode == "cv" or mode == "ce") and colors.fg or colors.surface,
    }
  end

  local config = {
    options = {
      theme = function()
        return {
          normal = { c = { fg = colors.fg, bg = transparent } },
          inactive = { c = { fg = colors.fg, bg = transparent } },
        }
      end,
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
      lualine_c = {
        {
          "filename",
          path = 1,
          color = function()
            return { fg = colors.fg }
          end,
        },
      },
      lualine_x = {
        {
          "location",
          color = function()
            return { fg = colors.fg }
          end,
        },
      },
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
      local buf = vim.api.nvim_get_current_buf()
      if git_roots[buf] == nil then
        local name = vim.api.nvim_buf_get_name(buf)
        git_roots[buf] = name ~= "" and vim.fs.root(name, ".git") or false
      end
      return git_roots[buf] ~= false
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

  ---@diagnostic disable-next-line: undefined-field
  local noice_status = require("noice").api.status
  local function has_noice_status(status)
    return function()
      return conditions.width_gt_80() and status.has()
    end
  end
  local has_mode = has_noice_status(noice_status.mode)
  local has_search = has_noice_status(noice_status.search)

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
    ins_left(vim.tbl_extend("force", {
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
    color = function()
      return { fg = colors.palette.magenta, bg = colors.surface, gui = "bold" }
    end,
    separator = { left = "" },
    icons_enabled = false,
  }, {
    icon = function()
      return ""
    end,
    color = function()
      return { fg = colors.surface, bg = colors.palette.magenta }
    end,
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

      local preferred = { "svelte", "vtsls", "tsgo" }
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
    color = function()
      return { fg = colors.fg, gui = "bold" }
    end,
  })
  space(true, all(conditions.lsp_active, conditions.width_gt_60))

  ins_right({
    "diff",
    symbols = { added = " ", modified = "󰝤 ", removed = " " },
    cond = conditions.width_gt_60,
    separator = { left = "", right = "" },
    color = function()
      return { fg = colors.fg, bg = colors.surface }
    end,
    diff_color = {
      added = "ConfigStatusDiffAdd",
      modified = "ConfigStatusDiffChange",
      removed = "ConfigStatusDiffDelete",
    },
    padding = { left = 0, right = 0 },
  })

  ins_right({ "diagnostics" })
  space(true)

  ins_right({
    function()
      ---@diagnostic disable-next-line: undefined-field
      return noice_status.mode.get()
    end,
    cond = has_mode,
    color = function()
      return { fg = colors.surface, bg = colors.palette.yellow }
    end,
    separator = { left = "", right = "" },
    padding = { left = 1, right = 1 },
  })
  space(true, has_mode)

  ins_right({
    function()
      ---@diagnostic disable-next-line: undefined-field
      local search = noice_status.search.get()
      return search:match("%[[^%]]+%]") or search
    end,
    cond = has_search,
    color = function()
      return { fg = colors.surface, bg = colors.palette.cyan }
    end,
    separator = { left = "", right = "" },
    padding = { left = 0, right = 0 },
  })
  space(true, has_search)

  ins_right({
    "filetype",
    cond = all(conditions.buffer_not_empty, conditions.buffer_editable, conditions.width_gt_100),
    color = function()
      return { fg = colors.surface, bg = colors.palette.magenta }
    end,
    colored = false,
    icon_only = true,
    separator = { left = "" },
    padding = { left = 0, right = 0 },
  })
  ins_right({
    "filetype",
    cond = all(conditions.buffer_not_empty, conditions.buffer_editable, conditions.width_gt_100),
    color = function()
      return { fg = colors.palette.magenta, bg = colors.surface }
    end,
    icons_enabled = false,
    separator = { right = "" },
    padding = { left = 1, right = 0 },
  })
  space(true, all(conditions.buffer_not_empty, conditions.buffer_editable, conditions.width_gt_100))

  ins_right({
    "progress",
    cond = conditions.width_gt_100,
    color = function()
      return { fg = colors.fg, bg = colors.surface }
    end,
    icons_enabled = false,
    separator = { left = "", right = "" },
    padding = { left = 1, right = 1 },
  })
  space(true, conditions.width_gt_100)

  ins_right({
    "location",
    color = function()
      return { fg = colors.surface, bg = colors.palette.purple, gui = "bold" }
    end,
    separator = { left = "" },
    padding = { left = 0, right = 1 },
  })

  lualine.setup(config)
end

M.setup()
theme_highlights.on_refresh("lualine", function()
  lualine.refresh({ scope = "all", place = { "statusline", "winbar" }, force = true })
end, 20)

return M
