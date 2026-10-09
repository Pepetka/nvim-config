---@type PackageInfoOptions
local options = {
  -- Optional overrides for projects with conflicting lockfiles:
  -- managers = { ["/absolute/path/to/project"] = "yarn@4" },
  -- auto_refresh = { on_enter = true, on_save = true }, -- false: manual checks only
  -- sections = { "dependencies", "devDependencies", "optionalDependencies", "peerDependencies" },
  -- exclude = { packages = { "@private/*" }, projects = { "/absolute/path/to/project" } },
  -- timeouts = { registry = 15000, manager = 5000, helper = 5000, bootstrap = 120000 }, -- milliseconds
  -- concurrency = { http = 32, http_per_project = 16, cli = 4, cli_per_project = 2 },
  -- cache = { ttl = 900000, retry = 30000, disk = true },
  -- display = { enabled = true, virt_text_pos = "eol", float = { border = "rounded", max_width = 80 } },
}

require("package_info").setup(options)
