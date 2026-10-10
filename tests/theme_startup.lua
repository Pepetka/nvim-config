-- Run: NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -n -l tests/theme_startup.lua
-- Attach an actual RPC UI and inspect every flushed frame, including the first.
local root = vim.fn.getcwd()
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary .. "/theme", "p")
assert(vim.uv.fs_symlink(root, temporary .. "/nvim", { dir = true }))
local child
local timings = {}

local function check_startup(mode)
  vim.fn.writefile({ mode }, temporary .. "/theme/mode")
  local replies, grids, attributes, frames = {}, {}, {}, {}
  local unpack = vim.mpack.Unpacker()
  local serial, failure, exit_code = 0, nil, nil
  local started = vim.uv.hrtime()

  local function frame()
    local grid = grids[1]
    if not grid then
      return
    end
    local result = { ms = (vim.uv.hrtime() - started) / 1e6 }
    for row, cells in ipairs(grid) do
      local text = table.concat(vim.tbl_map(function(cell)
        return cell.text
      end, cells))
      if text:find("██████╗    ██████╗", 1, true) then
        result.header = row
      end
      if text:find("plugins · config", 1, true) then
        result.footer = true
      end
      if text:find("Find file", 1, true) then
        result.key = text:find("[f]", 1, true) ~= nil
        for col = 1, #cells - 3 do
          if cells[col].text == "F" and cells[col + 1].text == "i" and cells[col + 2].text == "n" then
            result.description_fg = (attributes[cells[col].hl] or {}).foreground
            break
          end
        end
      end
    end
    if result.header then
      frames[#frames + 1] = result
    end
  end

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
          local grid = {}
          for row = 1, args[3] do
            grid[row] = {}
            for col = 1, args[2] do
              grid[row][col] = { text = " ", hl = 0 }
            end
          end
          grids[args[1]] = grid
        elseif event[1] == "grid_clear" then
          for _, row in ipairs(grids[args[1]]) do
            for col = 1, #row do
              row[col] = { text = " ", hl = 0 }
            end
          end
        elseif event[1] == "hl_attr_define" then
          attributes[args[1]] = args[2]
        elseif event[1] == "grid_line" then
          local row, col, hl = grids[args[1]][args[2] + 1], args[3] + 1, 0
          for _, cell in ipairs(args[4]) do
            hl = cell[2] or hl
            for _ = 1, cell[3] or 1 do
              row[col] = { text = cell[1], hl = hl }
              col = col + 1
            end
          end
        elseif event[1] == "flush" then
          frame()
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
    -- Fail if rendering regresses to querying every plugin's Git metadata.
    "lua local get = vim.pack.get; vim.pack.get = function(names, opts) "
      .. "assert(opts and opts.info == false, 'Startup requested plugin Git metadata'); return get(names, opts) end",
  }, {
    env = {
      XDG_CONFIG_HOME = temporary,
      XDG_CACHE_HOME = temporary .. "/cache",
      XDG_STATE_HOME = temporary .. "/state",
      NVIM_LOG_FILE = "/dev/null",
    },
    on_stdout = function(_, lines)
      local chunk = table.concat(
        vim.tbl_map(function(line)
          -- Job callbacks represent NUL as newline inside each list element.
          return line:gsub("\n", "\0")
        end, lines),
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
    on_stderr = function(_, lines)
      local text = table.concat(lines, "\n")
      if text ~= "" then
        failure = text
      end
    end,
    on_exit = function(_, code)
      exit_code = code
    end,
  })
  assert(child > 0, "Could not start Neovim")

  local function wait(predicate, label)
    local done = vim.wait(10000, function()
      return failure ~= nil or exit_code ~= nil or predicate()
    end, 10)
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
    local reply = replies[id]
    assert(reply[3] == vim.NIL, vim.inspect(reply[3]))
    return reply[4]
  end

  request("nvim_ui_attach", { 120, 50, { ext_linegrid = true, rgb = true } })
  wait(function()
    return #frames > 0
  end, "No dashboard frame")
  local state = request("nvim_exec_lua", {
    "local c = require('utils.colors'); return { bg = vim.o.background, muted = c.muted, "
      .. "laststatus = vim.o.laststatus, showtabline = vim.o.showtabline }",
    {},
  })
  assert(state.bg == mode and state.laststatus == 0 and state.showtabline == 0)
  local muted = tonumber(state.muted:sub(2), 16)
  local first = frames[1]
  assert(first.header > 1, "First dashboard frame was not vertically centered")
  assert(first.footer and first.key, "First dashboard frame was incomplete")
  assert(first.description_fg == muted, "First dashboard frame had default action colors")
  timings[mode] = first.ms

  local opposite = mode == "dark" and "light" or "dark"
  for _, target in ipairs({ opposite, mode }) do
    local before = #frames
    vim.fn.writefile({ target }, temporary .. "/theme/mode")
    assert(request("nvim_exec_lua", {
      "local mode = ...; return vim.wait(1800, function() return vim.o.background == mode end, 10)",
      { target },
    }))
    wait(function()
      return #frames > before
    end, "Theme did not redraw dashboard")
    for i = before + 1, #frames do
      assert(frames[i].header == first.header, "Theme changed dashboard position")
      assert(frames[i].footer and frames[i].key, "Theme exposed a partial dashboard")
    end
    assert(request("nvim_get_option_value", { "laststatus", {} }) == 0, "Theme revealed statusline")
  end

  request("nvim_ui_try_resize", { 140, 60 })
  wait(function()
    return frames[#frames].header ~= first.header
  end, "Dashboard did not recenter on resize")
  for _, rendered in ipairs(frames) do
    assert(rendered.footer and rendered.key, "Resize exposed a partial dashboard")
  end

  request("nvim_command", { "enew" })
  local status = request("nvim_get_option_value", { "laststatus", {} })
  assert(status == 3, "Leaving dashboard did not restore the statusline")
  local before = #frames
  request("nvim_command", { "Dashboard" })
  wait(function()
    return #frames > before
  end, "Dashboard did not reopen")
  local reopened = frames[#frames]
  assert(
    reopened.footer and reopened.key and reopened.description_fg == muted,
    "Reopened dashboard is incomplete: "
      .. vim.inspect(reopened)
      .. "; "
      .. request("nvim_exec_lua", { "return vim.v.errmsg", {} })
  )

  -- Requests may not reply during shutdown; send a notification instead.
  vim.fn.chansend(child, vim.mpack.encode({ 2, "nvim_command", { "qa!" } }))
  wait(function()
    return exit_code ~= nil
  end, "Neovim did not exit")
  assert(exit_code == 0)
  child = nil
end

local ok, err = xpcall(function()
  check_startup("dark")
  check_startup("light")
end, debug.traceback)
if child then
  vim.fn.jobstop(child)
  vim.fn.jobwait({ child }, 3000)
end
vim.fn.delete(temporary, "rf")
assert(ok, err)
print(
  string.format(
    "Dashboard UI passed: first colored/centered frame dark %.0f ms, light %.0f ms; resize/reopen",
    timings.dark,
    timings.light
  )
)
