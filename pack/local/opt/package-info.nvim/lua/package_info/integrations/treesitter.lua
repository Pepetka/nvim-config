local manifest = require("package_info.core.manifest")
local M = {}
---@param buf integer
---@return PackageInfoManifest?, string?
function M.parse(buf)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local ok, value = pcall(vim.json.decode, text)
  if not ok or type(value) ~= "table" then
    return nil
  end
  local success, parser = pcall(vim.treesitter.get_parser, buf, "json")
  if not success or not parser then
    return nil, "JSON Tree-sitter parser is unavailable"
  end
  local tree = parser:parse()[1]
  if not tree then
    return nil
  end
  local root = tree:root()
  local document = root:named_child(0)
  if not document or document:type() ~= "object" or root:has_error() then
    return nil
  end
  ---@type PackageInfoManifestFact[]
  local facts = {}
  ---@param node TSNode
  ---@param section? string
  ---@param top? boolean
  local function walk(node, section, top)
    for child in node:iter_children() do
      if child:type() == "pair" then
        local key_node, child_value = child:field("key")[1], child:field("value")[1]
        local key = vim.json.decode(vim.treesitter.get_node_text(key_node, buf))
        facts[#facts + 1] = {
          object = node:id(),
          key = key,
          row = child:start(),
          section = section,
          top = top,
          kind = child_value:type(),
        }
        walk(child_value, top and manifest.sections[key] and key or nil)
      else
        walk(child)
      end
    end
  end
  walk(document, nil, true)
  local lines = manifest.validate(facts)
  return lines and { text = text, lines = lines } or nil
end
return M
