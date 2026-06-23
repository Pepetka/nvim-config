---@alias CheatsheetBorder "none" | "single" | "double" | "rounded" | "solid" | "shadow"
---@alias CheatsheetTitlePosition "left" | "center" | "right"
---@alias CheatsheetMode "n" | "i" | "v" | "o" | "t"
---@alias CheatsheetSortKey "alphanum" | "desc"
---@alias CheatsheetGroupAlign "left" | "center" | "right"
---@alias CheatsheetModeAlign "left" | "center" | "right"

---@class CheatsheetWindowPadding
---@field left number
---@field right number
---@field top number
---@field bottom number

---@class CheatsheetWindowConfig
---@field width number
---@field height number
---@field border CheatsheetBorder
---@field title string
---@field title_pos CheatsheetTitlePosition
---@field zindex integer
---@field padding CheatsheetWindowPadding

---@class CheatsheetGroupRule
---@field pattern string
---@field group string
---@field icon string

---@class CheatsheetDefaultGroup
---@field name string
---@field icon string

---@class CheatsheetExcludeConfig
---@field no_desc boolean
---@field patterns string[]
---@field single_word boolean
---@field newline boolean
---@field groups string[]

---@class CheatsheetIconsConfig
---@field enabled boolean
---@field default string

---@class CheatsheetMappingsConfig
---@field close string[]
---@field next_mode string
---@field prev_mode string

---@class CheatsheetConfig
---@field window CheatsheetWindowConfig
---@field modes CheatsheetMode[]
---@field group_rules CheatsheetGroupRule[]
---@field default_group CheatsheetDefaultGroup
---@field exclude CheatsheetExcludeConfig
---@field icons CheatsheetIconsConfig
---@field sort_groups string[]
---@field sort_keys CheatsheetSortKey
---@field group_align CheatsheetGroupAlign
---@field mode_align CheatsheetModeAlign
---@field group_underline boolean
---@field mappings CheatsheetMappingsConfig
---@field open_mapping string | nil

---@class CheatsheetConfigPartial
---@field window? CheatsheetWindowConfig
---@field modes? CheatsheetMode[]
---@field group_rules? CheatsheetGroupRule[]
---@field default_group? CheatsheetDefaultGroup
---@field exclude? CheatsheetExcludeConfig
---@field icons? CheatsheetIconsConfig
---@field sort_groups? string[]
---@field sort_keys? CheatsheetSortKey
---@field group_align? CheatsheetGroupAlign
---@field mode_align? CheatsheetModeAlign
---@field group_underline? boolean
---@field mappings? CheatsheetMappingsConfig
---@field open_mapping? string | nil

local M = {}

---@type CheatsheetConfig
M.defaults = {
  window = {
    width = 0.8,
    height = 0.8,
    title = "Cheatsheet",
    title_pos = "left",
    border = "rounded",
    zindex = 50,
    padding = { left = 2, right = 2, top = 1, bottom = 1 },
  },

  modes = { "n", "i", "v", "o", "t" },

  group_rules = {
    { pattern = "^FZF:", group = "find", icon = " " },
    { pattern = "^Git:", group = "git", icon = "󰊢 " },
    { pattern = "^LSP:", group = "lsp", icon = "󰒕 " },
    { pattern = "^DAP:", group = "debug", icon = " " },
    { pattern = "^Tree:", group = "tree", icon = "󰙅 " },
    { pattern = "^Trouble:", group = "trouble", icon = "󰁙 " },
    { pattern = "^Buffer:", group = "buffer", icon = "󰓩 " },
    { pattern = "^AI:", group = "ai", icon = "󰚩 " },
    { pattern = "^Edit:", group = "edit", icon = "󰦨 " },
    { pattern = "^Navigate:", group = "navigate", icon = "󰆹 " },
    { pattern = "^General:", group = "general", icon = "󰌵 " },
    { pattern = "^Cheatsheet:", group = "cheatsheet", icon = "󰌌 " },
  },

  default_group = {
    name = "other",
    icon = "󰌌 ",
  },

  exclude = {
    no_desc = true,
    patterns = { "^<Plug>", "^Lua function" },
    single_word = true,
    newline = true,
    groups = { "terminal (t)", "autopairs" },
  },

  icons = {
    enabled = true,
    default = "󰌌 ",
  },

  sort_groups = {
    "find",
    "git",
    "lsp",
    "debug",
    "tree",
    "buffer",
    "trouble",
    "ai",
    "edit",
    "navigate",
    "general",
    "cheatsheet",
    "other",
  },

  sort_keys = "alphanum",
  group_align = "left",
  mode_align = "right",
  group_underline = true,

  mappings = {
    close = { "q" },
    next_mode = "<tab>",
    prev_mode = "<S-Tab>",
  },

  open_mapping = "<leader>ch",
}

---@param opts CheatsheetConfigPartial
---@return CheatsheetConfigPartial
local function validate_options(opts)
  ---@param path string
  ---@param value any
  ---@param validator function
  ---@param default any
  ---@param msg? string
  ---@return any
  local function check(path, value, validator, default, msg)
    if not validator(value) then
      vim.notify(
        "cheatsheet: invalid " .. path .. (msg and " (" .. msg .. ")" or "") .. ", using default",
        vim.log.levels.WARN
      )
      return default
    end
    return value
  end

  if opts.window then
    if opts.window.width then
      ---@param v number
      opts.window.width = check("window.width", opts.window.width, function(v)
        return type(v) == "number" and v > 0 and v <= 1
      end, M.defaults.window.width)
    end

    if opts.window.height then
      ---@param v number
      opts.window.height = check("window.height", opts.window.height, function(v)
        return type(v) == "number" and v > 0 and v <= 1
      end, M.defaults.window.height)
    end

    if opts.window.border then
      ---@type CheatsheetBorder[]
      local valid_borders = {
        "none",
        "single",
        "double",
        "rounded",
        "solid",
        "shadow",
      }
      ---@param v CheatsheetBorder
      opts.window.border = check("window.border", opts.window.border, function(v)
        return type(v) == "string" and vim.tbl_contains(valid_borders, v)
      end, M.defaults.window.border)
    end

    if opts.window.title_pos then
      ---@type CheatsheetTitlePosition[]
      local valid_positions = {
        "left",
        "center",
        "right",
      }
      ---@param v CheatsheetTitlePosition
      opts.window.title_pos = check("window.title_pos", opts.window.title_pos, function(v)
        return type(v) == "string" and vim.tbl_contains(valid_positions, v)
      end, M.defaults.window.title_pos)
    end

    if opts.window.padding then
      if type(opts.window.padding) ~= "table" then
        vim.notify("cheatsheet: invalid window.padding, using default", vim.log.levels.WARN)
        opts.window.padding = M.defaults.window.padding
      else
        for _, key in ipairs({ "left", "right", "top", "bottom" }) do
          local value = opts.window.padding[key]
          if value ~= nil then
            opts.window.padding[key] = check("window.padding." .. key, value, function(v)
              return type(v) == "number" and v >= 0
            end, M.defaults.window.padding[key])
          end
        end
      end
    end
  end

  if opts.modes then
    ---@type CheatsheetMode[]
    local valid_modes = {
      "n",
      "i",
      "v",
      "o",
      "t",
    }
    ---@param v CheatsheetMode[]
    opts.modes = check("modes", opts.modes, function(v)
      return type(v) == "table"
        ---@param m CheatsheetMode
        and vim.iter(v):all(function(m)
          return type(m) == "string" and vim.tbl_contains(valid_modes, m)
        end)
    end, M.defaults.modes)
  end

  if opts.sort_keys then
    ---@type CheatsheetSortKey[]
    local valid_sort_keys = {
      "alphanum",
      "desc",
    }
    ---@param v CheatsheetSortKey
    opts.sort_keys = check("sort_keys", opts.sort_keys, function(v)
      return type(v) == "string" and vim.tbl_contains(valid_sort_keys, v)
    end, M.defaults.sort_keys)
  end

  if opts.group_align then
    ---@type CheatsheetGroupAlign[]
    local valid_aligns = {
      "left",
      "center",
      "right",
    }
    ---@param v CheatsheetGroupAlign
    opts.group_align = check("group_align", opts.group_align, function(v)
      return type(v) == "string" and vim.tbl_contains(valid_aligns, v)
    end, M.defaults.group_align)
  end

  if opts.mode_align then
    ---@type CheatsheetModeAlign[]
    local valid_aligns = {
      "left",
      "center",
      "right",
    }
    ---@param v CheatsheetModeAlign
    opts.mode_align = check("mode_align", opts.mode_align, function(v)
      return type(v) == "string" and vim.tbl_contains(valid_aligns, v)
    end, M.defaults.mode_align)
  end

  if opts.group_underline ~= nil then
    opts.group_underline = check("group_underline", opts.group_underline, function(v)
      return type(v) == "boolean"
    end, M.defaults.group_underline)
  end

  if opts.group_rules then
    ---@param v CheatsheetGroupRule[]
    opts.group_rules = check("group_rules", opts.group_rules, function(v)
      return type(v) == "table"
        ---@param r CheatsheetGroupRule
        and vim.iter(v):all(function(r)
          return type(r) == "table"
            and type(r.pattern) == "string"
            and type(r.group) == "string"
            and type(r.icon) == "string"
        end)
    end, M.defaults.group_rules)
  end

  return opts
end

---@type CheatsheetConfig
M.options = nil

---@param opts? CheatsheetConfigPartial
---@return nil
function M.setup(opts)
  opts = validate_options(opts or {})
  M.options = vim.tbl_deep_extend("force", M.defaults, opts)
end

return M
