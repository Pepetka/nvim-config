---Drive a separate Neovim's real input loop; do not synthesize TextChanged events.
local root = vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")))
package.path = root .. "/tests/?.lua;" .. package.path
local t = require("support")
local child = 0

---@param code string
---@param args? unknown[]
---@return unknown
local function execute(code, args)
  return vim.rpcrequest(child, "nvim_exec_lua", code, args or {})
end

---@return nil
local function settle()
  execute("vim.g.stable_folds_test_ready = false; vim.defer_fn(function() vim.g.stable_folds_test_ready = true end, 5)")
  assert(
    vim.wait(1000, function()
      return execute("return vim.g.stable_folds_test_ready") == true
    end, 10),
    "input loop did not settle"
  )
end

---@param keys string
---@return nil
local function input(keys)
  vim.rpcrequest(child, "nvim_input", keys)
  settle()
end

---@param mode string
---@param split? boolean
---@param open_first? boolean
---@return nil
local function closed(mode, split, open_first)
  t.equal(execute("return vim.fn.mode()"), mode)
  execute(
    [[
    local split, open_first = ...
    for index, win in ipairs(vim.api.nvim_list_wins()) do
      vim.api.nvim_win_call(win, function()
        for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
          if line:find("local function", 1, true) then
            local opened = (open_first or (split and win == vim.g.stable_folds_test_open_window))
              and line:find("first", 1, true)
            local expected = opened and -1 or row
            assert(vim.fn.foldclosed(row) == expected,
              "wrong fold state at row " .. row .. " in window " .. win)
          end
        end
      end)
    end
  ]],
    { split == true, open_first == true }
  )
end

---@param name string
---@param run StableFoldsAction
---@param split? boolean
local function test(name, run, split)
  t.test(name, function()
    child = vim.fn.jobstart({ vim.v.progpath, "--clean", "--headless", "--embed", "-i", "NONE" }, { rpc = true })
    assert(child > 0)
    local ok, err = xpcall(function()
      execute(
        [[
        local root, split = ...
        vim.o.swapfile = false
        vim.opt.rtp:prepend(root)
        vim.opt.rtp:append(vim.fn.stdpath("data") .. "/site")
        vim.opt.packpath:append(vim.fn.stdpath("data") .. "/site")
        vim.cmd.packadd("nvim-treesitter")
        vim.bo.filetype = "lua"
        vim.wo.foldminlines, vim.wo.foldnestmax, vim.wo.foldlevel = 1, 3, 99
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
          "-- above", "local function first()", "  local a = 1", "  return a", "end", "",
          "local function second()", "  return 2", "end",
        })
        local folds = require("stable_folds")
        folds.setup()
        folds.attach()
        vim.cmd("2foldclose")
        vim.cmd("7foldclose")
        if split then
          local original = vim.api.nvim_get_current_win()
          vim.cmd.vsplit()
          vim.g.stable_folds_test_open_window = vim.api.nvim_get_current_win()
          vim.cmd("2foldopen")
          vim.api.nvim_set_current_win(original)
        end
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
      ]],
        { root, split == true }
      )
      run()
    end, debug.traceback)
    vim.fn.jobstop(child)
    child = 0
    assert(ok, err)
  end)
end

for _, command in ipairs({ "o", "O" }) do
  test(command .. " above closed folds stays closed throughout Insert and Normal", function()
    input(command)
    closed("i")
    input("typed")
    closed("i")
    input("<CR>more")
    closed("i")
    input("<Esc>")
    closed("n")
  end)
end

test("entering and leaving Insert without editing preserves states", function()
  input("i")
  closed("i")
  input("<Esc>")
  closed("n")
end)

test("inserting newlines at the start of the preceding comment preserves states", function()
  input("i<CR><CR>")
  closed("i")
  input("<Esc>")
  closed("n")
end)

test("typing and deleting text above closed folds preserves states", function()
  input("Atyped")
  closed("i")
  input("<BS><BS><BS><BS><BS>")
  closed("i")
  input("<Esc>")
  closed("n")
end)

for _, command in ipairs({ "p", "P" }) do
  test("linewise " .. command .. " above folds preserves state through undo and redo", function()
    execute('vim.fn.setreg("a", { "-- paste one", "-- paste two" }, "V")')
    input('"a' .. command)
    closed("n")
    input("u")
    closed("n")
    input("<C-r>")
    -- Redo of P puts the cursor on the first fold; native foldopen=undo opens it.
    closed("n", false, command == "P")
  end)
end

test("register insertion with newlines preserves folds while still in Insert", function()
  execute('vim.fn.setreg("a", "-- pasted\\n-- more", "v")')
  input("i<C-r>a")
  closed("i")
  input("<Esc>")
  closed("n")
end)

test("bracketed paste in Insert preserves closed folds before leaving Insert", function()
  input("i")
  vim.rpcrequest(child, "nvim_paste", "-- paste\n-- paste\n", false, -1)
  settle()
  closed("i")
  input("<Esc>")
  closed("n")
end)

test("streamed paste in Insert preserves state through each paste chunk", function()
  input("i")
  for phase, text in ipairs({ "-- first\n", "-- second\n", "-- third\n" }) do
    vim.rpcrequest(child, "nvim_paste", text, false, phase)
    settle()
    closed("i")
  end
  input("<Esc>")
  closed("n")
end)

test("o and paste preserve opposite states in two windows", function()
  input("o")
  closed("i", true)
  vim.rpcrequest(child, "nvim_paste", "-- pasted\n-- again", false, -1)
  settle()
  closed("i", true)
  input("<Esc>")
  closed("n", true)
end, true)

test("nested closed folds remain closed through Insert, paste and Escape", function()
  execute([[
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {
      "-- above", "local function outer()", "  local function inner()", "    return 1",
      "  end", "  return inner()", "end",
    })
    require("stable_folds").refresh()
    vim.cmd("3foldclose")
    vim.cmd("2foldclose")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  ]])
  ---@return nil
  local function nested()
    execute([[
      local outer, inner
      for row, text in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
        if text:find("function outer", 1, true) then outer = row end
        if text:find("function inner", 1, true) then inner = row end
      end
      local view = vim.fn.winsaveview()
      assert(vim.fn.foldclosed(outer) == outer)
      vim.cmd(outer .. "foldopen")
      assert(vim.fn.foldclosed(inner) == inner)
      vim.cmd(outer .. "foldclose")
      vim.fn.winrestview(view)
    ]])
  end
  input("o")
  nested()
  vim.rpcrequest(child, "nvim_paste", "-- pasted\n-- again", false, -1)
  settle()
  nested()
  input("<Esc>")
  nested()
end)

test("completion popup changes above folded text preserve folds in Insert", function()
  execute([[
    vim.g.stable_folds_test_popup_changes = 0
    vim.api.nvim_create_autocmd("TextChangedP", { callback = function()
      vim.g.stable_folds_test_popup_changes = vim.g.stable_folds_test_popup_changes + 1
    end })
  ]])
  input("Aalpha")
  execute('vim.fn.complete(vim.fn.col(".") - 5, { "alpha", "alphabet", "alpine" })')
  settle()
  input("<C-n>")
  closed("i")
  input("<C-y>")
  closed("i")
  assert(execute("return vim.g.stable_folds_test_popup_changes > 0") == true)
  input("<Esc>")
  closed("n")
end)

test("manual opening and editing inside one fold leaves neighboring folds closed", function()
  input("2GzojA -- changed")
  closed("i", false, true)
  input("<Esc>")
  closed("n", false, true)
end)

test("O at the closed first header respects native foldopen=insert", function()
  execute([[
    vim.api.nvim_buf_set_lines(0, 0, 1, false, {})
    require("stable_folds").refresh()
    vim.cmd("1foldclose")
    vim.cmd("6foldclose")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
  ]])
  input("O")
  closed("i", false, true)
  input("-- inserted<Esc>")
  closed("n", false, true)
end)

test("API line and text insertions above folds preserve state without synthetic events", function()
  execute('vim.api.nvim_buf_set_lines(0, 1, 1, false, { "-- one", "-- two" })')
  settle()
  closed("n")
  execute('vim.api.nvim_buf_set_text(0, 0, 0, 0, 0, { "-- prefix", "", "" })')
  settle()
  closed("n")
end)

t.run("stable-folds interactive")
