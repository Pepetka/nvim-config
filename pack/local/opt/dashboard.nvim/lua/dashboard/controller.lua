local rules = require("dashboard.core.config")
local blocks = require("dashboard.core.blocks")
local layout = require("dashboard.core.layout")
local navigation = require("dashboard.core.navigation")
local styles = require("dashboard.core.styles")
local keys = require("dashboard.core.keys")
local measurements = require("dashboard.core.measure")
local M = {}

---@param adapter DashboardAdapter
---@return DashboardController
function M.new(adapter)
  local public = {}
  ---@cast public DashboardController
  ---@type DashboardConfig?
  local config
  ---@type DashboardStyles
  local current_styles = {}
  ---@type table<integer, DashboardSession>
  local sessions = {}
  local installed, busy, queued = false, false, false
  local generation = 0

  ---@param fn fun(): nil
  ---@return nil
  local function protect(fn)
    if busy then
      return
    end
    busy = true
    local ok, err = xpcall(fn, debug.traceback)
    busy = false
    if not ok then
      adapter.notify(tostring(err))
    end
  end

  ---@param options DashboardConfig
  ---@return DashboardStyles
  local function theme_styles(options)
    local input = options.highlights
    if type(input) == "function" then
      return styles.resolve(input())
    end
    return styles.resolve(input)
  end

  ---@param session DashboardSession
  ---@return DashboardContext
  local function context(session)
    local result = adapter.context(session.win)
    result.source_buf = session.source_buf
    return result
  end

  ---@param options DashboardConfig
  ---@param ctx DashboardContext
  ---@return DashboardDocument
  local function build(options, ctx)
    local measure = measurements.cached(adapter.measure)
    local fragments, ids, layouts = {}, {}, {}
    for _, block in ipairs(options.blocks) do
      local enabled = block.enabled
      if type(enabled) == "function" then
        enabled = enabled(ctx)
        assert(type(enabled) == "boolean", "block.enabled must return boolean")
      end
      if enabled ~= false then
        local fragment
        if block.type == "text" then
          local lines = block.lines
          if type(lines) == "function" then
            lines = lines(ctx)
          end
          fragment = blocks.text(lines, block.style or "Text")
        elseif block.type == "actions" then
          local items = block.items
          if type(items) == "function" then
            items = items(ctx)
          end
          fragment = blocks.actions(items, block.label_width or 0, block.spacing or 1, measure)
        else
          fragment = blocks.validate(block.render(ctx))
        end
        fragments[#fragments + 1], ids[#ids + 1] = fragment, block.id
        layouts[#layouts + 1] = block.layout or {}
      end
    end
    return layout.compose(
      fragments,
      ids,
      ctx,
      options.layout,
      measure,
      adapter.normalize_key,
      { block_layouts = layouts, navigation = options.navigation.keys }
    )
  end

  ---@param session DashboardSession
  ---@param document DashboardDocument
  ---@return nil
  local function publish(session, document)
    local selected = navigation.preserve(document.targets, session.selected)
    adapter.apply(session, document, selected)
    session.document, session.selected = document, selected
  end

  ---@param win integer
  ---@param restore boolean
  ---@return nil
  local function close(win, restore)
    local session = sessions[win]
    if session then
      adapter.close(session, restore)
      sessions[win] = nil
    end
  end

  ---@param options? DashboardOptions
  ---@return nil
  function public.setup(options)
    protect(function()
      local candidate = rules.normalize(options)
      keys.reserved(candidate.navigation.keys, adapter.normalize_key)
      local candidate_styles = theme_styles(candidate)
      ---@type table<integer, DashboardDocument>
      local documents = {}
      ---@type table<integer, DashboardContext>
      local contexts = {}
      for win, session in pairs(sessions) do
        if adapter.valid(session) then
          contexts[win] = context(session)
          documents[win] = build(candidate, contexts[win])
        end
      end
      local previous, previous_styles = config, current_styles
      local ok, err = pcall(function()
        adapter.configure(candidate, candidate_styles)
        if not installed then
          adapter.install({
            show = public.show,
            refresh = public.refresh,
            changed = public.changed,
            theme = public.theme,
            move = public.move,
            activate = public.activate,
          })
        end
        for win, document in pairs(documents) do
          local ctx = context(sessions[win])
          if ctx.width ~= contexts[win].width or ctx.height ~= contexts[win].height then
            document = build(candidate, ctx)
            documents[win] = document
          end
          adapter.apply(sessions[win], document, navigation.preserve(document.targets, sessions[win].selected))
        end
      end)
      if not ok then
        if previous then
          adapter.configure(previous, previous_styles)
          for win in pairs(documents) do
            local session = sessions[win]
            adapter.apply(session, session.document, session.selected)
          end
        else
          adapter.uninstall()
        end
        error(err)
      end
      installed, config, current_styles = true, candidate, candidate_styles
      for win, document in pairs(documents) do
        local session = sessions[win]
        session.selected = navigation.preserve(document.targets, session.selected)
        session.document = document
      end
      adapter.reconcile()
    end)
  end

  ---@param win? integer
  ---@return nil
  function public.show(win)
    protect(function()
      local options = assert(config, "call dashboard.setup() before show()")
      local ctx = adapter.context(win)
      local existing = sessions[ctx.win]
      if existing and adapter.valid(existing) then
        publish(existing, build(options, context(existing)))
        return
      end
      close(ctx.win, false)
      -- A native split initially shares its parent's scratch buffer.
      for _, parent in pairs(sessions) do
        if parent.buf == ctx.source_buf then
          ctx.source_buf = parent.source_buf
          break
        end
      end
      local ok, err = pcall(function()
        local session = adapter.create(ctx, function(created)
          sessions[ctx.win] = created
        end)
        publish(session, build(options, context(session)))
      end)
      if not ok then
        local cleaned, cleanup_error = pcall(close, ctx.win, true)
        if not cleaned then
          error(tostring(err) .. "\nDashboard cleanup failed: " .. tostring(cleanup_error))
        end
        error(err)
      end
      adapter.reconcile()
    end)
  end

  ---@param win? integer
  ---@return nil
  function public.hide(win)
    protect(function()
      close(adapter.context(win).win, true)
      adapter.reconcile()
    end)
  end

  ---@param win? integer
  ---@return nil
  function public.refresh(win)
    protect(function()
      if not config then
        return
      end
      local target = win and adapter.context(win).win
      for id, session in pairs(sessions) do
        if (not target or id == target) and adapter.valid(session) then
          local ok, err = pcall(function()
            publish(session, build(config, context(session)))
          end)
          if not ok then
            adapter.notify("Dashboard window " .. id .. ": " .. tostring(err))
          end
        end
      end
      adapter.reconcile()
    end)
  end

  ---@return nil
  function public.theme()
    protect(function()
      if config then
        local candidate
        local ok, err = pcall(function()
          candidate = theme_styles(config)
          adapter.styles(candidate)
        end)
        if not ok then
          adapter.styles(current_styles)
          error(err)
        end
        current_styles = candidate
        adapter.reconcile()
      end
    end)
  end

  ---@param win integer
  ---@param delta integer
  ---@return nil
  function public.move(win, delta)
    protect(function()
      local session = sessions[win]
      if session and adapter.valid(session) then
        local selected =
          navigation.move(session.document.targets, session.selected, delta, config and config.navigation.wrap)
        adapter.select(session, selected)
        session.selected = selected
      end
    end)
  end

  ---@param win integer
  ---@param block_id? string
  ---@param id? string
  ---@return nil
  function public.activate(win, block_id, id)
    -- Run outside the orchestration lock: actions may call the public API.
    local session = sessions[win]
    if not session or not adapter.valid(session) then
      return
    end
    local selected = session.selected
    if id then
      local index =
        navigation.index(session.document.targets, { id = id, block_id = block_id, row = 0, col = 0, run = "" })
      selected = index and session.document.targets[index] or nil
    end
    if selected then
      local ok, err = pcall(adapter.run, selected.run, context(session))
      if not ok then
        adapter.notify(tostring(err))
      end
    end
  end

  ---@return nil
  function public.changed()
    if queued then
      return
    end
    queued = true
    local ticket = generation
    adapter.schedule(function()
      if ticket ~= generation then
        return
      end
      queued = false
      -- Adopt split views before disposing of a parent closed in the same turn.
      for _, win in ipairs(adapter.aliases()) do
        public.show(win)
      end
      protect(function()
        for win, session in pairs(sessions) do
          if not adapter.valid(session) then
            close(win, false)
          end
        end
        adapter.reconcile()
      end)
    end)
  end

  ---@return nil
  function public.teardown()
    protect(function()
      generation, queued = generation + 1, false
      for win in pairs(sessions) do
        close(win, true)
      end
      adapter.uninstall()
      config, current_styles, installed = nil, {}, false
    end)
  end

  return public
end

return M
