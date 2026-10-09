local M = {}

---Extract plain ranges only; native trees, nodes and queries stay in this layer.
---@param buf integer
---@param lang? string
---@param include_injections? boolean
---@return StableFoldsRawRange[]?
function M.collect(buf, lang, include_injections)
  if not lang then
    return nil
  end
  local ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
  if not ok or not parser then
    return nil
  end
  parser:parse(include_injections ~= false)
  ---@type StableFoldsRawRange[]
  local ranges = {}
  local available = false
  ---@param tree TSTree
  ---@param language_tree vim.treesitter.LanguageTree
  local function collect_tree(tree, language_tree)
    local query = vim.treesitter.query.get(language_tree:lang(), "folds")
    if not query then
      return
    end
    available = true
    for _, match, metadata in query:iter_matches(tree:root(), buf, 0, -1) do
      for id, nodes in pairs(match) do
        if query.captures[id] == "fold" and #nodes > 0 then
          local first = vim.treesitter.get_range(nodes[1], buf, metadata[id])
          local last = vim.treesitter.get_range(nodes[#nodes], buf, metadata[id])
          ranges[#ranges + 1] = {
            start_row = first[1],
            start_col = first[2],
            end_row = last[4],
            end_col = last[5],
          }
        end
      end
    end
  end
  if include_injections == false then
    for _, tree in pairs(parser:trees()) do
      collect_tree(tree, parser)
    end
  else
    parser:for_each_tree(collect_tree)
  end
  return available and ranges or nil
end

return M
