local groups = {
  "shared",
  "core",
  "workflow",
  "ui",
  "extras",
}

for _, group in ipairs(groups) do
  require("plugins.groups." .. group)
end
