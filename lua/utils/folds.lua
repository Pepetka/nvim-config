local M = {}
local api = vim.api
local cache = {}
local namespace = api.nvim_create_namespace("StableFoldStarts")
local tracked = {}

-- Native Tree-sitter folding shifts cached levels before an asynchronous parse.
-- An edit at a closed fold boundary can therefore temporarily fold unrelated text.
-- Compute one complete, synchronous snapshot per changedtick instead.
local function compute(buf, parser, minlines, nestmax)
  parser:parse(true)

  local starts, stops, seen = {}, {}, {}
  parser:for_each_tree(function(tree, language_tree)
    local query = vim.treesitter.query.get(language_tree:lang(), "folds")
    if not query then
      return
    end

    for _, match, metadata in query:iter_matches(tree:root(), buf, 0, -1) do
      for id, nodes in pairs(match) do
        if query.captures[id] == "fold" then
          local first = vim.treesitter.get_range(nodes[1], buf, metadata[id])
          local last = vim.treesitter.get_range(nodes[#nodes], buf, metadata[id])
          local start, stop = first[1] + 1, last[4] + 1
          if last[5] == 0 then
            stop = stop - 1
          end

          local key = start .. ":" .. stop
          if stop - start + 1 > minlines and not seen[key] then
            seen[key] = true
            starts[start] = (starts[start] or 0) + 1
            stops[stop] = (stops[stop] or 0) + 1
          end
        end
      end
    end
  end)

  local levels, level, previous_stop = {}, 0, 0
  for line = 1, api.nvim_buf_line_count(buf) do
    local start, stop = starts[line] or 0, stops[line] or 0
    level = level - previous_stop + start
    local prefix = ""
    if start > 0 then
      prefix = ">"
      -- Adjacent captures can end and start on the same line.
      if stop > 0 then
        level = level - stop
        stop = 0
      end
    end
    if level > nestmax then
      prefix = ""
    end
    levels[line] = prefix .. math.min(level, nestmax)
    previous_stop = stop
  end
  return levels
end

-- Identify folds by a moving header mark, rather than their current line number.
-- Neovim may inherit a neighbour's closed state when a new fold first appears.
local function track_new_folds(buf, levels, lang)
  local previous = tracked[buf]
  local old, headers = {}, {}
  if previous and previous.lang == lang then
    for _, mark in ipairs(previous.marks) do
      local position = api.nvim_buf_get_extmark_by_id(buf, namespace, mark.id, {})
      if #position > 0 then
        old[position[1] + 1] = mark
        if headers[mark.header] ~= nil then
          headers[mark.header] = false
        else
          headers[mark.header] = mark
        end
      end
    end
  end

  local marks = {}
  for line, level in ipairs(levels) do
    if level:sub(1, 1) == ">" then
      local header = api.nvim_buf_get_lines(buf, line - 1, line, false)[1]
      local mark = old[line]
      if not mark or mark.header ~= header then
        -- A formatter or set_lines edit can replace the header itself, moving
        -- its mark past the replacement. Recover an unchanged unique header.
        mark = headers[header] or nil
      end
      if mark then
        for old_line, candidate in pairs(old) do
          if candidate == mark then
            old[old_line] = nil
          end
        end
        api.nvim_buf_set_extmark(buf, namespace, line - 1, 0, { id = mark.id, right_gravity = true })
      else
        mark = {
          id = api.nvim_buf_set_extmark(buf, namespace, line - 1, 0, { right_gravity = true }),
          new = previous ~= nil and previous.lang == lang,
          header = header,
        }
      end
      headers[header] = nil
      marks[#marks + 1] = mark
    end
  end
  for _, mark in pairs(old) do
    api.nvim_buf_del_extmark(buf, namespace, mark.id)
  end
  tracked[buf] = { lang = lang, marks = marks }
end

---@param line? integer
---@return string
function M.expr(line)
  local buf = api.nvim_get_current_buf()
  if vim.bo[buf].buftype ~= "" or vim.b[buf].bigfile then
    return "0"
  end

  local tick = api.nvim_buf_get_changedtick(buf)
  local minlines, nestmax = vim.wo.foldminlines, vim.wo.foldnestmax
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  local entry = cache[buf]
  if
    not entry
    or entry.tick ~= tick
    or entry.minlines ~= minlines
    or entry.nestmax ~= nestmax
    or entry.lang ~= lang
  then
    local ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
    entry = {
      tick = tick,
      minlines = minlines,
      nestmax = nestmax,
      lang = lang,
      levels = ok and parser and compute(buf, parser, minlines, nestmax) or {},
    }
    cache[buf] = entry
    track_new_folds(buf, entry.levels, lang)
  end
  return entry.levels[line or vim.v.lnum] or "0"
end

local group = api.nvim_create_augroup("SynchronousFolds", { clear = true })

api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufWritePost" }, {
  group = group,
  desc = "Refresh complete fold boundaries after editing",
  callback = function(args)
    for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
      if vim.wo[win].foldmethod == "expr" and vim.wo[win].foldexpr == "v:lua.require'utils.folds'.expr()" then
        -- Native incremental folding can stop at an unchanged level even when
        -- the rest of a syntax node moved. Reassigning the method refreshes all
        -- lines while retaining manually opened/closed folds (unlike zx/zX).
        api.nvim_win_call(win, function()
          vim.wo.foldmethod = "expr"
          for _, mark in ipairs((tracked[args.buf] or {}).marks or {}) do
            if mark.new then
              local position = api.nvim_buf_get_extmark_by_id(args.buf, namespace, mark.id, {})
              local line = position[1] and position[1] + 1
              if line and vim.fn.foldclosed(line) == line then
                vim.cmd(line .. "foldopen!")
              end
            end
          end
        end)
      end
    end
    for _, mark in ipairs((tracked[args.buf] or {}).marks or {}) do
      mark.new = false
    end
  end,
})

api.nvim_create_autocmd({ "BufUnload", "FileType" }, {
  group = group,
  callback = function(args)
    cache[args.buf] = nil
    tracked[args.buf] = nil
    api.nvim_buf_clear_namespace(args.buf, namespace, 0, -1)
  end,
})

return M
