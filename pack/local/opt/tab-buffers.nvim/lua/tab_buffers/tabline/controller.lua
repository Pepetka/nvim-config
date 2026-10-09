local lists = require("tab_buffers.core.lists")
local layout = require("tab_buffers.core.layout")
local width_cache = require("tab_buffers.core.metrics")
local config_rules = require("tab_buffers.core.config")
local panel = require("tab_buffers.core.panel")
local M = {}

---@param adapter TabBuffersPanelAdapter
---@param buffers TabBuffers
---@return TabBuffersTabline
function M.new(adapter, buffers)
  local public = {}
  ---@cast public TabBuffersTabline
  local config = config_rules.normalize()
  ---@type TabBuffersAction?
  local cancel
  local cached = ""
  ---@type table<integer, TabBuffersPanelItem>
  local targets = {}
  ---@type table<integer, integer>
  local last_active = {}
  local generation, queued, serial = 0, false, 0
  local metrics = width_cache.new(adapter.metrics)
  ---@type TabBuffersPanelSnapshot?
  local previous_snapshot
  ---@type TabBuffersLabelEntry[]?
  local label_entries
  ---@type table<integer, string>?
  local labels
  local label_width = 0

  ---@return nil
  local function invalidate()
    metrics = width_cache.new(adapter.metrics)
    previous_snapshot, label_entries, labels = nil, nil, nil
  end

  ---@param document TabBuffersPanelDocument
  ---@return nil
  local function publish(document)
    cached, targets = document.text, document.targets
    last_active, serial = document.last_active, document.next_target
    adapter.redraw()
  end

  ---@param options TabBuffersTablineConfig
  ---@param snapshot TabBuffersPanelSnapshot
  ---@return TabBuffersPanelDocument
  local function build(options, snapshot)
    local entries = {}
    for _, entry in ipairs(snapshot.entries) do
      entries[#entries + 1] = { id = entry.id, name = entry.name }
    end
    if label_width ~= options.max_name_length or not lists.equal(label_entries, entries) then
      labels = layout.clipped_labels(entries, options.max_name_length, metrics)
      label_entries, label_width = entries, options.max_name_length
    end
    return panel.build(snapshot, options, last_active, serial, metrics, labels)
  end

  ---@return nil
  local function update()
    local snapshot = adapter.snapshot(config)
    if lists.equal(previous_snapshot, snapshot) then
      return
    end
    local document = build(config, snapshot)
    adapter.apply(nil, document.visibility)
    publish(document)
    previous_snapshot = snapshot
  end

  ---@return nil
  local function schedule()
    if not cancel or queued then
      return
    end
    queued = true
    local ticket = generation
    adapter.schedule(function()
      if not cancel or ticket ~= generation then
        return
      end
      queued = false
      local ok, err = pcall(update)
      if not ok then
        adapter.notify(tostring(err))
      end
    end)
  end

  ---@return nil
  local function theme()
    if not config then
      return
    end
    local ok, err = pcall(function()
      invalidate()
      local styles = adapter.highlights(config.highlights)
      local snapshot = adapter.snapshot(config)
      local document = build(config, snapshot)
      adapter.apply(styles, document.visibility)
      publish(document)
      previous_snapshot = snapshot
    end)
    if not ok then
      adapter.notify(tostring(err))
    end
  end

  function public.render()
    return cached
  end

  function public.click(id, clicks, button, modifiers)
    if clicks ~= 1 or modifiers and modifiers:find("[^ ]") or button ~= "l" and button ~= "m" then
      return
    end
    local target, ticket = targets[id], generation
    if not target then
      return
    end
    adapter.schedule(function()
      if not cancel or ticket ~= generation or not adapter.tab_valid(target.tab) then
        return
      end
      if target.kind == "tab" then
        if button == "l" then
          adapter.focus_tab(target.tab)
        end
      else
        buffers.refresh()
        if not target.id or not adapter.buffer_valid(target.id) or not buffers.contains(target.id, target.tab) then
          return
        end
        if button == "m" then
          buffers.close({ tab = target.tab, buf = target.id })
        else
          local _, err = buffers.open(target.id, { tab = target.tab })
          if err then
            adapter.notify(err)
          end
        end
      end
      schedule()
    end)
  end

  function public.setup(opts)
    local candidate = config_rules.normalize(opts)
    local styles = adapter.highlights(candidate.highlights)
    buffers.refresh()
    invalidate()
    local snapshot = adapter.snapshot(candidate)
    local document = build(candidate, snapshot)
    local installed
    local ok, err = pcall(function()
      if not cancel then
        installed = adapter.install({
          changed = schedule,
          theme = theme,
          metrics = function()
            invalidate()
            schedule()
          end,
        })
      end
      adapter.apply(styles, document.visibility)
    end)
    if not ok then
      if installed then
        installed()
      end
      error(err, 0)
    end
    generation, queued = generation + 1, false
    config, cancel = candidate, cancel or installed
    publish(document)
    previous_snapshot = snapshot
  end

  function public.teardown()
    generation = generation + 1
    if not cancel then
      return false
    end
    cancel()
    cancel, config, queued = nil, config_rules.normalize(), false
    cached, targets, last_active = "", {}, {}
    invalidate()
    return true
  end

  return public
end

return M
