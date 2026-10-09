local M = {}
M.sections = { dependencies = true, devDependencies = true, optionalDependencies = true, peerDependencies = true }
---@param facts PackageInfoManifestFact[]
---@return table<string, integer>?
function M.validate(facts)
  local seen, lines = {}, {}
  for _, fact in ipairs(facts) do
    seen[fact.object] = seen[fact.object] or {}
    if seen[fact.object][fact.key] then
      return nil
    end
    seen[fact.object][fact.key] = true
    if fact.section then
      lines[fact.section .. ":" .. fact.key] = fact.row
    end
    if fact.top and M.sections[fact.key] and fact.kind ~= "object" then
      return nil
    end
  end
  return lines
end
return M
