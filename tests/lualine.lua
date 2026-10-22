-- Run: NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -n -l tests/lualine.lua
local root = vim.fn.getcwd()
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary .. "/theme", "p")
assert(vim.uv.fs_symlink(root, temporary .. "/nvim", { dir = true }))
local lines = {}
for i = 1, 500 do
  lines[i] = "sample row " .. i
end
lines[10] = "а界z"
vim.fn.writefile(lines, temporary .. "/scroll.txt")
vim.fn.writefile({ "x", "sample row 12", "sample row 13", "lonely" }, temporary .. "/other.txt")
vim.fn.writefile({ "Word word WORD", "Word", "Sub sub" }, temporary .. "/case.txt")
local child

local function check(mode)
  vim.fn.writefile({ mode }, temporary .. "/theme/mode")
  local replies, grid, frames = {}, {}, {}
  local unpack = vim.mpack.Unpacker()
  local serial, failure, exit_code = 0, nil, nil
  local cursor

  local function notification(message)
    if message[1] == 1 then
      replies[message[2]] = message
      return
    end
    if message[1] ~= 2 or message[2] ~= "redraw" then
      return
    end
    for _, event in ipairs(message[3]) do
      for i = 2, #event do
        local args = event[i]
        if event[1] == "grid_resize" then
          assert(args[1] == 1)
          grid = {}
          for row = 1, args[3] do
            grid[row] = {}
            for col = 1, args[2] do
              grid[row][col] = " "
            end
          end
        elseif event[1] == "grid_clear" then
          for _, row in ipairs(grid) do
            for col = 1, #row do
              row[col] = " "
            end
          end
        elseif event[1] == "grid_line" then
          local row, col = grid[args[2] + 1], args[3] + 1
          for _, cell in ipairs(args[4]) do
            for _ = 1, cell[3] or 1 do
              row[col] = cell[1]
              col = col + 1
            end
          end
        elseif event[1] == "grid_scroll" then
          local top, bottom, left, right, delta = args[2] + 1, args[3], args[4] + 1, args[5], args[6]
          assert(args[7] == 0, "Unexpected horizontal grid scroll")
          local first, last, step = top, bottom - delta, 1
          if delta < 0 then
            first, last, step = bottom, top - delta, -1
          end
          for row = first, last, step do
            for col = left, right do
              grid[row][col] = grid[row + delta][col]
            end
          end
        elseif event[1] == "grid_cursor_goto" then
          cursor = { row = args[2] + 1, col = args[3] + 1 }
        elseif event[1] == "flush" then
          local file = false
          for _, row in ipairs(grid) do
            file = file or table.concat(row):find("sample row", 1, true) ~= nil
          end
          frames[#frames + 1] = { file = file, status = table.concat(grid[#grid]), cursor = cursor }
        end
      end
    end
  end

  child = vim.fn.jobstart({
    vim.v.progpath,
    "--embed",
    "-u",
    root .. "/init.lua",
    "-i",
    "NONE",
    "-n",
    "--cmd",
    -- Keep the rendering test independent of the external AI server download.
    "lua package.loaded['configs.windsurf'] = true",
    temporary .. "/scroll.txt",
  }, {
    env = {
      XDG_CONFIG_HOME = temporary,
      XDG_CACHE_HOME = temporary .. "/cache",
      XDG_STATE_HOME = temporary .. "/state",
      NVIM_LOG_FILE = "/dev/null",
    },
    on_stdout = function(_, chunks)
      local chunk = table.concat(
        vim.tbl_map(function(part)
          return part:gsub("\n", "\0")
        end, chunks),
        "\n"
      )
      local ok, err = pcall(function()
        local position = 1
        while position <= #chunk do
          local message
          message, position = unpack(chunk, position)
          if message then
            notification(message)
          end
        end
      end)
      if not ok then
        failure = err
      end
    end,
    on_stderr = function(_, chunks)
      local output = table.concat(chunks, "\n")
      if output ~= "" then
        failure = output
      end
    end,
    on_exit = function(_, code)
      exit_code = code
    end,
  })
  assert(child > 0)

  local function wait(predicate, label)
    local done = vim.wait(10000, function()
      return failure ~= nil or exit_code ~= nil or predicate()
    end, 5)
    assert(not failure, failure)
    assert(done and predicate(), label .. "; exit=" .. tostring(exit_code))
  end

  local function request(method, args)
    serial = serial + 1
    local id = serial
    vim.fn.chansend(child, vim.mpack.encode({ 0, id, method, args }))
    wait(function()
      return replies[id] ~= nil
    end, method)
    assert(replies[id][3] == vim.NIL, vim.inspect(replies[id][3]))
    return replies[id][4]
  end

  local function lua(code, args)
    return request("nvim_exec_lua", { code, args or {} })
  end

  local function screen()
    return lua([[
      local pos = vim.fn.screenpos(0, vim.fn.line('.'), vim.fn.col('.'))
      return {row = pos.row, col = pos.curscol}
    ]])
  end

  local function settle()
    local before = #frames
    request("nvim_command", { "redraw" })
    wait(function()
      return #frames > before
    end, "UI did not redraw")
  end

  local function status_matches(row, col, progress)
    local status = frames[#frames].status
    local location = string.format("%3d:%-2d", row, col)
    assert(status:find(location, 1, true), "Wrong location: " .. status)
    assert(status:find(progress, 1, true), "Wrong progress: " .. status)
  end

  request("nvim_ui_attach", { 120, 40, { ext_linegrid = true, rgb = true } })
  wait(function()
    return #frames > 0 and frames[#frames].file
  end, "File did not render")
  for _, rendered in ipairs(frames) do
    if rendered.file then
      assert(rendered.status:find("NORMAL", 1, true), "File appeared with an empty startup statusline")
    end
  end
  status_matches(1, 1, "Top")

  lua([[
    _G.statusline_writes = 0
    vim.api.nvim_create_autocmd('OptionSet', {
      pattern = 'statusline',
      callback = function() _G.statusline_writes = _G.statusline_writes + 1 end,
    })
  ]])

  local function scroll(label)
    lua("_G.statusline_writes = 0; _G.scroll_start = vim.fn.line('.')")
    for _ = 1, 60 do
      local before = screen()
      local first = #frames + 1
      request("nvim_input", { "j" })
      local target = screen()
      wait(function()
        local last = frames[#frames].cursor
        return last.row == target.row and last.col == target.col
      end, label .. " cursor did not render: " .. vim.inspect({ target = target, actual = frames[#frames].cursor }))
      vim.wait(20)
      for i = first, #frames do
        local actual = frames[i].cursor
        assert(
          (actual.row == before.row and actual.col == before.col)
            or (actual.row == target.row and actual.col == target.col),
          label .. " cursor jumped to another screen position"
        )
      end
    end
    assert(lua("return _G.statusline_writes") == 0, label .. " rewrote the statusline while scrolling")
    assert(lua("return vim.fn.line('.') == _G.scroll_start + 60"), label .. " lost cursor movements")
  end

  vim.wait(200)
  request("nvim_command", { "normal! gg" })
  settle()
  scroll("file")
  status_matches(61, 1, "12%")

  lua("vim.api.nvim_win_set_cursor(0, {10, 5})")
  settle()
  status_matches(10, 3, " 2%")
  request("nvim_command", { "normal! G0" })
  settle()
  status_matches(500, 1, "Bot")

  request("nvim_command", { "help options" })
  request("nvim_command", { "normal! gg0" })
  vim.wait(100)
  settle()
  scroll("help split")

  local underlying = frames[#frames].status
  request("nvim_command", { "Cheatsheet" })
  vim.wait(100)
  settle()
  assert(
    frames[#frames].status == underlying,
    "Ignored float opened with a different statusline: "
      .. vim.inspect({ before = underlying, after = frames[#frames].status })
  )
  scroll("cheatsheet")
  assert(frames[#frames].status == underlying, "Cheatsheet changed the ignored window's statusline")
  lua("require('cheatsheet').hide()")
  request("nvim_command", { "close" })
  vim.wait(100)
  settle()
  status_matches(500, 1, "Bot")

  -- Shorter than the lualine timer, so only native redraws can satisfy it.
  local function expect_status(text, label, present)
    local ok = vim.wait(400, function()
      return (frames[#frames].status:find(text, 1, true) ~= nil) == (present ~= false)
    end, 5)
    assert(ok, label .. ": " .. frames[#frames].status)
  end

  -- Plugins finish debounced redraws first; a redraw loop flushes about 20 frames in the measured 300 ms.
  local function idle_frames()
    vim.wait(500)
    local before = #frames
    vim.wait(300)
    return #frames - before
  end

  request("nvim_command", { "normal! gg" })
  request("nvim_input", { "/row 1[1-9]\\><CR>" })
  expect_status("[1/9]", "Search count did not appear")
  lua("_G.statusline_writes = 0")
  request("nvim_input", { "n" })
  expect_status("[2/9]", "Search count lagged behind n")
  request("nvim_input", { "G" })
  expect_status("[9/9]", "Search count ignored cursor movement")
  assert(lua("return _G.statusline_writes") == 0, "Search count rewrote the statusline")

  request("nvim_input", { "osample row 17" })
  vim.wait(100)
  assert(
    frames[#frames].status:find("[9/9]", 1, true),
    "Search count recounted in Insert mode: " .. frames[#frames].status
  )
  request("nvim_input", { "<Esc>" })
  expect_status("[10/10]", "Search count missed an Insert mode edit")
  request("nvim_command", { "undo" })
  expect_status("[9/9]", "Search count missed an undo")
  -- An edit away from the cursor changes the count without moving it.
  lua("vim.api.nvim_buf_set_lines(0, 0, 1, false, { 'sample row 17' })")
  expect_status("[10/10]", "Search count missed an edit away from the cursor")
  request("nvim_command", { "undo | normal! G" })
  expect_status("[9/9]", "Search count missed a second undo")

  request("nvim_command", { "tabedit " .. temporary .. "/other.txt" })
  expect_status("[0/2]", "Search count kept another tab's value")
  request("nvim_input", { "G" })
  expect_status("[2/2]", "Search count ignored the new buffer")
  request("nvim_input", { "*" })
  expect_status("[1/1]", "Search count missed a pattern change without a jump")
  request("nvim_input", { "<Esc>" })
  expect_status("[1/1]", "Search count survived :nohlsearch", false)
  request("nvim_input", { "qq" })
  expect_status("recording @q", "Recording did not appear")
  request("nvim_input", { "q" })
  expect_status("recording @q", "Recording survived its end", false)

  request("nvim_command", { "edit " .. temporary .. "/case.txt" })
  request("nvim_input", { "j*" })
  expect_status("[1/4]", "Search count ignored the case rules of *")
  request("nvim_input", { ":3s/Sub/Sub/<CR>" })
  expect_status("[1/1]", "Search count ignored the :substitute pattern")
  request("nvim_command", { "undo" })

  lua([=[
    vim.cmd("enew | setlocal buftype=nofile bufhidden=wipe")
    local lines = {}
    for i = 1, 40000 do
      lines[i] = "local value_" .. i .. " = compute(alpha, beta, gamma) -- regular source text"
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.fn.setreg("/", [[compute(.*zeta]])
    vim.cmd("let v:hlsearch = 1")
  ]=])
  -- Filling the buffer delays the first frame, so wait for the value rather than a native redraw.
  wait(function()
    return frames[#frames].status:find("[?/??]", 1, true) ~= nil
  end, "Slow search did not report an incomplete count")
  local elapsed = lua([[
    local start = vim.uv.hrtime()
    for _ = 1, 20 do
      vim.cmd("normal! j")
      vim.cmd.redrawstatus()
    end
    return (vim.uv.hrtime() - start) / 1e6
  ]])
  assert(elapsed < 300, "Cursor moves rescanned the buffer: " .. elapsed .. " ms")
  request("nvim_command", { "nohlsearch" })
  request("nvim_command", { "tabclose | normal! 0" })
  settle()
  status_matches(500, 1, "Bot")

  request("nvim_command", { "vsplit" })
  settle()
  assert(frames[#frames].status:find("scroll.txt", 1, true), "Split hid components of the global statusline")
  status_matches(500, 1, "Bot")
  local wide = frames[#frames].status

  lua([[
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_open_win(buf, true, { relative = "editor", row = 1, col = 1, width = 20, height = 3 })
  ]])
  assert(lua("return vim.api.nvim_win_get_config(0).relative ~= ''"), "Float did not take focus")
  vim.wait(200)
  assert(frames[#frames].status == wide, "Focused float replaced the statusline: " .. frames[#frames].status)
  request("nvim_command", { "close" })

  request("nvim_command", { "split | vsplit" })
  settle()
  lua([[
    local lualine = require("lualine")
    local statusline = lualine.statusline
    _G.statusline_renders = 0
    lualine.statusline = function(...)
      _G.statusline_renders = _G.statusline_renders + 1
      return statusline(...)
    end
  ]])
  vim.wait(100)
  local windows = lua("_G.statusline_renders = 0; return #vim.api.nvim_tabpage_list_wins(0)")
  request("nvim_input", { "i" })
  vim.wait(100)
  local renders = lua("return _G.statusline_renders")
  -- One render per event, plus at most one timer refresh; the tabpage scope renders every window.
  assert(renders >= 1, "A mode change did not render the statusline")
  assert(renders < windows, "A mode change rendered the statusline for every window: " .. renders)
  request("nvim_input", { "<Esc>" })
  request("nvim_command", { "only" })
  settle()

  -- A hidden search count must not keep redrawing the statusline.
  request("nvim_ui_try_resize", { 80, 40 })
  request("nvim_input", { "/row 3<CR>" })
  assert(idle_frames() <= 2, "Narrow statusline redrew in a loop")
  request("nvim_command", { "nohlsearch" })
  assert(idle_frames() <= 2, "Narrow statusline redrew in a loop after :nohlsearch")
  request("nvim_ui_try_resize", { 120, 40 })
  request("nvim_input", { "/row 4<CR>" })

  request("nvim_command", { "Dashboard" })
  assert(lua("return vim.o.laststatus") == 0, "Dashboard revealed the statusline")
  assert(idle_frames() <= 2, "Dashboard redrew in a loop")
  request("nvim_command", { "nohlsearch" })
  assert(idle_frames() <= 2, "Dashboard redrew in a loop after :nohlsearch")
  request("nvim_command", { "enew" })
  assert(lua("return vim.o.laststatus") == 3, "Dashboard did not restore the statusline")

  -- The search count keeps working after the config is reloaded with :source.
  request("nvim_command", { "source " .. root .. "/lua/configs/lualine.lua" })
  request("nvim_command", { "edit " .. temporary .. "/other.txt" })
  request("nvim_input", { "/row<CR>" })
  expect_status("[1/2]", "Search count broke after reloading the config")
  request("nvim_input", { "<Esc>" })
  expect_status("[1/2]", "Search count survived :nohlsearch after reloading the config", false)

  -- Gitsigns skips files longer than its max_file_length, which still belong to the working directory repo.
  local repo, branch = temporary .. "/repo-" .. mode, "lualine-branch"
  local git = { "git", "-C", repo, "-c", "user.name=test", "-c", "user.email=test@example.invalid" }
  vim.list_extend(git, { "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null" })
  vim.fn.mkdir(repo)
  assert(vim.system(vim.list_extend(vim.deepcopy(git), { "init", "-q", "-b", branch })):wait().code == 0)
  assert(
    vim.system(vim.list_extend(vim.deepcopy(git), { "commit", "-q", "--allow-empty", "-m", "init" })):wait().code == 0
  )
  local long = {}
  for i = 1, 40001 do
    long[i] = "line " .. i
  end
  vim.fn.writefile(long, repo .. "/long.txt")
  request("nvim_command", { "cd " .. repo })
  for _ = 1, 200 do
    if lua("return vim.g.gitsigns_head") == branch then
      break
    end
    vim.wait(50)
  end
  assert(lua("return vim.g.gitsigns_head") == branch, "Gitsigns did not report the working directory branch")
  vim.wait(300)
  assert(not frames[#frames].status:find(branch, 1, true), "A file outside the working directory showed its branch")
  request("nvim_command", { "edit " .. repo .. "/long.txt" })
  wait(function()
    return frames[#frames].status:find(branch .. " ", 1, true) ~= nil
  end, "A file skipped by Gitsigns hid the branch")

  vim.fn.chansend(child, vim.mpack.encode({ 2, "nvim_command", { "qa!" } }))
  wait(function()
    return exit_code ~= nil
  end, "Neovim did not exit")
  assert(exit_code == 0)
  child = nil
  print(
    "Lualine UI passed ("
      .. mode
      .. "): first frame, native position/progress, Unicode, scroll, search, recording, splits and floats"
  )
end

local ok, err = xpcall(function()
  check("dark")
  check("light")
end, debug.traceback)
if child then
  vim.fn.jobstop(child)
  vim.fn.jobwait({ child }, 3000)
end
vim.fn.delete(temporary, "rf")
assert(ok, err)
