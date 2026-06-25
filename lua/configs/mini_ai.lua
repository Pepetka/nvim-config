local mini_ai = require("mini.ai")

local gen_spec = mini_ai.gen_spec

local config = {
  n_lines = 50,
  search_method = "cover_or_next",
  mappings = {
    around = "a",
    inside = "i",
    around_next = "",
    inside_next = "",
    around_last = "al",
    inside_last = "il",
    goto_left = "g[",
    goto_right = "g]",
  },
  custom_textobjects = {
    a = gen_spec.argument({ separator = "%s*,%s*" }),
    f = gen_spec.function_call({ name_pattern = "[%w_]" }),
    ["*"] = gen_spec.pair("*", "*", { type = "greedy" }),
    ["_"] = gen_spec.pair("_", "_", { type = "greedy" }),
    g = function()
      return {
        from = { line = 1, col = 1 },
        to = { line = vim.fn.line("$"), col = math.max(vim.fn.getline("$"):len(), 1) },
        vis_mode = "V",
      }
    end,
  },
}

mini_ai.setup(config)
