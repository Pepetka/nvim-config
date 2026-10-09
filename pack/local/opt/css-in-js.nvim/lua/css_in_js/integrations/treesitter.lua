local copy = require("css_in_js.core.config").copy
local regions = require("css_in_js.core.regions")
local M = {}

---@param node TSNode
---@return CssInJsRegion
local function bounds(node)
  local sr, sc, er, ec = node:range()
  return { start_row = sr, start_col = sc, end_row = er, end_col = ec, substitutions = {} }
end

---@param buf integer
---@param row integer
---@param col integer
---@return CssInJsPublicRegion?
function M.context(buf, row, col)
  local parser = vim.treesitter.get_parser(buf)
  if not parser then
    return nil
  end
  parser:parse(true)
  local tree, styled = parser:trees()[1], parser:children().styled
  if not tree or not styled then
    return nil
  end
  local node = tree:root():named_descendant_for_range(row, col, row, col)
  while node do
    if node:type() == "template_substitution" then
      return nil
    end
    if node:type() == "template_string" then
      local sr, sc = node:range()
      for _, included in pairs(styled:included_regions()) do
        for _, range in ipairs(included) do
          if range[1] == sr and range[2] == sc + 1 then
            local region = {
              node = node,
              start_row = sr,
              start_col = sc + 1,
              end_row = range[4],
              end_col = range[5],
              substitutions = {},
            }
            for child in node:iter_children() do
              if child:type() == "template_substitution" then
                region.substitutions[#region.substitutions + 1] = bounds(child)
              end
            end
            if regions.active(region, row, col) then
              return region
            end
          end
        end
      end
      return nil
    end
    node = node:parent()
  end
end

---@param region CssInJsRegion
---@return CssInJsRegion
function M.plain(region)
  return {
    start_row = region.start_row,
    start_col = region.start_col,
    end_row = region.end_row,
    end_col = region.end_col,
    substitutions = copy(region.substitutions),
  }
end

---@type CssInJsParserInfo[]
local owners = {}
---@type CssInJsParserInfo?
local baseline
---@type CssInJsParserInfo?
local applied

---@return nil
local function apply_override()
  local parser = require("nvim-treesitter.parsers").styled
  local newest = owners[#owners]
  if newest then
    parser.install_info = copy(newest)
    applied = copy(newest)
  end
end

local owner_sequence = 0

---@param group_name? string
---@return CssInJsParserOverride
function M.override(group_name)
  owner_sequence = owner_sequence + 1
  local owner_group = (group_name or "CssInJsParser") .. owner_sequence
  ---@type CssInJsParserInfo?
  local owned
  ---@type integer?
  local group
  local integration = {}
  function integration.teardown()
    if group then
      vim.api.nvim_del_augroup_by_id(group)
      group = nil
    end
    if not owned then
      return
    end
    for index, owner in ipairs(owners) do
      if owner == owned then
        table.remove(owners, index)
        break
      end
    end
    owned = nil
    local parser = require("nvim-treesitter.parsers").styled
    if vim.deep_equal(parser.install_info, applied) then
      if #owners > 0 then
        apply_override()
      else
        parser.install_info = copy(baseline)
      end
    end
    if #owners == 0 then
      baseline, applied = nil, nil
    end
  end
  ---@param info CssInJsParserInfo
  function integration.setup(info)
    integration.teardown()
    local parser = require("nvim-treesitter.parsers").styled
    if #owners == 0 or not vim.deep_equal(parser.install_info, applied) then
      baseline = copy(parser.install_info)
    end
    owned = copy(info)
    owners[#owners + 1] = owned
    local ok, err = pcall(function()
      apply_override()
      group = vim.api.nvim_create_augroup(owner_group, { clear = true })
      vim.api.nvim_create_autocmd("User", { group = group, pattern = "TSUpdate", callback = apply_override })
    end)
    if not ok then
      integration.teardown()
      error(err, 0)
    end
  end
  return integration
end

return M
