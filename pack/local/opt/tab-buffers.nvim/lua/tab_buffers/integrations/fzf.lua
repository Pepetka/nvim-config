local api = vim.api
local buffers = require("tab_buffers")
local M = {}

---Open a tab-local buffer picker. Resume rebuilds the current tab's membership list.
---@param opts? table Visual fzf-lua options.
function M.buffers(opts)
  assert(opts == nil or type(opts) == "table", "opts must be a table")
  buffers.refresh()
  local fzf = require("fzf-lua")
  local session = {}
  local configured = vim.tbl_deep_extend("force", {
    prompt = "Buffers❯ ",
    file_icons = true,
    color_icons = true,
    previewer = "builtin",
  }, vim.deepcopy(opts or {}))
  configured.no_hide = true
  configured.no_resume = false
  configured.fzf_opts = vim.tbl_extend("force", configured.fzf_opts or {}, {
    ["--multi"] = true,
    ["--tiebreak"] = "index",
    ["--header-lines"] = 0,
  })

  local function selected_ids(selected)
    if not session.tab or not api.nvim_tabpage_is_valid(session.tab) then
      return {}
    end
    buffers.refresh()
    local ids = {}
    for _, entry in ipairs(selected) do
      local buf = tonumber(entry:match("^%[(%d+)%]"))
      if buf and buffers.contains(buf, session.tab) then
        ids[#ids + 1] = buf
      end
    end
    return ids
  end

  local function open(split)
    return function(selected)
      local buf = selected_ids(selected)[1]
      if not buf then
        return
      end
      local _, err = buffers.open(buf, { tab = session.tab, split = split })
      if err then
        vim.notify(err, vim.log.levels.WARN, { title = "tab-buffers" })
      end
    end
  end
  configured.actions = {
    ["default"] = open(),
    ["ctrl-s"] = open("horizontal"),
    ["ctrl-v"] = open("vertical"),
    ["ctrl-x"] = {
      fn = function(selected)
        local ids = selected_ids(selected)
        if #ids > 0 then
          buffers.close_many(ids, { tab = session.tab })
        end
      end,
      reload = true,
    },
  }

  local contents = function(cb)
    -- fzf-lua may request contents from an RPC/fast callback.
    local function generate()
      buffers.refresh()
      session.tab = api.nvim_get_current_tabpage()
      local tabwin = api.nvim_tabpage_get_win(session.tab)
      local source = fzf.utils.CTX()
      local current = source.tabh == session.tab and source.bufnr or api.nvim_win_get_buf(tabwin)
      local cwd = vim.fn.getcwd()
      for _, buf in ipairs(buffers.buffers(session.tab)) do
        local name = api.nvim_buf_get_name(buf)
        local display = name == "" and "[No Name]"
          or fzf.make_entry.file(name:gsub("\n", "␊"):gsub("\r", "␍"), {
            cwd = cwd,
            file_icons = configured.file_icons,
            color_icons = configured.color_icons,
          })
        local flags = (buf == current and "%" or " ") .. (vim.bo[buf].modified and "+" or " ")
        cb(string.format("[%d]%s%s%s%s", buf, fzf.utils.nbsp, flags, fzf.utils.nbsp, display))
      end
      cb(nil)
    end
    if vim.in_fast_event() then
      vim.schedule(generate)
    else
      generate()
    end
  end
  return fzf.fzf_exec(contents, configured)
end

return M
