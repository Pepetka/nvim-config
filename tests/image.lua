-- Run: NVIM_LOG_FILE=/dev/null nvim --headless -u NONE -i NONE -n -l tests/image.lua
-- Drive the real config in a native TUI with real keys and read the Kitty commands it writes to the terminal.
local root = vim.fn.getcwd()
local temporary = vim.fn.tempname()
local work = temporary .. "/work"
local site = vim.fn.stdpath("data") .. "/site"
local placeholder = vim.fn.nr2char(0x10EEEE)
local columns, lines = 170, 50
local sessions = 0
local child

vim.fn.mkdir(work, "p")
vim.fn.mkdir(temporary .. "/data/nvim", "p")
assert(vim.fn.executable("magick") == 1, "ImageMagick is required")
assert(vim.fn.executable("fzf") == 1, "fzf is required")
assert(vim.uv.fs_symlink(root, temporary .. "/nvim", { dir = true }))
assert(vim.uv.fs_symlink(site, temporary .. "/data/nvim/site", { dir = true }))
for name, colors in pairs({ ["big.png"] = "gradient:red-blue", ["big.jpg"] = "gradient:green-black" }) do
  local result = vim.system({ "magick", "-size", "1600x1000", colors, work .. "/" .. name }):wait()
  assert(result.code == 0, result.stderr)
end
vim.fn.writefile({ "not an image" }, work .. "/broken.jpg")
vim.fn.writefile({ "plain text" }, work .. "/note.txt")
vim.fn.writefile({ "# Document", "", "![picture](big.png)", "" }, work .. "/doc.md")

---@return any
local function run(session, code)
  return vim.rpcrequest(session.channel, "nvim_exec_lua", code, {})
end

local function start()
  sessions = sessions + 1
  local socket = temporary .. "/nvim-" .. sessions .. ".sock"
  local session = { chunks = {}, buffer = vim.api.nvim_create_buf(false, true) }
  vim.api.nvim_set_current_buf(session.buffer)
  session.job = vim.fn.jobstart({
    vim.v.progpath,
    "-u",
    root .. "/init.lua",
    "-i",
    "NONE",
    "-n",
    "--listen",
    socket,
    "--cmd",
    "lua for _, name in ipairs({ 'mason', 'lsp' }) do package.loaded['configs.' .. name] = true end",
    "note.txt",
  }, {
    term = true,
    cwd = work,
    clear_env = true,
    env = {
      HOME = vim.env.HOME,
      PATH = vim.env.PATH,
      LANG = "en_US.UTF-8",
      TERM = "xterm-256color",
      XDG_CONFIG_HOME = temporary,
      XDG_DATA_HOME = temporary .. "/data",
      XDG_STATE_HOME = temporary .. "/state",
      XDG_CACHE_HOME = temporary .. "/cache-" .. sessions,
      NVIM_LOG_FILE = "/dev/null",
      SNACKS_GHOSTTY = "true",
    },
    on_stdout = function(_, data)
      session.chunks[#session.chunks + 1] = table.concat(data, "\n")
    end,
  })
  assert(session.job > 0, "Could not start the native TUI")
  vim.fn.jobresize(session.job, columns, lines)
  assert(
    vim.wait(10000, function()
      return vim.uv.fs_stat(socket) ~= nil
    end, 10),
    "Native TUI did not listen"
  )
  session.channel = vim.fn.sockconnect("pipe", socket, { rpc = true })
  child = session
  assert(
    vim.wait(10000, function()
      return run(session, "return Snacks ~= nil and vim.fn.mode()") == "n"
    end, 20),
    "Native TUI did not reach Normal mode"
  )
  -- A jobstart pty reports zero pixels, which real terminals never do.
  run(
    session,
    string.format(
      [[
      Snacks.image.terminal.size = function()
        return { width = %d, height = %d, columns = %d, rows = %d, cell_width = 10, cell_height = 20, scale = 1.25 }
      end
    ]],
      columns * 10,
      lines * 20,
      columns,
      lines
    )
  )
  return session
end

local function stop(session)
  vim.fn.jobstop(session.job)
  vim.fn.jobwait({ session.job }, 1000)
  vim.api.nvim_buf_delete(session.buffer, { force = true })
  child = nil
end

local function keys(session, input)
  vim.fn.chansend(session.job, input)
end

local function output(session)
  return table.concat(session.chunks)
end

local function await(message, predicate)
  assert(vim.wait(15000, predicate, 20), message)
end

local function await_filetype(session, filetype)
  await("Filetype did not become " .. filetype, function()
    return run(session, "return vim.bo.filetype") == filetype
  end)
end

-- Upvalue 1 of Placement.clean is the placement registry of the running session.
local placements_code = [[
  local _, registry = debug.getupvalue(Snacks.image.placement.clean, 1)
  local result = {}
  for buf, placements in pairs(registry) do
    for id, placement in pairs(placements) do
      local state = placement._state
      result[#result + 1] = {
        id = id,
        buf = buf,
        src = vim.fs.basename(placement.img.src),
        image = placement.img.id,
        visible = #placement:wins() > 0,
        hidden = placement.hidden or false,
        inline = placement.opts.inline or false,
        failed = placement.img:failed() or false,
        ready = state ~= nil,
        width = state and state.loc.width or 0,
        height = state and state.loc.height or 0,
      }
    end
  end
  return result
]]

local function placements(session)
  return run(session, placements_code)
end

local function find(session, src, inline)
  for _, placement in ipairs(placements(session)) do
    if placement.src == src and placement.visible and placement.ready and placement.inline == (inline or false) then
      return placement
    end
  end
end

local function await_placement(session, src, inline)
  local placement
  await("No visible placement for " .. src, function()
    placement = find(session, src, inline)
    return placement ~= nil
  end)
  return placement
end

---@return {a?: string, d?: string, t?: string, i?: string, p?: string, c?: string, r?: string}[]
local function commands(text)
  local result = {}
  for control in text:gmatch("\27_G([^;\27]*);?[^\27]*\27\\") do
    local command = {}
    for key, value in control:gmatch("(%a)=([^,]*)") do
      command[key] = value
    end
    result[#result + 1] = command
  end
  return result
end

-- Neovim drops the placement id from the cells, so Ghostty picks the lowest id among these placements.
local function terminal_placements(session, image)
  local result = {}
  for _, command in ipairs(commands(output(session))) do
    if command.a == "p" and command.i == tostring(image) then
      result[#result + 1] = { id = tonumber(command.p), width = tonumber(command.c), height = tonumber(command.r) }
    elseif command.a == "d" and command.i == tostring(image) then
      result = vim.tbl_filter(function(placement)
        return command.p ~= nil and placement.id ~= tonumber(command.p)
      end, result)
    end
  end
  return result
end

local function assert_only_placement(session, placement)
  local expected = { { id = placement.id, width = placement.width, height = placement.height } }
  local actual
  await("Terminal keeps a stale placement, expected " .. vim.inspect(expected), function()
    actual = terminal_placements(session, placement.image)
    return vim.deep_equal(actual, expected)
  end)
end

local function assert_redrawn(session, from, placement, retransmitted)
  await("Image was not redrawn: " .. vim.inspect(placement), function()
    local text = output(session):sub(from + 1)
    local transmitted, placed = false, false
    for _, command in ipairs(commands(text)) do
      if command.i == tostring(placement.image) then
        transmitted = transmitted or command.t == "f"
        placed = placed or command.a == "p"
        assert(transmitted or not retransmitted or not placed, "Image was placed before its data was sent")
      end
    end
    return placed and text:find(placeholder, 1, true) ~= nil and find(session, placement.src, placement.inline) ~= nil
  end)
end

local function assert_cells_redrawn(session, from, placement)
  await("Cells were not redrawn", function()
    return output(session):sub(from + 1):find(placeholder, 1, true) ~= nil
  end)
  assert_only_placement(session, placement)
end

local function await_deleted(session, from, placement)
  await("Hidden placement stayed in the terminal", function()
    for _, command in ipairs(commands(output(session):sub(from + 1))) do
      if command.a == "d" and command.d == "I" and command.i == tostring(placement.image) then
        return true
      end
    end
    return false
  end)
end

local function assert_unmodified(session, description)
  assert(not run(session, "return vim.bo.modified"), description .. " left the buffer modified")
end

local function await_picker(session)
  await("Picker did not open", function()
    return run(session, "return vim.bo.filetype .. vim.fn.mode()") == "fzft"
  end)
end

local function open_picker(session, query)
  keys(session, " ff")
  await_picker(session)
  keys(session, query)
end

local function resume_picker(session)
  -- The hide action of the fzf process lands after the key and would close a picker resumed sooner.
  vim.wait(1000)
  keys(session, " fr")
  await_picker(session)
end

local function check_fzf_open()
  local session = start()
  open_picker(session, "big.png")
  local preview = await_placement(session, "big.png")
  keys(session, "\r")
  await_filetype(session, "image")
  local placement
  await("Buffer placement did not replace the preview", function()
    placement = find(session, "big.png")
    return placement ~= nil and placement.id ~= preview.id
  end)
  assert(placement.width > preview.width, "Buffer image is not larger than its preview")
  assert_only_placement(session, placement)

  local from = #output(session)
  keys(session, "\t")
  await_deleted(session, from, placement)
  from = #output(session)
  keys(session, "\t")
  await_filetype(session, "image")
  assert_redrawn(session, from, placement, true)
  assert_only_placement(session, placement)

  from = #output(session)
  resume_picker(session)
  assert_redrawn(session, from, preview)
  keys(session, "\27")
  await_filetype(session, "image")
  assert_only_placement(session, placement)
  stop(session)
  print("Image passed: fzf opens the full-size buffer image, and it survives <Tab> and resume")
end

local function check_preview()
  local session = start()
  open_picker(session, "big.")
  local first = await_placement(session, "big.jpg")
  keys(session, "\27[B")
  await_placement(session, "big.png")
  local from = #output(session)
  keys(session, "\27[A")
  await_placement(session, "big.jpg")
  assert_cells_redrawn(session, from, first)

  from = #output(session)
  keys(session, "\27")
  await("Picker did not hide", function()
    return run(session, "return vim.bo.filetype") ~= "fzf"
  end)
  await_deleted(session, from, first)
  from = #output(session)
  resume_picker(session)
  assert_redrawn(session, from, first, true)
  assert_only_placement(session, first)
  stop(session)
  print("Image passed: fzf preview survives moving between entries, hide and resume")
end

local function check_visibility()
  local session = start()
  keys(session, ":e big.png\r")
  await_filetype(session, "image")
  local placement = await_placement(session, "big.png")

  local from = #output(session)
  keys(session, "\t")
  await_deleted(session, from, placement)
  from = #output(session)
  keys(session, "\t")
  await_filetype(session, "image")
  assert_redrawn(session, from, placement, true)

  from = #output(session)
  keys(session, ":tabnew\r")
  await_deleted(session, from, placement)
  from = #output(session)
  keys(session, ":tabprevious\r")
  await_filetype(session, "image")
  assert_redrawn(session, from, placement, true)

  keys(session, " x")
  await("<leader>x did not close the image", function()
    return run(session, "return vim.bo.filetype") ~= "image"
  end)
  assert_unmodified(session, "Closing an image")
  from = #output(session)
  keys(session, ":e big.png\r")
  await_filetype(session, "image")
  assert_redrawn(session, from, await_placement(session, "big.png"), true)
  stop(session)
  print("Image passed: buffers and tabs restore images, and a closed image opens again")
end

local function check_modified()
  local session = start()
  keys(session, ":e big.jpg\r")
  await_filetype(session, "image")
  await_placement(session, "big.jpg")
  assert_unmodified(session, "The first uncached image")

  keys(session, ":e broken.jpg\r")
  await("Conversion failure was not reported", function()
    local text = run(session, "return table.concat(vim.api.nvim_buf_get_lines(0, 0, 1, false))")
    return text:find("Image Conversion Failed", 1, true) ~= nil
  end)
  assert_unmodified(session, "A failed conversion")
  stop(session)
  print("Image passed: loading and failed images stay unmodified")
end

local function check_inline()
  local session = start()
  keys(session, ":e doc.md\r")
  await_filetype(session, "markdown")
  local placement = await_placement(session, "big.png", true)
  keys(session, ":enew\r")
  await_filetype(session, "")
  local from = #output(session)
  keys(session, ":buffer doc.md\r")
  await_filetype(session, "markdown")
  assert_cells_redrawn(session, from, placement)

  keys(session, "Go![broken](broken.jpg)\27")
  await("Inline conversion did not fail", function()
    return vim.iter(placements(session)):any(function(item)
      return item.src == "broken.jpg" and item.failed
    end)
  end)
  vim.wait(200)
  assert(run(session, "return vim.bo.modified"), "A failed inline image dropped unsaved changes")
  stop(session)
  print("Image passed: inline images keep working and unsaved documents stay modified")
end

local ok, err = xpcall(function()
  check_fzf_open()
  check_preview()
  check_visibility()
  check_modified()
  check_inline()
end, debug.traceback)
if child then
  stop(child)
end
vim.fn.delete(temporary, "rf")
assert(ok, err)
