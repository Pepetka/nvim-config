local blink = require("blink.cmp")

blink.setup({
  keymap = {
    preset = "none",
    ["<C-j>"] = { "select_next", "fallback" },
    ["<C-k>"] = { "select_prev", "fallback" },
    ["<CR>"] = { "accept", "fallback" },
    ["<C-e>"] = { "hide", "fallback" },
    ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
    ["<Tab>"] = { "snippet_forward", "fallback" },
    ["<S-Tab>"] = { "snippet_backward", "fallback" },
  },

  appearance = {
    nerd_font_variant = "mono",
    use_nvim_cmp_as_default = true,
  },

  snippets = {
    preset = "default",
  },

  completion = {
    keyword = { range = "full" },

    accept = {
      auto_brackets = { enabled = true },
    },

    list = {
      selection = {
        preselect = true,
        auto_insert = true,
      },
    },

    menu = {
      auto_show = true,
      border = "rounded",

      draw = {
        treesitter = { "lsp" },

        columns = {
          { "kind_icon" },
          { "label", gap = 1 },
          { "kind" },
        },

        components = {
          source_name = {
            width = { max = 30 },
            text = function(ctx)
              return "[" .. ctx.source_name .. "]"
            end,
            highlight = "BlinkCmpSource",
          },
        },
      },
    },

    documentation = {
      auto_show = true,
      auto_show_delay_ms = 200,
      window = { border = "rounded" },
    },

    ghost_text = { enabled = false },
  },

  sources = {
    default = { "lazydev", "lsp", "css_in_js", "path", "snippets", "buffer" },
    providers = {
      lsp = {
        transform_items = function(ctx, items)
          if not require("utils.css_in_js").context(ctx.bufnr, ctx.cursor[1] - 1, ctx.cursor[2]) then
            return items
          end
          return vim.tbl_filter(function(item)
            local client = vim.lsp.get_client_by_id(item.client_id)
            return not client or (client.name ~= "tsgo" and client.name ~= "vtsls")
          end, items)
        end,
      },
      css_in_js = {
        name = "CSS-in-JS",
        module = "completion.css_in_js",
      },
      lazydev = {
        name = "LazyDev",
        module = "lazydev.integrations.blink",
        score_offset = 100,
      },
    },
  },

  signature = {
    enabled = true,
    window = { border = "rounded" },
  },

  cmdline = {
    enabled = true,
    keymap = { preset = "cmdline" },
    sources = function()
      local type = vim.fn.getcmdtype()
      if type == "/" or type == "?" then
        return { "buffer" }
      end
      if type == ":" or type == "@" then
        return { "cmdline", "buffer" }
      end
      return {}
    end,
    completion = {
      list = { selection = { preselect = false, auto_insert = true } },
      menu = {
        auto_show = function(ctx)
          return ctx.mode == "cmdwin"
        end,
      },
      ghost_text = { enabled = true },
    },
  },

  fuzzy = {
    implementation = "prefer_rust_with_warning",
  },
})
