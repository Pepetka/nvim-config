local codeium = require("codeium")
local vt = require("codeium.virtual_text")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")

local config = {
  config_path = vim.fn.expand("~/.codeium/config.json"),
  enable_cmp_source = false,
  enable_chat = false,
  enable_local_search = false,
  enable_index_service = false,
  virtual_text = {
    enabled = true,
    manual = false,
    idle_delay = 75,
    virtual_text_priority = 65535,
    map_keys = false,
    default_filetype_enabled = true,
    filetypes = {
      help = false,
      gitcommit = false,
      gitrebase = false,
      TelescopePrompt = false,
      noice = false,
      fzf = false,
      NvimTree = false,
      mason = false,
      ["."] = false,
    },
  },
  workspace_root = {
    use_lsp = true,
  },
}
codeium.setup(config)

-- ═══════════════════════════════════════════════════════════════
--  Global keymaps
-- ═══════════════════════════════════════════════════════════════
local function opts(desc, extra)
  return map_opts("Windsurf: " .. desc, extra)
end

map("i", "<A-g>", function()
  return vt.accept()
end, opts("Accept suggestion", { expr = true, script = true, nowait = true }))

map("i", "<A-w>", function()
  return vt.accept_next_word()
end, opts("Accept word", { expr = true, script = true, nowait = true }))

map("i", "<A-l>", function()
  return vt.accept_next_line()
end, opts("Accept line", { expr = true, script = true, nowait = true }))

map("i", "<A-j>", function()
  return vt.cycle_or_complete(1)
end, opts("Next / complete", { expr = true }))

map("i", "<A-k>", function()
  return vt.cycle_or_complete(-1)
end, opts("Previous suggestion", { expr = true }))

map("i", "<A-c>", function()
  return vt.clear()
end, opts("Clear suggestion", { expr = true }))
