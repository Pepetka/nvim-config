local minuet = require("minuet")
local vt = require("minuet.virtualtext").action
local map = vim.keymap.set
local map_opts = require("utils.map_opts")

local config = {
  provider = "openai_fim_compatible",

  context_window = 2048,
  context_ratio = 0.7,
  n_completions = 1,
  throttle = 300,
  debounce = 200,
  request_timeout = 10,
  notify = false,

  provider_options = {
    openai_fim_compatible = {
      model = "qwen2.5-coder:3b",
      end_point = "http://localhost:11434/v1/completions",
      api_key = "TERM",
      name = "Ollama",
      stream = false,
      optional = {
        max_tokens = 56,
        temperature = 0.1,
        top_p = 0.9,
        stop = { "\n" },
      },
    },
  },

  virtualtext = {
    auto_trigger_ft = { "*" },
    auto_trigger_ignore_ft = {
      "help",
      "noice",
      "prompt",
      "fzf",
      "NvimTree",
      "mason",
      "TelescopePrompt",
    },
    show_on_completion_menu = true,
    keymap = {
      accept = nil,
      accept_line = nil,
      accept_n_lines = nil,
      next = nil,
      prev = nil,
      dismiss = nil,
    },
  },
}
minuet.setup(config)

-- ═══════════════════════════════════════════════════════════════
--  Global keymaps
-- ═══════════════════════════════════════════════════════════════
local function opts(desc)
  return map_opts("AI: " .. desc)
end

map("i", "<A-g>", vt.accept, opts("Accept suggestion"))
map("i", "<A-l>", vt.accept_line, opts("Accept line"))
map("i", "<A-w>", vt.accept_n_lines, opts("Accept n lines"))
map("i", "<A-j>", vt.next, opts("Next / complete"))
map("i", "<A-k>", vt.prev, opts("Previous suggestion"))
map("i", "<A-c>", vt.dismiss, opts("Dismiss suggestion"))
