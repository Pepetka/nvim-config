local api = vim.api
local buffers = require("tab_buffers")
local M = {}
local positions, group, original, previous_visibility, visibility
local generation = 0
local disabled_commands = {
  "BufferLineMoveNext",
  "BufferLineMovePrev",
  "BufferLineSortByExtension",
  "BufferLineSortByDirectory",
  "BufferLineSortByRelativeDirectory",
  "BufferLineSortByTabs",
  "BufferLineTogglePin",
}

local function update()
  positions = {}
  local members = buffers.buffers()
  for index, buf in ipairs(members) do
    positions[buf] = index
  end
  visibility = (#members > 1 or #buffers.tabs() > 1) and 2 or 0
  vim.o.showtabline = visibility
  vim.cmd.redrawtabline()
end

local function handler(operation)
  return function(buf)
    local tab, ticket = api.nvim_get_current_tabpage(), generation
    vim.schedule(function()
      if not group or ticket ~= generation or not api.nvim_tabpage_is_valid(tab) then
        return
      end
      buffers.refresh()
      if not buffers.contains(buf, tab) then
        return
      end
      if operation == "open" then
        local _, err = buffers.open(buf, { tab = tab })
        if err then
          vim.notify(err, vim.log.levels.WARN, { title = "tab-buffers" })
        end
      else
        buffers.close({ tab = tab, buf = buf })
      end
    end)
  end
end

---Configure bufferline using the ownership model; visual settings remain caller-owned.
---@param config? table
function M.setup(config)
  assert(config == nil or type(config) == "table", "config must be a table")
  local bufferline = require("bufferline")
  buffers.refresh()
  M.teardown()
  original = vim.deepcopy(config or {})
  previous_visibility = vim.o.showtabline
  local configured = vim.deepcopy(original)
  configured.options = vim.tbl_extend("force", configured.options or {}, {
    mode = "buffers",
    persist_buffer_sort = false,
    auto_toggle_bufferline = false,
    custom_filter = function(buf)
      return positions and positions[buf] ~= nil or false
    end,
    sort_by = function(a, b)
      local left, right = positions[a.id] or math.huge, positions[b.id] or math.huge
      return left == right and a.id < b.id or left < right
    end,
    left_mouse_command = handler("open"),
    close_command = handler("close"),
    right_mouse_command = handler("close"),
  })
  -- Global groups (including pins) would take precedence over the model's order.
  configured.options.groups = { items = {} }
  positions = {}
  bufferline.setup(configured)
  for _, command in ipairs(disabled_commands) do
    pcall(api.nvim_del_user_command, command)
  end
  group = api.nvim_create_augroup("TabBuffersBufferline", { clear = true })
  api.nvim_create_autocmd({ "TabEnter", "TabClosed" }, {
    group = group,
    callback = function(args)
      if args.event == "TabEnter" then
        update()
      else
        local ticket = generation
        vim.schedule(function()
          if group and ticket == generation then
            update()
          end
        end)
      end
    end,
  })
  api.nvim_create_autocmd("User", { group = group, pattern = "TabBuffersChanged", callback = update })
  update()
end

function M.teardown()
  generation = generation + 1
  if not group then
    return false
  end
  api.nvim_del_augroup_by_id(group)
  group = nil
  require("bufferline").setup(original)
  if vim.o.showtabline == visibility then
    vim.o.showtabline = previous_visibility
  end
  positions, original = nil, nil
  return true
end

return M
