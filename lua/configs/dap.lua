local dap = require("dap")
local map = vim.keymap.set
local map_opts = require("utils.map_opts")
local colors = require("utils.colors")

local js_debug_path = vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js"

dap.adapters["pwa-node"] = {
  type = "server",
  host = "127.0.0.1",
  port = "${port}",
  executable = {
    command = "node",
    args = { js_debug_path, "${port}", "127.0.0.1" },
  },
}

dap.adapters["pwa-chrome"] = {
  type = "server",
  host = "127.0.0.1",
  port = "${port}",
  executable = {
    command = "node",
    args = { js_debug_path, "${port}", "127.0.0.1" },
  },
}

local js_filetypes = {
  "javascript",
  "typescript",
  "javascriptreact",
  "typescriptreact",
  "svelte",
}

local js_configs = {
  -- Launch the current file directly with node.
  {
    type = "pwa-node",
    request = "launch",
    name = "Launch file",
    program = "${file}",
    cwd = "${workspaceFolder}",
    args = { "${file}" },
    sourceMaps = true,
    skipFiles = { "<node_internals>/**" },
  },
  -- Attach to an already running Node process selected from a list.
  {
    type = "pwa-node",
    request = "attach",
    name = "Attach to process",
    processId = require("dap.utils").pick_process,
    cwd = "${workspaceFolder}",
    sourceMaps = true,
    skipFiles = { "<node_internals>/**" },
  },
  -- Attach to a Node debugger started with --inspect=9229.
  {
    type = "pwa-node",
    request = "attach",
    name = "Attach to 9229",
    port = 9229,
    address = "localhost",
    cwd = "${workspaceFolder}",
    localRoot = "${workspaceFolder}",
    sourceMaps = true,
    skipFiles = { "<node_internals>/**" },
  },
}

-- Prefer the visible window when jumping to a breakpoint/frame.
-- Falls back to existing tabs/windows before creating new splits.
dap.defaults.fallback.switchbuf = "usevisible,usetab,uselast"

for _, ft in ipairs(js_filetypes) do
  dap.configurations[ft] = js_configs
end

local function setup_dap_highlights()
  vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = colors.error })
  vim.api.nvim_set_hl(0, "DapBreakpointCondition", { fg = colors.alert })
  vim.api.nvim_set_hl(0, "DapBreakpointRejected", { fg = colors.warning })
  vim.api.nvim_set_hl(0, "DapLogPoint", { fg = colors.info })
  vim.api.nvim_set_hl(0, "DapStopped", { fg = colors.accent })
  vim.api.nvim_set_hl(0, "DapStoppedLine", { bg = colors.bg_visual })
end

setup_dap_highlights()

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("DapHighlights", { clear = true }),
  callback = setup_dap_highlights,
})

vim.fn.sign_define("DapBreakpoint", { text = "●", texthl = "DapBreakpoint" })
vim.fn.sign_define("DapBreakpointCondition", { text = "◆", texthl = "DapBreakpointCondition" })
vim.fn.sign_define("DapLogPoint", { text = "◉", texthl = "DapLogPoint" })
vim.fn.sign_define("DapStopped", { text = "▶", texthl = "DapStopped", linehl = "DapStoppedLine" })
vim.fn.sign_define("DapBreakpointRejected", { text = "✕", texthl = "DapBreakpointRejected" })

dap.listeners.before.attach.dapview_config = function()
  require("dap-view").open()
end
dap.listeners.before.launch.dapview_config = function()
  require("dap-view").open()
end
dap.listeners.before.event_terminated.dapview_config = function()
  require("dap-view").close()
end
dap.listeners.before.event_exited.dapview_config = function()
  require("dap-view").close()
end

-- ═══════════════════════════════════════════════════════════════
--  Global keymaps
-- ═══════════════════════════════════════════════════════════════
local function opts(desc)
  return map_opts("DAP: " .. desc, { noremap = false })
end

map("n", "<leader>db", function()
  dap.toggle_breakpoint()
end, opts("Toggle breakpoint"))

map("n", "<leader>dB", function()
  dap.set_breakpoint(vim.fn.input("Breakpoint condition: "))
end, opts("Conditional breakpoint"))

map("n", "<leader>dc", function()
  dap.continue()
end, opts("Continue / start debugging"))

map("n", "<leader>dC", function()
  dap.run_to_cursor()
end, opts("Run to cursor"))

map("n", "<leader>do", function()
  dap.step_over()
end, opts("Step over"))

map("n", "<leader>di", function()
  dap.step_into()
end, opts("Step into"))

map("n", "<leader>dO", function()
  dap.step_out()
end, opts("Step out"))

map("n", "<leader>dl", function()
  dap.run_last()
end, opts("Run last configuration"))

map("n", "<leader>dt", function()
  dap.terminate()
end, opts("Terminate session"))

map("n", "<leader>dr", function()
  dap.repl.toggle()
end, opts("Toggle REPL"))
