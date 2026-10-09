local config = require("cheatsheet.core.config")
local mappings = require("cheatsheet.core.mappings")
local modes = require("cheatsheet.core.modes")
local layout = require("cheatsheet.core.layout")
local M = {}

---Create a controller with an injected Neovim adapter (or a test double).
---@param adapter CheatsheetAdapter
---@return CheatsheetController
function M.new(adapter)
  local initialized = false
  ---@type CheatsheetConfig?
  local options
  ---@type CheatsheetMode?
  local mode
  ---@type CheatsheetSession?
  local session
  ---@type CheatsheetGeometry?
  local geometry
  local updating = false
  local controller = {}

  ---@param err unknown
  ---@return nil
  local function report(err)
    adapter.notify("cheatsheet: " .. tostring(err), "ERROR")
  end

  ---@return boolean
  local function ready()
    if not initialized then
      report("setup() must be called first")
      return false
    end
    return true
  end

  ---@return nil
  function controller.hide()
    local previous, previous_mode, previous_geometry = session, mode, geometry
    session, geometry = nil, nil
    mode = options and options.modes[1] or nil
    adapter.displayed(false)
    if previous then
      local ok, err = pcall(adapter.close, previous)
      if not ok then
        if adapter.exists(previous) then
          session, mode, geometry = previous, previous_mode, previous_geometry
          adapter.displayed(adapter.valid(previous))
        end
        report(err)
      end
    end
  end

  ---@param reset boolean
  ---@param size? CheatsheetGeometry
  ---@return nil
  local function render(reset, size)
    local options, mode, session = assert(options), assert(mode), assert(session)
    local global, local_mappings = adapter.collect(mode, session.source_buf)
    local groups = mappings.build(global, local_mappings, options, { mode = mode, leader = adapter.leader() })
    size = size or layout.geometry(options.window, adapter.viewport())
    local document = layout.build(groups, mode, options, size.width, adapter.measure)
    adapter.update(session, size, document, reset)
    geometry = size
  end

  ---@param requested_mode? CheatsheetMode
  ---@return nil
  function controller.show(requested_mode)
    if not ready() or updating then
      return
    end
    local options = assert(options)
    local selected = requested_mode
    if selected == nil then
      selected = mode
    end
    if not modes.index(options.modes, selected) then
      report("mode must be one of the configured modes")
      return
    end
    if session and not adapter.valid(session) then
      controller.hide()
      if session then
        return
      end
    end
    mode = assert(selected)
    updating = true
    local ok, err = pcall(function()
      local size = layout.geometry(options.window, adapter.viewport())
      if not session then
        local source_buf, source_win = adapter.source()
        local creation_error
        session, creation_error = adapter.create(options, source_buf, source_win, {
          close = controller.hide,
          next_mode = controller.next_mode,
          prev_mode = controller.prev_mode,
        }, size)
        if creation_error then
          error(creation_error, 0)
        end
      end
      render(true, size)
      adapter.displayed(true)
    end)
    updating = false
    if not ok then
      controller.hide()
      report(err)
    end
  end

  ---@return nil
  function controller.toggle()
    if session and adapter.valid(session) then
      controller.hide()
    else
      controller.show()
    end
  end

  ---@param direction integer
  ---@return nil
  local function cycle(direction)
    if ready() then
      controller.show(modes.cycle(assert(options).modes, mode, direction))
    end
  end

  ---@return nil
  function controller.next_mode()
    cycle(1)
  end

  ---@return nil
  function controller.prev_mode()
    cycle(-1)
  end

  ---@return nil
  function controller.resize()
    if updating or not session then
      return
    end
    if not adapter.valid(session) then
      controller.hide()
      return
    end
    updating = true
    local ok, err = pcall(function()
      local size = layout.geometry(assert(options).window, adapter.viewport())
      if
        geometry
        and size.width == geometry.width
        and size.height == geometry.height
        and size.row == geometry.row
        and size.col == geometry.col
      then
        return
      end
      render(false, size)
    end)
    updating = false
    if not ok then
      controller.hide()
      report(err)
    end
  end

  ---@param kind CheatsheetResourceKind
  ---@param id integer
  ---@return nil
  function controller.closed(kind, id)
    if session and session[kind] == id then
      -- The resource is already being removed; dispose only its counterpart.
      session[kind] = nil
      controller.hide()
    end
  end

  ---@param opts? CheatsheetConfigPartial
  ---@return nil
  function controller.setup(opts)
    if initialized then
      adapter.notify("cheatsheet: already initialized", "WARN")
      return
    end
    local diagnostics
    options, diagnostics = config.normalize(opts)
    for _, message in ipairs(diagnostics) do
      adapter.notify(message, "WARN")
    end
    mode = options.modes[1]
    local ok, err = pcall(adapter.install, options, {
      toggle = controller.toggle,
      resize = controller.resize,
      closed = controller.closed,
    })
    if not ok then
      options, mode = nil, nil
      report(err)
      return
    end
    adapter.displayed(false)
    initialized = true
  end

  return controller
end

return M
