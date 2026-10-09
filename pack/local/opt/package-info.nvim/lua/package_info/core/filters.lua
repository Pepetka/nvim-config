local M = {}
---@param value string
---@param pattern string
---@return boolean
function M.matches(value, pattern)
  local escaped = pattern:gsub("([%^%$%(%)%%%.%[%]%+%-])", "%%%1"):gsub("%*", ".*"):gsub("%?", ".")
  return value:match("^" .. escaped .. "$") ~= nil
end
---@param path string
---@param projects string[]
---@return boolean
function M.excluded_project(path, projects)
  for _, project in ipairs(projects) do
    project = project:gsub("/+$", "")
    if path == project or path:sub(1, #project + 1) == project .. "/" then
      return true
    end
  end
  return false
end
---@param dependencies PackageInfoDependency[]
---@param config PackageInfoConfig
---@return PackageInfoDependency[]
function M.dependencies(dependencies, config)
  local sections, result = {}, {}
  for _, section in ipairs(config.sections) do
    sections[section] = true
  end
  for _, dep in ipairs(dependencies) do
    local excluded = false
    for _, pattern in ipairs(config.exclude.packages) do
      if M.matches(dep.name, pattern) or dep.target and M.matches(dep.target, pattern) then
        excluded = true
        break
      end
    end
    if sections[dep.section] and not excluded then
      result[#result + 1] = dep
    end
  end
  return result
end
return M
