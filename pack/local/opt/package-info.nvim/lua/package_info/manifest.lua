local M = {}
local sections = { dependencies = true, devDependencies = true, optionalDependencies = true, peerDependencies = true }

-- Walk direct object pairs, so nested overrides and repeated names in other sections cannot steal a line.
function M.parse(buf)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local ok, manifest = pcall(vim.json.decode, text)
  if not ok or type(manifest) ~= "table" then
    return nil
  end
  local success, parser = pcall(vim.treesitter.get_parser, buf, "json")
  if not success then
    return nil, "JSON Tree-sitter parser is unavailable"
  end
  local root = parser:parse()[1]:root()
  local document = root:named_child(0)
  if not document or document:type() ~= "object" or root:has_error() then
    return nil
  end
  local lines = {}
  local seen = {}
  for pair in document:iter_children() do
    if pair:type() == "pair" then
      local key = pair:field("key")[1]
      local value = pair:field("value")[1]
      local section = vim.json.decode(vim.treesitter.get_node_text(key, buf))
      if seen[section] then
        return nil
      end
      seen[section] = true
      if sections[section] and value:type() == "object" then
        for dependency in value:iter_children() do
          if dependency:type() == "pair" then
            local name = vim.json.decode(vim.treesitter.get_node_text(dependency:field("key")[1], buf))
            local id = section .. ":" .. name
            if lines[id] then
              return nil
            end
            local row = dependency:start()
            lines[id] = row
          end
        end
      elseif sections[section] then
        return nil
      end
    end
  end
  return { text = text, lines = lines }
end

return M
